# UI-B-07 — Piano-roll pieces: keys, grid, velocity, toolbar

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational, painters) |
| **Dependencies** | UI-A-02; `ObDropdown`, `ObTransportButton` from UI-B-01 |
| **Reference** | workspace of `ui-files/screens/piano-roll.png` |
| **Target files** | `app/lib/src/features/piano_roll/` — `key_column.dart`, `note_grid.dart`, `velocity_lane.dart`, `pr_toolbar.dart`; tests `app/test/features/piano_roll/piano_roll_pieces_golden_test.dart` |
| **Estimate** | L |

## Context

The most painter-heavy cluster. An existing implementation lives in `lib/src/ui/piano_roll.dart` (store-bound, ~stage-3 look) — read it for painter techniques (paint objects allocated outside `paint()`, no per-frame allocation) but build fresh presentational widgets in `features/piano_roll/`. All coordinates flow from a shared `PrViewport{double ticksPerPx, double rowHeight, int firstVisibleTick, int topMidiNote}` so the three lanes align by construction.

## Scope

1. **Vm** (`note_grid.dart`): `PianoRollVm{List<PrNoteVm> notes, List<PrNoteVm> ghostNotes, int? playheadTick, PrViewport viewport, Set<int> selected}`; `PrNoteVm{int id, int startTick, int lengthTicks, int midiNote, double velocity}`.
2. **`PrKeyColumn`** — 75px piano keys per mockup: white/black key blocks, octave labels `C2..C6` on the C rows (mono micro).
3. **`PrNoteGrid`** — CustomPainter: row shading (in-scale vs out rows alternate per mockup), vertical beat/bar lines (`gridLine` / `gridLineStrong`), bar numbers row at top (1,2,3,4,5), notes as rounded 8px-high bars — active channel notes in the cyan note colour with white for selected, **ghost notes** in dim grey (see the grey bars in the mockup), accent playhead line.
4. **`PrVelocityLane`** — bottom lane: `VEL ▾` selector chip + one vertical stem per note, height ∝ velocity, colour matches the note (white when selected).
5. **`PrToolbar`** — header row: breadcrumb `Piano roll › Main Groove › Soft Keys` (note icon tile + dim separators), `PATTERN Main Groove ▾` dropdown, tool buttons (pencil active-accent, select, tag, eraser), `SCALE C min ▾`, `SNAP 1/4 ▾`, zoom `− +`, `✕ Back to playlist` button.
6. Interactions (presentational level only): tap empty grid → `onAddNote(tick, note)`, tap note → `onSelectNote(id)`, `onToolChange`, dropdown callbacks. No drag-resize yet.
7. Goldens: `pr_toolbar_dark` (1600×56) and `piano_roll_body_dark` (1600×900: key column + grid + velocity lane) reproducing the mockup phrase — transcribe ~20 notes + 6 ghost notes + selected note from the mockup into the fixture (approximate pitches are fine; keep them fixed).

## Acceptance criteria

- [ ] Body golden reads like the mockup: same lane proportions, row shading, ghost notes, playhead at bar 2.2, velocity stems.
- [ ] All paint objects allocated outside `paint()`; `shouldRepaint` compares vms.
- [ ] Painter unit test: tick↔x and note↔y round-trip through `PrViewport`.
- [ ] analyze + token lint + tests clean.

## Out of scope

Note editing gestures (drag/resize/marquee — D-03), scrolling physics, audition on key press, the browser panel (B-04) and chrome.
