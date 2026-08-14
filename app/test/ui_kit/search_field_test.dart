// ObSearchField behaviour (visual states are on the core-controls board
// golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/search_field.dart';

import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObSearchField(
          hint: 'Search samples, presets…',
          onTap: () => fired++,
        ),
      ),
      size: const Size(400, 200),
    );
    await tester.tap(find.byType(ObSearchField));
    expect(fired, 1);
  });

  testWidgets('renders the shortcut tag only when given one', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObSearchField(hint: 'Search actions', shortcut: '⌘K'),
      ),
      size: const Size(400, 200),
    );
    expect(find.text('⌘K'), findsOneWidget);
  });
}
