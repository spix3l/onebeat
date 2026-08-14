// ObRailButton: behaviour + a golden of rest / active states.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/rail_button.dart';

import '../support/ui_glyphs.dart';
import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders every state as the golden', (WidgetTester tester) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _RailStates(spacing: tokens.spacing.md),
      size: const Size(260, 100),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(_RailStates), uiGolden('rail_button'));
  });

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObRailButton(
          icon: RailGlyph.grid(),
          label: 'playlist',
          onTap: () => fired++,
        ),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObRailButton));
    expect(fired, 1);
  });
}

class _RailStates extends StatelessWidget {
  const _RailStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ObRailButton(icon: RailGlyph.grid(), label: 'playlist', onTap: null),
        SizedBox(width: spacing),
        ObRailButton(
          icon: RailGlyph.grid(),
          label: 'rack',
          active: true,
          onTap: null,
        ),
        SizedBox(width: spacing),
        ObRailButton(icon: RailGlyph.sliders(), label: 'mixer', onTap: null),
        SizedBox(width: spacing),
        ObRailButton(icon: RailGlyph.wave(), label: 'roll', onTap: null),
      ],
    );
  }
}
