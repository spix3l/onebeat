# UI-D-03 — Wire piano roll

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-03, UI-D-01 |
| **Reference** | existing `app/lib/src/ui/piano_roll_store.dart`, old `piano_roll.dart` (behaviour source of truth), tickets OB-3-10, OB-3-08 |
| **Target files** | `app/lib/src/features/piano_roll/piano_roll_store.dart` + `piano_roll_binding.dart`; tests `app/test/features/piano_roll/piano_roll_binding_test.dart` |
| **Estimate** | L |

## Scope

1. **Store port + `PianoRollBinding`**: port the old `piano_roll_store.dart` into `features/piano_roll/piano_roll_store.dart` (same commands/undo/snapshot behaviour — the old file is reference only, deleted in D-09); binding maps store state → `PianoRollScreenVm` (notes, ghosts, selection, scale shading, snap, viewport, playhead from snapshots); callbacks → store commands.
2. Gesture layer on top of the presentational grid (inside `features/piano_roll/`, or opt-in controller): add note (pencil), select/marquee, move, resize, delete, velocity edit in the lane, pan/zoom, snap behaviour — port the interactions the old `piano_roll.dart` implements; one undo entry per gesture.
3. Toolbar wiring: pattern switch, tool switch, scale/snap dropdowns, back-to-playlist navigation (returns to the playlist workspace via D-01's switcher), zoom.
4. Keyboard audition on key-column press if the old path supports it.
5. Tests against `fake_stage3_client.dart`: add/move/resize round-trips, selection, scale change re-shades, snap applied.

## Acceptance criteria

- [ ] Feature parity with the old piano roll (walk OB-3-10's acceptance list); editing an 8-bar phrase works against the real engine.
- [ ] Paint cost stays within the stage-3 paint-cost test bounds (port/extend `stage3_paint_cost_test.dart` to the new painters).
- [ ] Suite green; analyze + token lint clean; C-03 goldens unchanged.

## Out of scope

Deleting old `piano_roll.dart` (D-09).
