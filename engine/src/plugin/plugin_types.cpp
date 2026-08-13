#include "plugin/plugin_types.h"

namespace onebeat::plugin {
namespace {

// Zero-initialised POD with constant initialisation: no guard variable, no
// __cxa_thread_atexit registration, no lazy construction. The audio thread only
// ever reads and writes a single byte in its own TLS block.
thread_local ThreadRole GlobalRole = ThreadRole::Unknown;

}  // namespace

// See the note in current() for why the effect check is suppressed on every TLS
// access in this file.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"

void ThreadCheck::enterMainThread() noexcept {
  GlobalRole = ThreadRole::Main;
}

void ThreadCheck::enterAudioThread() noexcept OB_NONBLOCKING {
  GlobalRole = ThreadRole::Audio;
}

void ThreadCheck::leaveAudioThread() noexcept OB_NONBLOCKING {
  GlobalRole = ThreadRole::Unknown;
}

#pragma clang diagnostic pop

ThreadRole ThreadCheck::current() noexcept OB_NONBLOCKING {
  // On Darwin a thread_local read goes through libSystem's `tlv_get_addr`
  // trampoline, which Clang cannot see into — so the effect check is suppressed
  // for this one access exactly as rt::monotonicNanos() does for the commpage
  // read. tlv_get_addr is a load plus a predictable branch for an already
  // initialised, constant-initialised slot; RTSan verifies it at runtime and
  // has never flagged it. The whole call disappears in release builds anyway,
  // where nothing but the assertions consults it.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"
  const ThreadRole role = GlobalRole;
#pragma clang diagnostic pop
  return role;
}

bool ThreadCheck::onMainThread() noexcept OB_NONBLOCKING {
  return current() == ThreadRole::Main;
}

bool ThreadCheck::onAudioThread() noexcept OB_NONBLOCKING {
  return current() == ThreadRole::Audio;
}

}  // namespace onebeat::plugin
