// RackBinding tests (UI-D-02).
//
// Verifies:
// 1. Step toggle round-trip.
// 2. Drag-paint gesture transaction (1 transaction begin, 1 commit for multiple steps).
// 3. Velocity adjustment.
// 4. Pattern switch re-scopes rows.
// 5. Playing step updates from snapshot.
// 6. Channel inspector updates on row selection.
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/channel_rack/channel_inspector.dart';
import 'package:onebeat/src/features/channel_rack/channel_rack_screen.dart';
import 'package:onebeat/src/features/channel_rack/rack_binding.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';
import 'package:onebeat/src/features/channel_rack/rack_store.dart';
import 'package:onebeat/src/ui_kit/popover_menu.dart';

import '../../support/app_harness.dart';

class _FakeRackEngineClient implements EngineClient {
  _FakeRackEngineClient({
    this.isPlaying = false,
    this.positionBeats = 0.0,
    this.loopStartBeats = 0,
    this.loopEndBeats = 4,
    this.withPluginRow = false,
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
        pluginId: 'onebeat.sample',
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
        pluginId: 'onebeat.sample',
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
    if (withPluginRow) {
      instruments = <ProjectInstrument>[
        ...instruments,
        const ProjectInstrument(
          id: 'reese',
          name: 'Reese',
          color: '#9FC65C',
          order: 2,
          pluginId: 'dev.onebeat.reese',
          pluginName: 'Reese CLAP',
          pluginVendor: 'OneBeat',
          pluginPath: '/plugins/reese.clap',
          muted: false,
          selected: false,
          affectedPatterns: 0,
          affectedClips: 0,
          affectedNotes: 0,
        ),
      ];
      rows = <RackRow>[
        ...rows,
        RackRow(
          instrumentId: 'reese',
          gridTicks: 240,
          hasSequence: false,
          offGridCount: 0,
          noteCount: 0,
          steps: List<RackStep>.filled(
            16,
            const RackStep(active: false, velocity: 0),
          ),
        ),
      ];
    }
  }

  bool isPlaying;
  double positionBeats;
  double loopStartBeats;
  double loopEndBeats;

  /// Adds a third lane that hosts a plug-in (as opposed to the two sample
  /// lanes), so the double-click-to-open-plug-in behaviour has a row to act
  /// on.
  final bool withPluginRow;

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
  void addEmptyInstrument(String name) {
    final String id = 'empty-${instruments.length}';
    instruments.add(
      ProjectInstrument(
        id: id,
        name: name,
        color: '#9FC65C',
        order: instruments.length,
        pluginId: '',
        pluginName: '',
        pluginVendor: '',
        pluginPath: '',
        muted: false,
        selected: false,
        affectedPatterns: 0,
        affectedClips: 0,
        affectedNotes: 0,
      ),
    );
    rows.add(
      RackRow(
        instrumentId: id,
        gridTicks: 240,
        hasSequence: false,
        offGridCount: 0,
        noteCount: 0,
        steps: List<RackStep>.filled(
          16,
          const RackStep(active: false, velocity: 0),
        ),
      ),
    );
  }

  int duplicateCalls = 0;
  int deleteCalls = 0;

  /// Every rename the binding asked for, as (instrumentId, name).
  final List<(String, String)> renames = <(String, String)>[];

  /// Every reorder the binding asked for, as (instrumentId, newOrder).
  final List<(String, int)> reorders = <(String, int)>[];

  @override
  void reorderInstrument(String id, int order) => reorders.add((id, order));

  @override
  void setInstrumentMuted(String id, {required bool muted}) {
    instruments = instruments
        .map(
          (ProjectInstrument inst) => inst.id == id
              ? ProjectInstrument(
                  id: inst.id,
                  name: inst.name,
                  color: inst.color,
                  order: inst.order,
                  pluginId: inst.pluginId,
                  pluginName: inst.pluginName,
                  pluginVendor: inst.pluginVendor,
                  pluginPath: inst.pluginPath,
                  muted: muted,
                  selected: inst.selected,
                  affectedPatterns: inst.affectedPatterns,
                  affectedClips: inst.affectedClips,
                  affectedNotes: inst.affectedNotes,
                )
              : inst,
        )
        .toList();
  }

  @override
  void duplicateInstrument(String id) => duplicateCalls++;

  @override
  void deleteInstrument(String id) => deleteCalls++;

  @override
  void renameInstrument(String id, String name) {
    renames.add((id, name));
    instruments = instruments
        .map(
          (ProjectInstrument inst) => inst.id == id
              ? ProjectInstrument(
                  id: inst.id,
                  name: name,
                  color: inst.color,
                  order: inst.order,
                  pluginId: inst.pluginId,
                  pluginName: inst.pluginName,
                  pluginVendor: inst.pluginVendor,
                  pluginPath: inst.pluginPath,
                  muted: inst.muted,
                  selected: inst.selected,
                  affectedPatterns: inst.affectedPatterns,
                  affectedClips: inst.affectedClips,
                  affectedNotes: inst.affectedNotes,
                )
              : inst,
        )
        .toList();
  }

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
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('RackBinding keeps the inspector closed until a lane is selected', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // The rack can show lanes without implying that one is selected.
    expect(find.text('CHANNEL RACK'), findsOneWidget);
    expect(find.text('Main Groove'), findsOneWidget);
    expect(find.text('Verse Drums'), findsOneWidget);
    expect(find.text('Kick 808'), findsOneWidget);
    expect(find.text('Snare'), findsOneWidget);
    expect(find.byType(ObChannelInspector), findsNothing);

    await tester.tap(find.text('Kick 808'));
    await tester.pump();

    expect(find.text('Kick 808'), findsNWidgets(2));
    expect(find.byType(ObChannelInspector), findsOneWidget);
    expect(find.byType(MiniKeyboard), findsOneWidget);
  });

  testWidgets('Add channel creates a visible empty lane without opening the inspector', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    await tester.tap(find.text('+ Add channel'));
    await tester.pump();

    expect(find.text('Channel 3'), findsOneWidget);
    expect(find.byType(ObChannelInspector), findsNothing);
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

  testWidgets('click-drag paints every crossed step cell', (
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

    final Rect grid = tester.getRect(find.byType(ObStepGrid).first);
    const double cell = 30;
    const double gap = 4;
    const double groupGap = 8;
    final Offset start = Offset(grid.left + cell * 1.5 + gap, grid.center.dy);
    final Offset end = Offset(
      grid.left + cell * 4 + gap * 3 + groupGap + cell / 2,
      grid.center.dy,
    );

    final TestGesture gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await gesture.up();
    await tester.pump();

    // Kick starts with 1/5/9/13. Painting from step 2 to step 5 fills the
    // skipped cells 3 and 4 as well, without toggling the existing step 5 off.
    expect(client.rows.first.steps[1].active, isTrue);
    expect(client.rows.first.steps[2].active, isTrue);
    expect(client.rows.first.steps[3].active, isTrue);
    expect(client.rows.first.steps[4].active, isTrue);
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

  testWidgets('playhead loops on the loop region, not the stored length', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient(
      isPlaying: true,
      positionBeats: 3.5, // past the end of a [1, 3) loop region
      loopStartBeats: 1,
      loopEndBeats: 3,
    );

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    final ChannelRackScreen screen =
        tester.widget(find.byType(ChannelRackScreen));
    // 3.5 beats minus a 1-beat loop start wraps (2-beat region) to 0.5 beat,
    // which is step 2 of the 1/16 grid.
    expect(screen.vm.playingStep, 2);
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

    await tester.tap(find.text('Kick 808'));
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

  testWidgets('the row power button toggles the instrument mute', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // The power button is the first control in each row: the left edge plus the
    // md inset and half the power-well width. Tap the one on the first row.
    final Rect kickRow = tester.getRect(find.byType(ObRackRow).first);
    await tester.tapAt(Offset(kickRow.left + 12 + 9, kickRow.center.dy));
    await tester.pump();

    expect(client.instruments.first.muted, isTrue);
  });

  testWidgets('dragging a lane by its name reorders the channel', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // The name block is the drag handle. Grab the first lane's name and drag it
    // down past the second lane.
    final Rect firstRow = tester.getRect(find.byType(ObRackRow).first);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Kick 808')),
    );
    // The handle uses an immediate drag recognizer, so one pump to let it
    // claim the pointer, then a move past the touch slop.
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(Offset(0, firstRow.height * 1.2));
    await tester.pump();
    await gesture.up();
    // Plain pumps, not pumpAndSettle: the binding drives a continuous
    // playhead ticker, so the tree never goes quiet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The kick was first; it is now second.
    expect(client.reorders, <(String, int)>[('kick', 1)]);
  });

  testWidgets('dragging across the step cells paints instead of reordering', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // A vertical drag starting on a step cell must not move the lane: the grid
    // is a paint surface, and only the name block is a handle.
    final Rect cell = tester.getRect(find.byType(ObStepGrid).first);
    final TestGesture gesture = await tester.startGesture(cell.center);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(client.reorders, isEmpty);
  });

  testWidgets('double-clicking a plug-in lane opens its plug-in window', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client =
        _FakeRackEngineClient(withPluginRow: true);
    final List<String> opened = <String>[];

    await pumpForTest(
      tester,
      RackBinding(client: client, onOpenPlugin: opened.add),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // Two taps inside the double-tap window: the lane's instrument is handed
    // to the shell, which is what opens the plug-in window.
    await tester.tap(find.text('Reese'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Reese'));
    await tester.pump();

    expect(opened, <String>['reese']);

    // The double-click selects the lane too, like a click would.
    expect(find.byType(ObChannelInspector), findsOneWidget);

    // A later single click must not re-open the window, even once its tap has
    // fired after the double-tap window closes.
    await tester.tap(find.text('Reese').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, <String>['reese']);
  });

  Future<void> rightClickRow(WidgetTester tester, String name) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text(name)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();
  }

  testWidgets('right-clicking a lane offers the channel actions', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    await rightClickRow(tester, 'Kick 808');

    // A sample lane has no window to open, so that row is absent.
    expect(find.text('Open in piano roll'), findsOneWidget);
    expect(find.text('Open plugin window'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('STEP ACTIONS'), findsOneWidget);
    expect(find.text('Add note every 2 steps'), findsOneWidget);
    expect(find.text('Add note every 4 steps'), findsOneWidget);
    expect(find.text('Add note every 8 steps'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Duplicate'));
    await tester.pump();
    expect(client.duplicateCalls, 1);

    // Re-open for delete.
    await rightClickRow(tester, 'Kick 808');
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(client.deleteCalls, 1);
  });

  testWidgets('a step fill from the context menu fills the channel grid', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // Kick starts with steps 0/4/8/12 lit.
    expect(client.rows.first.steps[2].active, isFalse);

    await rightClickRow(tester, 'Kick 808');
    await tester.tap(find.text('Add note every 2 steps'));
    await tester.pump();

    // Every second step is now lit, including the ones that were empty.
    expect(client.rows.first.steps[2].active, isTrue);
    expect(client.rows.first.steps[1].active, isFalse);
    expect(client.rows.first.steps[4].active, isTrue);
  });

  testWidgets('right-clicking a plug-in lane offers Open plugin window', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client =
        _FakeRackEngineClient(withPluginRow: true);
    final List<String> opened = <String>[];

    await pumpForTest(
      tester,
      RackBinding(client: client, onOpenPlugin: opened.add),
      size: const Size(1520, 880),
    );
    await tester.pump();

    await rightClickRow(tester, 'Reese');

    expect(find.text('Open plugin window'), findsOneWidget);
    await tester.tap(find.text('Open plugin window'));
    await tester.pump();

    expect(opened, <String>['reese']);
  });

  testWidgets('the inspector opens the plug-in window for a plug-in lane', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client =
        _FakeRackEngineClient(withPluginRow: true);
    final List<String> opened = <String>[];

    await pumpForTest(
      tester,
      RackBinding(client: client, onOpenPlugin: opened.add),
      size: const Size(1520, 880),
    );
    await tester.pump();

    // A sample lane's inspector has no window to open.
    await tester.tap(find.text('Kick 808'));
    await tester.pump();
    expect(find.text('Open plugin'), findsNothing);

    // Selecting the plug-in lane brings the action up. A plug-in lane's
    // double-tap recognizer holds its single tap for the double-tap window,
    // so the selection lands only after that window closes.
    final Finder reeseFinder = find.text('Reese');
    await tester.tap(reeseFinder);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open plugin'), findsOneWidget);
    await tester.tap(find.text('Open plugin'));
    await tester.pump();
    expect(opened, <String>['reese']);
  });

  testWidgets('Rename from the context menu renames the channel', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    await rightClickRow(tester, 'Kick 808');
    await tester.tap(find.text('Rename'));
    await tester.pump();

    // The dialog opens pre-filled with the channel's current name.
    expect(find.text('Rename channel'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Kick Heavy');
    await tester.tap(find.text('Rename'));
    await tester.pump();

    expect(client.renames, <(String, String)>[('kick', 'Kick Heavy')]);
    expect(find.text('Kick Heavy'), findsOneWidget);
  });

  testWidgets('Solo from the context menu toggles the channel solo state', (
    WidgetTester tester,
  ) async {
    final _FakeRackEngineClient client = _FakeRackEngineClient();

    await pumpForTest(
      tester,
      RackBinding(client: client),
      size: const Size(1520, 880),
    );
    await tester.pump();

    await rightClickRow(tester, 'Kick 808');
    await tester.tap(find.text('Solo'));
    await tester.pump();

    // Re-open: the row is now ticked.
    await rightClickRow(tester, 'Kick 808');
    final ObPopoverMenu menu =
        tester.widget<ObPopoverMenu>(find.byType(ObPopoverMenu));
    final ObMenuRowVm soloRow = menu.vm.rows.firstWhere(
      (ObMenuRowVm row) => row.label == 'Solo',
    );
    expect(soloRow.checked, isTrue);

    // Toggling again clears the tick.
    await tester.tap(find.text('Solo'));
    await tester.pump();
    await rightClickRow(tester, 'Kick 808');
    final ObPopoverMenu reopened =
        tester.widget<ObPopoverMenu>(find.byType(ObPopoverMenu));
    final ObMenuRowVm cleared = reopened.vm.rows.firstWhere(
      (ObMenuRowVm row) => row.label == 'Solo',
    );
    expect(cleared.checked, isFalse);
  });
}
