#include "plugin/plugin_types.h"

#include <pthread.h>

#include <atomic>
#include <cstdint>

namespace onebeat::plugin {
namespace {

// Darwin allocates a thread's TLV block lazily on its first `thread_local`
// access. That makes even a constant-initialised TLS byte unsafe in the first
// CoreAudio callback (RTSan correctly intercepts the allocation). A process has
// one render thread, so identify it with pthread_self() instead. Darwin creates
// the pthread object before invoking us; reading its identity does not allocate.
std::atomic<uintptr_t> AudioThread{0};
std::atomic<uintptr_t> MainThread{0};

uintptr_t currentThread() noexcept OB_NONBLOCKING {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"
  const auto thread = reinterpret_cast<uintptr_t>(::pthread_self());
#pragma clang diagnostic pop
  return thread;
}

}  // namespace

// See the note in current() for why the effect check is suppressed on every TLS
// access in this file.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"

void ThreadCheck::enterMainThread() noexcept {
  MainThread.store(currentThread(), std::memory_order_release);
}

void ThreadCheck::enterAudioThread() noexcept OB_NONBLOCKING {
  AudioThread.store(currentThread(), std::memory_order_release);
}

void ThreadCheck::leaveAudioThread() noexcept OB_NONBLOCKING {
  AudioThread.store(0, std::memory_order_release);
}

#pragma clang diagnostic pop

ThreadRole ThreadCheck::current() noexcept OB_NONBLOCKING {
  const uintptr_t thread = currentThread();
  if (AudioThread.load(std::memory_order_acquire) == thread) return ThreadRole::Audio;
  if (MainThread.load(std::memory_order_acquire) == thread) return ThreadRole::Main;
  return ThreadRole::Unknown;
}

bool ThreadCheck::onMainThread() noexcept OB_NONBLOCKING {
  return current() == ThreadRole::Main;
}

bool ThreadCheck::onAudioThread() noexcept OB_NONBLOCKING {
  return current() == ThreadRole::Audio;
}

}  // namespace onebeat::plugin
