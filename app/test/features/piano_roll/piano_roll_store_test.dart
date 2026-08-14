// Store-level behaviour for PianoRollStore: drags are single gestures, the
// selection survives edits, quantise snaps, and the viewport is per instrument.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_store.dart';
import 'package:onebeat/src/engine/engine_client.dart';

import '../../support/app_harness.dart';

void main() {
  test('a move drag is one gesture no matter how many steps it takes', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
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
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
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
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll;

    roll.selectOnly(roll.notes.first);
    roll.transposeSelection(12);
    expect(roll.selection.single.key, 72, reason: 'follows the moved note');

    roll.deleteSelection();
    expect(roll.selection, isEmpty);
    expect(roll.notes.length, 3);
  });

  test('quantise pulls an off-grid note onto the grid', () {
    final EditorHarness harness = EditorHarness();
    harness.client.addNote('inst_a', 137, 240, 67, velocity: 8000);
    final PianoRollStore roll = harness.pianoRoll
      ..load('inst_a')
      ..setGrid(const GridChoice('1/16', 240))
      ..selectAll();

    roll.quantiseSelection();

    expect(roll.notes.single.startTicks, 240);
  });

  test('drawing reuses the last note length', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');

    roll.addNoteAt(0, 60, length: 960);
    roll.addNoteAt(1920, 62);

    expect(roll.notes.map((SequenceNote n) => n.lengthTicks), <int>[960, 960]);
  });

  test('the viewport is remembered per instrument for the session', () {
    final EditorHarness harness = EditorHarness();
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
    final EditorHarness harness = EditorHarness()
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
}
