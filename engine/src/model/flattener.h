// The flattener: model → schedule (OB-3-04, ARCHITECTURE.md §7).
//
// THE rule of this codebase, restated from core/schedule.h: **the audio thread
// never walks a reference graph.** Editing is reference-heavy — a clip points
// at a pattern, a pattern holds sparse sequences keyed by instrument — and the
// audio thread reads a flat, absolutely-positioned, time-ordered array. This
// file is the whole of the distance between those two facts.
//
// It runs off the audio thread, allocates freely, and produces an immutable
// `core::Schedule` that the caller publishes through OB-1-07's atomic swap.
// Nothing here is real-time code and nothing here is reachable from the audio
// thread; that separation is the point (anti-pattern §6 #7).
//
// The tick → frame conversion happens exactly once, here, through `TimeMap`.
// After this, musical time does not exist: the schedule is in frames.
#pragma once

#include <cstdint>
#include <map>
#include <memory>

#include "core/schedule.h"
#include "model/changes.h"
#include "model/project.h"

namespace onebeat::model {

struct FlattenOptions {
  double sample_rate = 48000.0;
  uint64_t generation = 1;
};

struct FlattenResult {
  std::unique_ptr<core::Schedule> schedule;

  // The model addresses instruments by ULID; the schedule addresses them by a
  // dense integer, because the audio thread indexes an array with it. The map
  // is assigned in ULID order, so it is stable for a given model and the
  // caller can bind engine voices to it.
  std::map<InstrumentId, core::InstrumentId> instrument_index;

  int64_t length_frames = 0;
  size_t event_count = 0;
  size_t clips_flattened = 0;
  size_t notes_dropped = 0;  // transposed outside 0..127

  // Same model ⇒ same bytes (scope §5). Golden tests compare this rather than
  // the event array, and a change to the flattener that alters output is
  // impossible to land silently.
  uint64_t hash = 0;

  double elapsed_ms = 0.0;
};

// Deterministic: the same project always produces the same events in the same
// order with the same hash, whatever order it was built in.
FlattenResult flatten(const Project& project, const FlattenOptions& options);

// Watches a project and remembers whether the schedule it produced is stale.
//
// v0.3 re-flattens the whole project rather than a dirty span — measured at
// well under the 10 ms budget for a 1,000-clip project (see
// docs/flattener-budget.md). The dirty-span machinery only earns its
// complexity once that measurement stops holding, and this class is where it
// would go, so callers do not change when it does.
class FlattenScheduler {
 public:
  explicit FlattenScheduler(Project& project);
  ~FlattenScheduler();

  FlattenScheduler(const FlattenScheduler&) = delete;
  FlattenScheduler& operator=(const FlattenScheduler&) = delete;

  bool dirty() const { return dirty_; }
  void markDirty() { dirty_ = true; }

  // Flattens if anything changed since the last call, bumping the generation.
  // Returns a result whose `schedule` is null when nothing needed doing —
  // publishing an identical schedule would retire the live one for nothing.
  FlattenResult flushIfDirty(double sample_rate);

  uint64_t generation() const { return generation_; }

 private:
  Project& project_;
  ChangeBus::Token token_ = 0;
  bool dirty_ = true;
  uint64_t generation_ = 0;
};

}  // namespace onebeat::model
