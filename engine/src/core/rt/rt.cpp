#include "core/rt/rt.h"

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <mach/mach_time.h>
#endif

namespace onebeat::rt {
namespace {

// Namespace-scope const: initialised when the dylib loads, long before any
// audio thread exists, so the audio thread only ever reads it. A function-local
// static would be wrong here — its thread-safe initialisation guard is a lock.
struct Timebase {
  // noexcept: this runs during static initialisation, where an escaping
  // exception is uncatchable and terminates the process.
  Timebase() noexcept {
#if defined(_WIN32)
    LARGE_INTEGER value{};
    QueryPerformanceFrequency(&value);
    frequency = value.QuadPart > 0 ? static_cast<uint64_t>(value.QuadPart) : 1;
#else
    mach_timebase_info_data_t info{};
    mach_timebase_info(&info);
    numerator = info.numer;
    denominator = info.denom == 0 ? 1 : info.denom;
#endif
  }
#if defined(_WIN32)
  uint64_t frequency = 1;
#else
  uint32_t numerator = 1;
  uint32_t denominator = 1;
#endif
};

const Timebase GlobalTimebase;  // NOLINT(cert-err58-cpp)

}  // namespace

uint64_t monotonicNanos() noexcept OB_NONBLOCKING {
  // mach_absolute_time() is a commpage read: no syscall, no lock, no allocation.
  // Clang cannot see that through the libSystem declaration, so the effect check
  // is suppressed for this one call and RTSan verifies it at runtime instead.
#if defined(_WIN32)
  LARGE_INTEGER counter{};
  QueryPerformanceCounter(&counter);
  const uint64_t ticks = static_cast<uint64_t>(counter.QuadPart);
  return ticks * 1'000'000'000ULL / GlobalTimebase.frequency;
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"
  const uint64_t ticks = mach_absolute_time();
#pragma clang diagnostic pop
  return ticks * GlobalTimebase.numerator / GlobalTimebase.denominator;
#endif
}

}  // namespace onebeat::rt
