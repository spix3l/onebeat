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
        name: pattern?.name ?? '',
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
      );
    }).toList();
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
