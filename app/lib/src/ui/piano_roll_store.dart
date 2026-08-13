// Piano roll editor state (OB-3-10).
//
// The model is native and the notes are read back after every edit. What lives
// here is what the model must never learn about: which notes are selected, what
// tool is active, where the viewport is, and the in-flight state of a drag.
//
// Selection is a `Set<SequenceNote>` of *values*, matching how the ABI
// addresses notes. After any edit the selection is re-derived rather than
// carried, because the values it held have changed — see [_reselect].
import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';
import 'pattern_store.dart';

/// Ticks per quarter note. Mirrors the model's constant; musical time is
/// integer ticks everywhere (ADR-004 §3).
const int ticksPerQuarter = 960;
const int ticksPerBar = ticksPerQuarter * 4;

enum PianoTool { draw, select }

/// A snap resolution. Triplets are a third of the plain division, which is why
/// this is a value with a tick count rather than an enum of fractions.
@immutable
class GridChoice {
  const GridChoice(this.label, this.ticks);

  final String label;
  final int ticks;

  static const List<GridChoice> all = <GridChoice>[
    GridChoice('1/4', ticksPerQuarter),
    GridChoice('1/8', ticksPerQuarter ~/ 2),
    GridChoice('1/8T', ticksPerQuarter ~/ 3),
    GridChoice('1/16', ticksPerQuarter ~/ 4),
    GridChoice('1/16T', ticksPerQuarter ~/ 6),
    GridChoice('1/32', ticksPerQuarter ~/ 8),
    GridChoice('Off', 0),
  ];
}

/// The scale used for row highlighting. Intervals are semitones from the root.
@immutable
class MusicalScale {
  const MusicalScale(this.name, this.intervals);

  final String name;
  final List<int> intervals;

  static const List<MusicalScale> all = <MusicalScale>[
    MusicalScale('Chromatic', <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
    MusicalScale('Major', <int>[0, 2, 4, 5, 7, 9, 11]),
    MusicalScale('Minor', <int>[0, 2, 3, 5, 7, 8, 10]),
    MusicalScale('Dorian', <int>[0, 2, 3, 5, 7, 9, 10]),
    MusicalScale('Mixolydian', <int>[0, 2, 4, 5, 7, 9, 10]),
    MusicalScale('Pentatonic', <int>[0, 2, 4, 7, 9]),
    MusicalScale('Blues', <int>[0, 3, 5, 6, 7, 10]),
  ];

  bool contains(int key, int root) =>
      intervals.contains(((key - root) % 12 + 12) % 12);
}

const List<String> pitchClassNames = <String>[
  'C',
  'C♯',
  'D',
  'D♯',
  'E',
  'F',
  'F♯',
  'G',
  'G♯',
  'A',
  'A♯',
  'B',
];

/// A black key on the drawn keyboard, and the row that gets the darker shade.
bool isAccidental(int key) =>
    const <int>[1, 3, 6, 8, 10].contains(((key % 12) + 12) % 12);

String keyName(int key) =>
    '${pitchClassNames[((key % 12) + 12) % 12]}${(key ~/ 12) - 1}';

/// What a drag is doing. Kept as one enum so that a gesture cannot be two
/// things at once, which is the bug that produces notes that both move and
/// resize.
enum PianoDragKind { none, draw, move, resize, marquee, velocity }

class PianoRollStore extends ChangeNotifier {
  PianoRollStore(this._client, this._patterns);

  final NoteClient _client;
  final PatternStore _patterns;

  /// Which instrument's sequence is being edited. Empty until one is selected.
  String instrumentId = '';

  List<SequenceNote> notes = const <SequenceNote>[];

  /// Other instruments' notes in the same pattern, drawn faintly for context.
  List<SequenceNote> ghostNotes = const <SequenceNote>[];

  final Set<SequenceNote> selection = <SequenceNote>{};

  PianoTool tool = PianoTool.draw;
  GridChoice grid = GridChoice.all[3];
  MusicalScale scale = MusicalScale.all[0];
  int scaleRoot = 0;

  /// Length of the last note the user drew, reused as the default for the next
  /// one (OB-3-10 §2). Musicians draw runs of equal-length notes.
  int lastNoteLength = ticksPerQuarter ~/ 4;

  /// Viewport, persisted per (pattern, instrument) for the session (§4).
  double horizontalZoom = 1;
  double verticalZoom = 1;
  double scrollTicks = 0;
  int topKey = 84;

  final Map<String, _Viewport> _viewports = <String, _Viewport>{};

  PianoDragKind dragKind = PianoDragKind.none;
  int _dragDeltaTicks = 0;
  int _dragSemitones = 0;
  int _dragLengthDelta = 0;
  bool _gestureOpen = false;

  /// The marquee rectangle in model space, or null. The painter reads it; the
  /// model never hears about it.
  MarqueeSelection? marquee;

  bool get hasSelection => selection.isNotEmpty;
  int get snapTicks => grid.ticks;

  void load(String instrument, {String fromClipId = ''}) {
    if (instrumentId == instrument) {
      refresh();
      return;
    }
    _saveViewport();
    instrumentId = instrument;
    selection.clear();
    _restoreViewport();
    if (fromClipId.isNotEmpty) _patterns.editingFromClipId = fromClipId;
    refresh();
  }

  void refresh() {
    if (instrumentId.isEmpty) {
      notes = const <SequenceNote>[];
      ghostNotes = const <SequenceNote>[];
      notifyListeners();
      return;
    }
    notes = _client.readNotes(instrumentId);
    _reselect();
    notifyListeners();
  }

  /// Re-derives the selection after an edit. The notes the user selected are
  /// gone as *values* — a moved note has a different start — so selection is
  /// kept by identity-in-time: whatever now occupies the place the selection
  /// moved to. Anything that no longer exists simply drops out, which is what
  /// makes deleting a selection leave nothing selected.
  void _reselect() {
    if (selection.isEmpty) return;
    final Set<SequenceNote> live = notes.toSet();
    selection.removeWhere((SequenceNote note) => !live.contains(note));
  }

  /// Loads the ghost layer: every other instrument's notes in this pattern.
  void setGhostNotes(List<SequenceNote> value) {
    ghostNotes = value;
    notifyListeners();
  }

  // ----- viewport -----------------------------------------------------------

  String get _viewportKey => '${_patterns.current?.id ?? ''}/$instrumentId';

  void _saveViewport() {
    if (instrumentId.isEmpty) return;
    _viewports[_viewportKey] = _Viewport(
      horizontalZoom,
      verticalZoom,
      scrollTicks,
      topKey,
    );
  }

  void _restoreViewport() {
    final _Viewport? saved = _viewports[_viewportKey];
    if (saved == null) return;
    horizontalZoom = saved.horizontalZoom;
    verticalZoom = saved.verticalZoom;
    scrollTicks = saved.scrollTicks;
    topKey = saved.topKey;
  }

  void setTool(PianoTool value) {
    if (tool == value) return;
    tool = value;
    notifyListeners();
  }

  void setGrid(GridChoice value) {
    grid = value;
    notifyListeners();
  }

  void setScale(MusicalScale value, int root) {
    scale = value;
    scaleRoot = ((root % 12) + 12) % 12;
    notifyListeners();
  }

  void zoomHorizontally(double factor) {
    horizontalZoom = (horizontalZoom * factor).clamp(0.15, 12.0);
    _saveViewport();
    notifyListeners();
  }

  void zoomVertically(double factor) {
    verticalZoom = (verticalZoom * factor).clamp(0.5, 4.0);
    _saveViewport();
    notifyListeners();
  }

  void panTo(double ticks, int key) {
    scrollTicks = ticks < 0 ? 0 : ticks;
    topKey = key.clamp(11, 127);
    _saveViewport();
    notifyListeners();
  }

  /// Zoom-to-selection (§4). A no-op with nothing selected rather than an
  /// error: the toolbar button stays enabled and simply does nothing useful,
  /// which is less surprising than a control that greys out mid-gesture.
  void zoomToSelection({required double viewportWidth}) {
    if (selection.isEmpty || viewportWidth <= 0) return;
    int lowTick = 1 << 62;
    int highTick = 0;
    int lowKey = 127;
    int highKey = 0;
    for (final SequenceNote note in selection) {
      lowTick = note.startTicks < lowTick ? note.startTicks : lowTick;
      highTick = note.endTicks > highTick ? note.endTicks : highTick;
      lowKey = note.key < lowKey ? note.key : lowKey;
      highKey = note.key > highKey ? note.key : highKey;
    }
    final int span = (highTick - lowTick).clamp(ticksPerQuarter, 1 << 30);
    horizontalZoom = (viewportWidth / (span * _basePixelsPerTick)).clamp(
      0.15,
      12.0,
    );
    scrollTicks = (lowTick - ticksPerQuarter / 2).clamp(0, double.infinity);
    topKey = (highKey + 2).clamp(11, 127);
    _saveViewport();
    notifyListeners();
  }

  static const double _basePixelsPerTick = 0.08;
  double get pixelsPerTick => _basePixelsPerTick * horizontalZoom;

  // ----- selection ----------------------------------------------------------

  void selectOnly(SequenceNote note) {
    selection
      ..clear()
      ..add(note);
    notifyListeners();
  }

  void toggleSelection(SequenceNote note) {
    if (!selection.remove(note)) selection.add(note);
    notifyListeners();
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(notes);
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    notifyListeners();
  }

  /// The note under a point, topmost first. Notes do not overlap visually
  /// within a row, so "first match" is unambiguous.
  SequenceNote? noteAt(int tick, int key) {
    for (final SequenceNote note in notes) {
      if (note.key != key) continue;
      if (tick >= note.startTicks && tick < note.endTicks) return note;
    }
    return null;
  }

  int snap(int tick) {
    if (snapTicks <= 0) return tick < 0 ? 0 : tick;
    final int snapped = ((tick / snapTicks).round()) * snapTicks;
    return snapped < 0 ? 0 : snapped;
  }

  int snapDown(int tick) {
    if (snapTicks <= 0) return tick < 0 ? 0 : tick;
    final int snapped = (tick ~/ snapTicks) * snapTicks;
    return snapped < 0 ? 0 : snapped;
  }

  // ----- edits --------------------------------------------------------------
  //
  // Every one of these goes through the native command layer, so every one of
  // them undoes. None of them mutates `notes` directly: the model is the source
  // of truth and is re-read afterwards.

  /// Opens the native transaction that makes a whole drag one history entry.
  void _beginGesture(String name) {
    if (_gestureOpen) return;
    _patterns.noteEditStarted();
    _client.beginGesture(name);
    _gestureOpen = true;
  }

  void addNoteAt(int tick, int key, {int? length}) {
    if (instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    final int start = snapDown(tick);
    final int noteLength = length ?? lastNoteLength;
    _client.addNote(instrumentId, start, noteLength, key);
    lastNoteLength = noteLength;
    refresh();
    final SequenceNote? created = noteAt(start, key);
    if (created != null) selectOnly(created);
  }

  void deleteSelection() {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    _client.removeNotes(instrumentId, selection.toList());
    selection.clear();
    refresh();
  }

  void deleteNote(SequenceNote note) {
    if (instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    _client.removeNotes(instrumentId, <SequenceNote>[note]);
    selection.remove(note);
    refresh();
  }

  void duplicateSelection() {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    // Offset by the selection's span, rounded up to the grid, so a duplicated
    // phrase lands after itself rather than on top of itself.
    int lowest = 1 << 62;
    int highest = 0;
    for (final SequenceNote note in selection) {
      lowest = note.startTicks < lowest ? note.startTicks : lowest;
      highest = note.endTicks > highest ? note.endTicks : highest;
    }
    int delta = highest - lowest;
    if (snapTicks > 0) {
      delta = ((delta + snapTicks - 1) ~/ snapTicks) * snapTicks;
    }
    if (delta <= 0) delta = lastNoteLength;
    _client.duplicateNotes(instrumentId, selection.toList(), deltaTicks: delta);
    _shiftSelection(deltaTicks: delta);
    refresh();
  }

  void transposeSelection(int semitones) {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    _client.moveNotes(instrumentId, selection.toList(), semitones: semitones);
    _shiftSelection(semitones: semitones);
    refresh();
  }

  void nudgeSelection(int deltaTicks) {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    _client.moveNotes(instrumentId, selection.toList(), deltaTicks: deltaTicks);
    _shiftSelection(deltaTicks: deltaTicks);
    refresh();
  }

  void setSelectionVelocity(int velocity) {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _patterns.noteEditStarted();
    final int clamped = velocity.clamp(1, 16383);
    _client.setNoteVelocity(instrumentId, selection.toList(), clamped);
    final List<SequenceNote> updated = selection
        .map((SequenceNote note) => note.copyWith(velocity: clamped))
        .toList();
    selection
      ..clear()
      ..addAll(updated);
    refresh();
  }

  void quantiseSelection({double strength = 1.0}) {
    if (selection.isEmpty || instrumentId.isEmpty || snapTicks <= 0) return;
    _patterns.noteEditStarted();
    _client.quantiseNotes(
      instrumentId,
      selection.toList(),
      gridTicks: snapTicks,
      strength: strength,
    );
    // Quantise moves notes by amounts the store cannot predict, so the
    // selection is rebuilt from what the model reports rather than shifted.
    final Set<int> keys = selection.map((SequenceNote n) => n.key).toSet();
    selection.clear();
    refresh();
    selection.addAll(notes.where((SequenceNote n) => keys.contains(n.key)));
    notifyListeners();
  }

  /// Keeps the selection pointing at the same notes after a wholesale shift.
  void _shiftSelection({int deltaTicks = 0, int semitones = 0}) {
    final List<SequenceNote> moved = selection
        .map(
          (SequenceNote note) => note.copyWith(
            startTicks: note.startTicks + deltaTicks,
            key: note.key + semitones,
          ),
        )
        .toList();
    selection
      ..clear()
      ..addAll(moved);
  }

  // ----- drags --------------------------------------------------------------
  //
  // A drag is one undo entry: the gesture brackets every intermediate edit, and
  // the intermediate steps are applied as deltas relative to the drag's start.

  void beginMove() {
    if (selection.isEmpty) return;
    dragKind = PianoDragKind.move;
    _dragDeltaTicks = 0;
    _dragSemitones = 0;
    _beginGesture('Move notes');
    notifyListeners();
  }

  void updateMove(int deltaTicks, int semitones) {
    if (dragKind != PianoDragKind.move) return;
    final int tickStep = deltaTicks - _dragDeltaTicks;
    final int keyStep = semitones - _dragSemitones;
    if (tickStep == 0 && keyStep == 0) return;
    _client.moveNotes(
      instrumentId,
      selection.toList(),
      deltaTicks: tickStep,
      semitones: keyStep,
    );
    _shiftSelection(deltaTicks: tickStep, semitones: keyStep);
    _dragDeltaTicks = deltaTicks;
    _dragSemitones = semitones;
    refresh();
  }

  void beginResize() {
    if (selection.isEmpty) return;
    dragKind = PianoDragKind.resize;
    _dragLengthDelta = 0;
    _beginGesture('Resize notes');
    notifyListeners();
  }

  void updateResize(int lengthDelta) {
    if (dragKind != PianoDragKind.resize) return;
    final int step = lengthDelta - _dragLengthDelta;
    if (step == 0) return;
    _client.resizeNotes(instrumentId, selection.toList(), lengthDelta: step);
    final List<SequenceNote> resized = selection
        .map(
          (SequenceNote note) => note.copyWith(
            lengthTicks: note.lengthTicks + step < 1
                ? 1
                : note.lengthTicks + step,
          ),
        )
        .toList();
    selection
      ..clear()
      ..addAll(resized);
    _dragLengthDelta = lengthDelta;
    if (selection.isNotEmpty) lastNoteLength = selection.first.lengthTicks;
    refresh();
  }

  void beginMarquee(int tick, int key) {
    dragKind = PianoDragKind.marquee;
    marquee = MarqueeSelection(tick, key, tick, key);
    notifyListeners();
  }

  void updateMarquee(int tick, int key) {
    final MarqueeSelection? current = marquee;
    if (dragKind != PianoDragKind.marquee || current == null) return;
    marquee = MarqueeSelection(
      current.startTick,
      current.startKey,
      tick,
      key,
    );
    selection
      ..clear()
      ..addAll(notes.where((SequenceNote note) => marquee!.contains(note)));
    notifyListeners();
  }

  void endDrag() {
    if (dragKind == PianoDragKind.none) {
      marquee = null;
      return;
    }
    dragKind = PianoDragKind.none;
    marquee = null;
    if (_gestureOpen) {
      _client.commitGesture();
      _gestureOpen = false;
    }
    _dragDeltaTicks = 0;
    _dragSemitones = 0;
    _dragLengthDelta = 0;
    refresh();
  }

  /// Cancels an in-flight drag, reverting every edit it made. Bound to Escape,
  /// which is what makes an accidental drag across a dense pattern recoverable
  /// without reaching for undo.
  void cancelDrag() {
    if (dragKind == PianoDragKind.none) return;
    dragKind = PianoDragKind.none;
    marquee = null;
    if (_gestureOpen) {
      _client.abortGesture();
      _gestureOpen = false;
    }
    _dragDeltaTicks = 0;
    _dragSemitones = 0;
    _dragLengthDelta = 0;
    refresh();
  }

  // ----- audition -----------------------------------------------------------

  void audition(int key) {
    _client
      ..auditionNoteOn(key, 0.8)
      ..auditionNoteOff(key);
  }
}

@immutable
class MarqueeSelection {
  const MarqueeSelection(
    this.startTick,
    this.startKey,
    this.endTick,
    this.endKey,
  );

  final int startTick;
  final int startKey;
  final int endTick;
  final int endKey;

  int get lowTick => startTick < endTick ? startTick : endTick;
  int get highTick => startTick < endTick ? endTick : startTick;
  int get lowKey => startKey < endKey ? startKey : endKey;
  int get highKey => startKey < endKey ? endKey : startKey;

  /// Half-open in time, inclusive in pitch — the same rule the model's
  /// `NoteRange` uses, so a lasso and a range query agree.
  bool contains(SequenceNote note) =>
      note.key >= lowKey &&
      note.key <= highKey &&
      note.endTicks > lowTick &&
      note.startTicks < highTick;
}

@immutable
class _Viewport {
  const _Viewport(
    this.horizontalZoom,
    this.verticalZoom,
    this.scrollTicks,
    this.topKey,
  );

  final double horizontalZoom;
  final double verticalZoom;
  final double scrollTicks;
  final int topKey;
}
