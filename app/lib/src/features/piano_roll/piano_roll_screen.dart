// PianoRollScreen — the piano roll workspace surface (UI-C-03, UI-D-03).
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'key_column.dart';
import 'note_grid.dart';
import 'piano_roll_screen_vm.dart';
import 'pr_scrollbar.dart';
import 'pr_toolbar.dart';
import 'velocity_lane.dart';

/// The lowest and highest MIDI keys the roll can scroll to. The vertical rail's
/// track is this whole range, which is what lets the thumb say "you are near
/// the top of the keyboard" rather than only "you can scroll".
const int prLowestKey = 0;
const int prHighestKey = 127;
const int prKeyCount = prHighestKey - prLowestKey + 1;

/// The pointers a canvas drag will accept — every kind but
/// [PointerDeviceKind.trackpad].
///
/// A trackpad's two-finger scroll is delivered as a pan gesture, which a drag
/// recogniser accepts by default. On an editing surface that means scrolling
/// silently draws. Trackpad scrolling is handled as a pan/zoom signal instead.
const Set<PointerDeviceKind> prCanvasPointers = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

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
    this.onPointerPanZoomStart,
    this.onPointerPanZoomUpdate,
    this.onPointerPanZoomEnd,
    this.onLaneChanged,
    this.onVelocityTapDown,
    this.onVelocityDragStart,
    this.onVelocityDragUpdate,
    this.onVelocityDragEnd,
    this.onScrollTicks,
    this.onScrollTopKey,
    this.onGridSize,
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

  /// Trackpad gestures. Separate from [onPointerSignal] because a trackpad
  /// two-finger scroll is a pan/zoom gesture at the framework level, not a
  /// scroll signal.
  final void Function(PointerPanZoomStartEvent event)? onPointerPanZoomStart;
  final void Function(PointerPanZoomUpdateEvent event)? onPointerPanZoomUpdate;
  final void Function(PointerPanZoomEndEvent event)? onPointerPanZoomEnd;

  final ValueChanged<String>? onLaneChanged;
  final void Function(TapDownDetails details, double height)? onVelocityTapDown;
  final VoidCallback? onVelocityDragStart;
  final void Function(DragUpdateDetails details, double height)?
      onVelocityDragUpdate;
  final VoidCallback? onVelocityDragEnd;

  /// The scroll rails report absolute positions: a tick for the horizontal
  /// rail, a top MIDI key for the vertical one — the same two fields the
  /// viewport is built from, so there is no second scroll model to keep in
  /// sync.
  final ValueChanged<double>? onScrollTicks;
  final ValueChanged<int>? onScrollTopKey;

  /// The measured canvas, reported up so keyboard paging and zoom anchoring can
  /// work in the units the user sees rather than guessing at a viewport size.
  final ValueChanged<Size>? onGridSize;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    if (!vm.hasInstrument) {
      return _EmptyPianoRoll(message: vm.emptyMessage);
    }

    final double railThickness = tokens.size.prScrollbarThickness;

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
          //
          // A trackpad reports a two-finger scroll as a *pan/zoom gesture*, not
          // as a scroll signal, so it needs its own three callbacks. Without
          // them the gesture fell through to the canvas's drag recogniser and
          // two-finger scrolling drew notes.
          Expanded(
            child: Listener(
              onPointerSignal: onPointerSignal,
              onPointerPanZoomStart: onPointerPanZoomStart,
              onPointerPanZoomUpdate: onPointerPanZoomUpdate,
              onPointerPanZoomEnd: onPointerPanZoomEnd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _RulerRow(
                    viewport: vm.roll.viewport,
                    railThickness: railThickness,
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
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
                            onGridSize: onGridSize,
                          ),
                        ),
                        _VerticalRail(
                          viewport: vm.roll.viewport,
                          onScrollTopKey: onScrollTopKey,
                        ),
                      ],
                    ),
                  ),
                  _HorizontalRail(
                    viewport: vm.roll.viewport,
                    contentEndTicks: vm.contentEndTicks,
                    railThickness: railThickness,
                    onScrollTicks: onScrollTicks,
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
            onVelocityDragStart: onVelocityDragStart,
            onVelocityDragUpdate: onVelocityDragUpdate,
            onVelocityDragEnd: onVelocityDragEnd,
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
  const _RulerRow({required this.viewport, required this.railThickness});

  final PrViewport viewport;
  final double railThickness;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(width: tokens.size.prKeyColumnWidth),
        Expanded(child: PrBarRuler(viewport: viewport)),
        // Holds the ruler off the vertical rail so a bar number never sits
        // half-under the thumb.
        SizedBox(width: railThickness),
      ],
    );
  }
}

/// The vertical rail. Its track is the whole keyboard, and its position is the
/// top row — MIDI keys count *down* the screen, so the offset is inverted here
/// rather than everywhere the rail is used.
class _VerticalRail extends StatelessWidget {
  const _VerticalRail({required this.viewport, this.onScrollTopKey});

  final PrViewport viewport;
  final ValueChanged<int>? onScrollTopKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double rows = viewport.rowHeight <= 0
            ? 1
            : constraints.maxHeight / viewport.rowHeight;
        final ValueChanged<int>? notify = onScrollTopKey;
        return PrScrollbar(
          axis: Axis.vertical,
          offset: (prHighestKey - viewport.topMidiNote).toDouble(),
          viewportExtent: rows,
          contentExtent: prKeyCount.toDouble(),
          onOffsetChanged: notify == null
              ? null
              : (double offset) =>
                  notify((prHighestKey - offset.round()).clamp(
                    prLowestKey,
                    prHighestKey,
                  )),
        );
      },
    );
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({
    required this.viewport,
    required this.contentEndTicks,
    required this.railThickness,
    this.onScrollTicks,
  });

  final PrViewport viewport;
  final int contentEndTicks;
  final double railThickness;
  final ValueChanged<double>? onScrollTicks;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      height: railThickness,
      child: Row(
        children: <Widget>[
          SizedBox(width: tokens.size.prKeyColumnWidth),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double visibleTicks =
                    constraints.maxWidth * viewport.ticksPerPx;
                return PrScrollbar(
                  axis: Axis.horizontal,
                  offset: viewport.firstVisibleTick.toDouble(),
                  viewportExtent: visibleTicks,
                  // Never shorter than what is on screen, so the thumb fills
                  // the track instead of inverting when a pattern is empty.
                  contentExtent: contentEndTicks < visibleTicks
                      ? visibleTicks
                      : contentEndTicks.toDouble(),
                  onOffsetChanged: onScrollTicks,
                );
              },
            ),
          ),
          SizedBox(width: railThickness),
        ],
      ),
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
    this.onGridSize,
  });

  final PianoRollVm roll;
  final ValueChanged<int>? onKeyPress;
  final void Function(TapDownDetails details)? onTapDown;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details)? onPanUpdate;
  final void Function(DragEndDetails details)? onPanEnd;
  final VoidCallback? onPanCancel;
  final ValueChanged<Size>? onGridSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrKeyColumn(
          viewport: roll.viewport,
          onKeyPress: onKeyPress,
          activeKeys: roll.activeKeys,
        ),
        Expanded(
          child: _InteractiveGridArea(
            roll: roll,
            onTapDown: onTapDown,
            onSecondaryTapDown: onSecondaryTapDown,
            onPanStart: onPanStart,
            onPanUpdate: onPanUpdate,
            onPanEnd: onPanEnd,
            onPanCancel: onPanCancel,
            onGridSize: onGridSize,
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
    this.onGridSize,
  });

  final PianoRollVm roll;
  final void Function(TapDownDetails details)? onTapDown;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details)? onPanUpdate;
  final void Function(DragEndDetails details)? onPanEnd;
  final VoidCallback? onPanCancel;
  final ValueChanged<Size>? onGridSize;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final ValueChanged<Size>? report = onGridSize;
        if (report != null) {
          final Size size = Size(constraints.maxWidth, constraints.maxHeight);
          // Reported after the frame: the listener drives state the roll is
          // mid-build with, and writing to it during layout would be a rebuild
          // inside a rebuild.
          WidgetsBinding.instance.addPostFrameCallback((_) => report(size));
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Everything that can point at a canvas *except* a trackpad. A
          // trackpad two-finger scroll arrives as a pan gesture, and a drag
          // recogniser will happily accept it — which is how scrolling ended up
          // drawing notes. Scrolling is handled by the Listener above instead.
          supportedDevices: prCanvasPointers,
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
      },
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
    this.onVelocityDragStart,
    this.onVelocityDragUpdate,
    this.onVelocityDragEnd,
  });

  final PianoRollVm roll;
  final String lane;
  final List<String> lanes;
  final ValueChanged<String>? onLaneChanged;
  final void Function(TapDownDetails details, double height)? onVelocityTapDown;
  final VoidCallback? onVelocityDragStart;
  final void Function(DragUpdateDetails details, double height)?
      onVelocityDragUpdate;
  final VoidCallback? onVelocityDragEnd;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double laneHeight = tokens.size.prVelocityLaneHeight;
    final bool editable = PrLaneKind.fromLabel(lane).available;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: prCanvasPointers,
      onTapDown: onVelocityTapDown == null || !editable
          ? null
          : (TapDownDetails d) => onVelocityTapDown!(d, laneHeight),
      // A pan rather than a vertical drag: dragging sideways across the lane
      // is how you shape a run of notes in one gesture, and a vertical-only
      // recogniser gave that gesture up to the roll behind it.
      onPanStart: !editable ? null : (_) => onVelocityDragStart?.call(),
      onPanUpdate: onVelocityDragUpdate == null || !editable
          ? null
          : (DragUpdateDetails d) => onVelocityDragUpdate!(d, laneHeight),
      onPanEnd: !editable ? null : (_) => onVelocityDragEnd?.call(),
      onPanCancel: !editable ? null : onVelocityDragEnd,
      child: PrVelocityLane(
        vm: roll,
        lane: lane,
        lanes: lanes,
        onLaneChanged: onLaneChanged,
      ),
    );
  }
}
