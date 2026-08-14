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
import 'arrangement.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'channel_rack.dart';
import 'chrome.dart';
import 'meter.dart';
import 'pattern_selector.dart';
import 'performance_overlay.dart';
import 'piano_roll.dart';
import 'plugin_list_debug.dart';
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
    return ScopedShortcuts(
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
                    DestinationRail(
                      destinations: _destinations,
                      activeView: _controller.view,
                      onSelectView: _controller.setView,
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
                            _buildWorkspace(),
                          FrameTimingOverlay(controller: _controller),
                          if (_showShortcutSheet)
                            ShortcutSheet(
                              onDismiss: () =>
                                  setState(() => _showShortcutSheet = false),
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
    );
  }

  /// The rail's destinations. `Packs` and `FX` have no view yet and render
  /// disabled — an enabled tile that does nothing is worse than an honest one
  /// that says "not yet" by being unclickable (FR-UX-13).
  List<RailDestination> get _destinations => const <RailDestination>[
    RailDestination(
      actionId: 'view.playlist',
      glyph: '▤',
      label: 'Playlist',
      view: WorkspaceView.arrangement,
    ),
    RailDestination(
      actionId: 'view.channels',
      glyph: '▥',
      label: 'Channels',
      view: WorkspaceView.rack,
    ),
    RailDestination(
      actionId: 'view.pianoRoll',
      glyph: '♪',
      label: 'Piano',
      view: WorkspaceView.pianoRoll,
    ),
  ];

  /// The three Stage 3 editors. All of them edit the same project through the
  /// same command bus, so switching between them is presentation only — no
  /// state is handed over and nothing is saved on the way out.
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
  const _TopBar({required this.controller, required this.onOpenShortcuts});

  final EngineController controller;
  final VoidCallback onOpenShortcuts;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.topBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
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
          const BrandMark(version: 'v0.3 SEQUENCES'),
          SizedBox(width: tokens.spacing.lg),
          AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) => TransportCluster(
              playing: controller.snapshot.playing,
              canUndo: controller.client.canUndoProject,
              canRedo: controller.client.canRedoProject,
              undoName: controller.client.undoProjectName,
              redoName: controller.client.redoProjectName,
              onTogglePlay: controller.togglePlay,
              onUndo: controller.undoProject,
              onRedo: controller.redoProject,
              onReturnToZero: () => controller.client.seekFrames(0),
            ),
          ),
          SizedBox(width: tokens.spacing.lg),
          // Three separate wells, as the design draws them: a value you read
          // constantly should not have to be picked out of a strip.
          AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) => ReadoutWell(
              width: tokens.size.bpmFieldWidth,
              label: 'BPM',
              child: TempoField(
                tempo: controller.snapshot.tempoBpm,
                onChanged: controller.client.setTempo,
              ),
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          ReadoutWell(
            width: tokens.size.signatureWidth,
            label: 'SIG',
            child: Text('4/4', style: tokens.type.numeric),
          ),
          SizedBox(width: tokens.spacing.sm),
          ReadoutWell(
            width: tokens.size.clockWidth,
            label: 'BAR · BEAT · TICK',
            child: TransportReadout(controller: controller),
          ),
          SizedBox(width: tokens.spacing.lg),
          SearchAffordance(onTap: onOpenShortcuts),
          const Spacer(),
          AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) => ViewSwitcher(
              activeView: controller.view,
              onSelect: controller.setView,
            ),
          ),
          SizedBox(width: tokens.spacing.lg),
          MasterMeter.of(controller),
        ],
      ),
    );
  }
}

/// The designed empty state. It names what is here, and offers the actions that
/// exist — the demo pads and the transport — rather than an apology.
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
          return Row(
            children: <Widget>[
              Text(controller.client.deviceName, style: tokens.type.label),
              SizedBox(width: tokens.spacing.lg),
              Text(
                '${snapshot.sampleRate.toStringAsFixed(0)} Hz · ${snapshot.blockFrames} frames · '
                '${snapshot.latencyMilliseconds.toStringAsFixed(1)} ms',
                style: tokens.type.numericSmall,
              ),
              SizedBox(width: tokens.spacing.lg),
              Text(
                '${snapshot.activeVoices} voices',
                style: tokens.type.numericSmall,
              ),
              SizedBox(width: tokens.spacing.lg),
              Text(
                'CPU ${(snapshot.cpuLoad * 100).toStringAsFixed(0)}%',
                style: tokens.type.numericSmall,
              ),
              if (snapshot.xrunCount > 0) ...<Widget>[
                SizedBox(width: tokens.spacing.lg),
                Text(
                  '${snapshot.xrunCount} dropouts',
                  style: tokens.type.numericSmall.copyWith(
                    color: tokens.color.warning,
                  ),
                ),
              ],
              const Spacer(),
              if (controller.status.isNotEmpty)
                Flexible(
                  child: Text(
                    controller.status,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.label.copyWith(
                      color: tokens.color.textPrimary,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
