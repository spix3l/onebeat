// ObSearchIcon: behaviour + a golden of the round icon variant.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/search_icon.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders as the golden', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const Center(child: ObSearchIcon(onTap: null)),
      size: const Size(80, 80),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(ObSearchIcon), uiGolden('search_icon'));
  });

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(child: ObSearchIcon(onTap: () => fired++)),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObSearchIcon));
    expect(fired, 1);
  });
}
