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
import '../playlist/playlist_store.dart';
import '../plugins/plugin_binding.dart';
import '../preferences/preferences_binding.dart';
import '../project/project_store.dart';
import '../project/rename_project_dialog.dart';
import '../project/unsaved_project_dialog.dart';
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
const String _samplePluginId = 'onebeat.sample';

class ShellBinding extends StatefulWidget {
  const ShellBinding({required this.client, this.controller, super.key});

  final EngineClient client;
  final core.EngineController? controller;

  @override
  State<ShellBinding> createState() => _ShellBindingState();
}

class _ShellBindingState extends State<ShellBinding> with TickerProviderStateMixin {
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
  PlaylistInsertItem? _lastPlaylistItem;
  int _framesSinceBrowserRefresh = 0;
  int _framesSinceProjectRefresh = 0;
  bool _showRenameDialog = false;
  bool _showNewProjectDialog = false;
  late final ProjectStore _project;
  int _builtinsGeneration = -1;
  List<PluginListing> _builtins = const <PluginListing>[];
  HostedInstance? _openPlugin;
  List<HostedParameter> _openPluginParameters = const <HostedParameter>[];
  String? _openPluginTrackId;
  Offset _pluginOffset = const Offset(140, 70);

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
        core.EngineController(client: widget.client, vsync: this, motion: OneBeatTokens.dark().motion);
    _controller.addListener(_onControllerChanged);
    // The controller's client, not the widget's: when a test supplies its own
    // controller those can differ, and the project must be the one the rest of
    // the shell is reading.
    _project = ProjectStore(_controller.client)..addListener(_onProjectChanged);
    // The shell's root node is the default home for focus: a text field that
    // finishes editing returns the keyboard here when no editor has claimed it.
    FocusPolicy.registerShell(_rootFocus);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      stdout.writeln('onebeat: shell usable in ${startupStopwatch.elapsedMilliseconds} ms');
    });

    _browserNodes = _buildBrowserNodes();
    _samplePackPlatform.setDropHandler(onFolders: _onFoldersDropped, onAudioFiles: _onAudioFilesDropped);
    unawaited(_restoreBrowserExpansion());
    unawaited(_restoreSamplePacks());
  }

  @override
  void dispose() {
    _samplePackPlatform.clearDropHandler();
    _project.removeListener(_onProjectChanged);
    _project.dispose();
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _rootFocus.dispose();
    super.dispose();
  }

  List<PluginListing> _readBuiltins() {
    final PluginScanStatus status = _controller.client.readPluginScanStatus();
    if (status.pluginCount > 0 && status.listGeneration != _builtinsGeneration) {
      _builtinsGeneration = status.listGeneration;
      _builtins = _controller.client.readPluginList(status.pluginCount).where((PluginListing p) => p.isUsable).toList();
    }
    return _builtins;
  }

  /// A folder the user opened stays open across restarts. Only the rows they
  /// touched are restored, so a section added in a later build still appears
  /// the way it was designed to.
  Future<void> _restoreBrowserExpansion() async {
    final Map<String, bool> stored = await _samplePackPlatform.loadBrowserExpansion();
    if (!mounted || stored.isEmpty) return;
    setState(() {
      // Anything toggled while the read was in flight wins: it is the more
      // recent statement of what the user wants.
      for (final MapEntry<String, bool> entry in stored.entries) {
        _browserExpanded.putIfAbsent(entry.key, () => entry.value);
      }
      _browserNodes = _buildBrowserNodes();
    });
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
        () => _samplePackMessage =
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
      await _samplePackPlatform.saveFolders(_samplePacks.map((SamplePack item) => item.path));
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
          expanded: _browserExpanded['pack:${_samplePacks[packIndex].path}'] ?? true,
          children: <BrowserNodeVm>[
            for (int assetIndex = 0; assetIndex < _samplePacks[packIndex].assets.length; assetIndex++)
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
          dragData: PlaylistInsertItem(id: 'pattern:${p.id}', patternId: p.id),
        ),
      );
    }
    // Patterns are arrangement sources, so keep this section scoped to the
    // Playlist. The rack and piano roll already expose the current pattern in
    // their own selectors; repeating it in the browser made the browser look
    // like a project tree on every workspace.
    if (_activeRailIndex == 1 && project.isNotEmpty) {
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
    unawaited(_samplePackPlatform.saveBrowserExpansion(Map<String, bool>.of(_browserExpanded)));
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
    if (node is BrowserSampleVm) {
      if (node.dragData case final SampleAsset asset) {
        _lastPlaylistItem = PlaylistInsertItem(id: asset.id, audioPath: asset.path);
      }
      if (node.previewPath != null) {
        try {
          _controller.previewSample(node.previewPath!);
        } catch (_) {
          // A preview failure must not interrupt browser navigation or dragging.
        }
      }
      setState(() {});
      return;
    }
    if (id.startsWith('pattern:')) {
      final String patternId = id.substring('pattern:'.length);
      _controller.client.selectPattern(patternId);
      _lastPlaylistItem = PlaylistInsertItem(id: id, patternId: patternId);
      setState(() {});
      _browserNodes = _buildBrowserNodes();
    }
  }

  void _onBrowserDoubleTap(String id) {
    final BrowserNodeVm? node = _findBrowserNode(id);
    final Object? data = node is BrowserSampleVm ? node.dragData : null;
    if (data is! PluginListing) return;

    final List<ProjectInstrument> instruments = _controller.client.readInstruments();
    ProjectInstrument? instrument;
    for (final ProjectInstrument candidate in instruments) {
      if (candidate.pluginId == data.id) {
        instrument = candidate;
        break;
      }
    }
    if (instrument == null) {
      for (final ProjectInstrument candidate in instruments) {
        if (candidate.selected) {
          instrument = candidate;
          break;
        }
      }
    }
    final HostedInstance? hosted = _controller.client.readHostedInstance();
    if (hosted == null) return;
    if (instrument != null && hosted.pluginId != data.id) return;

    setState(() {
      _openPlugin = hosted;
      _openPluginTrackId = instrument?.id ?? '';
      _openPluginParameters = _controller.client.readParameters(hosted);
    });
  }

  void _closePlugin() {
    setState(() {
      _openPlugin = null;
      _openPluginParameters = const <HostedParameter>[];
      _openPluginTrackId = null;
    });
  }

  void _movePlugin(Offset delta) {
    setState(() => _pluginOffset += delta);
  }

  /// Opens the plug-in window for [instrumentId]'s lane. The engine's hosted-
  /// instance surface follows the selection, so the lane is selected first —
  /// which also moves the rack highlight, exactly as a click would. Sample and
  /// empty lanes have nothing hosted, so they read as null and stay closed.
  void _openPluginForInstrument(String instrumentId) {
    if (instrumentId.isEmpty) return;
    ProjectInstrument? instrument;
    for (final ProjectInstrument candidate in _controller.client.readInstruments()) {
      if (candidate.id == instrumentId) {
        instrument = candidate;
        break;
      }
    }
    if (instrument == null) return;
    // A final capture: flow analysis does not carry the null-check promotion
    // of a loop-assigned variable into the setState closure below.
    final ProjectInstrument target = instrument;
    _controller.client.selectInstrument(instrumentId);
    if (target.pluginId == _samplePluginId) {
      // Samples are first-class rack channels too, but they do not have a
      // hosted CLAP instance to expose through readHostedInstance(). Give the
      // shared plugin window a small built-in sampler instance instead.
      final HostedInstance sampler = HostedInstance(
        id: 0,
        pluginId: _samplePluginId,
        name: 'OneBeat Sampler',
        vendor: 'OneBeat',
        path: target.pluginPath,
        format: PluginFormat.builtin,
        missing: false,
        hasEditor: false,
        needsRestart: false,
        paramCount: 0,
      );
      setState(() {
        _openPlugin = sampler;
        _openPluginTrackId = target.id;
        _openPluginParameters = const <HostedParameter>[];
      });
      return;
    }
    final HostedInstance? hosted = _controller.client.readHostedInstance();
    if (hosted == null || hosted.pluginId != target.pluginId) return;
    setState(() {
      _openPlugin = hosted;
      _openPluginTrackId = target.id;
      _openPluginParameters = _controller.client.readParameters(hosted);
    });
  }

  void _onControllerChanged() {
    if (++_framesSinceBrowserRefresh >= 20) {
      _framesSinceBrowserRefresh = 0;
      _browserNodes = _buildBrowserNodes();
    }
    // Answering "is this saved?" walks the whole project, so it is asked on a
    // human cadence rather than per frame. A third of a second of staleness in
    // an edited marker is invisible; a project walk every frame is not.
    if (++_framesSinceProjectRefresh >= 20) {
      _framesSinceProjectRefresh = 0;
      _project.refresh();
    }
    if (mounted) setState(() {});
  }

  void _onProjectChanged() {
    if (mounted) setState(() {});
  }

  // ----- project files (OB-3-05 §4) -----------------------------------------

  Future<ProjectResult> _saveProject() async {
    final ProjectResult result = await _project.save();
    _project.refresh();
    return result;
  }

  Future<void> _startNewProject() async {
    final ProjectResult result = _project.newProject();
    if (!mounted) return;
    if (result.isFailure) return;
    _browserNodes = _buildBrowserNodes();
    setState(() => _showNewProjectDialog = false);
  }

  Future<void> _newProject() async {
    // The shell normally polls the dirty bit on a human cadence. Ask once more
    // at the destructive action boundary so a just-finished rack edit cannot
    // slip past the prompt.
    _project.refresh();
    if (_project.modified) {
      setState(() => _showNewProjectDialog = true);
      return;
    }
    await _startNewProject();
  }

  Future<void> _saveBeforeNewProject() async {
    final ProjectResult result = await _saveProject();
    if (!mounted || result.outcome != ProjectOutcome.done) return;
    await _startNewProject();
  }

  Future<void> _saveProjectAs() async {
    await _project.saveAs();
    _project.refresh();
  }

  Future<void> _openProject() async {
    await _project.open();
    if (!mounted) return;
    // A different project means different patterns, instruments and packs in
    // the tree; the 20-frame refresh would show the old one until it came round.
    _browserNodes = _buildBrowserNodes();
    setState(() {});
  }

  Future<void> _renameProject(String name) async {
    setState(() => _showRenameDialog = false);
    await _project.rename(name);
    _project.refresh();
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

  int _durationTicks() {
    int end = 960 * 4 * 8;
    for (final ArrangementClip clip in _controller.client.readClips()) {
      if (clip.endTicks > end) end = clip.endTicks;
    }
    return end;
  }

  String _formatDuration(double seconds) {
    final int totalSeconds = seconds.round().clamp(0, 359999);
    final int minutes = totalSeconds ~/ 60;
    final int remaining = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  ShellScreenVm _buildVm() {
    final EngineSnapshot snapshot = _controller.snapshot;

    final String bpmText = snapshot.tempoBpm.toStringAsFixed(2);
    const String sigText = '4/4';
    final int durationTicks = _durationTicks();
    final double durationSeconds = durationTicks / 960.0 * 60.0 / snapshot.tempoBpm.clamp(1.0, 999.0);

    final int bar = snapshot.bar.clamp(1, 9999);
    final int beat = snapshot.beat.clamp(1, 4);
    final int tick = snapshot.tick.clamp(0, 959);
    final String positionText =
        '${bar.toString().padLeft(2, '0')}:${beat.toString().padLeft(2, '0')}:${tick.toString().padLeft(3, '0')}';

    final double meterLeft = dbToFraction(_controller.meter.left.levelDb);
    final double meterRight = dbToFraction(_controller.meter.right.levelDb);

    final ObTransportBarVm transportVm = ObTransportBarVm(
      title: 'ONEBEAT',
      playing: snapshot.playing,
      looping: snapshot.loopEnabled,
      metronome: _controller.metronomeEnabled,
      bpmText: bpmText,
      sigText: sigText,
      positionText: positionText,
      durationText: _formatDuration(durationSeconds),
      meterLeft: meterLeft,
      meterRight: meterRight,
      searchHint: 'Search actions',
    );

    final ObSideRailVm railVm = ObSideRailVm(
      items: _railItems,
      activeIndex: _activeRailIndex == _pianoRollIndex ? _lastRailIndex : _activeRailIndex,
      separatorBefore: null,
    );

    final double cpuPercent = (snapshot.cpuLoad * 100.0).clamp(0.0, 100.0);
    final double sampleRateKhz = snapshot.sampleRate / 1000.0;
    final double latencyMs = (snapshot.latencyFramesRoundTrip / snapshot.sampleRate) * 1000.0;

    final String leftDetail =
        'CoreAudio · ${sampleRateKhz.toStringAsFixed(1)} kHz · ${snapshot.blockFrames} spl · ${latencyMs.toStringAsFixed(1)} ms';

    // The project line is the same in both states: whether the transport is
    // running has nothing to do with whether the work is safe on disk, and the
    // status bar was previously claiming a file name it had made up.
    final String projectDetail = _project.hasFile ? _project.displayName : '${_project.displayName} · not saved yet';

    final ObStatusBarVm statusVm = ObStatusBarVm(
      tone: _project.message.isNotEmpty || snapshot.xrunCount > 0 ? StatusTone.warning : StatusTone.ok,
      primary: snapshot.playing ? 'Playing' : _project.name,
      details: snapshot.playing
          ? <String>[
              projectDetail,
              leftDetail,
              '${cpuPercent.toStringAsFixed(0)}% CPU',
              '${snapshot.activeVoices} voices',
            ]
          : <String>[projectDetail, if (_project.message.isNotEmpty) _project.message else 'Press ⌘S to save'],
      rightHint: snapshot.playing ? '⌘K Search actions' : '⌘S save · ⌘K actions',
    );

    return ShellScreenVm(
      menuBar: null,
      transport: transportVm,
      rail: railVm,
      status: statusVm,
      browserWidth: _browserWidth,
      browser: (_activeRailIndex == 0 || _activeRailIndex == 1)
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
      project: _project,
      onOpenExport: () => setState(() => _showExportDialog = true),
      onOpenPreferences: () => setState(() => _showPreferencesDialog = true),
      onSaveProject: () => unawaited(_saveProject()),
      onSaveProjectAs: () => unawaited(_saveProjectAs()),
      onNewProject: () => unawaited(_newProject()),
      onOpenProject: () => unawaited(_openProject()),
      onRenameProject: () => setState(() => _showRenameDialog = true),
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
          SaveProjectIntent: CallbackAction<SaveProjectIntent>(
            onInvoke: (_) {
              unawaited(_saveProject());
              return null;
            },
          ),
          SaveProjectAsIntent: CallbackAction<SaveProjectAsIntent>(
            onInvoke: (_) {
              unawaited(_saveProjectAs());
              return null;
            },
          ),
          OpenProjectIntent: CallbackAction<OpenProjectIntent>(
            onInvoke: (_) {
              unawaited(_openProject());
              return null;
            },
          ),
          RenameProjectIntent: CallbackAction<RenameProjectIntent>(
            onInvoke: (_) {
              setState(() => _showRenameDialog = true);
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
                  onOpenPlugin: _openPluginForInstrument,
                  onOpenPattern: () => _openPianoRoll(),
                  onClosePianoRoll: _closePianoRoll,
                  externalAudioDrop: _audioFileDrop,
                  lastPlaylistItem: _lastPlaylistItem,
                ),
                onRailSelect: _onRailSelect,
                onMenuTap: _onMenuTap,
                onTogglePlay: _controller.togglePlay,
                onStop: _controller.stop,
                onToggleLoop: _controller.toggleLoop,
                onToggleMetronome: _controller.toggleMetronome,
                onUndo: _controller.undoProject,
                onRedo: _controller.redoProject,
                onExport: () => setState(() => _showExportDialog = true),
                onTempoSubmitted: (String value) {
                  final double? bpm = double.tryParse(value);
                  if (bpm != null && bpm >= 20 && bpm <= 999) {
                    _controller.setTempo(bpm);
                  }
                },
                onBrowserTap: _onBrowserTap,
                onBrowserDoubleTap: _onBrowserDoubleTap,
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
              if (_showNewProjectDialog)
                UnsavedProjectDialog(
                  projectName: _project.name,
                  onSave: () => unawaited(_saveBeforeNewProject()),
                  onDiscard: () => unawaited(_startNewProject()),
                  onCancel: () => setState(() => _showNewProjectDialog = false),
                ),
              if (_showRenameDialog)
                RenameProjectDialog(
                  initialName: _project.name,
                  currentFileName: _project.hasFile ? _project.path : '',
                  onSubmit: (String name) => unawaited(_renameProject(name)),
                  onClose: () => setState(() => _showRenameDialog = false),
                ),
              if (_openPlugin case final HostedInstance plugin)
                Positioned(
                  left: _pluginOffset.dx,
                  top: _pluginOffset.dy,
                  child: PluginBinding(
                    client: widget.client,
                    trackId: _openPluginTrackId ?? '',
                    pluginName: plugin.name,
                    sampleName: plugin.pluginId == _samplePluginId
                        ? _controller.client
                              .readInstruments()
                              .firstWhere(
                                (ProjectInstrument item) => item.id == (_openPluginTrackId ?? ''),
                                orElse: () => const ProjectInstrument(
                                  id: '',
                                  name: '808_Kick_Punchy.wav',
                                  color: '',
                                  order: 0,
                                  pluginId: '',
                                  pluginName: '',
                                  pluginVendor: '',
                                  pluginPath: '',
                                  muted: false,
                                  selected: false,
                                  affectedPatterns: 0,
                                  affectedClips: 0,
                                  affectedNotes: 0,
                                ),
                              )
                              .name
                        : null,
                    trackName: _openPluginTrackId?.isNotEmpty == true
                        ? (_controller.client
                              .readInstruments()
                              .firstWhere(
                                (ProjectInstrument item) => item.id == _openPluginTrackId,
                                orElse: () => const ProjectInstrument(
                                  id: '',
                                  name: 'Instrument',
                                  color: '',
                                  order: 0,
                                  pluginId: '',
                                  pluginName: '',
                                  pluginVendor: '',
                                  pluginPath: '',
                                  muted: false,
                                  selected: false,
                                  affectedPatterns: 0,
                                  affectedClips: 0,
                                  affectedNotes: 0,
                                ),
                              )
                              .name)
                        : 'Instrument',
                    parameters: _openPluginParameters,
                    onDragUpdate: _movePlugin,
                    onClose: _closePlugin,
                  ),
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
    required this.onOpenPlugin,
    required this.onOpenPattern,
    required this.onClosePianoRoll,
    this.externalAudioDrop,
    this.lastPlaylistItem,
  });

  final int activeRailIndex;
  final core.EngineController coreController;
  final ValueChanged<int> onSelectRail;
  final ValueChanged<String> onOpenPianoRoll;
  final ValueChanged<String> onOpenPlugin;
  final VoidCallback onOpenPattern;
  final VoidCallback onClosePianoRoll;
  final AudioFileDrop? externalAudioDrop;
  final PlaylistInsertItem? lastPlaylistItem;

  @override
  Widget build(BuildContext context) {
    return switch (activeRailIndex) {
      0 => RackBinding(
        client: coreController.client,
        controller: coreController,
        onBrowsePlugins: () => onSelectRail(0),
        onOpenMixer: () => onSelectRail(2),
        onOpenPianoRoll: onOpenPianoRoll,
        onOpenPlugin: onOpenPlugin,
        onOpenSampler: onOpenPlugin,
      ),
      1 => PlaylistBinding(
        client: coreController.client,
        controller: coreController,
        onOpenPattern: (String patternId, String clipId) {
          coreController.client.selectPattern(patternId);
          onOpenPattern();
        },
        externalAudioDrop: externalAudioDrop,
        lastClickedItem: lastPlaylistItem,
      ),
      2 => MixerBinding(client: coreController.client, controller: coreController),
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
    required this.project,
    required this.onOpenExport,
    required this.onOpenPreferences,
    required this.onNewProject,
    required this.onSaveProject,
    required this.onSaveProjectAs,
    required this.onOpenProject,
    required this.onRenameProject,
    required this.onSelectRail,
    required this.child,
  });

  final core.EngineController controller;
  final ProjectStore project;
  final VoidCallback onOpenExport;
  final VoidCallback onOpenPreferences;
  final VoidCallback onNewProject;
  final VoidCallback onSaveProject;
  final VoidCallback onSaveProjectAs;
  final VoidCallback onOpenProject;
  final VoidCallback onRenameProject;
  final ValueChanged<int> onSelectRail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _StablePlatformMenuBar(
      menuVersion:
          '${project.hasFile}:${project.modified}:${controller.client.canUndoProject}:${controller.client.undoProjectName}:${controller.client.canRedoProject}:${controller.client.redoProjectName}',
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: 'OneBeat',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Settings…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
                  onSelected: onOpenPreferences,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: <PlatformMenuItem>[
            // New Project is intentionally a menu action rather than ⌘N:
            // ⌘N remains the pattern-creation shortcut in the editor scope.
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(label: 'New Project', onSelected: onNewProject),
                PlatformMenuItem(
                  label: 'Open…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
                  onSelected: onOpenProject,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: project.hasFile ? 'Save' : 'Save…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
                  onSelected: onSaveProject,
                ),
                PlatformMenuItem(
                  label: 'Save as…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
                  onSelected: onSaveProjectAs,
                ),
                PlatformMenuItem(label: 'Rename project…', onSelected: onRenameProject),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Export audio…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true, shift: true),
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
              label: controller.client.canUndoProject && controller.client.undoProjectName.isNotEmpty
                  ? 'Undo ${controller.client.undoProjectName}'
                  : 'Undo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
              onSelected: controller.client.canUndoProject ? controller.undoProject : null,
            ),
            PlatformMenuItem(
              label: controller.client.canRedoProject && controller.client.redoProjectName.isNotEmpty
                  ? 'Redo ${controller.client.redoProjectName}'
                  : 'Redo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
              onSelected: controller.client.canRedoProject ? controller.redoProject : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(label: 'Channels', onSelected: () => onSelectRail(0)),
                PlatformMenuItem(label: 'Playlist', onSelected: () => onSelectRail(1)),
                PlatformMenuItem(label: 'Mixer', onSelected: () => onSelectRail(2)),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

/// Keeps Flutter's native menu tracking alive while the engine ticker rebuilds
/// the shell. Replacing PlatformMenuBar during a mouse-down menu interaction
/// makes AppKit dismiss the currently open menu.
class _StablePlatformMenuBar extends StatefulWidget {
  const _StablePlatformMenuBar({required this.menuVersion, required this.menus, required this.child});

  final String menuVersion;
  final List<PlatformMenuItem> menus;
  final Widget child;

  @override
  State<_StablePlatformMenuBar> createState() => _StablePlatformMenuBarState();
}

class _StablePlatformMenuBarState extends State<_StablePlatformMenuBar> {
  late final ValueNotifier<Widget> _child;
  late Widget _platformMenuBar;

  @override
  void initState() {
    super.initState();
    _child = ValueNotifier<Widget>(widget.child);
    _platformMenuBar = _buildPlatformMenuBar(widget.menus);
  }

  Widget _buildPlatformMenuBar(List<PlatformMenuItem> menus) {
    return PlatformMenuBar(
      menus: menus,
      child: ValueListenableBuilder<Widget>(valueListenable: _child, builder: (_, Widget child, _) => child),
    );
  }

  @override
  void didUpdateWidget(covariant _StablePlatformMenuBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _child.value = widget.child;
    if (widget.menuVersion != oldWidget.menuVersion) {
      _platformMenuBar = _buildPlatformMenuBar(widget.menus);
    }
  }

  @override
  void dispose() {
    _child.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _platformMenuBar;
}
