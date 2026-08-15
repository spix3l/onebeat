// Browser panel (UI-B-04): one golden with every content variant in it, plus
// the callbacks.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/browser/browser_panel.dart';
import 'package:onebeat/src/features/playlist/playlist_store.dart';
import 'package:onebeat/src/ui_kit/search_field.dart';

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
              vm: ObBrowserPanelVm(
                nodes: demoBrowserSamples,
                selectedId: 'sub',
              ),
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
        vm: ObBrowserPanelVm(nodes: demoBrowserTree, selectedId: 'soft-keys'),
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

  testWidgets('search focuses the field and filters matching branches', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      ObBrowserPanel(vm: ObBrowserPanelVm(nodes: demoBrowserTree)),
      size: _panel,
    );

    await tester.tap(find.byType(ObSearchField));
    await tester.enterText(find.byType(EditableText), 'bass');
    await tester.pump();

    expect(find.text('Drums'), findsNothing);
    expect(find.text('Bass Motif'), findsOneWidget);
    expect(find.text('Main Groove'), findsOneWidget);
    expect(find.text('Packs'), findsNothing);
  });

  testWidgets('toggling a folder collapses its children', (
    WidgetTester tester,
  ) async {
    bool expanded = true;
    await pumpUi(
      tester,
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return ObBrowserPanel(
            vm: ObBrowserPanelVm(
              nodes: <BrowserNodeVm>[
                BrowserFolderVm(
                  id: 'drums',
                  name: 'Drums',
                  expanded: expanded,
                  children: demoBrowserSamples,
                ),
              ],
            ),
            onToggle: (_) => setState(() => expanded = !expanded),
          );
        },
      ),
      size: _panel,
    );

    expect(find.text('Kick 808'), findsOneWidget);
    await tester.tap(find.text('Drums'));
    await tester.pump();
    expect(find.text('Kick 808'), findsNothing);
  });

  testWidgets('filtered folder count matches visible children', (
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
              count: 2,
              expanded: true,
              children: <BrowserNodeVm>[
                BrowserSampleVm(
                  id: 'kick',
                  name: 'Kick 808',
                  color: channelColors[0],
                ),
                BrowserSampleVm(
                  id: 'snare',
                  name: 'Snare',
                  color: channelColors[1],
                ),
              ],
            ),
          ],
        ),
      ),
      size: _panel,
    );

    await tester.tap(find.byType(ObSearchField));
    await tester.enterText(find.byType(EditableText), 'kick');
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Snare'), findsNothing);
  });

  testWidgets('add packs stays available after a pack is imported', (
    WidgetTester tester,
  ) async {
    bool addFolderClicked = false;
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: ObBrowserPanelVm(
          nodes: <BrowserNodeVm>[
            BrowserFolderVm(
              id: 'pack:drums',
              name: 'Drums',
              count: 1,
              children: <BrowserNodeVm>[
                BrowserSampleVm(
                  id: 'kick',
                  name: 'Kick',
                  color: channelColors[0],
                ),
              ],
            ),
          ],
          emptyButtonLabel: 'Add packs',
        ),
        onAddFolder: () => addFolderClicked = true,
      ),
      size: _panel,
    );

    expect(find.text('Add packs'), findsOneWidget);
    expect(find.text('Drums'), findsOneWidget);
    await tester.tap(find.text('Add packs'));
    expect(addFolderClicked, isTrue);
  });

  testWidgets('pattern rows with a payload can be dragged', (
    WidgetTester tester,
  ) async {
    const PlaylistInsertItem item = PlaylistInsertItem(
      id: 'pattern:main',
      patternId: 'main',
    );
    await pumpUi(
      tester,
      const ObBrowserPanel(
        vm: ObBrowserPanelVm(
          nodes: <BrowserNodeVm>[
            BrowserPatternVm(
              id: 'main',
              name: 'Main',
              color: Color(0xfff05a47),
              dragData: item,
            ),
          ],
        ),
      ),
      size: _panel,
    );

    final Draggable<Object> draggable = tester.widget(
      find.byType(Draggable<Object>),
    );
    expect(draggable.data, same(item));
  });

  testWidgets('sample rows carry a waveform mark', (WidgetTester tester) async {
    await pumpUi(
      tester,
      ObBrowserPanel(vm: ObBrowserPanelVm(nodes: demoBrowserSamples)),
      size: _panel,
    );
    expect(find.byType(BrowserSampleRow), findsNWidgets(8));
  });

  test('sample preview availability is independent from drag data', () {
    const BrowserSampleVm sample = BrowserSampleVm(
      id: 'kick',
      name: 'Kick 808',
      color: Color(0xfff05a47),
      previewPath: '/tmp/Kick.wav',
    );

    expect(sample.previewPath, '/tmp/Kick.wav');
    expect(sample.dragData, isNull);
  });

  testWidgets('empty browser nodes render empty state with add folder button', (
    WidgetTester tester,
  ) async {
    bool addFolderClicked = false;
    await pumpUi(
      tester,
      ObBrowserPanel(
        vm: const ObBrowserPanelVm(nodes: <BrowserNodeVm>[]),
        onAddFolder: () => addFolderClicked = true,
      ),
      size: _panel,
    );
    expect(find.text('No sound folders yet.'), findsOneWidget);
    expect(find.text('Add sound folder...'), findsOneWidget);

    await tester.tap(find.text('Add sound folder...'));
    await tester.pump();
    expect(addFolderClicked, isTrue);
  });
}
