// Top chrome (UI-B-02): the golden of the two stacked bars with the shared
// fixture values, plus behaviour tests for the vm-driven pieces.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/menu_bar.dart';
import 'package:onebeat/src/features/shell/readouts.dart';
import 'package:onebeat/src/features/shell/transport_bar.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

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

  testWidgets('renders the two bars as the golden', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const Column(
        key: Key('topChrome'),
        children: <Widget>[
          ObMenuBar(
            vm: ObMenuBarVm(menus: demoMenus, activeIndex: 5, clock: demoClock),
          ),
          ObTransportBar(
            vm: ObTransportBarVm(
              title: 'ONEBEAT',
              subtitle: 'v0.3 SEQUENCES',
              playing: true,
              looping: false,
              bpmText: demoBpm,
              sigText: demoSig,
              positionText: demoPosition,
              meterLeft: 0.72,
              meterRight: 0.65,
              searchHint: 'Search actions',
            ),
          ),
        ],
      ),
      size: const Size(1600, 92),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('topChrome')), uiGolden('top_chrome'));
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

  testWidgets('transport controls fire their callbacks', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ObTransportBar(
        vm: const ObTransportBarVm(
          title: 'ONEBEAT',
          subtitle: 'v0.3 SEQUENCES',
          playing: false,
          looping: false,
          bpmText: demoBpm,
          sigText: demoSig,
          positionText: demoPosition,
          meterLeft: 0.5,
          meterRight: 0.5,
          searchHint: 'Search actions',
        ),
        onTogglePlay: () => fired.add('play'),
        onToggleLoop: () => fired.add('loop'),
        onExport: () => fired.add('export'),
        onSearchTap: () => fired.add('search'),
      ),
      size: const Size(1600, 68),
    );
    // undo, redo, play, stop, loop — play is the third well.
    await tester.tap(find.byType(ObTransportButton).at(2));
    await tester.tap(find.byType(ObTransportButton).at(4));
    await tester.tap(find.text('Export'));
    await tester.tap(find.text('Search actions'));
    expect(fired, <String>['play', 'loop', 'export', 'search']);
  });

  testWidgets('every readout value and unit comes from the caller', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObReadout(value: '124.00', unit: 'BPM'),
      ),
      size: const Size(200, 100),
    );
    expect(find.text('124.00'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
  });
}
