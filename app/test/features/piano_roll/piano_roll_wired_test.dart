// The assembled roll (UI-D-03): the golden that shows the four things the body
// golden cannot, because they only exist once the screen wires them together —
// scale banding, the sounding row, and the two always-visible scroll rails.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/piano_roll/note_grid.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_screen.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_screen_vm.dart';
import 'package:onebeat/src/features/piano_roll/pr_scrollbar.dart';
import 'package:onebeat/src/features/piano_roll/pr_toolbar.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

const PrToolbarVm _toolbar = PrToolbarVm(
  crumbs: <String>['Piano roll', 'Main Groove', 'Soft Keys'],
  pattern: 'Main Groove',
  scale: 'C min',
  snap: '1/4',
);

PianoRollScreen _screen({bool scrollable = true}) => PianoRollScreen(
  key: const Key('roll'),
  vm: PianoRollScreenVm(
    toolbar: _toolbar,
    roll: PianoRollVm(
      notes: demoNotes,
      ghostNotes: demoGhostNotes,
      viewport: demoViewport,
      playheadTick: demoPlayheadTick,
      selected: demoSelected,
      // The two rows the playhead is inside.
      activeKeys: const <int>{70, 58},
      // C minor.
      scaleIntervals: const <int>[0, 2, 3, 5, 7, 8, 10],
    ),
    contentEndTicks: demoViewport.ticksPerBar * 6,
  ),
  onScrollTicks: scrollable ? (_) {} : null,
  onScrollTopKey: scrollable ? (_) {} : null,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the wired roll renders as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(tester, _screen(), size: const Size(1600, 900));
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('roll')), uiGolden('piano_roll_wired'));
  });

  testWidgets('both rails are laid out, and outside the canvas', (
    WidgetTester tester,
  ) async {
    await pumpUi(tester, _screen(), size: const Size(1600, 900));
    await tester.pumpAndSettle();

    final List<Rect> rails = tester
        .widgetList(find.byType(PrScrollbar))
        .map((Widget w) => tester.getRect(find.byWidget(w)))
        .toList();

    expect(rails.length, 2, reason: 'one per axis, always');
    final Rect vertical = rails.firstWhere((Rect r) => r.height > r.width);
    final Rect horizontal = rails.firstWhere((Rect r) => r.width > r.height);

    // The vertical rail sits on the right edge, the horizontal one under the
    // canvas and to the right of the key column — neither overlaps the notes.
    expect(vertical.right, 1600);
    expect(horizontal.top, greaterThan(vertical.top));
    expect(horizontal.left, greaterThan(0), reason: 'clears the key column');
  });
}
