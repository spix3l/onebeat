// Preferences view models (UI-C-08 / UI-D-07).
import 'package:flutter/foundation.dart';

@immutable
class PrefFolderVm {
  const PrefFolderVm({
    required this.path,
    required this.detail,
    this.removable = true,
  });

  final String path;
  final String detail;
  final bool removable;
}

@immutable
class PrefShortcutVm {
  const PrefShortcutVm({
    required this.label,
    required this.shortcut,
  });

  final String label;
  final String shortcut;
}

@immutable
class AudioPrefsVm {
  const AudioPrefsVm({
    required this.deviceName,
    required this.selectedBuffer,
    required this.sampleRateText,
    required this.latencyText,
    this.bufferOptions = const <int>[64, 128, 256, 512, 1024, 2048],
  });

  final String deviceName;
  final int selectedBuffer;
  final String sampleRateText;
  final String latencyText;
  final List<int> bufferOptions;
}

@immutable
class PreferencesVm {
  const PreferencesVm({
    required this.activeTab,
    required this.audio,
    required this.folders,
    required this.shortcuts,
    this.isScanning = false,
  });

  final int activeTab; // 0 = Audio, 1 = Sound & Plugins, 2 = Keys & Shortcuts
  final AudioPrefsVm audio;
  final List<PrefFolderVm> folders;
  final List<PrefShortcutVm> shortcuts;
  final bool isScanning;
}
