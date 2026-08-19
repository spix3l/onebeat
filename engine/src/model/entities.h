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

#include <cmath>
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

// Channel-level playback settings. Kept on the project-global instrument so
// they apply consistently to every pattern that addresses the channel.
struct ChannelSettings {
  int32_t gate_percent = 100;
  Ticks shift_ticks = 0;
  int32_t cut_group = 0;
  int32_t cut_by_group = 0;
  int32_t max_polyphony = 0;  // 0 means unlimited
  bool mono = false;
  bool portamento = false;
  int32_t root_key = 60;
  int32_t key_low = 0;
  int32_t key_high = 127;
  int32_t fine_tune_cents = 0;
  float velocity_tracking = 1.0F;
  int32_t mod_x = 0;
  int32_t mod_y = 0;
  bool arpeggiator = false;
  int32_t arpeggiator_time_ticks = TicksPerQuarter / 4;
  int32_t arpeggiator_gate_percent = 100;
  int32_t echo_time_ticks = 0;
  int32_t echo_feedback_percent = 0;
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
  ChannelSettings channel_settings;
  std::vector<OutputRoute> routing;
  bool muted = false;
  bool soloed = false;
  // Channel gain (linear 0..2) and pan (-1..1), the channel rack's VOL/PAN
  // knobs. Applied to the hosted voice while this instrument is selected; the
  // per-track mixer (v0.4) replaces these with mixer-track gain/pan.
  float gain = 1.0F;
  float pan = 0.0F;
};

// One insert in a mixer track's effect chain.
//
// The plugin is named the same way an instrument's is — by `PluginRef`, format
// and all — so a hosted CLAP effect drops into a slot with no model change; the
// stock four simply carry `PluginFormat::Builtin`. What a slot adds over a bare
// `PluginRef` is an identity and a bypass, and both exist for the same reason:
// automation. A curve is written against `EffectId`, so dragging the reverb up
// the chain moves its automation with it, and bypass is a slot property rather
// than a plugin parameter so that every effect has one whether or not its
// author thought to provide it.
struct EffectSlot {
  EffectId id;
  PluginRef plugin;
  bool bypassed = false;
  // Base parameter values, keyed by the plugin's own stable `ParamId`. Sparse:
  // a parameter the user has never touched is absent and the plugin's default
  // stands, which is what keeps a project file from pinning every default the
  // day a plugin ships a better one.
  std::map<plugin::ParamId, float> params;
};

// Stage 4's behaviour, less the sends. A track is a signal path: things render
// into it, its chain processes what arrived, and the result goes to `output` —
// another track, or nothing at all for the one track that is Master.
struct MixerTrack {
  MixerTrackId id;
  std::string name;
  std::optional<MixerTrackId> output;  // nullopt == this is Master
  float gain = 1.0F;
  float pan = 0.0F;
  bool muted = false;  // an *audio* gate, not the lane's event gate (D-M4)
  bool soloed = false;
  // Chain order is array order, and here that is correct rather than lazy: a
  // chain *is* a sequence, unlike lanes and instruments whose display order is
  // a field because their identity must survive reordering. Slots keep their
  // `EffectId` across a move, which is what automation needs (see EffectSlot).
  std::vector<EffectSlot> effects;

  const EffectSlot* findEffect(EffectId effect) const {
    for (const EffectSlot& slot : effects) {
      if (slot.id == effect) return &slot;
    }
    return nullptr;
  }
};

// --------------------------------------------------------------------------
// Time axis
// --------------------------------------------------------------------------

struct TimeSignature {
  int32_t numerator = 4;
  int32_t denominator = 4;
};

// One point on an automation curve: a value at a position, clip-relative.
struct AutomationPoint {
  Ticks position = 0;
  float value = 0.0F;
};

// Pattern and arrangement automation share the same target vocabulary. Keeping
// this value type above Pattern lets patterns own automation without a pointer
// or a second, subtly different curve representation.
struct AutomationSource {
  enum class TargetKind : uint8_t { Instrument, MixerTrack, Effect };
  TargetKind target_kind = TargetKind::Instrument;
  InstrumentId instrument;
  MixerTrackId mixer_track;
  EffectId effect;
  plugin::ParamId parameter = plugin::InvalidParamId;
  std::vector<AutomationPoint> points;
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
  // Automation authored with the pattern rather than as a separate arrangement
  // clip. Arrangement automation remains supported for compatibility; this
  // collection is what makes a pattern self-contained when it is duplicated.
  std::vector<AutomationSource> automation;
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

// How a clip reconciles the length the user dragged with the length of the
// audio underneath it.
enum class StretchMode : uint8_t {
  // The source plays at its own rate and the clip is a window onto it: dragging
  // the right edge trims, and dragging it past the end buys silence, not more
  // audio. The honest default, and what a one-shot wants.
  Off = 0,
  // Playback rate follows the clip. Pitch moves with it — the turntable, and
  // the sound most people actually mean by "speed it up".
  Resample = 1,
  // Duration follows the clip and pitch does not, via the overlap-add stretcher
  // in core/time_stretch.h. What "fit to tempo" wants for anything melodic.
  Stretch = 2,
};

// `path` is bundle-relative once consolidated (FR-PRJ-05).
//
// The edit parameters split cleanly in two, and keeping the split visible is
// what stops the two from fighting:
//
//   - `source_offset` / `source_length` are a window **in source time**. They
//     say which part of the file this clip is made of, and they do not change
//     when the tempo does.
//   - `Clip::length` is a duration **on the timeline**, and `stretch_mode` is
//     the rule that maps one onto the other.
//
// The stretch *ratio* is deliberately not a field: it is `Clip::length` over
// `source_length`, derived by `audioStretchRatio` below. Storing it as well
// would be a second source of truth that a resize has to remember to update,
// and the first time it is forgotten a clip plays at a rate that matches
// nothing on screen.
struct AudioSource {
  std::string path;
  // Trim-in: where in the file this clip starts. Source time, not timeline time.
  Ticks source_offset = 0;
  // Trim-out, as a duration from `source_offset`. 0 means "to the end of the
  // file" — the state a freshly dropped sample is in, before anything knows how
  // long the file is.
  Ticks source_length = 0;
  float gain = 1.0F;
  bool reversed = false;
  MixerTrackId destination;  // routes to a track directly — no instrument (D-M7)
  StretchMode stretch_mode = StretchMode::Off;
  // The tempo the material was recorded at, 0 when unknown. Only "fit to tempo"
  // reads it, and it is stored rather than re-detected so that a user who
  // corrects a bad guess corrects it once.
  double source_bpm = 0.0;
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
// Derived audio-clip geometry
// --------------------------------------------------------------------------
//
// One place computes these, and everything — the flattener, the ABI, the
// waveform painter — asks here. The alternative is three implementations of the
// same arithmetic that agree until one of them is fixed.

// How much source the clip consumes, in source time. `source_length` of 0 means
// "to the end of the file", which only the caller holding the file's duration
// can resolve, so it passes that in; 0 for an unknown duration falls back to the
// clip's own length, which is what a freshly dropped sample is.
inline Ticks audioSourceSpan(const AudioSource& source, Ticks clip_length,
                             Ticks source_duration = 0) {
  if (source.source_length > 0) return source.source_length;
  if (source_duration > source.source_offset) return source_duration - source.source_offset;
  return clip_length;
}

// Source frames consumed per timeline frame. 1.0 whenever stretching is off, so
// a clip nobody has stretched is bit-identical to the file.
inline double audioStretchRatio(const AudioSource& source, Ticks clip_length,
                                Ticks source_duration = 0) {
  if (source.stretch_mode == StretchMode::Off) return 1.0;
  const Ticks span = audioSourceSpan(source, clip_length, source_duration);
  if (span <= 0 || clip_length <= 0) return 1.0;
  return static_cast<double>(span) / static_cast<double>(clip_length);
}

// The timeline length that plays `source` at its recorded tempo against a
// project running at `project_bpm` — the whole of "fit to tempo".
//
// Returns 0 when the answer is unknowable (no source tempo, no material), and
// the caller leaves the clip alone rather than resizing it to a guess.
inline Ticks audioLengthAtTempo(const AudioSource& source, Ticks clip_length, double project_bpm,
                                Ticks source_duration = 0) {
  if (source.source_bpm <= 0.0 || project_bpm <= 0.0) return 0;
  const Ticks span = audioSourceSpan(source, clip_length, source_duration);
  if (span <= 0) return 0;
  const double scaled = static_cast<double>(span) * (source.source_bpm / project_bpm);
  const Ticks result = static_cast<Ticks>(std::llround(scaled));
  return result > 0 ? result : 1;
}

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
  // On: play repeats the arrangement rather than running off its end into
  // silence. The switch is the user's — the transport bar toggles it and the
  // project remembers it — while the *region* is derived from the arrangement
  // (ABI publishModel).
  bool loop_enabled = true;
  Ticks loop_start = 0;
  Ticks loop_end = TicksPerBarFourFour * 8;
};

struct ProjectMeta {
  std::string name = "Untitled";
  std::string created_with;
};

}  // namespace onebeat::model
