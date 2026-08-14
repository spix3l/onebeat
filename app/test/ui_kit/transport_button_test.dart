// ObTransportButton behaviour (visual states are on the core-controls board
// golden).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObTransportButton(
          onTap: () => fired++,
          child: const SizedBox.shrink(),
        ),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObTransportButton));
    expect(fired, 1);
  });

  testWidgets('without onTap it renders but stays inert', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObTransportButton(active: true, child: SizedBox.shrink()),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObTransportButton));
    expect(find.byType(ObTransportButton), findsOneWidget);
  });
}
