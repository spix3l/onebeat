// ObToggleChip behaviour (visual states are on the core-controls board
// golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/toggle_chip.dart';

import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObToggleChip(
          tone: ObToggleTone.mute,
          on: false,
          onTap: () => fired++,
        ),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObToggleChip));
    expect(fired, 1);
  });

  testWidgets('shows M for mute and S for solo', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ObToggleChip(tone: ObToggleTone.mute, on: true),
            ObToggleChip(tone: ObToggleTone.solo, on: false),
          ],
        ),
      ),
      size: const Size(200, 200),
    );
    expect(find.text('M'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });
}
