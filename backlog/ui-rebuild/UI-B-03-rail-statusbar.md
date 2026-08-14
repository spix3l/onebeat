# UI-B-03 — Left rail + status bar

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; uses `ObRailButton` from UI-B-01 (if not merged yet, build against a local private copy and swap on rebase) |
| **Reference** | left 80px and bottom 28px of `ui-files/screens/channel-rack.png`, `piano-roll.png`, `routing-mixer.png` |
| **Target files** | `app/lib/src/features/shell/side_rail.dart`, `status_bar.dart`; tests `app/test/features/shell/rail_status_golden_test.dart` |
| **Estimate** | S |

## Scope

1. **`ObSideRail`** — 80px wide, `surfaceSunken`, right hairline: vertical stack of `ObRailButton`s — PLAYLIST, CHANNELS, PIANO, MIXER, PACKS (icons: grid, circled ?, note, sliders, folder) with a hairline separator before PACKS. Vm: `List<RailItemVm{icon, label}>`, `activeIndex`, `onSelect(int)`. Active item = accent pill exactly as mockups (CHANNELS active on channel-rack, PIANO on piano-roll, MIXER on routing-mixer).
2. **`ObStatusBar`** — 28px, `surfaceSunken`, top hairline: status dot (green/amber/danger), bold primary text (`Ready`, `Playing`, `Inspecting Drums Bus`), dim `·`-separated detail (`Main Groove · 8 channels · 16 steps`), right-aligned dim hint (`Double-click a channel to open its piano roll`, `⌘R routing · ⇧⌘R overview`). Vm: `{StatusTone tone, String primary, List<String> details, String? rightHint}`.
3. Goldens: `side_rail_dark` (all five items, one active) and `status_bar_dark` (two stacked examples: Ready-state and Playing-state per fixtures).

## Acceptance criteria

- [ ] Matches mockup strips; labels micro-caps ~8px on the rail; status text mixes bold primary + dim details.
- [ ] Vm-driven only; callbacks fire on tap (widget test, not golden).
- [ ] analyze + token lint + tests clean.

## Out of scope

Actual view switching (C-01), keyboard shortcuts.
