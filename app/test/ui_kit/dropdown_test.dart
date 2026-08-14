// ObDropdown behaviour (visual states are on the core-controls board golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/dropdown.dart';

import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('opens, selects and reports the choice', (
    WidgetTester tester,
  ) async {
    String? selected;
    await pumpUi(
      tester,
      Center(
        child: ObDropdown(
          label: 'SNAP',
          value: '1/2 step',
          items: const <String>['none', '1/2 step', '1/4 step'],
          onSelected: (String item) => selected = item,
        ),
      ),
      size: const Size(300, 300),
    );
    await tester.tap(find.text('1/2 step').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1/4 step'));
    await tester.pumpAndSettle();
    expect(selected, '1/4 step');
  });

  testWidgets('tapping the field twice closes the menu', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObDropdown(
          label: 'GROUP',
          value: 'Audio 2',
          items: <String>['Audio 1', 'Audio 2'],
        ),
      ),
      size: const Size(300, 300),
    );
    // While open the widget's box grows to cover the menu, so the field —
    // not the box centre — is the tap target.
    await tester.tap(find.text('Audio 2').first);
    await tester.pumpAndSettle();
    expect(find.text('Audio 1'), findsOneWidget);
    await tester.tap(find.text('Audio 2').first);
    await tester.pumpAndSettle();
    expect(find.text('Audio 1'), findsNothing);
  });
}
