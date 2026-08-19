// A scripted stand-in for the engine seam.
//
// It holds a small in-memory model so the editors can be driven end to end in
// `flutter test` without the engine, an audio device or a plug-in. It is
// deliberately *not* a re-implementation of the real model: it keeps just
// enough state for the behaviours the widget and store tests assert — note
// values, pattern usage counts, lane and clip fields — and counts the gesture
// calls, which is how "a drag is one undo entry" is tested at this level.
import 'package:onebeat/src/engine/engine_client.dart';

class FakeEngineClient implements EngineClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  FakeEngineClient() {
    patterns['pat_a'] = MutablePattern(
      id: 'pat_a',
      name: 'Verse Drums',
      color: '#EF6F91',
      lengthTicks: 3840,
    );
    currentPatternId = 'pat_a';
    lanes['lane_a'] = MutableLane(id: 'lane_a', name: 'Patterns', order: 0);
  }

  final Map<String, MutablePattern> patterns = <String, MutablePattern>{};
  final Map<String, MutableLane> lanes = <String, MutableLane>{};
  final Map<String, MutableClip> clips = <String, MutableClip>{};
  String currentPatternId = '';

  int gestureBegins = 0;
  int gestureCommits = 0;
  int gestureAborts = 0;
  final List<int> auditionedKeys = <int>[];
  int nextId = 1;

  String _mint(String prefix) => '${prefix}_${nextId++}';

  MutablePattern get _current => patterns[currentPatternId]!;

  // ----- gestures -----------------------------------------------------------

  @override
  void beginGesture(String name) => gestureBegins++;

  @override
  void commitGesture() => gestureCommits++;

  @override
  void abortGesture() => gestureAborts++;

  // ----- notes --------------------------------------------------------------

  @override
  List<SequenceNote> readNotes(String instrumentId) {
    final List<SequenceNote> notes = List<SequenceNote>.of(
      _current.sequences[instrumentId] ?? const <SequenceNote>[],
    );
    // The real sequence is kept sorted at all times, and the editors rely on
    // that ordering, so the fake has to honour it too.
    notes.sort((SequenceNote a, SequenceNote b) {
      if (a.startTicks != b.startTicks) {
        return a.startTicks.compareTo(b.startTicks);
      }
      return a.key.compareTo(b.key);
    });
    return notes;
  }

  List<SequenceNote> _sequence(String instrumentId) =>
      _current.sequences.putIfAbsent(instrumentId, () => <SequenceNote>[]);

  @override
  void addNote(
    String instrumentId,
    int startTicks,
    int lengthTicks,
    int key, {
    int velocity = 0,
  }) {
    _sequence(instrumentId).add(
      SequenceNote(
        startTicks: startTicks,
        lengthTicks: lengthTicks,
        key: key,
        velocity: velocity <= 0 ? 12900 : velocity,
      ),
    );
  }

  @override
  void removeNotes(String instrumentId, List<SequenceNote> notes) {
    final List<SequenceNote> sequence = _sequence(instrumentId);
    for (final SequenceNote note in notes) {
      sequence.remove(note);
    }
  }

  /// Replaces each selected note with a transformed copy, which is how every
  /// move/resize/velocity edit works against a value-addressed sequence.
  void _transform(
    String instrumentId,
    List<SequenceNote> notes,
    SequenceNote Function(SequenceNote) transform,
  ) {
    final List<SequenceNote> sequence = _sequence(instrumentId);
    for (final SequenceNote note in notes) {
      final int index = sequence.indexOf(note);
      if (index < 0) continue;
      sequence[index] = transform(note);
    }
  }

  @override
  void moveNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    int deltaTicks = 0,
    int semitones = 0,
    int snapTicks = 0,
  }) => _transform(
    instrumentId,
    notes,
    (SequenceNote note) => note.copyWith(
      startTicks: (note.startTicks + deltaTicks).clamp(0, 1 << 30),
      key: (note.key + semitones).clamp(0, 127),
    ),
  );

  @override
  void resizeNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int lengthDelta,
    int snapTicks = 0,
  }) => _transform(
    instrumentId,
    notes,
    (SequenceNote note) => note.copyWith(
      lengthTicks: (note.lengthTicks + lengthDelta).clamp(1, 1 << 30),
    ),
  );

  @override
  void setNoteVelocity(
    String instrumentId,
    List<SequenceNote> notes,
    int velocity,
  ) => _transform(
    instrumentId,
    notes,
    (SequenceNote note) => note.copyWith(velocity: velocity),
  );

  @override
  void quantiseNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int gridTicks,
    required double strength,
  }) => _transform(instrumentId, notes, (SequenceNote note) {
    final int target = ((note.startTicks / gridTicks).round()) * gridTicks;
    final int moved = note.startTicks + ((target - note.startTicks) * strength).round();
    return note.copyWith(startTicks: moved);
  });

  @override
  void duplicateNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int deltaTicks,
  }) {
    final List<SequenceNote> sequence = _sequence(instrumentId);
    for (final SequenceNote note in notes) {
      sequence.add(note.copyWith(startTicks: note.startTicks + deltaTicks));
    }
  }

  @override
  void auditionNoteOn(int key, double velocity) => auditionedKeys.add(key);

  @override
  void auditionNoteOff(int key) {}

  // ----- patterns -----------------------------------------------------------

  int _usageOf(String patternId) => clips.values.where((MutableClip clip) => clip.patternId == patternId).length;

  @override
  List<PatternSummary> readPatterns() => patterns.values
      .map(
        (MutablePattern pattern) => PatternSummary(
          id: pattern.id,
          name: pattern.name,
          color: pattern.color,
          lengthTicks: pattern.lengthTicks,
          swing: pattern.swing,
          usageCount: _usageOf(pattern.id),
          noteCount: pattern.sequences.values.fold<int>(
            0,
            (int sum, List<SequenceNote> notes) => sum + notes.length,
          ),
          isCurrent: pattern.id == currentPatternId,
        ),
      )
      .toList();

  @override
  void selectPattern(String patternId) {
    if (patterns.containsKey(patternId)) currentPatternId = patternId;
  }

  @override
  void createPattern(String name) {
    final String id = _mint('pat');
    patterns[id] = MutablePattern(
      id: id,
      name: name,
      color: '#6C8CFF',
      lengthTicks: 3840,
    );
    currentPatternId = id;
  }

  @override
  void renamePattern(String patternId, String name) => patterns[patternId]?.name = name;

  @override
  void recolorPattern(String patternId, String color) => patterns[patternId]?.color = color;

  @override
  void duplicatePattern(String patternId) {
    final MutablePattern? source = patterns[patternId];
    if (source == null) return;
    final String id = _mint('pat');
    patterns[id] = source.cloneAs(id, '${source.name} 2');
    currentPatternId = id;
  }

  @override
  void removePattern(String patternId) {
    if (patterns.length <= 1) return;
    patterns.remove(patternId);
    clips.removeWhere((_, MutableClip clip) => clip.patternId == patternId);
    if (currentPatternId == patternId) {
      currentPatternId = patterns.keys.first;
    }
  }

  @override
  void setPatternTimeSignature(String patternId, int numerator, int denominator) {}

  @override
  void reorderPattern(String patternId, int order) {}

  @override
  void setPatternGroup(String patternId, String group) {}

  @override
  void makeClipsUnique(List<String> clipIds) {
    if (clipIds.isEmpty) return;
    final MutableClip? first = clips[clipIds.first];
    final MutablePattern? source = first == null ? null : patterns[first.patternId];
    if (source == null) return;
    final String id = _mint('pat');
    patterns[id] = source.cloneAs(id, '${source.name} 2');
    for (final String clipId in clipIds) {
      clips[clipId]?.patternId = id;
    }
    currentPatternId = id;
  }

  @override
  void splitClipByChannel(String clipId) {
    final MutableClip? clip = clips[clipId];
    final MutablePattern? source = clip == null ? null : patterns[clip.patternId];
    if (clip == null || source == null) return;
    final List<String> channels =
        source.sequences.entries
            .where((MapEntry<String, List<SequenceNote>> entry) => entry.value.isNotEmpty)
            .map((MapEntry<String, List<SequenceNote>> entry) => entry.key)
            .toList()
          ..sort();
    if (channels.length < 2) return;

    final MutableLane sourceLane = lanes[clip.laneId]!;
    for (final MutableLane lane in lanes.values) {
      if (lane.order > sourceLane.order) lane.order += channels.length - 1;
    }

    for (int index = 0; index < channels.length; index++) {
      final String channel = channels[index];
      final String patternId = _mint('pat');
      patterns[patternId] = MutablePattern(
        id: patternId,
        name: channel,
        color: source.color,
        lengthTicks: source.lengthTicks,
      )..sequences[channel] = List<SequenceNote>.of(source.sequences[channel]!);

      String laneId = clip.laneId;
      if (index > 0) {
        laneId = _mint('lane');
        lanes[laneId] = MutableLane(id: laneId, name: channel, order: sourceLane.order + index);
      }

      final String newClipId = _mint('clip');
      clips[newClipId] = MutableClip(
        id: newClipId,
        laneId: laneId,
        patternId: patternId,
        startTicks: clip.startTicks,
        lengthTicks: clip.lengthTicks,
      )
        ..transpose = clip.transpose
        ..windowStartTicks = clip.windowStartTicks
        ..muted = clip.muted
        ..loop = clip.loop;
    }
    clips.remove(clipId);
  }

  // ----- lanes --------------------------------------------------------------

  @override
  List<ArrangementLane> readLanes() {
    final List<MutableLane> ordered = lanes.values.toList()
      ..sort((MutableLane a, MutableLane b) => a.order.compareTo(b.order));
    return ordered
        .map(
          (MutableLane lane) => ArrangementLane(
            id: lane.id,
            name: lane.name,
            color: lane.color,
            order: lane.order,
            height: lane.height,
            clipCount: clips.values.where((MutableClip clip) => clip.laneId == lane.id).length,
            muted: lane.muted,
            soloed: lane.soloed,
            collapsed: lane.collapsed,
          ),
        )
        .toList();
  }

  @override
  void createLane(String name) {
    final String id = _mint('lane');
    lanes[id] = MutableLane(id: id, name: name, order: lanes.length);
  }

  @override
  void renameLane(String laneId, String name) => lanes[laneId]?.name = name;

  @override
  void recolorLane(String laneId, String color) => lanes[laneId]?.color = color;

  @override
  void reorderLane(String laneId, int order) => lanes[laneId]?.order = order;

  @override
  void setLaneHeight(String laneId, int height) => lanes[laneId]?.height = height;

  @override
  void setLaneMuted(String laneId, {required bool muted}) => lanes[laneId]?.muted = muted;

  @override
  void setLaneSoloed(String laneId, {required bool soloed}) => lanes[laneId]?.soloed = soloed;

  @override
  void setLaneCollapsed(String laneId, {required bool collapsed}) => lanes[laneId]?.collapsed = collapsed;

  @override
  void removeLane(String laneId) {
    lanes.remove(laneId);
    clips.removeWhere((_, MutableClip clip) => clip.laneId == laneId);
  }

  // ----- clips --------------------------------------------------------------

  @override
  List<ArrangementClip> readClips() {
    final List<MutableClip> ordered = clips.values.toList()
      ..sort((MutableClip a, MutableClip b) {
        final int laneA = lanes[a.laneId]?.order ?? 0;
        final int laneB = lanes[b.laneId]?.order ?? 0;
        if (laneA != laneB) return laneA.compareTo(laneB);
        return a.startTicks.compareTo(b.startTicks);
      });
    return ordered.map((MutableClip clip) {
      final MutablePattern? pattern = patterns[clip.patternId];
      return ArrangementClip(
        id: clip.id,
        laneId: clip.laneId,
        patternId: clip.patternId,
        name: clip.isAudio ? clip.audioPath.split('/').last : (pattern?.name ?? ''),
        color: pattern?.color ?? '#6C8CFF',
        startTicks: clip.startTicks,
        lengthTicks: clip.lengthTicks,
        windowStartTicks: clip.windowStartTicks,
        patternLengthTicks: pattern?.lengthTicks ?? 0,
        transpose: clip.transpose,
        noteCount:
            pattern?.sequences.values.fold<int>(
              0,
              (int sum, List<SequenceNote> notes) => sum + notes.length,
            ) ??
            0,
        usageCount: _usageOf(clip.patternId),
        muted: clip.muted,
        loop: clip.loop,
        isAudio: clip.isAudio,
        audioPath: clip.audioPath,
      );
    }).toList();
  }

  /// Seeds an audio clip. Not an override — the real client reads a WAV to
  /// derive the length, and a test wants to state it.
  String addAudioClip(String laneId, {required int startTicks, required int lengthTicks, String path = '/samples/loop.wav'}) {
    final String id = _mint('clip');
    clips[id] = MutableClip(
      id: id,
      laneId: laneId,
      patternId: '',
      startTicks: startTicks,
      lengthTicks: lengthTicks,
    )
      ..isAudio = true
      ..audioPath = path;
    return id;
  }

  @override
  void addClip(
    String laneId, {
    String patternId = '',
    required int startTicks,
    required int lengthTicks,
  }) {
    final String id = _mint('clip');
    clips[id] = MutableClip(
      id: id,
      laneId: laneId,
      patternId: patternId.isEmpty ? currentPatternId : patternId,
      startTicks: startTicks,
      lengthTicks: lengthTicks,
    );
  }

  @override
  void moveClip(String clipId, {String laneId = '', required int startTicks}) {
    final MutableClip? clip = clips[clipId];
    if (clip == null) return;
    clip.startTicks = startTicks;
    if (laneId.isNotEmpty) clip.laneId = laneId;
  }

  @override
  void resizeClip(String clipId, int lengthTicks) => clips[clipId]?.lengthTicks = lengthTicks;

  @override
  void duplicateClip(
    String clipId, {
    String laneId = '',
    required int startTicks,
  }) {
    final MutableClip? source = clips[clipId];
    if (source == null) return;
    final String id = _mint('clip');
    clips[id] = source.cloneAs(
      id,
      laneId.isEmpty ? source.laneId : laneId,
      startTicks,
    );
  }

  @override
  void removeClip(String clipId) => clips.remove(clipId);

  @override
  void setClipMuted(String clipId, {required bool muted}) => clips[clipId]?.muted = muted;

  @override
  void setClipLoop(String clipId, {required bool loop}) => clips[clipId]?.loop = loop;

  @override
  void setClipWindowStart(String clipId, int windowStartTicks) => clips[clipId]?.windowStartTicks = windowStartTicks;

  @override
  void setClipTranspose(String clipId, int semitones) => clips[clipId]?.transpose = semitones;

  // ----- mixer and inserts --------------------------------------------------
  // A real chain, not a stub: the binding reads back what it just wrote, so a
  // fake that swallowed the writes would make every rack test pass vacuously.

  List<MixerTrackInfo> mixerTracks = <MixerTrackInfo>[
    const MixerTrackInfo(
      id: 'mix_master',
      outputId: '',
      name: 'Master',
      gain: 1,
      pan: 0,
      effectCount: 0,
      muted: false,
      soloed: false,
      isMaster: true,
    ),
  ];

  /// Chains by track ID, in chain order.
  final Map<String, List<EffectInfo>> effects = <String, List<EffectInfo>>{};

  /// Parameter values by (track, slot, param). Sparse, like the model's.
  final Map<String, double> effectParams = <String, double>{};

  /// Every insert edit, in order, so a test can assert what the UI asked for
  /// rather than only what it ended up showing.
  final List<String> effectLog = <String>[];

  int _nextEffectId = 0;

  List<EffectDescriptor> builtinEffects = const <EffectDescriptor>[
    EffectDescriptor(id: 'dev.onebeat.fx.reverb', name: 'OneBeat Reverb', summary: 'Room and hall.'),
    EffectDescriptor(id: 'dev.onebeat.fx.delay', name: 'OneBeat Delay', summary: 'Feedback delay.'),
  ];

  /// Bumped by every edit below, so a view that memoises on it sees exactly
  /// what it would see against the real engine.
  int revision = 0;

  /// Records an edit and marks the model as moved. Every mutating call goes
  /// through one of these two, so the two can never disagree.
  void _logEffect(String entry) {
    revision++;
    effectLog.add(entry);
  }

  void _logClip(String entry) {
    revision++;
    clipLog.add(entry);
  }

  /// How many times a view has asked for the model. A view that reads it once
  /// per frame instead of once per change shows up here as a number that keeps
  /// climbing while nothing is being edited.
  int modelReads = 0;

  @override
  int get modelRevision => revision;

  @override
  List<MixerTrackInfo> readMixerTracks() {
    modelReads++;
    return mixerTracks;
  }

  @override
  void setMixerTrackGain(String trackId, double gain) => _logEffect('gain:$trackId:$gain');

  @override
  void setMixerTrackPan(String trackId, double pan) => _logEffect('pan:$trackId:$pan');

  @override
  void setMixerTrackMuted(String trackId, {required bool muted}) =>
      _logEffect('mute:$trackId:$muted');

  @override
  void setMixerTrackSoloed(String trackId, {required bool soloed}) =>
      _logEffect('solo:$trackId:$soloed');

  @override
  List<EffectDescriptor> readBuiltinEffects() => builtinEffects;

  @override
  List<EffectInfo> readMixerEffects(String trackId) =>
      effects[trackId] ?? const <EffectInfo>[];

  @override
  void addMixerEffect(String trackId, String pluginId, {int? index}) {
    final List<EffectInfo> chain = effects.putIfAbsent(trackId, () => <EffectInfo>[]);
    final String id = 'efx_${_nextEffectId++}';
    final EffectDescriptor descriptor = builtinEffects.firstWhere(
      (EffectDescriptor e) => e.id == pluginId,
      orElse: () => const EffectDescriptor(id: '', name: 'Unknown', summary: ''),
    );
    final int at = (index ?? chain.length).clamp(0, chain.length);
    chain.insert(
      at,
      EffectInfo(
        id: id,
        pluginId: pluginId,
        name: descriptor.name,
        index: at,
        paramCount: 2,
        bypassed: false,
        missing: descriptor.id.isEmpty,
      ),
    );
    _renumber(trackId);
    _logEffect('add:$trackId:$pluginId');
  }

  @override
  int mixerEffectImpact(String trackId, String effectId) => 0;

  @override
  void removeMixerEffect(String trackId, String effectId) {
    effects[trackId]?.removeWhere((EffectInfo e) => e.id == effectId);
    _renumber(trackId);
    _logEffect('remove:$trackId:$effectId');
  }

  @override
  void moveMixerEffect(String trackId, String effectId, int index) {
    final List<EffectInfo>? chain = effects[trackId];
    if (chain == null) return;
    final int from = chain.indexWhere((EffectInfo e) => e.id == effectId);
    if (from < 0) return;
    final EffectInfo moved = chain.removeAt(from);
    chain.insert(index.clamp(0, chain.length), moved);
    _renumber(trackId);
    _logEffect('move:$trackId:$effectId:$index');
  }

  @override
  void setMixerEffectBypassed(String trackId, String effectId, {required bool bypassed}) {
    final List<EffectInfo>? chain = effects[trackId];
    if (chain == null) return;
    final int at = chain.indexWhere((EffectInfo e) => e.id == effectId);
    if (at < 0) return;
    chain[at] = EffectInfo(
      id: chain[at].id,
      pluginId: chain[at].pluginId,
      name: chain[at].name,
      index: chain[at].index,
      paramCount: chain[at].paramCount,
      bypassed: bypassed,
      missing: chain[at].missing,
    );
    _logEffect('bypass:$trackId:$effectId:$bypassed');
  }

  @override
  List<HostedParameter> readMixerEffectParams(String trackId, String effectId) => <HostedParameter>[
    for (final String name in const <String>['Bypass', 'Mix'])
      HostedParameter(
        id: name == 'Bypass' ? 1 : 5,
        name: name,
        module: '/',
        display: '${effectParams['$trackId:$effectId:${name == 'Bypass' ? 1 : 5}'] ?? 0}',
        value: effectParams['$trackId:$effectId:${name == 'Bypass' ? 1 : 5}'] ?? 0,
        minimum: 0,
        maximum: 1,
        defaultValue: 0,
      ),
  ];

  @override
  void setMixerEffectParam(String trackId, String effectId, int paramId, double value) {
    effectParams['$trackId:$effectId:$paramId'] = value;
    _logEffect('param:$trackId:$effectId:$paramId:$value');
  }

  /// Chain position is array position, so it has to be rewritten whenever the
  /// array changes — which is the same thing the engine's flattener does.
  void _renumber(String trackId) {
    final List<EffectInfo>? chain = effects[trackId];
    if (chain == null) return;
    for (int i = 0; i < chain.length; i++) {
      chain[i] = EffectInfo(
        id: chain[i].id,
        pluginId: chain[i].pluginId,
        name: chain[i].name,
        index: i,
        paramCount: chain[i].paramCount,
        bypassed: chain[i].bypassed,
        missing: chain[i].missing,
      );
    }
  }

  // ----- audio clip editing -------------------------------------------------

  /// Audio edit state by clip ID.
  final Map<String, AudioClipEdit> audioClips = <String, AudioClipEdit>{};

  /// Every clip edit the UI asked for, in order.
  final List<String> clipLog = <String>[];

  @override
  AudioClipEdit readAudioClip(String clipId) =>
      audioClips[clipId] ??
      const AudioClipEdit(
        stretchMode: StretchMode.off,
        sourceOffsetTicks: 0,
        sourceLengthTicks: 0,
        sourceDurationTicks: 0,
        sourceBpm: 0,
        gain: 1,
        reversed: false,
      );

  AudioClipEdit _withAudio(String clipId, AudioClipEdit Function(AudioClipEdit) update) {
    final AudioClipEdit next = update(readAudioClip(clipId));
    audioClips[clipId] = next;
    return next;
  }

  @override
  void setAudioClipWindow(String clipId, {required int sourceOffsetTicks, required int sourceLengthTicks}) {
    _withAudio(
      clipId,
      (AudioClipEdit e) => AudioClipEdit(
        stretchMode: e.stretchMode,
        sourceOffsetTicks: sourceOffsetTicks,
        sourceLengthTicks: sourceLengthTicks,
        sourceDurationTicks: e.sourceDurationTicks,
        sourceBpm: e.sourceBpm,
        gain: e.gain,
        reversed: e.reversed,
      ),
    );
    _logClip('window:$clipId:$sourceOffsetTicks:$sourceLengthTicks');
  }

  @override
  void setAudioClipStretchMode(String clipId, StretchMode mode) {
    _withAudio(
      clipId,
      (AudioClipEdit e) => AudioClipEdit(
        stretchMode: mode,
        sourceOffsetTicks: e.sourceOffsetTicks,
        sourceLengthTicks: e.sourceLengthTicks,
        sourceDurationTicks: e.sourceDurationTicks,
        sourceBpm: e.sourceBpm,
        gain: e.gain,
        reversed: e.reversed,
      ),
    );
    _logClip('stretch:$clipId:${mode.name}');
  }

  @override
  void setAudioClipSourceBpm(String clipId, double bpm) {
    _withAudio(
      clipId,
      (AudioClipEdit e) => AudioClipEdit(
        stretchMode: e.stretchMode,
        sourceOffsetTicks: e.sourceOffsetTicks,
        sourceLengthTicks: e.sourceLengthTicks,
        sourceDurationTicks: e.sourceDurationTicks,
        sourceBpm: bpm,
        gain: e.gain,
        reversed: e.reversed,
      ),
    );
    _logClip('bpm:$clipId:$bpm');
  }

  @override
  void setAudioClipReversed(String clipId, {required bool reversed}) {
    _withAudio(
      clipId,
      (AudioClipEdit e) => AudioClipEdit(
        stretchMode: e.stretchMode,
        sourceOffsetTicks: e.sourceOffsetTicks,
        sourceLengthTicks: e.sourceLengthTicks,
        sourceDurationTicks: e.sourceDurationTicks,
        sourceBpm: e.sourceBpm,
        gain: e.gain,
        reversed: reversed,
      ),
    );
    _logClip('reverse:$clipId:$reversed');
  }

  @override
  void setAudioClipGain(String clipId, double gain) => _logClip('gain:$clipId:$gain');

  @override
  void resizeAudioClip(String clipId, int lengthTicks) {
    clips[clipId]?.lengthTicks = lengthTicks;
    _logClip('resizeAudio:$clipId:$lengthTicks');
  }

  @override
  void fitAudioClipToTempo(String clipId) => _logClip('fit:$clipId');

  @override
  void splitClip(String clipId, int atTicks) => _logClip('split:$clipId:$atTicks');

  // ----- project files ------------------------------------------------------
  // Written out rather than left to noSuchMethod: these return values, and a
  // null String from the catch-all is a type error at the call site rather
  // than a useful default.

  /// Where the fake project has been written, and what it is called. Public so
  /// a test can arrange "already saved" or assert what a save did.
  String savedPath = '';
  String name = 'Untitled';
  bool modified = false;
  int saves = 0;
  int opens = 0;

  /// Set to throw from the next [saveProject] or [openProject], which is how
  /// the failure paths are exercised without a broken file on disk.
  EngineException? failure;

  @override
  String get projectPath => savedPath;

  @override
  String get projectName => name;

  @override
  bool get isProjectModified => modified;

  @override
  void setProjectName(String value) {
    name = value;
    modified = true;
  }

  @override
  void saveProject(String path) {
    if (failure case final EngineException error) throw error;
    saves++;
    savedPath = path;
    modified = false;
  }

  @override
  void openProject(String path) {
    if (failure case final EngineException error) throw error;
    opens++;
    savedPath = path;
    modified = false;
  }

  // ----- export -------------------------------------------------------------

  /// The arguments the last [startExport] was given, and what the next status
  /// poll should answer with. A test drives the render by writing to
  /// [exportStatus] between pumps, which is what the engine thread does for
  /// real.
  String? exportedDirectory;
  ExportFormat? exportedFormat;
  int? exportedSampleRate;
  int exportCancels = 0;
  ExportStatus exportStatus = const ExportStatus(
    state: ExportState.idle,
    progress: 0,
    path: '',
    error: '',
  );

  @override
  void startExport({required String directory, required ExportFormat format, required int sampleRate}) {
    if (failure case final EngineException error) throw error;
    exportedDirectory = directory;
    exportedFormat = format;
    exportedSampleRate = sampleRate;
    exportStatus = const ExportStatus(state: ExportState.running, progress: 0, path: '', error: '');
  }

  @override
  ExportStatus readExportStatus() => exportStatus;

  @override
  void cancelExport() {
    exportCancels++;
    exportStatus = const ExportStatus(
      state: ExportState.cancelled,
      progress: 0,
      path: '',
      error: '',
    );
  }
}

class MutablePattern {
  MutablePattern({
    required this.id,
    required this.name,
    required this.color,
    required this.lengthTicks,
  });

  final String id;
  String name;
  String color;
  int lengthTicks;
  double swing = 0;
  final Map<String, List<SequenceNote>> sequences = <String, List<SequenceNote>>{};

  MutablePattern cloneAs(String newId, String newName) {
    final MutablePattern clone = MutablePattern(
      id: newId,
      name: newName,
      color: color,
      lengthTicks: lengthTicks,
    )..swing = swing;
    sequences.forEach((String instrument, List<SequenceNote> notes) {
      clone.sequences[instrument] = List<SequenceNote>.of(notes);
    });
    return clone;
  }
}

class MutableLane {
  MutableLane({required this.id, required this.name, required this.order});

  final String id;
  String name;
  String color = '#6C8CFF';
  int order;
  int height = 72;
  bool muted = false;
  bool soloed = false;
  bool collapsed = false;
}

class MutableClip {
  MutableClip({
    required this.id,
    required this.laneId,
    required this.patternId,
    required this.startTicks,
    required this.lengthTicks,
  });

  final String id;
  String laneId;
  String patternId;
  int startTicks;
  int lengthTicks;
  int windowStartTicks = 0;
  int transpose = 0;
  bool muted = false;
  bool loop = true;
  /// Audio clips carry a source path instead of a pattern, and take the audio
  /// branch of every edit. Set by [FakeEngineClient.addAudioClip].
  bool isAudio = false;
  String audioPath = '';

  MutableClip cloneAs(String newId, String newLaneId, int newStart) =>
      MutableClip(
          id: newId,
          laneId: newLaneId,
          patternId: patternId,
          startTicks: newStart,
          lengthTicks: lengthTicks,
        )
        ..windowStartTicks = windowStartTicks
        ..transpose = transpose
        ..muted = muted
        ..loop = loop;
}
