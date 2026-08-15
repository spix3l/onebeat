// ShellBinding — wires the shell presentation to the core engine (UI-D-01..UI-D-08).
//
// Owns the mapping from the engine snapshot to the ShellScreenVm. Listens to
// the core EngineController, formats readouts, routes transport commands and
// handles workspace navigation.
import 'dart:async';
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
import '../browser/sample_pack.dart';
import '../browser/sample_pack_platform.dart';
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

/// The workspace index of the piano roll. It sits *past* the rail's items
/// (Channels, Playlist, Mixer) because the piano roll is opened from a channel
/// or a clip rather than from the rail, and the rail keeps highlighting
/// whichever view you came from. Library-level so the shell and the workspace
/// switch below cannot drift apart: when they did, opening the piano roll fell
/// through to the empty default and rendered a black screen.
const int _pianoRollIndex = 3;

class ShellBinding extends StatefulWidget {
  const ShellBinding({required this.client, this.controller, super.key});

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
  double _browserWidth = 240;
  String _browserSearchQuery = '';
  double _browserScrollOffset = 0;

  List<BrowserNodeVm> _browserNodes = const <BrowserNodeVm>[];
  List<SamplePack> _samplePacks = const <SamplePack>[];
  final SamplePackPlatform _samplePackPlatform = SamplePackPlatform();
  final Map<String, bool> _browserExpanded = <String, bool>{};
  String? _samplePackMessage;
  AudioFileDrop? _audioFileDrop;
  int _framesSinceBrowserRefresh = 0;
  int _builtinsGeneration = -1;
  List<PluginListing> _builtins = const <PluginListing>[];
  bool _demoSeeded = false;

  // The channel rack is the composition home; the arrangement is secondary.
  // Piano roll is not a rail destination — it is opened from the rack or
  // playlist and returns to wherever it was opened from (index 4, hidden).
  static const List<RailItemVm> _railItems = <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
  ];

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
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
    _samplePackPlatform.setDropHandler(
      onFolders: _onFoldersDropped,
      onAudioFiles: _onAudioFilesDropped,
    );
    unawaited(_restoreSamplePacks());
  }

  @override
  void dispose() {
    _samplePackPlatform.clearDropHandler();
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
    if (status.pluginCount > 0 &&
        status.listGeneration != _builtinsGeneration) {
      _builtinsGeneration = status.listGeneration;
      _builtins =
          _controller.client
              .readPluginList(status.pluginCount)
              .where((PluginListing p) => p.isUsable)
              .toList();
    }
    return _builtins;
  }

  Future<void> _restoreSamplePacks() async {
    final List<String> paths = await _samplePackPlatform.loadFolders();
    for (final String path in paths) {
      await _importSamplePack(path, persist: false);
    }
  }

  Future<void> _onAddFolder() async {
    final String? path = await _samplePackPlatform.pickFolder();
    if (path != null) await _importSamplePack(path);
  }

  void _onFoldersDropped(List<String> paths) {
    unawaited(() async {
      for (final String path in paths) {
        await _importSamplePack(path);
      }
    }());
  }

  void _onAudioFilesDropped(AudioFileDrop drop) {
    // Finder drops are routed to the active Playlist only. Dropping a file on
    // another workspace should not silently create an arrangement clip.
    if (_activeRailIndex != 1) return;
    setState(() => _audioFileDrop = drop);
  }

  Future<bool> _importSamplePack(String path, {bool persist = true}) async {
    final SamplePack? pack = await SamplePackScanner.scan(path);
    if (!mounted) return false;
    if (pack == null) {
      setState(
        () =>
            _samplePackMessage =
                'That folder has no supported audio files. Add a folder containing at least one WAV file.',
      );
      return false;
    }

    final List<SamplePack> next = <SamplePack>[
      ..._samplePacks.where((SamplePack item) => item.path != pack.path),
      pack,
    ];
    setState(() {
      _samplePacks = next;
      _samplePackMessage = null;
      // Packs are part of the shared instrument browser now, so refresh its
      // tree immediately instead of waiting for the controller heartbeat.
      _browserNodes = _buildBrowserNodes();
    });
    if (persist) {
      await _samplePackPlatform.saveFolders(
        _samplePacks.map((SamplePack item) => item.path),
      );
    }
    return true;
  }

  List<BrowserNodeVm> _buildPackNodes() {
    return <BrowserNodeVm>[
      for (int packIndex = 0; packIndex < _samplePacks.length; packIndex++)
        BrowserFolderVm(
          id: 'pack:${_samplePacks[packIndex].path}',
          name: _samplePacks[packIndex].name,
          count: _samplePacks[packIndex].assets.length,
          expanded:
              _browserExpanded['pack:${_samplePacks[packIndex].path}'] ?? true,
          children: <BrowserNodeVm>[
            for (
              int assetIndex = 0;
              assetIndex < _samplePacks[packIndex].assets.length;
              assetIndex++
            )
              BrowserSampleVm(
                id: _samplePacks[packIndex].assets[assetIndex].id,
                name: _samplePacks[packIndex].assets[assetIndex].name,
                color: _resolveColor('', assetIndex + packIndex),
                previewPath: _samplePacks[packIndex].assets[assetIndex].path,
                dragData: _samplePacks[packIndex].assets[assetIndex],
              ),
          ],
        ),
    ];
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
          expanded: _browserExpanded['pattern:${p.id}'] ?? false,
        ),
      );
    }
    if (project.isNotEmpty) {
      nodes.add(
        BrowserFolderVm(
          id: 'current-project',
          name: 'Current Project',
          count: project.length,
          expanded: _browserExpanded['current-project'] ?? true,
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

    final List<BrowserNodeVm> instrumentSources = <BrowserNodeVm>[];
    if (builtins.isNotEmpty) {
      instrumentSources.add(
        BrowserFolderVm(
          id: 'builtins',
          name: 'Built-ins',
          count: builtins.length,
          expanded: _browserExpanded['builtins'] ?? true,
          children: builtins,
        ),
      );
    }

    final List<BrowserNodeVm> packNodes = _buildPackNodes();
    if (packNodes.isNotEmpty) {
      instrumentSources.add(
        BrowserFolderVm(
          id: 'sample-packs',
          name: 'Sample Packs',
          count: packNodes.length,
          expanded: _browserExpanded['sample-packs'] ?? true,
          children: packNodes,
        ),
      );
    }

    if (instrumentSources.isNotEmpty) {
      // Plug-ins and samples are both things that can become rack
      // instruments. Their source categories stay visible without creating a
      // separate library destination in the rail.
      nodes.add(
        BrowserFolderVm(
          id: 'instruments',
          name: 'Instruments',
          expanded: _browserExpanded['instruments'] ?? true,
          children: instrumentSources,
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

  BrowserNodeVm? _findBrowserNode(String id, [List<BrowserNodeVm>? source]) {
    final List<BrowserNodeVm> roots = source ?? _browserNodes;
    for (final BrowserNodeVm node in roots) {
      if (node.id == id) return node;
      final BrowserNodeVm? child = _findBrowserNode(id, node.children);
      if (child != null) return child;
    }
    return null;
  }

  void _onBrowserToggle(String id) {
    final BrowserNodeVm? node = _findBrowserNode(id);
    if (node is BrowserFolderVm) {
      _browserExpanded[id] = !node.expanded;
    } else if (node is BrowserPatternVm) {
      _browserExpanded[id] = !node.expanded;
    } else {
      return;
    }
    _browserNodes = _buildBrowserNodes();
    if (mounted) setState(() {});
  }

  void _onBrowserSearchChanged(String query) {
    _browserSearchQuery = query;
  }

  void _onBrowserScrollChanged(double offset) {
    _browserScrollOffset = offset;
  }

  void _onBrowserResize(double delta) {
    setState(() {
      _browserWidth = (_browserWidth + delta).clamp(180.0, 420.0).toDouble();
    });
  }

  void _onBrowserTap(String id) {
    final BrowserNodeVm? node = _findBrowserNode(id);
    if (node is BrowserSampleVm && node.previewPath != null) {
      try {
        _controller.previewSample(node.previewPath!);
      } catch (_) {
        // A preview failure must not interrupt browser navigation or dragging.
      }
      return;
    }
    if (id.startsWith('pattern:')) {
      _controller.client.selectPattern(id.substring('pattern:'.length));
      setState(() {});
      _browserNodes = _buildBrowserNodes();
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
      activeIndex:
          _activeRailIndex == _pianoRollIndex
              ? _lastRailIndex
              : _activeRailIndex,
      separatorBefore: null,
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
      details:
          snapshot.playing
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
          snapshot.playing
              ? '⌘K Search actions'
              : '⌘N new pattern · ⌘K actions',
    );

    return ShellScreenVm(
      menuBar: null,
      transport: transportVm,
      rail: railVm,
      status: statusVm,
      browserWidth: _browserWidth,
      browser:
          (_activeRailIndex == 0 || _activeRailIndex == 1)
              ? ObBrowserPanelVm(
                nodes: _browserNodes,
                title: 'Browser',
                emptyHeading: 'No instruments yet.',
                emptyButtonLabel: 'Add packs',
                searchQuery: _browserSearchQuery,
                scrollOffset: _browserScrollOffset,
                message: _samplePackMessage,
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
                  externalAudioDrop: _audioFileDrop,
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
                onBrowserToggle: _onBrowserToggle,
                onBrowserSearchChanged: _onBrowserSearchChanged,
                onBrowserScrollChanged: _onBrowserScrollChanged,
                onBrowserResize: _onBrowserResize,
                onBrowserAddFolder: _onAddFolder,
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
    this.externalAudioDrop,
  });

  final int activeRailIndex;
  final core.EngineController coreController;
  final ValueChanged<int> onSelectRail;
  final ValueChanged<String> onOpenPianoRoll;
  final VoidCallback onOpenPattern;
  final VoidCallback onClosePianoRoll;
  final AudioFileDrop? externalAudioDrop;

  @override
  Widget build(BuildContext context) {
    return switch (activeRailIndex) {
      0 => RackBinding(
        client: coreController.client,
        controller: coreController,
        onBrowsePlugins: () => onSelectRail(0),
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
        externalAudioDrop: externalAudioDrop,
      ),
      2 => MixerBinding(
        client: coreController.client,
        controller: coreController,
      ),
      _pianoRollIndex => PianoRollBinding(
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
              label:
                  controller.client.canUndoProject &&
                          controller.client.undoProjectName.isNotEmpty
                      ? 'Undo ${controller.client.undoProjectName}'
                      : 'Undo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected:
                  controller.client.canUndoProject
                      ? controller.undoProject
                      : null,
            ),
            PlatformMenuItem(
              label:
                  controller.client.canRedoProject &&
                          controller.client.redoProjectName.isNotEmpty
                      ? 'Redo ${controller.client.redoProjectName}'
                      : 'Redo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected:
                  controller.client.canRedoProject
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
