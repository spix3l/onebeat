// ObRailButton behaviour (visual states are on the core-controls board
// golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/rail_button.dart';

import '../support/ui_glyphs.dart';
import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

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
