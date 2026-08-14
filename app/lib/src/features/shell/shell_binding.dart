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
import 'menu_bar.dart';
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
  bool _showExportDialog = false;
  bool _showPreferencesDialog = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      stdout.writeln(
        'onebeat: shell usable in ${startupStopwatch.elapsedMilliseconds} ms',
      );
    });
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

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onRailSelect(int index) {
    if (index >= 0 && index < _railItems.length) {
      setState(() => _activeRailIndex = index);
    }
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
      searchHint: 'Action, shortcut, instrument, note…',
    );

    const ObMenuBarVm menuBarVm = ObMenuBarVm(
      menus: _menus,
      clock: '14:02',
    );

    final ObSideRailVm railVm = ObSideRailVm(
      items: _railItems,
      activeIndex: _activeRailIndex,
      separatorBefore: 4,
    );

    final double cpuPercent = (snapshot.cpuLoad * 100.0).clamp(0.0, 100.0);
    final double sampleRateKhz = snapshot.sampleRate / 1000.0;
    final double latencyMs =
        (snapshot.latencyFramesRoundTrip / snapshot.sampleRate) * 1000.0;

    final String leftDetail =
        'CoreAudio · ${sampleRateKhz.toStringAsFixed(1)} kHz · ${snapshot.blockFrames} spl · ${latencyMs.toStringAsFixed(1)} ms';

    final ObStatusBarVm statusVm = ObStatusBarVm(
      tone: snapshot.xrunCount > 0 ? StatusTone.warning : StatusTone.ok,
      primary: snapshot.playing ? 'Playing' : 'Ready',
      details: <String>[
        leftDetail,
        '${cpuPercent.toStringAsFixed(0)}% CPU',
        '${snapshot.activeVoices} voices',
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
                  coreController: _controller,
                  onSelectRail: _onRailSelect,
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
  });

  final int activeRailIndex;
  final core.EngineController coreController;
  final ValueChanged<int> onSelectRail;

  @override
  Widget build(BuildContext context) {
    return switch (activeRailIndex) {
      0 => PlaylistBinding(
          client: coreController.client,
          controller: coreController,
          onOpenPattern: (String patternId, String clipId) {
            onSelectRail(2);
          },
        ),
      1 => RackBinding(
          client: coreController.client,
          controller: coreController,
          onBrowsePlugins: () {},
          onOpenPianoRoll: (String instrumentId) {
            onSelectRail(2);
          },
        ),
      2 => PianoRollBinding(
          client: coreController.client,
          controller: coreController,
          onBackToPlaylist: () => onSelectRail(0),
        ),
      3 => MixerBinding(
          client: coreController.client,
          controller: coreController,
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
