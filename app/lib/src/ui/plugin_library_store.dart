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
  final Set<String> _dismissedQuarantinePaths = <String>{};

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
  void pump() => _refresh();

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
