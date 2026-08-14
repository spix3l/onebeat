# UI-C-03 — Piano roll screen

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-07 (UI-C-01 for full-frame golden) |
| **Reference** | `ui-files/screens/piano-roll.png` — open it before writing code |
| **Target files** | `app/lib/src/features/piano_roll/piano_roll_screen.dart`, `piano_roll_screen_vm.dart`; fixture `app/test/features/piano_roll/fixture.dart`; tests `app/test/features/piano_roll/piano_roll_screen_golden_test.dart` |
| **Estimate** | M |

## Scope

1. **`PianoRollScreenVm`**: `PrToolbarVm` (breadcrumb `Piano roll › Main Groove › Soft Keys`, pattern `Main Groove`, tool = pencil, scale `C min`, snap `1/4`), `PianoRollVm` (from UI-B-07) and layout params.
2. **`PianoRollScreen`** — workspace-only: toolbar → body (`PrKeyColumn` + `PrNoteGrid` sharing one viewport) → `PrVelocityLane`, proportions per mockup (velocity lane ~140px).
3. Fixture: the UI-B-07 phrase transcription (same file if practical — import, don't duplicate), playhead at bar 2.2, one selected note (white).
4. Callbacks bubble: `onAddNote`, `onSelectNote`, `onToolChange`, `onSnapChange`, `onScaleChange`, `onBackToPlaylist`, `onZoom`.
5. Goldens: `piano_roll_screen_dark` (workspace 1520×880) and `piano_roll_full_dark` (in `ShellScreen`, PIANO rail active, browser showing the piano-roll variant tree with `Soft Keys` selected) vs the mockup.

## Acceptance criteria

- [ ] Full-frame golden comparable 1:1 with `screens/piano-roll.png`.
- [ ] Grid/keys/velocity lanes stay aligned when the surface is resized (widget test at two sizes asserting shared viewport maths).
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Editing gestures, scroll/zoom behaviour (D-03).
