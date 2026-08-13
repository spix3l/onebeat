// The stand-in for OneBeat's audio callback. It paces itself at the block
// period CoreAudio would, hands each block to a helper process over shared
// memory, waits for the answer under a deadline, and records what that cost.
//
// What it is really measuring is the question OB-2-04 has to answer: can a
// sandboxed plugin be called *synchronously* inside the callback, or must
// OneBeat pipeline it and pay a block of latency (FR-ENG-04)?
//
// Usage: ob204_host [options]
//   --backend <spin|wait_on_address|posix_sem|mach_sem>
//   --frames N              block size (default 128)
//   --seconds N             run length (default 30)
//   --load N                N competing CPU-burner processes (default 0)
//   --kill-after N          SIGKILL the helper N seconds in (failure test)
//   --deadline-frac F       fraction of the block period the host will wait
//   --csv <path>            write every round-trip sample for offline analysis

#include <fcntl.h>
#include <mach/mach.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cerrno>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#include "shared.h"

extern char** environ;

namespace {

using namespace ipc;

struct Options {
  Backend backend = Backend::WaitAddress;
  uint32_t frames = 128;
  uint32_t sample_rate = 48'000;
  double seconds = 30.0;
  int load = 0;
  double kill_after = -1.0;
  double deadline_frac = 0.6;
  std::string csv;
};

// A reply that arrives after we gave up is not a reply, it is noise from the
// previous block. Two consecutive misses is the point at which we stop paying
// for the wait at all and declare the helper gone.
constexpr int MissesBeforeDead = 2;

std::string helperPath(const char* argv0) {
  std::string path(argv0);
  const auto slash = path.find_last_of('/');
  path = (slash == std::string::npos) ? std::string() : path.substr(0, slash + 1);
  return path + "ob204_helper";
}

pid_t spawnBurner() {
  pid_t pid = 0;
  char* const argv[] = {const_cast<char*>("/bin/sh"), const_cast<char*>("-c"),
                        const_cast<char*>("while :; do :; done"), nullptr};
  if (posix_spawn(&pid, "/bin/sh", nullptr, nullptr, argv, environ) != 0) return -1;
  return pid;
}

double percentile(const std::vector<uint32_t>& sorted, double p) {
  if (sorted.empty()) return 0.0;
  const auto idx = static_cast<std::size_t>(p * static_cast<double>(sorted.size() - 1));
  return static_cast<double>(sorted[idx]);
}

}  // namespace

int main(int argc, char** argv) {
  Options opt;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    auto next = [&]() -> const char* { return (i + 1 < argc) ? argv[++i] : "0"; };
    if (a == "--backend") {
      if (!parseBackend(next(), opt.backend)) { std::fprintf(stderr, "bad backend\n"); return 2; }
    } else if (a == "--frames") {
      opt.frames = static_cast<uint32_t>(std::atoi(next()));
    } else if (a == "--seconds") {
      opt.seconds = std::atof(next());
    } else if (a == "--load") {
      opt.load = std::atoi(next());
    } else if (a == "--kill-after") {
      opt.kill_after = std::atof(next());
    } else if (a == "--deadline-frac") {
      opt.deadline_frac = std::atof(next());
    } else if (a == "--csv") {
      opt.csv = next();
    } else {
      std::fprintf(stderr, "unknown option %s\n", a.c_str());
      return 2;
    }
  }
  if (opt.frames == 0 || opt.frames > MaxFrames) {
    std::fprintf(stderr, "frames must be 1..%u\n", MaxFrames);
    return 2;
  }

  const uint64_t period_nanos =
      (static_cast<uint64_t>(opt.frames) * 1'000'000'000ULL) / opt.sample_rate;
  const uint64_t period_ticks = nanosToTicks(period_nanos);
  const uint64_t deadline_nanos =
      static_cast<uint64_t>(static_cast<double>(period_nanos) * opt.deadline_frac);

  // ---- shared segment -----------------------------------------------------
  shm_unlink(ShmName);
  const int fd = shm_open(ShmName, O_CREAT | O_EXCL | O_RDWR, 0600);
  if (fd < 0) { std::perror("host: shm_open"); return 1; }
  if (ftruncate(fd, sizeof(SharedBlock)) != 0) { std::perror("host: ftruncate"); return 1; }
  void* mapping = mmap(nullptr, sizeof(SharedBlock), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  if (mapping == MAP_FAILED) { std::perror("host: mmap"); return 1; }
  auto* sb = new (mapping) SharedBlock{};
  sb->backend.store(static_cast<uint32_t>(opt.backend));
  sb->frames.store(opt.frames);
  sb->channels.store(2);
  sb->quit.store(0);

  // Faulting a page in for the first time is a syscall, and doing it from the
  // callback would show up as a first-block outlier that has nothing to do with
  // IPC. Touch and wire the whole segment before the clock starts.
  std::memset(sb->in, 0, sizeof(sb->in));
  std::memset(sb->out, 0, sizeof(sb->out));
  if (mlock(mapping, sizeof(SharedBlock)) != 0) {
    std::fprintf(stderr, "host: mlock failed (continuing unwired): %s\n", std::strerror(errno));
  }

  // ---- transport ----------------------------------------------------------
  sem_t* sem_to_helper = SEM_FAILED;
  sem_t* sem_to_host = SEM_FAILED;
  semaphore_t mach_to_helper = MACH_PORT_NULL;
  semaphore_t mach_to_host = MACH_PORT_NULL;
  mach_port_t bootstrap_recv = MACH_PORT_NULL;

  if (opt.backend == Backend::PosixSem) {
    sem_unlink(SemToHelperName);
    sem_unlink(SemToHostName);
    sem_to_helper = sem_open(SemToHelperName, O_CREAT | O_EXCL, 0600, 0);
    sem_to_host = sem_open(SemToHostName, O_CREAT | O_EXCL, 0600, 0);
    if (sem_to_helper == SEM_FAILED || sem_to_host == SEM_FAILED) {
      std::perror("host: sem_open");
      return 1;
    }
  } else if (opt.backend == Backend::MachSem) {
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &bootstrap_recv) != KERN_SUCCESS ||
        mach_port_insert_right(mach_task_self(), bootstrap_recv, bootstrap_recv,
                               MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
      std::fprintf(stderr, "host: could not make bootstrap port\n");
      return 1;
    }
  }

  // ---- helper -------------------------------------------------------------
  const std::string helper = helperPath(argv[0]);
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  if (opt.backend == Backend::MachSem) {
    // The only channel a freshly exec'd process has to a port we own.
    posix_spawnattr_setspecialport_np(&attr, bootstrap_recv, TASK_BOOTSTRAP_PORT);
  }
  char* const helper_argv[] = {const_cast<char*>(helper.c_str()),
                               const_cast<char*>(backendName(opt.backend)), nullptr};
  pid_t helper_pid = 0;
  if (posix_spawn(&helper_pid, helper.c_str(), nullptr, &attr, helper_argv, environ) != 0) {
    std::perror("host: posix_spawn helper");
    return 1;
  }
  posix_spawnattr_destroy(&attr);

  if (opt.backend == Backend::MachSem) {
    PortMessageRecv rx{};
    const mach_msg_return_t mr =
        mach_msg(&rx.msg.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                 sizeof(rx), bootstrap_recv, 5000, MACH_PORT_NULL);
    if (mr != MACH_MSG_SUCCESS) {
      std::fprintf(stderr, "host: never received helper's semaphores: 0x%x\n", mr);
      return 1;
    }
    mach_to_helper = rx.msg.to_helper.name;
    mach_to_host = rx.msg.to_host.name;
  }

  // Wait for the helper to be ready before the clock starts. A real host does
  // this too: a plugin is not part of the graph until it has answered.
  {
    const uint64_t give_up = mach_absolute_time() + nanosToTicks(5'000'000'000ULL);
    while (sb->ready.load(std::memory_order_acquire) == 0) {
      if (mach_absolute_time() > give_up) {
        std::fprintf(stderr, "host: helper never became ready\n");
        return 1;
      }
      usleep(1000);
    }
  }

  std::vector<pid_t> burners;
  for (int i = 0; i < opt.load; ++i) {
    const pid_t p = spawnBurner();
    if (p > 0) burners.push_back(p);
  }

  // ---- the callback loop --------------------------------------------------
  if (!makeThreadRealtime(period_nanos)) {
    std::fprintf(stderr, "host: thread_policy_set failed; results are not RT\n");
  }

  const auto total_blocks =
      static_cast<uint64_t>(opt.seconds * static_cast<double>(opt.sample_rate) / opt.frames);
  std::vector<uint32_t> round_trip;
  round_trip.reserve(total_blocks);
  std::vector<uint32_t> callback_time;
  callback_time.reserve(total_blocks);

  uint64_t misses = 0;
  uint64_t consecutive_misses = 0;
  uint64_t silent_blocks = 0;
  uint64_t overruns = 0;
  bool helper_dead = false;
  bool helper_killed = false;
  uint64_t death_detected_block = 0;
  uint64_t kill_time = 0;
  uint64_t death_time = 0;
  uint32_t worst_callback_after_death = 0;
  const uint32_t samples = opt.frames * 2;

  uint64_t next_wake = mach_absolute_time();
  const uint64_t start = next_wake;
  const uint64_t kill_at =
      opt.kill_after >= 0.0 ? start + nanosToTicks(static_cast<uint64_t>(opt.kill_after * 1e9)) : 0;

  for (uint64_t block = 0; block < total_blocks; ++block) {
    next_wake += period_ticks;
    const uint64_t block_start = mach_absolute_time();

    if (kill_at != 0 && !helper_killed && block_start >= kill_at) {
      kill(helper_pid, SIGKILL);
      helper_killed = true;
      kill_time = block_start;
    }

    for (uint32_t i = 0; i < samples; ++i) {
      sb->in[i] = static_cast<float>(i & 63) * (1.0f / 64.0f);
    }

    bool answered = false;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!helper_dead) {
      const uint32_t seq = static_cast<uint32_t>(block) + 1;
      t0 = mach_absolute_time();
      sb->request.store(seq, std::memory_order_release);
      switch (opt.backend) {
        case Backend::Spin: break;
        case Backend::WaitAddress:
          os_sync_wake_by_address_any(&sb->request, sizeof(uint32_t),
                                      OS_SYNC_WAKE_BY_ADDRESS_SHARED);
          break;
        case Backend::PosixSem: sem_post(sem_to_helper); break;
        case Backend::MachSem: semaphore_signal(mach_to_helper); break;
      }

      const uint64_t give_up = t0 + nanosToTicks(deadline_nanos);
      while (!answered) {
        if (sb->response.load(std::memory_order_acquire) == seq) { answered = true; break; }
        if (mach_absolute_time() >= give_up) break;

        switch (opt.backend) {
          case Backend::Spin:
            spinHint();
            break;
          case Backend::WaitAddress: {
            // Deadline form, so a dead helper costs us the deadline and not the
            // callback. An unbounded wait here is the bug that turns one
            // crashed plugin into a dead audio device.
            const uint64_t now = ticksToNanos(mach_absolute_time());
            const uint64_t end = ticksToNanos(give_up);
            if (now >= end) break;
            os_sync_wait_on_address_with_timeout(
                &sb->response, sb->response.load(std::memory_order_relaxed),
                sizeof(uint32_t), OS_SYNC_WAIT_ON_ADDRESS_SHARED,
                OS_CLOCK_MACH_ABSOLUTE_TIME, end - now);
            break;
          }
          case Backend::PosixSem:
            // macOS has no sem_timedwait. The only bounded option is to poll,
            // which is why this backend cannot be the answer — see FINDINGS.md.
            if (sem_trywait(sem_to_host) == 0) {
              answered = sb->response.load(std::memory_order_acquire) == seq;
            } else {
              spinHint();
            }
            break;
          case Backend::MachSem: {
            const uint64_t now = mach_absolute_time();
            if (now >= give_up) break;
            const uint64_t left = ticksToNanos(give_up - now);
            mach_timespec_t ts{static_cast<unsigned int>(left / 1'000'000'000ULL),
                               static_cast<clock_res_t>(left % 1'000'000'000ULL)};
            if (semaphore_timedwait(mach_to_host, ts) == KERN_SUCCESS) {
              answered = sb->response.load(std::memory_order_acquire) == seq;
            }
            break;
          }
        }
      }
      t1 = mach_absolute_time();
    }

    if (answered) {
      round_trip.push_back(static_cast<uint32_t>(ticksToNanos(t1 - t0)));
      consecutive_misses = 0;
    } else {
      // 0 marks "no round trip for this block", so the CSV stays aligned with
      // the block index and the percentiles below can skip it.
      round_trip.push_back(0);
      ++misses;
      ++consecutive_misses;
      // Silence for this plugin, on time, is always better than a late block.
      std::memset(sb->out, 0, sizeof(float) * samples);
      ++silent_blocks;
      if (!helper_dead && consecutive_misses >= MissesBeforeDead) {
        helper_dead = true;
        death_detected_block = block;
        death_time = mach_absolute_time();
      }
    }

    const uint64_t block_end = mach_absolute_time();
    const uint32_t spent = static_cast<uint32_t>(ticksToNanos(block_end - block_start));
    callback_time.push_back(spent);
    if (spent > period_nanos) ++overruns;
    if (helper_dead && spent > worst_callback_after_death) worst_callback_after_death = spent;

    mach_wait_until(next_wake);
  }

  sb->quit.store(1, std::memory_order_release);
  if (opt.backend == Backend::WaitAddress) {
    os_sync_wake_by_address_all(&sb->request, sizeof(uint32_t), OS_SYNC_WAKE_BY_ADDRESS_SHARED);
  } else if (opt.backend == Backend::PosixSem) {
    sem_post(sem_to_helper);
  } else if (opt.backend == Backend::MachSem) {
    semaphore_signal(mach_to_helper);
  }

  const uint64_t elapsed_ns = ticksToNanos(mach_absolute_time() - start);
  if (!helper_killed) kill(helper_pid, SIGTERM);
  waitpid(helper_pid, nullptr, 0);
  for (pid_t p : burners) { kill(p, SIGKILL); waitpid(p, nullptr, 0); }
  shm_unlink(ShmName);
  if (opt.backend == Backend::PosixSem) { sem_unlink(SemToHelperName); sem_unlink(SemToHostName); }

  if (!opt.csv.empty()) {
    if (FILE* f = std::fopen(opt.csv.c_str(), "w")) {
      std::fprintf(f, "block,round_trip_ns,callback_ns\n");
      for (std::size_t i = 0; i < callback_time.size(); ++i) {
        std::fprintf(f, "%zu,%u,%u\n", i, round_trip[i], callback_time[i]);
      }
      std::fclose(f);
    }
  }

  std::vector<uint32_t> sorted;
  sorted.reserve(round_trip.size());
  for (uint32_t v : round_trip) {
    if (v != 0) sorted.push_back(v);
  }
  std::sort(sorted.begin(), sorted.end());
  std::vector<uint32_t> cb_sorted = callback_time;
  std::sort(cb_sorted.begin(), cb_sorted.end());

  std::printf("backend=%s frames=%u period=%.3fms deadline=%.3fms load=%d blocks=%llu elapsed=%.1fs\n",
              backendName(opt.backend), opt.frames,
              static_cast<double>(period_nanos) / 1e6,
              static_cast<double>(deadline_nanos) / 1e6, opt.load,
              static_cast<unsigned long long>(total_blocks),
              static_cast<double>(elapsed_ns) / 1e9);
  std::printf("round-trip us: min=%.2f p50=%.2f p99=%.2f p99.9=%.2f max=%.2f  (n=%zu)\n",
              sorted.empty() ? 0.0 : sorted.front() / 1000.0,
              percentile(sorted, 0.50) / 1000.0, percentile(sorted, 0.99) / 1000.0,
              percentile(sorted, 0.999) / 1000.0,
              sorted.empty() ? 0.0 : sorted.back() / 1000.0, sorted.size());
  std::printf("callback  us: p50=%.2f p99.9=%.2f max=%.2f\n",
              percentile(cb_sorted, 0.50) / 1000.0, percentile(cb_sorted, 0.999) / 1000.0,
              cb_sorted.empty() ? 0.0 : cb_sorted.back() / 1000.0);
  std::printf("misses=%llu silent_blocks=%llu overruns=%llu helper_dead=%s",
              static_cast<unsigned long long>(misses),
              static_cast<unsigned long long>(silent_blocks),
              static_cast<unsigned long long>(overruns), helper_dead ? "yes" : "no");
  if (helper_dead) {
    std::printf(" detected_at_block=%llu", static_cast<unsigned long long>(death_detected_block));
    if (kill_time != 0 && death_time > kill_time) {
      std::printf(" detect_latency=%.2fms", static_cast<double>(ticksToNanos(death_time - kill_time)) / 1e6);
    }
    std::printf(" worst_callback_after_death=%.2fus",
                static_cast<double>(worst_callback_after_death) / 1000.0);
  }
  std::printf("\n");
  return overruns == 0 ? 0 : 3;
}
