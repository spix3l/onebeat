// Shared vocabulary for the format-agnostic plugin model (OB-2-01, D5).
//
// Everything in `plugin/` is modelled on **CLAP's semantics**, not on the
// intersection of CLAP/VST3/AU. VST3 and AU adapters (Stage 5) map *down* into
// these types and document what they cannot express; the model never shrinks to
// fit the weakest format. See docs/plugin-threading-contract.md for the thread
// rules and docs/clap-coverage.md for the concept-by-concept audit.
//
// Nothing here is part of the C ABI. These are internal C++ interfaces; the
// public extension surface is the WIT/WASM API in Stage 6, and the host↔helper
// wire format is ADR-003. Both are deliberately separate from this file so that
// this model can change without a compatibility event.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "core/rt/rt.h"

namespace onebeat::plugin {

// --------------------------------------------------------------------------
// Identity
// --------------------------------------------------------------------------

// Stable for the lifetime of an instance and across save/load. A plugin that
// renumbers its parameters between versions breaks every project that automates
// them, which is why these are IDs and never indices (CLAP makes the same
// distinction, and it is the single most common host-side bug in VST3 hosting).
using ParamId = uint32_t;
using PortId = uint32_t;

// Per-note identity for note expression and per-note modulation. -1 means "no
// specific note", which in a *matching* context means "any" (CLAP's wildcard).
using NoteId = int32_t;

inline constexpr ParamId InvalidParamId = 0xFFFFFFFFU;
inline constexpr PortId InvalidPortId = 0xFFFFFFFFU;
inline constexpr NoteId AnyNote = -1;

// Wildcards for the (port, channel, key, note_id) tuple that addresses notes and
// per-note parameters. A note-off with all four wildcarded is "all notes off" —
// the model has no separate panic event, exactly as CLAP has none.
inline constexpr int16_t AnyPort = -1;
inline constexpr int16_t AnyChannel = -1;
inline constexpr int16_t AnyKey = -1;

// --------------------------------------------------------------------------
// Fixed-capacity text
// --------------------------------------------------------------------------

// Names are inline fixed arrays rather than std::string so that every info
// struct is a trivially copyable POD: they cross into snapshots, caches and (in
// Stage 2) the helper-process IPC boundary without allocating or serialising.
// Truncation is silent and bounded, never a reallocation.
template <size_t Capacity>
struct FixedText {
  char value[Capacity] = {};

  FixedText() = default;
  explicit FixedText(const char* text) { assign(text); }

  void assign(const char* text) {
    if (text == nullptr) {
      value[0] = '\0';
      return;
    }
    const size_t length = std::strlen(text);
    const size_t copied = length < Capacity - 1 ? length : Capacity - 1;
    std::memcpy(value, text, copied);
    value[copied] = '\0';
  }

  const char* text() const noexcept { return value; }
  bool empty() const noexcept { return value[0] == '\0'; }
};

using PluginName = FixedText<128>;  // "Diva", "OneBeat Sampler"
using ModulePath = FixedText<128>;  // "/osc1/shape" — the parameter tree (CLAP module)

// --------------------------------------------------------------------------
// Thread checking
// --------------------------------------------------------------------------

// CLAP annotates every entry point `[main-thread]` or `[audio-thread]`, and
// almost every real-world hosting bug is a violation of one of those. We mirror
// the annotations in comments *and* assert them at runtime in debug builds, so
// a violation is a trap at the call site rather than a rare corruption.
//
// Release builds compile the checks away entirely: `ThreadRole` is only ever
// consulted inside `OB_ASSERT_*_THREAD`.
enum class ThreadRole : uint8_t { Unknown = 0, Main = 1, Audio = 2 };

class ThreadCheck {
 public:
  // Called once by whichever thread takes the role. The audio backend calls
  // `enterAudioThread()` at the top of its first callback; the engine calls
  // `enterMainThread()` from initialise().
  static void enterMainThread() noexcept;
  // Nonblocking: Engine::process() claims and releases the role on every block,
  // and it is itself an OB_NONBLOCKING function. A single TLS byte store.
  static void enterAudioThread() noexcept OB_NONBLOCKING;
  static void leaveAudioThread() noexcept OB_NONBLOCKING;

  // Cheap enough to call from the audio thread: reads a thread-local byte.
  static ThreadRole current() noexcept OB_NONBLOCKING;
  static bool onMainThread() noexcept OB_NONBLOCKING;
  static bool onAudioThread() noexcept OB_NONBLOCKING;

  // Tests drive `process()` from an ordinary thread. Rather than weaken the
  // assertions, a test claims the audio role explicitly for its scope.
  class ScopedAudioThread {
   public:
    ScopedAudioThread() noexcept { enterAudioThread(); }
    ~ScopedAudioThread() { leaveAudioThread(); }
    ScopedAudioThread(const ScopedAudioThread&) = delete;
    ScopedAudioThread& operator=(const ScopedAudioThread&) = delete;
  };
};

namespace detail {

// A trap rather than assert(): assert() calls into libc, which is neither
// allocation- nor lock-free, so it cannot appear inside an OB_NONBLOCKING
// function without failing the compile-time effect check. The trap gives a
// debugger a precise stop with no runtime cost when the checks are off.
inline void assertAudioThread() noexcept OB_NONBLOCKING {
#ifndef NDEBUG
  if (!ThreadCheck::onAudioThread()) {
    __builtin_trap();
  }
#endif
}

inline void assertMainThread() noexcept {
#ifndef NDEBUG
  if (ThreadCheck::current() == ThreadRole::Audio) {
    __builtin_trap();
  }
#endif
}

}  // namespace detail

// `[audio-thread]` — the caller is the thread currently inside the render
// callback (or a test standing in for it).
#define OB_ASSERT_AUDIO_THREAD() ::onebeat::plugin::detail::assertAudioThread()

// `[main-thread]` — anything but the audio thread. Deliberately weaker than
// "the one main thread": OneBeat's scanner and housekeeping threads legitimately
// call main-thread functions, serialised by the caller. What must never happen
// is the *audio* thread calling one.
#define OB_ASSERT_MAIN_THREAD() ::onebeat::plugin::detail::assertMainThread()

}  // namespace onebeat::plugin
