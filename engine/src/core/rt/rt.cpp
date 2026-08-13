#include "core/rt/rt.h"

#include <mach/mach_time.h>

namespace onebeat::rt {
namespace {

// Namespace-scope const: initialised when the dylib loads, long before any
// audio thread exists, so the audio thread only ever reads it. A function-local
// static would be wrong here — its thread-safe initialisation guard is a lock.
struct Timebase {
  // noexcept: this runs during static initialisation, where an escaping
  // exception is uncatchable and terminates the process.
  Timebase() noexcept {
    mach_timebase_info_data_t info{};
    mach_timebase_info(&info);
    numerator = info.numer;
    denominator = info.denom == 0 ? 1 : info.denom;
  }
  uint32_t numerator = 1;
  uint32_t denominator = 1;
};

const Timebase GlobalTimebase;  // NOLINT(cert-err58-cpp)

}  // namespace

uint64_t monotonicNanos() noexcept OB_NONBLOCKING {
  // mach_absolute_time() is a commpage read: no syscall, no lock, no allocation.
  // Clang cannot see that through the libSystem declaration, so the effect check
  // is suppressed for this one call and RTSan verifies it at runtime instead.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"
  const uint64_t ticks = mach_absolute_time();
#pragma clang diagnostic pop
  return ticks * GlobalTimebase.numerator / GlobalTimebase.denominator;
}

}  // namespace onebeat::rt
