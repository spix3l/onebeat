// RackBinding tests (UI-D-02).
//
// Verifies:
// 1. Step toggle round-trip.
// 2. Drag-paint gesture transaction (1 transaction begin, 1 commit for multiple steps).
// 3. Velocity adjustment.
// 4. Pattern switch re-scopes rows.
// 5. Playing step updates from snapshot.
// 6. Channel inspector updates on row selection.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/channel_rack/channel_inspector.dart';
import 'package:onebeat/src/features/channel_rack/channel_rack_screen.dart';
import 'package:onebeat/src/features/channel_rack/rack_binding.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';
import 'package:onebeat/src/features/channel_rack/rack_store.dart';

import '../../support/stage3_harness.dart';

class _FakeRackEngineClient implements EngineClient {
  _FakeRackEngineClient({
    this.isPlaying = false,
    this.positionBeats = 0.0,
  }) {
    patterns = <PatternSummary>[
      const PatternSummary(
        id: 'pat_1',
        name: 'Main Groove',
        color: '#EF6F91',
        lengthTicks: 3840,
        swing: 0.0,
        usageCount: 4,
        noteCount: 4,
        isCurrent: true,
      ),
      const PatternSummary(
        id: 'pat_2',
        name: 'Verse Drums',
        color: '#4FAFF5',
        lengthTicks: 3840,
        swing: 0.0,
        usageCount: 2,
        noteCount: 2,
        isCurrent: false,
      ),
    ];
    instruments = <ProjectInstrument>[
      const ProjectInstrument(
        id: 'kick',
        name: 'Kick 808',
        color: '#EF6F91',
        order: 0,
        pluginId: 'sampler',
        pluginName: 'Sampler',
        pluginVendor: 'OneBeat',
        pluginPath: '/plugins/sampler',
        muted: false,
        selected: true,
        affectedPatterns: 1,
        affectedClips: 1,
        affectedNotes: 4,
      ),
      const ProjectInstrument(
        id: 'snare',
        name: 'Snare',
        color: '#4FAFF5',
        order: 1,
        pluginId: 'sampler',
        pluginName: 'Sampler',
        pluginVendor: 'OneBeat',
        pluginPath: '/plugins/sampler',
        muted: false,
        selected: false,
        affectedPatterns: 1,
        affectedClips: 1,
        affectedNotes: 2,
      ),
    ];
    rows = <RackRow>[
      RackRow(
        instrumentId: 'kick',
        gridTicks: 240,
        hasSequence: true,
        offGridCount: 0,
        noteCount: 4,
        steps: List<RackStep>.generate(
          16,
          (int i) => RackStep(
            active: i % 4 == 0,
            velocity: i % 4 == 0 ? 12900 : 0,
          ),
        ),
      ),
      RackRow(
        instrumentId: 'snare',
        gridTicks: 240,
        hasSequence: true,
        offGridCount: 0,
        noteCount: 2,
        steps: List<RackStep>.generate(
          16,
          (int i) => RackStep(
            active: i == 4 || i == 12,
            velocity: i == 4 || i == 12 ? 12900 : 0,
          ),
        ),
      ),
    ];
  }

  bool isPlaying;
  double positionBeats;
  late List<PatternSummary> patterns;
  late List<ProjectInstrument> instruments;
  late List<RackRow> rows;

  RackPattern pattern = const RackPattern(
    id: 'pat_1',
    name: 'Main Groove',
    lengthTicks: 3840,
    baseGridTicks: 240,
    swing: 0.0,
  );

  int transactionBegins = 0;
  int transactionCommits = 0;
  int transactionAborts = 0;
  int undoCalls = 0;
  int redoCalls = 0;
  final List<int> auditionedNotes = <int>[];

  @override
  bool get canUndoProject => transactionCommits > undoCalls;

  @override
  bool get canRedoProject => redoCalls == 0 && undoCalls > 0;

  @override
  String get undoProjectName => 'Edit steps';

  @override
  String get redoProjectName => 'Edit steps';

  @override
  void beginRackGesture(String name) => transactionBegins++;

  @override
  void commitRackGesture() => transactionCommits++;

  @override
  void abortRackGesture() => transactionAborts++;

  @override
  RackPattern readRackPattern() => pattern;

  @override
  List<RackRow> readRackRows() => rows;

  @override
  List<PatternSummary> readPatterns() => patterns;

  @override
  List<ProjectInstrument> readInstruments() => instruments;

  @override
  void selectPattern(String patternId) {
    patterns = patterns
        .map((PatternSummary p) => PatternSummary(
              id: p.id,
              name: p.name,
              color: p.color,
              lengthTicks: p.lengthTicks,
              swing: p.swing,
              usageCount: p.usageCount,
              noteCount: p.noteCount,
              isCurrent: p.id == patternId,
            ))
        .toList();
    final PatternSummary selected =
        patterns.firstWhere((PatternSummary p) => p.id == patternId);
    pattern = RackPattern(
      id: selected.id,
      name: selected.name,
      lengthTicks: pattern.lengthTicks,
      baseGridTicks: pattern.baseGridTicks,
      swing: pattern.swing,
    );
  }

  @override
  void setRackLength(int steps) {
    pattern = RackPattern(
      id: pattern.id,
      name: pattern.name,
      lengthTicks: steps * pattern.baseGridTicks,
      baseGridTicks: pattern.baseGridTicks,
      swing: pattern.swing,
    );
  }

  @override
  void setRackRowGrid(String instrumentId, int gridTicks) {
    final int idx = rows.indexWhere((RackRow r) => r.instrumentId == instrumentId);
    if (idx >= 0) {
      final RackRow current = rows[idx];
      rows[idx] = RackRow(
        instrumentId: current.instrumentId,
        gridTicks: gridTicks,
        hasSequence: current.hasSequence,
        offGridCount: current.offGridCount,
        noteCount: current.noteCount,
        steps: current.steps,
      );
    }
  }

  @override
  void setRackStepVelocity(String instrumentId, int step, int velocity) {
    final int idx = rows.indexWhere((RackRow r) => r.instrumentId == instrumentId);
    if (idx >= 0) {
      final RackRow current = rows[idx];
      final List<RackStep> steps = List<RackStep>.of(current.steps);
      steps[step] = RackStep(active: true, velocity: velocity);
      rows[idx] = RackRow(
        instrumentId: current.instrumentId,
        gridTicks: current.gridTicks,
        hasSequence: true,
        offGridCount: current.offGridCount,
        noteCount: current.noteCount,
        steps: steps,
      );
    }
  }

  @override
  void setRackSwing(double swing) {
    pattern = RackPattern(
      id: pattern.id,
      name: pattern.name,
      lengthTicks: pattern.lengthTicks,
      baseGridTicks: pattern.baseGridTicks,
      swing: swing,
    );
  }

  @override
  void toggleRackStep(String instrumentId, int step) {
    final int idx = rows.indexWhere((RackRow r) => r.instrumentId == instrumentId);
    if (idx >= 0) {
      final RackRow current = rows[idx];
      final List<RackStep> steps = List<RackStep>.of(current.steps);
      final bool nextActive = !steps[step].active;
      steps[step] = RackStep(
        active: nextActive,
        velocity: nextActive ? 12900 : 0,
      );
      rows[idx] = RackRow(
        instrumentId: current.instrumentId,
        gridTicks: current.gridTicks,
        hasSequence: steps.any((RackStep s) => s.active),
        offGridCount: current.offGridCount,
        noteCount: steps.where((RackStep s) => s.active).length,
        steps: steps,
      );
    }
  }

  @override
  void removeRackSequence(String instrumentId) {
    final int idx = rows.indexWhere((RackRow r) => r.instrumentId == instrumentId);
    if (idx >= 0) {
      final RackRow current = rows[idx];
      rows[idx] = RackRow(
        instrumentId: current.instrumentId,
        gridTicks: current.gridTicks,
        hasSequence: false,
        offGridCount: 0,
        noteCount: 0,
        steps: List<RackStep>.filled(
          current.steps.length,
          const RackStep(active: false, velocity: 0),
        ),
      );
    }
  }

  @override
  void undoProject() => undoCalls++;

  @override
  void redoProject() => redoCalls++;

  @override
  void auditionNoteOn(int key, double velocity) {
    auditionedNotes.add(key);
  }

  @override
  void auditionNoteOff(int key) {}

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
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('RackBinding renders rows, pattern tabs, toolbar and inspector', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // Check title and pattern tabs
    expect(find.text('CHANNEL RACK'), findsOneWidget);
    expect(find.text('Main Groove'), findsOneWidget);
    expect(find.text('Verse Drums'), findsOneWidget);

    // Check row instruments (Kick 808 is in row and selected in inspector)
    expect(find.text('Kick 808'), findsNWidgets(2));
    expect(find.text('Snare'), findsOneWidget);

    // Check inspector
    expect(find.byType(ObChannelInspector), findsOneWidget);
    expect(find.byType(MiniKeyboard), findsOneWidget);
  });

  testWidgets('step toggle updates store and reflects on UI', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();
    final RackStore store = RackStore(client)..load();

    await pumpForTest(
      tester,
      RackBinding(client: client, store: store),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // Step 1 of Kick 808 is initially inactive (index 1)
    expect(client.rows.first.steps[1].active, isFalse);

    // Tap step 1 of Kick 808
    final Finder grids = find.byType(ObStepGrid);
    expect(grids, findsNWidgets(2));

    final Rect kickGrid = tester.getRect(grids.first);
    const double stepCellPitch = 34.0;
    await tester.tapAt(
      Offset(kickGrid.left + stepCellPitch * 1.5, kickGrid.center.dy),
    );
    await tester.pump();

    expect(client.rows.first.steps[1].active, isTrue);
  });

  testWidgets('drag paint performs single transaction begin and commit', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();
    final RackStore store = RackStore(client)..load();

    store.beginPaint('kick', 1, active: true);
    store.paintStep('kick', 2);
    store.paintStep('kick', 3);
    store.commitPaint();

    expect(client.transactionBegins, 1);
    expect(client.transactionCommits, 1);
    expect(client.rows.first.steps[1].active, isTrue);
    expect(client.rows.first.steps[2].active, isTrue);
    expect(client.rows.first.steps[3].active, isTrue);
  });

  testWidgets('velocity setting updates step velocity', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();
    final RackStore store = RackStore(client)..load();

    store.setVelocity('kick', 0, 8192);
    expect(client.rows.first.steps[0].velocity, 8192);

    store.nudgeVelocity(1024);
    expect(client.rows.first.steps[0].velocity, 9216);
  });

  testWidgets('switching pattern tabs re-scopes pattern and rows', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    expect(client.pattern.name, 'Main Groove');

    // Tap 'Verse Drums' tab
    await tester.tap(find.text('Verse Drums'));
    await tester.pump();

    expect(client.pattern.name, 'Verse Drums');
  });

  testWidgets('playing step calculates cursor position when transport is playing', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient(
      isPlaying: true,
      positionBeats: 1.5, // Beat 1.5 in 4-beat bar = step index 6
    );

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    final ChannelRackScreen screen =
        tester.widget(find.byType(ChannelRackScreen));
    expect(screen.vm.playingStep, 6);
  });

  testWidgets('mini keyboard in inspector triggers audition', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    final Rect keysRect = tester.getRect(find.byType(MiniKeyboard));
    final double whiteKeyWidth = keysRect.width / 14;

    // Tap first white key (Middle C, 60)
    await tester.tapAt(
      Offset(keysRect.left + whiteKeyWidth * 0.5, keysRect.center.dy),
    );
    await tester.pump();

    expect(client.auditionedNotes, contains(60));
  });
}
