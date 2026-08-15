// PlaylistScreen — the complete playlist workspace view (UI-C-04 / UI-D-04).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
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
                    SizedBox(width: tokens.size.laneHeaderWidth),
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
          ),
        ],
      ),
    );
  }
}

class PlaylistLaneHeaders extends StatelessWidget {
  const PlaylistLaneHeaders({required this.lanes, this.onMute, this.onSolo, this.onCollapse, super.key});

  final List<PlaylistLaneVm> lanes;
  final ValueChanged<String>? onMute;
  final ValueChanged<String>? onSolo;
  final ValueChanged<String>? onCollapse;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.laneHeaderWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final PlaylistLaneVm lane in lanes)
            SizedBox(
              height: tokens.size.playlistLaneHeight,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
                decoration: BoxDecoration(
                  color: tokens.color.surfacePanel,
                  border: Border(
                    right: BorderSide(color: tokens.color.line, width: tokens.border.hairline),
                    bottom: BorderSide(color: tokens.color.line, width: tokens.border.hairline),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      onTap: onCollapse == null ? null : () => onCollapse!(lane.id),
                      child: Text(lane.collapsed ? '>' : 'v', style: tokens.type.label),
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    Container(
                      width: tokens.size.swatchSize,
                      height: tokens.size.swatchSize,
                      decoration: BoxDecoration(color: lane.color, borderRadius: BorderRadius.all(tokens.radius.sm)),
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    Expanded(child: Text(lane.name, overflow: TextOverflow.ellipsis, style: tokens.type.label)),
                    GestureDetector(
                      onTap: onMute == null ? null : () => onMute!(lane.id),
                      child: Text(
                        'M',
                        style: tokens.type.tag.copyWith(
                          color: lane.muted ? tokens.color.danger : tokens.color.textMuted,
                        ),
                      ),
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    GestureDetector(
                      onTap: onSolo == null ? null : () => onSolo!(lane.id),
                      child: Text(
                        'S',
                        style: tokens.type.tag.copyWith(
                          color: lane.soloed ? tokens.color.warning : tokens.color.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
  });

  final ClipInspectorVm vm;
  final ValueChanged<int>? onStartChanged;
  final ValueChanged<int>? onLengthChanged;
  final ValueChanged<int>? onOffsetChanged;
  final ValueChanged<bool>? onLoopToggle;
  final VoidCallback? onMuteToggle;
  final ValueChanged<int>? onTransposeChanged;
  final VoidCallback? onMakeUnique;

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
  });

  final ClipInspectorVm vm;
  final ValueChanged<int>? onStartChanged;
  final ValueChanged<int>? onLengthChanged;
  final ValueChanged<int>? onOffsetChanged;
  final ValueChanged<bool>? onLoopToggle;
  final VoidCallback? onMuteToggle;
  final ValueChanged<int>? onTransposeChanged;
  final VoidCallback? onMakeUnique;

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
        ],
      ],
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
