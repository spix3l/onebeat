// Piano roll editor state and commands (UI-D-03, OB-3-10).
//
// The model is native and notes are read back after every edit. What lives here
// is what the model must never learn about: which notes are selected, what tool
// is active, where the viewport is, and the in-flight state of a drag.
//
// Selection is a `Set<SequenceNote>` of values, matching how the ABI addresses
// notes. After any edit the selection is re-derived rather than carried.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import 'pr_toolbar.dart';

/// Ticks per quarter note. Mirrors the model's constant; musical time is
/// integer ticks everywhere (ADR-004 §3).
const int ticksPerQuarter = 960;
const int ticksPerBar = ticksPerQuarter * 4;

/// A snap resolution. Triplets are a third of the plain division.
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

/// A black key on the drawn keyboard.
bool isAccidental(int key) =>
    const <int>[1, 3, 6, 8, 10].contains(((key % 12) + 12) % 12);

String keyName(int key) =>
    '${pitchClassNames[((key % 12) + 12) % 12]}${(key ~/ 12) - 1}';

/// What a drag gesture is currently doing.
enum PianoDragKind { none, draw, move, resize, marquee, velocity, erase }

class PianoRollStore extends ChangeNotifier {
  PianoRollStore(this._client, [this._patterns]);

  final EngineClient _client;
  // ignore: unused_field
  final Object? _patterns;

  /// Which instrument's sequence is being edited.
  String instrumentId = '';

  /// Currently selected pattern ID.
  String patternId = '';

  List<SequenceNote> notes = const <SequenceNote>[];
  List<SequenceNote> ghostNotes = const <SequenceNote>[];
  final Set<SequenceNote> selection = <SequenceNote>{};
  List<PatternSummary> patterns = const <PatternSummary>[];
  List<ProjectInstrument> instruments = const <ProjectInstrument>[];

  PrTool tool = PrTool.pencil;
  GridChoice grid = GridChoice.all[3]; // 1/16
  MusicalScale scale = MusicalScale.all[0]; // Chromatic
  int scaleRoot = 0; // C

  /// Length of the last note drawn, reused as default for next note.
  int lastNoteLength = ticksPerQuarter ~/ 4;

  /// The length a newly drawn note gets: whatever the last one was.
  ///
  /// Reuse rather than "always the grid", because once you have sized a note by
  /// hand you are usually about to draw more like it. [setGrid] is what
  /// re-couples the two — see the note there.
  int get defaultNoteLength => lastNoteLength;

  /// Viewport state.
  double horizontalZoom = 1.0;
  double verticalZoom = 1.0;
  double scrollTicks = 0.0;
  int topKey = 84;

  final Map<String, _Viewport> _viewports = <String, _Viewport>{};

  PianoDragKind dragKind = PianoDragKind.none;
  int _dragDeltaTicks = 0;
  int _dragSemitones = 0;
  int _dragLengthDelta = 0;
  bool _gestureOpen = false;

  MarqueeSelection? marquee;

  bool get hasSelection => selection.isNotEmpty;
  int get snapTicks => grid.ticks;

  bool get canUndo {
    try {
      return _client.canUndoProject;
    } catch (_) {
      return false;
    }
  }

  bool get canRedo {
    try {
      return _client.canRedoProject;
    } catch (_) {
      return false;
    }
  }

  String get undoName {
    try {
      return _client.undoProjectName;
    } catch (_) {
      return 'Edit notes';
    }
  }

  String get redoName {
    try {
      return _client.redoProjectName;
    } catch (_) {
      return 'Edit notes';
    }
  }

  void load(String instrument, {String fromClipId = ''}) {
    if (instrumentId == instrument) {
      refresh();
      return;
    }
    _saveViewport();
    instrumentId = instrument;
    selection.clear();
    _restoreViewport();
    refresh();
  }

  void refresh() {
    try {
      patterns = _client.readPatterns();
      if (patterns.isNotEmpty) {
        final PatternSummary? current = patterns.cast<PatternSummary?>().firstWhere(
              (PatternSummary? p) => p?.isCurrent ?? false,
              orElse: () => patterns.first,
            );
        patternId = current?.id ?? patterns.first.id;
      }
    } catch (_) {
      // Stub if readPatterns not available
    }

    try {
      instruments = _client.readInstruments();
      if (instrumentId.isEmpty && instruments.isNotEmpty) {
        final ProjectInstrument? sel = instruments.cast<ProjectInstrument?>().firstWhere(
              (ProjectInstrument? inst) => inst?.selected ?? false,
              orElse: () => instruments.first,
            );
        instrumentId = sel?.id ?? instruments.first.id;
      }
    } catch (_) {
      // Stub if readInstruments not available
    }

    if (instrumentId.isEmpty) {
      notes = const <SequenceNote>[];
      ghostNotes = const <SequenceNote>[];
      notifyListeners();
      return;
    }

    notes = _client.readNotes(instrumentId);
    _reselect();
    _refreshGhosts();
    notifyListeners();
  }

  void _refreshGhosts() {
    if (instruments.isEmpty) return;
    final List<SequenceNote> ghosts = <SequenceNote>[];
    for (final ProjectInstrument inst in instruments) {
      if (inst.id == instrumentId) continue;
      try {
        ghosts.addAll(_client.readNotes(inst.id));
      } catch (_) {
        // Skip if read fails
      }
    }
    ghostNotes = ghosts;
  }

  void _reselect() {
    if (selection.isEmpty) return;
    final Set<SequenceNote> live = notes.toSet();
    selection.removeWhere((SequenceNote note) => !live.contains(note));
  }

  void setGhostNotes(List<SequenceNote> value) {
    ghostNotes = value;
    notifyListeners();
  }

  void selectPattern(String newPatternId) {
    if (patternId == newPatternId) return;
    try {
      _client.selectPattern(newPatternId);
    } catch (_) {
      // Stub
    }
    patternId = newPatternId;
    refresh();
  }

  // ----- Viewport -----------------------------------------------------------

  String get _viewportKey => '$patternId/$instrumentId';

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

  void setTool(PrTool value) {
    if (tool == value) return;
    tool = value;
    notifyListeners();
  }

  /// Picks the snap resolution — and, with it, the size of the next note.
  ///
  /// Choosing "1/8" and then drawing a 1/16 is the reason Snap read as a
  /// control that did nothing. Reaching for the grid is a statement about the
  /// resolution you are working at, so it re-arms [lastNoteLength]; drawing or
  /// resizing by hand then takes over again until you next change it.
  void setGrid(GridChoice value) {
    grid = value;
    if (value.ticks > 0) lastNoteLength = value.ticks;
    notifyListeners();
  }

  void setScale(MusicalScale value, int root) {
    scale = value;
    scaleRoot = ((root % 12) + 12) % 12;
    notifyListeners();
  }

  /// Zooms the time axis, keeping [anchorTick] under the same pixel.
  ///
  /// Without an anchor a zoom is measured from the left edge, which walks the
  /// thing you were looking at off the screen — the single most common
  /// complaint about a roll that "zooms wrong". The anchor is normally the tick
  /// under the pointer, or the centre of the viewport for a button or a key.
  void zoomHorizontally(double factor, {double? anchorTick}) {
    final double before = horizontalZoom;
    horizontalZoom = (horizontalZoom * factor).clamp(minZoom, maxZoom);
    if (horizontalZoom == before) return;
    if (anchorTick != null) {
      final double offsetFromLeft = anchorTick - scrollTicks;
      scrollTicks = anchorTick - offsetFromLeft * (before / horizontalZoom);
      if (scrollTicks < 0) scrollTicks = 0;
    }
    _saveViewport();
    notifyListeners();
  }

  /// Zooms the pitch axis, keeping [anchorKey] on the same row.
  void zoomVertically(double factor, {int? anchorKey, int visibleRows = 0}) {
    final double before = verticalZoom;
    verticalZoom = (verticalZoom * factor).clamp(minRowZoom, maxRowZoom);
    if (verticalZoom == before) return;
    if (anchorKey != null && visibleRows > 0) {
      final int rowsAbove = topKey - anchorKey;
      final int scaled = (rowsAbove * (before / verticalZoom)).round();
      topKey = (anchorKey + scaled).clamp(0, maxKey);
    }
    _saveViewport();
    notifyListeners();
  }

  static const double minZoom = 0.15;
  static const double maxZoom = 12.0;
  static const double minRowZoom = 0.5;
  static const double maxRowZoom = 4.0;
  static const int maxKey = 127;

  void panTo(double ticks, int key) {
    scrollTicks = ticks < 0 ? 0 : ticks;
    topKey = key.clamp(0, maxKey);
    _saveViewport();
    notifyListeners();
  }

  /// Pans by a delta in each axis. The one entry point every pan gesture and
  /// key binding goes through, so bounds are enforced once.
  ///
  /// [visibleRows] lets the bottom of the keyboard be a real floor: without it
  /// the roll scrolls past key 0 into empty canvas.
  void panBy({double deltaTicks = 0, int deltaKeys = 0, int visibleRows = 0}) {
    final double ticks = scrollTicks + deltaTicks;
    final int floor = visibleRows > 0 ? (visibleRows - 1).clamp(0, maxKey) : 0;
    panTo(ticks, (topKey + deltaKeys).clamp(floor, maxKey));
  }

  /// The last tick any note in this instrument's sequence ends on. 0 when there
  /// are none.
  int get noteEndTicks {
    int end = 0;
    for (final SequenceNote note in notes) {
      if (note.endTicks > end) end = note.endTicks;
    }
    return end;
  }

  /// The last tick with anything on it — where the horizontal rail's track
  /// ends. Padded by a bar so there is always somewhere to write next.
  int get contentEndTicks {
    final int end = noteEndTicks;
    const int floor = ticksPerBar * 4;
    return (end > floor ? end : floor) + ticksPerBar;
  }

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
      minZoom,
      maxZoom,
    );
    scrollTicks = (lowTick - ticksPerQuarter / 2).clamp(0, double.infinity);
    topKey = (highKey + 2).clamp(0, maxKey);
    _saveViewport();
    notifyListeners();
  }

  static const double _basePixelsPerTick = 0.08;
  double get pixelsPerTick => _basePixelsPerTick * horizontalZoom;

  // ----- Selection ----------------------------------------------------------

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

  // ----- Edits & Transactions -----------------------------------------------

  void _beginGesture(String name) {
    if (_gestureOpen) return;
    _client.beginGesture(name);
    _gestureOpen = true;
  }

  void _commitGesture() {
    if (!_gestureOpen) return;
    _client.commitGesture();
    _gestureOpen = false;
  }

  void addNoteAt(int tick, int key, {int? length, int velocity = 12900}) {
    if (instrumentId.isEmpty) return;
    final int start = snapDown(tick);
    final int noteLength = length ?? defaultNoteLength;
    _client.addNote(
      instrumentId,
      start,
      noteLength,
      key,
      velocity: velocity,
    );
    lastNoteLength = noteLength;
    refresh();
    final SequenceNote? created = noteAt(start, key);
    if (created != null) selectOnly(created);
  }

  void deleteSelection() {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _client.removeNotes(instrumentId, selection.toList());
    selection.clear();
    refresh();
  }

  void deleteNote(SequenceNote note) {
    if (instrumentId.isEmpty) return;
    _client.removeNotes(instrumentId, <SequenceNote>[note]);
    selection.remove(note);
    refresh();
  }

  void duplicateSelection() {
    if (selection.isEmpty || instrumentId.isEmpty) return;
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

  // ----- Clipboard ----------------------------------------------------------

  /// The copied phrase, held with its start ticks relative to [_clipboardTick]
  /// — a *shape*, so it can be dropped anywhere rather than only back where it
  /// came from.
  ///
  /// Static, because a clipboard the user cannot carry between instruments is
  /// not a clipboard. Every roll shares one, the way ⌘C works everywhere else.
  static List<SequenceNote> _clipboard = const <SequenceNote>[];
  static int _clipboardTick = 0;

  bool get hasClipboard => _clipboard.isNotEmpty;

  /// The tick the copied phrase was taken from — where a plain paste puts it
  /// back.
  int get clipboardTick => _clipboardTick;

  /// The first free slot on the timeline: the snap step at or after the last
  /// note's end.
  ///
  /// Where a paste lands when the pointer is not over the canvas — the next
  /// place you could have written something, so a blind ⌘V appends rather than
  /// dropping a copy on top of the bar you are looking at.
  int get nextFreeTick {
    final int end = noteEndTicks;
    if (end <= 0) return 0;
    if (snapTicks <= 0) return end;
    return ((end + snapTicks - 1) ~/ snapTicks) * snapTicks;
  }

  void copySelection() {
    if (selection.isEmpty) return;
    int lowest = 1 << 62;
    for (final SequenceNote note in selection) {
      if (note.startTicks < lowest) lowest = note.startTicks;
    }
    _clipboardTick = lowest;
    _clipboard = selection
        .map(
          (SequenceNote note) =>
              note.copyWith(startTicks: note.startTicks - lowest),
        )
        .toList()
      ..sort((SequenceNote a, SequenceNote b) {
        final int byTick = a.startTicks.compareTo(b.startTicks);
        return byTick != 0 ? byTick : a.key.compareTo(b.key);
      });
    notifyListeners();
  }

  void cutSelection() {
    if (selection.isEmpty) return;
    copySelection();
    deleteSelection();
  }

  /// Drops the copied phrase at [atTick], or back where it was copied from.
  ///
  /// The paste becomes the selection, so the very next gesture — a nudge, a
  /// drag, another paste — acts on what you just made rather than on what you
  /// copied it from.
  void pasteClipboard({int? atTick}) {
    if (_clipboard.isEmpty || instrumentId.isEmpty) return;
    final int origin = atTick ?? _clipboardTick;
    _beginGesture('Paste notes');
    for (final SequenceNote note in _clipboard) {
      _client.addNote(
        instrumentId,
        origin + note.startTicks,
        note.lengthTicks,
        note.key,
        velocity: note.velocity,
      );
    }
    _commitGesture();
    final Set<int> pasted = <int>{
      for (final SequenceNote note in _clipboard)
        Object.hash(origin + note.startTicks, note.key),
    };
    selection.clear();
    refresh();
    selection.addAll(
      notes.where(
        (SequenceNote note) =>
            pasted.contains(Object.hash(note.startTicks, note.key)),
      ),
    );
    notifyListeners();
  }

  void transposeSelection(int semitones) {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _client.moveNotes(instrumentId, selection.toList(), semitones: semitones);
    _shiftSelection(semitones: semitones);
    refresh();
  }

  void nudgeSelection(int deltaTicks) {
    if (selection.isEmpty || instrumentId.isEmpty) return;
    _client.moveNotes(instrumentId, selection.toList(), deltaTicks: deltaTicks);
    _shiftSelection(deltaTicks: deltaTicks);
    refresh();
  }

  void setSelectionVelocity(int velocity) {
    if (selection.isEmpty || instrumentId.isEmpty) return;
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

  /// Sets one note's velocity, leaving the selection alone.
  ///
  /// The lane edits the stem you are pointing at. Routing every lane drag
  /// through [setSelectionVelocity] meant grabbing one stem flattened every
  /// selected note to the same value — destructive, and invisible until you
  /// looked away from the stem you were dragging.
  void setNoteVelocity(SequenceNote note, int velocity) {
    if (instrumentId.isEmpty) return;
    final int clamped = velocity.clamp(1, 16383);
    if (note.velocity == clamped) return;
    _client.setNoteVelocity(instrumentId, <SequenceNote>[note], clamped);
    // The selection holds notes by value, so the edited note's old value would
    // dangle. Swap it for the new one rather than dropping the selection.
    if (selection.remove(note)) {
      selection.add(note.copyWith(velocity: clamped));
    }
    refresh();
  }

  /// Opens an undo transaction around a run of lane drags, so dragging across
  /// twenty stems is one undo step rather than twenty.
  void beginVelocityGesture() {
    if (dragKind == PianoDragKind.velocity) return;
    dragKind = PianoDragKind.velocity;
    _beginGesture('Set velocity');
    notifyListeners();
  }

  /// The note whose stem is nearest [tick], within [toleranceTicks].
  ///
  /// A stem is a few pixels wide, so the lane hit-tests by proximity to the
  /// note's *start* rather than by containment — otherwise short notes at a
  /// low zoom would be unhittable.
  SequenceNote? noteNearTick(int tick, int toleranceTicks) {
    SequenceNote? best;
    int bestDistance = toleranceTicks;
    for (final SequenceNote note in notes) {
      final int distance = (note.startTicks - tick).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = note;
      }
    }
    return best;
  }

  /// Every note whose stem lands on the *same* lane position as the nearest
  /// one — a chord, whose stems coincide exactly.
  ///
  /// The lane is one-dimensional: it has an x for time and a y for the value,
  /// and no axis left over for pitch. So a chord is a genuinely ambiguous
  /// target; the caller resolves it against the selection.
  List<SequenceNote> notesNearTick(int tick, int toleranceTicks) {
    final SequenceNote? nearest = noteNearTick(tick, toleranceTicks);
    if (nearest == null) return const <SequenceNote>[];
    return notes
        .where((SequenceNote note) => note.startTicks == nearest.startTicks)
        .toList();
  }

  void quantiseSelection({double strength = 1.0}) {
    if (selection.isEmpty || instrumentId.isEmpty || snapTicks <= 0) return;
    _client.quantiseNotes(
      instrumentId,
      selection.toList(),
      gridTicks: snapTicks,
      strength: strength,
    );
    final Set<int> keys = selection.map((SequenceNote n) => n.key).toSet();
    selection.clear();
    refresh();
    selection.addAll(notes.where((SequenceNote n) => keys.contains(n.key)));
    notifyListeners();
  }

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

  // ----- Drags --------------------------------------------------------------

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

  /// Opens an erase drag: one undo step for however many notes the sweep
  /// crosses, rather than one per note.
  void beginErase() {
    if (dragKind == PianoDragKind.erase) return;
    dragKind = PianoDragKind.erase;
    _beginGesture('Erase notes');
    notifyListeners();
  }

  /// Removes the note under (tick, key), if there is one. Returns whether it
  /// removed anything, so a sweep can skip the read-back when it crosses empty
  /// canvas — which is most of the pixels in a drag.
  bool eraseAt(int tick, int key) {
    final SequenceNote? hit = noteAt(tick, key);
    if (hit == null) return false;
    deleteNote(hit);
    return true;
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
    _commitGesture();
    _dragDeltaTicks = 0;
    _dragSemitones = 0;
    _dragLengthDelta = 0;
    refresh();
  }

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

  // ----- Audition -----------------------------------------------------------

  Timer? _auditionTimer;
  int _auditionKey = -1;

  /// The key currently being previewed, or null. The roll lights its row while
  /// it sounds: a preview you can hear but not see leaves you hunting for which
  /// row you just hit, which is the whole reason for clicking the keyboard.
  int? get auditionKey => _auditionKey < 0 ? null : _auditionKey;

  /// Previews a note with an audible length: note-on now, note-off a moment
  /// later. Sending both back-to-back produced a note so short it was silent.
  void audition(int key, {double velocity = 0.8}) {
    _releaseAudition();
    _auditionKey = key;
    notifyListeners();
    try {
      _client.auditionNoteOn(key, velocity);
    } catch (_) {
      // Preview path stub
    }
    _auditionTimer = Timer(OneBeatTokens.dark().motion.settled, _releaseAudition);
  }

  void _releaseAudition() {
    _auditionTimer?.cancel();
    _auditionTimer = null;
    if (_auditionKey < 0) return;
    final int key = _auditionKey;
    _auditionKey = -1;
    try {
      _client.auditionNoteOff(key);
    } catch (_) {
      // Preview path stub
    }
    // The row has to go dark again when the preview ends. Guarded because this
    // also runs from dispose, where notifying is both pointless and illegal.
    if (hasListeners) notifyListeners();
  }

  /// Ends any audition in flight and cancels its pending note-off.
  ///
  /// The preview is a note-on with a note-off owed 250ms later. If the roll
  /// goes away in between, nobody sends the note-off and the instrument holds
  /// the note forever — so whoever started the preview has to be able to end
  /// it, whether or not it owns this store.
  void stopAudition() => _releaseAudition();

  void auditionNoteOff(int key) {
    try {
      _client.auditionNoteOff(key);
    } catch (_) {
      // Preview path stub
    }
  }

  @override
  void dispose() {
    _releaseAudition();
    super.dispose();
  }

  void undo() {
    try {
      _client.undoProject();
      refresh();
    } catch (_) {
      // Stub
    }
  }

  void redo() {
    try {
      _client.redoProject();
      refresh();
    } catch (_) {
      // Stub
    }
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
