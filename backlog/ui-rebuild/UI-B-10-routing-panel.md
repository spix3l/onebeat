# UI-B-10 — Routing panel pieces

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; `ObChip` from UI-B-01 |
| **Reference** | right panel of `ui-files/screens/routing-mixer.png`; also `ui-files/screens/routing-overview.png`, `routing-default.png` for secondary states |
| **Target files** | `app/lib/src/features/mixer/routing_panel.dart`; tests `app/test/features/mixer/routing_panel_golden_test.dart` |
| **Estimate** | M |

## Context

The "route by name, never by number" panel: plain-words routing for the selected track. Header `ROUTING — DRUMS BUS` / `in plain words`; sections FEEDS THIS TRACK, THIS TRACK FEEDS, SENDS, SIDECHAIN; a one-sentence explanation caption at the bottom.

## Scope

1. **Vm**: `RoutingPanelVm{String trackName, List<FeedVm> feeds /* (color, name, routeText: 'out 1 → Drums Bus') */, List<FeedVm> feedsInto /* Master → output, accent-tinted row */, List<SendVm> sends /* (name, value 0..1, valueText '0.42', pre: bool) */, SidechainVm? sidechain /* (sourceName, targetName, enabled, amountText '-6 dB') */, String caption}`.
2. **`ObRoutingPanel`** composing:
   - panel header row (micro-caps title left, dim right note),
   - section label (`FEEDS THIS TRACK` micro-caps + right dim mono `4 inputs`),
   - `FeedRow`: raised row, colour dot + name, right dim mono route text; the feeds-into variant with accent tint (Master row),
   - `SendRow`: `→ Reverb Send` label, horizontal slider (accent fill + white cap), mono value, `PRE`/`POST` tag (POST = accent outline),
   - `SidechainCard`: amber-outlined card — source dot+name+`sidechain source` caption, dashed amber connector arrow, right block `Drums Bus / compressor key input`, `Enabled` toggle (accent), `Amount −6 dB` mono,
   - plain-words caption paragraph (dim, 15px).
3. Callbacks: `onFeedTap`, `onSendChange(i,double)`, `onPrePostToggle(i)`, `onSidechainToggle`, `onSidechainAmount`.
4. Golden `routing_panel_dark` (~1370×1120) reproducing the Drums Bus mockup content exactly (4 feeds, Master, 2 sends 0.42 PRE / 0.18 POST, Sub Bass sidechain, the caption sentence).

## Acceptance criteria

- [ ] Golden comparable 1:1 with the mockup's right panel.
- [ ] Slider drag updates via callback (widget test); toggle renders both states.
- [ ] analyze + token lint + tests clean.

## Out of scope

The mixer strips (B-09), the overview graph screen (`routing-overview.png` — screens ticket C-05 decides whether it ships; its pieces are out of this ticket).
