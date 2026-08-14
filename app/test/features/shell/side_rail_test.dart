// Left rail (UI-B-03): the golden with the mockup's content, plus the
// callback tests the golden cannot make.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/rail_glyphs.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';

import '../../support/ui_harness.dart';

/// The rail: three project destinations (channels first, the composition
/// home), a grouping hairline, then the library. Piano roll is opened from the
/// rack, not listed here.
const ObSideRailVm demoRail = ObSideRailVm(
  items: <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
    RailItemVm(icon: ObRailGlyphKind.folder, label: 'Packs'),
  ],
  activeIndex: 0,
  separatorBefore: 3,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders its four destinations as the golden', (
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
    expect(selected, <int>[2, 3]);
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
    expect(find.byType(ObRailGlyph), findsNWidgets(4));
  });
}
