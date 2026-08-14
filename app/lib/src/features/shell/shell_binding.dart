// ShellBinding — wires the shell presentation to the core engine (UI-D-01..UI-D-08).
//
// Owns the mapping from the engine snapshot to the ShellScreenVm. Listens to
// the core EngineController, formats readouts, routes transport commands and
// handles workspace navigation.
import 'dart:io' show stdout;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../main.dart' show startupStopwatch;
import '../../core/engine_controller.dart' as core;
import '../../core/meter_state.dart';
import '../../core/shortcuts.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../browser/browser_panel.dart';
import '../channel_rack/rack_binding.dart';
import '../export/export_binding.dart';
import '../mixer/mixer_binding.dart';
import '../piano_roll/piano_roll_binding.dart';
import '../playlist/playlist_binding.dart';
import '../preferences/preferences_binding.dart';
import 'rail_glyphs.dart';
import 'shell_screen.dart';
import 'shell_screen_vm.dart';
import 'side_rail.dart';
import 'status_bar.dart';
import 'transport_bar.dart';

class ShellBinding extends StatefulWidget {
  const ShellBinding({
    required this.client,
    this.controller,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;

  @override
  State<ShellBinding> createState() => _ShellBindingState();
}

class _ShellBindingState extends State<ShellBinding>
    with TickerProviderStateMixin {
  late final core.EngineController _controller;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'shell');

  int _activeRailIndex = 0;
  int _lastRailIndex = 0;
  bool _showExportDialog = false;
  bool _showPreferencesDialog = false;

  List<BrowserNodeVm> _browserNodes = const <BrowserNodeVm>[];
  int _framesSinceBrowserRefresh = 0;
  int _builtinsGeneration = -1;
  List<PluginListing> _builtins = const <PluginListing>[];
  bool _demoSeeded = false;

  // The channel rack is the composition home; the arrangement is secondary.
  // Piano roll is not a rail destination — it is opened from the rack or
  // playlist and returns to wherever it was opened from (index 4, hidden).
  static const int _pianoRollIndex = 4;

  static const List<RailItemVm> _railItems = <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
    RailItemVm(icon: ObRailGlyphKind.folder, label: 'Packs'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        core.EngineController(
          client: widget.client,
          vsync: this,
          motion: OneBeatTokens.dark().motion,
        );
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      stdout.writeln(
        'onebeat: shell usable in ${startupStopwatch.elapsedMilliseconds} ms',
      );
    });

    _browserNodes = _buildBrowserNodes();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _rootFocus.dispose();
    super.dispose();
  }

  /// Adds one default channel (the bundled stock instrument) to an empty
  /// project, so the rack never opens blank (FR-UX-14). It does not seed notes
  /// or start playback — the project opens silent and ready.
  void _maybeSeedDemo() {
    if (_demoSeeded) return;
    final EngineClient client = _controller.client;
    if (client.readInstruments().isNotEmpty) {
      _demoSeeded = true;
      return;
    }
    final PluginScanStatus status = client.readPluginScanStatus();
    if (status.isScanning || status.pluginCount <= 0) return;
    _demoSeeded = true;

    final PluginListing? piano = client.firstUsablePlugin();
    if (piano == null) return;
    try {
      client.addPluginByPath(piano.path, piano.id);
    } catch (_) {
      // Hosting failed (missing helper, incompatible plug-in). Leave the rack
      // empty rather than crashing the shell.
    }
    _browserNodes = _buildBrowserNodes();
  }

  List<PluginListing> _readBuiltins() {
    final PluginScanStatus status = _controller.client.readPluginScanStatus();
    if (status.pluginCount > 0 && status.listGeneration != _builtinsGeneration) {
      _builtinsGeneration = status.listGeneration;
      _builtins = _controller.client
          .readPluginList(status.pluginCount)
          .where((PluginListing p) => p.isUsable)
          .toList();
    }
    return _builtins;
  }

  List<BrowserNodeVm> _buildBrowserNodes() {
    final EngineClient client = _controller.client;
    final List<BrowserNodeVm> nodes = <BrowserNodeVm>[];

    final List<BrowserNodeVm> project = <BrowserNodeVm>[];
    for (final PatternSummary p in client.readPatterns()) {
      project.add(
        BrowserPatternVm(
          id: 'pattern:${p.id}',
          name: p.name,
          color: _resolveColor(p.color, 0),
          badge: p.usageCount > 0 ? '${p.usageCount}×' : 'piano roll',
          expanded: false,
        ),
      );
    }
    if (project.isNotEmpty) {
      nodes.add(
        BrowserFolderVm(
          id: 'current-project',
          name: 'Current Project',
          count: project.length,
          expanded: true,
          children: project,
        ),
      );
    }

    final List<PluginListing> builtinPlugins = _readBuiltins();
    final List<BrowserNodeVm> builtins = <BrowserNodeVm>[
      for (int i = 0; i < builtinPlugins.length; i++)
        BrowserSampleVm(
          id: 'plugin:${builtinPlugins[i].path}',
          name: builtinPlugins[i].name,
          color: _resolveColor('', i),
          dragData: builtinPlugins[i],
        ),
    ];
    if (builtins.isNotEmpty) {
      nodes.add(
        BrowserFolderVm(
          id: 'builtins',
          name: 'Built-ins',
          count: builtins.length,
          expanded: true,
          children: builtins,
        ),
      );
    }

    return nodes;
  }

  Color _resolveColor(String? hex, int fallbackIndex) {
    if (hex != null && hex.isNotEmpty) {
      final int? parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
      if (parsed != null && parsed != 0) {
        return Color(0xFF000000 | parsed);
      }
    }
    return channelColors[fallbackIndex % channelColors.length];
  }

  void _onBrowserTap(String id) {
    if (id.startsWith('pattern:')) {
      _controller.client.selectPattern(id.substring('pattern:'.length));
      setState(() {});
      _browserNodes = _buildBrowserNodes();
    } else if (id.startsWith('plugin:')) {
      final String path = id.substring('plugin:'.length);
      for (final PluginListing p in _readBuiltins()) {
        if (p.path == path) {
          _controller.client.addPluginByPath(p.path, p.id);
          setState(() {});
          _browserNodes = _buildBrowserNodes();
          return;
        }
      }
    }
  }

  void _onControllerChanged() {
    _maybeSeedDemo();
    if (++_framesSinceBrowserRefresh >= 20) {
      _framesSinceBrowserRefresh = 0;
      _browserNodes = _buildBrowserNodes();
    }
    if (mounted) setState(() {});
  }

  void _onRailSelect(int index) {
    if (index >= 0 && index < _railItems.length) {
      _lastRailIndex = index;
      setState(() => _activeRailIndex = index);
      _browserNodes = _buildBrowserNodes();
    }
  }

  /// Opens the piano roll for [instrumentId] (or the selected instrument when
  /// omitted), remembering where to return to.
  void _openPianoRoll([String? instrumentId]) {
    if (instrumentId != null && instrumentId.isNotEmpty) {
      _controller.client.selectInstrument(instrumentId);
    }
    setState(() => _activeRailIndex = _pianoRollIndex);
  }

  void _closePianoRoll() {
    setState(() => _activeRailIndex = _lastRailIndex);
  }

  void _onMenuTap(int index) {
    switch (index) {
      case 0: // File
        setState(() => _showExportDialog = true);
        break;
      case 4: // Tools
      case 6: // Window
        setState(() => _showPreferencesDialog = true);
        break;
    }
  }

  ShellScreenVm _buildVm() {
    final EngineSnapshot snapshot = _controller.snapshot;

    final String bpmText = snapshot.tempoBpm.toStringAsFixed(2);
    const String sigText = '4/4';

    final int bar = snapshot.bar.clamp(1, 9999);
    final int beat = snapshot.beat.clamp(1, 4);
    final int tick = snapshot.tick.clamp(0, 959);
    final String positionText =
        '${bar.toString().padLeft(2, '0')}:${beat.toString().padLeft(2, '0')}:${tick.toString().padLeft(3, '0')}';

    final double meterLeft = dbToFraction(_controller.meter.left.levelDb);
    final double meterRight = dbToFraction(_controller.meter.right.levelDb);

    final ObTransportBarVm transportVm = ObTransportBarVm(
      title: 'ONEBEAT',
      subtitle: 'v0.3 SEQUENCES',
      playing: snapshot.playing,
      looping: snapshot.loopEnabled,
      bpmText: bpmText,
      sigText: sigText,
      positionText: positionText,
      meterLeft: meterLeft,
      meterRight: meterRight,
      searchHint: 'Search actions',
    );

    final ObSideRailVm railVm = ObSideRailVm(
      items: _railItems,
      activeIndex: _activeRailIndex == _pianoRollIndex
          ? _lastRailIndex
          : _activeRailIndex,
      separatorBefore: 3,
    );

    final double cpuPercent = (snapshot.cpuLoad * 100.0).clamp(0.0, 100.0);
    final double sampleRateKhz = snapshot.sampleRate / 1000.0;
    final double latencyMs =
        (snapshot.latencyFramesRoundTrip / snapshot.sampleRate) * 1000.0;

    final String leftDetail =
        'CoreAudio · ${sampleRateKhz.toStringAsFixed(1)} kHz · ${snapshot.blockFrames} spl · ${latencyMs.toStringAsFixed(1)} ms';

    final ObStatusBarVm statusVm = ObStatusBarVm(
      tone: snapshot.xrunCount > 0 ? StatusTone.warning : StatusTone.ok,
      primary: snapshot.playing ? 'Playing' : 'New project',
      details: snapshot.playing
          ? <String>[
              leftDetail,
              '${cpuPercent.toStringAsFixed(0)}% CPU',
              '${snapshot.activeVoices} voices',
            ]
          : const <String>[
              'Untitled.onebeat',
              'Nothing saved yet — autosave starts on first edit',
            ],
      rightHint:
          snapshot.playing ? '⌘K Search actions' : '⌘N new pattern · ⌘K actions',
    );

    return ShellScreenVm(
      menuBar: null,
      transport: transportVm,
      rail: railVm,
      status: statusVm,
      browser: (_activeRailIndex == 0 ||
              _activeRailIndex == 1 ||
              _activeRailIndex == 3)
          ? ObBrowserPanelVm(
              nodes: _activeRailIndex == 3
                  ? const <BrowserNodeVm>[]
                  : _browserNodes,
              title: _activeRailIndex == 3 ? 'Packs' : 'Browser',
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ShellScreenVm vm = _buildVm();

    return _PlatformMenuHost(
      controller: _controller,
      onOpenExport: () => setState(() => _showExportDialog = true),
      onOpenPreferences: () => setState(() => _showPreferencesDialog = true),
      onSelectRail: _onRailSelect,
      child: ScopedShortcuts(
        shortcuts: shortcutsForScope(ShortcutScope.global),
        handlers: const <String, VoidCallback>{},
        extraActions: <Type, Action<Intent>>{
          TogglePlayIntent: CallbackAction<TogglePlayIntent>(
            onInvoke: (_) {
              _controller.togglePlay();
              return null;
            },
          ),
          TogglePauseIntent: CallbackAction<TogglePauseIntent>(
            onInvoke: (_) {
              _controller.togglePause();
              return null;
            },
          ),
          ReturnToZeroIntent: CallbackAction<ReturnToZeroIntent>(
            onInvoke: (_) {
              _controller.seekFrames(0);
              return null;
            },
          ),
          UndoIntent: CallbackAction<UndoIntent>(
            onInvoke: (_) {
              _controller.undoProject();
              return null;
            },
          ),
          RedoIntent: CallbackAction<RedoIntent>(
            onInvoke: (_) {
              _controller.redoProject();
              return null;
            },
          ),
          ShowViewIntent: CallbackAction<ShowViewIntent>(
            onInvoke: (ShowViewIntent intent) {
              _onRailSelect(switch (intent.index) {
                1 => 0, // Channels
                2 => 1, // Playlist
                3 => 2, // Mixer
                _ => 0,
              });
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          child: Stack(
            children: <Widget>[
              ShellScreen(
                vm: vm,
                workspace: _WorkspaceSlot(
                  activeRailIndex: _activeRailIndex,
                  coreController: _controller,
                  onSelectRail: _onRailSelect,
                  onOpenPianoRoll: _openPianoRoll,
                  onOpenPattern: () => _openPianoRoll(),
                  onClosePianoRoll: _closePianoRoll,
                ),
                onRailSelect: _onRailSelect,
                onMenuTap: _onMenuTap,
                onTogglePlay: _controller.togglePlay,
                onStop: _controller.stop,
                onToggleLoop: _controller.toggleLoop,
                onUndo: _controller.undoProject,
                onRedo: _controller.redoProject,
                onExport: () => setState(() => _showExportDialog = true),
                onBrowserTap: _onBrowserTap,
              ),
              if (_showExportDialog)
                ExportBinding(
                  client: widget.client,
                  controller: _controller,
                  onClose: () => setState(() => _showExportDialog = false),
                ),
              if (_showPreferencesDialog)
                PreferencesBinding(
                  client: widget.client,
                  controller: _controller,
                  onClose: () => setState(() => _showPreferencesDialog = false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Workspace view switcher complying with "Always use widgets to build UI and never methods".
class _WorkspaceSlot extends StatelessWidget {
  const _WorkspaceSlot({
    required this.activeRailIndex,
    required this.coreController,
    required this.onSelectRail,
    required this.onOpenPianoRoll,
    required this.onOpenPattern,
    required this.onClosePianoRoll,
  });

  final int activeRailIndex;
  final core.EngineController coreController;
  final ValueChanged<int> onSelectRail;
  final ValueChanged<String> onOpenPianoRoll;
  final VoidCallback onOpenPattern;
  final VoidCallback onClosePianoRoll;

  @override
  Widget build(BuildContext context) {
    return switch (activeRailIndex) {
      0 => RackBinding(
          client: coreController.client,
          controller: coreController,
          onBrowsePlugins: () => onSelectRail(3),
          onOpenMixer: () => onSelectRail(2),
          onOpenPianoRoll: onOpenPianoRoll,
        ),
      1 => PlaylistBinding(
          client: coreController.client,
          controller: coreController,
          onOpenPattern: (String patternId, String clipId) {
            coreController.client.selectPattern(patternId);
            onOpenPattern();
          },
        ),
      2 => MixerBinding(
          client: coreController.client,
          controller: coreController,
        ),
      4 => PianoRollBinding(
          client: coreController.client,
          controller: coreController,
          onBackToPlaylist: onClosePianoRoll,
        ),
      _ => const SizedBox.expand(),
    };
  }
}

/// Native macOS menu bar integration.
class _PlatformMenuHost extends StatelessWidget {
  const _PlatformMenuHost({
    required this.controller,
    required this.onOpenExport,
    required this.onOpenPreferences,
    required this.onSelectRail,
    required this.child,
  });

  final core.EngineController controller;
  final VoidCallback onOpenExport;
  final VoidCallback onOpenPreferences;
  final ValueChanged<int> onSelectRail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: 'OneBeat',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Settings…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: onOpenPreferences,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Export audio…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyE,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: onOpenExport,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: controller.client.canUndoProject &&
                      controller.client.undoProjectName.isNotEmpty
                  ? 'Undo ${controller.client.undoProjectName}'
                  : 'Undo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: controller.client.canUndoProject
                  ? controller.undoProject
                  : null,
            ),
            PlatformMenuItem(
              label: controller.client.canRedoProject &&
                      controller.client.redoProjectName.isNotEmpty
                  ? 'Redo ${controller.client.redoProjectName}'
                  : 'Redo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: controller.client.canRedoProject
                  ? controller.redoProject
                  : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Channels',
                  onSelected: () => onSelectRail(0),
                ),
                PlatformMenuItem(
                  label: 'Playlist',
                  onSelected: () => onSelectRail(1),
                ),
                PlatformMenuItem(
                  label: 'Mixer',
                  onSelected: () => onSelectRail(2),
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
