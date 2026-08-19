// The concrete commands (OB-3-03 §1, §3).
//
// One factory per user action. They take the project by reference because a
// command has to capture the inverse *from the current state* — "set the name
// back to what it is now" is only knowable now — and because create commands
// mint their IDs up front (see command.h).
//
// The vocabulary is deliberately small. Anything a user does in Stage 3 is one
// of these, or a transaction over several of them.
#pragma once

#include <cstddef>
#include <string>
#include <vector>

#include "model/command.h"
#include "model/entities.h"
#include "model/note_sequence.h"
#include "model/project.h"

namespace onebeat::model {

// The parts of a pattern that are not notes. Edited far more often than the
// notes are, and separated so that renaming a pattern does not copy 10,000
// notes twice into the history.
struct PatternMeta {
  std::string name;
  ColorHex color;
  Ticks length = 0;
  int32_t order = 0;
  std::string group;
  TimeSignature time_signature;
  double swing = 0.0;

  static PatternMeta from(const Pattern& pattern) {
    return PatternMeta{pattern.name,  pattern.color,          pattern.length, pattern.order,
                       pattern.group, pattern.time_signature, pattern.swing};
  }
};

// ----- create -------------------------------------------------------------
// `addInstrument` is a composite: D-M2's auto-created mixer track is part of
// the same user action, so it undoes with it.
CommandPtr addInstrument(Project& project, const std::string& name, const PluginRef& plugin);
// User-facing creation: derives a unique name from the descriptor and cycles
// through the instrument palette. The explicit-name overload remains useful
// for import and tests.
CommandPtr addInstrument(Project& project, const PluginRef& plugin);
CommandPtr addPattern(Project& project, const std::string& name,
                      Ticks length = TicksPerBarFourFour * 4);
CommandPtr addLane(Project& project, const std::string& name);
CommandPtr addMixerTrack(Project& project, const std::string& name);
CommandPtr addClip(Project& project, ArrangementLaneId lane, const ClipSource& source, Ticks start,
                   Ticks length);

// ----- delete -------------------------------------------------------------
// Each captures its full inverse at apply time, including every cascade: the
// sequences an instrument had in every pattern, the clips a pattern or lane
// carried, the routing a mixer track's dependents were using.
CommandPtr removeInstrument(InstrumentId id);
CommandPtr removePattern(PatternId id);
CommandPtr removeLane(ArrangementLaneId id);
CommandPtr removeClip(ClipId id);
CommandPtr removeMixerTrack(MixerTrackId id);

// ----- instrument lifecycle ----------------------------------------------
// Duplication owns a fresh ID and dedicated mixer track but copies the plugin
// reference/state, note defaults and presentation. Replacement deliberately
// changes only the plugin: sequences belong to patterns and survive.
CommandPtr duplicateInstrument(Project& project, InstrumentId id);
CommandPtr replaceInstrument(const Project& project, InstrumentId id, const PluginRef& plugin);
CommandPtr reorderInstrument(const Project& project, InstrumentId id, int32_t target_order);

// ----- edit ---------------------------------------------------------------
// `mutator` runs on a copy to derive the "after" state, so the command owns
// both ends before anything is applied. Consecutive edits to the same entity
// and field coalesce while the bus's coalescing window is open — that is what
// makes a knob twiddle one history entry.
CommandPtr editInstrument(const Project& project, InstrumentId id, ChangeField field,
                          const std::function<void(Instrument&)>& mutator, std::string name);
CommandPtr editPatternMeta(const Project& project, PatternId id, ChangeField field,
                           const std::function<void(PatternMeta&)>& mutator, std::string name);
CommandPtr editLane(const Project& project, ArrangementLaneId id, ChangeField field,
                    const std::function<void(ArrangementLane&)>& mutator, std::string name);
CommandPtr editClip(const Project& project, ClipId id, ChangeField field,
                    const std::function<void(Clip&)>& mutator, std::string name);
CommandPtr editMixerTrack(const Project& project, MixerTrackId id, ChangeField field,
                          const std::function<void(MixerTrack&)>& mutator, std::string name);

// ----- notes --------------------------------------------------------------
// Granular on purpose: a note edit captures the notes it touched, not the
// sequence it touched them in (OB-3-03 §2, "memory-bounded by command
// granularity, not snapshots").
CommandPtr insertNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> notes);
CommandPtr removeNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> notes);
// Move, resize, re-velocity: the same notes, before and after. `before` and
// `after` must be the same size and correspond element-wise.
CommandPtr replaceNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> before,
                        std::vector<Note> after);

// ----- audio clips --------------------------------------------------------
//
// The window is in *source* time and the clip's length is in timeline time;
// `AudioSource`'s comment is the normative account of how the two meet. What
// these add over `editClip` is that each is one user gesture with one name in
// the undo menu, and that the derived arithmetic lives in exactly one place.

// Trim. `source_length` of 0 keeps its "to the end of the file" meaning.
CommandPtr setAudioClipWindow(const Project& project, ClipId id, Ticks source_offset,
                              Ticks source_length);
CommandPtr setAudioClipStretchMode(const Project& project, ClipId id, StretchMode mode);
CommandPtr setAudioClipSourceBpm(const Project& project, ClipId id, double bpm);
CommandPtr setAudioClipReversed(const Project& project, ClipId id, bool reversed);
CommandPtr setAudioClipGain(const Project& project, ClipId id, float gain);

// Resize with the clip's own stretch rule applied: a clip that is not stretched
// re-trims (its window follows the new length), and one that is stretches (its
// window is untouched and the ratio moves). One entry point so that the two
// cannot drift apart, which is the whole reason `stretch_ratio` is derived.
CommandPtr resizeAudioClip(const Project& project, ClipId id, Ticks length);

// Cut at an absolute tick. Returns null when `at` is not strictly inside the
// clip — a cut on an edge is a no-op, not an error, and must not enter history.
// The left half keeps the original clip's ID; the right half is a new clip
// whose source window starts where the left half's ends, so cutting audio does
// not re-trigger the sample from its beginning.
CommandPtr splitClip(Project& project, ClipId id, Ticks at);

// Resize so the material plays at `project_bpm`, and switch the clip to
// pitch-preserving stretch. Null when the clip has no source tempo to fit —
// guessing one silently is how a project ends up subtly out of time.
CommandPtr fitAudioClipToTempo(const Project& project, ClipId id, double project_bpm,
                               Ticks source_duration = 0);

// ----- mixer effects ------------------------------------------------------
// The chain is a field of the track, so all of these are track edits. They are
// named individually because "Add Reverb" and "Bypass Reverb" are different
// entries in the undo menu, and because removing a slot has a cascade that a
// generic edit would not know to perform.

// Inserts at `index`, clamping to the end of the chain. Mints the slot's ID up
// front so apply → undo → redo lands the same one and any automation written
// against it in the meantime still resolves.
CommandPtr addEffect(Project& project, MixerTrackId track, const PluginRef& plugin,
                     size_t index = SIZE_MAX);
// Composite: drops the slot *and* every automation clip driving it, as one
// undo entry (see Project::effectImpact).
CommandPtr removeEffect(Project& project, MixerTrackId track, EffectId effect);
CommandPtr moveEffect(const Project& project, MixerTrackId track, EffectId effect, size_t index);
CommandPtr setEffectBypassed(const Project& project, MixerTrackId track, EffectId effect,
                             bool bypassed);
// Coalesces per (track, effect, parameter), so one knob drag is one entry and
// two knobs are two.
CommandPtr setEffectParam(const Project& project, MixerTrackId track, EffectId effect,
                          plugin::ParamId parameter, float value);

// ----- project-level state ------------------------------------------------
CommandPtr setTransport(const Project& project, const TransportState& transport);
CommandPtr setProjectMeta(const Project& project, const ProjectMeta& meta);

}  // namespace onebeat::model
