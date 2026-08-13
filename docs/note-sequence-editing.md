# NoteSequence editing contract

OB-3-08 keeps one note representation. Both the channel rack and piano roll
query and edit `model::NoteSequence`; editor state may hold a selection, but it
must not hold a second sequence.

## Time and selection

- Musical time is signed 64-bit integer ticks at 960 PPQ.
- `NoteSequence` is canonically ordered by onset, key, then length. Overlaps are
  preserved, including the same pitch; playback cuts the earlier voice at the
  later same-pitch onset without rewriting the notes.
- `startingIn([start, end))` is the allocation-free painting query for onsets.
  `selectNotesInRange` includes a long note beginning before the range when it
  still sounds inside it. Key bounds are inclusive.
- Lasso geometry stays in the UI. It is supplied to `selectNotes` as a
  predicate, keeping canvas coordinates out of the model.

## Grid behavior

`NoteGrid` has a positive spacing and an origin. Snapping chooses the nearest
grid line; an exact half chooses the later line. Moving a group snaps its
earliest onset and applies one delta to every selected note, preserving the
selection's internal timing. Quantise moves each onset toward its nearest line:

```
new onset = old onset + round((nearest line - old onset) * strength)
```

Strength is in `[0, 1]`. Resize snaps note ends and never produces a length less
than one tick. Transpose clamps the group delta so every key remains in 0–127.
Velocity is 14-bit and set/scale operations clamp to 0–16383.

## Step view (DM-Q4)

A rack cell `(key, index)` covers one grid interval. A note of that key whose
onset equals the interval start makes the step active, even if its length or
velocity was changed in the piano roll. Other same-key onsets inside the cell
are `off_grid` indicators.

Toggling an inactive step inserts one note at the exact onset with grid-length
duration and the instrument's default velocity. Toggling an active step removes
only notes at that exact onset. It never removes off-grid notes. This makes a
rack toggle and a piano-roll edit round-trip through the same sequence without
reconciliation.

## Undo and scale

Every mutation returns an OB-3-03 command. Replacement commands coalesce an
`A → B`, `B → C` gesture into one `A → C` history entry; explicit command-bus
transactions remain available to bracket a gesture. Batch replacement uses
indexed removal and one final sort, avoiding repeated vector erasure.

The stress acceptance test builds 10,000 notes, performs a visible-range query,
and quantises the full selection. Ordinary builds require the combined work to
fit the 16.667 ms frame budget; sanitizer builds run the same correctness path
without asserting wall-clock time.

On 13 August 2026, the Debug build on the development Apple Silicon Mac measured
0.09 ms for the range query and 1.11 ms for the full 10,000-note edit (1.20 ms
combined). The executable test remains the authority because CI hardware and
future implementations will differ.
