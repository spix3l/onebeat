// PrScrollbar — the roll's always-visible scroll rails (UI-D-03).
//
// The roll is not a Scrollable: its viewport is a `PrViewport` a painter reads,
// so Flutter's Scrollbar has nothing to attach to. This is the equivalent in
// the roll's own vocabulary — a track, a proportional thumb, and a drag that
// reports an offset back in the same units the caller passed in.
//
// It is always visible on purpose. An overlay scrollbar that fades out answers
// "can I scroll here" only *after* you have already tried, and on a canvas with
// 128 rows and no natural end that is the question you have most often.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// A scroll rail for a hand-painted viewport.
///
/// [offset], [viewportExtent] and [contentExtent] are all in the caller's own
/// units — ticks for the horizontal rail, semitone rows for the vertical one.
/// Nothing here knows which.
class PrScrollbar extends StatefulWidget {
  const PrScrollbar({
    required this.axis,
    required this.offset,
    required this.viewportExtent,
    required this.contentExtent,
    this.onOffsetChanged,
    super.key,
  });

  final Axis axis;

  /// The first visible unit — the leading edge of the thumb.
  final double offset;

  /// How much of [contentExtent] is on screen.
  final double viewportExtent;

  /// The full scrollable span. Clamped up to [viewportExtent] so a thumb never
  /// paints longer than its track.
  final double contentExtent;

  /// Fired with the new [offset] while the thumb is dragged. Already clamped to
  /// `0 .. contentExtent - viewportExtent`.
  final ValueChanged<double>? onOffsetChanged;

  @override
  State<PrScrollbar> createState() => _PrScrollbarState();
}

class _PrScrollbarState extends State<PrScrollbar> {
  bool _hover = false;
  bool _dragging = false;

  /// Where in the thumb the drag grabbed it, as a fraction of thumb length.
  /// Kept so the thumb does not jump under the cursor on the first frame.
  double _grabWithinThumb = 0;

  double get _maxOffset =>
      math.max(0, widget.contentExtent - widget.viewportExtent);

  /// The thumb, as (start, length) fractions of the track.
  ({double start, double length}) _thumb() {
    final double content = math.max(widget.contentExtent, 1e-9);
    final double length = (widget.viewportExtent / content).clamp(0.0, 1.0);
    final double max = _maxOffset;
    final double progress = max <= 0 ? 0.0 : (widget.offset / max).clamp(0.0, 1.0);
    // The thumb travels the track *minus its own length*, which is what keeps
    // its trailing edge on the end of the track at maximum offset.
    return (start: progress * (1 - length), length: length);
  }

  void _scrollTo(double pointerFraction, double minThumbFraction) {
    final ValueChanged<double>? notify = widget.onOffsetChanged;
    if (notify == null) return;
    final double max = _maxOffset;
    if (max <= 0) return;
    final double length = math.max(_thumb().length, minThumbFraction);
    final double travel = 1 - length;
    if (travel <= 0) return;
    final double start = pointerFraction - _grabWithinThumb * length;
    notify((start / travel).clamp(0.0, 1.0) * max);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool horizontal = widget.axis == Axis.horizontal;
    final double thickness = tokens.size.prScrollbarThickness;
    final bool enabled = widget.onOffsetChanged != null && _maxOffset > 0;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double track =
              horizontal ? constraints.maxWidth : constraints.maxHeight;
          // A thumb shorter than this stops being grabbable, so it is floored
          // in pixels and the travel maths is told about the floor.
          final double minThumbFraction =
              track <= 0 ? 1.0 : (tokens.size.prScrollbarMinThumb / track).clamp(0.0, 1.0);

          void handle(Offset local, {required bool starting}) {
            if (track <= 0) return;
            final double fraction =
                ((horizontal ? local.dx : local.dy) / track).clamp(0.0, 1.0);
            if (starting) {
              final ({double start, double length}) thumb = _thumb();
              final double length = math.max(thumb.length, minThumbFraction);
              final bool onThumb =
                  fraction >= thumb.start && fraction <= thumb.start + length;
              // Grabbing the thumb keeps the grip point; clicking the track
              // centres the thumb on the click, which is the platform
              // behaviour and is what makes a long track usable.
              _grabWithinThumb =
                  onThumb && length > 0 ? (fraction - thumb.start) / length : 0.5;
            }
            _scrollTo(fraction, minThumbFraction);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) =>
                handle(d.localPosition, starting: true),
            onPanDown: (DragDownDetails d) {
              setState(() => _dragging = true);
              handle(d.localPosition, starting: true);
            },
            onPanUpdate: (DragUpdateDetails d) =>
                handle(d.localPosition, starting: false),
            onPanEnd: (_) => setState(() => _dragging = false),
            onPanCancel: () => setState(() => _dragging = false),
            child: SizedBox(
              width: horizontal ? null : thickness,
              height: horizontal ? thickness : null,
              child: CustomPaint(
                painter: _PrScrollbarPainter(
                  axis: widget.axis,
                  thumb: _thumb(),
                  minThumbFraction: minThumbFraction,
                  enabled: enabled,
                  lit: _dragging || _hover,
                  track: tokens.color.scrollTrack,
                  border: tokens.color.line,
                  thumbColor: tokens.color.scrollThumb,
                  thumbLit: tokens.color.scrollThumbHover,
                  radius: tokens.radius.xs,
                  lineWidth: tokens.border.hairline,
                  inset: tokens.spacing.xxs,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PrScrollbarPainter extends CustomPainter {
  _PrScrollbarPainter({
    required this.axis,
    required this.thumb,
    required this.minThumbFraction,
    required this.enabled,
    required this.lit,
    required this.track,
    required this.border,
    required this.thumbColor,
    required this.thumbLit,
    required this.radius,
    required this.lineWidth,
    required this.inset,
  });

  final Axis axis;
  final ({double start, double length}) thumb;
  final double minThumbFraction;
  final bool enabled;
  final bool lit;
  final Color track;
  final Color border;
  final Color thumbColor;
  final Color thumbLit;
  final Radius radius;
  final double lineWidth;
  final double inset;

  late final Paint _track = Paint()..color = track;
  late final Paint _edge =
      Paint()
        ..color = border
        ..strokeWidth = lineWidth;
  late final Paint _thumb =
      Paint()..color = lit && enabled ? thumbLit : thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bool horizontal = axis == Axis.horizontal;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _track);
    // The rail's inner edge, so the track reads as part of the canvas chrome
    // rather than as a floating strip.
    if (horizontal) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), _edge);
    } else {
      canvas.drawLine(Offset.zero, Offset(0, size.height), _edge);
    }

    if (!enabled) return;

    final double extent = horizontal ? size.width : size.height;
    final double length = math.max(thumb.length, minThumbFraction) * extent;
    final double start = thumb.start * extent;
    final Rect rect =
        horizontal
            ? Rect.fromLTWH(start, inset, length, size.height - inset * 2)
            : Rect.fromLTWH(inset, start, size.width - inset * 2, length);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), _thumb);
  }

  @override
  bool shouldRepaint(_PrScrollbarPainter oldDelegate) =>
      oldDelegate.thumb != thumb ||
      oldDelegate.minThumbFraction != minThumbFraction ||
      oldDelegate.enabled != enabled ||
      oldDelegate.lit != lit ||
      oldDelegate.thumbColor != thumbColor;
}
