// The mixer graph: what renders into what, and what happens on the way
// (ARCHITECTURE.md §3.5, EPIC-4).
//
// The rule this file exists to keep is the same one the schedule keeps: **the
// audio thread never walks a reference graph.** A model mixer track points at
// another mixer track by ULID, through a `std::map`. What the audio thread gets
// instead is this — a flat array of nodes addressed by dense index, in an order
// already proven acyclic and already sorted so that every input is rendered
// before the track it feeds.
//
// **What is in the graph and what is not.** The graph holds *structure*: who
// feeds whom, and which effect instances sit on which track. Structure changes
// rarely — adding an effect, re-routing a bus — and a change rebuilds and
// republishes it by atomic swap, which resets the effect tails on that track.
// Levels are deliberately *not* here: gain, pan, mute and solo live as atomics
// beside the graph, because moving a fader must not rebuild anything and must
// not cut a reverb tail. So must effect parameters, which arrive as events.
//
// The published graph is immutable in shape. The effect instances it owns are
// mutated by processing, which is why `process` is const and the instances are
// reached through pointers rather than by value.
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "core/audio_buffer.h"
#include "core/rt/rt.h"
#include "plugin/builtin/effects/effect_plugin.h"
#include "plugin/event.h"

namespace onebeat::core {

// The ceiling on project mixer tracks, and the size of the bus array the audio
// thread indexes with a track's dense index.
inline constexpr int MaxMixerTracks = 64;
// The ceiling on inserts across the whole project. Effects are addressed by a
// dense index in the schedule (see EventType::EffectParam), and this is the
// size of that address space.
inline constexpr int MaxMixerEffects = 256;

// One insert, as the audio thread sees it: an instance, and the dense index
// automation addresses it by.
struct GraphEffect {
  std::unique_ptr<plugin::builtin::EffectPlugin> instance;
  int32_t index = -1;
  // The model's EffectId, carried so a rebuild can tell whether this slot is
  // the same insert in a new position or a genuinely new one.
  std::string effect_id;
};

struct GraphNode {
  // Dense index of the track this one feeds, or -1 for the master, which feeds
  // the device.
  int32_t output = -1;
  std::vector<GraphEffect> effects;
  // The model's MixerTrackId, for reconciliation and for diagnostics.
  std::string track_id;
};

class MixerGraph {
 public:
  MixerGraph() = default;
  MixerGraph(const MixerGraph&) = delete;
  MixerGraph& operator=(const MixerGraph&) = delete;

  std::vector<GraphNode>& nodes() noexcept { return nodes_; }
  const std::vector<GraphNode>& nodes() const noexcept OB_NONBLOCKING { return nodes_; }

  // Nodes in the order they must be rendered: every track appears after every
  // track that feeds it, so summing into an output is always summing into
  // something not yet processed.
  const std::vector<int32_t>& order() const noexcept OB_NONBLOCKING { return order_; }
  int32_t master() const noexcept OB_NONBLOCKING { return master_; }
  int32_t effectCount() const noexcept OB_NONBLOCKING { return effect_count_; }

  // Off the audio thread. Sorts `nodes_` into a render order and finds the
  // master. Returns false when the routing contains a cycle — the model's
  // invariant checker should have caught it first, and this is the second line
  // of defence, because the symptom of a cycle here is a hang.
  bool finalise();

  // The dense index of the track with this model ID, or -1.
  int32_t indexOf(const std::string& track_id) const;

 private:
  std::vector<GraphNode> nodes_;
  std::vector<int32_t> order_;
  int32_t master_ = -1;
  int32_t effect_count_ = 0;
};

}  // namespace onebeat::core
