// Mixer strips (UI-B-09): one golden with a board per variant, plus the
// callbacks and the painter contract the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/mixer/mixer_strip.dart';
import 'package:onebeat/src/features/mixer/strip_meter.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

class _Board extends StatelessWidget {
  const _Board({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: tokens.size.mixerStripGap),
          children[i],
        ],
      ],
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the docked meter and detached fader boards render as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      Row(
        key: const Key('boards'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 400,
            child: _Board(
              key: const Key('meters'),
              children: <Widget>[
                for (final MixerStripVm strip in demoMeterStrips)
                  ObMixerStrip.meter(vm: strip),
              ],
            ),
          ),
          SizedBox(
            width: 680,
            child: _Board(
              key: const Key('faders'),
              children: <Widget>[
                for (final MixerStripVm strip in demoFaderStrips)
                  ObMixerStrip.fader(vm: strip),
              ],
            ),
          ),
        ],
      ),
      size: const Size(1120, 480),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('boards')),
      uiGolden('mixer_strip'),
    );
  });

  testWidgets('the master strip is wider and carries a wider meter', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _Board(
        children: <Widget>[
          ObMixerStrip.meter(vm: demoMeterStrips.first),
          ObMixerStrip.meter(vm: demoMeterStrips.last),
        ],
      ),
      size: const Size(200, 400),
    );
    final List<double> widths =
        tester
            .widgetList<StripMeter>(find.byType(StripMeter))
            .map((StripMeter m) => m.width!)
            .toList();
    expect(widths, <double>[
      tokens.size.mixerMeterWidth,
      tokens.size.mixerMasterMeterWidth,
    ]);
  });

  testWidgets('strip, mute and solo taps report themselves', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ObMixerStrip.meter(
        vm: demoMeterStrips[4],
        onTap: () => fired.add('tap'),
        onMute: () => fired.add('mute'),
        onSolo: () => fired.add('solo'),
      ),
      size: const Size(60, 400),
    );
    await tester.tap(find.text('M'));
    await tester.tap(find.text('S'));
    await tester.tap(find.text('Drums Bus'));
    expect(fired, <String>['mute', 'solo', 'tap']);
  });

  testWidgets('dragging a fader reports a new position', (
    WidgetTester tester,
  ) async {
    final List<double> positions = <double>[];
    await pumpUi(
      tester,
      ObMixerStrip.fader(vm: demoFaderStrips.first, onFader: positions.add),
      size: const Size(120, 400),
    );
    final Rect fader = tester.getRect(find.byType(StripFader));
    // Drag toward the top of the track: the position must rise.
    await tester.dragFrom(fader.center, Offset(0, -fader.height / 4));
    expect(positions, isNotEmpty);
    expect(positions.last, greaterThan(0.5));
  });

  testWidgets('the sidechain tag only appears on the ducked strip', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      _Board(
        children: <Widget>[
          for (final MixerStripVm strip in demoMeterStrips)
            ObMixerStrip.meter(vm: strip),
        ],
      ),
      size: const Size(400, 480),
    );
    expect(find.text('↓ SC in'), findsOneWidget);
  });

  test('the meter painter repaints on level and nothing else', () {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    StripMeterPainter build(double level) => StripMeterPainter(
      level: level,
      track: tokens.color.meterTrack,
      low: tokens.color.meterLow,
      mid: tokens.color.meterMid,
      high: tokens.color.meterHigh,
      radius: tokens.radius.xs,
    );
    final StripMeterPainter base = build(0.5);
    expect(build(0.5).shouldRepaint(base), isFalse);
    expect(build(0.51).shouldRepaint(base), isTrue);
  });
}
