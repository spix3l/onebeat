import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/extensions/extension_binding.dart';

import '../../support/stage3_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('ExtensionBinding renders installed extensions list and details', (
    WidgetTester tester,
  ) async {
    await pumpForTest(
      tester,
      const ExtensionBinding(),
    );

    expect(find.text('Humanize Grooves'), findsWidgets);
    expect(find.text('Euclidean Rhythms'), findsWidgets);
    expect(find.text('CAPABILITIES'), findsOneWidget);
    expect(find.text('Read project state'), findsWidgets);
  });

  testWidgets('ExtensionBinding switches selected extension and inspects crash card', (
    WidgetTester tester,
  ) async {
    await pumpForTest(
      tester,
      const ExtensionBinding(),
    );

    // Tap on Sidechain Auto-Ducker (crashed extension)
    await tester.tap(find.text('Sidechain Auto-Ducker').first);
    await tester.pump();

    expect(find.text('CRASHED'), findsOneWidget);
    expect(find.textContaining('The host caught the fault cleanly'), findsOneWidget);
  });
}
