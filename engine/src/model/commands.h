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
  double swing = 0.0;

  static PatternMeta from(const Pattern& pattern) {
    return PatternMeta{pattern.name, pattern.color, pattern.length, pattern.swing};
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

// ----- project-level state ------------------------------------------------
CommandPtr setTransport(const Project& project, const TransportState& transport);
CommandPtr setProjectMeta(const Project& project, const ProjectMeta& meta);

}  // namespace onebeat::model
