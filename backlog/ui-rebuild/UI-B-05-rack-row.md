# UI-B-05 — Channel rack row + step grid + rack toolbar

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; `ObKnob`, `ObDropdown`, `ObChip` from UI-B-01 |
| **Reference** | `ui-files/components/channel-row.png` (919×46 isolated row); workspace of `ui-files/screens/channel-rack.png` |
| **Target files** | `app/lib/src/features/channel_rack/rack_row.dart`, `rack_toolbar.dart`; tests `app/test/features/channel_rack/rack_row_golden_test.dart` |
| **Estimate** | M |

## Context

The heart of the rack screen. The old `channel_rack.dart` is store-bound; this is its presentational replacement. A row is 46px: power, colour chip, name block, 16 step cells grouped 4×4, vol/pan knobs, send chip.

## Scope

1. **`RackRowVm`**: `{String name, String type, Color color, bool powered, List<StepVm> steps, double vol, double pan, String route, bool selected}` with `StepVm{bool on, double velocity}`.
2. **`ObRackRow`** widget, matching `components/channel-row.png` left→right:
   - power toggle (accent ring icon when on, dim when off — see Shaker row off in the mockup),
   - 22px rounded colour chip (channel colour),
   - name block: name (semibold 15) over dim type caption,
   - step grid: 16 cells ~34×34 r8; off = `surfaceWell`, on = accent fill (velocity may modulate brightness), extra gap every 4 cells; **playing column** = white outline ring (see column 9 in the screen mockup); cells fire `onStepTap(i)`,
   - `ObKnob` ×2 (vol, pan),
   - route chip `→ D1` (mono).
   - `selected` state: full-row shade + left accent edge (see Soft Keys row).
3. **`ObRackToolbar`** (`rack_toolbar.dart`) — the row above the grid: `CHANNEL TYPE Sampler ▾`, `GROUP All ▾`, `SNAP 1/4 ▾` dropdowns, three icon buttons (sliders, accent `+`, waveform), right mono caption `16 steps · loop`.
4. **`ObRackHeader`** — the column-caption row: `PWR  CHANNEL  1 2 3 4 … 13 14 15 16  VOL PAN SEND` in dim micro-caps/mono, aligned to the row geometry.
5. **`ObRackFooter`** — the "Drop a sample from the browser, or **Add channel** to grow the rack" hint row with `+` tile and `⌘A` right tag.
6. Goldens: `rack_row_dark` (a board of 4 rows: normal-on-pattern, selected, powered-off, velocity-varied) and `rack_toolbar_dark` (toolbar + header + footer stacked).

## Acceptance criteria

- [ ] Row board indistinguishable in structure/colour from `components/channel-row.png` and screen rows.
- [ ] Playing-column ring renders from a vm `playingStep` value passed to the row, off-screen for `null`.
- [ ] Step tap, knob change, row tap callbacks proven with a widget test.
- [ ] analyze + token lint + tests clean.

## Out of scope

Drag-painting steps, right-click velocity gesture (D-02), scrolling/virtualisation, the bottom inspector (UI-B-06), screen assembly (C-02).
