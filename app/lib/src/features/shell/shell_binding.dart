// ShellBinding — wires the shell presentation to the core engine (UI-D-01).
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
import 'menu_bar.dart';
import 'rail_glyphs.dart';
import 'shell_screen.dart';
import 'shell_screen_vm.dart';
import 'side_rail.dart';
import 'status_bar.dart';
import 'transport_bar.dart';

// TODO(UI-D-09): Temporary imports for un-migrated workspace surfaces.
import '../../ui/arrangement.dart' as old_ui;
import '../../ui/channel_rack.dart' as old_ui;
import '../../ui/engine_controller.dart' as old_ui;
import '../../ui/export_dialog.dart' as old_ui;
import '../../ui/mixer_view.dart' as old_ui;
import '../../ui/piano_roll.dart' as old_ui;
import '../../ui/preferences_dialog.dart' as old_ui;

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
  bool _showExportDialog = false;
  bool _showPreferencesDialog = false;

  // TODO(UI-D-09): Bridge controller for temporary old workspace surfaces.
  old_ui.EngineController? _oldUiController;

  static const List<RailItemVm> _railItems = <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.note, label: 'Piano'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
    RailItemVm(icon: ObRailGlyphKind.folder, label: 'Packs'),
  ];

  static const List<String> _menus = <String>[
    'File',
    'Edit',
    'Pattern',
    'View',
    'Tools ▾',
    'Mixer',
    'Window',
    'Help',
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

    // TODO(UI-D-09): Initialize temporary old store bridge for embedded surfaces.
    _initOldUiBridge();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      stdout.writeln(
        'onebeat: shell usable in ${startupStopwatch.elapsedMilliseconds} ms',
      );
    });
  }

  void _initOldUiBridge() {
    // TODO(UI-D-09): Remove when feature stores migrate in UI-D-02..D-05.
    try {
      final old_ui.EngineController bridge = old_ui.EngineController(
        client: widget.client,
        vsync: this,
        motion: OneBeatTokens.dark().motion,
      );
      _oldUiController = bridge;
      bridge.library.load();
      bridge.rack.load();
      bridge.patterns.load();
      bridge.arrangement.load();
    } catch (_) {
      // If store loads fail on test fakes, bridge is kept so it gets disposed.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.frameStats.syncToDisplay(View.of(context));
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _oldUiController?.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatPosition(EngineSnapshot snapshot) {
    final int bar = snapshot.bar;
    final int beat = snapshot.beat;
    final int tick = snapshot.tick;
    return '${bar.toString().padLeft(2, '0')}:'
        '${beat.toString().padLeft(2, '0')}:'
        '${tick.toString().padLeft(3, '0')}';
  }

  String _formatBpm(EngineSnapshot snapshot) {
    return snapshot.tempoBpm.toStringAsFixed(2);
  }

  String _formatClock() {
    final DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _onRailSelect(int index) {
    setState(() {
      _activeRailIndex = index;
      if (_oldUiController != null) {
        _oldUiController!.setView(switch (index) {
          0 => old_ui.WorkspaceView.arrangement,
          1 => old_ui.WorkspaceView.rack,
          2 => old_ui.WorkspaceView.pianoRoll,
          3 => old_ui.WorkspaceView.mixer,
          _ => old_ui.WorkspaceView.arrangement,
        });
      }
    });
  }

  void _onMenuTap(int index) {
    switch (index) {
      case 0: // File
        break;
      case 1: // Edit
        break;
      case 2: // Pattern
        _onRailSelect(1);
      case 3: // View
        break;
      case 4: // Tools
        break;
      case 5: // Mixer
        _onRailSelect(3);
      case 6: // Window
        break;
      case 7: // Help
        break;
    }
  }

  ShellScreenVm _buildVm() {
    final EngineSnapshot snapshot = _controller.snapshot;
    final double leftLevel = dbToFraction(_controller.meter.left.levelDb);
    final double rightLevel = dbToFraction(_controller.meter.right.levelDb);

    final ObMenuBarVm menuBarVm = ObMenuBarVm(
      menus: _menus,
      clock: _formatClock(),
      activeIndex: null,
    );

    final ObTransportBarVm transportVm = ObTransportBarVm(
      title: 'ONEBEAT',
      subtitle: 'v0.3 SEQUENCES',
      playing: snapshot.playing,
      looping: snapshot.loopEnabled,
      bpmText: _formatBpm(snapshot),
      sigText: '4/4',
      positionText: _formatPosition(snapshot),
      meterLeft: leftLevel.clamp(0.0, 1.0),
      meterRight: rightLevel.clamp(0.0, 1.0),
      searchHint: 'Search actions',
    );

    final ObSideRailVm railVm = ObSideRailVm(
      items: _railItems,
      activeIndex: _activeRailIndex,
      separatorBefore: 4,
    );

    final ObStatusBarVm statusVm = ObStatusBarVm(
      tone: _controller.status.isNotEmpty
          ? StatusTone.warning
          : (snapshot.playing ? StatusTone.ok : StatusTone.ok),
      primary: _controller.status.isNotEmpty
          ? 'Notice'
          : (snapshot.playing ? 'Playing' : 'Ready'),
      details: <String>[
        if (_controller.status.isNotEmpty)
          _controller.status
        else ...<String>[
          'Buffer ${snapshot.blockFrames}',
          '${snapshot.latencyMilliseconds.toStringAsFixed(1)} ms',
        ],
      ],
      rightHint: '⌘K Search actions',
    );

    return ShellScreenVm(
      menuBar: menuBarVm,
      transport: transportVm,
      rail: railVm,
      status: statusVm,
      browser: _activeRailIndex == 4
          ? const ObBrowserPanelVm(
              nodes: <BrowserNodeVm>[],
              title: 'Packs',
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
                1 => 0, // Playlist
                2 => 1, // Channels
                3 => 2, // Piano roll
                4 => 3, // Mixer
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
                  oldUiController: _oldUiController,
                  coreController: _controller,
                ),
                onRailSelect: _onRailSelect,
                onMenuTap: _onMenuTap,
                onTogglePlay: _controller.togglePlay,
                onStop: _controller.stop,
                onToggleLoop: _controller.toggleLoop,
                onUndo: _controller.undoProject,
                onRedo: _controller.redoProject,
                onExport: () => setState(() => _showExportDialog = true),
              ),
              if (_showExportDialog)
                old_ui.ExportAudioDialog(
                  onClose: () => setState(() => _showExportDialog = false),
                ),
              if (_showPreferencesDialog)
                old_ui.PreferencesDialog(
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
    required this.oldUiController,
    required this.coreController,
  });

  final int activeRailIndex;
  final old_ui.EngineController? oldUiController;
  final core.EngineController coreController;

  @override
  Widget build(BuildContext context) {
    final old_ui.EngineController? bridge = oldUiController;
    if (bridge == null) {
      return const SizedBox.expand();
    }

    // TODO(UI-D-09): Replaced as Phase D wiring lands for each surface (UI-D-02..D-05).
    return switch (activeRailIndex) {
      0 => old_ui.ArrangementView(
          controller: bridge,
          store: bridge.arrangement,
          patterns: bridge.patterns,
          onOpenPattern: (String patternId, String clipId) =>
              bridge.openPattern(patternId, fromClipId: clipId),
        ),
      1 => old_ui.ChannelRack(
          controller: bridge,
          onBrowsePlugins: () {},
        ),
      2 => old_ui.PianoRoll(
          controller: bridge,
          store: bridge.pianoRoll,
          patterns: bridge.patterns,
        ),
      3 => old_ui.MixerRoutingView(controller: bridge),
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
                  label: 'Playlist',
                  onSelected: () => onSelectRail(0),
                ),
                PlatformMenuItem(
                  label: 'Channels',
                  onSelected: () => onSelectRail(1),
                ),
                PlatformMenuItem(
                  label: 'Piano roll',
                  onSelected: () => onSelectRail(2),
                ),
                PlatformMenuItem(
                  label: 'Mixer',
                  onSelected: () => onSelectRail(3),
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
