// Menu bar (UI-B-02): the golden of the mockup's menu row, plus the tap
// behaviour the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/menu_bar.dart';

import '../../support/ui_fixtures.dart';
import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // The mockup's menu row: `Mixer` active on its raised pill, with the
  // dropdown chevron the ticket writes as `Mixer▾`.
  const List<String> demoMenus = <String>[
    'File',
    'Edit',
    'Pattern',
    'View',
    'Tools',
    'Mixer ▾',
    'Window',
    'Help',
  ];

  testWidgets('renders the menu row as the golden', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const ObMenuBar(
        key: Key('menuBar'),
        vm: ObMenuBarVm(menus: demoMenus, activeIndex: 5, clock: demoClock),
      ),
      size: const Size(1600, 24),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('menuBar')), uiGolden('menu_bar'));
  });

  testWidgets('menu items fire onMenuTap with their index', (
    WidgetTester tester,
  ) async {
    final List<int> tapped = <int>[];
    await pumpUi(
      tester,
      ObMenuBar(
        vm: const ObMenuBarVm(menus: demoMenus, clock: demoClock),
        onMenuTap: tapped.add,
      ),
      size: const Size(1600, 24),
    );
    await tester.tap(find.text('Mixer'));
    expect(tapped, <int>[5]);
  });
}
