// Shared vocabulary for the OB-2-04 IPC prototype: the shared-memory layout,
// the four signalling backends under evaluation, and the small amount of
// real-time plumbing (thread policy, timebase) both processes need.
//
// This is spike code, not engine code. It is deliberately standalone — it does
// not link against libonebeat_core — so that what it measures is the IPC
// mechanism and nothing else.
#pragma once

#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <os/os_sync_wait_on_address.h>
#include <pthread.h>
#include <semaphore.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace ipc {

// One cache line on Apple silicon is 128 bytes, and the whole point of the
// layout below is that the host's write and the helper's write never share one.
constexpr std::size_t CacheLine = 128;

constexpr uint32_t MaxFrames = 1024;
constexpr uint32_t MaxChannels = 2;

// The four candidates OB-2-04 asks us to evaluate.
enum class Backend : uint32_t {
  Spin = 0,          // busy-wait on the shared word; the latency floor
  WaitAddress = 1,   // os_sync_wait_on_address (Darwin's futex), macOS 14.4+
  PosixSem = 2,      // sem_open / sem_post / sem_wait
  MachSem = 3,       // semaphore_create + a send right passed at spawn
};

inline const char* backendName(Backend b) {
  switch (b) {
    case Backend::Spin: return "spin";
    case Backend::WaitAddress: return "wait_on_address";
    case Backend::PosixSem: return "posix_sem";
    case Backend::MachSem: return "mach_sem";
  }
  return "?";
}

inline bool parseBackend(const char* s, Backend& out) {
  if (std::strcmp(s, "spin") == 0) { out = Backend::Spin; return true; }
  if (std::strcmp(s, "wait_on_address") == 0) { out = Backend::WaitAddress; return true; }
  if (std::strcmp(s, "posix_sem") == 0) { out = Backend::PosixSem; return true; }
  if (std::strcmp(s, "mach_sem") == 0) { out = Backend::MachSem; return true; }
  return false;
}

// ---------------------------------------------------------------------------
// The shared segment
// ---------------------------------------------------------------------------
//
// `request` and `response` are sequence numbers, not flags. A flag cannot tell
// "the helper answered this block" from "the helper answered the previous one
// and I missed it", and that distinction is the whole of the failure handling:
// a late reply must be discarded, not consumed as if it were fresh.
struct SharedBlock {
  alignas(CacheLine) std::atomic<uint32_t> backend;
  std::atomic<uint32_t> frames;
  std::atomic<uint32_t> channels;
  std::atomic<uint32_t> quit;
  // The helper sets this once it has mapped the segment and opened its end of
  // the transport. Without it the host's first blocks race the helper's
  // startup, and a host that treats consecutive misses as death — as this one
  // does, and as the real one must — would declare it dead before it ever ran.
  std::atomic<uint32_t> ready;

  // 32-bit because os_sync_wait_on_address compares a 32-bit word; keeping the
  // counters the width of the wait primitive avoids a cast that would only be
  // correct on a little-endian machine.
  alignas(CacheLine) std::atomic<uint32_t> request;   // host writes, helper reads
  alignas(CacheLine) std::atomic<uint32_t> response;  // helper writes, host reads

  alignas(CacheLine) float in[MaxChannels * MaxFrames];
  alignas(CacheLine) float out[MaxChannels * MaxFrames];
};

constexpr const char* ShmName = "/onebeat.ob204.shm";
constexpr const char* SemToHelperName = "/onebeat.ob204.h2p";
constexpr const char* SemToHostName = "/onebeat.ob204.p2h";

// A hint to the core that we are in a spin loop, so it can let the other SMT
// thread run and drop the clock. Cheap on Apple silicon, and the difference
// between a spin backend that is merely wasteful and one that is hostile.
inline void spinHint() {
#if defined(__aarch64__)
  __asm__ __volatile__("yield");
#elif defined(__x86_64__)
  __asm__ __volatile__("pause");
#endif
}

// ---------------------------------------------------------------------------
// Timebase
// ---------------------------------------------------------------------------
inline mach_timebase_info_data_t& timebase() {
  static mach_timebase_info_data_t tb = [] {
    mach_timebase_info_data_t t{};
    mach_timebase_info(&t);
    return t;
  }();
  return tb;
}

inline uint64_t ticksToNanos(uint64_t ticks) {
  const auto& tb = timebase();
  return ticks * tb.numer / tb.denom;
}

inline uint64_t nanosToTicks(uint64_t nanos) {
  const auto& tb = timebase();
  return nanos * tb.denom / tb.numer;
}

// ---------------------------------------------------------------------------
// Real-time thread policy
// ---------------------------------------------------------------------------
//
// Both processes' audio threads ask for the same time-constraint policy
// CoreAudio gives its callback thread. Measuring an IPC round trip between two
// ordinary threads would flatter the numbers: the scheduler treats an RT thread
// very differently, and it is the RT case the ADR has to budget for.
inline bool makeThreadRealtime(uint64_t period_nanos) {
  const uint64_t period = nanosToTicks(period_nanos);
  thread_time_constraint_policy_data_t policy{};
  policy.period = static_cast<uint32_t>(period);
  policy.computation = static_cast<uint32_t>(period / 2);
  policy.constraint = static_cast<uint32_t>(period);
  policy.preemptible = 0;

  const kern_return_t kr = thread_policy_set(
      pthread_mach_thread_np(pthread_self()), THREAD_TIME_CONSTRAINT_POLICY,
      reinterpret_cast<thread_policy_t>(&policy),
      THREAD_TIME_CONSTRAINT_POLICY_COUNT);
  return kr == KERN_SUCCESS;
}

// ---------------------------------------------------------------------------
// Mach port transfer
// ---------------------------------------------------------------------------
//
// A Mach semaphore is a port, and ports are not inherited across fork or exec.
// The only way a spawned helper can share one is for somebody to *send* the
// right over an existing port — which is exactly the chicken-and-egg the
// bootstrap port exists to break. The host hands the helper a send right to a
// port it owns via posix_spawnattr_setspecialport_np(TASK_BOOTSTRAP_PORT), the
// helper creates both semaphores and mails both send rights back in one
// message. See FINDINGS.md for what this costs in a sandboxed helper.
struct PortMessage {
  mach_msg_header_t header;
  mach_msg_body_t body;
  mach_msg_port_descriptor_t to_helper;
  mach_msg_port_descriptor_t to_host;
};

struct PortMessageRecv {
  PortMessage msg;
  mach_msg_trailer_t trailer;
};

}  // namespace ipc
