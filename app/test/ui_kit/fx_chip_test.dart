// ObFxChip behaviour (visual states are on the core-controls board golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/fx_chip.dart';

import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObFxChip(
          label: 'Chorus',
          dotColor: OneBeatTokens.dark().color.channelColors.first,
          onTap: () => fired++,
        ),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObFxChip));
    expect(fired, 1);
  });

  testWidgets('renders its label', (WidgetTester tester) async {
    await pumpUi(
      tester,
      Center(
        child: ObFxChip(
          label: 'Reeverb 2',
          dotColor: OneBeatTokens.dark().color.channelColors.first,
        ),
      ),
      size: const Size(200, 200),
    );
    expect(find.text('Reeverb 2'), findsOneWidget);
  });
}
