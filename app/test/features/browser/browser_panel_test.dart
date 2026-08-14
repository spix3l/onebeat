// Browser panel (UI-B-04): one golden with every content variant in it, plus
// the callbacks.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/browser/browser_panel.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

/// Tall enough to show every row of both fixtures with the empty tail the
/// mockups have below the last one.
const Size _panel = Size(240, 440);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the tree and sample-list variants render as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      Row(
        key: const Key('browser'),
        children: <Widget>[
          SizedBox.fromSize(
            size: _panel,
            child: ObBrowserPanel(
              vm: ObBrowserPanelVm(
                nodes: demoBrowserTree,
                selectedId: 'main-groove',
              ),
            ),
          ),
          SizedBox.fromSize(
            size: _panel,
            child: ObBrowserPanel(
              vm: ObBrowserPanelVm(nodes: demoBrowserSamples, selectedId: 'sub'),
            ),
          ),
        ],
      ),
      size: Size(_panel.width * 2, _panel.height),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('browser')),
      uiGolden('browser_panel'),
    );
  });

  testWidgets('a selected pattern also renders in the piano-roll tree', (
    WidgetTester tester,
  ) async {
    // The piano-roll mockup selects `Soft Keys` instead — the accent row has
    // to work at depth 1 as well as at the root.
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: ObBrowserPanelVm(
          nodes: demoBrowserTree,
          selectedId: 'soft-keys',
        ),
      ),
      size: _panel,
    );
    expect(find.byType(BrowserPatternRow), findsNWidgets(3));
    final BrowserPatternRow row = tester.widget(
      find.byType(BrowserPatternRow).at(1),
    );
    expect(row.selected, isTrue);
    expect(row.depth, 1);
  });

  testWidgets('tapping a row reports its id', (WidgetTester tester) async {
    final List<String> tapped = <String>[];
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: ObBrowserPanelVm(nodes: demoBrowserTree),
        onTap: tapped.add,
      ),
      size: _panel,
    );
    await tester.tap(find.text('Main Groove'));
    await tester.tap(find.text('Bass Motif'));
    expect(tapped, <String>['main-groove', 'bass-motif']);
  });

  testWidgets('tapping a folder reports a disclosure toggle', (
    WidgetTester tester,
  ) async {
    final List<String> toggled = <String>[];
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: ObBrowserPanelVm(nodes: demoBrowserTree),
        onToggle: toggled.add,
      ),
      size: _panel,
    );
    await tester.tap(find.text('Packs'));
    await tester.tap(find.text('Drums'));
    expect(toggled, <String>['packs', 'drums']);
  });

  testWidgets('a collapsed folder hides its children', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: ObBrowserPanelVm(
          nodes: <BrowserNodeVm>[
            BrowserFolderVm(
              id: 'drums',
              name: 'Drums',
              count: 340,
              children: demoBrowserSamples,
            ),
          ],
        ),
      ),
      size: _panel,
    );
    expect(find.text('Kick 808'), findsNothing);
    expect(find.byType(BrowserFolderRow), findsOneWidget);
  });

  testWidgets('sample rows carry a waveform mark', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: ObBrowserPanelVm(nodes: demoBrowserSamples),
      ),
      size: _panel,
    );
    expect(find.byType(BrowserSampleRow), findsNWidgets(8));
  });
}
