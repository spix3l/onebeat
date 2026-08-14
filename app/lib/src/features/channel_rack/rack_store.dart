// RackStore — channel rack state and commands (UI-D-02).
//
// Ports the behaviour of `ui/rack_store.dart` and the rack-relevant parts of
// `pattern_store.dart`. The engine remains the model source of truth; this
// store holds presentation selections (e.g. showAll, included empty rows,
// selected instrument for the inspector, drag paint state) and translates
// user actions into engine commands.
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
  final Map<String, List<SequenceNote>> notesByInstrument =
      <String, List<SequenceNote>>{};

  bool showAll = false;
  final Set<String> _includedEmptyRows = <String>{};

  String? selectedInstrumentId;
  String? selectedVelocityInstrument;
  int? selectedVelocityStep;

  bool _painting = false;
  bool _velocityPainting = false;
  bool _paintActive = true;
  String? _paintInstrument;
  final Set<int> _paintedSteps = <int>{};

  bool get canUndo => _client.canUndoProject;
  bool get canRedo => _client.canRedoProject;
  String get undoName => _client.undoProjectName;
  String get redoName => _client.redoProjectName;

  void load() => refresh();

  void refresh() {
    pattern = _client.readRackPattern();
    rows = _client.readRackRows();
    patterns = _client.readPatterns();
    instruments = _client.readInstruments();

    notesByInstrument.clear();
    for (final RackRow row in rows) {
      if (!row.hasSequence) continue;
      try {
        notesByInstrument[row.instrumentId] = _client.readNotes(row.instrumentId);
      } catch (_) {
        // Stub if readNotes is unavailable.
      }
    }

    // Selection is a UI action, not a default derived from the engine's
    // current instrument. Keeping it null until a lane is clicked prevents the
    // inspector from occupying the rack before the user has selected anything.
    if (selectedInstrumentId != null &&
        !instruments.any((ProjectInstrument inst) => inst.id == selectedInstrumentId)) {
      selectedInstrumentId = null;
    }

    notifyListeners();
  }

  bool isVisible(RackRow row) =>
      showAll ||
      row.hasSequence ||
      _includedEmptyRows.contains(row.instrumentId);

  void setShowAll({required bool value}) {
    if (showAll == value) return;
    showAll = value;
    notifyListeners();
  }

  void includeInstrument(String instrumentId) {
    if (_includedEmptyRows.add(instrumentId)) notifyListeners();
  }

  void removeSequence(String instrumentId) {
    _client.removeRackSequence(instrumentId);
    _includedEmptyRows.remove(instrumentId);
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

  void beginPaint(String instrumentId, int step, {required bool active}) {
    if (_painting) abortPaint();
    _painting = true;
    _paintActive = active;
    _paintInstrument = instrumentId;
    _paintedSteps.clear();
    _client.beginRackGesture(active ? 'Paint steps' : 'Erase steps');
    paintStep(instrumentId, step);
  }

  void paintStep(String instrumentId, int step) {
    if (!_painting ||
        _paintInstrument != instrumentId ||
        !_paintedSteps.add(step)) {
      return;
    }
    final RackRow? row = rowFor(instrumentId);
    if (row == null || step >= row.steps.length) return;
    if (row.steps[step].active != _paintActive) {
      _client.toggleRackStep(instrumentId, step);
      rows = _client.readRackRows();
    }
    selectedVelocityInstrument = instrumentId;
    selectedVelocityStep = step;
    selectedInstrumentId = instrumentId;
    notifyListeners();
  }

  void commitPaint() {
    if (!_painting) return;
    _client.commitRackGesture();
    _painting = false;
    _paintInstrument = null;
    _paintedSteps.clear();
    refresh();
  }

  void abortPaint() {
    if (!_painting) return;
    _client.abortRackGesture();
    _painting = false;
    _paintInstrument = null;
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
    if (instrumentId == null ||
        step == null ||
        row == null ||
        step >= row.steps.length) {
      return;
    }
    final int current =
        row.steps[step].active ? row.steps[step].velocity : 12900;
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
  List<SequenceNote> notesFor(String instrumentId) =>
      notesByInstrument[instrumentId] ?? const <SequenceNote>[];

  void undo() {
    _client.undoProject();
    refresh();
  }

  void redo() {
    _client.redoProject();
    refresh();
  }
}
