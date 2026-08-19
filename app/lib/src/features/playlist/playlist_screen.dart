// PlaylistScreen — the complete playlist workspace view (UI-C-04 / UI-D-04).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/toggle_chip.dart';
import 'playlist_canvas.dart';
import 'playlist_screen_vm.dart';
import 'playlist_store.dart';
import 'timeline_ruler.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({
    required this.vm,
    this.canvasKey,
    this.onClipTap,
    this.onClipDoubleTap,
    this.onClipPanStart,
    this.onClipPanUpdate,
    this.onClipPanEnd,
    this.onClipPanCancel,
    this.onClipResizeStart,
    this.onClipResizeUpdate,
    this.onClipResizeEnd,
    this.onClipResizeCancel,
    this.onBackgroundPanStart,
    this.onBackgroundPanUpdate,
    this.onBackgroundPanEnd,
    this.onBackgroundPanCancel,
    this.onBackgroundTap,
    this.onDrop,
    this.onScroll,
    this.onPanZoom,
    this.onSeekBar,
    this.onSnapChanged,
    this.onStartChanged,
    this.onLengthChanged,
    this.onOffsetChanged,
    this.onLoopToggle,
    this.onMuteToggle,
    this.onTransposeChanged,
    this.onMakeUnique,
    this.onSplitByChannel,
    this.onStretchModeChanged,
    this.onReverseToggle,
    this.onSourceBpmChanged,
    this.onFitToTempo,
    this.onSplitAtPlayhead,
    this.onLaneMute,
    this.onLaneSolo,
    this.onLaneCollapse,
    super.key,
  });

  final PlaylistScreenVm vm;
  final Key? canvasKey;
  final ValueChanged<int>? onClipTap;
  final ValueChanged<int>? onClipDoubleTap;
  final void Function(int clipId, DragStartDetails details)? onClipPanStart;
  final void Function(int clipId, DragUpdateDetails details)? onClipPanUpdate;
  final void Function(int clipId, DragEndDetails details)? onClipPanEnd;
  final ValueChanged<int>? onClipPanCancel;
  final void Function(int clipId, DragStartDetails details)? onClipResizeStart;
  final void Function(int clipId, DragUpdateDetails details)? onClipResizeUpdate;
  final void Function(int clipId, DragEndDetails details)? onClipResizeEnd;
  final ValueChanged<int>? onClipResizeCancel;
  final GestureDragStartCallback? onBackgroundPanStart;
  final GestureDragUpdateCallback? onBackgroundPanUpdate;
  final GestureDragEndCallback? onBackgroundPanEnd;
  final VoidCallback? onBackgroundPanCancel;
  final void Function(double bar, int lane)? onBackgroundTap;
  final void Function(Object data, double bar, int lane)? onDrop;
  final ValueChanged<Offset>? onScroll;
  final ValueChanged<Offset>? onPanZoom;
  final ValueChanged<double>? onSeekBar;
  final ValueChanged<String>? onSnapChanged;
  final ValueChanged<int>? onStartChanged;
  final ValueChanged<int>? onLengthChanged;
  final ValueChanged<int>? onOffsetChanged;
  final ValueChanged<bool>? onLoopToggle;
  final VoidCallback? onMuteToggle;
  final ValueChanged<int>? onTransposeChanged;
  final VoidCallback? onMakeUnique;
  final VoidCallback? onSplitByChannel;
  final ValueChanged<StretchMode>? onStretchModeChanged;
  final ValueChanged<bool>? onReverseToggle;
  final ValueChanged<double>? onSourceBpmChanged;
  final VoidCallback? onFitToTempo;
  final VoidCallback? onSplitAtPlayhead;
  final ValueChanged<String>? onLaneMute;
  final ValueChanged<String>? onLaneSolo;
  final ValueChanged<String>? onLaneCollapse;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      color: tokens.color.surfaceDeep,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PlaylistHeader(
                  title: vm.canvas.headerTitle,
                  right: vm.canvas.headerRight,
                  snap: vm.canvas.snapTicks == 0 ? 'Off' : _snapLabel(vm.canvas.snapTicks),
                  onSnapChanged: onSnapChanged,
                ),
                Container(height: tokens.border.hairline, color: tokens.color.line),
                Row(
                  children: <Widget>[
                    // The ruler strip names the bars; over the header column it
                    // names the column, so neither strip is an unlabelled band.
                    Container(
                      width: tokens.size.laneHeaderWidth,
                      height: tokens.size.playlistRulerHeight,
                      padding: EdgeInsets.only(left: tokens.spacing.md),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
                      ),
                      child: Text('TRACKS', style: tokens.type.microCapsWide),
                    ),
                    Expanded(
                      child: PlaylistRuler(
                        pxPerBar: vm.canvas.pxPerBar,
                        scrollTicks: vm.canvas.scrollTicks,
                        onSeekBar: onSeekBar,
                      ),
                    ),
                  ],
                ),
                Container(height: tokens.border.hairline, color: tokens.color.line),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      PlaylistLaneHeaders(
                        lanes: vm.canvas.lanes,
                        scrollLanes: vm.canvas.scrollLanes,
                        onMute: onLaneMute,
                        onSolo: onLaneSolo,
                        onCollapse: onLaneCollapse,
                      ),
                      Expanded(
                        child: PlaylistCanvas(
                          key: canvasKey,
                          vm: vm.canvas,
                          onClipTap: onClipTap,
                          onClipDoubleTap: onClipDoubleTap,
                          onClipPanStart: onClipPanStart,
                          onClipPanUpdate: onClipPanUpdate,
                          onClipPanEnd: onClipPanEnd,
                          onClipPanCancel: onClipPanCancel,
                          onClipResizeStart: onClipResizeStart,
                          onClipResizeUpdate: onClipResizeUpdate,
                          onClipResizeEnd: onClipResizeEnd,
                          onClipResizeCancel: onClipResizeCancel,
                          onBackgroundPanStart: onBackgroundPanStart,
                          onBackgroundPanUpdate: onBackgroundPanUpdate,
                          onBackgroundPanEnd: onBackgroundPanEnd,
                          onBackgroundPanCancel: onBackgroundPanCancel,
                          onBackgroundTap: onBackgroundTap,
                          onDrop: onDrop,
                          onScroll: onScroll,
                          onPanZoom: onPanZoom,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _PlaylistInspectorPanel(
            vm: vm.inspector,
            onStartChanged: onStartChanged,
            onLengthChanged: onLengthChanged,
            onOffsetChanged: onOffsetChanged,
            onLoopToggle: onLoopToggle,
            onMuteToggle: onMuteToggle,
            onTransposeChanged: onTransposeChanged,
            onMakeUnique: onMakeUnique,
            onSplitByChannel: onSplitByChannel,
            onStretchModeChanged: onStretchModeChanged,
            onReverseToggle: onReverseToggle,
            onSourceBpmChanged: onSourceBpmChanged,
            onFitToTempo: onFitToTempo,
            onSplitAtPlayhead: onSplitAtPlayhead,
          ),
        ],
      ),
    );
  }
}

/// The track header column down the playlist's left edge.
///
/// One header per lane, on the same 50px pitch as the canvas rows it labels —
/// including the same vertical scroll offset, or the names stop naming the
/// rows beside them the moment the arrangement is scrolled.
class PlaylistLaneHeaders extends StatelessWidget {
  const PlaylistLaneHeaders({
    required this.lanes,
    this.scrollLanes = 0,
    this.onMute,
    this.onSolo,
    this.onCollapse,
    super.key,
  });

  final List<PlaylistLaneVm> lanes;

  /// How far the canvas is scrolled, in lanes. Fractional: the canvas scrolls
  /// smoothly, so the headers have to as well.
  final double scrollLanes;

  final ValueChanged<String>? onMute;
  final ValueChanged<String>? onSolo;
  final ValueChanged<String>? onCollapse;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: tokens.size.laneHeaderWidth,
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        // The column's own edge, drawn once. Per-row borders would stop at the
        // last lane and leave the empty space below the column unbounded.
        border: Border(right: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
      ),
      child: ClipRect(
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -scrollLanes * tokens.size.playlistLaneHeight,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < lanes.length; i++)
                    _LaneHeaderRow(lane: lanes[i], index: i, onMute: onMute, onSolo: onSolo, onCollapse: onCollapse),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One track header: identity spine, disclosure, number, name over a caption,
/// then the mute and solo squares the rest of the app uses.
class _LaneHeaderRow extends StatefulWidget {
  const _LaneHeaderRow({required this.lane, required this.index, this.onMute, this.onSolo, this.onCollapse});

  final PlaylistLaneVm lane;
  final int index;
  final ValueChanged<String>? onMute;
  final ValueChanged<String>? onSolo;
  final ValueChanged<String>? onCollapse;

  @override
  State<_LaneHeaderRow> createState() => _LaneHeaderRowState();
}

class _LaneHeaderRowState extends State<_LaneHeaderRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final PlaylistLaneVm lane = widget.lane;

    // A muted lane keeps its colour but loses its ink: the row stays findable
    // in the column while reading as switched off.
    final Color nameInk = lane.muted ? color.textMuted : color.textPrimary;
    final Color spine = lane.muted ? color.mutedLaneSpine(lane.color) : lane.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: tokens.size.playlistLaneHeight,
        decoration: BoxDecoration(
          color: _hover ? color.surfaceHover : color.none,
          border: Border(bottom: BorderSide(color: color.line, width: tokens.border.hairline)),
        ),
        child: Row(
          children: <Widget>[
            Container(width: tokens.size.playlistLaneSpineWidth, height: double.infinity, color: spine),
            SizedBox(width: tokens.spacing.sm),
            _LaneDisclosure(
              collapsed: lane.collapsed,
              onTap: widget.onCollapse == null ? null : () => widget.onCollapse!(lane.id),
            ),
            SizedBox(width: tokens.spacing.xs),
            SizedBox(
              width: tokens.size.playlistLaneIndexWidth,
              child: Text('${widget.index + 1}', textAlign: TextAlign.right, style: tokens.type.numericSmall),
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    lane.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.rackName.copyWith(color: nameInk),
                  ),
                  Text(_caption(lane), maxLines: 1, overflow: TextOverflow.ellipsis, style: tokens.type.rackCaption),
                ],
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
            ObToggleChip(
              tone: ObToggleTone.mute,
              on: lane.muted,
              onTap: widget.onMute == null ? null : () => widget.onMute!(lane.id),
            ),
            SizedBox(width: tokens.spacing.xs),
            ObToggleChip(
              tone: ObToggleTone.solo,
              on: lane.soloed,
              onTap: widget.onSolo == null ? null : () => widget.onSolo!(lane.id),
            ),
            SizedBox(width: tokens.spacing.sm),
          ],
        ),
      ),
    );
  }

  /// What the lane holds, in the words the user would use for it.
  static String _caption(PlaylistLaneVm lane) {
    if (lane.muted) return 'Muted';
    if (lane.clipCount == 0) return 'Empty';
    return lane.clipCount == 1 ? '1 clip' : '${lane.clipCount} clips';
  }
}

/// The collapse triangle: right when collapsed, down when open, on a hit
/// target big enough to click without aiming at the 14px mark itself.
class _LaneDisclosure extends StatelessWidget {
  const _LaneDisclosure({required this.collapsed, this.onTap});

  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double side = tokens.size.playlistLaneDiscloseSize;

    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: side,
          height: tokens.size.playlistLaneHeight,
          child: Center(
            child: Transform.rotate(
              angle: collapsed ? 0 : math.pi / 2,
              child: SizedBox(
                width: side,
                height: side,
                child: CustomPaint(
                  painter: KitGlyphPainter(
                    kind: ObKitGlyphKind.chevronRight,
                    color: tokens.color.textMuted,
                    stroke: tokens.border.glyph,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _snapLabel(int ticks) {
  if (ticks == ticksPerBar * 4) return '4 bars';
  if (ticks == ticksPerBar) return '1 bar';
  if (ticks == ticksPerQuarter) return '1/4';
  if (ticks == ticksPerQuarter ~/ 2) return '1/8';
  if (ticks == ticksPerQuarter ~/ 4) return '1/16';
  return 'Custom';
}

class _PlaylistInspectorPanel extends StatelessWidget {
  const _PlaylistInspectorPanel({
    required this.vm,
    this.onStartChanged,
    this.onLengthChanged,
    this.onOffsetChanged,
    this.onLoopToggle,
    this.onMuteToggle,
    this.onTransposeChanged,
    this.onMakeUnique,
    this.onSplitByChannel,
    this.onStretchModeChanged,
    this.onReverseToggle,
    this.onSourceBpmChanged,
    this.onFitToTempo,
    this.onSplitAtPlayhead,
  });

  final ClipInspectorVm vm;
  final ValueChanged<int>? onStartChanged;
  final ValueChanged<int>? onLengthChanged;
  final ValueChanged<int>? onOffsetChanged;
  final ValueChanged<bool>? onLoopToggle;
  final VoidCallback? onMuteToggle;
  final ValueChanged<int>? onTransposeChanged;
  final VoidCallback? onMakeUnique;
  final VoidCallback? onSplitByChannel;
  final ValueChanged<StretchMode>? onStretchModeChanged;
  final ValueChanged<bool>? onReverseToggle;
  final ValueChanged<double>? onSourceBpmChanged;
  final VoidCallback? onFitToTempo;
  final VoidCallback? onSplitAtPlayhead;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      width: tokens.size.clipInspectorWidth,
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(left: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
      ),
      child: SingleChildScrollView(
        child:
            vm.isEmpty
                ? const _EmptyInspectorContent()
                : (vm.isMulti
                    ? _MultiInspectorContent(count: vm.selectedCount, onMakeUnique: onMakeUnique)
                    : _SingleClipInspectorContent(
                      vm: vm,
                      onStartChanged: onStartChanged,
                      onLengthChanged: onLengthChanged,
                      onOffsetChanged: onOffsetChanged,
                      onLoopToggle: onLoopToggle,
                      onMuteToggle: onMuteToggle,
                      onTransposeChanged: onTransposeChanged,
                      onMakeUnique: onMakeUnique,
                      onSplitByChannel: onSplitByChannel,
                      onStretchModeChanged: onStretchModeChanged,
                      onReverseToggle: onReverseToggle,
                      onSourceBpmChanged: onSourceBpmChanged,
                      onFitToTempo: onFitToTempo,
                      onSplitAtPlayhead: onSplitAtPlayhead,
                    )),
      ),
    );
  }
}

class _EmptyInspectorContent extends StatelessWidget {
  const _EmptyInspectorContent();

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('CLIP', style: tokens.type.label),
        SizedBox(height: tokens.spacing.sm),
        Text(
          'Select a clip to window, loop or transpose it.',
          style: tokens.type.body.copyWith(color: tokens.color.textMuted),
        ),
      ],
    );
  }
}

class _MultiInspectorContent extends StatelessWidget {
  const _MultiInspectorContent({required this.count, this.onMakeUnique});

  final int count;
  final VoidCallback? onMakeUnique;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$count CLIPS', style: tokens.type.label),
        SizedBox(height: tokens.spacing.md),
        ObButton(label: 'Make unique', onTap: onMakeUnique, width: double.infinity),
        SizedBox(height: tokens.spacing.sm),
        Text('Clones selected pattern-clips so edits do not affect other copies.', style: tokens.type.label),
      ],
    );
  }
}

class _SingleClipInspectorContent extends StatelessWidget {
  const _SingleClipInspectorContent({
    required this.vm,
    this.onStartChanged,
    this.onLengthChanged,
    this.onOffsetChanged,
    this.onLoopToggle,
    this.onMuteToggle,
    this.onTransposeChanged,
    this.onMakeUnique,
    this.onSplitByChannel,
    this.onStretchModeChanged,
    this.onReverseToggle,
    this.onSourceBpmChanged,
    this.onFitToTempo,
    this.onSplitAtPlayhead,
  });

  final ClipInspectorVm vm;
  final ValueChanged<int>? onStartChanged;
  final ValueChanged<int>? onLengthChanged;
  final ValueChanged<int>? onOffsetChanged;
  final ValueChanged<bool>? onLoopToggle;
  final VoidCallback? onMuteToggle;
  final ValueChanged<int>? onTransposeChanged;
  final VoidCallback? onMakeUnique;
  final VoidCallback? onSplitByChannel;
  final ValueChanged<StretchMode>? onStretchModeChanged;
  final ValueChanged<bool>? onReverseToggle;
  final ValueChanged<double>? onSourceBpmChanged;
  final VoidCallback? onFitToTempo;
  final VoidCallback? onSplitAtPlayhead;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('CLIP', style: tokens.type.label),
        SizedBox(height: tokens.spacing.xs),
        Row(
          children: <Widget>[
            Container(
              width: tokens.size.swatchSize,
              height: tokens.size.swatchSize,
              decoration: BoxDecoration(color: vm.color, borderRadius: BorderRadius.all(tokens.radius.sm)),
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(child: Text(vm.name, overflow: TextOverflow.ellipsis, style: tokens.type.title)),
          ],
        ),
        SizedBox(height: tokens.spacing.xs),
        Text(vm.usageText, style: tokens.type.label),
        const _InspectorDivider(),
        _InspectorStepperRow(
          label: 'Start',
          value: '${vm.startBar} bar',
          onMinus: onStartChanged == null ? null : () => onStartChanged!(vm.startBar - 1),
          onPlus: onStartChanged == null ? null : () => onStartChanged!(vm.startBar + 1),
        ),
        SizedBox(height: tokens.spacing.sm),
        _InspectorStepperRow(
          label: 'Length',
          value: '${vm.lengthBars} bar',
          onMinus: onLengthChanged == null ? null : () => onLengthChanged!(vm.lengthBars - 1),
          onPlus: onLengthChanged == null ? null : () => onLengthChanged!(vm.lengthBars + 1),
        ),
        SizedBox(height: tokens.spacing.sm),
        _InspectorStepperRow(
          label: 'Offset',
          value: '${vm.offsetBeats} beat',
          onMinus: onOffsetChanged == null ? null : () => onOffsetChanged!(vm.offsetBeats - 1),
          onPlus: onOffsetChanged == null ? null : () => onOffsetChanged!(vm.offsetBeats + 1),
        ),
        const _InspectorDivider(),
        Row(
          children: <Widget>[
            Expanded(child: Text('Loop', style: tokens.type.label)),
            GestureDetector(
              onTap: onLoopToggle == null ? null : () => onLoopToggle!(!vm.loop),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs, vertical: tokens.spacing.xxs),
                decoration: BoxDecoration(
                  color: vm.loop ? tokens.color.accentWash : tokens.color.surfaceWell,
                  borderRadius: BorderRadius.all(tokens.radius.sm),
                  border: Border.all(
                    color: vm.loop ? tokens.color.accent : tokens.color.lineStrong,
                    width: tokens.border.hairline,
                  ),
                ),
                child: Text(
                  vm.loop ? 'LOOP' : 'HOLD',
                  style: tokens.type.tag.copyWith(color: vm.loop ? tokens.color.accentBright : tokens.color.textMuted),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.sm),
        Row(
          children: <Widget>[
            Expanded(child: Text('Mute', style: tokens.type.label)),
            ObToggleChip(tone: ObToggleTone.mute, on: vm.muted, onTap: onMuteToggle),
          ],
        ),
        if (!vm.isAudio) ...<Widget>[
          const _InspectorDivider(),
          _InspectorStepperRow(
            label: 'Transpose',
            value: '${vm.transpose > 0 ? "+" : ""}${vm.transpose} st',
            onMinus: onTransposeChanged == null ? null : () => onTransposeChanged!(vm.transpose - 1),
            onPlus: onTransposeChanged == null ? null : () => onTransposeChanged!(vm.transpose + 1),
          ),
          SizedBox(height: tokens.spacing.xs),
          Text('Non-destructive: the pattern is untouched.', style: tokens.type.label),
          SizedBox(height: tokens.spacing.md),
          ObButton(label: 'Make unique', onTap: onMakeUnique, width: double.infinity),
          SizedBox(height: tokens.spacing.xs),
          Text(
            vm.isShared ? 'Creates a unique clone of this pattern.' : 'This clip already has the pattern to itself.',
            style: tokens.type.label,
          ),
          SizedBox(height: tokens.spacing.md),
          ObButton(label: 'Split by channel', onTap: onSplitByChannel, width: double.infinity),
          SizedBox(height: tokens.spacing.xs),
          Text('Gives every channel in the pattern its own pattern, on its own track.', style: tokens.type.label),
        ],
        if (vm.isAudio) ...<Widget>[
          const _InspectorDivider(),
          Text('STRETCH', style: tokens.type.label),
          SizedBox(height: tokens.spacing.xs),
          // Three exclusive modes, all visible. A dropdown would hide the fact
          // that resizing means something different in each of them, which is
          // the one thing a user has to know here.
          Row(
            children: <Widget>[
              for (final StretchMode mode in StretchMode.values)
                Padding(
                  padding: EdgeInsets.only(right: tokens.spacing.xs),
                  child: _InspectorPill(
                    label: switch (mode) {
                      StretchMode.off => 'TRIM',
                      StretchMode.resample => 'SPEED',
                      StretchMode.stretch => 'STRETCH',
                    },
                    active: vm.stretchMode == mode,
                    onTap: onStretchModeChanged == null ? null : () => onStretchModeChanged!(mode),
                  ),
                ),
            ],
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            switch (vm.stretchMode) {
              StretchMode.off => 'Resizing trims. Past the end is silence.',
              StretchMode.resample => 'Resizing changes the speed, and the pitch with it.',
              StretchMode.stretch => 'Resizing changes the length. The pitch stays put.',
            },
            style: tokens.type.label,
          ),
          const _InspectorDivider(),
          Row(
            children: <Widget>[
              Expanded(child: Text('Reverse', style: tokens.type.label)),
              _InspectorPill(
                label: vm.reversed ? 'ON' : 'OFF',
                active: vm.reversed,
                onTap: onReverseToggle == null ? null : () => onReverseToggle!(!vm.reversed),
              ),
            ],
          ),
          const _InspectorDivider(),
          _InspectorStepperRow(
            label: 'Source tempo',
            value: vm.sourceBpm > 0 ? '${vm.sourceBpm.toStringAsFixed(1)} bpm' : 'unknown',
            onMinus: onSourceBpmChanged == null
                ? null
                : () => onSourceBpmChanged!(vm.sourceBpm <= 0 ? 120 : vm.sourceBpm - 1),
            onPlus: onSourceBpmChanged == null
                ? null
                : () => onSourceBpmChanged!(vm.sourceBpm <= 0 ? 120 : vm.sourceBpm + 1),
          ),
          SizedBox(height: tokens.spacing.md),
          ObButton(
            label: 'Fit to tempo',
            onTap: vm.canFitToTempo ? onFitToTempo : null,
            width: double.infinity,
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            vm.canFitToTempo
                ? 'Stretches the clip so it plays at the project tempo.'
                : 'Set the source tempo first — fitting without one would be a guess.',
            style: tokens.type.label,
          ),
          SizedBox(height: tokens.spacing.md),
          ObButton(label: 'Cut at playhead', onTap: onSplitAtPlayhead, width: double.infinity),
          SizedBox(height: tokens.spacing.xs),
          Text('The right half resumes where the left one stopped.', style: tokens.type.label),
        ],
      ],
    );
  }
}

/// A small on/off pill. The inspector's loop control paints one inline; this is
/// the same shape, named, because the audio section needs four of them.
class _InspectorPill extends StatelessWidget {
  const _InspectorPill({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs, vertical: tokens.spacing.xxs),
        decoration: BoxDecoration(
          color: active ? tokens.color.accentWash : tokens.color.surfaceWell,
          borderRadius: BorderRadius.all(tokens.radius.sm),
          border: Border.all(
            color: active ? tokens.color.accent : tokens.color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
        child: Text(
          label,
          style: tokens.type.tag.copyWith(
            color: active ? tokens.color.accentBright : tokens.color.textMuted,
          ),
        ),
      ),
    );
  }
}

class _InspectorDivider extends StatelessWidget {
  const _InspectorDivider();

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
      child: Container(height: tokens.border.hairline, color: tokens.color.line),
    );
  }
}

class _InspectorStepperRow extends StatelessWidget {
  const _InspectorStepperRow({required this.label, required this.value, this.onMinus, this.onPlus});

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: tokens.type.label)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm, vertical: tokens.spacing.xxs),
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(onTap: onMinus, child: Text('−', style: tokens.type.numeric)),
              SizedBox(width: tokens.spacing.sm),
              Text(value, style: tokens.type.numeric),
              SizedBox(width: tokens.spacing.sm),
              GestureDetector(onTap: onPlus, child: Text('+', style: tokens.type.numeric)),
            ],
          ),
        ),
      ],
    );
  }
}
