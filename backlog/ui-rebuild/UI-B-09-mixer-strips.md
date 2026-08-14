# UI-B-09 — Mixer strips: mini, fader, master

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; `ObToggleChip` from UI-B-01 |
| **Reference** | left panel of `ui-files/screens/routing-mixer.png` (mini strips with tall meters); floating window in `ui-files/screens/workspace-window.png` (fader strips) |
| **Target files** | `app/lib/src/features/mixer/` — `mixer_strip.dart`, `strip_meter.dart`; tests `app/test/features/mixer/mixer_strips_golden_test.dart` |
| **Estimate** | M |

## Context

Two strip variants exist in the mockups: the **meter strip** (routing screen: narrow column, colour bar under the name, M/S/route-dot, tall green→amber→red meter, `→ Drums` route label at the bottom) and the **fader strip** (detached mixer window: name, M/S/dot, long fader with white cap, route label).

## Scope

1. **Vm**: `MixerStripVm{String name, Color color, bool muted, bool soloed, bool routeActive, double level /* 0..1 meter */, double fader /* 0..1 pos */, String route /* '→ Drums', '0.0 dB' for master */, bool selected, bool isMaster, bool sidechainIn}`.
2. **`StripMeter`** — vertical meter painter: gradient stack `meterLow→meterMid→meterHigh` over a `meterTrack` well, deterministic from `level`.
3. **`ObMixerStrip.meter(...)`** — ~57px wide: name (9px), colour bar, `M S ●` row (dot = route indicator; accent-active on Drums Bus/MASTER in the mockup), `↓ SC in` tag when `sidechainIn`, tall meter, bottom mono route label. Selected = accent outline + tinted fill (Drums Bus in mockup).
4. **`ObMixerStrip.fader(...)`** — ~135px wide for the floating window: name centered, `M S ●`, vertical fader track with white cap at `fader` plus meter colour below the cap (per mockup), bottom route label; selected = accent outline (Drums Bus).
5. Callbacks: `onTap`, `onMute`, `onSolo`, `onFader(double)` (vertical drag on fader variant).
6. Goldens: `mixer_meter_strips_dark` reproducing the 8 strips of the routing mockup (Kick 808…MASTER, Drums Bus selected w/ SC in) and `mixer_fader_strips_dark` reproducing the 6 strips of the floating-window mockup.

## Acceptance criteria

- [ ] Both strip boards comparable 1:1 with their mockup regions, including selection and `SC in` tag.
- [ ] Meter painter allocation-free in `paint()`.
- [ ] analyze + token lint + tests clean.

## Out of scope

The routing panel (B-10), window chrome (B-11), meter animation, drag-to-route.
