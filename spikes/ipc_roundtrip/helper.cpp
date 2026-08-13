// The stand-in for a sandboxed plugin host process (OB-2-05). It maps the
// shared segment, waits to be told a block is ready, applies a trivial gain,
// and signals back. Nothing here is meant to be a plugin; the whole point is
// that the DSP is negligible so the number the host measures is transport cost.
//
// Usage: ob204_helper <backend>
//   backend ∈ spin | wait_on_address | posix_sem | mach_sem

#include <fcntl.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>

#include "shared.h"

namespace {

using namespace ipc;

// Sends both semaphore send rights to the host over the port we were handed as
// our bootstrap port. Returns false if we were not spawned with one.
bool publishMachSemaphores(semaphore_t to_helper, semaphore_t to_host) {
  mach_port_t reply = MACH_PORT_NULL;
  if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &reply) != KERN_SUCCESS ||
      reply == MACH_PORT_NULL) {
    std::fprintf(stderr, "helper: no bootstrap port\n");
    return false;
  }

  PortMessage msg{};
  msg.header.msgh_bits =
      MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
  msg.header.msgh_size = sizeof(PortMessage);
  msg.header.msgh_remote_port = reply;
  msg.header.msgh_local_port = MACH_PORT_NULL;
  msg.header.msgh_id = 0x0B204;
  msg.body.msgh_descriptor_count = 2;
  msg.to_helper.name = to_helper;
  msg.to_helper.disposition = MACH_MSG_TYPE_COPY_SEND;
  msg.to_helper.type = MACH_MSG_PORT_DESCRIPTOR;
  msg.to_host.name = to_host;
  msg.to_host.disposition = MACH_MSG_TYPE_COPY_SEND;
  msg.to_host.type = MACH_MSG_PORT_DESCRIPTOR;

  const mach_msg_return_t mr =
      mach_msg(&msg.header, MACH_SEND_MSG, sizeof(PortMessage), 0,
               MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
  if (mr != MACH_MSG_SUCCESS) {
    std::fprintf(stderr, "helper: mach_msg send failed: 0x%x\n", mr);
    return false;
  }
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: ob204_helper <backend>\n");
    return 2;
  }
  Backend backend{};
  if (!parseBackend(argv[1], backend)) {
    std::fprintf(stderr, "helper: unknown backend %s\n", argv[1]);
    return 2;
  }

  const int fd = shm_open(ShmName, O_RDWR, 0600);
  if (fd < 0) {
    std::perror("helper: shm_open");
    return 1;
  }
  void* mapping = mmap(nullptr, sizeof(SharedBlock), PROT_READ | PROT_WRITE,
                       MAP_SHARED, fd, 0);
  close(fd);
  if (mapping == MAP_FAILED) {
    std::perror("helper: mmap");
    return 1;
  }
  auto* sb = static_cast<SharedBlock*>(mapping);

  // Wiring the transport must happen before we tell the host we are ready,
  // otherwise the first block races the semaphore that carries it.
  sem_t* sem_to_helper = SEM_FAILED;
  sem_t* sem_to_host = SEM_FAILED;
  semaphore_t mach_to_helper = MACH_PORT_NULL;
  semaphore_t mach_to_host = MACH_PORT_NULL;

  if (backend == Backend::PosixSem) {
    sem_to_helper = sem_open(SemToHelperName, 0);
    sem_to_host = sem_open(SemToHostName, 0);
    if (sem_to_helper == SEM_FAILED || sem_to_host == SEM_FAILED) {
      std::perror("helper: sem_open");
      return 1;
    }
  } else if (backend == Backend::MachSem) {
    if (semaphore_create(mach_task_self(), &mach_to_helper, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS ||
        semaphore_create(mach_task_self(), &mach_to_host, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS) {
      std::fprintf(stderr, "helper: semaphore_create failed\n");
      return 1;
    }
    if (!publishMachSemaphores(mach_to_helper, mach_to_host)) return 1;
  }

  // The helper's worker is a real-time thread too: a sandboxed plugin that ran
  // at default priority would be descheduled by any busy UI and the measurement
  // would be of the scheduler, not of the transport.
  // OB204_NO_RT=1 leaves the helper at default priority. It exists to test one
  // specific hypothesis: that the spin backend collapses because a
  // time-constraint thread which never yields blows its computation budget and
  // is demoted by the scheduler. See FINDINGS.md.
  const uint32_t frames = sb->frames.load(std::memory_order_relaxed);
  const uint64_t period_nanos = (static_cast<uint64_t>(frames) * 1'000'000'000ULL) / 48'000ULL;
  const char* no_rt = std::getenv("OB204_NO_RT");
  if (no_rt == nullptr || no_rt[0] != '1') makeThreadRealtime(period_nanos);

  sb->ready.store(1, std::memory_order_release);

  uint32_t seen = 0;
  for (;;) {
    if (sb->quit.load(std::memory_order_acquire) != 0) break;

    uint32_t request = 0;
    switch (backend) {
      case Backend::Spin:
        while ((request = sb->request.load(std::memory_order_acquire)) == seen) {
          if (sb->quit.load(std::memory_order_relaxed) != 0) return 0;
          spinHint();
        }
        break;
      case Backend::WaitAddress: {
        // The wait is a *conditional* sleep: it blocks only while the word
        // still reads `seen`, so a wake that arrives between the load and the
        // call is not lost. Getting this wrong is how futex code hangs once an
        // hour instead of immediately.
        while (sb->request.load(std::memory_order_acquire) == seen) {
          os_sync_wait_on_address(&sb->request, seen, sizeof(uint32_t),
                                  OS_SYNC_WAIT_ON_ADDRESS_SHARED);
          if (sb->quit.load(std::memory_order_relaxed) != 0) return 0;
        }
        request = sb->request.load(std::memory_order_acquire);
        break;
      }
      case Backend::PosixSem:
        while (sem_wait(sem_to_helper) != 0) {
        }
        if (sb->quit.load(std::memory_order_acquire) != 0) return 0;
        request = sb->request.load(std::memory_order_acquire);
        break;
      case Backend::MachSem:
        while (semaphore_wait(mach_to_helper) != KERN_SUCCESS) {
        }
        if (sb->quit.load(std::memory_order_acquire) != 0) return 0;
        request = sb->request.load(std::memory_order_acquire);
        break;
    }
    seen = request;

    const uint32_t n = sb->frames.load(std::memory_order_relaxed) *
                       sb->channels.load(std::memory_order_relaxed);
    for (uint32_t i = 0; i < n; ++i) sb->out[i] = sb->in[i] * 0.5f;

    sb->response.store(seen, std::memory_order_release);
    switch (backend) {
      case Backend::Spin:
        break;
      case Backend::WaitAddress:
        os_sync_wake_by_address_any(&sb->response, sizeof(uint32_t),
                                    OS_SYNC_WAKE_BY_ADDRESS_SHARED);
        break;
      case Backend::PosixSem:
        sem_post(sem_to_host);
        break;
      case Backend::MachSem:
        semaphore_signal(mach_to_host);
        break;
    }
  }
  return 0;
}
