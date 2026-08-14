# UI-B-02 — Top chrome: menu bar, transport, readouts, export

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02 (UI-B-01 helpful but not required — duplicate nothing, coordinate via imports once merged) |
| **Reference** | top ~90px of `ui-files/screens/channel-rack.png` (any screen shows the same chrome); `ui-files/components/shell.png` |
| **Target files** | `app/lib/src/features/shell/menu_bar.dart`, `transport_bar.dart`, `readouts.dart`; tests `app/test/features/shell/top_chrome_golden_test.dart` |
| **Estimate** | M |

## Context

Two stacked bars sit on every screen: a 24px system/menu bar and a ~68px transport bar. They are pure chrome — every value comes in via a vm.

## Scope

1. **`ObMenuBar`** (`menu_bar.dart`) — 24px tall, `surfaceSunken`: app dot + `OneBeat` wordmark, menu items `File Edit Pattern View Tools Mixer▾ Window Help` (active item `Mixer` gets a raised pill per the mockup), right-aligned mono clock (`14:02`, fixture value). Vm: `ObMenuBarVm{List<String> menus, int? activeIndex, String clock}` + `onMenuTap(int)`.
2. **`ObTransportBar`** (`transport_bar.dart`) — full-width row on `surfaceSunken`, left to right per mockup:
   - traffic lights (three 12px dots: danger/amber/green),
   - app tile (28px rounded accent square) + title block (`ONEBEAT` caps + `v0.3 SEQUENCES` micro),
   - transport cluster: undo, redo, play (active accent), stop, loop — `ObTransportButton`s,
   - readout boxes (see 3),
   - action search field (`Search actions ⌘K`),
   - right group: vertical master meter sliver (three-colour stack per mockup) + primary `Export` button (accent fill, download icon).
   Vm carries: title, subtitle, playing/looping flags, bpm text, sig text, position text, meter levels (L/R 0..1), search hint.
3. **`readouts.dart`** — the dark inset boxes with mono numerals: `ObReadout(value: '124.00', unit: 'BPM')`, `ObReadout(value: '4/4', unit: 'SIG')`, `ObReadout(value: '02:01:218', unit: 'BAR · BEAT · TICK')`. Height 44, `surfaceSunken` fill inside a hairline, MartianMono numerals ~21px, dim micro unit label.
4. Golden `top_chrome_dark` at 1600×92 with the fixture values (UI-A-02) — must be indistinguishable in structure from the top of any screen mockup.

## Acceptance criteria

- [ ] Layout, order and proportions match the mockup strip; numerals in MartianMono; unit labels micro-caps.
- [ ] Play shows the accent-active state; Export renders the accent button with icon.
- [ ] All strings/values injected via vm (no defaults harvested from real state).
- [ ] analyze + token lint + tests clean; golden committed.

## Out of scope

Menu popups and their contents (Phase D wires the existing `app_menu_bar.dart` actions), meter animation, actual search palette.
