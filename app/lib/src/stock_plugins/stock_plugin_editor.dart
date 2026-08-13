import 'package:flutter/widgets.dart';

import '../engine/engine_client.dart';
import '../ui/plugin_library_store.dart';
import 'piano/onebeat_piano_editor.dart';

/// Routes stock plug-ins to their app-owned docked editor.
///
/// Third-party plug-ins continue through the generic parameter/native-editor
/// path. Keeping this registry beside the stock editors prevents the plug-in
/// manager from accumulating instrument-specific UI code.
Widget? buildStockPluginEditor({
  required HostedInstance instance,
  required PluginLibraryStore library,
}) {
  return switch (instance.pluginId) {
    'dev.onebeat.stock.piano' => OneBeatPianoEditor(library: library),
    _ => null,
  };
}
