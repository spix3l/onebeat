// Channel rack fixtures (UI-B-05/06) — the eight lanes of
// `screens/channel-rack.png`, with their step patterns read off the PNG.
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';

/// The step column the transport is sitting on in the mockup (zero-based):
/// the white ring is around the seventh cell.
const int demoPlayingStep = 6;

/// Builds a sixteen-step pattern from its lit positions, 1-based, the way a
/// drummer would count them.
List<StepVm> stepsAt(List<int> lit, {Map<int, double> velocities = const {}}) {
  return <StepVm>[
    for (int i = 1; i <= 16; i++)
      lit.contains(i)
          ? StepVm(on: true, velocity: velocities[i] ?? 1)
          : const StepVm.off(),
  ];
}

/// The eight lanes, in the mockup's order, with the patterns it draws.
final List<RackRowVm> demoRackRows = <RackRowVm>[
  RackRowVm(
    name: 'Kick 808',
    type: 'Sampler',
    color: channelColors[0],
    steps: stepsAt(<int>[1, 5, 9, 13]),
    vol: 0.78,
    pan: 0.5,
    route: '→ D1',
  ),
  RackRowVm(
    name: 'Snare',
    type: 'Sampler',
    color: channelColors[5],
    steps: stepsAt(<int>[5, 13]),
    vol: 0.7,
    pan: 0.5,
    route: '→ D1',
  ),
  RackRowVm(
    name: 'Hats',
    type: 'Synth',
    color: channelColors[1],
    // The one lane in the mockup with velocity shading: eighths that lean on
    // the beat and back off between them.
    steps: stepsAt(
      <int>[1, 3, 5, 7, 9, 11, 13, 15],
      velocities: <int, double>{3: 0.45, 7: 0.45, 11: 0.45, 15: 0.45},
    ),
    vol: 0.62,
    pan: 0.55,
    route: '→ D1',
  ),
  RackRowVm(
    name: 'Sub Bass',
    type: 'Reese CLAP',
    color: channelColors[2],
    steps: stepsAt(<int>[1, 4, 7, 10, 13]),
    vol: 0.82,
    pan: 0.5,
    route: '→ B1',
  ),
  RackRowVm(
    name: 'Soft Keys',
    type: 'EP',
    color: channelColors[4],
    steps: stepsAt(<int>[1, 6, 11, 16]),
    vol: 0.6,
    pan: 0.5,
    route: '→ M1',
    selected: true,
  ),
  RackRowVm(
    name: 'Pluck Lead',
    type: 'Synth',
    color: channelColors[3],
    steps: stepsAt(<int>[2, 7, 12, 15]),
    vol: 0.66,
    pan: 0.44,
    route: '→ M1',
  ),
  RackRowVm(
    name: 'Shaker',
    type: 'Sampler',
    color: channelColors[6],
    steps: stepsAt(<int>[]),
    vol: 0.5,
    pan: 0.6,
    route: '→ D1',
    powered: false,
  ),
  RackRowVm(
    name: 'Open Hat',
    type: 'Sampler',
    color: channelColors[7],
    steps: stepsAt(<int>[3, 7, 11, 15]),
    vol: 0.58,
    pan: 0.5,
    route: '→ D1',
  ),
];

/// The lane width `components/channel-row.png` draws: the left block, sixteen
/// columns, the two knobs and the route chip, at the export's 2× scale.
const double demoRackRowWidth = 919;
