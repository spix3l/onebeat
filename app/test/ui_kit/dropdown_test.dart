// ObDropdown: behaviour + a golden of the closed field and the open popover
// menu with its checked row.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/dropdown.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders closed and open as the golden', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _DropdownStates(spacing: tokens.spacing.lg),
      // Tall enough that the open menu, which now floats in the overlay rather
      // than inflating the field's own box, clears the surface's bottom edge.
      size: const Size(400, 240),
      center: true,
    );
    await tester.pumpAndSettle();
    // Open the second field so the popover menu is part of the golden.
    await tester.tap(find.text('C minor').first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(_DropdownStates), uiGolden('dropdown'));
  });

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
    // Tapping the field toggles the overlay menu; the field text and the menu
    // row share a label, so `.first` targets the field (it sits before the
    // overlay entry in tree order).
    await tester.tap(find.text('Audio 2').first);
    await tester.pumpAndSettle();
    expect(find.text('Audio 1'), findsOneWidget);
    await tester.tap(find.text('Audio 2').first);
    await tester.pumpAndSettle();
    expect(find.text('Audio 1'), findsNothing);
  });
}

class _DropdownStates extends StatelessWidget {
  const _DropdownStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const ObDropdown(
          label: 'SNAP',
          value: '1/4 step',
          items: <String>['none', '1/2 step', '1/4 step'],
        ),
        SizedBox(width: spacing),
        const ObDropdown(
          label: 'SCALE',
          value: 'C minor',
          items: <String>['C minor', 'C major', 'chromatic'],
        ),
      ],
    );
  }
}
