// Painted glyphs for the top chrome (UI-B-02).
//
// The shipped typefaces do not carry the arrow, download and chevron glyphs
// the mockups use (the old UI's rail rendered them as tofu before it moved to
// painted icons), so the chrome paints its own at stroke weight
// `BorderTokens.glyph`. Transport glyphs render at `transportGlyphSize` inside
// `ObTransportButton` wells; the export glyph at `iconSize`; the chevron at
// half that, beside a menu item.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// Which chrome glyph to paint.
enum ObChromeGlyphKind { undo, redo, play, stop, loop, download, chevronDown }

/// A painted top-chrome glyph, coloured by the caller.
class ObChromeGlyph extends StatelessWidget {
  const ObChromeGlyph({
    required this.kind,
    required this.color,
    this.scale = ObGlyphScale.transport,
    super.key,
  });

  final ObChromeGlyphKind kind;
  final Color color;

  /// Transport glyphs render at `transportGlyphSize`; chrome glyphs (the
  /// export mark, the menu chevron) at `iconSize`, with the chevron shrinking
  /// inside its own painter.
  final ObGlyphScale scale;

  @override
  Widget build(BuildContext context) {
    final SizeTokens size = OneBeatTheme.of(context).size;
    final double side = scale == ObGlyphScale.transport
        ? size.transportGlyphSize
        : size.iconSize;
    return SizedBox(
      width: side,
      height: side,
      child: CustomPaint(
        painter: _ChromeGlyphPainter(kind: kind, color: color),
      ),
    );
  }
}

enum ObGlyphScale { transport, chrome }

/// One degree, so the arc geometry below can be written in the units it was
/// designed in.
const double _radian = math.pi / 180;

class _ChromeGlyphPainter extends CustomPainter {
  _ChromeGlyphPainter({required this.kind, required this.color});

  final ObChromeGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final double w = size.width;
    final double h = size.height;
    final double weight = w / 8;
    final Paint stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = weight
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    switch (kind) {
      case ObChromeGlyphKind.undo:
      case ObChromeGlyphKind.redo:
        // A circular arrow: one ring with a gap, and a solid head filling the
        // gap. The old pair drew its head as two loose strokes, which at this
        // size closed up into a smudge on the side of a circle.
        //
        // Redo is undo under a horizontal flip rather than a second set of
        // coordinates, so the two can never drift apart.
        canvas.save();
        if (kind == ObChromeGlyphKind.redo) {
          canvas
            ..translate(w, 0)
            ..scale(-1, 1);
        }
        final Offset centre = Offset(w * 0.5, h * 0.52);
        final double r = w * 0.33;
        Offset onRing(double angle) =>
            centre + Offset(math.cos(angle), math.sin(angle)) * r;

        // The ring opens across the top — the one place a reader looks first —
        // and runs anti-clockwise, which is the direction the head then has to
        // travel in.
        const double lead = -50 * _radian;
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: r),
          lead,
          285 * _radian,
          false,
          stroke,
        );
        // Along the tangent at that end. An isoceles head on the tangent is the
        // one placement that reads as motion rather than as a flag stuck to the
        // side of a circle.
        final Offset heading = Offset(math.sin(lead), -math.cos(lead));
        final double reach = w * 0.24;
        _arrowHead(
          canvas,
          fill,
          tip: onRing(lead) + heading * reach,
          direction: heading,
          length: reach,
          halfWidth: w * 0.13,
        );
        canvas.restore();
      case ObChromeGlyphKind.play:
        // Optically centred rather than geometrically: a triangle's mass sits
        // behind its apex, so the shape is nudged left of the box's middle.
        // Rounded at the corners to match the stop square's radius.
        final Path path =
            Path()
              ..moveTo(w * 0.30, h * 0.18)
              ..lineTo(w * 0.82, h * 0.5)
              ..lineTo(w * 0.30, h * 0.82)
              ..close();
        canvas
          ..drawPath(path, fill)
          ..drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 0.12
              ..strokeJoin = StrokeJoin.round,
          );
      case ObChromeGlyphKind.stop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.22, w * 0.56, h * 0.56),
            Radius.circular(w * 0.12),
          ),
          fill,
        );
      case ObChromeGlyphKind.loop:
        // The repeat mark: a rounded-rect track with a break in each long edge
        // and a solid head at each break. A rectangle rather than a ring, so it
        // never reads as another undo arrow; solid heads, so at this size it
        // is an arrow rather than the blob the all-stroke version was.
        final Rect track = Rect.fromLTWH(w * 0.12, h * 0.26, w * 0.76, h * 0.48);
        final double radius = track.height / 2;
        // Both breaks straddle the centre, so the two halves of the track are
        // one shape reflected through the middle.
        final double gapHalf = w * 0.15;
        final double cx = track.center.dx;

        // The right half: top edge from the break, round the right end, back
        // along the bottom to the other break.
        final Path right =
            Path()
              ..moveTo(cx + gapHalf, track.top)
              ..lineTo(track.right - radius, track.top)
              ..arcToPoint(
                Offset(track.right - radius, track.bottom),
                radius: Radius.circular(radius),
              )
              ..lineTo(cx + gapHalf, track.bottom);
        // The left half is that path rotated half a turn about the centre.
        canvas
          ..drawPath(right, stroke)
          ..save()
          ..translate(track.center.dx, track.center.dy)
          ..rotate(math.pi)
          ..translate(-track.center.dx, -track.center.dy)
          ..drawPath(right, stroke)
          ..restore();

        // Top head travelling right, bottom head travelling left: one
        // circulation, which is the whole of what "loop" means.
        _arrowHead(
          canvas,
          fill,
          tip: Offset(cx + gapHalf + w * 0.02, track.top),
          direction: const Offset(1, 0),
          length: w * 0.21,
          halfWidth: w * 0.15,
        );
        _arrowHead(
          canvas,
          fill,
          tip: Offset(cx - gapHalf - w * 0.02, track.bottom),
          direction: const Offset(-1, 0),
          length: w * 0.21,
          halfWidth: w * 0.15,
        );
      case ObChromeGlyphKind.download:
        // A down arrow into a tray.
        canvas.drawLine(Offset(w * 0.5, h * 0.1), Offset(w * 0.5, h * 0.6), stroke);
        canvas.drawLine(
          Offset(w * 0.28, h * 0.42),
          Offset(w * 0.5, h * 0.64),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.72, h * 0.42),
          Offset(w * 0.5, h * 0.64),
          stroke,
        );
        canvas.drawLine(Offset(w * 0.14, h * 0.82), Offset(w * 0.86, h * 0.82), stroke);
      case ObChromeGlyphKind.chevronDown:
        canvas.drawLine(
          Offset(w * 0.18, h * 0.34),
          Offset(w * 0.5, h * 0.66),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.5, h * 0.66),
          Offset(w * 0.82, h * 0.34),
          stroke,
        );
    }
  }

  /// A solid triangular arrowhead with its point at [tip], aimed along the unit
  /// vector [direction].
  ///
  /// Solid rather than two strokes: below about 16px a stroked head's two limbs
  /// meet inside a single pixel and read as a lump on the end of a line. A
  /// filled triangle keeps its silhouette all the way down.
  void _arrowHead(
    Canvas canvas,
    Paint fill, {
    required Offset tip,
    required Offset direction,
    required double length,
    required double halfWidth,
  }) {
    final Offset back = tip - direction * length;
    final Offset across = Offset(-direction.dy, direction.dx) * halfWidth;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + across.dx, back.dy + across.dy)
        ..lineTo(back.dx - across.dx, back.dy - across.dy)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(_ChromeGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
