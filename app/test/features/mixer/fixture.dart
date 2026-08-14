// Mixer fixtures (UI-B-09) — the eight docked strips of
// `screens/routing-mixer.png` and the four faders of the detached window in
// `screens/workspace-window.png`.
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/mixer/mixer_strip.dart';

/// The docked mixer, left to right. Drums Bus is the selected strip the
/// routing panel is describing, and the one being ducked.
final List<MixerStripVm> demoMeterStrips = <MixerStripVm>[
  MixerStripVm(
    name: 'Kick 808',
    color: channelColors[0],
    route: '→ Drums',
    level: 0.62,
  ),
  MixerStripVm(
    name: 'Snare',
    color: channelColors[5],
    route: '→ Drums',
    level: 0.55,
  ),
  MixerStripVm(
    name: 'Hats',
    color: channelColors[1],
    route: '→ Drums',
    level: 0.48,
  ),
  MixerStripVm(
    name: 'Clap',
    color: channelColors[7],
    route: '→ Drums',
    level: 0.41,
  ),
  MixerStripVm(
    name: 'Drums Bus',
    color: channelColors[4],
    route: '→ Master',
    level: 0.7,
    routeActive: true,
    selected: true,
    sidechainIn: true,
  ),
  MixerStripVm(
    name: 'Sub Bass',
    color: channelColors[2],
    route: '→ Bass',
    level: 0.66,
  ),
  MixerStripVm(
    name: 'Soft Keys',
    color: channelColors[4],
    route: '→ Music',
    level: 0.5,
  ),
  MixerStripVm(
    name: 'MASTER',
    color: channelColors[7],
    route: '0.0 dB',
    level: 0.74,
    routeActive: true,
    isMaster: true,
  ),
];

/// The detached window's faders. Same tracks, different shape — and the
/// window's own selection is still Drums Bus.
final List<MixerStripVm> demoFaderStrips = <MixerStripVm>[
  MixerStripVm(
    name: 'Kick 808',
    color: channelColors[0],
    route: '→ Drums',
    fader: 0.68,
  ),
  MixerStripVm(
    name: 'Snare',
    color: channelColors[5],
    route: '→ Drums',
    fader: 0.6,
  ),
  MixerStripVm(
    name: 'Drums Bus',
    color: channelColors[4],
    route: '→ Master',
    fader: 0.74,
    routeActive: true,
    selected: true,
  ),
  MixerStripVm(
    name: 'Sub Bass',
    color: channelColors[2],
    route: '→ Bass',
    fader: 0.55,
  ),
  MixerStripVm(
    name: 'Soft Keys',
    color: channelColors[4],
    route: '→ Music',
    fader: 0.42,
  ),
  MixerStripVm(
    name: 'MASTER',
    color: channelColors[7],
    route: '0.0 dB',
    fader: 0.72,
    routeActive: true,
    isMaster: true,
  ),
];
