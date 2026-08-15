// PlaylistCanvas — the free-form arrangement surface (UI-B-08).
//
// Clips are positioned from `(startBar, lane)` on a gridline background, with
// the playhead drawn over everything. Free-form on purpose: there are no lane
// headers and no track list, because in this design a clip's lane is where you
// put it, not a row you had to create first.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../browser/sample_pack.dart';
import 'clip_card.dart';
import 'playlist_store.dart';

@immutable
class PlaylistVm {
  const PlaylistVm({
    required this.clips,
    required this.pxPerBar,
    this.playheadBar16ths,
    this.laneCountOverride,
    this.scrollTicks = 0,
    this.scrollLanes = 0,
    this.snapTicks = ticksPerBar,
    this.marqueeRect,
    this.headerTitle = 'Playlist',
    this.headerRight = '',
  });

  final List<ClipVm> clips;

  /// Horizontal zoom. A double so a zoom step never has to round to a whole
  /// pixel per bar.
  final double pxPerBar;

  /// The playhead, in sixteenths of a bar from the start; null hides it.
  /// Sixteenths rather than bars because that is the finest thing the
  /// transport reports, and a playhead that can only stop on a bar line is
  /// a playhead nobody believes.
  final int? playheadBar16ths;

  /// The model's lanes include empty rows, so the binding can provide the
  /// actual count instead of deriving it only from clips already placed.
  final int? laneCountOverride;

  /// The viewport origin. These are deliberately not bounded by content: the
  /// user can pan into empty future bars and lanes and place the next item
  /// there.
  final double scrollTicks;
  final double scrollLanes;
  final int snapTicks;

  /// The current Alt/⌘ rubber-band selection in canvas coordinates.
  final Rect? marqueeRect;

  final String headerTitle;

  /// `Untitled.onebeat · 124 BPM · 4/4`.
  final String headerRight;

  /// The lane count the canvas has to make room for.
  int get laneCount {
    if (laneCountOverride != null) return laneCountOverride!;
    if (clips.isEmpty) return 0;
    return clips.map((ClipVm c) => c.lane).reduce((int a, int b) => a > b ? a : b) + 1;
  }
}

class PlaylistCanvas extends StatelessWidget {
  const PlaylistCanvas({
    required this.vm,
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
    super.key,
  });

  final PlaylistVm vm;
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

  /// Fired with the (bar, lane) of a tap on empty canvas — fractional bar,
  /// because snapping is the store's decision, not the canvas's.
  final void Function(double bar, int lane)? onBackgroundTap;

  /// Fired when a browser asset is dropped onto empty playlist space.
  final void Function(Object data, double bar, int lane)? onDrop;

  /// Scroll deltas are translated by the binding into the store's unbounded
  /// tick/lane viewport.
  final ValueChanged<Offset>? onScroll;
  final ValueChanged<Offset>? onPanZoom;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final SizeTokens size = tokens.size;

    final Widget surface = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onBackgroundTap == null
          ? null
          : (TapUpDetails details) => onBackgroundTap!(
              details.localPosition.dx / vm.pxPerBar + vm.scrollTicks / ticksPerBar.toDouble(),
              (details.localPosition.dy / size.playlistLaneHeight + vm.scrollLanes).floor(),
            ),
      onPanStart: onBackgroundPanStart,
      onPanUpdate: onBackgroundPanUpdate,
      onPanEnd: onBackgroundPanEnd,
      onPanCancel: onBackgroundPanCancel,
      child: CustomPaint(
        painter: _PlaylistBackgroundPainter(
          pxPerBar: vm.pxPerBar,
          labelEvery: size.playlistBarLabelEvery,
          gridLine: tokens.color.gridLine,
          lineWidth: tokens.border.hairline,
          scrollBars: vm.scrollTicks / ticksPerBar.toDouble(),
          scrollLanes: vm.scrollLanes,
          laneHeight: size.playlistLaneHeight,
          snapTicks: vm.snapTicks,
        ),
        foregroundPainter: vm.playheadBar16ths == null
            ? null
            : _PlayheadPainter(
                x: vm.playheadBar16ths! * vm.pxPerBar / 16 - vm.scrollTicks / ticksPerBar.toDouble() * vm.pxPerBar,
                color: tokens.color.playhead,
                width: size.playheadWidth,
              ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            if (vm.marqueeRect != null)
              Positioned.fromRect(
                rect: vm.marqueeRect!,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.color.marqueeFill,
                      border: Border.all(
                        color: tokens.color.accentOutline,
                        width: tokens.border.hairline,
                      ),
                    ),
                  ),
                ),
              ),
            for (final ClipVm clip in vm.clips)
              Positioned(
                left: (clip.startBar - vm.scrollTicks / ticksPerBar.toDouble()) * vm.pxPerBar,
                top:
                    (clip.lane - vm.scrollLanes) * size.playlistLaneHeight +
                    (size.playlistLaneHeight - size.playlistClipHeight) / 2,
                width: clip.lengthBars * vm.pxPerBar,
                height: size.playlistClipHeight,
                child: ObClipCard(
                  vm: clip,
                  onTap: onClipTap == null ? null : () => onClipTap!(clip.id),
                  onDoubleTap: onClipDoubleTap == null ? null : () => onClipDoubleTap!(clip.id),
                  onPanStart: onClipPanStart == null
                      ? null
                      : (DragStartDetails details) => onClipPanStart!(clip.id, details),
                  onPanUpdate: onClipPanUpdate == null
                      ? null
                      : (DragUpdateDetails details) => onClipPanUpdate!(clip.id, details),
                  onPanEnd: onClipPanEnd == null ? null : (DragEndDetails details) => onClipPanEnd!(clip.id, details),
                  onPanCancel: onClipPanCancel == null ? null : () => onClipPanCancel!(clip.id),
                  onResizeStart: onClipResizeStart == null
                      ? null
                      : (DragStartDetails details) => onClipResizeStart!(clip.id, details),
                  onResizeUpdate: onClipResizeUpdate == null
                      ? null
                      : (DragUpdateDetails details) => onClipResizeUpdate!(clip.id, details),
                  onResizeEnd: onClipResizeEnd == null
                      ? null
                      : (DragEndDetails details) => onClipResizeEnd!(clip.id, details),
                  onResizeCancel: onClipResizeCancel == null ? null : () => onClipResizeCancel!(clip.id),
                ),
              ),
          ],
        ),
      ),
    );

    final Widget input = Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) onScroll?.call(event.scrollDelta);
      },
      onPointerPanZoomUpdate: onPanZoom == null
          ? null
          : (PointerPanZoomUpdateEvent event) => onPanZoom!(event.panDelta),
      child: surface,
    );

    return DragTarget<Object>(
      onWillAcceptWithDetails: (DragTargetDetails<Object> details) =>
          onDrop != null && (details.data is SampleAsset || details.data is PlaylistInsertItem),

      onAcceptWithDetails: onDrop == null
          ? null
          : (DragTargetDetails<Object> details) {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              final Offset local = box.globalToLocal(details.offset);
              onDrop!(
                details.data,
                local.dx / vm.pxPerBar + vm.scrollTicks / ticksPerBar.toDouble(),
                (local.dy / size.playlistLaneHeight + vm.scrollLanes).floor(),
              );
            },
      builder:
          (
            BuildContext context,
            List<Object?> candidateData,
            List<dynamic> rejectedData,
          ) => input,
    );
  }
}

class _PlaylistBackgroundPainter extends CustomPainter {
  _PlaylistBackgroundPainter({
    required this.pxPerBar,
    required this.labelEvery,
    required this.gridLine,
    required this.lineWidth,
    required this.scrollBars,
    required this.scrollLanes,
    required this.laneHeight,
    required this.snapTicks,
  });

  final double pxPerBar;

  /// Labelled bars get the gridline; the ones between them stay clean, which
  /// is what keeps a 33-bar arrangement from reading as a fence.
  final int labelEvery;
  final Color gridLine;
  final double lineWidth;
  final double scrollBars;
  final double scrollLanes;
  final double laneHeight;
  final int snapTicks;

  late final Paint _line = Paint()
    ..color = gridLine
    ..strokeWidth = lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final double firstBar = scrollBars.floorToDouble();
    final int visibleBars = (size.width / pxPerBar).ceil() + 2;
    final double stepBars = snapTicks > 0 ? (snapTicks / ticksPerBar.toDouble()).clamp(1 / 64, 64.0) : 1.0;
    final Paint minor = Paint()
      ..color = gridLine.withValues(alpha: 0.55)
      ..strokeWidth = lineWidth;
    final Paint horizontal = Paint()
      ..color = gridLine.withValues(alpha: 0.42)
      ..strokeWidth = lineWidth;
    for (int index = 0; index <= (visibleBars / stepBars).ceil(); index++) {
      final double bar = firstBar + index * stepBars;
      final double x = (bar - scrollBars) * pxPerBar;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    final double firstLane = scrollLanes.floorToDouble();
    final int visibleLanes = (size.height / laneHeight).ceil() + 2;
    for (int lane = firstLane.toInt(); lane <= firstLane + visibleLanes; lane++) {
      final double y = (lane - scrollLanes) * laneHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontal);
    }

    final int firstLabel = (firstBar / labelEvery).floor() * labelEvery;
    final int lastLabel = (firstBar + visibleBars).ceil();
    for (int bar = firstLabel; bar <= lastLabel; bar += labelEvery) {
      final double x = (bar - scrollBars) * pxPerBar;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _line);
    }
  }

  @override
  bool shouldRepaint(_PlaylistBackgroundPainter oldDelegate) =>
      oldDelegate.pxPerBar != pxPerBar ||
      oldDelegate.labelEvery != labelEvery ||
      oldDelegate.gridLine != gridLine ||
      oldDelegate.scrollBars != scrollBars ||
      oldDelegate.scrollLanes != scrollLanes ||
      oldDelegate.laneHeight != laneHeight ||
      oldDelegate.snapTicks != snapTicks;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({required this.x, required this.color, required this.width});

  final double x;
  final Color color;
  final double width;

  late final Paint _paint = Paint()
    ..color = color
    ..strokeWidth = width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), _paint);
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) => oldDelegate.x != x || oldDelegate.color != color;
}
