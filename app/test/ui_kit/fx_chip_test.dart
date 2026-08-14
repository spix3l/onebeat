// ObFxChip: behaviour + a golden of the FX entries and the mono route chip,
// labels verbatim from the mockups.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/fx_chip.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders every variant as the golden', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _FxChipStates(spacing: tokens.spacing.sm),
      size: const Size(360, 80),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(_FxChipStates), uiGolden('fx_chip'));
  });

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

class _FxChipStates extends StatelessWidget {
  const _FxChipStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    final ColorTokens color = OneBeatTheme.of(context).color;
    return Row(
      children: <Widget>[
        ObFxChip(
          label: 'Chorus',
          dotColor: color.channelColors[4],
          onTap: () {},
        ),
        SizedBox(width: spacing),
        ObFxChip(label: 'EQ 4', dotColor: color.channelColors[1], onTap: () {}),
        SizedBox(width: spacing),
        ObFxChip(
          label: 'Reeverb 2',
          dotColor: color.channelColors[2],
          onTap: () {},
        ),
        SizedBox(width: spacing),
        ObFxChip(label: '→ D1', dotColor: color.channelColors[0], mono: true),
      ],
    );
  }
}
