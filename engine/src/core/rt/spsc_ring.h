// Single-producer / single-consumer POD ring.
//
// Used for the UI -> engine command channel (producer: UI thread, consumer:
// audio thread) and for the RT log (producer: audio thread, consumer: the log
// drain thread).
//
// It is the same bounded ring as MpscRing. We deliberately do not use a
// third-party queue here: every function on the audio thread must be *provably*
// nonblocking under Clang's function effect analysis, and a queue whose
// internals are not annotated forces a blanket -Wfunction-effects suppression
// over the hottest code in the engine. A 60-line ring we own costs less than
// the hole that suppression would leave (ADR-002 §3).
#pragma once

#include <cstddef>

#include "core/rt/mpsc_ring.h"
#include "core/rt/rt.h"

namespace onebeat::rt {

template <typename T, size_t Capacity>
using SpscRing = MpscRing<T, Capacity>;

}  // namespace onebeat::rt
