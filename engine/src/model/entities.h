// The domain entities (OB-3-02 §1–§5). ARCHITECTURE.md §2–§4 is normative and
// this file is its transcription; the anti-pattern table in §6 is the review
// checklist for every change to it (R15).
//
// The shape to keep in mind while reading: **two orthogonal axes meeting at
// exactly one point.** Time is Pattern → Clip → ArrangementLane. Signal is
// Instrument → MixerTrack → Master. `Instrument` is the join, and it is the
// only join. Concretely, and deliberately:
//
//   - `ArrangementLane` has no instrument, no effects, no routing and no audio.
//     Not "empty for now" — there is no field, and `TypedId` makes adding one by
//     accident impossible (model/ids.h).
//   - `Clip` holds no note data. It holds a `PatternId`. Every placement of a
//     pattern therefore updates when the pattern is edited, which is what
//     pattern-based composition is *for* (D-M3; `Make unique` is OB-3-11).
//   - `Instrument` is project-global and lives in no pattern, lane or track.
#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "model/ids.h"
#include "model/note_sequence.h"
#include "plugin/scan/descriptor.h"

namespace onebeat::model {

using PluginFormat = plugin::scan::PluginFormat;

// "#RRGGBB". A string because it goes straight into the project file and
// straight into a token lookup; the model never interprets it.
using ColorHex = std::string;

// --------------------------------------------------------------------------
// Signal axis
// --------------------------------------------------------------------------

// What is needed to find the plugin again, and to keep faith with a project
// whose plugin is missing: identity is `id`, never `path_hint` (FR-PLG-10).
struct PluginRef {
  PluginFormat format = PluginFormat::Unknown;
  std::string id;
  std::string name;
  std::string vendor;
  std::string path_hint;
  std::string state_ref;     // bundle-relative, e.g. "state/bass.bin"
  std::string state_sha256;  // hex digest of the chunk at that path
};

// One output port of an instrument, routed to one mixer track by **stable ID,
// never an index** (D-M1). Multi-output instruments have several of these; a
// single-output instrument has exactly one.
struct OutputRoute {
  plugin::PortId port = 0;
  MixerTrackId track;
};

// Per-instrument defaults applied to notes that do not override them. Stored
// once per instrument rather than per note, which is why a note record is four
// integers.
struct NoteDefaults {
  Velocity velocity = DefaultVelocity;
  float pan = 0.0F;
  int16_t pitch_offset = 0;
};

struct Instrument {
  InstrumentId id;
  std::string name;
  ColorHex color = "#6C8CFF";
  // Presentation order is data, never map/creation order. Reordering the
  // channel rack therefore changes no identity and no pattern reference.
  int32_t order = 0;
  PluginRef plugin;
  NoteDefaults note_defaults;
  std::vector<OutputRoute> routing;
  bool muted = false;
  bool soloed = false;
  // Channel gain (linear 0..2) and pan (-1..1), the channel rack's VOL/PAN
  // knobs. Applied to the hosted voice while this instrument is selected; the
  // per-track mixer (v0.4) replaces these with mixer-track gain/pan.
  float gain = 1.0F;
  float pan = 0.0F;
};

// Stage 4 owns the behaviour (chains, gain law, sends, solo semantics). What
// exists here is what routing needs to be real from day one: an ID space, a
// name, and an output that is another track or, for exactly one track, nothing.
struct MixerTrack {
  MixerTrackId id;
  std::string name;
  std::optional<MixerTrackId> output;  // nullopt == this is Master
  float gain = 1.0F;
  float pan = 0.0F;
  bool muted = false;  // an *audio* gate, not the lane's event gate (D-M4)
  bool soloed = false;
};

// --------------------------------------------------------------------------
// Time axis
// --------------------------------------------------------------------------

struct TimeSignature {
  int32_t numerator = 4;
  int32_t denominator = 4;
};

// A horizontal slice across instruments, not a container belonging to one. The
// map is **sparse**: a pattern stores sequences only for the instruments it
// actually uses (D-M5's "show only what the pattern uses" is a view over this,
// not a second model).
struct Pattern {
  PatternId id;
  std::string name;
  ColorHex color = "#6C8CFF";
  Ticks length = TicksPerBarFourFour * 4;
  // Presentation order and grouping are persisted pattern metadata, not map order.
  int32_t order = 0;
  std::string group;
  TimeSignature time_signature;
  // 0..1. At 1, every odd sixteenth is delayed by half a sixteenth.
  // Stored on the pattern because swing is part of the groove, not transport.
  double swing = 0.0;
  std::map<InstrumentId, NoteSequence> sequences;
};

// Purely organisational. Holds no instrument, no effects, no routing, no audio.
// Two clips on different lanes sound identical.
struct ArrangementLane {
  ArrangementLaneId id;
  std::string name;
  ColorHex color = "#6C8CFF";
  int32_t height = 88;
  // Display order is this field, never array position (FR-PRJ-02). Reordering
  // lanes rewrites one integer per lane and touches no clip.
  int32_t order = 0;
  bool collapsed = false;
  bool muted = false;  // an *event* gate: clips on this lane do not fire (D-M4)
  bool soloed = false;
  // Reserved for DM-Q1 (folder lanes). Always nullopt in v0.3; present so that
  // answering DM-Q1 is a value change rather than a schema change.
  std::optional<ArrangementLaneId> group_id;
};

// --------------------------------------------------------------------------
// Clips — one entity, three sources (D-M7)
// --------------------------------------------------------------------------
//
// Audio and automation clips are clip types, not instrument types. FL models
// them as channels living in the Channel Rack, which is a historical artefact
// that confuses users; separating them costs nothing.

// Holds a reference and nothing else. There is deliberately no path from a clip
// to mutable note data: to edit notes you must go to the pattern, which is what
// makes "editing a pattern changes every placement" true by construction rather
// than by discipline (anti-pattern §6.3).
struct PatternSource {
  PatternId pattern;
};

// Stage 9 owns editing. `path` is bundle-relative once consolidated (FR-PRJ-05).
struct AudioSource {
  std::string path;
  Ticks source_offset = 0;
  float gain = 1.0F;
  bool reversed = false;
  MixerTrackId destination;  // routes to a track directly — no instrument (D-M7)
};

// One point on an automation curve: a value at a position, clip-relative.
// Stage 4 owns curve *shapes* (the interpolation between points, tension,
// stepped vs smooth). v0.3 stores the points and flattens each one to a
// parameter event, which is enough to prove the path end to end.
struct AutomationPoint {
  Ticks position = 0;
  float value = 0.0F;
};

// Stage 4 owns curves. The target is an entity plus a parameter, by ID.
struct AutomationSource {
  enum class TargetKind : uint8_t { Instrument, MixerTrack };
  TargetKind target_kind = TargetKind::Instrument;
  InstrumentId instrument;   // valid when target_kind == Instrument
  MixerTrackId mixer_track;  // valid when target_kind == MixerTrack
  plugin::ParamId parameter = plugin::InvalidParamId;
  std::vector<AutomationPoint> points;
};

using ClipSource = std::variant<PatternSource, AudioSource, AutomationSource>;

// Non-destructive variation without cloning the pattern (D-M3, DM-Q3). Only
// `transpose`, `loop` and `window_start` are honoured in v0.3; the rest are
// stored, round-tripped and ignored until OB-3-13 gives them semantics.
struct ClipTransforms {
  int16_t transpose = 0;
  // Off by default: stretching a clip past its source shows how much room it
  // has, and silence is the honest result. Repeating the source is an edit the
  // user asks for with the clip inspector's LOOP toggle, not something a drag
  // of the right edge does on its own.
  bool loop = false;
  Ticks window_start = 0;
  float velocity_scale = 1.0F;  // reserved, DM-Q3
  Ticks time_nudge = 0;         // reserved, DM-Q3
  float probability = 1.0F;     // reserved, DM-Q3
};

struct Clip {
  ClipId id;
  ArrangementLaneId lane;  // organisational only — see ARCHITECTURE.md §4
  Ticks start = 0;
  Ticks length = 0;
  bool muted = false;
  ClipSource source;
  ClipTransforms transforms;

  bool isPattern() const { return std::holds_alternative<PatternSource>(source); }
  const PatternSource* pattern() const { return std::get_if<PatternSource>(&source); }
  const AudioSource* audio() const { return std::get_if<AudioSource>(&source); }
  const AutomationSource* automation() const { return std::get_if<AutomationSource>(&source); }
};

// --------------------------------------------------------------------------
// Project-level, non-entity state
// --------------------------------------------------------------------------

// The last tick any note in `pattern` ends on, across every instrument. 0 when
// the pattern holds nothing.
inline Ticks patternContentEnd(const Pattern& pattern) {
  Ticks end = 0;
  for (const auto& [instrument, sequence] : pattern.sequences) {
    (void)instrument;
    end = std::max(end, sequence.contentEnd());
  }
  return end;
}

// The shortest whole number of bars that holds everything in the pattern, and
// never less than one bar.
//
// This is the floor under `Pattern::length`, not a replacement for it: the
// flattener drops whatever falls past the pattern length, so a length below
// this one means notes that are stored and drawn but cannot sound. Rounding to
// a bar rather than to the last note keeps the turnaround on a barline, which
// is where the ear expects it.
inline Ticks patternLoopLength(const Pattern& pattern) {
  const Ticks content = patternContentEnd(pattern);
  if (content <= 0) return TicksPerBarFourFour;
  const Ticks bars = (content + TicksPerBarFourFour - 1) / TicksPerBarFourFour;
  return bars * TicksPerBarFourFour;
}

// How long the pattern actually plays for: the length the user set, stretched
// to whole bars whenever the notes in it need more room.
//
// `Pattern::length` is the *declared* length — what the rack's Steps control
// writes and what the file stores — and it is never re-derived from the notes.
// Drawing past the end therefore lengthens the pattern (the note sounds instead
// of being silently dropped by the flattener), and deleting that note lets it
// come back down to the declared length rather than stranding the pattern at a
// size the user never chose and could not set back.
inline Ticks patternEffectiveLength(const Pattern& pattern) {
  const Ticks declared = pattern.length > 0 ? pattern.length : TicksPerBarFourFour;
  const Ticks content = patternContentEnd(pattern);
  return content <= declared ? declared : patternLoopLength(pattern);
}

struct TransportState {
  double tempo = 120.0;
  TimeSignature time_signature;
  bool metronome_enabled = false;
  bool loop_enabled = false;
  Ticks loop_start = 0;
  Ticks loop_end = TicksPerBarFourFour * 8;
};

struct ProjectMeta {
  std::string name = "Untitled";
  std::string created_with;
};

}  // namespace onebeat::model
