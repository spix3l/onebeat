// The rack clipboard moves note data between patterns: cut in one pattern,
// select another, paste. The fake below is pattern-aware for exactly that
// reason — a clipboard test against a single-pattern fake would pass without
// ever proving the thing the feature exists for.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/channel_rack/rack_store.dart';

class _PatternedEngineClient implements EngineClient {
  _PatternedEngineClient();

  String current = 'p1';

  final Map<String, Map<String, List<SequenceNote>>> notes = <String, Map<String, List<SequenceNote>>>{
    'p1': <String, List<SequenceNote>>{
      'lead': <SequenceNote>[
        const SequenceNote(startTicks: 0, lengthTicks: 240, key: 60, velocity: 12900),
        const SequenceNote(startTicks: 480, lengthTicks: 240, key: 64, velocity: 9000),
      ],
    },
    'p2': <String, List<SequenceNote>>{},
  };

  int gestureBegins = 0;
  int gestureCommits = 0;

  List<ProjectInstrument> instruments = <ProjectInstrument>[
    const ProjectInstrument(
      id: 'lead',
      name: 'Lead',
      color: '#EF6F91',
      order: 0,
      pluginId: 'synth',
      pluginName: 'Synth',
      pluginVendor: 'OneBeat',
      pluginPath: '/plugins/synth',
      muted: false,
      selected: true,
      affectedPatterns: 1,
      affectedClips: 1,
      affectedNotes: 2,
    ),
    const ProjectInstrument(
      id: 'kick',
      name: 'Kick',
      color: '#8FD3C1',
      order: 1,
      pluginId: 'sampler',
      pluginName: 'Sampler',
      pluginVendor: 'OneBeat',
      pluginPath: '/plugins/sampler',
      muted: false,
      selected: false,
      affectedPatterns: 1,
      affectedClips: 1,
      affectedNotes: 0,
    ),
  ];

  Map<String, List<SequenceNote>> get _currentNotes => notes.putIfAbsent(current, () => <String, List<SequenceNote>>{});

  @override
  List<SequenceNote> readNotes(String instrumentId) =>
      List<SequenceNote>.of(_currentNotes[instrumentId] ?? const <SequenceNote>[]);

  @override
  void addNote(String instrumentId, int startTicks, int lengthTicks, int key, {int velocity = 0}) {
    _currentNotes
        .putIfAbsent(instrumentId, () => <SequenceNote>[])
        .add(SequenceNote(startTicks: startTicks, lengthTicks: lengthTicks, key: key, velocity: velocity));
  }

  @override
  void removeNotes(String instrumentId, List<SequenceNote> selection) {
    _currentNotes[instrumentId]?.removeWhere(selection.contains);
  }

  @override
  void selectPattern(String patternId) => current = patternId;

  @override
  void beginRackGesture(String name) => gestureBegins++;

  @override
  void commitRackGesture() => gestureCommits++;

  @override
  void abortRackGesture() {}

  @override
  RackPattern readRackPattern() =>
      RackPattern(id: current, name: current, lengthTicks: 3840, baseGridTicks: 240, swing: 0);

  @override
  List<RackRow> readRackRows() => <RackRow>[
    for (final ProjectInstrument instrument in instruments)
      RackRow(
        instrumentId: instrument.id,
        gridTicks: 240,
        hasSequence: (_currentNotes[instrument.id] ?? const <SequenceNote>[]).isNotEmpty,
        offGridCount: 0,
        noteCount: (_currentNotes[instrument.id] ?? const <SequenceNote>[]).length,
        steps: List<RackStep>.filled(16, const RackStep(active: false, velocity: 0)),
      ),
  ];

  @override
  List<PatternSummary> readPatterns() => <PatternSummary>[
    for (final String id in notes.keys)
      PatternSummary(
        id: id,
        name: id,
        color: '#EF6F91',
        lengthTicks: 3840,
        swing: 0,
        usageCount: 1,
        noteCount: (notes[id] ?? const <String, List<SequenceNote>>{}).values.fold(
          0,
          (int total, List<SequenceNote> value) => total + value.length,
        ),
        isCurrent: id == current,
      ),
  ];

  @override
  List<ProjectInstrument> readInstruments() => instruments;

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(RackStore.clearClipboard);
  tearDown(RackStore.clearClipboard);

  test('cut and paste move a channel\'s notes into another pattern', () {
    final _PatternedEngineClient client = _PatternedEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.selectInstrument('lead');
    expect(store.cutNotes(), isTrue);

    // Gone from the pattern it was written in, and still on the clipboard.
    expect(client.notes['p1']!['lead'], isEmpty);
    expect(store.canPaste, isTrue);

    store.selectPattern('p2');
    expect(store.pasteNotes(), isTrue);

    expect(client.notes['p2']!['lead'], hasLength(2));
    expect(client.notes['p2']!['lead']!.first.key, 60);
    expect(client.notes['p2']!['lead']!.first.velocity, 12900, reason: 'velocity survives the move');
    expect(client.notes['p1']!['lead'], isEmpty, reason: 'a move leaves the source pattern empty');
  });

  test('cut and paste are one undo entry each', () {
    final _PatternedEngineClient client = _PatternedEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.selectInstrument('lead');
    store.cutNotes();
    store.selectPattern('p2');
    store.pasteNotes();

    expect(client.gestureBegins, 2);
    expect(client.gestureCommits, 2);
  });

  test('copy leaves the source pattern alone and pastes as a duplicate', () {
    final _PatternedEngineClient client = _PatternedEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.selectInstrument('lead');
    expect(store.copyNotes(), isTrue);
    expect(client.notes['p1']!['lead'], hasLength(2));

    store.selectPattern('p2');
    store.pasteNotes();
    expect(client.notes['p1']!['lead'], hasLength(2));
    expect(client.notes['p2']!['lead'], hasLength(2));
  });

  test('paste can be aimed at another channel', () {
    final _PatternedEngineClient client = _PatternedEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.selectInstrument('lead');
    store.copyNotes();
    store.pasteNotes('kick');

    expect(client.notes['p1']!['kick'], hasLength(2));
    expect(store.selectedInstrumentId, 'kick');
  });

  test('an empty channel has nothing to copy, and an empty clipboard nothing to paste', () {
    final _PatternedEngineClient client = _PatternedEngineClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    expect(store.pasteNotes(), isFalse);
    store.selectInstrument('kick');
    expect(store.copyNotes(), isFalse);
    expect(store.cutNotes(), isFalse);
    expect(store.canPaste, isFalse);
  });

  test('the clipboard outlives the store, so a cut survives leaving the rack', () {
    final _PatternedEngineClient client = _PatternedEngineClient();
    final RackStore first = RackStore(client)..load();
    first.selectInstrument('lead');
    first.cutNotes();
    first.dispose();

    // The user switched to the playlist and back: a new store, same session.
    final RackStore second = RackStore(client)..load();
    addTearDown(second.dispose);
    second.selectPattern('p2');

    expect(second.canPaste, isTrue);
    expect(second.pasteNotes(), isTrue);
    expect(client.notes['p2']!['lead'], hasLength(2));
  });
}
