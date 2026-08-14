// PianoRollScreen — the piano roll workspace surface (UI-C-03, UI-D-03).
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'key_column.dart';
import 'note_grid.dart';
import 'piano_roll_screen_vm.dart';
import 'pr_toolbar.dart';
import 'velocity_lane.dart';

class PianoRollScreen extends StatelessWidget {
  const PianoRollScreen({
    required this.vm,
    this.onPattern,
    this.onTool,
    this.onScale,
    this.onSnap,
    this.onZoomIn,
    this.onZoomOut,
    this.onBack,
    this.onKeyPress,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.onPointerSignal,
    this.onLaneChanged,
    this.onVelocityTapDown,
    this.onVelocityDragUpdate,
    super.key,
  });

  final PianoRollScreenVm vm;
  final ValueChanged<String>? onPattern;
  final ValueChanged<PrTool>? onTool;
  final ValueChanged<String>? onScale;
  final ValueChanged<String>? onSnap;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onBack;
  final ValueChanged<int>? onKeyPress;

  final void Function(TapDownDetails details)? onTapDown;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details)? onPanUpdate;
  final void Function(DragEndDetails details)? onPanEnd;
  final VoidCallback? onPanCancel;
  final void Function(PointerSignalEvent event)? onPointerSignal;

  final ValueChanged<String>? onLaneChanged;
  final void Function(TapDownDetails details, double height)? onVelocityTapDown;
  final void Function(DragUpdateDetails details, double height)?
      onVelocityDragUpdate;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    if (!vm.hasInstrument) {
      return _EmptyPianoRoll(message: vm.emptyMessage);
    }

    return ColoredBox(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PrToolbar(
            vm: vm.toolbar,
            channelColor: vm.channelColor,
            onPattern: onPattern,
            onTool: onTool,
            onScale: onScale,
            onSnap: onSnap,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onBack: onBack,
          ),
          // The whole body scrolls as one: wheel or trackpad anywhere over the
          // ruler, the key column or the canvas pans the viewport.
          Expanded(
            child: Listener(
              onPointerSignal: onPointerSignal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _RulerRow(viewport: vm.roll.viewport),
                  Expanded(
                    child: _GridRow(
                      roll: vm.roll,
                      onKeyPress: onKeyPress,
                      onTapDown: onTapDown,
                      onSecondaryTapDown: onSecondaryTapDown,
                      onPanStart: onPanStart,
                      onPanUpdate: onPanUpdate,
                      onPanEnd: onPanEnd,
                      onPanCancel: onPanCancel,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _InteractiveVelocityArea(
            roll: vm.roll,
            lane: vm.velocityLane,
            lanes: vm.velocityLanes,
            onLaneChanged: onLaneChanged,
            onVelocityTapDown: onVelocityTapDown,
            onVelocityDragUpdate: onVelocityDragUpdate,
          ),
        ],
      ),
    );
  }
}

class _EmptyPianoRoll extends StatelessWidget {
  const _EmptyPianoRoll({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      color: tokens.color.surfaceDeep,
      alignment: Alignment.center,
      child: SizedBox(
        width: tokens.size.proseWidth,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: tokens.type.body.copyWith(color: tokens.color.textMuted),
        ),
      ),
    );
  }
}

class _RulerRow extends StatelessWidget {
  const _RulerRow({required this.viewport});

  final PrViewport viewport;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(width: tokens.size.prKeyColumnWidth),
        Expanded(child: PrBarRuler(viewport: viewport)),
      ],
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.roll,
    this.onKeyPress,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
  });

  final PianoRollVm roll;
  final ValueChanged<int>? onKeyPress;
  final void Function(TapDownDetails details)? onTapDown;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details)? onPanUpdate;
  final void Function(DragEndDetails details)? onPanEnd;
  final VoidCallback? onPanCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrKeyColumn(viewport: roll.viewport, onKeyPress: onKeyPress),
        Expanded(
          child: _InteractiveGridArea(
            roll: roll,
            onTapDown: onTapDown,
            onSecondaryTapDown: onSecondaryTapDown,
            onPanStart: onPanStart,
            onPanUpdate: onPanUpdate,
            onPanEnd: onPanEnd,
            onPanCancel: onPanCancel,
          ),
        ),
      ],
    );
  }
}

class _InteractiveGridArea extends StatelessWidget {
  const _InteractiveGridArea({
    required this.roll,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
  });

  final PianoRollVm roll;
  final void Function(TapDownDetails details)? onTapDown;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details)? onPanUpdate;
  final void Function(DragEndDetails details)? onPanEnd;
  final VoidCallback? onPanCancel;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      onPanCancel: onPanCancel,
      child: ClipRect(
        child: CustomPaint(
          painter: PrGridPainter(
            vm: roll,
            color: tokens.color,
            noteHeight: tokens.size.prNoteHeight,
            noteRadius: tokens.radius.xs,
            lineWidth: tokens.border.hairline,
            playheadWidth: tokens.size.playheadWidth,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _InteractiveVelocityArea extends StatelessWidget {
  const _InteractiveVelocityArea({
    required this.roll,
    required this.lane,
    required this.lanes,
    this.onLaneChanged,
    this.onVelocityTapDown,
    this.onVelocityDragUpdate,
  });

  final PianoRollVm roll;
  final String lane;
  final List<String> lanes;
  final ValueChanged<String>? onLaneChanged;
  final void Function(TapDownDetails details, double height)? onVelocityTapDown;
  final void Function(DragUpdateDetails details, double height)?
      onVelocityDragUpdate;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double laneHeight = tokens.size.prVelocityLaneHeight;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onVelocityTapDown == null
          ? null
          : (TapDownDetails d) => onVelocityTapDown!(d, laneHeight),
      onVerticalDragUpdate: onVelocityDragUpdate == null
          ? null
          : (DragUpdateDetails d) => onVelocityDragUpdate!(d, laneHeight),
      child: PrVelocityLane(
        vm: roll,
        lane: lane,
        lanes: lanes,
        onLaneChanged: onLaneChanged,
      ),
    );
  }
}
