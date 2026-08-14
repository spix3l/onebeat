import 'package:onebeat/src/engine/engine_client.dart';

class FakeRackClient implements EngineClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

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

  int transactionBegins = 0;
  int transactionCommits = 0;
  int transactionAborts = 0;
  int undoCalls = 0;
  int redoCalls = 0;

  @override
  bool get canRedoProject => redoCalls == 0;

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
  List<PatternSummary> readPatterns() => const <PatternSummary>[];

  @override
  List<ProjectInstrument> readInstruments() => const <ProjectInstrument>[
        ProjectInstrument(
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
          affectedClips: 0,
          affectedNotes: 0,
        ),
      ];

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
}
