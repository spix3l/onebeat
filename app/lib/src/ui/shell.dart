// The app shell (OB-1-11 §1).
//
// A skeleton of the designed layout: real top bar, real status bar, and a centre
// that is an *empty state* rather than a placeholder — it says what the app can
// do right now and invites the one action that works (FR-UX-13).
import 'dart:io' show stdout;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../main.dart' show startupStopwatch;
import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'app_menu_bar.dart';
import 'arrangement.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'export_dialog.dart';
import 'extension_manager_view.dart';
import 'channel_rack.dart';
import 'chrome.dart';
import 'icons.dart';
import 'mixer_view.dart';
import 'pattern_selector.dart';
import 'performance_overlay.dart';
import 'piano_roll.dart';
import 'plugin_builtin_view.dart';
import 'plugin_list_debug.dart';
import 'preferences_dialog.dart';
import 'script_console_view.dart';
import 'shortcuts.dart';
import 'token_gallery.dart';
import 'transport_readout.dart';

class OneBeatShell extends StatefulWidget {
  const OneBeatShell({required this.client, super.key});

  final EngineClient client;

  @override
  State<OneBeatShell> createState() => _OneBeatShellState();
}

class _OneBeatShellState extends State<OneBeatShell>
    with SingleTickerProviderStateMixin {
  late final EngineController _controller;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'shell');
  bool _showTokenGallery = false;
  bool _showPluginList = false;
  bool _showShortcutSheet = false;
  bool _showExportDialog = false;
  bool _showPreferencesDialog = false;

  @override
  void initState() {
    super.initState();
    _controller = EngineController(
      client: widget.client,
      vsync: this,
      motion: OneBeatTokens.dark().motion,
    );
    // Synchronous, and deliberately before the first frame: the cache read is
    // one file, and doing it here is what makes the list present at startup
    // rather than appearing a moment later (FR-PLG-05, OB-2-02).
    _controller.library.load();
    _controller.rack.load();
    _controller.patterns.load();
    _controller.arrangement.load();
    // NFR-04's number, printed on every launch rather than measured once and
    // written into a document that then goes stale. This is the frame the user
    // can act on: engine up, plug-in list populated from the cache.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      stdout.writeln(
        'onebeat: usable in ${startupStopwatch.elapsedMilliseconds} ms '
        'with ${_controller.library.plugins.length} plug-ins from cache',
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The view (and so the display's refresh rate) is only available once
    // dependencies are resolved — and it can change when the window moves to
    // another monitor, which is exactly when the frame budget changes too.
    _controller.frameStats.syncToDisplay(View.of(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    // Global shortcuts: the transport, undo, and view switching. They live on
    // the shell so they stay reachable from every editor — `Shortcuts` resolve
    // up the tree, so an editor owning its own keys does not shadow these.
    //
    // Space is the transport, always. No control binds it, so it works no
    // matter which one was clicked last (FR-UX-24). The typing-aware manager in
    // ScopedShortcuts is what stops it inserting a space into a rename field.
    return OneBeatMenuBar(
      controller: _controller,
      onOpenExport: () => setState(() => _showExportDialog = true),
      onOpenPreferences: () => setState(() => _showPreferencesDialog = true),
      onOpenShortcuts: () => setState(() => _showShortcutSheet = true),
      child: ScopedShortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        ...shortcutsForScope(ShortcutScope.global),
        // Debug surfaces. Function keys, so they never collide with typing.
        const SingleActivator(LogicalKeyboardKey.f8):
            const _TogglePerformanceOverlayIntent(),
        const SingleActivator(LogicalKeyboardKey.f9):
            const _ToggleTokenGalleryIntent(),
        const SingleActivator(LogicalKeyboardKey.f10):
            const _TogglePluginListIntent(),
      },
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
            _controller.client.seekFrames(0);
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
            _controller.setView(switch (intent.index) {
              1 => WorkspaceView.arrangement,
              2 => WorkspaceView.rack,
              _ => WorkspaceView.pianoRoll,
            });
            return null;
          },
        ),
        CommandPaletteIntent: CallbackAction<CommandPaletteIntent>(
          onInvoke: (_) {
            setState(() => _showShortcutSheet = !_showShortcutSheet);
            return null;
          },
        ),
        _TogglePerformanceOverlayIntent:
            CallbackAction<_TogglePerformanceOverlayIntent>(
              onInvoke: (_) {
                _controller.togglePerformanceOverlay();
                return null;
              },
            ),
        _ToggleTokenGalleryIntent: CallbackAction<_ToggleTokenGalleryIntent>(
          onInvoke: (_) {
            setState(() => _showTokenGallery = !_showTokenGallery);
            return null;
          },
        ),
        _TogglePluginListIntent: CallbackAction<_TogglePluginListIntent>(
          onInvoke: (_) {
            setState(() => _showPluginList = !_showPluginList);
            return null;
          },
        ),
      },
      child: Focus(
        // The one autofocus in the app. Editors take focus on interaction;
        // two competing autofocus nodes is what made Space-to-play depend on
        // build order.
        focusNode: _rootFocus,
        autofocus: true,
        child: Container(
          color: tokens.color.surfaceDeep,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TopBar(
                controller: _controller,
                onOpenShortcuts: () =>
                    setState(() => _showShortcutSheet = true),
                onOpenExport: () =>
                    setState(() => _showExportDialog = true),
                onOpenPreferences: () =>
                    setState(() => _showPreferencesDialog = true),
              ),
              // D-M6's notice sits directly under the chrome and above every
              // editor: the warning belongs to the pattern being edited, not
              // to whichever view happens to be open.
              SharedPatternNoticeBar(
                store: _controller.patterns,
                onMakeUnique: (String clipId) {
                  _controller.patterns.makeUnique(<String>[clipId]);
                  _controller.refreshAll();
                },
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Rail and workspace both follow the view notifier rather
                    // than the controller: the controller notifies every
                    // frame, and this subtree is the expensive one.
                    ValueListenableBuilder<WorkspaceView>(
                      valueListenable: _controller.viewNotifier,
                      builder:
                          (BuildContext context, WorkspaceView view, _) =>
                              DestinationRail(
                                destinations: _destinations,
                                activeView: view,
                                onSelectView: _controller.setView,
                              ),
                    ),
                    if (!_showTokenGallery && !_showPluginList)
                      PatternSelector(
                        store: _controller.patterns,
                        onOpenPattern: _controller.openPattern,
                      ),
                    Expanded(
                      child: Stack(
                        children: <Widget>[
                          if (_showTokenGallery)
                            const TokenGallery()
                          else if (_showPluginList)
                            PluginListDebugPanel(controller: _controller)
                          else
                            ValueListenableBuilder<WorkspaceView>(
                              valueListenable: _controller.viewNotifier,
                              builder:
                                  (BuildContext context, WorkspaceView _, _) =>
                                      _buildWorkspace(),
                            ),
                          FrameTimingOverlay(controller: _controller),
                          if (_showShortcutSheet)
                            ShortcutSheet(
                              onDismiss: () =>
                                  setState(() => _showShortcutSheet = false),
                            ),
                          if (_showExportDialog)
                            ExportAudioDialog(
                              onClose: () => setState(() => _showExportDialog = false),
                            ),
                          if (_showPreferencesDialog)
                            PreferencesDialog(
                              onClose: () => setState(() => _showPreferencesDialog = false),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBar(controller: _controller),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// The rail's destinations.
  List<RailDestination> get _destinations => <RailDestination>[
    const RailDestination(
      actionId: 'view.playlist',
      icon: OneBeatIconData.playlist,
      label: 'Playlist',
      view: WorkspaceView.arrangement,
    ),
    const RailDestination(
      actionId: 'view.pianoRoll',
      icon: OneBeatIconData.piano,
      label: 'Piano',
      view: WorkspaceView.pianoRoll,
    ),
    const RailDestination(
      actionId: 'view.channels',
      icon: OneBeatIconData.channels,
      label: 'Rack',
      view: WorkspaceView.rack,
    ),
    const RailDestination(
      actionId: 'view.mixer',
      icon: OneBeatIconData.mixer,
      label: 'Mixer',
      view: WorkspaceView.mixer,
    ),
    const RailDestination(
      actionId: 'view.plugins',
      icon: OneBeatIconData.plugins,
      label: 'FX',
      view: WorkspaceView.plugins,
    ),
    const RailDestination(
      actionId: 'view.console',
      icon: OneBeatIconData.console,
      label: 'Script',
      view: WorkspaceView.console,
    ),
    const RailDestination(
      actionId: 'view.extensions',
      icon: OneBeatIconData.extensions,
      label: 'Extns',
      view: WorkspaceView.extensions,
    ),
    RailDestination(
      actionId: 'view.prefs',
      icon: OneBeatIconData.preferences,
      label: 'Prefs',
      onSelected: () => setState(() => _showPreferencesDialog = true),
    ),
  ];

  /// The workspace views.
  Widget _buildWorkspace() => switch (_controller.view) {
    WorkspaceView.rack => ChannelRack(
      controller: _controller,
      onBrowsePlugins: () => setState(() => _showPluginList = true),
    ),
    WorkspaceView.pianoRoll => PianoRoll(
      controller: _controller,
      store: _controller.pianoRoll,
      patterns: _controller.patterns,
    ),
    WorkspaceView.arrangement => ArrangementView(
      controller: _controller,
      store: _controller.arrangement,
      patterns: _controller.patterns,
      onOpenPattern: (String patternId, String clipId) =>
          _controller.openPattern(patternId, fromClipId: clipId),
    ),
    WorkspaceView.mixer => MixerRoutingView(controller: _controller),
    WorkspaceView.plugins => BuiltinPluginsView(controller: _controller),
    WorkspaceView.console => ScriptConsoleView(controller: _controller),
    WorkspaceView.extensions => ExtensionManagerView(controller: _controller),
  };
}

class _TogglePerformanceOverlayIntent extends Intent {
  const _TogglePerformanceOverlayIntent();
}

class _ToggleTokenGalleryIntent extends Intent {
  const _ToggleTokenGalleryIntent();
}

class _TogglePluginListIntent extends Intent {
  const _TogglePluginListIntent();
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.onOpenShortcuts,
    required this.onOpenExport,
    required this.onOpenPreferences,
  });

  final EngineController controller;
  final VoidCallback onOpenShortcuts;
  final VoidCallback onOpenExport;
  final VoidCallback onOpenPreferences;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.topBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
          children: <Widget>[
            // The window's real close/minimise/zoom buttons sit here, drawn by
            // macOS over the app's own bar (full-size content view).
            const TitleBarInset(),
            const BrandMark(version: 'v0.3 SEQUENCES'),
            SizedBox(width: tokens.spacing.lg),
            AnimatedBuilder(
              animation: controller,
              builder: (BuildContext context, Widget? child) => TransportCluster(
                playing: controller.snapshot.playing,
                canUndo: controller.client.canUndoProject,
                canRedo: controller.client.canRedoProject,
                loopEnabled: controller.snapshot.loopEnabled,
                undoName: controller.client.undoProjectName,
                redoName: controller.client.redoProjectName,
                onTogglePlay: controller.togglePlay,
                onUndo: controller.undoProject,
                onRedo: controller.redoProject,
                onReturnToZero: () => controller.client.seekFrames(0),
                onToggleLoop: () => controller.client.setLoop(
                  controller.snapshot.loopStartBeats,
                  controller.snapshot.loopEndBeats,
                  enabled: !controller.snapshot.loopEnabled,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.md),
            // Three separate wells, as the design draws them: a value you read
            // constantly should not have to be picked out of a strip.
            AnimatedBuilder(
              animation: controller,
              builder: (BuildContext context, Widget? child) => ReadoutWell(
                label: 'BPM',
                child: TempoField(
                  tempo: controller.snapshot.tempoBpm,
                  onChanged: controller.client.setTempo,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.xs),
            ReadoutWell(
              label: 'SIG',
              child: Text(
                '4/4',
                maxLines: 1,
                softWrap: false,
                style: tokens.type.numericLarge,
              ),
            ),
            SizedBox(width: tokens.spacing.xs),
            ReadoutWell(
              label: 'BAR · BEAT · TICK',
              child: TransportReadout(controller: controller),
            ),
            SizedBox(width: tokens.spacing.md),
            // The search well takes whatever is left: at the window's 1280px
            // minimum it collapses to its icon and at 1900 it stretches, and in
            // neither case does the Export button fall off the end of the bar
            // (it used to). `chrome_layout_test.dart` holds that at three
            // widths — the claim was wrong by 90px before it was measured.
            Flexible(child: SearchAffordance(onTap: onOpenShortcuts)),
            SizedBox(width: tokens.spacing.md),
            ValueListenableBuilder<WorkspaceView>(
              valueListenable: controller.viewNotifier,
              builder: (BuildContext context, WorkspaceView view, _) =>
                  ViewSwitcher(activeView: view, onSelect: controller.setView),
            ),
            SizedBox(width: tokens.spacing.sm),
            ExportButton(onPressed: onOpenExport),
            SizedBox(width: tokens.spacing.sm),
            const MasterPeakIndicator(),
          ],
      ),
    );
  }
}

/// The designed status bar. Shows live engine info and context hints.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.statusBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        border: Border(
          top: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final EngineSnapshot snapshot = controller.snapshot;
          final String patternName = controller.patterns.current?.name ?? 'Main Groove';
          final int clipCount = controller.arrangement.clips.length;
          return Row(
            children: <Widget>[
              Container(
                width: tokens.spacing.sm,
                height: tokens.spacing.sm,
                decoration: BoxDecoration(
                  color: snapshot.playing ? tokens.color.meterLow : tokens.color.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                snapshot.playing ? 'Playing · $patternName' : 'Stopped · $patternName',
                style: tokens.type.label.copyWith(color: tokens.color.textPrimary),
              ),
              SizedBox(width: tokens.spacing.lg),
              Text(
                'All view · $clipCount clips',
                style: tokens.type.numericSmall,
              ),
              SizedBox(width: tokens.spacing.lg),
              Text(
                'Buffer ${snapshot.blockFrames} · ${snapshot.latencyMilliseconds.toStringAsFixed(1)} ms',
                style: tokens.type.numericSmall,
              ),
              const Spacer(),
              Text(
                'Actions: system menu bar · ⌘K for anything',
                style: tokens.type.label,
              ),
            ],
          );
        },
      ),
    );
  }
}
