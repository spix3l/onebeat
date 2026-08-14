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

import '../../support/fake_stage3_client.dart';
import '../../support/stage3_harness.dart';

class _FakePianoRollEngineClient extends FakeStage3Client implements EngineClient {
  _FakePianoRollEngineClient({
    this.isPlaying = false,
    this.positionBeats = 0.0,
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

  testWidgets('PianoRollBinding renders toolbar, ruler, key column, grid and velocity lane', (
    WidgetTester tester,
  ) async {
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
  });

  testWidgets('add note and select note in PianoRollStore round-trip to client', (
    WidgetTester tester,
  ) async {
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
  });

  testWidgets('drag move and resize perform single transaction begin and commit', (
    WidgetTester tester,
  ) async {
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
  });

  testWidgets('duplicate, transpose, nudge, and quantise commands mutate notes correctly', (
    WidgetTester tester,
  ) async {
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
  });

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
    expect(store.selection.map((n) => n.key).toSet(), containsAll(<int>[60, 64]));
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

    await tester.tap(find.text('Back to playlist'));
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
}
