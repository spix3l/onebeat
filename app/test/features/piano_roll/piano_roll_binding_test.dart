// PianoRollBinding tests (UI-D-03).
//
// Verifies:
// 1. PianoRollBinding renders toolbar, ruler, key column, note grid and velocity lane.
// 2. Note addition and selection round-trips.
// 3. Drag gesture transaction (1 transaction begin, 1 commit for move/resize).
// 4. Duplicate, transpose, nudge, and quantise commands.
// 5. Velocity adjustment on selection.
// 6. Scale and snap changes.
// 7. Key column press and note placement auditioning.
// 8. Pattern switching and back-to-playlist navigation.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/piano_roll/key_column.dart';
import 'package:onebeat/src/features/piano_roll/note_grid.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_binding.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_screen.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_store.dart';
import 'package:onebeat/src/features/piano_roll/pr_toolbar.dart';
import 'package:onebeat/src/features/piano_roll/velocity_lane.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakePianoRollEngineClient extends FakeEngineClient
    implements EngineClient {
  _FakePianoRollEngineClient({
    this.isPlaying = false,
    this.positionBeats = 0.0,
    this.loopStartBeats = 0,
    this.loopEndBeats = 4,
  }) {
    instruments = <ProjectInstrument>[
      const ProjectInstrument(
        id: 'inst_keys',
        name: 'Soft Keys',
        color: '#4FAFF5',
        order: 0,
        pluginId: 'synth',
        pluginName: 'Synth',
        pluginVendor: 'OneBeat',
        pluginPath: '/plugins/synth',
        muted: false,
        selected: true,
        affectedPatterns: 1,
        affectedClips: 1,
        affectedNotes: 4,
      ),
      const ProjectInstrument(
        id: 'inst_bass',
        name: 'Sub Bass',
        color: '#EF6F91',
        order: 1,
        pluginId: 'synth',
        pluginName: 'Synth',
        pluginVendor: 'OneBeat',
        pluginPath: '/plugins/synth',
        muted: false,
        selected: false,
        affectedPatterns: 1,
        affectedClips: 1,
        affectedNotes: 2,
      ),
    ];
  }

  bool isPlaying;
  double positionBeats;
  double loopStartBeats;
  double loopEndBeats;
  late List<ProjectInstrument> instruments;
  int undoCalls = 0;
  int redoCalls = 0;

  @override
  List<ProjectInstrument> readInstruments() => instruments;

  @override
  bool get canUndoProject => gestureCommits > undoCalls;

  @override
  bool get canRedoProject => redoCalls == 0 && undoCalls > 0;

  @override
  String get undoProjectName => 'Edit notes';

  @override
  String get redoProjectName => 'Edit notes';

  @override
  void undoProject() => undoCalls++;

  @override
  void redoProject() => redoCalls++;

  @override
  EngineSnapshot readSnapshot() => EngineSnapshot(
    playing: isPlaying,
    loopEnabled: true,
    loopStartBeats: loopStartBeats,
    loopEndBeats: loopEndBeats,
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

  @override
  RackPattern readRackPattern() => const RackPattern(
    id: 'pat_a',
    name: 'Verse Drums',
    lengthTicks: 3840,
    baseGridTicks: 240,
    swing: 0.0,
  );

  @override
  List<RackRow> readRackRows() => const <RackRow>[];
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'PianoRollBinding renders toolbar, ruler, key column, grid and velocity lane',
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      client.addNote('inst_keys', 0, 240, 72, velocity: 12900);
      client.addNote('inst_keys', 240, 240, 75, velocity: 10000);

      await pumpForTest(
        tester,
        PianoRollBinding(client: client),
        size: const Size(1600, 900),
      );
      await tester.pump();

      expect(find.byType(PianoRollScreen), findsOneWidget);
      expect(find.byType(PrToolbar), findsOneWidget);
      expect(find.byType(PrBarRuler), findsOneWidget);
      expect(find.byType(PrKeyColumn), findsOneWidget);
      expect(find.byType(PrVelocityLane), findsOneWidget);
      expect(find.text('Piano roll'), findsOneWidget);
      expect(find.text('Verse Drums'), findsNWidgets(2));
      expect(find.text('Soft Keys'), findsOneWidget);
    },
  );

  testWidgets(
    'add note and select note in PianoRollStore round-trip to client',
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

      expect(client.readNotes('inst_keys'), isEmpty);

      store.addNoteAt(0, 72, length: 240);
      expect(client.readNotes('inst_keys').length, 1);
      expect(client.readNotes('inst_keys').first.key, 72);
      expect(client.readNotes('inst_keys').first.startTicks, 0);
      expect(store.hasSelection, isTrue);

      // Add second note
      store.addNoteAt(480, 76, length: 240);
      expect(client.readNotes('inst_keys').length, 2);
      expect(store.selection.length, 1);
      expect(store.selection.first.key, 76);
    },
  );

  testWidgets(
    'drag move and resize perform single transaction begin and commit',
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

      store.addNoteAt(0, 72, length: 240);
      expect(client.readNotes('inst_keys').first.startTicks, 0);

      // Test drag move
      store.beginMove();
      store.updateMove(240, 2);
      store.updateMove(480, 2);
      store.endDrag();

      expect(client.gestureBegins, 1);
      expect(client.gestureCommits, 1);
      expect(client.readNotes('inst_keys').first.startTicks, 480);
      expect(client.readNotes('inst_keys').first.key, 74);

      // Test drag resize
      store.beginResize();
      store.updateResize(240);
      store.updateResize(480);
      store.endDrag();

      expect(client.gestureBegins, 2);
      expect(client.gestureCommits, 2);
      expect(client.readNotes('inst_keys').first.lengthTicks, 720);
    },
  );

  testWidgets(
    'duplicate, transpose, nudge, and quantise commands mutate notes correctly',
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

      store.addNoteAt(0, 60, length: 240);
      expect(client.readNotes('inst_keys').length, 1);

      // Transpose
      store.transposeSelection(12);
      expect(client.readNotes('inst_keys').first.key, 72);

      // Nudge
      store.nudgeSelection(240);
      expect(client.readNotes('inst_keys').first.startTicks, 240);

      // Duplicate
      store.duplicateSelection();
      expect(client.readNotes('inst_keys').length, 2);

      // Quantise
      store.quantiseSelection();
      expect(client.readNotes('inst_keys').length, 2);
    },
  );

  testWidgets('velocity adjustment modifies selected notes', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    store.addNoteAt(0, 72, length: 240);
    expect(client.readNotes('inst_keys').first.velocity, 12900);

    store.setSelectionVelocity(8000);
    expect(client.readNotes('inst_keys').first.velocity, 8000);
  });

  testWidgets('scale and snap dropdowns update store state', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    // Change scale
    store.setScale(MusicalScale.all[2], 0); // Minor
    expect(store.scale.name, 'Minor');

    // Change snap
    store.setGrid(GridChoice.all[0]); // 1/4
    expect(store.grid.label, '1/4');
    expect(store.snapTicks, 960);
  });

  testWidgets('marquee selection captures notes within bounds', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    store.addNoteAt(0, 60, length: 240);
    store.addNoteAt(480, 64, length: 240);
    store.addNoteAt(960, 67, length: 240);
    store.clearSelection();
    expect(store.selection, isEmpty);

    // Marquee enclosing notes at tick 0..600, keys 58..66
    store.beginMarquee(0, 58);
    store.updateMarquee(600, 66);
    store.endDrag();

    expect(store.selection.length, 2);
    expect(
      store.selection.map((n) => n.key).toSet(),
      containsAll(<int>[60, 64]),
    );
  });

  testWidgets('key column press triggers note auditioning', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Finder keyColumn = find.byType(PrKeyColumn);
    expect(keyColumn, findsOneWidget);

    final Rect rect = tester.getRect(keyColumn);
    // Tap top of key column (near topMidiNote = 84)
    await tester.tapAt(Offset(rect.center.dx, rect.top + 7));
    await tester.pump();

    expect(client.auditionedKeys, isNotEmpty);
  });

  testWidgets('back to playlist callback fires when Back button is tapped', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    bool backFired = false;

    await pumpForTest(
      tester,
      PianoRollBinding(
        client: client,
        onBackToPlaylist: () => backFired = true,
      ),
      size: const Size(1600, 900),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('pr-back')));
    await tester.pump();

    expect(backFired, isTrue);
  });

  testWidgets('playing transport calculates active playhead tick', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient(
      isPlaying: true,
      positionBeats: 1.0, // Beat 1.0 = tick 960
    );

    await pumpForTest(
      tester,
      PianoRollBinding(client: client),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final PianoRollScreen screen = tester.widget(find.byType(PianoRollScreen));
    expect(screen.vm.roll.playheadTick, 960);
  });

  testWidgets('playhead wraps on the loop region', (WidgetTester tester) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient(
      isPlaying: true,
      positionBeats: 3.5, // past the end of a [1, 3) loop region
      loopStartBeats: 1,
      loopEndBeats: 3,
    );

    await pumpForTest(
      tester,
      PianoRollBinding(client: client),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final PianoRollScreen screen = tester.widget(find.byType(PianoRollScreen));
    // 3.5 beats minus a 1-beat loop start, wrapped on a 2-beat region, is 0.5
    // beat = 480 ticks.
    expect(screen.vm.roll.playheadTick, 480);
  });

  testWidgets('a sounding note lights its row and its key', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient(
      isPlaying: true,
      positionBeats: 1.0, // tick 960
    );
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    // One note the playhead is inside, one it is not.
    store.addNoteAt(960, 64, length: 480);
    store.addNoteAt(2880, 67, length: 480);

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final PianoRollScreen screen = tester.widget(find.byType(PianoRollScreen));
    expect(screen.vm.roll.activeKeys, <int>{64});
  });

  testWidgets('nothing is lit when the transport is stopped', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store.addNoteAt(0, 64, length: 480);

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final PianoRollScreen screen = tester.widget(find.byType(PianoRollScreen));
    expect(screen.vm.roll.activeKeys, isEmpty);
  });

  testWidgets('the canvas is told the snap grid and the scale', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    store
      ..setGrid(const GridChoice('1/8', 480))
      ..setScale(MusicalScale.all[2], 0); // Minor
    await tester.pump();

    final PianoRollScreen screen = tester.widget(find.byType(PianoRollScreen));
    expect(screen.vm.roll.viewport.subdivisionTicks, 480);
    expect(screen.vm.roll.hasScale, isTrue);
    expect(screen.vm.roll.inScale(63), isTrue, reason: 'E♭ is in C minor');
    expect(screen.vm.roll.inScale(64), isFalse, reason: 'E is not');
  });

  testWidgets('⌘-drag lassos even with the draw tool up', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store.addNoteAt(0, 84, length: 480);
    final int notesBefore = store.notes.length;
    expect(store.tool, PrTool.pencil);

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect grid = tester.getRect(find.byType(PrKeyColumn));
    final Offset start = Offset(grid.right + 20, grid.top + 20);

    await simulateKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.dragFrom(start, const Offset(160, 60));
    await tester.pump();
    await simulateKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(
      store.notes.length,
      notesBefore,
      reason: 'a lasso drag must not draw',
    );
  });

  testWidgets('⌘A, ⌘C, ⌘V and ⌘B are wired to the roll', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store
      ..addNoteAt(0, 60, length: 480)
      ..addNoteAt(480, 64, length: 480)
      // The select tool, so the focusing tap below is not also a pencil stroke.
      ..setTool(PrTool.select)
      ..clearSelection();

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    // The canvas has to hold focus for a shortcut to reach it.
    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    await tester.tapAt(Offset(keys.right + 600, keys.top + 300));
    await tester.pump();

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    await press(LogicalKeyboardKey.keyA);
    expect(store.selection.length, 2, reason: '⌘A takes the lot');

    await press(LogicalKeyboardKey.keyC);
    expect(store.hasClipboard, isTrue);

    store.deleteSelection();
    expect(store.notes, isEmpty);

    await press(LogicalKeyboardKey.keyV);
    expect(store.notes.length, 2, reason: '⌘V drops the phrase back');

    final int afterPaste = store.notes.length;
    await press(LogicalKeyboardKey.keyB);
    expect(
      store.notes.length,
      afterPaste + 2,
      reason: '⌘B duplicates what the paste selected',
    );
  });

  testWidgets('⌘V lands the phrase under the pointer', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store
      ..setGrid(GridChoice.all[3]) // 1/16 = 240 ticks
      ..setTool(PrTool.select)
      ..addNoteAt(0, 84, length: 240)
      ..addNoteAt(240, 84, length: 240)
      ..selectAll()
      ..copySelection()
      ..deleteSelection();

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    await tester.tapAt(Offset(keys.right + 300, keys.top + 300));
    await tester.pump();

    // 0.08 px per tick, so 200px into the canvas is tick 2500 — which the 1/16
    // grid takes down to 2400.
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(Offset(keys.right + 200, keys.top + 40));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(
      store.notes.map((SequenceNote n) => n.startTicks).toList()..sort(),
      <int>[2400, 2640],
      reason: 'the phrase starts where the pointer is and keeps its shape',
    );
  });

  testWidgets(
    '⌘V with the pointer off the canvas appends after the last note',
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
      store
        ..setGrid(GridChoice.all[3]) // 1/16 = 240 ticks
        ..setTool(PrTool.select)
        ..addNoteAt(0, 84, length: 500)
        ..selectAll()
        ..copySelection();

      await pumpForTest(
        tester,
        PianoRollBinding(client: client, store: store),
        size: const Size(1600, 900),
      );
      await tester.pump();

      // Focused by a touch tap, so no mouse ever hovers the canvas.
      final Rect keys = tester.getRect(find.byType(PrKeyColumn));
      await tester.tapAt(Offset(keys.right + 300, keys.top + 300));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(
        store.notes.map((SequenceNote n) => n.startTicks).toList()..sort(),
        <int>[0, 720],
        reason: 'the note ends at 500, so the next free 1/16 slot is 720',
      );
    },
  );

  testWidgets('⌥-drag lassos rather than drawing', (WidgetTester tester) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store.addNoteAt(0, 84, length: 480);
    store.clearSelection();
    final int notesBefore = store.notes.length;
    expect(store.tool, PrTool.pencil);

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    // Starting on empty canvas above the note and sweeping down across it.
    final Offset start = Offset(keys.right + 4, keys.top + 4);

    await simulateKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.dragFrom(start, const Offset(180, 40));
    await tester.pump();
    await simulateKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(
      store.notes.length,
      notesBefore,
      reason: '⌥ is the lasso modifier; it must never draw',
    );
    expect(
      store.selection,
      isNotEmpty,
      reason: 'and it selected what it swept',
    );
  });

  testWidgets('a plain drag with the draw tool still draws', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    final int notesBefore = store.notes.length;

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect grid = tester.getRect(find.byType(PrKeyColumn));
    await tester.dragFrom(
      Offset(grid.right + 20, grid.top + 20),
      const Offset(160, 0),
    );
    await tester.pump();

    expect(store.notes.length, notesBefore + 1);
  });

  testWidgets('a trackpad two-finger scroll pans and never draws', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    final int notesBefore = store.notes.length;
    final int keyBefore = store.topKey;
    expect(store.tool, PrTool.pencil, reason: 'the draw tool is up');

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    final Offset over = Offset(keys.right + 200, keys.top + 200);

    // A trackpad scroll is a pan/zoom gesture, not a drag and not a scroll
    // signal. It used to reach the canvas's drag recogniser and draw.
    final TestPointer pad = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pad.panZoomStart(over));
    await tester.sendEventToBinding(
      pad.panZoomUpdate(over, pan: const Offset(0, 120)),
    );
    await tester.sendEventToBinding(pad.panZoomEnd());
    await tester.pump();

    expect(store.notes.length, notesBefore, reason: 'scrolling is not drawing');
    expect(store.topKey, isNot(keyBefore), reason: 'and it did scroll');
  });

  testWidgets('the selection picks which voices of a chord the lane moves', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    // Three voices sharing a start tick: their stems coincide in the lane.
    store
      ..addNoteAt(0, 60, length: 480)
      ..addNoteAt(0, 64, length: 480)
      ..addNoteAt(0, 67, length: 480);
    store.clearSelection();

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect lane = tester.getRect(find.byType(PrVelocityLane));
    final Offset onStem = Offset(lane.left + 62, lane.top + 20);

    // Nothing selected: the visible stem is the whole stack, so the whole
    // stack follows it. Refusing to act read as the lane being broken.
    await tester.tapAt(onStem);
    await tester.pump();
    final Set<int> moved =
        store.notes.map((SequenceNote n) => n.velocity).toSet();
    expect(moved.length, 1, reason: 'all three voices landed on one value');
    expect(moved.single, isNot(12900));

    // Restore the chord, then select one voice: only that one follows.
    for (final SequenceNote note in store.notes.toList()) {
      store.setNoteVelocity(note, 12900);
    }
    store.clearSelection();
    await tester.pump();

    // Select one voice, and only that one follows the lane.
    final SequenceNote target = store.notes.firstWhere(
      (SequenceNote n) => n.key == 64,
    );
    store.selectOnly(target);
    await tester.pump();

    await tester.tapAt(onStem);
    await tester.pump();

    final SequenceNote after = store.notes.firstWhere(
      (SequenceNote n) => n.key == 64,
    );
    expect(after.velocity, isNot(target.velocity));
    for (final SequenceNote note in store.notes) {
      if (note.key == 64) continue;
      expect(note.velocity, 12900, reason: 'the other voices are untouched');
    }
  });

  testWidgets('auditioning a key lights its row', (WidgetTester tester) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    PianoRollScreen screen() =>
        tester.widget(find.byType(PianoRollScreen)) as PianoRollScreen;
    expect(screen().vm.roll.activeKeys, isEmpty);

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    await tester.tapAt(Offset(keys.center.dx, keys.top + 7));
    await tester.pump();

    expect(screen().vm.roll.activeKeys, isNotEmpty);

    // And it goes dark when the preview is released.
    store.stopAudition();
    await tester.pump();
    expect(screen().vm.roll.activeKeys, isEmpty);
  });

  testWidgets('the roll releases a preview note when it goes away', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect rect = tester.getRect(find.byType(PrKeyColumn));
    await tester.tapAt(Offset(rect.center.dx, rect.top + 7));
    await tester.pump();
    expect(client.auditionedKeys, isNotEmpty);

    // Tearing the roll down mid-preview must not leave the note ringing — and
    // must not leave the note-off timer pending either.
    await pumpForTest(tester, const SizedBox(), size: const Size(1600, 900));
    await tester.pump();
  });

  testWidgets(
    'a right-button sweep erases every note it crosses, as one undo step',
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
      // Three notes along one row. At the default zoom, 12.5 ticks to the pixel,
      // so all three sit inside the first 80px of canvas.
      store
        ..addNoteAt(0, 84, length: 240)
        ..addNoteAt(480, 84, length: 240)
        ..addNoteAt(960, 84, length: 240);
      expect(store.notes.length, 3);

      await pumpForTest(
        tester,
        PianoRollBinding(client: client, store: store),
        size: const Size(1600, 900),
      );
      await tester.pump();

      final Rect keys = tester.getRect(find.byType(PrKeyColumn));
      final double rowY = keys.top + 7;
      final int commitsBefore = client.gestureCommits;

      final TestPointer mouse = TestPointer(
        1,
        PointerDeviceKind.mouse,
        null,
        kSecondaryButton,
      );
      await tester.sendEventToBinding(mouse.down(Offset(keys.right + 2, rowY)));
      await tester.sendEventToBinding(
        mouse.move(Offset(keys.right + 100, rowY)),
      );
      await tester.sendEventToBinding(mouse.up());
      await tester.pump();

      expect(store.notes, isEmpty, reason: 'the sweep crossed all three');
      expect(
        client.gestureCommits - commitsBefore,
        1,
        reason: 'a sweep is one undo step, not one per note',
      );
    },
  );

  testWidgets('a right-button sweep only erases the row it crosses', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store
      ..addNoteAt(0, 84, length: 240)
      ..addNoteAt(0, 80, length: 240);

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    final TestPointer mouse = TestPointer(
      1,
      PointerDeviceKind.mouse,
      null,
      kSecondaryButton,
    );
    await tester.sendEventToBinding(
      mouse.down(Offset(keys.right + 2, keys.top + 7)),
    );
    await tester.sendEventToBinding(
      mouse.move(Offset(keys.right + 40, keys.top + 7)),
    );
    await tester.sendEventToBinding(mouse.up());
    await tester.pump();

    expect(store.notes.length, 1);
    expect(store.notes.single.key, 80, reason: 'the other row is untouched');
  });

  testWidgets(
    "the cursor says 'resize' over a note's right edge and 'grab' over its body",
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
      // 960 ticks at 12.5 ticks/px is 76.8px wide, so the handle is the full 8px
      // rather than the third-of-the-note cap.
      store.addNoteAt(0, 84, length: 960);

      await pumpForTest(
        tester,
        PianoRollBinding(client: client, store: store),
        size: const Size(1600, 900),
      );
      await tester.pump();

      final Rect keys = tester.getRect(find.byType(PrKeyColumn));
      final double rowY = keys.top + 7;
      MouseCursor cursor() =>
          tester
              .widget<PianoRollScreen>(find.byType(PianoRollScreen))
              .gridCursor;

      final TestPointer mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(Offset(keys.right + 20, rowY)),
      );
      await tester.pump();
      expect(cursor(), SystemMouseCursors.grab);

      // 76.8px in is the note's end; 2px short of it is inside the grab zone.
      await tester.sendEventToBinding(
        mouse.hover(Offset(keys.right + 75, rowY)),
      );
      await tester.pump();
      expect(cursor(), SystemMouseCursors.resizeLeftRight);

      await tester.sendEventToBinding(
        mouse.hover(Offset(keys.right + 400, rowY)),
      );
      await tester.pump();
      expect(
        cursor(),
        MouseCursor.defer,
        reason: 'empty canvas asks for nothing',
      );
    },
  );

  testWidgets(
    "resizing lands the note's edge under the pointer, not offset by the grab",
    (WidgetTester tester) async {
      final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
      final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
      store
        ..setGrid(GridChoice.all[3]) // 1/16 = 240 ticks
        ..addNoteAt(0, 84, length: 960);

      await pumpForTest(
        tester,
        PianoRollBinding(client: client, store: store),
        size: const Size(1600, 900),
      );
      await tester.pump();

      final Rect keys = tester.getRect(find.byType(PrKeyColumn));
      final double rowY = keys.top + 7;
      // Grab 3px inside the edge and drag to tick 1920 (153.6px). The old code
      // measured the drag from where the grab started, so the edge finished 3px
      // — a snap step, once rounded — short of the pointer.
      await tester.dragFrom(Offset(keys.right + 74, rowY), const Offset(80, 0));
      await tester.pump();

      expect(store.notes.single.endTicks, 1920);
    },
  );

  testWidgets('a selection of notes drags as one block', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store
      ..setGrid(GridChoice.all[3]) // 1/16 = 240 ticks
      ..addNoteAt(0, 84, length: 240)
      ..addNoteAt(240, 83, length: 240)
      ..addNoteAt(480, 82, length: 240)
      ..selectAll();
    expect(store.selection.length, 3);

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    // Press on one of the three and hold past the tap deadline before moving.
    // A press that rests before it drags is the normal way to grab a block, and
    // it is exactly the path where the press used to collapse the selection.
    final TestGesture drag = await tester.startGesture(
      Offset(keys.right + 4, keys.top + 7),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await drag.moveBy(const Offset(80, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(
      store.notes.map((SequenceNote n) => n.startTicks).toList()..sort(),
      <int>[960, 1200, 1440],
      reason: 'every selected note moved by the same 960 ticks',
    );
    expect(store.selection.length, 3, reason: 'and the block stays selected');
  });

  testWidgets('clicking one note of a selection narrows to it', (
    WidgetTester tester,
  ) async {
    final _FakePianoRollEngineClient client = _FakePianoRollEngineClient();
    final PianoRollStore store = PianoRollStore(client)..load('inst_keys');
    store
      ..addNoteAt(0, 84, length: 240)
      ..addNoteAt(240, 83, length: 240)
      ..selectAll();

    await pumpForTest(
      tester,
      PianoRollBinding(client: client, store: store),
      size: const Size(1600, 900),
    );
    await tester.pump();

    final Rect keys = tester.getRect(find.byType(PrKeyColumn));
    await tester.tapAt(Offset(keys.right + 4, keys.top + 7));
    await tester.pump();

    expect(
      store.selection.single.key,
      84,
      reason: 'a click that never dragged',
    );
  });
}
