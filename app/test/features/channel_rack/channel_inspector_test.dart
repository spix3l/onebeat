// Channel inspector (UI-B-06): the golden of the Soft Keys strip from
// `screens/channel-rack.png`, plus the interactions the golden cannot show.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/channel_rack/channel_inspector.dart';

import '../../support/ui_harness.dart';

/// The mockup's three-lobe envelope with a short tail, as a closed form so the
/// preview is identical on every machine and every run: three swells of
/// falling height, ridden on a low floor.
List<double> demoWaveform() {
  const int count = 96;
  return <double>[for (int i = 0; i < count; i++) _lobe(i / (count - 1))];
}

double _lobe(double t) {
  double amplitude = 0.12;
  // (centre, width, height) of each swell, read off the mockup's preview.
  const List<(double, double, double)> lobes = <(double, double, double)>[
    (0.16, 0.13, 0.88),
    (0.44, 0.10, 0.66),
    (0.68, 0.11, 1.0),
    (0.88, 0.05, 0.42),
  ];
  for (final (double centre, double width, double height) in lobes) {
    final double d = (t - centre) / width;
    amplitude = math.max(amplitude, height * math.exp(-d * d));
  }
  return amplitude;
}

final ChannelInspectorVm demoInspector = ChannelInspectorVm(
  name: 'Soft Keys',
  subtitle: 'EP · channel 5',
  color: channelColors[4],
  waveform: demoWaveform(),
  vol: 0.78,
  volText: '78',
  pan: 0.5,
  panText: '· C',
  fx: <FxVm>[
    FxVm(name: 'Chorus', color: channelColors[4], active: true),
    FxVm(name: 'EQ 4', color: channelColors[2]),
    FxVm(name: 'Reeverb 2', color: channelColors[5]),
  ],
  route: 'M1 · Music',
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the Soft Keys strip renders as the golden', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObChannelInspector(key: const Key('inspector'), vm: demoInspector),
      size: Size(1600, tokens.size.inspectorHeight),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('inspector')),
      uiGolden('channel_inspector'),
    );
  });

  testWidgets('mute, solo and route taps report themselves', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObChannelInspector(
        vm: demoInspector,
        onMute: () => fired.add('mute'),
        onSolo: () => fired.add('solo'),
        onRouteTap: () => fired.add('route'),
      ),
      size: Size(1600, tokens.size.inspectorHeight),
    );
    await tester.tap(find.text('M'));
    await tester.tap(find.text('S'));
    await tester.tap(find.text('M1 · Music'));
    expect(fired, <String>['mute', 'solo', 'route']);
  });

  testWidgets('the keyboard maps x to a note and reports it', (
    WidgetTester tester,
  ) async {
    final List<int> notes = <int>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObChannelInspector(vm: demoInspector, onKeyPress: notes.add),
      size: Size(1600, tokens.size.inspectorHeight),
    );
    final Rect keys = tester.getRect(find.byType(MiniKeyboard));
    final double whiteWidth = keys.width / 14;
    // The first white key is middle C; the eighth is the C an octave up.
    await tester.tapAt(Offset(keys.left + whiteWidth * 0.5, keys.center.dy));
    await tester.tapAt(Offset(keys.left + whiteWidth * 7.5, keys.center.dy));
    // A black key sits over the boundary between the first two white keys and
    // wins there, because that is what a finger expects.
    await tester.tapAt(
      Offset(keys.left + whiteWidth, keys.top + keys.height * 0.2),
    );
    expect(notes, <int>[60, 72, 61]);
  });

  testWidgets('the inspector omits the waveform and FX controls', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final ChannelInspectorVm flat = ChannelInspectorVm(
      name: 'Silence',
      subtitle: 'Sampler · channel 1',
      color: channelColors[0],
      waveform: const <double>[0, 0, 0],
      vol: 0.5,
      volText: '50',
      pan: 0.5,
      panText: '· C',
      fx: const <FxVm>[],
      route: 'M1 · Music',
    );
    await pumpUi(
      tester,
      ObChannelInspector(vm: flat),
      size: Size(1600, tokens.size.inspectorHeight),
    );
    expect(find.text('Chorus'), findsNothing);
    expect(find.text('EQ 4'), findsNothing);
    expect(find.text('+'), findsNothing);
    expect(find.byType(MiniKeyboard), findsOneWidget);
  });
}
