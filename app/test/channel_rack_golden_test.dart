import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/channel_rack.dart';

import 'support/stage3_harness.dart';

void main() {
  // Real fonts: block glyphs measure nothing like Archivo or MartianMono.
  setUpAll(loadAppFonts);

  testWidgets('channel rack step surface matches the dark token system', (
    WidgetTester tester,
  ) async {
    const RackPattern pattern = RackPattern(
      id: 'pattern',
      name: 'Pattern 1',
      lengthTicks: 3840,
      baseGridTicks: 240,
      swing: 0.25,
    );
    const List<RackRow> rows = <RackRow>[
      RackRow(
        instrumentId: 'kick',
        gridTicks: 240,
        hasSequence: true,
        offGridCount: 0,
        noteCount: 4,
        steps: <RackStep>[
          RackStep(active: true, velocity: 16383),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: true, velocity: 12900),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: true, velocity: 14500),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: true, velocity: 11200),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
        ],
      ),
      RackRow(
        instrumentId: 'snare',
        gridTicks: 240,
        hasSequence: true,
        offGridCount: 1,
        noteCount: 3,
        steps: <RackStep>[
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: true, velocity: 15000),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: true, velocity: 13000),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
          RackStep(active: false, velocity: 0),
        ],
      ),
    ];

    await tester.pumpWidget(
      OneBeatTheme(
        tokens: OneBeatTokens.dark(),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: ValueKey<String>('rack-golden'),
              child: SizedBox(
                width: 544,
                height: 104,
                child: RackStepGrid(
                  rows: rows,
                  pattern: pattern,
                  positionBeats: 1.5,
                  playing: true,
                  selectedInstrument: 'snare',
                  selectedStep: 4,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey<String>('rack-golden')),
      matchesGoldenFile('goldens/channel_rack_dark.png'),
    );
  });
}
