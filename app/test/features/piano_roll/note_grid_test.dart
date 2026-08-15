// Piano roll note grid (UI-B-07): the golden of the body laid out the way the
// screen does it, the viewport round-trip the three lanes depend on, and the
// tap behaviour the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/piano_roll/key_column.dart';
import 'package:onebeat/src/features/piano_roll/note_grid.dart';
import 'package:onebeat/src/features/piano_roll/velocity_lane.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

/// Key column + ruler + canvas + velocity lane, laid out the way the screen
/// does — the golden of the whole body.
class _Body extends StatelessWidget {
  const _Body({super.key});

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(width: tokens.size.prKeyColumnWidth),
            const Expanded(child: PrBarRuler(viewport: demoViewport)),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PrKeyColumn(viewport: demoViewport),
              Expanded(child: PrNoteGrid(vm: demoPianoRoll)),
            ],
          ),
        ),
        PrVelocityLane(vm: demoPianoRoll),
      ],
    );
  }
}

/// The same body, scrolled so a note that starts at tick 0 straddles the left
/// edge. The note's visible sliver has to stop at the key column — the canvas
/// clips, never draws under the keys.
class _ScrolledBody extends StatelessWidget {
  const _ScrolledBody({super.key});

  /// Two bars in, so everything before tick 3840 is off the left edge.
  static const PrViewport viewport = PrViewport(
    ticksPerPx: demoTicksPerPx,
    rowHeight: 14,
    firstVisibleTick: 3840,
    topMidiNote: demoTopMidiNote,
  );

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    // A sixteen-bar note at tick 0: on screen it is a sliver at the very left
    // of the canvas, exactly the note that used to paint over the keys.
    final PianoRollVm vm = PianoRollVm(
      notes: <PrNoteVm>[
        const PrNoteVm(id: 900, startTick: 0, lengthTicks: 960 * 16, midiNote: 70),
        ...demoNotes,
      ],
      viewport: viewport,
    );
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(width: tokens.size.prKeyColumnWidth),
            const Expanded(child: PrBarRuler(viewport: viewport)),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PrKeyColumn(viewport: viewport),
              Expanded(child: PrNoteGrid(vm: vm)),
            ],
          ),
        ),
        PrVelocityLane(vm: vm),
      ],
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the roll body renders as the golden', (WidgetTester tester) async {
    await pumpUi(
      tester,
      const _Body(key: Key('body')),
      size: const Size(1600, 900),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('body')),
      uiGolden('piano_roll_body'),
    );
  });

  testWidgets('a note that starts before the visible area is clipped at the key column', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const _ScrolledBody(key: Key('body-scrolled')),
      size: const Size(1600, 900),
    );
    await tester.pumpAndSettle();
    // The sixteen-bar note at tick 0 pokes into view from the left; the golden
    // records it stopping cleanly at the key column instead of painting over
    // the keys.
    await expectLater(
      find.byKey(const Key('body-scrolled')),
      uiGolden('piano_roll_body_scrolled'),
    );
  });

  test('tick and note round-trip through the viewport', () {
    const PrViewport view = demoViewport;
    for (final int tick in <int>[0, 240, 960, 1440, 3840]) {
      expect(view.tickAt(view.xOf(tick)), tick);
    }
    for (final int midi in <int>[82, 77, 72, 60, 46]) {
      // yOf gives the row's top edge; a point inside the row must map back to
      // the same note, which is what a click has to do.
      expect(view.noteAt(view.yOf(midi) + view.rowHeight / 2), midi);
      expect(view.noteAt(view.yOf(midi)), midi);
    }
  });

  test('a zoom changes the mapping but not its invertibility', () {
    final PrViewport zoomed = demoViewport.copyWith(ticksPerPx: 1.25);
    expect(zoomed.xOf(960), isNot(demoViewport.xOf(960)));
    expect(zoomed.tickAt(zoomed.xOf(960)), 960);
  });

  test('a scrolled viewport keeps the origin at the left edge', () {
    final PrViewport scrolled = demoViewport.copyWith(firstVisibleTick: 960);
    expect(scrolled.xOf(960), 0);
    expect(scrolled.tickAt(0), 960);
  });

  testWidgets('tapping empty canvas reports a tick and a note', (
    WidgetTester tester,
  ) async {
    final List<(int, int)> added = <(int, int)>[];
    await pumpUi(
      tester,
      PrNoteGrid(
        vm: demoPianoRoll,
        onAddNote: (int tick, int midi) => added.add((tick, midi)),
      ),
      size: const Size(1200, 700),
    );
    // A point in the empty top-left corner of the canvas: bar 1, top row.
    await tester.tapAt(const Offset(4, 4));
    expect(added, <(int, int)>[(demoViewport.tickAt(4), demoTopMidiNote)]);
  });

  testWidgets('tapping a note selects it instead of adding one', (
    WidgetTester tester,
  ) async {
    final List<int> selected = <int>[];
    final List<(int, int)> added = <(int, int)>[];
    await pumpUi(
      tester,
      PrNoteGrid(
        vm: demoPianoRoll,
        onSelectNote: selected.add,
        onAddNote: (int tick, int midi) => added.add((tick, midi)),
      ),
      size: const Size(1200, 700),
    );
    // Note 7: MIDI 70 at bar 0, a quarter long.
    final PrNoteVm target = demoNotes[6];
    await tester.tapAt(
      Offset(
        demoViewport.xOf(target.startTick + target.lengthTicks ~/ 2),
        demoViewport.yOf(target.midiNote) + demoViewport.rowHeight / 2,
      ),
    );
    expect(selected, <int>[target.id]);
    expect(added, isEmpty);
  });

  test('painters repaint on a new vm and not on an identical one', () {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    PrGridPainter build(PianoRollVm vm) => PrGridPainter(
      vm: vm,
      color: tokens.color,
      noteHeight: tokens.size.prNoteHeight,
      noteRadius: tokens.radius.xs,
      lineWidth: tokens.border.hairline,
      playheadWidth: tokens.size.playheadWidth,
    );
    final PrGridPainter same = build(demoPianoRoll);
    expect(build(demoPianoRoll).shouldRepaint(same), isFalse);

    final PianoRollVm moved = PianoRollVm(
      notes: demoNotes,
      ghostNotes: demoGhostNotes,
      viewport: demoViewport,
      playheadTick: demoPlayheadTick + 240,
      selected: demoSelected,
    );
    expect(build(moved).shouldRepaint(same), isTrue);
  });

  test('a beat is the model\'s beat, not a sixteenth of one', () {
    // The painter and the store have to agree about what a tick is: notes
    // arrive from the ABI at 960 PPQN, so a "beat line" is 960 ticks apart and
    // a bar is four of them.
    expect(prTicksPerBeat, 960);
    expect(demoViewport.ticksPerBar, 960 * 4);
  });

  test('a chromatic scale bands by the keyboard, not by the scale', () {
    const PianoRollVm chromatic = PianoRollVm(
      notes: <PrNoteVm>[],
      viewport: demoViewport,
      scaleIntervals: <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    );
    expect(chromatic.hasScale, isFalse, reason: 'twelve of twelve says nothing');
    // With no scale selected at all, every row is "in".
    const PianoRollVm none = PianoRollVm(
      notes: <PrNoteVm>[],
      viewport: demoViewport,
    );
    expect(none.hasScale, isFalse);
    expect(none.inScale(61), isTrue);
  });

  test('a selected scale sorts rows into in and out', () {
    // C minor: C D E♭ F G A♭ B♭.
    const PianoRollVm cMinor = PianoRollVm(
      notes: <PrNoteVm>[],
      viewport: demoViewport,
      scaleIntervals: <int>[0, 2, 3, 5, 7, 8, 10],
    );
    expect(cMinor.hasScale, isTrue);
    expect(cMinor.inScale(60), isTrue, reason: 'C');
    expect(cMinor.inScale(63), isTrue, reason: 'E♭');
    expect(cMinor.inScale(64), isFalse, reason: 'E is out of C minor');
  });

  test('a scale follows its root', () {
    const PianoRollVm dMinor = PianoRollVm(
      notes: <PrNoteVm>[],
      viewport: demoViewport,
      scaleIntervals: <int>[0, 2, 3, 5, 7, 8, 10],
      scaleRoot: 2,
    );
    expect(dMinor.inScale(64), isTrue, reason: 'E is in D minor');
    expect(dMinor.inScale(63), isFalse, reason: 'E♭ is not');
  });

  test('the painter repaints when the sounding rows change', () {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    PrGridPainter build(PianoRollVm vm) => PrGridPainter(
      vm: vm,
      color: tokens.color,
      noteHeight: tokens.size.prNoteHeight,
      noteRadius: tokens.radius.xs,
      lineWidth: tokens.border.hairline,
      playheadWidth: tokens.size.playheadWidth,
    );
    final PianoRollVm lit = PianoRollVm(
      notes: demoNotes,
      viewport: demoViewport,
      activeKeys: const <int>{70},
    );
    expect(build(lit).shouldRepaint(build(demoPianoRoll)), isTrue);
  });
}
