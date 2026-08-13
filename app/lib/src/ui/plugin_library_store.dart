// The UI's view of the plug-in library (OB-2-02 scope §4, §5).
//
// The startup order is the point of this class. `load()` reads the persistent
// cache synchronously — one file read — so the list exists before the first
// frame, and only then starts a scan whose results arrive underneath a working
// UI (FR-PLG-05). Nothing here ever blocks on the scan.
//
// It does not own a ticker. `pump()` is driven from `EngineController`'s
// existing per-frame callback, because a second ticker would be a second thing
// that can disagree with the first about what frame it is.
import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';

class PluginLibraryStore extends ChangeNotifier {
  PluginLibraryStore(this._client);

  final EngineClient _client;

  PluginScanStatus status = const PluginScanStatus.idle();
  List<PluginListing> plugins = const <PluginListing>[];
  List<ProjectInstrument> instruments = const <ProjectInstrument>[];
  final Set<String> _dismissedQuarantinePaths = <String>{};
  HostedInstance? instance;
  List<HostedParameter> parameters = const <HostedParameter>[];
  bool showParameters = false;

  Iterable<PluginListing> get availablePlugins =>
      plugins.where((PluginListing plugin) => !plugin.isQuarantined);

  Iterable<PluginListing> get quarantinedPlugins => plugins.where(
    (PluginListing plugin) =>
        plugin.isQuarantined &&
        !_dismissedQuarantinePaths.contains(plugin.path),
  );

  // The list is copied out of the engine only when this moves, so an idle app
  // and a scanning app cost the same per frame.
  int _seenGeneration = -1;

  /// Reads the cache and publishes whatever was in it. Blocking by design.
  void load() {
    _client.loadPluginCache();
    _refresh(force: true);
    refreshInstance();
    refreshInstruments();
  }

  void add(PluginListing plugin) {
    _client.addPlugin(plugin);
    refreshInstance();
    refreshInstruments();
  }

  void removeInstance() {
    final HostedInstance? current = instance;
    if (current == null) return;
    _client.removePlugin(current.id);
    instance = null;
    parameters = const <HostedParameter>[];
    showParameters = false;
    refreshInstruments();
    notifyListeners();
  }

  void openParameters() {
    final HostedInstance? current = instance;
    if (current == null || current.missing) return;
    parameters = _client.readParameters(current);
    showParameters = true;
    notifyListeners();
  }

  void openEditor() {
    final HostedInstance? current = instance;
    if (current == null) return;
    _client.openPluginEditor(current.id);
  }

  void restartInstance() {
    final HostedInstance? current = instance;
    if (current == null || !current.needsRestart) return;
    _client.restartPlugin(current.id);
    refreshInstance();
  }

  void closeParameters() {
    showParameters = false;
    notifyListeners();
  }

  void setParameter(HostedParameter parameter, double value) {
    _client.setParameter(parameter.id, value);
    final int index = parameters.indexWhere(
      (HostedParameter item) => item.id == parameter.id,
    );
    if (index >= 0) {
      parameters = List<HostedParameter>.of(parameters)
        ..[index] = HostedParameter(
          id: parameter.id,
          name: parameter.name,
          module: parameter.module,
          display: value.toStringAsFixed(3),
          value: value,
          minimum: parameter.minimum,
          maximum: parameter.maximum,
          defaultValue: parameter.defaultValue,
        );
      notifyListeners();
    }
  }

  void beginParameterGesture(int paramId) =>
      _client.beginParameterGesture(paramId);
  void endParameterGesture(int paramId) => _client.endParameterGesture(paramId);

  void auditionNoteOn(int note) => _client.noteOn(note, 0.82);
  void auditionNoteOff(int note) => _client.noteOff(note);

  void refreshInstruments() {
    instruments = _client.readInstruments();
    notifyListeners();
  }

  void selectInstrument(ProjectInstrument instrument) {
    _client.selectInstrument(instrument.id);
    refreshInstance();
    refreshInstruments();
  }

  void renameInstrument(ProjectInstrument instrument, String name) {
    _client.renameInstrument(instrument.id, name);
    refreshInstruments();
  }

  void recolorInstrument(ProjectInstrument instrument, String color) {
    _client.recolorInstrument(instrument.id, color);
    refreshInstruments();
  }

  void toggleInstrumentMuted(ProjectInstrument instrument) {
    _client.setInstrumentMuted(instrument.id, muted: !instrument.muted);
    refreshInstruments();
  }

  void replaceSelectedInstrument(PluginListing plugin) {
    ProjectInstrument? selected;
    for (final ProjectInstrument instrument in instruments) {
      if (instrument.selected) selected = instrument;
    }
    if (selected == null) return;
    _client.replaceInstrument(selected.id, plugin);
    refreshInstance();
    refreshInstruments();
  }

  void moveInstrument(ProjectInstrument instrument, int order) {
    _client.reorderInstrument(instrument.id, order);
    refreshInstruments();
  }

  void duplicateInstrument(ProjectInstrument instrument) {
    _client.duplicateInstrument(instrument.id);
    refreshInstruments();
  }

  void deleteInstrument(ProjectInstrument instrument) {
    _client.deleteInstrument(instrument.id);
    refreshInstance();
    refreshInstruments();
  }

  bool get canUndo => _client.canUndoProject;
  bool get canRedo => _client.canRedoProject;

  void undo() {
    _client.undoProject();
    refreshInstance();
    refreshInstruments();
  }

  void redo() {
    _client.redoProject();
    refreshInstance();
    refreshInstruments();
  }

  void refreshInstance() {
    instance = _client.readHostedInstance();
    parameters =
        instance == null || instance!.missing
            ? const <HostedParameter>[]
            : _client.readParameters(instance!);
    notifyListeners();
  }

  bool startScan({List<String> directories = const <String>[]}) {
    final bool started = _client.startPluginScan(directories: directories);
    if (started) {
      _refresh(force: true);
    }
    return started;
  }

  void cancelScan() {
    _client.cancelPluginScan();
    _refresh(force: true);
  }

  bool retry(PluginListing plugin) {
    final bool started = _client.retryPluginScan(plugin.path);
    if (started) {
      _dismissedQuarantinePaths.remove(plugin.path);
      _refresh(force: true);
    }
    return started;
  }

  /// Acknowledges the warning for this app session. The engine cache remains
  /// quarantined, so the bundle is still skipped on the next scan and launch.
  void keepQuarantined(PluginListing plugin) {
    if (_dismissedQuarantinePaths.add(plugin.path)) {
      notifyListeners();
    }
  }

  /// Called once per frame while a scan is running. Cheap when nothing changed:
  /// one native call that returns a small struct, and no list copy.
  void pump() {
    _refresh();
    final HostedInstance? next = _client.readHostedInstance();
    if (next?.needsRestart != instance?.needsRestart) {
      instance = next;
      notifyListeners();
    }
  }

  void _refresh({bool force = false}) {
    final PluginScanStatus next = _client.readPluginScanStatus();
    final bool listChanged = force || next.listGeneration != _seenGeneration;
    if (listChanged) {
      _seenGeneration = next.listGeneration;
      plugins = _client.readPluginList(next.pluginCount);
    }
    final bool statusChanged =
        next.state != status.state ||
        next.bundlesProbed != status.bundlesProbed ||
        next.bundlesDiscovered != status.bundlesDiscovered ||
        next.current != status.current;
    status = next;
    if (listChanged || statusChanged) {
      notifyListeners();
    }
  }

  /// The progress line, in the shape FR-UX-12 asks for: what is happening, and
  /// what the user ends up with — never a bare percentage.
  String get summary {
    switch (status.state) {
      case ScanState.idle:
        return plugins.isEmpty
            ? 'No plug-ins scanned yet.'
            : '${plugins.length} plug-ins';
      case ScanState.discovering:
        return 'Looking for plug-ins…';
      case ScanState.probing:
        final int done = status.bundlesReused + status.bundlesProbed;
        return 'Scanning $done of ${status.bundlesDiscovered}…';
      case ScanState.complete:
        // Naming the reused count is not a vanity metric: it is how anyone
        // checks that the cache is doing its job (OB-2-02 AC 2).
        return '${plugins.length} plug-ins · '
            '${status.bundlesProbed} scanned, ${status.bundlesReused} from cache';
      case ScanState.cancelled:
        return 'Scan stopped. ${plugins.length} plug-ins from the last full scan.';
    }
  }
}
