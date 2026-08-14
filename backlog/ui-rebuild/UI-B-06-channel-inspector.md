# UI-B-06 — Channel inspector strip

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; `ObKnob`, `ObToggleChip`, `ObFxChip` from UI-B-01 |
| **Reference** | bottom strip (y≈1730..1930 in the 2× PNG) of `ui-files/screens/channel-rack.png` |
| **Target files** | `app/lib/src/features/channel_rack/channel_inspector.dart`; tests `app/test/features/channel_rack/channel_inspector_golden_test.dart` |
| **Estimate** | M |

## Context

When a channel is selected in the rack, a full-width inspector strip appears at the bottom of the workspace: identity, waveform, mix controls, FX chain, routing, and a mini keyboard.

## Scope

1. **`ChannelInspectorVm`**: `{String name, String subtitle /* 'EP · channel 5' */, Color color, List<double> waveform /* normalized samples */, double vol /* shown as '78 VOL' */, String pan /* '· C PAN' */, bool muted, bool soloed, List<FxVm> fx /* (name, colorDot, active) */, String route /* 'M1 · Music' */}`.
2. **`ObChannelInspector`** left→right per mockup:
   - 48px rounded icon tile in the channel colour (note glyph),
   - name (semibold) + dim subtitle,
   - waveform preview: accent-coloured mirrored bars from `waveform` (custom painter; deterministic from vm data — no randomness),
   - vol knob with mono value `78` + `VOL` micro label; pan knob with `· C` + `PAN`,
   - `M` / `S` toggle chips with their small round indicator dots below,
   - FX chain: `Chorus` (active, accent outline), `EQ 4`, `Reeverb 2` chips + dim `+` tile,
   - route arrow + `M1 · Music` mono chip,
   - mini piano keyboard (~200px wide, 2 octaves, white/black keys, custom painter).
3. Callbacks: `onVol`, `onPan`, `onMute`, `onSolo`, `onFxTap(i)`, `onAddFx`, `onRouteTap`, `onKeyPress(midiNote)` (tap only).
4. Golden `channel_inspector_dark` at 1600×120 with the Soft Keys fixture (matches mockup content).

## Acceptance criteria

- [ ] Strip matches the mockup region; waveform drawn from fixture data.
- [ ] Keyboard hit-test maps x→note and fires `onKeyPress` (widget test).
- [ ] analyze + token lint + tests clean.

## Out of scope

Audio preview, FX reordering, opening plugin windows.
