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

  test('copy then paste puts the phrase back where it was taken from', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    roll
      ..addNoteAt(960, 60, length: 240)
      ..addNoteAt(1200, 64, length: 240);
    roll.selectAll();

    roll.copySelection();
    roll.deleteSelection();
    expect(roll.notes, isEmpty);

    roll.pasteClipboard();

    expect(
      roll.notes.map((SequenceNote n) => n.startTicks).toList()..sort(),
      <int>[960, 1200],
      reason: 'the phrase keeps its shape and its place',
    );
    expect(roll.notes.map((SequenceNote n) => n.key).toSet(), <int>{60, 64});
    expect(
      roll.selection.length,
      2,
      reason: 'the paste is what the next gesture acts on',
    );
  });

  test('a paste can be dropped at another tick, keeping its shape', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    roll
      ..addNoteAt(960, 60, length: 240)
      ..addNoteAt(1200, 64, length: 240);
    roll
      ..selectAll()
      ..copySelection()
      ..deleteSelection();

    roll.pasteClipboard(atTick: 0);

    expect(
      roll.notes.map((SequenceNote n) => n.startTicks).toList()..sort(),
      <int>[0, 240],
      reason: 'the gap between the two voices survives the move',
    );
  });

  test('a paste is one undo step however many notes it lands', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    roll
      ..addNoteAt(0, 60, length: 240)
      ..addNoteAt(240, 62, length: 240)
      ..addNoteAt(480, 64, length: 240)
      ..selectAll()
      ..copySelection();
    final int beginsBefore = harness.client.gestureBegins;

    roll.pasteClipboard(atTick: 1920);

    expect(harness.client.gestureBegins, beginsBefore + 1);
    expect(harness.client.gestureCommits, harness.client.gestureBegins);
  });

  test('cut takes the notes away and keeps them for the paste', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    roll
      ..addNoteAt(480, 67, length: 240)
      ..selectAll()
      ..cutSelection();

    expect(roll.notes, isEmpty);
    expect(roll.hasClipboard, isTrue);

    roll.pasteClipboard();
    expect(roll.notes.single.key, 67);
    expect(roll.notes.single.startTicks, 480);
  });

  test('duplicate lands the copy one selection-length later', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    roll
      ..setGrid(const GridChoice('1/4', ticksPerQuarter))
      ..addNoteAt(0, 60, length: 960)
      ..selectAll()
      ..duplicateSelection();

    expect(
      roll.notes.map((SequenceNote n) => n.startTicks).toList()..sort(),
      <int>[0, 960],
    );
    expect(
      roll.selection.single.startTicks,
      960,
      reason: 'the copy is selected, so ⌘B again walks it along',
    );
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

  test('an anchored zoom keeps the anchor tick under the same pixel', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll..panTo(1920, 84);

    // The pixel the anchor sat at before the zoom...
    const double anchor = 3840;
    final double pixelBefore = (anchor - roll.scrollTicks) * roll.pixelsPerTick;

    roll.zoomHorizontally(2.0, anchorTick: anchor);

    final double pixelAfter = (anchor - roll.scrollTicks) * roll.pixelsPerTick;
    expect(pixelAfter, closeTo(pixelBefore, 0.001));
    expect(roll.horizontalZoom, 2.0);
  });

  test('an unanchored zoom leaves the scroll position alone', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll..panTo(1920, 84);

    roll.zoomHorizontally(2.0);

    expect(roll.scrollTicks, 1920);
  });

  test('zooming does not scroll past the start of the pattern', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll..panTo(0, 84);

    roll.zoomHorizontally(0.5, anchorTick: 0);

    expect(roll.scrollTicks, greaterThanOrEqualTo(0));
  });

  test('panning stops at the ends of the keyboard and the pattern', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll..panTo(0, 84);

    roll.panBy(deltaTicks: -10000, deltaKeys: 99);
    expect(roll.scrollTicks, 0, reason: 'time does not go negative');
    expect(roll.topKey, 127, reason: 'and the keyboard has a top');

    // With 24 rows on screen the lowest row must still be key 0, so the top
    // row can go no lower than 23.
    roll.panBy(deltaKeys: -999, visibleRows: 24);
    expect(roll.topKey, 23);
  });

  test('choosing a snap resolution arms the next note length', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');

    roll.setGrid(const GridChoice('1/8', ticksPerQuarter ~/ 2));
    roll.addNoteAt(0, 60);

    expect(roll.notes.single.lengthTicks, ticksPerQuarter ~/ 2);
  });

  test('"Snap: Off" leaves the note length where it was', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');

    roll.addNoteAt(0, 60, length: 960);
    roll.setGrid(const GridChoice('Off', 0));
    roll.addNoteAt(1920, 62);

    expect(roll.notes.map((SequenceNote n) => n.lengthTicks), <int>[960, 960]);
  });

  test('the lane edits one note without flattening the selection', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll..selectAll();
    final SequenceNote target = roll.notes.first;

    roll.setNoteVelocity(target, 4000);

    final List<SequenceNote> byKey = roll.notes.toList()
      ..sort((SequenceNote a, SequenceNote b) => a.key.compareTo(b.key));
    expect(byKey.first.velocity, 4000);
    expect(
      byKey.skip(1).map((SequenceNote n) => n.velocity),
      everyElement(9000),
      reason: 'the other selected notes are untouched',
    );
  });

  test('an edited note stays selected under its new value', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll;
    final SequenceNote target = roll.notes.first;
    roll.selectOnly(target);

    roll.setNoteVelocity(target, 4000);

    expect(roll.selection.single.velocity, 4000);
  });

  test('the lane hit-tests the nearest stem within tolerance', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll;

    // Notes start at 0/240/480/720.
    expect(roll.noteNearTick(250, 40)?.startTicks, 240);
    expect(roll.noteNearTick(600, 40), isNull, reason: 'nothing is close');
  });

  test('a chord reports every stem that shares its lane position', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    // Three voices starting together, plus one that does not.
    roll
      ..addNoteAt(0, 60, length: 240)
      ..addNoteAt(0, 64, length: 240)
      ..addNoteAt(0, 67, length: 240)
      ..addNoteAt(960, 72, length: 240);

    expect(roll.notesNearTick(0, 40).length, 3);
    expect(roll.notesNearTick(960, 40).length, 1);
    expect(roll.notesNearTick(2000, 40), isEmpty);
  });

  test('a preview lights its key and goes dark when released', () {
    final EditorHarness harness = EditorHarness()..seedNotes('inst_a');
    final PianoRollStore roll = harness.pianoRoll;

    expect(roll.auditionKey, isNull);
    roll.audition(64);
    expect(roll.auditionKey, 64);

    roll.stopAudition();
    expect(roll.auditionKey, isNull);
  });

  test('the scroll extent covers the last note plus room to keep writing', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');

    roll.addNoteAt(ticksPerBar * 7, 60, length: ticksPerQuarter);

    expect(roll.contentEndTicks, greaterThan(ticksPerBar * 7));
  });

  test('an erase sweep is one undo step whatever it crosses', () {
    final EditorHarness harness = EditorHarness();
    final PianoRollStore roll = harness.pianoRoll..load('inst_a');
    roll
      ..addNoteAt(0, 60, length: ticksPerQuarter)
      ..addNoteAt(ticksPerQuarter, 60, length: ticksPerQuarter);
    final int notesBefore = roll.notes.length;

    roll.beginErase();
    expect(roll.eraseAt(ticksPerQuarter ~/ 2, 60), isTrue);
    // Empty canvas, and a row the sweep only passed over.
    expect(roll.eraseAt(ticksPerQuarter ~/ 2, 61), isFalse);
    expect(roll.eraseAt(ticksPerQuarter + 10, 60), isTrue);
    roll.endDrag();

    expect(roll.notes.length, notesBefore - 2);
    expect(roll.dragKind, PianoDragKind.none);
  });
}
