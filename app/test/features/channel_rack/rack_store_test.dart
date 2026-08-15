import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/channel_rack/rack_store.dart';

class _FakeStoreEngineClient implements EngineClient {
  RackPattern pattern = const RackPattern(
    id: 'pattern',
    name: 'Pattern 1',
    lengthTicks: 3840,
    baseGridTicks: 240,
    swing: 0,
  );

  List<RackRow> rows = <RackRow>[
    RackRow(
      instrumentId: 'kick',
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

  List<PatternSummary> patterns = <PatternSummary>[
    const PatternSummary(
      id: 'pattern',
      name: 'Pattern 1',
      color: '#EF6F91',
      lengthTicks: 3840,
      swing: 0,
      usageCount: 1,
      noteCount: 0,
      isCurrent: true,
    ),
  ];

  List<ProjectInstrument> instruments = <ProjectInstrument>[
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
      affectedNotes: 0,
    ),
  ];

  int transactionBegins = 0;
  int transactionCommits = 0;
  int transactionAborts = 0;
  int undoCalls = 0;
  int redoCalls = 0;

  @override
  bool get canRedoProject => redoCalls == 0 && undoCalls > 0;

  @override
  bool get canUndoProject => transactionCommits > undoCalls;

  @override
  String get redoProjectName => canRedoProject ? 'Paint steps' : '';

  @override
  String get undoProjectName => canUndoProject ? 'Paint steps' : '';

  @override
  void abortRackGesture() => transactionAborts++;

  @override
  void beginRackGesture(String name) => transactionBegins++;

  @override
  void commitRackGesture() => transactionCommits++;

  @override
  RackPattern readRackPattern() => pattern;

  @override
  List<RackRow> readRackRows() => rows;

  @override
  List<PatternSummary> readPatterns() => patterns;

  @override
  List<ProjectInstrument> readInstruments() => instruments;

  @override
  void selectPattern(String patternId) {}

  @override
  void redoProject() => redoCalls++;

  @override
  void removeRackSequence(String instrumentId) {
    final RackRow row = rows.single;
    rows = <RackRow>[
      RackRow(
        instrumentId: row.instrumentId,
        gridTicks: row.gridTicks,
        hasSequence: false,
        offGridCount: 0,
        noteCount: 0,
        steps: List<RackStep>.filled(
          row.steps.length,
          const RackStep(active: false, velocity: 0),
        ),
      ),
    ];
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
  void setRackRowGrid(String instrumentId, int gridTicks) {}

  @override
  void setRackStepVelocity(String instrumentId, int step, int velocity) {
    _replaceStep(step, RackStep(active: true, velocity: velocity));
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
    final RackStep current = rows.single.steps[step];
    _replaceStep(
      step,
      RackStep(active: !current.active, velocity: current.active ? 0 : 12900),
    );
  }

  @override
  void undoProject() => undoCalls++;

  void _replaceStep(int step, RackStep replacement) {
    final RackRow row = rows.single;
    final List<RackStep> steps = List<RackStep>.of(row.steps)
      ..[step] = replacement;
    final int active = steps.where((RackStep value) => value.active).length;
    rows = <RackRow>[
      RackRow(
        instrumentId: row.instrumentId,
        gridTicks: row.gridTicks,
        hasSequence: active > 0,
        offGridCount: row.offGridCount,
        noteCount: active,
        steps: steps,
      ),
    ];
  }

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'refresh leaves the inspector selection empty until a lane is chosen',
    () {
      final _FakeStoreEngineClient client = _FakeStoreEngineClient();
      final RackStore store = RackStore(client)..load();
      addTearDown(store.dispose);

      expect(store.selectedInstrumentId, isNull);

      store.selectInstrument('kick');
      expect(store.selectedInstrumentId, 'kick');
    },
  );

  test('paint drag is one transaction and paints each crossed step once', () {
    final _FakeStoreEngineClient client = _FakeStoreEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.beginPaint('kick', 0, active: true);
    // One move can skip over several cells; the store fills the interval.
    store.paintStep('kick', 4);
    store.paintStep('kick', 4);
    store.paintStep('kick', 2);
    store.commitPaint();

    expect(client.transactionBegins, 1);
    expect(client.transactionCommits, 1);
    expect(
      store.rows.single.steps.take(5).every((RackStep step) => step.active),
      isTrue,
    );
    expect(store.canUndo, isTrue);
  });

  test('velocity and pattern controls stay on the same engine seam', () {
    final _FakeStoreEngineClient client = _FakeStoreEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.setVelocity('kick', 4, 8192);
    store.setSwing(0.55);
    store.setLength(32);

    expect(store.rows.single.steps[4].velocity, 8192);
    expect(store.pattern!.swing, 0.55);
    expect(store.pattern!.baseStepCount, 32);
  });

  test('adds notes at an interval without removing existing notes', () {
    final _FakeStoreEngineClient client = _FakeStoreEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.toggleStep('kick', 3);
    store.addNotesEvery('kick', 4);

    expect(
      store.rows.single.steps
          .asMap()
          .entries
          .where((MapEntry<int, RackStep> entry) => entry.value.active)
          .map((MapEntry<int, RackStep> entry) => entry.key),
      containsAll(<int>[0, 3, 4, 8, 12]),
    );
  });

  test('remove sequence clears the notes but keeps the channel', () {
    final _FakeStoreEngineClient client = _FakeStoreEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.toggleStep('kick', 0);
    expect(store.rows.single.hasSequence, isTrue);

    store.removeSequence('kick');
    expect(store.rows.single.hasSequence, isFalse);
    // Clearing a channel's steps is not deleting the channel: it stays a row.
    expect(store.rows, hasLength(1));
  });

  test(
    'refreshIfInstrumentsChanged picks up an externally added instrument',
    () {
      final _FakeStoreEngineClient client = _FakeStoreEngineClient();
      client.instruments = <ProjectInstrument>[];
      client.rows = <RackRow>[];
      final RackStore store = RackStore(client)..load();
      addTearDown(store.dispose);

      expect(store.instruments, isEmpty);

      // The shell seeds the default channel outside the store.
      client.instruments = <ProjectInstrument>[
        const ProjectInstrument(
          id: 'piano',
          name: 'OneBeat Piano',
          color: '#6C8CFF',
          order: 0,
          pluginId: 'com.onebeat.piano',
          pluginName: 'OneBeat Piano',
          pluginVendor: 'OneBeat',
          pluginPath: '@bundled/OneBeatPiano.clap',
          muted: false,
          selected: true,
          affectedPatterns: 0,
          affectedClips: 0,
          affectedNotes: 0,
        ),
      ];
      client.rows = <RackRow>[
        RackRow(
          instrumentId: 'piano',
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

      store.refreshIfInstrumentsChanged();
      expect(store.instruments, hasLength(1));
      expect(store.rows, hasLength(1));
    },
  );

  test('an empty channel is a row, so it survives a rebuild of the store', () {
    final _FakeStoreEngineClient client = _FakeStoreEngineClient();
    // A channel with no notes anywhere: what "+ Add channel" produces, and what
    // used to vanish on the way to the playlist and back.
    client.instruments = <ProjectInstrument>[
      const ProjectInstrument(
        id: 'empty',
        name: 'Channel 1',
        color: '#6C8CFF',
        order: 0,
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
    ];
    client.rows = <RackRow>[
      RackRow(
        instrumentId: 'empty',
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

    // Two independent stores over the same engine: the second stands in for the
    // rack being rebuilt after a trip to the playlist.
    final RackStore first = RackStore(client)..load();
    addTearDown(first.dispose);
    expect(first.rows, hasLength(1));

    final RackStore second = RackStore(client)..load();
    addTearDown(second.dispose);
    expect(second.rows, hasLength(1));
  });
}
