// The app shell (OB-1-11 §1).
//
// A skeleton of the designed layout: real top bar, real status bar, and a centre
// that is an *empty state* rather than a placeholder — it says what the app can
// do right now and invites the one action that works (FR-UX-13).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'meter.dart';
import 'performance_overlay.dart';
import 'token_gallery.dart';
import 'transport_readout.dart';

class OneBeatShell extends StatefulWidget {
  const OneBeatShell({required this.client, super.key});

  final EngineClient client;

  @override
  State<OneBeatShell> createState() => _OneBeatShellState();
}

class _OneBeatShellState extends State<OneBeatShell> with SingleTickerProviderStateMixin {
  late final EngineController _controller;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'shell');
  bool _showTokenGallery = false;

  @override
  void initState() {
    super.initState();
    _controller = EngineController(
      client: widget.client,
      vsync: this,
      motion: OneBeatTokens.dark().motion,
    );
    widget.client.setStepPattern(EngineController.demoPattern);
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

    // Space is the transport, always. It is bound at the root of the shell and
    // the chrome controls deliberately do not consume it, so it works no matter
    // which control was clicked last (OB-1-11 AC).
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.f8): _TogglePerformanceOverlayIntent(),
        SingleActivator(LogicalKeyboardKey.f9): _ToggleTokenGalleryIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
            onInvoke: (_) {
              _controller.togglePlay();
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
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          child: Container(
            color: tokens.color.surfaceDeep,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TopBar(controller: _controller),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      if (_showTokenGallery)
                        const TokenGallery()
                      else
                        _EmptyStage(controller: _controller),
                      FrameTimingOverlay(controller: _controller),
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
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _TogglePerformanceOverlayIntent extends Intent {
  const _TogglePerformanceOverlayIntent();
}

class _ToggleTokenGalleryIntent extends Intent {
  const _ToggleTokenGalleryIntent();
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.topBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(bottom: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
      ),
      child: Row(
        children: <Widget>[
          AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) => Row(
              children: <Widget>[
                OneBeatButton(
                  label: controller.snapshot.playing ? 'STOP' : 'PLAY',
                  semanticLabel: controller.snapshot.playing
                      ? 'Stop playback, space bar'
                      : 'Start playback, space bar',
                  active: controller.snapshot.playing,
                  onPressed: controller.togglePlay,
                ),
                SizedBox(width: tokens.spacing.sm),
                OneBeatButton(
                  label: 'RTZ',
                  semanticLabel: 'Return to zero',
                  onPressed: () => controller.client.seekFrames(0),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.xl),
          AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) => TempoField(
              tempo: controller.snapshot.tempoBpm,
              onChanged: controller.client.setTempo,
            ),
          ),
          SizedBox(width: tokens.spacing.xs),
          Text('BPM', style: tokens.type.label),
          SizedBox(width: tokens.spacing.xl),
          TransportReadout(controller: controller),
          const Spacer(),
          MasterMeter(controller: controller),
        ],
      ),
    );
  }
}

/// The designed empty state. It names what is here, and offers the actions that
/// exist — the demo pads and the transport — rather than an apology.
class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.controller});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text('Nothing arranged yet', style: tokens.type.title),
          SizedBox(height: tokens.spacing.sm),
          SizedBox(
            width: tokens.size.proseWidth,
            child: Text(
              'Press Play to hear the built-in pattern, or tap a pad to trigger the '
              'sampler. The channel rack and the arrangement arrive in v0.3.',
              textAlign: TextAlign.center,
              style: tokens.type.body.copyWith(color: tokens.color.textMuted),
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          const _DemoPads(),
        ],
      ),
    );
  }
}

class _DemoPads extends StatelessWidget {
  const _DemoPads();

  static const List<int> _notes = <int>[48, 52, 55, 60, 64, 67, 72, 76];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final _OneBeatShellState state = context.findAncestorStateOfType<_OneBeatShellState>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final int note in _notes) ...<Widget>[
          OneBeatButton(
            label: '$note',
            semanticLabel: 'Trigger note $note',
            onPressed: () => state.widget.client.noteOn(note, 0.9),
          ),
          SizedBox(width: tokens.spacing.sm),
        ],
      ],
    );
  }
}

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
        color: tokens.color.surfacePanel,
        border: Border(top: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
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
              Text('${snapshot.activeVoices} voices', style: tokens.type.numericSmall),
              SizedBox(width: tokens.spacing.lg),
              Text(
                'CPU ${(snapshot.cpuLoad * 100).toStringAsFixed(0)}%',
                style: tokens.type.numericSmall,
              ),
              if (snapshot.xrunCount > 0) ...<Widget>[
                SizedBox(width: tokens.spacing.lg),
                Text(
                  '${snapshot.xrunCount} dropouts',
                  style: tokens.type.numericSmall.copyWith(color: tokens.color.warning),
                ),
              ],
              const Spacer(),
              if (controller.status.isNotEmpty)
                Flexible(
                  child: Text(
                    controller.status,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.label.copyWith(color: tokens.color.textPrimary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
