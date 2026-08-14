// PreferencesBinding — manages preferences state and engine device configuration (UI-D-07).
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../engine/engine_client.dart';
import 'preferences_dialog.dart';
import 'preferences_vm.dart';

class PreferencesBinding extends StatefulWidget {
  const PreferencesBinding({
    required this.client,
    required this.onClose,
    this.controller,
    this.initialTab = 0,
    super.key,
  });

  final EngineClient client;
  final VoidCallback onClose;
  final core.EngineController? controller;
  final int initialTab;

  @override
  State<PreferencesBinding> createState() => _PreferencesBindingState();
}

class _PreferencesBindingState extends State<PreferencesBinding> {
  late int _activeTab;
  int _selectedBuffer = 128;
  bool _isScanning = false;
  final List<PrefFolderVm> _folders = <PrefFolderVm>[
    const PrefFolderVm(
      path: '~/Music/OneBeat/Samples',
      detail: 'Default factory sample library · 482 files',
      removable: false,
    ),
    const PrefFolderVm(
      path: '~/Library/Audio/Plug-Ins/CLAP',
      detail: 'System CLAP plugins directory · 12 plugins discovered',
      removable: true,
    ),
    const PrefFolderVm(
      path: '~/Library/Audio/Plug-Ins/VST3',
      detail: 'System VST3 plugins directory · 28 plugins discovered',
      removable: true,
    ),
  ];

  static const List<PrefShortcutVm> _defaultShortcuts = <PrefShortcutVm>[
    PrefShortcutVm(label: 'Play / Stop', shortcut: 'Space'),
    PrefShortcutVm(label: 'Record', shortcut: 'R'),
    PrefShortcutVm(label: 'Duplicate Selection', shortcut: '⌘D'),
    PrefShortcutVm(label: 'Delete Selection', shortcut: 'Delete / Backspace'),
    PrefShortcutVm(label: 'Select All', shortcut: '⌘A'),
    PrefShortcutVm(label: 'Quantise Notes', shortcut: 'Q'),
    PrefShortcutVm(label: 'Toggle Metronome', shortcut: 'C'),
    PrefShortcutVm(label: 'Undo', shortcut: '⌘Z'),
    PrefShortcutVm(label: 'Redo', shortcut: '⇧⌘Z'),
    PrefShortcutVm(label: 'Open Piano Roll', shortcut: 'Enter / Return'),
    PrefShortcutVm(label: 'Close / Cancel', shortcut: 'Escape'),
  ];

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    final EngineSnapshot snapshot = widget.client.readSnapshot();
    if (snapshot.blockFrames > 0) {
      _selectedBuffer = snapshot.blockFrames;
    }
  }

  void _onBufferChanged(int buffer) {
    setState(() => _selectedBuffer = buffer);
  }

  void _onAddFolder() {
    setState(() {
      _folders.add(
        PrefFolderVm(
          path: '~/Music/OneBeat/Custom Library ${_folders.length + 1}',
          detail: 'User sample library · 0 files',
          removable: true,
        ),
      );
    });
  }

  void _onRemoveFolder(String path) {
    setState(() {
      _folders.removeWhere((PrefFolderVm f) => f.path == path);
    });
  }

  void _onRescanPlugins() {
    setState(() => _isScanning = true);
    Future<void>.delayed(const Duration(milliseconds: 600), () { // token-lint-ok: simulated scan delay
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final EngineSnapshot snapshot = widget.client.readSnapshot();
    final double sampleRateKhz = snapshot.sampleRate / 1000.0;
    final double latencyMs = (_selectedBuffer * 2 / snapshot.sampleRate) * 1000.0;

    final PreferencesVm vm = PreferencesVm(
      activeTab: _activeTab,
      isScanning: _isScanning,
      audio: AudioPrefsVm(
        deviceName: 'MacBook Pro Built-in Output (CoreAudio)',
        selectedBuffer: _selectedBuffer,
        sampleRateText: '${sampleRateKhz.toStringAsFixed(1)} kHz',
        latencyText:
            '${latencyMs.toStringAsFixed(1)} ms roundtrip latency · $_selectedBuffer samples @ ${sampleRateKhz.toStringAsFixed(1)} kHz · ${snapshot.xrunCount} dropouts',
      ),
      folders: _folders,
      shortcuts: _defaultShortcuts,
    );

    return PreferencesDialog(
      vm: vm,
      onClose: widget.onClose,
      onTabChanged: (int tab) => setState(() => _activeTab = tab),
      onBufferChanged: _onBufferChanged,
      onAddFolder: _onAddFolder,
      onRemoveFolder: _onRemoveFolder,
      onRescanPlugins: _onRescanPlugins,
    );
  }
}
