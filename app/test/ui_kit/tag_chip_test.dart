// ObTagChip: behaviour + a golden of the counter badges.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/tag_chip.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders the badges as the golden', (WidgetTester tester) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _TagChipStates(spacing: tokens.spacing.xs),
      size: const Size(160, 60),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(_TagChipStates), uiGolden('tag_chip'));
  });

  testWidgets('renders its label', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const Center(child: ObTagChip(label: '4 tracks')),
      size: const Size(200, 200),
    );
    expect(find.text('4 tracks'), findsOneWidget);
  });
}

class _TagChipStates extends StatelessWidget {
  const _TagChipStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const ObTagChip(label: '4 tracks'),
        SizedBox(width: spacing),
        const ObTagChip(label: '12'),
      ],
    );
  }
}
