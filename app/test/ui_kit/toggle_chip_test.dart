// ObToggleChip: behaviour + a golden of M/S on and off states.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/toggle_chip.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders every state as the golden', (WidgetTester tester) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _ToggleChipStates(spacing: tokens.spacing.xs),
      size: const Size(160, 80),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(_ToggleChipStates), uiGolden('toggle_chip'));
  });

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

class _ToggleChipStates extends StatelessWidget {
  const _ToggleChipStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        ObToggleChip(tone: ObToggleTone.mute, on: true, onTap: () {}),
        SizedBox(width: spacing),
        ObToggleChip(tone: ObToggleTone.solo, on: true, onTap: () {}),
        SizedBox(width: spacing),
        ObToggleChip(tone: ObToggleTone.mute, on: false, onTap: () {}),
        SizedBox(width: spacing),
        ObToggleChip(tone: ObToggleTone.solo, on: false, onTap: () {}),
      ],
    );
  }
}
