import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/playlist/clip_card.dart';
import 'package:onebeat/src/features/playlist/playlist_binding.dart';
import 'package:onebeat/src/features/playlist/playlist_canvas.dart';
import 'package:onebeat/src/features/playlist/playlist_screen.dart';
import 'package:onebeat/src/features/playlist/playlist_store.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakePlaylistEngineClient extends FakeEngineClient
    implements EngineClient {
  _FakePlaylistEngineClient();

  bool isPlaying = false;
  double positionBeats = 0.0;

  @override
  EngineSnapshot readSnapshot() => EngineSnapshot(
    playing: isPlaying,
    loopEnabled: true,
    loopStartBeats: 0,
    loopEndBeats: 4,
    positionFrames: 0,
    positionBeats: positionBeats,
    positionSeconds: 0,
    hostTimeNanos: 0,
    tempoBpm: 120,
    bar: 1,
    beat: 1,
    tick: 0,
    sampleRate: 48000,
    blockFrames: 128,
    activeVoices: 0,
    peakLeft: 0,
    peakRight: 0,
    rmsLeft: 0,
    rmsRight: 0,
    cpuLoad: 0,
    xrunCount: 0,
    latencyFramesRoundTrip: 256,
    scheduleEventCount: 0,
  );

  @override
  List<EngineEvent> pollEvents() => const <EngineEvent>[];
}

void main() {
  setUpAll(loadAppFonts);

  late _FakePlaylistEngineClient fakeClient;
  late PlaylistStore store;

  setUp(() {
    fakeClient = _FakePlaylistEngineClient();
    store = PlaylistStore(fakeClient)..load();
  });

  testWidgets('places a pattern clip on empty background tap', (
    WidgetTester tester,
  ) async {
    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    expect(store.clips.isEmpty, isTrue);

    // Tap canvas background
    await tester.tap(find.byType(PlaylistBinding));
    await tester.pump();

    expect(store.clips.length, 1);
    expect(store.clips.first.patternId, 'pat_a');
    expect(store.selectedClipIds.contains(store.clips.first.id), isTrue);
  });

  testWidgets('an empty slot uses the pattern last selected in the browser', (
    WidgetTester tester,
  ) async {
    fakeClient.createPattern('Bass Motif');
    store.refresh();
    fakeClient.selectPattern('pat_1');
    store.setLastClickedItem(
      const PlaylistInsertItem(id: 'pattern:pat_1', patternId: 'pat_1'),
    );

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    final RenderBox canvas = tester.renderObject(find.byType(PlaylistCanvas));
    await tester.tapAt(canvas.localToGlobal(const Offset(220, 12)));
    await tester.pump();

    expect(store.clips.single.patternId, 'pat_1');
  });

  testWidgets('placing on an empty row creates a second playlist lane', (
    WidgetTester tester,
  ) async {
    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    final RenderBox canvas = tester.renderObject(find.byType(PlaylistCanvas));
    final double laneHeight = OneBeatTokens.dark().size.playlistLaneHeight;
    await tester.tapAt(canvas.localToGlobal(Offset(20, laneHeight + 12)));
    await tester.pump();

    expect(store.lanes, hasLength(2));
    expect(store.clips, hasLength(1));
    expect(store.clips.single.laneId, isNot('lane_a'));
  });

  testWidgets('dragging a playlist clip moves it on the grid', (
    WidgetTester tester,
  ) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    store.refresh();

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    await tester.drag(
      find.byType(ObClipCard),
      const Offset(140, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(store.clips.single.startTicks, greaterThan(0));
    expect(fakeClient.gestureBegins, 1);
    expect(fakeClient.gestureCommits, 1);
  });

  testWidgets('double-clicking a pattern opens its piano roll target', (
    WidgetTester tester,
  ) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    store.refresh();
    final List<(String, String)> opened = <(String, String)>[];

    await pumpForTest(
      tester,
      PlaylistBinding(
        client: fakeClient,
        store: store,
        onOpenPattern: (String patternId, String clipId) {
          opened.add((patternId, clipId));
        },
      ),
    );

    await tester.tap(find.byType(ObClipCard));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(ObClipCard));
    await tester.pump(const Duration(milliseconds: 350));
    expect(opened, hasLength(1));
    expect(opened.single.$1, 'pat_a');
    expect(opened.single.$2, store.clips.single.id);
  });

  testWidgets('dragging the right edge resizes a playlist clip', (
    WidgetTester tester,
  ) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    store.refresh();

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    final RenderBox card = tester.renderObject(find.byType(ObClipCard));
    await tester.dragFrom(
      card.localToGlobal(Offset(card.size.width - 2, card.size.height / 2)),
      const Offset(40, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(store.clips.single.lengthTicks, greaterThan(3840));
    expect(fakeClient.gestureBegins, 1);
    expect(fakeClient.gestureCommits, 1);
  });

  testWidgets('shift-click adds clips and alt-drag lassos them', (
    WidgetTester tester,
  ) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 3840,
      lengthTicks: 3840,
    );
    store.refresh();

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    await tester.tap(find.byType(ObClipCard).first);
    await tester.pump(const Duration(milliseconds: 350));
    await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byType(ObClipCard).at(1));
    await tester.pump(const Duration(milliseconds: 350));
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(store.selectedClipIds, hasLength(2));

    store.clearClipSelection();
    final RenderBox canvas = tester.renderObject(find.byType(PlaylistCanvas));
    await simulateKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(
      canvas.localToGlobal(const Offset(200, 4)),
      const Offset(-190, 76),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await simulateKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(store.selectedClipIds, hasLength(2));
    expect(store.clips, hasLength(2));
  });

  testWidgets('dual-instance: 2 clips of same pattern update name together', (
    WidgetTester tester,
  ) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 3840,
      lengthTicks: 3840,
    );
    store.refresh();

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    expect(store.clips.length, 2);
    expect(store.clips[0].name, 'Verse Drums');
    expect(store.clips[1].name, 'Verse Drums');
    expect(find.text('Verse Drums'), findsNWidgets(2));

    fakeClient.renamePattern('pat_a', 'Chorus Drums');
    store.refresh();
    await tester.pump();

    expect(store.clips[0].name, 'Chorus Drums');
    expect(store.clips[1].name, 'Chorus Drums');
    expect(find.text('Chorus Drums'), findsNWidgets(2));
  });

  testWidgets('makes shared clip unique', (WidgetTester tester) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 3840,
      lengthTicks: 3840,
    );
    store.refresh();
    store.selectClip(store.clips.first.id);

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    expect(find.text('Make unique'), findsOneWidget);
    await tester.tap(find.text('Make unique'));
    await tester.pump();

    // Now clips have different pattern IDs
    expect(store.clips[0].patternId != store.clips[1].patternId, isTrue);
  });

  testWidgets('inspector modifiers: start, length, transpose, mute, loop', (
    WidgetTester tester,
  ) async {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    store.refresh();
    store.selectClip(store.clips.first.id);

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );

    final String clipId = store.clips.first.id;

    // Transpose
    store.setClipTranspose(clipId, 3);
    expect(store.clips.first.transpose, 3);

    // Mute
    store.toggleClipMute(store.clips.first);
    expect(store.clips.first.muted, isTrue);

    // Resize
    store.resizeClip(clipId, 7680);
    expect(store.clips.first.lengthTicks, 7680);

    // Duplicate
    store.duplicateSelection();
    expect(store.clips.length, 2);

    // Delete
    store.deleteSelection();
    expect(store.clips.length, 1);
  });

  testWidgets('scrolling the playlist viewport is unbounded', (
    WidgetTester tester,
  ) async {
    final List<Offset> deltas = <Offset>[];
    await pumpForTest(
      tester,
      PlaylistCanvas(
        vm: const PlaylistVm(clips: <ClipVm>[], pxPerBar: 40),
        onScroll: deltas.add,
      ),
    );

    final Finder listenerFinder = find.byWidgetPredicate(
      (Widget widget) => widget is Listener && widget.onPointerSignal != null,
    );
    final Listener listener = tester.widget(listenerFinder.first);
    listener.onPointerSignal!(
      const PointerScrollEvent(scrollDelta: Offset(400, 720)),
    );
    expect(deltas, <Offset>[const Offset(400, 720)]);
  });

  test('deleting a clip is visible to a newly opened playlist store', () {
    fakeClient.addClip(
      'lane_a',
      patternId: 'pat_a',
      startTicks: 0,
      lengthTicks: 3840,
    );
    store.refresh();
    store.selectClip(store.clips.single.id);
    store.deleteSelection();

    final PlaylistStore reopened = PlaylistStore(fakeClient)..load();
    addTearDown(reopened.dispose);
    expect(reopened.clips, isEmpty);
  });

  testWidgets('the playhead runs linearly over the playlist, not looped', (
    WidgetTester tester,
  ) async {
    fakeClient.isPlaying = true;
    fakeClient.positionBeats = 6.0; // past the 4-beat loop region

    await pumpForTest(
      tester,
      PlaylistBinding(client: fakeClient, store: store),
    );
    await tester.pump();

    final PlaylistScreen screen = tester.widget(find.byType(PlaylistScreen));
    // 6 beats is 24 sixteenths. A looped head would wrap to 2 beats (8).
    expect(screen.vm.canvas.playheadBar16ths, 24);
  });
}
