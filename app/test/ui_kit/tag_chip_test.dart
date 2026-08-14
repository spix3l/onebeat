// ObTagChip behaviour (visual states are on the core-controls board golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/tag_chip.dart';

import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders its label', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const Center(child: ObTagChip(label: '4 tracks')),
      size: const Size(200, 200),
    );
    expect(find.text('4 tracks'), findsOneWidget);
  });
}
