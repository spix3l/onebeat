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
    // Tapping the field opens the menu; the field text and the menu row share
    // a label, so `.first` targets the field (it sits before the overlay entry
    // in tree order). Once open, the overlay's tap barrier covers the field,
    // so a second tap on the same spot lands on the barrier and closes it.
    await tester.tap(find.text('Audio 2').first);
    await tester.pumpAndSettle();
    expect(find.text('Audio 1'), findsOneWidget);
    await tester.tap(find.text('Audio 2').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Audio 1'), findsNothing);
  });

  testWidgets('the open menu is exactly as wide as the field', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      const Center(
        child: ObDropdown(
          label: 'SNAP',
          value: '1/4',
          // Narrower than the 156px default: the menu must shrink to match
          // the field instead of ballooning to a fixed minimum width.
          width: 130,
          items: <String>['1/4', '1/8', '1/16', 'None'],
        ),
      ),
      size: const Size(400, 300),
    );
    final Rect field = tester.getRect(find.byType(ObDropdown));
    expect(field.width, 130);

    await tester.tap(find.text('1/4').first);
    await tester.pumpAndSettle();

    final Finder menu = find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == tokens.color.surfaceOverlay,
    );
    expect(menu, findsOneWidget);
    expect(tester.getRect(menu).width, field.width);
  });

  testWidgets('a click outside the menu closes it', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const Center(
        child: ObDropdown(
          label: 'SNAP',
          value: '1/4',
          items: <String>['1/4', '1/8', '1/16', 'None'],
        ),
      ),
      size: const Size(400, 300),
    );
    await tester.tap(find.text('1/4').first);
    await tester.pumpAndSettle();
    expect(find.text('1/8'), findsOneWidget);

    // Tap well away from the centred field and the menu hanging below it; the
    // overlay's tap barrier must swallow the click and close the menu.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('1/8'), findsNothing);
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
