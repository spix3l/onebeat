// Left rail (UI-B-03): the golden with the mockup's content, plus the
// callback tests the golden cannot make.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/rail_glyphs.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';

import '../../support/ui_harness.dart';

/// The rail contains only project destinations. Library sources such as
/// plug-ins and sample packs appear in the browser panel instead.
const ObSideRailVm demoRail = ObSideRailVm(
  items: <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
  ],
  activeIndex: 0,
  separatorBefore: null,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders its three destinations as the golden', (
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
    expect(selected, <int>[2]);
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
    expect(find.byType(ObRailGlyph), findsNWidgets(3));
  });
}
