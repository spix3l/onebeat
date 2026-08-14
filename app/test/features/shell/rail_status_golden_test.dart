// Left rail + status bar (UI-B-03): goldens of both strips with the mockup's
// content, plus the callback tests the goldens cannot make.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/rail_glyphs.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';
import 'package:onebeat/src/features/shell/status_bar.dart';

import '../../support/ui_harness.dart';

/// The rail exactly as every screen mockup draws it: four project
/// destinations, a grouping hairline, then the library.
const ObSideRailVm demoRail = ObSideRailVm(
  items: <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.note, label: 'Piano'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
    RailItemVm(icon: ObRailGlyphKind.folder, label: 'Packs'),
  ],
  activeIndex: 1,
  separatorBefore: 4,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('rail renders its five destinations as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObSideRail(key: Key('rail'), vm: demoRail),
      size: const Size(60, 320),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('rail')), uiGolden('side_rail'));
  });

  testWidgets('status bar renders both fixture states as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Column(
        key: Key('statusBars'),
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // The channel-rack mockup's footer.
          ObStatusBar(
            vm: ObStatusBarVm(
              tone: StatusTone.ok,
              primary: 'Playing',
              details: <String>['Main Groove', '8 channels', '16 steps'],
              rightHint: 'Double-click a channel to open its piano roll',
            ),
          ),
          // The routing mockup's footer: idle, with the routing shortcuts.
          ObStatusBar(
            vm: ObStatusBarVm(
              tone: StatusTone.warning,
              primary: 'Inspecting Drums Bus',
              details: <String>['4 inputs', '2 sends'],
              rightHint: '⌘R routing · ⇧⌘R overview',
            ),
          ),
        ],
      ),
      size: const Size(1600, 60),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('statusBars')),
      uiGolden('status_bar'),
    );
  });

  testWidgets('tapping a destination reports its index', (
    WidgetTester tester,
  ) async {
    final List<int> selected = <int>[];
    await pumpUi(
      tester,
      ObSideRail(vm: demoRail, onSelect: selected.add),
      size: const Size(60, 320),
    );
    await tester.tap(find.text('MIXER'));
    await tester.tap(find.text('PACKS'));
    expect(selected, <int>[3, 4]);
  });

  testWidgets('the active destination is the only filled tile', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObSideRail(vm: demoRail),
      size: const Size(60, 320),
    );
    expect(find.text('CHANNELS'), findsOneWidget);
    expect(find.byType(ObRailGlyph), findsNWidgets(5));
  });

  testWidgets('status details render dot-separated after the primary', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObStatusBar(
        vm: ObStatusBarVm(
          tone: StatusTone.danger,
          primary: 'Audio device disconnected',
          details: <String>['no output'],
        ),
      ),
      size: const Size(1600, 26),
    );
    expect(find.text('Audio device disconnected'), findsOneWidget);
    expect(find.text('· no output'), findsOneWidget);
  });
}
