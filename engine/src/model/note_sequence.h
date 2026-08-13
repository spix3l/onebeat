// The one note representation (OB-3-02 §2, DM-Q4, docs/project-format.md §5.2).
//
// There is exactly one of these. The step sequencer and the piano roll write
// the same array — a step *is* a quantised note — because two representations
// would need permanent reconciliation and would eventually disagree.
//
// Edit operations (insert/delete/move/resize/quantise/legato…) belong to
// OB-3-08. This header defines the storage, its ordering invariant, and the
// minimum needed to hold notes; nothing more, so that OB-3-08 can build the
// editing vocabulary without unpicking a guess made here.
#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

namespace onebeat::model {

// Musical time is integer ticks, never seconds and never floats (ADR-004 §3).
// Seconds appear for the first time in the flattener, where the time map turns
// ticks into frames.
using Ticks = int64_t;
inline constexpr Ticks TicksPerQuarter = 960;
inline constexpr Ticks TicksPerBarFourFour = TicksPerQuarter * 4;

// 14-bit, so MIDI-1 velocity v is exactly v * 129 and CLAP's 0..1 double is
// value / 16383. No rounding, no formatting rule, no drift.
using Velocity = uint16_t;
inline constexpr Velocity MaxVelocity = 16383;
inline constexpr Velocity DefaultVelocity = 100 * 129;

constexpr Velocity velocityFromMidi1(uint8_t midi) {
  return static_cast<Velocity>(midi * 129);
}
constexpr float velocityToUnit(Velocity velocity) {
  return static_cast<float>(velocity) / static_cast<float>(MaxVelocity);
}

struct Note {
  Ticks start = 0;   // relative to the pattern, never to a clip
  Ticks length = 0;  // > 0; a zero-length note is not a note
  int16_t key = 60;  // MIDI key 0..127
  Velocity velocity = DefaultVelocity;

  friend constexpr bool operator==(const Note&, const Note&) = default;
};

// The canonical order of docs/project-format.md §6: start, then key, then
// length. Sorting on write would be enough for the file, but keeping the vector
// sorted at all times is what lets the flattener and the piano roll binary-search
// a range instead of scanning.
constexpr bool noteOrderBefore(const Note& a, const Note& b) {
  if (a.start != b.start) return a.start < b.start;
  if (a.key != b.key) return a.key < b.key;
  return a.length < b.length;
}

class NoteSequence {
 public:
  const std::vector<Note>& notes() const { return notes_; }
  bool empty() const { return notes_.empty(); }
  size_t size() const { return notes_.size(); }

  // Inserts in order. Returns the index the note landed at.
  size_t insert(const Note& note) {
    const auto position = std::upper_bound(notes_.begin(), notes_.end(), note, noteOrderBefore);
    const auto index = static_cast<size_t>(position - notes_.begin());
    notes_.insert(position, note);
    return index;
  }

  void eraseAt(size_t index) {
    if (index < notes_.size()) notes_.erase(notes_.begin() + static_cast<ptrdiff_t>(index));
  }

  void clear() { notes_.clear(); }

  // Adopts an arbitrary vector — the load path, which then owes the ordering
  // invariant. Sorting here rather than trusting the file means a hand-edited
  // project cannot poison the binary searches downstream.
  void assignSorted(std::vector<Note> notes) {
    std::stable_sort(notes.begin(), notes.end(), noteOrderBefore);
    notes_ = std::move(notes);
  }

  bool isSorted() const { return std::is_sorted(notes_.begin(), notes_.end(), noteOrderBefore); }

  // The end of the last note, which is what "how long is this pattern really?"
  // means when a note runs past the pattern's declared length.
  Ticks contentEnd() const {
    Ticks end = 0;
    for (const Note& note : notes_) end = std::max(end, note.start + note.length);
    return end;
  }

 private:
  std::vector<Note> notes_;
};

}  // namespace onebeat::model
