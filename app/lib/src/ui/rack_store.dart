import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';

/// Editor state for the channel rack. The model remains native; this store
/// holds only presentation choices such as Show all and explicitly-added empty
/// rows, so the pattern's sparse sequence map stays sparse (D-M5).
class RackStore extends ChangeNotifier {
  RackStore(this._client);

  final RackClient _client;

  RackPattern? pattern;
  List<RackRow> rows = const <RackRow>[];
  bool showAll = false;
  final Set<String> _includedEmptyRows = <String>{};

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

  void toggleStep(String instrumentId, int step) {
    _client.toggleRackStep(instrumentId, step);
    selectedVelocityInstrument = instrumentId;
    selectedVelocityStep = step;
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

  RackRow? rowFor(String instrumentId) {
    for (final RackRow row in rows) {
      if (row.instrumentId == instrumentId) return row;
    }
    return null;
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
