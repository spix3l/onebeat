// ignore_for_file: prefer_const_constructors

// Playlist canvas (UI-B-08): the golden of the arrangement body, and the tap
// callbacks the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/browser/sample_pack.dart';
import 'package:onebeat/src/features/playlist/clip_card.dart';
import 'package:onebeat/src/features/playlist/playlist_canvas.dart';
import 'package:onebeat/src/features/playlist/timeline_ruler.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

/// Header, ruler and canvas stacked the way the screen does them.
class _Body extends StatelessWidget {
  const _Body({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PlaylistHeader(
          title: demoPlaylist.headerTitle,
          right: demoPlaylist.headerRight,
        ),
        PlaylistRuler(pxPerBar: demoPlaylist.pxPerBar),
        Expanded(child: PlaylistCanvas(vm: demoPlaylist)),
      ],
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the arrangement body renders as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const _Body(key: Key('body')),
      size: const Size(1600, 860),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('body')),
      uiGolden('playlist_body'),
    );
  });

  testWidgets('tapping a clip reports its id', (WidgetTester tester) async {
    final List<int> tapped = <int>[];
    await pumpUi(
      tester,
      PlaylistCanvas(vm: demoPlaylist, onClipTap: tapped.add),
      size: const Size(1600, 700),
    );
    await tester.tap(find.text('Vocal Chop'));
    await tester.tap(find.text('Riser'));
    expect(tapped, <int>[7, 8]);
  });

  testWidgets('tapping empty canvas reports a bar and a lane', (
    WidgetTester tester,
  ) async {
    final List<(double, int)> taps = <(double, int)>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      PlaylistCanvas(
        vm: demoPlaylist,
        onBackgroundTap: (double bar, int lane) => taps.add((bar, lane)),
      ),
      size: const Size(1600, 700),
    );
    // Lane 6 is empty in the fixture, so nothing intercepts the tap.
    final double y = tokens.size.playlistLaneHeight * 6.5;
    await tester.tapAt(Offset(demoPlaylist.pxPerBar * 4, y));
    expect(taps, hasLength(1));
    expect(taps.single.$1, closeTo(4, 0.01));
    expect(taps.single.$2, 6);
  });

  testWidgets('a selected clip outlines instead of changing its fill', (
    WidgetTester tester,
  ) async {
    final ClipVm selected = ClipVm(
      id: 1,
      name: 'Intro Kick',
      duration: '0:08',
      color: channelColors[0],
      startBar: 0,
      lengthBars: 4,
      lane: 0,
      selected: true,
    );
    await pumpUi(
      tester,
      PlaylistCanvas(
        vm: PlaylistVm(clips: <ClipVm>[selected], pxPerBar: 38.3),
      ),
      size: const Size(400, 100),
    );
    final Container card = tester.widget(
      find.descendant(
        of: find.byType(ObClipCard),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, channelColors[0]);
    expect(
      (decoration.border! as Border).top.color,
      OneBeatTokens.dark().color.clipSelectedOutline,
    );
  });

  testWidgets('a sample drag reports its canvas position', (
    WidgetTester tester,
  ) async {
    final List<(Object, double, int)> drops = <(Object, double, int)>[];
    const SampleAsset sample = SampleAsset(
      id: 'sample:kick.wav',
      name: 'kick.wav',
      path: '/Samples/kick.wav',
    );
    await pumpUi(
      tester,
      SizedBox(
        width: 600,
        height: 500,
        child: PlaylistCanvas(
          vm: PlaylistVm(clips: <ClipVm>[], pxPerBar: 100),
          onDrop: (Object data, double bar, int lane) =>
              drops.add((data, bar, lane)),
        ),
      ),
      size: const Size(600, 500),
    );

    final DragTarget<Object> target = tester.widget(
      find.byType(DragTarget<Object>),
    );
    // Flutter's test details constructor is intentionally non-const.
    target.onAcceptWithDetails!(
      DragTargetDetails<Object>(
        data: sample,
        offset: const Offset(200, 20),
      ),
    );
    await tester.pump();

    expect(drops, hasLength(1));
    expect(drops.single.$1, same(sample));
    expect(drops.single.$2, closeTo(2.0, 0.05));
    expect(drops.single.$3, 0);
  });

  test('the vm reports how many lanes the canvas has to make room for', () {
    expect(demoPlaylist.laneCount, 5);
    expect(const PlaylistVm(clips: <ClipVm>[], pxPerBar: 38.3).laneCount, 0);
  });
}
