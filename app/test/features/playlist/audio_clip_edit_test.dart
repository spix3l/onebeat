// Audio clip editing through the store: which engine call each edit makes, and
// the one distinction that matters — that an audio clip's right edge means
// something different from a pattern clip's.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/playlist/playlist_store.dart';

import '../../support/app_harness.dart';

void main() {
  test('resizing an audio clip takes the stretch-aware path, not the plain one', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 7680, lengthTicks: 3840);
    final ArrangementStore store = harness.arrangement..refresh();

    store.resizeClip(audioId, 1920);

    // The engine owns the branch between "re-trim" and "stretch"; sending an
    // audio clip through the plain resize would silently pick trimming forever.
    expect(harness.client.clipLog, contains('resizeAudio:$audioId:1920'));
  });

  test('resizing a pattern clip does not', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    final ArrangementClip clip = store.clips.first;

    store.resizeClip(clip.id, 1920);

    expect(harness.client.clipLog.where((String e) => e.startsWith('resizeAudio')), isEmpty);
    expect(store.clipById(clip.id)!.lengthTicks, 1920);
  });

  test('dragging the start edge trims the source and preserves the clip end', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 7680, lengthTicks: 3840);
    harness.client.audioClips[audioId] = const AudioClipEdit(
      stretchMode: StretchMode.off,
      sourceOffsetTicks: 0,
      sourceLengthTicks: 3840,
      sourceDurationTicks: 7680,
      sourceBpm: 0,
      gain: 1,
      reversed: false,
    );
    final ArrangementStore store = harness.arrangement..refresh();

    store
      ..selectClip(audioId)
      ..beginClipDrag(ClipDragKind.resizeStart)
      ..updateClipResizeStart(audioId, 8640)
      ..endClipDrag();

    final ArrangementClip clip = store.clipById(audioId)!;
    expect(clip.startTicks, 8640);
    expect(clip.endTicks, 11520, reason: 'trimming the start must not move the right edge');
    expect(clip.lengthTicks, 2880);
    final AudioClipEdit edit = harness.client.audioClips[audioId]!;
    expect(edit.sourceOffsetTicks, 960);
    expect(edit.sourceLengthTicks, 2880);
  });

  test('dragging the edge and typing a length agree with each other', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 7680, lengthTicks: 3840);
    final ArrangementStore store = harness.arrangement..refresh();

    store
      ..selectClip(audioId)
      ..beginClipDrag(ClipDragKind.resizeEnd)
      ..updateClipResize(audioId, 2400)
      ..endClipDrag();

    // Both routes must reach the same call, or a stretched clip stretches one
    // way and trims the other.
    expect(harness.client.clipLog, contains('resizeAudio:$audioId:2400'));
  });

  test('stretch mode, reverse and source tempo round-trip through the store', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 0, lengthTicks: 3840);
    final ArrangementStore store = harness.arrangement..refresh();
    store.selectClip(audioId);

    store
      ..setClipStretchMode(audioId, StretchMode.stretch)
      ..setClipReversed(audioId, reversed: true)
      ..setClipSourceBpm(audioId, 174);

    final AudioClipEdit? edit = store.selectedAudioEdit;
    expect(edit, isNotNull);
    expect(edit!.stretchMode, StretchMode.stretch);
    expect(edit.reversed, isTrue);
    expect(edit.sourceBpm, 174);
    expect(edit.canFitToTempo, isTrue);
  });

  test('a clip with no source tempo cannot be fitted', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 0, lengthTicks: 3840);
    final ArrangementStore store = harness.arrangement..refresh();
    store.selectClip(audioId);

    // Offered as unavailable rather than silently guessing a tempo, which is
    // how a project ends up subtly out of time.
    expect(store.selectedAudioEdit!.canFitToTempo, isFalse);
  });

  test('the audio edit is null unless exactly one audio clip is selected', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;

    store.selectClip(store.clips.first.id);
    expect(store.selectedAudioEdit, isNull, reason: 'a pattern clip has no audio to describe');

    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 0, lengthTicks: 3840);
    store
      ..refresh()
      ..selectClip(audioId)
      ..selectClip(store.clips.first.id, additive: true);
    expect(store.selectedAudioEdit, isNull, reason: 'a multi-selection has no single answer');
  });

  test('cutting reports the tick it was asked to cut at', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 0, lengthTicks: 3840);
    final ArrangementStore store = harness.arrangement..refresh();

    store.splitClipAt(audioId, 1920);

    expect(harness.client.clipLog, contains('split:$audioId:1920'));
  });

  test('trimming sends the source window, in source time', () {
    final EditorHarness harness = EditorHarness()..seedArrangement();
    final String audioId = harness.client.addAudioClip('lane_a', startTicks: 0, lengthTicks: 3840);
    final ArrangementStore store = harness.arrangement..refresh();

    store.setClipSourceWindow(audioId, offsetTicks: 480, lengthTicks: 1920);

    expect(harness.client.clipLog, contains('window:$audioId:480:1920'));
    // A negative window is clamped rather than rejected: dragging a trim handle
    // past the start of the file is a gesture, not an error.
    store.setClipSourceWindow(audioId, offsetTicks: -100, lengthTicks: -5);
    expect(harness.client.clipLog, contains('window:$audioId:0:0'));
  });
}
