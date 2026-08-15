// The playlist's track header column (UI-B-08): what a header says about its
// lane, and the three controls it carries.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/playlist/playlist_canvas.dart';
import 'package:onebeat/src/features/playlist/playlist_screen.dart';
import 'package:onebeat/src/ui_kit/toggle_chip.dart';

import '../../support/ui_harness.dart';

PlaylistLaneVm _lane(
  String id,
  String name, {
  bool muted = false,
  bool soloed = false,
  bool collapsed = false,
  int clipCount = 0,
}) => PlaylistLaneVm(
  id: id,
  name: name,
  color: channelColors[0],
  muted: muted,
  soloed: soloed,
  collapsed: collapsed,
  clipCount: clipCount,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a header numbers its lane and says what the lane holds', (WidgetTester tester) async {
    await pumpUi(
      tester,
      PlaylistLaneHeaders(
        lanes: <PlaylistLaneVm>[
          _lane('a', 'Patterns', clipCount: 4),
          _lane('b', 'Drums', clipCount: 1),
          _lane('c', 'Bass'),
          _lane('d', 'Pads', muted: true, clipCount: 2),
        ],
      ),
      size: const Size(320, 400),
    );

    // The number is the lane's position, not its id — the canvas rows are read
    // in the same order.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    expect(find.text('4 clips'), findsOneWidget);
    expect(find.text('1 clip'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    // A muted lane says so where the clip count would be: the count is the
    // less useful fact once nothing on the lane is heard.
    expect(find.text('Muted'), findsOneWidget);
  });

  testWidgets('mute, solo and collapse report the lane they belong to', (WidgetTester tester) async {
    final List<String> muted = <String>[];
    final List<String> soloed = <String>[];
    final List<String> collapsed = <String>[];

    await pumpUi(
      tester,
      PlaylistLaneHeaders(
        lanes: <PlaylistLaneVm>[_lane('a', 'Patterns'), _lane('b', 'Drums')],
        onMute: muted.add,
        onSolo: soloed.add,
        onCollapse: collapsed.add,
      ),
      size: const Size(320, 400),
    );

    await tester.tap(find.byType(ObToggleChip).at(2)); // Drums' M
    await tester.tap(find.byType(ObToggleChip).at(1)); // Patterns' S
    await tester.tap(find.text('Drums'));

    expect(muted, <String>['b']);
    expect(soloed, <String>['a']);
    // Tapping the name is not a collapse — only the triangle is.
    expect(collapsed, isEmpty);

    // The triangle's own column, half way down the first row.
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final Offset origin = tester.getTopLeft(find.byType(PlaylistLaneHeaders));
    await tester.tapAt(
      origin +
          Offset(
            tokens.size.playlistLaneSpineWidth + tokens.spacing.sm + tokens.size.playlistLaneDiscloseSize / 2,
            tokens.size.playlistLaneHeight / 2,
          ),
    );
    expect(collapsed, <String>['a']);
  });

  testWidgets('the column scrolls with the canvas it labels', (WidgetTester tester) async {
    final List<PlaylistLaneVm> lanes = <PlaylistLaneVm>[
      for (int i = 0; i < 6; i++) _lane('l$i', 'Track ${i + 1}'),
    ];
    final double laneHeight = OneBeatTokens.dark().size.playlistLaneHeight;

    // Both columns in one tree: same lanes, one of them scrolled, so the
    // comparison is a layout difference rather than two pumps.
    await pumpUi(
      tester,
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlaylistLaneHeaders(key: const Key('still'), lanes: lanes),
          PlaylistLaneHeaders(key: const Key('scrolled'), lanes: lanes, scrollLanes: 1.5),
        ],
      ),
      size: const Size(640, 400),
    );

    double topOf(String column) => tester
        .getTopLeft(find.descendant(of: find.byKey(Key(column)), matching: find.text('Track 1')))
        .dy;

    expect(topOf('still') - topOf('scrolled'), closeTo(1.5 * laneHeight, 0.01));
  });
}
