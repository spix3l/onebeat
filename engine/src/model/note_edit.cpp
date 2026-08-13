#include "model/note_edit.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace onebeat::model {
namespace {

Ticks clampStart(Ticks value) {
  return std::max<Ticks>(0, value);
}

Ticks addClamped(Ticks value, Ticks delta) {
  if (delta > 0 && value > std::numeric_limits<Ticks>::max() - delta) {
    return std::numeric_limits<Ticks>::max();
  }
  if (delta < 0 && value < std::numeric_limits<Ticks>::min() - delta) {
    return std::numeric_limits<Ticks>::min();
  }
  return value + delta;
}

Ticks subtractClamped(Ticks value, Ticks subtrahend) {
  if (subtrahend > 0 && value < std::numeric_limits<Ticks>::min() + subtrahend) {
    return std::numeric_limits<Ticks>::min();
  }
  if (subtrahend < 0 && value > std::numeric_limits<Ticks>::max() + subtrahend) {
    return std::numeric_limits<Ticks>::max();
  }
  return value - subtrahend;
}

Ticks noteEnd(const Note& note) {
  return addClamped(note.start, note.length);
}

std::optional<Ticks> stepOnset(int64_t index, const NoteGrid& grid) {
  if (!grid.valid() || index < 0 || index > std::numeric_limits<Ticks>::max() / grid.spacing) {
    return std::nullopt;
  }
  const Ticks offset = index * grid.spacing;
  if (grid.origin > 0 && offset > std::numeric_limits<Ticks>::max() - grid.origin) {
    return std::nullopt;
  }
  const Ticks onset = grid.origin + offset;
  if (onset < 0) return std::nullopt;
  return onset;
}

int16_t boundedTranspose(const std::vector<Note>& notes, int16_t requested) {
  if (notes.empty()) return 0;
  int16_t lowest = 127;
  int16_t highest = 0;
  for (const Note& note : notes) {
    lowest = std::min(lowest, note.key);
    highest = std::max(highest, note.key);
  }
  const int lower = -static_cast<int>(lowest);
  const int upper = 127 - static_cast<int>(highest);
  return static_cast<int16_t>(std::clamp(static_cast<int>(requested), lower, upper));
}

std::vector<Note> moved(std::vector<Note> notes, Ticks delta, int16_t semitones,
                        const std::optional<NoteGrid>& grid) {
  if (notes.empty()) return notes;
  Ticks time_delta = delta;
  if (grid.has_value() && grid->valid()) {
    const auto anchor = std::min_element(
        notes.begin(), notes.end(),
        [](const Note& left, const Note& right) { return left.start < right.start; });
    const Ticks proposed = addClamped(anchor->start, delta);
    time_delta = subtractClamped(snapTick(proposed, *grid), anchor->start);
  }
  // Clamp the group as a group, preserving every relative onset.
  Ticks earliest = notes.front().start;
  for (const Note& note : notes) earliest = std::min(earliest, note.start);
  time_delta = std::max(time_delta, -earliest);
  const int16_t pitch_delta = boundedTranspose(notes, semitones);
  for (Note& note : notes) {
    note.start = addClamped(note.start, time_delta);
    note.key = static_cast<int16_t>(note.key + pitch_delta);
  }
  return notes;
}

}  // namespace

Ticks snapTick(Ticks tick, const NoteGrid& grid) {
  if (!grid.valid()) return tick;
  const Ticks relative = subtractClamped(tick, grid.origin);
  const Ticks quotient = relative / grid.spacing;
  const Ticks remainder = relative % grid.spacing;
  Ticks snapped_offset = quotient * grid.spacing;
  if (remainder >= 0) {
    // Exact halves go forward, which makes mouse movement deterministic in
    // both directions and matches conventional musical quantisation.
    if (remainder >= grid.spacing - remainder) {
      snapped_offset = addClamped(snapped_offset, grid.spacing);
    }
  } else {
    const Ticks distance_to_later = -remainder;
    if (distance_to_later > grid.spacing - distance_to_later) {
      snapped_offset = addClamped(snapped_offset, -grid.spacing);
    }
  }
  return addClamped(grid.origin, snapped_offset);
}

std::vector<Note> selectNotesInRange(const NoteSequence& sequence, const NoteRange& range) {
  std::vector<Note> selected;
  if (range.end <= range.start || range.high_key < range.low_key) return selected;
  for (const Note& note : sequence.notes()) {
    if (note.start >= range.end) break;
    if (noteEnd(note) <= range.start) continue;
    if (note.key < range.low_key || note.key > range.high_key) continue;
    selected.push_back(note);
  }
  return selected;
}

std::vector<Note> selectNotes(const NoteSequence& sequence, const NotePredicate& predicate) {
  std::vector<Note> selected;
  if (!predicate) return selected;
  for (const Note& note : sequence.notes()) {
    if (predicate(note)) selected.push_back(note);
  }
  return selected;
}

CommandPtr addNote(const Project& project, PatternId pattern, InstrumentId instrument, Ticks start,
                   Ticks length, int16_t key) {
  const Instrument* owner = project.findInstrument(instrument);
  if (project.findPattern(pattern) == nullptr || owner == nullptr) return nullptr;
  Note note;
  note.start = start;
  note.length = length;
  note.key = key;
  note.velocity = owner->note_defaults.velocity;
  if (!isValidNote(note)) return nullptr;
  return insertNotes(pattern, instrument, {note});
}

CommandPtr moveNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                     Ticks delta, int16_t semitones, std::optional<NoteGrid> grid) {
  if (selection.empty() || (grid.has_value() && !grid->valid())) return nullptr;
  std::vector<Note> after = moved(selection, delta, semitones, grid);
  return replaceNotes(pattern, instrument, std::move(selection), std::move(after));
}

CommandPtr resizeNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                       Ticks length_delta, std::optional<NoteGrid> grid) {
  if (selection.empty() || (grid.has_value() && !grid->valid())) return nullptr;
  std::vector<Note> after = selection;
  for (Note& note : after) {
    Ticks end = addClamped(noteEnd(note), length_delta);
    if (grid.has_value()) end = snapTick(end, *grid);
    note.length = end <= note.start ? 1 : end - note.start;
  }
  return replaceNotes(pattern, instrument, std::move(selection), std::move(after));
}

CommandPtr setNoteVelocity(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                           Velocity velocity) {
  if (selection.empty() || velocity > MaxVelocity) return nullptr;
  std::vector<Note> after = selection;
  for (Note& note : after) note.velocity = velocity;
  return replaceNotes(pattern, instrument, std::move(selection), std::move(after));
}

CommandPtr scaleNoteVelocity(PatternId pattern, InstrumentId instrument,
                             std::vector<Note> selection, double scale) {
  if (selection.empty() || !std::isfinite(scale) || scale < 0.0) return nullptr;
  std::vector<Note> after = selection;
  for (Note& note : after) {
    const double scaled = std::round(static_cast<double>(note.velocity) * scale);
    note.velocity =
        static_cast<Velocity>(std::clamp(scaled, 0.0, static_cast<double>(MaxVelocity)));
  }
  return replaceNotes(pattern, instrument, std::move(selection), std::move(after));
}

CommandPtr quantiseNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                         const NoteGrid& grid, double strength) {
  if (selection.empty() || !grid.valid() || !std::isfinite(strength) || strength < 0.0 ||
      strength > 1.0) {
    return nullptr;
  }
  std::vector<Note> after = selection;
  for (Note& note : after) {
    const Ticks target = snapTick(note.start, grid);
    const auto adjustment = static_cast<Ticks>(
        std::llround(static_cast<double>(subtractClamped(target, note.start)) * strength));
    note.start = clampStart(addClamped(note.start, adjustment));
  }
  return replaceNotes(pattern, instrument, std::move(selection), std::move(after));
}

CommandPtr transposeNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                          int16_t semitones) {
  return moveNotes(pattern, instrument, std::move(selection), 0, semitones);
}

CommandPtr duplicateNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> selection,
                          Ticks delta, std::optional<NoteGrid> grid) {
  if (selection.empty() || (grid.has_value() && !grid->valid())) return nullptr;
  std::vector<Note> copies = moved(std::move(selection), delta, 0, grid);
  return insertNotes(pattern, instrument, std::move(copies));
}

StepCell inspectStep(const NoteSequence& sequence, int16_t key, int64_t index,
                     const NoteGrid& grid) {
  StepCell cell;
  const std::optional<Ticks> onset = stepOnset(index, grid);
  if (key < 0 || key > 127 || !onset.has_value()) return cell;
  const Ticks start = *onset;
  const Ticks end = addClamped(start, grid.spacing);
  for (const Note& note : sequence.startingIn(start, end)) {
    if (note.key != key) continue;
    (note.start == start ? cell.on_grid : cell.off_grid).push_back(note);
  }
  return cell;
}

CommandPtr toggleStep(const Project& project, PatternId pattern, InstrumentId instrument,
                      int16_t key, int64_t index, const NoteGrid& grid) {
  const Pattern* owner = project.findPattern(pattern);
  const Instrument* voice = project.findInstrument(instrument);
  const std::optional<Ticks> onset = stepOnset(index, grid);
  if (owner == nullptr || voice == nullptr || key < 0 || key > 127 || !onset.has_value()) {
    return nullptr;
  }
  const auto sequence = owner->sequences.find(instrument);
  if (sequence != owner->sequences.end()) {
    StepCell cell = inspectStep(sequence->second, key, index, grid);
    if (cell.active()) return removeNotes(pattern, instrument, std::move(cell.on_grid));
  }
  return addNote(project, pattern, instrument, *onset, grid.spacing, key);
}

}  // namespace onebeat::model
