// Store-level behaviour for ArrangementStore: lane changes touch only the
// lane, clip transforms round-trip, and the selection stays coherent.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/playlist/playlist_selection.dart';
import 'package:onebeat/src/features/playlist/playlist_store.dart';
import 'package:onebeat/src/engine/engine_client.dart';

import '../../support/app_harness.dart';

void main() {
  test('timeline zoom can move in and out around the viewport centre', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final PlaylistStore store = harness.arrangement;

    store.zoomHorizontally(2.0, anchorTick: 3840);

    expect(store.horizontalZoom, 2.0);
    expect(store.scrollTicks, 1920.0);

    store.zoomHorizontally(0.5, anchorTick: 3840);

    expect(store.horizontalZoom, 1.0);
    expect(store.scrollTicks, 0.0);
  });

  test('moving a clip between lanes changes only the lane', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final ArrangementClip clip = store.clips.first;
    final String otherLane = store.lanes.firstWhere((ArrangementLane lane) => lane.id != clip.laneId).id;

    store
      ..selectClip(clip.id)
      ..beginClipDrag(ClipDragKind.move)
      ..updateClipMove(0, laneId: otherLane)
      ..endClipDrag();

    final ArrangementClip moved = store.clipById(clip.id)!;
    expect(moved.laneId, otherLane);
    expect(moved.startTicks, clip.startTicks);
    expect(moved.patternId, clip.patternId);
    expect(moved.transpose, clip.transpose);
    expect(harness.client.gestureBegins, 1);
    expect(harness.client.gestureCommits, 1);
  });

  test('moving multiple clips preserves their relative lanes', () {
    final EditorHarness harness = EditorHarness();
    harness.client
      ..createLane('Second')
      ..createLane('Third');
    final String laneB = harness.client.lanes.values.firstWhere((value) => value.name == 'Second').id;
    final String laneC = harness.client.lanes.values.firstWhere((value) => value.name == 'Third').id;
    harness.client
      ..addClip('lane_a', startTicks: 0, lengthTicks: 3840)
      ..addClip(laneB, startTicks: 0, lengthTicks: 3840)
      ..addClip(laneC, startTicks: 0, lengthTicks: 3840);
    harness.arrangement.refresh();

    final Map<String, String> clipsByStartingLane = <String, String>{
      for (final ArrangementClip clip in harness.arrangement.clips) clip.laneId: clip.id,
    };
    final PlaylistStore store = harness.arrangement;
    store
      ..selectClips(clipsByStartingLane.values)
      ..beginClipDrag(ClipDragKind.move)
      ..updateClipMove(0, laneDelta: 1)
      ..endClipDrag();

    expect(store.clipById(clipsByStartingLane['lane_a']!)!.laneId, laneB);
    expect(store.clipById(clipsByStartingLane[laneB]!)!.laneId, laneC);
    final String lastLane = store.lanes.last.id;
    expect(store.clipById(clipsByStartingLane[laneC]!)!.laneId, lastLane);
    expect(store.clips, hasLength(3));
  });

  test('clip windowing and transforms round-trip through the store', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final String id = store.clips.first.id;

    store
      ..resizeClip(id, 1920)
      ..setClipWindowStart(id, 480)
      ..setClipLoop(id, loop: false)
      ..setClipTranspose(id, 3);

    final ArrangementClip clip = store.clipById(id)!;
    expect(clip.lengthTicks, 1920);
    expect(clip.windowStartTicks, 480);
    expect(clip.loop, isFalse);
    expect(clip.transpose, 3);
    // Hold-off means the clip plays its window once; repeatCount reflects it.
    expect(clip.repeatCount, 1);
  });

  test('transpose is clamped to the ±48 semitone range', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final String id = store.clips.first.id;

    store.setClipTranspose(id, 200);
    expect(store.clipById(id)!.transpose, 48);

    store.setClipTranspose(id, -200);
    expect(store.clipById(id)!.transpose, -48);
  });

  test('a looping clip reports how many times its pattern repeats', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final String id = store.clips.first.id;

    store.resizeClip(id, 3840 * 3);

    expect(store.clipById(id)!.repeatCount, 3);
  });

  test('a marquee selects clips by time and lane', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final ArrangementClip clip = store.clips.first;
    final int lane = store.lanes.indexWhere((ArrangementLane candidate) => candidate.id == clip.laneId);

    store
      ..beginMarquee(clip.startTicks, lane)
      ..updateMarquee(clip.endTicks, lane)
      ..endMarquee();

    expect(store.selectedClipIds, contains(clip.id));
    expect(store.dragKind, ClipDragKind.none);
    expect(store.marquee, isNull);
  });

  test('a dropped pattern item creates the requested pattern clip', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final String laneId = store.lanes.first.id;
    final int before = store.clips.length;

    store.placeItem(const PlaylistInsertItem(id: 'pattern:pat_a', patternId: 'pat_a'), laneId, 1920);

    expect(store.clips.length, before + 1);
    expect(store.clips.last.patternId, 'pat_a');
    expect(store.clips.last.startTicks, 3840);
  });

  test('deleting a clip clears it from the selection', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final String id = store.clips.first.id;

    store
      ..selectClip(id)
      ..deleteSelection();

    expect(store.selectedClipIds, isEmpty);
    expect(store.clipById(id), isNull);
  });

  test('lane reorder renumbers densely', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final String last = store.lanes.last.id;

    store.moveLaneTo(last, 0);

    expect(store.lanes.first.id, last);
    expect(store.lanes.map((ArrangementLane lane) => lane.order), <int>[0, 1]);
  });

  test('the lane event gate is a lane field, never an instrument one', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final ArrangementLane lane = store.lanes.first;

    store.toggleLaneMute(lane);

    expect(store.lanes.first.muted, isTrue);
    // The clips are untouched: muting a lane gates its events, it does not
    // edit what is on it.
    expect(store.clipsOnLane(lane.id).every((ArrangementClip clip) => !clip.muted), isTrue);
  });

  test('tool and timeline selection state are explicit and cancellable', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final PlaylistStore store = harness.arrangement;

    store.setTool(PlaylistTool.slice);
    store.setTimeSelection(3840, 960);

    expect(store.tool, PlaylistTool.slice);
    expect(store.timeSelection!.lowTick, 960);
    expect(store.timeSelection!.highTick, 3840);

    store.clearTimeSelection();
    expect(store.timeSelection, isNull);
  });
}
