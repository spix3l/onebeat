// Real-time discipline primitives shared by every audio-thread code path.
// The rules that go with these are in docs/rt-rules.md and are enforced by
// RTSan in CI (OB-1-02) plus Clang's function effect analysis at compile time.
#pragma once

#include <cstdint>

// Every function reachable from the audio callback carries this. It expands to
// [[clang::nonblocking]], which makes the compiler prove (Function Effect
// Analysis, -Wfunction-effects) that the body performs no allocation, no lock,
// no exception, no virtual/indirect call to a non-nonblocking target.
// Grep for OB_NONBLOCKING to enumerate the real-time surface.
#if defined(__clang__) && defined(__has_cpp_attribute)
#if __has_cpp_attribute(clang::nonblocking)
#define OB_NONBLOCKING [[clang::nonblocking]]
#else
#define OB_NONBLOCKING
#endif
#else
#define OB_NONBLOCKING
#endif

// Marks a function that is *called from* the audio thread but is knowingly
// allowed to do more than a nonblocking function may (currently only the
// platform backend's outermost trampoline, which is not ours to constrain).
#define OB_RT_ENTRY

namespace onebeat::rt {

// Flush-to-zero / denormals-are-zero for the calling thread. Denormals turn a
// decaying tail into a 100x CPU spike and break bit-exact reproducibility, so
// the audio thread sets this once at the top of its first callback and the
// offline driver sets it too (OB-1-13 §4).
inline void enableFlushToZero() noexcept OB_NONBLOCKING {
#if defined(__aarch64__)
  uint64_t fpcr = 0;
  __asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr));
  fpcr |= (1ULL << 24);  // FZ
  __asm__ __volatile__("msr fpcr, %0" : : "r"(fpcr));
#elif defined(__x86_64__)
  // _MM_SET_FLUSH_ZERO_MODE / _MM_SET_DENORMALS_ZERO_MODE without the header.
  unsigned int csr = 0;
  __asm__ __volatile__("stmxcsr %0" : "=m"(csr));
  csr |= 0x8040u;  // FTZ | DAZ
  __asm__ __volatile__("ldmxcsr %0" : : "m"(csr));
#endif
}

// Monotonic nanoseconds. Used for snapshot timestamps (meter ballistics must be
// wall-clock based, never frame-count based) and render-time budgeting.
uint64_t monotonicNanos() noexcept OB_NONBLOCKING;

}  // namespace onebeat::rt
