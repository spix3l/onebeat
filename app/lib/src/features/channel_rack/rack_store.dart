// RackStore — channel rack state and commands (UI-D-02).
//
// Ports the behaviour of `ui/rack_store.dart` and the rack-relevant parts of
// `pattern_store.dart`. The engine remains the model source of truth; this
// store holds presentation selections (selected instrument for the inspector,
// drag paint state) and translates user actions into engine commands.
//
// Every project instrument is a rack row, always. There is deliberately no
// visibility filter: one used to hide channels with no notes in the current
// pattern, but the "keep this one anyway" set lived on this object, so
// switching to the playlist and back rebuilt the store and silently emptied
// the rack of every channel the user had not yet drawn a step on. A channel
// exists because the user made it — the rack shows it until they delete it.
import 'package:flutter/foundation.dart';

import '../../engine/engine_client.dart';

class RackStore extends ChangeNotifier {
  RackStore(this._client);

  final EngineClient _client;

  RackPattern? pattern;
  List<RackRow> rows = const <RackRow>[];
  List<PatternSummary> patterns = const <PatternSummary>[];
  List<ProjectInstrument> instruments = const <ProjectInstrument>[];

  /// Notes per instrument, read for rows that have a sequence so the rack can
  /// draw a piano-roll preview for melodies.
  final Map<String, List<SequenceNote>> notesByInstrument = <String, List<SequenceNote>>{};

  String? selectedInstrumentId;
  String? selectedVelocityInstrument;
  bool showAll = true;

  /// Rows visible under the rack's All/Used filter. The underlying [rows]
  /// remains the complete project rack so changing filters never loses state.
  List<RackRow> get visibleRows => showAll ? rows : rows.where((RackRow row) => row.hasSequence).toList(growable: false);
  int? selectedVelocityStep;

  bool _painting = false;
  bool _velocityPainting = false;
  bool _paintActive = true;
  String? _paintInstrument;
  int? _lastPaintStep;
  final Set<int> _paintedSteps = <int>{};

  bool get canUndo => _client.canUndoProject;
  bool get canRedo => _client.canRedoProject;
  String get undoName => _client.undoProjectName;
  String get redoName => _client.redoProjectName;

  void load() => refresh();

  /// Re-reads the instrument list and refreshes the whole store only when the
  /// set of instruments actually changed. This is the cheap way for the binding
  /// to notice an edit made outside the store — the shell seeding the default
  /// channel on the first tick is the canonical one — without re-reading notes
  /// on every frame.
  void refreshIfInstrumentsChanged() {
    final List<ProjectInstrument> now = _client.readInstruments();
    if (now.length == instruments.length) {
      final Set<String> nowIds = now.map((ProjectInstrument inst) => inst.id).toSet();
      final Set<String> cachedIds = instruments.map((ProjectInstrument inst) => inst.id).toSet();
      if (nowIds.length == cachedIds.length && nowIds.containsAll(cachedIds)) {
        return;
      }
    }
    refresh();
  }

  void refresh() {
    pattern = _client.readRackPattern();
    rows = _client.readRackRows();
    patterns = _client.readPatterns();
    instruments = _client.readInstruments();

    notesByInstrument.clear();
    for (final RackRow row in rows) {
      if (!row.hasSequence) continue;
      try {
        notesByInstrument[row.instrumentId] = _client.readNotes(
          row.instrumentId,
        );
      } catch (_) {
        // Stub if readNotes is unavailable.
      }
    }

    // Selection is a UI action, not a default derived from the engine's
    // current instrument. Keeping it null until a lane is clicked prevents the
    // inspector from occupying the rack before the user has selected anything.
    if (selectedInstrumentId != null &&
        !instruments.any(
          (ProjectInstrument inst) => inst.id == selectedInstrumentId,
        )) {
      selectedInstrumentId = null;
    }

    notifyListeners();
  }

  void removeSequence(String instrumentId) {
    _client.removeRackSequence(instrumentId);
    refresh();
  }

  void setGrid(String instrumentId, int ticks) {
    _client.setRackRowGrid(instrumentId, ticks);
    refresh();
  }

  void setLength(int steps) {
    _client.setRackLength(steps);
    refresh();
  }

  void setSwing(double value) {
    _client.setRackSwing(value.clamp(0.0, 1.0));
    refresh();
  }

  void setShowAll(bool value) {
    if (showAll == value) return;
    showAll = value;
    notifyListeners();
  }

  void selectPattern(String patternId) {
    _client.selectPattern(patternId);
    refresh();
  }

  void selectInstrument(String instrumentId) {
    if (selectedInstrumentId == instrumentId) return;
    selectedInstrumentId = instrumentId;
    selectedVelocityInstrument = instrumentId;
    notifyListeners();
  }

  void toggleStep(String instrumentId, int step) {
    _client.toggleRackStep(instrumentId, step);
    selectedVelocityInstrument = instrumentId;
    selectedVelocityStep = step;
    selectedInstrumentId = instrumentId;
    refresh();
  }

  /// Ensures a note exists at every [interval]th step without removing notes
  /// that are already present.
  void addNotesEvery(String instrumentId, int interval) {
    if (interval <= 0) return;
    final RackRow? row = rowFor(instrumentId);
    if (row == null) return;

    _client.beginRackGesture('Add note every $interval steps');
    for (int step = 0; step < row.steps.length; step += interval) {
      if (!row.steps[step].active) _client.toggleRackStep(instrumentId, step);
    }
    _client.commitRackGesture();
    selectedInstrumentId = instrumentId;
    refresh();
  }

  void beginPaint(String instrumentId, int step, {required bool active}) {
    if (_painting) abortPaint();
    _painting = true;
    _paintActive = active;
    _paintInstrument = instrumentId;
    _lastPaintStep = null;
    _paintedSteps.clear();
    _client.beginRackGesture(active ? 'Paint steps' : 'Erase steps');
    paintStep(instrumentId, step);
  }

  /// Paints the step under the pointer and fills any indices skipped by a
  /// coalesced pointer-move event. That makes a quick click-drag continuous
  /// instead of dependent on the event rate.
  void paintStep(String instrumentId, int step) {
    if (!_painting || _paintInstrument != instrumentId) return;
    final RackRow? row = rowFor(instrumentId);
    if (row == null || step < 0 || step >= row.steps.length) return;

    final int previous = _lastPaintStep ?? step;
    final int direction = step >= previous ? 1 : -1;
    for (int index = previous; ; index += direction) {
      _paintSingleStep(instrumentId, index);
      if (index == step) break;
    }
    _lastPaintStep = step;
    notifyListeners();
  }

  void _paintSingleStep(String instrumentId, int step) {
    if (!_paintedSteps.add(step)) return;
    final RackRow? row = rowFor(instrumentId);
    if (row == null || step < 0 || step >= row.steps.length) return;
    if (row.steps[step].active != _paintActive) {
      _client.toggleRackStep(instrumentId, step);
      rows = _client.readRackRows();
    }
    selectedVelocityInstrument = instrumentId;
    selectedVelocityStep = step;
    selectedInstrumentId = instrumentId;
  }

  void commitPaint() {
    if (!_painting) return;
    _client.commitRackGesture();
    _painting = false;
    _paintInstrument = null;
    _lastPaintStep = null;
    _paintedSteps.clear();
    refresh();
  }

  void abortPaint() {
    if (!_painting) return;
    _client.abortRackGesture();
    _painting = false;
    _paintInstrument = null;
    _lastPaintStep = null;
    _paintedSteps.clear();
    refresh();
  }

  void selectVelocity(String instrumentId, int step) {
    selectedVelocityInstrument = instrumentId;
    selectedVelocityStep = step;
    notifyListeners();
  }

  void nudgeVelocity(int delta) {
    final String? instrumentId = selectedVelocityInstrument;
    final int? step = selectedVelocityStep;
    final RackRow? row = instrumentId == null ? null : rowFor(instrumentId);
    if (instrumentId == null || step == null || row == null || step >= row.steps.length) {
      return;
    }
    final int current = row.steps[step].active ? row.steps[step].velocity : 12900;
    setVelocity(instrumentId, step, (current + delta).clamp(1, 16383));
  }

  void setVelocity(String instrumentId, int step, int velocity) {
    _client.setRackStepVelocity(instrumentId, step, velocity.clamp(1, 16383));
    selectedVelocityInstrument = instrumentId;
    selectedVelocityStep = step;
    selectedInstrumentId = instrumentId;
    refresh();
  }

  void beginVelocityPaint() {
    if (_velocityPainting) return;
    _velocityPainting = true;
    _client.beginRackGesture('Paint step velocity');
  }

  void commitVelocityPaint() {
    if (!_velocityPainting) return;
    _client.commitRackGesture();
    _velocityPainting = false;
    refresh();
  }

  void abortVelocityPaint() {
    if (!_velocityPainting) return;
    _client.abortRackGesture();
    _velocityPainting = false;
    refresh();
  }

  void auditionNote(int key, {double velocity = 0.8}) {
    try {
      _client.auditionNoteOn(key, velocity);
    } catch (_) {
      // Stub if audition not supported on fake client
    }
  }

  void stopAuditionNote(int key) {
    try {
      _client.auditionNoteOff(key);
    } catch (_) {
      // Stub if audition not supported on fake client
    }
  }

  RackRow? rowFor(String instrumentId) {
    for (final RackRow row in rows) {
      if (row.instrumentId == instrumentId) return row;
    }
    return null;
  }

  ProjectInstrument? instrumentFor(String instrumentId) {
    for (final ProjectInstrument inst in instruments) {
      if (inst.id == instrumentId) return inst;
    }
    return null;
  }

  /// The notes of [instrumentId], or an empty list when it has none.
  List<SequenceNote> notesFor(String instrumentId) => notesByInstrument[instrumentId] ?? const <SequenceNote>[];

  // --- the channel clipboard: moving notes between patterns ----------------

  /// The clipboard is deliberately **static**, not a field on this store.
  ///
  /// Cutting is only half a move — the other half happens after the user has
  /// switched patterns, and switching away from the rack (to the playlist, say)
  /// rebuilds this object. A per-store clipboard would therefore drop the notes
  /// the user is in the middle of moving, which is data loss dressed up as a
  /// paste that does nothing. One clipboard per session is also what the user
  /// means by "the clipboard".
  static ChannelNoteClipboard? _clipboard;

  static ChannelNoteClipboard? get clipboard => _clipboard;

  /// Tests share a process, and therefore share the static clipboard.
  @visibleForTesting
  static void clearClipboard() => _clipboard = null;

  bool get canPaste => _clipboard != null;

  /// Reads the live notes of [instrumentId] rather than the cached ones, so a
  /// copy never lags an edit made in the piano roll since the last refresh.
  List<SequenceNote> _liveNotes(String instrumentId) {
    try {
      return _client.readNotes(instrumentId);
    } catch (_) {
      return notesFor(instrumentId);
    }
  }

  /// Puts the selected channel's notes *in the current pattern* on the
  /// clipboard. Returns false when there is nothing to copy — no channel, or a
  /// channel that is empty in this pattern.
  bool copyNotes([String? instrumentId]) {
    final String? id = instrumentId ?? selectedInstrumentId;
    if (id == null || instrumentFor(id) == null) return false;
    final List<SequenceNote> notes = _liveNotes(id);
    if (notes.isEmpty) return false;
    _clipboard = ChannelNoteClipboard(
      instrumentId: id,
      instrumentName: instrumentFor(id)?.name ?? '',
      notes: List<SequenceNote>.unmodifiable(notes),
    );
    notifyListeners();
    return true;
  }

  /// Copy, then lift the notes out of the current pattern as one undo entry.
  /// The channel itself stays: cut moves note data, it does not delete a
  /// channel — deleting one would take its notes out of every other pattern
  /// too, which is the opposite of a move.
  bool cutNotes([String? instrumentId]) {
    final String? id = instrumentId ?? selectedInstrumentId;
    if (id == null || !copyNotes(id)) return false;
    _client.beginRackGesture('Cut notes');
    _client.removeNotes(id, _clipboard!.notes.toList(growable: false));
    _client.commitRackGesture();
    refresh();
    return true;
  }

  /// Writes the clipboard into the *current* pattern — the whole point of the
  /// feature: cut in one pattern, select another, paste. The notes land on the
  /// channel they came from when it still exists, and on the selected channel
  /// otherwise, so a paste after deleting the source channel is not silently
  /// lost. Pasting adds to whatever is already there, as one undo entry.
  bool pasteNotes([String? instrumentId]) {
    final ChannelNoteClipboard? clipboard = _clipboard;
    if (clipboard == null) return false;
    final String? target =
        instrumentId ?? (instrumentFor(clipboard.instrumentId) != null ? clipboard.instrumentId : selectedInstrumentId);
    if (target == null || instrumentFor(target) == null) return false;

    _client.beginRackGesture('Paste notes');
    for (final SequenceNote note in clipboard.notes) {
      _client.addNote(target, note.startTicks, note.lengthTicks, note.key, velocity: note.velocity);
    }
    _client.commitRackGesture();
    selectedInstrumentId = target;
    refresh();
    return true;
  }

  void undo() {
    _client.undoProject();
    refresh();
  }

  void redo() {
    _client.redoProject();
    refresh();
  }
}

/// Notes lifted off one channel, waiting to be dropped into a pattern.
///
/// It holds values, not references: the notes are the ones the source pattern
/// held at the moment of the copy, so editing that pattern afterwards does not
/// change what a later paste writes.
class ChannelNoteClipboard {
  const ChannelNoteClipboard({required this.instrumentId, required this.instrumentName, required this.notes});

  final String instrumentId;
  final String instrumentName;
  final List<SequenceNote> notes;
}
