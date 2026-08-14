# UI-B-01 — Core controls: knob, buttons, dropdown, chips, search

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02 |
| **Reference** | `ui-files/components/knob.png`, `rail-button.png`, `transport-btn.png`, `dropdown.png`, `fx-chip.png`; usage in `ui-files/screens/channel-rack.png` |
| **Target files** | `app/lib/src/ui_kit/knob.dart`, `buttons.dart`, `dropdown.dart`, `chips.dart`, `search_field.dart`; tests in `app/test/ui_kit/core_controls_golden_test.dart` |
| **Estimate** | M |

## Context

The smallest reusable atoms, used by almost every screen. Isolated component mockups exist for each. Existing widgets in `lib/src/ui/controls.dart` may be similar — **do not modify or import them**; these are their replacements and live in `ui_kit/`.

## Scope

All widgets: presentational, tokens only, `(data, callbacks)` constructors, no stores.

1. **`ObKnob`** — 26×26 circular knob (`components/knob.png`): ring on `surfaceWell`, pointer line rotating with `value` (0..1), optional accent-tinted variant, optional tiny label below (`VOL`, `PAN` style, MartianMono micro caps). Callback `onChanged(double)` via vertical drag; no fancy gesture work beyond that.
2. **`ObTransportButton`** — 32×32 rounded square (`components/transport-btn.png`): icon child, states rest / hover / active(accent fill, e.g. Play in the mockups) / toggled.
3. **`ObRailButton`** — 42×44 icon+micro-label stack (`components/rail-button.png`): rest (dim icon+label) and active (accent fill, white icon) as on the left rail of `screens/channel-rack.png`.
4. **`ObDropdown`** — 156×26 field (`components/dropdown.png`): micro-caps prefix label (`SNAP`, `SCALE`, `GROUP`…), value text, chevron; opens a token-styled popover menu of items (plain `List<String>` + `onSelected`). Menu styling per the layouts popover in `screens/workspace-window.png` (raised panel, radius, hairline, checked row accent).
5. **`ObChip`** family (`chips.dart`):
   - `ObFxChip` (`components/fx-chip.png`, 67×26): colour dot + label, used for FX chain entries (`Chorus`, `EQ 4`, `Reeverb 2`) and route chips (`→ D1`, mono font variant).
   - `ObToggleChip`: `M` / `S` mute-solo squares with on-colours (danger for M, amber for S per `screens/export-audio.png` inspector).
   - `ObTagChip`: small counter/badge (`4 tracks`, `12`) in mono.
6. **`ObSearchField`** — rounded search input with magnifier icon and hint (`Search samples, presets…`) plus the compact icon-only round variant (top-right of rack header) and the `⌘K` shortcut tag variant (`Search actions ⌘K` in the top bar). Static text rendering is enough; a real `TextField` styled to match is fine but not required to be functional.
7. Golden tests: one board-style golden laying out every widget in every state on a `surfaceSunken` background (like a storybook sheet), named `core_controls_dark`.

## Acceptance criteria

- [ ] Each widget matches its component PNG at 1:1 size (PNGs are 2×: on-screen size = px/2).
- [ ] All states listed above visible on the golden board.
- [ ] No imports from `engine/`, stores, or old `ui/*.dart` files.
- [ ] analyze + token lint + `flutter test` clean; goldens committed.

## Out of scope

Keyboard focus, tooltips, drag-to-reorder. The old `controls.dart` stays untouched.
