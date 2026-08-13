// NoteSequence editing vocabulary (OB-3-08, DM-Q4).
//
// These functions are the seam used by both note editors. Queries are pure;
// mutations return OB-3-03 commands, so neither editor gets a private model or
// a way around undo. A step is only a view of the same NoteSequence.
#pragma once

#include <functional>
#include <optional>
#include <vector>

#include "model/commands.h"

namespace onebeat::model {

struct NoteGrid {
  Ticks spacing = TicksPerQuarter / 4;  // sixteenth notes
  Ticks origin = 0;

  bool valid() const { return spacing > 0; }
};

// Time is half-open and keys are inclusive. This matches canvas clipping: a
// note ending exactly at `start` and one beginning exactly at `end` are out.
struct NoteRange {
  Ticks start = 0;
  Ticks end = 0;
  int16_t low_key = 0;
  int16_t high_key = 127;
};

using NotePredicate = std::function<bool(const Note&)>;

Ticks snapTick(Ticks tick, const NoteGrid& grid);

// Select sounding intersections, including long notes which begin before the
// visible range. The predicate overload is the lasso seam: the UI converts its
// shape into a note predicate without adding selection state to the model.
std::vector<Note> selectNotesInRange(const NoteSequence& sequence, const NoteRange& range);
std::vector<Note> selectNotes(const NoteSequence& sequence, const NotePredicate& predicate);

// Adds a note using the instrument defaults. Pan/pitch/mod remain schema-
// reserved per-note expressions; Stage 3 notes intentionally store no override.
CommandPtr addNote(const Project& project, PatternId pattern, InstrumentId instrument, Ticks start,
                   Ticks length, int16_t key);
CommandPtr moveNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                     Ticks delta, int16_t semitones, std::optional<NoteGrid> grid = std::nullopt);
CommandPtr resizeNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                       Ticks length_delta, std::optional<NoteGrid> grid = std::nullopt);
CommandPtr setNoteVelocity(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                           Velocity velocity);
CommandPtr scaleNoteVelocity(PatternId pattern, InstrumentId instrument,
                             std::vector<Note> selection, double scale);
CommandPtr quantiseNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                         const NoteGrid& grid, double strength);
CommandPtr transposeNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                          int16_t semitones);
CommandPtr duplicateNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                          Ticks delta, std::optional<NoteGrid> grid = std::nullopt);

struct StepCell {
  std::vector<Note> on_grid;
  std::vector<Note> off_grid;

  bool active() const { return !on_grid.empty(); }
};

// A cell owns [origin + index*spacing, next cell). A note of the requested key
// exactly at the cell onset is the step, regardless of its piano-roll length or
// velocity. Other notes inside the cell are reported as off-grid and toggleStep
// never removes them.
StepCell inspectStep(const NoteSequence& sequence, int16_t key, int64_t index,
                     const NoteGrid& grid);
CommandPtr toggleStep(const Project& project, PatternId pattern, InstrumentId instrument,
                      int16_t key, int64_t index, const NoteGrid& grid);

}  // namespace onebeat::model
