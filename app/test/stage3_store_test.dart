// Store-level behaviour for the Stage 3 editors (OB-3-10/11/12/13).
//
// These test the rules that are easy to state and easy to break: a drag is one
// undo entry, the D-M6 notice appears once per pattern per session, Make unique
// diverges one clip and leaves the other alone, and clip transforms round-trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/arrangement_store.dart';
import 'package:onebeat/src/ui/pattern_store.dart';
import 'package:onebeat/src/ui/piano_roll_store.dart';

import 'support/stage3_harness.dart';

void main() {
  group('piano roll', () {
    test('a move drag is one gesture no matter how many steps it takes', () {
      final Stage3Harness harness = Stage3Harness()..seedNotes('inst_a');
      final PianoRollStore roll = harness.pianoRoll..selectAll();

      roll.beginMove();
      // A real drag emits a stream of updates; the history must see one entry.
      for (int step = 1; step <= 8; step++) {
        roll.updateMove(step * 240, 0);
      }
      roll.endDrag();

      expect(harness.client.gestureBegins, 1);
      expect(harness.client.gestureCommits, 1);
      expect(harness.client.gestureAborts, 0);
      expect(roll.notes.first.startTicks, 8 * 240);
    });

    test('cancelling a drag aborts the gesture rather than committing it', () {
      final Stage3Harness harness = Stage3Harness()..seedNotes('inst_a');
      final PianoRollStore roll = harness.pianoRoll..selectAll();

      roll
        ..beginMove()
        ..updateMove(480, 2)
        ..cancelDrag();

      expect(harness.client.gestureBegins, 1);
      expect(harness.client.gestureAborts, 1);
      expect(harness.client.gestureCommits, 0);
    });

    test('the selection survives an edit and drops deleted notes', () {
      final Stage3Harness harness = Stage3Harness()..seedNotes('inst_a');
      final PianoRollStore roll = harness.pianoRoll;

      roll.selectOnly(roll.notes.first);
      roll.transposeSelection(12);
      expect(roll.selection.single.key, 72, reason: 'follows the moved note');

      roll.deleteSelection();
      expect(roll.selection, isEmpty);
      expect(roll.notes.length, 3);
    });

    test('quantise pulls an off-grid note onto the grid', () {
      final Stage3Harness harness = Stage3Harness();
      harness.client.addNote('inst_a', 137, 240, 67, velocity: 8000);
      final PianoRollStore roll = harness.pianoRoll
        ..load('inst_a')
        ..setGrid(const GridChoice('1/16', 240))
        ..selectAll();

      roll.quantiseSelection();

      expect(roll.notes.single.startTicks, 240);
    });

    test('drawing reuses the last note length', () {
      final Stage3Harness harness = Stage3Harness();
      final PianoRollStore roll = harness.pianoRoll..load('inst_a');

      roll.addNoteAt(0, 60, length: 960);
      roll.addNoteAt(1920, 62);

      expect(roll.notes.map((SequenceNote n) => n.lengthTicks), <int>[960, 960]);
    });

    test('the viewport is remembered per instrument for the session', () {
      final Stage3Harness harness = Stage3Harness();
      final PianoRollStore roll = harness.pianoRoll..load('inst_a');

      roll.panTo(1920, 72);
      roll.load('inst_b');
      expect(roll.scrollTicks, 1920, reason: 'a fresh instrument keeps the view');

      roll.panTo(0, 84);
      roll.load('inst_a');
      expect(roll.scrollTicks, 1920, reason: 'inst_a restores what it had');
      expect(roll.topKey, 72);
    });

    test('a marquee selects notes it overlaps and no others', () {
      final Stage3Harness harness = Stage3Harness()
        ..seedNotes('inst_a', count: 4);
      final PianoRollStore roll = harness.pianoRoll;

      // Notes sit at ticks 0/240/480/720 on keys 60..63.
      roll
        ..beginMarquee(0, 60)
        ..updateMarquee(500, 61);

      expect(roll.selection.length, 2);
      expect(
        roll.selection.map((SequenceNote n) => n.key).toSet(),
        <int>{60, 61},
      );
    });
  });

  group('pattern management (D-M6)', () {
    test('the shared-pattern notice appears once per pattern per session', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final PatternStore patterns = harness.patterns;
      expect(patterns.current!.usageCount, 2, reason: 'two clips share it');

      patterns.noteEditStarted();
      expect(patterns.notice, isNotNull);
      expect(patterns.notice!.usageCount, 2);
      expect(patterns.notice!.message, contains('used in 2 places'));

      patterns.dismissNotice();
      patterns.noteEditStarted();
      expect(
        patterns.notice,
        isNull,
        reason: 'the second edit of the same pattern must not nag',
      );
    });

    test('a pattern used once raises no notice at all', () {
      final Stage3Harness harness = Stage3Harness();
      harness.client.addClip('lane_a', startTicks: 0, lengthTicks: 3840);
      harness.patterns.refresh();

      harness.patterns.noteEditStarted();

      expect(harness.patterns.notice, isNull);
    });

    test('the notice offers Make unique only with a clip context', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final PatternStore patterns = harness.patterns;

      // Reaching a pattern without going through a clip: "unique for which
      // clip?" has no answer, so the inline action is not offered.
      patterns.noteEditStarted();
      expect(patterns.notice!.canMakeUnique, isFalse);

      // A second shared pattern, reached by double-clicking one of its clips.
      // It has to be a *different* pattern: the once-per-session rule below
      // would otherwise suppress this notice entirely.
      harness.client
        ..createPattern('Chorus Drums')
        ..addClip('lane_a', startTicks: 7680, lengthTicks: 3840)
        ..addClip('lane_a', startTicks: 11520, lengthTicks: 3840);
      patterns.refresh();
      harness.arrangement.refresh();
      final String chorus = patterns.current!.id;
      final String chorusClip = harness.arrangement.clips
          .firstWhere((ArrangementClip clip) => clip.patternId == chorus)
          .id;

      patterns
        ..dismissNotice()
        ..select(chorus, fromClipId: chorusClip);
      patterns.noteEditStarted();

      expect(patterns.notice!.canMakeUnique, isTrue);
      expect(patterns.notice!.clipId, chorusClip);
    });

    test('the once-per-session rule is per pattern, not global', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final PatternStore patterns = harness.patterns;
      final String first = patterns.current!.id;

      patterns.noteEditStarted();
      expect(patterns.notice, isNotNull);
      patterns.dismissNotice();

      harness.client
        ..createPattern('Chorus Drums')
        ..addClip('lane_a', startTicks: 7680, lengthTicks: 3840)
        ..addClip('lane_a', startTicks: 11520, lengthTicks: 3840);
      patterns.refresh();

      patterns.noteEditStarted();
      expect(
        patterns.notice,
        isNotNull,
        reason: 'a different shared pattern deserves its own warning',
      );
      expect(patterns.hasWarnedAbout(first), isTrue);
    });

    test('usage counts are live rather than cached', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      expect(harness.patterns.current!.usageCount, 2);

      harness.arrangement
        ..selectClip(harness.arrangement.clips.first.id)
        ..deleteSelection();

      expect(harness.patterns.current!.usageCount, 1);
    });
  });

  group('Make unique (FR-SEQ-04, D-M3)', () {
    test('diverges the chosen clip and leaves the other sharing', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      harness.client.addNote('inst_a', 0, 240, 60, velocity: 9000);
      harness.patterns.refresh();

      final List<ArrangementClip> before = harness.arrangement.clips;
      final String firstClip = before[0].id;
      final String secondClip = before[1].id;
      final String originalPattern = before[0].patternId;

      harness.patterns.makeUnique(<String>[firstClip]);
      harness.arrangement.refresh();

      final ArrangementClip first = harness.arrangement.clipById(firstClip)!;
      final ArrangementClip second = harness.arrangement.clipById(secondClip)!;
      expect(first.patternId, isNot(originalPattern));
      expect(second.patternId, originalPattern);
      expect(first.name, 'Verse Drums 2');
      expect(first.noteCount, second.noteCount, reason: 'the clone copied notes');

      // Editing the clone must not reach the original.
      harness.patterns.select(first.patternId);
      harness.client.addNote('inst_a', 1920, 240, 72, velocity: 9000);
      harness.arrangement.refresh();
      expect(
        harness.arrangement.clipById(firstClip)!.noteCount,
        harness.arrangement.clipById(secondClip)!.noteCount + 1,
      );
    });

    test('one clone serves a whole multi-clip selection', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final List<String> ids = harness.arrangement.clips
          .map((ArrangementClip clip) => clip.id)
          .toList();

      harness.patterns.makeUnique(ids);
      harness.arrangement.refresh();

      final Set<String> patternIds = harness.arrangement.clips
          .map((ArrangementClip clip) => clip.patternId)
          .toSet();
      expect(patternIds.length, 1, reason: 'both clips share the one clone');
      expect(harness.patterns.patterns.length, 2);
    });
  });

  group('arrangement and clip transforms', () {
    test('moving a clip between lanes changes only the lane', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final ArrangementStore store = harness.arrangement;
      final ArrangementClip clip = store.clips.first;
      final String otherLane = store.lanes
          .firstWhere((ArrangementLane lane) => lane.id != clip.laneId)
          .id;

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

    test('clip windowing and transforms round-trip through the store', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
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
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final ArrangementStore store = harness.arrangement;
      final String id = store.clips.first.id;

      store.setClipTranspose(id, 200);
      expect(store.clipById(id)!.transpose, 48);

      store.setClipTranspose(id, -200);
      expect(store.clipById(id)!.transpose, -48);
    });

    test('a looping clip reports how many times its pattern repeats', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final ArrangementStore store = harness.arrangement;
      final String id = store.clips.first.id;

      store.resizeClip(id, 3840 * 3);

      expect(store.clipById(id)!.repeatCount, 3);
    });

    test('deleting a clip clears it from the selection', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final ArrangementStore store = harness.arrangement;
      final String id = store.clips.first.id;

      store
        ..selectClip(id)
        ..deleteSelection();

      expect(store.selectedClipIds, isEmpty);
      expect(store.clipById(id), isNull);
    });

    test('lane reorder renumbers densely', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final ArrangementStore store = harness.arrangement;
      final String last = store.lanes.last.id;

      store.moveLaneTo(last, 0);

      expect(store.lanes.first.id, last);
      expect(
        store.lanes.map((ArrangementLane lane) => lane.order),
        <int>[0, 1],
      );
    });

    test('the lane event gate is a lane field, never an instrument one', () {
      final Stage3Harness harness = Stage3Harness()..seedArrangement();
      final ArrangementStore store = harness.arrangement;
      final ArrangementLane lane = store.lanes.first;

      store.toggleLaneMute(lane);

      expect(store.lanes.first.muted, isTrue);
      // The clips are untouched: muting a lane gates its events, it does not
      // edit what is on it (D-M4).
      expect(
        store.clipsOnLane(lane.id).every((ArrangementClip clip) => !clip.muted),
        isTrue,
      );
    });
  });
}
