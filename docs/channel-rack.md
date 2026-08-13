# Channel rack contract

OB-3-09 is the first model-backed editor in the app. It edits the current
pattern's `NoteSequence` values through ABI 1.6; there is no Dart-side shadow
sequence and the old Stage 1 demo pattern is no longer installed at startup.

## Design source

The implementation was checked against the Pen `onebeat-shell.html` frame from
the maintainer's shared document on 13 August 2026. The rack follows that
surface's compact dark workstation language: panel/deep surfaces, hairline
separators, square-ish dense controls, one violet selection role, fixed
instrument headers and a horizontally scrollable work canvas. It deliberately
does not introduce cards, gradients, floating panels, or a second accent.

## Editing and visibility

- A one-bar `Pattern 1` and looping placement are created for a new engine. Its
  base sixteenth grid produces 16 steps; visible 16/32/64 controls resize it.
- Each row may show 1/8, 1/16, or 1/32 cells. That divisor is presentation
  state; notes remain integer-tick `NoteSequence` records.
- Click toggles. Drag paints or erases consistently and brackets all crossed
  cells in one command-bus transaction, so one undo reverses the gesture.
- Option-drag or right-drag paints 14-bit velocity. Every active cell shows its
  velocity as a bottom fill, and the selected cell has visible −/+ velocity
  controls, so the gesture has no right-click-only capability.
- By default, rows with notes plus explicitly added empty rows are shown.
  `SHOW ALL` reveals every project instrument. `+ ADD INSTRUMENT` can reveal an
  existing project instrument or open the plug-in browser.
- `− PAT` removes only that sequence from the current pattern. `DELETE` is a
  separate two-step project-global action whose accessibility label states the
  affected notes and patterns.
- Notes that do not map to the row's step grid are counted as `OFF` and remain
  untouched. The rack points the user to the piano roll rather than hiding or
  quantising them.

## Swing and playback

Pattern swing is persisted as a value from 0 to 1. Flattening delays exact odd
sixteenth onsets by `swing × 120 ticks`; even onsets and deliberately off-grid
notes do not move. The native golden test fixes the 50% result at
`0, 300, 315, 480, 780` ticks and checks a stable schedule hash.

The cursor reads the existing seqlock snapshot. The rack widget does not rebuild
at playback rate: the controller is connected directly to the custom painter's
repaint channel, and its paints are allocated once with the painter rather than
inside `paint()`.

## Interaction walkthrough (FR-UX-17 / FR-UX-21)

| Action | Visible path | Alternate gesture | Undo unit |
|---|---|---|---|
| Toggle step | Click a step cell | — | One click |
| Paint / erase | Drag across cells | — | One drag |
| Set velocity | Select cell, then visible `VELOCITY −/+` | Option-drag or right-drag | One drag |
| Resize pattern | `STEPS 16 / 32 / 64` | — | One click |
| Change row grid | Visible `1/8`, `1/16`, or `1/32` button | — | Presentation only |
| Change swing | Visible `SWING −/+` | — | Coalesced edits |
| Add row | `+ ADD INSTRUMENT` | — | Presentation only until a note is added |
| Remove from pattern | `− PAT` on the row | — | One click |
| Delete instrument | Select row, `DELETE`, then `DELETE?` | — | One confirmed action |
| Undo / redo | Visible toolbar buttons | Project command surface | One command or gesture |

## Verification

- ABI tests cover the default pattern, 16-step row, paint transaction,
  velocity, swing, remove/undo, per-row divisor, and 32-step pattern length.
- `rack_store_test.dart` drives the editor through a fake `RackClient`, proving
  a crossed cell is painted once and a drag commits as one transaction.
- `channel_rack_dark.png` is the first Stage 3 per-theme golden.
- The dense painter benchmark renders 8 × 64 cells and guards a fraction of an
  8.33 ms frame budget. A real 120 Hz display profile remains the field gate;
  this machine's panel cannot manufacture that evidence.
