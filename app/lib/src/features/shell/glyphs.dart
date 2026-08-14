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

class _ChromeGlyphPainter extends CustomPainter {
  _ChromeGlyphPainter({required this.kind, required this.color});

  final ObChromeGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width / 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;
    switch (kind) {
      case ObChromeGlyphKind.undo:
      case ObChromeGlyphKind.redo:
        final bool mirrored = kind == ObChromeGlyphKind.redo;
        // A half-circle arrow. Drawn around a centre on the glyph's midline so
        // `mirrored` is a flip rather than a second path to keep in step.
        final double cx = mirrored ? w * 0.42 : w * 0.58;
        final Offset centre = Offset(cx, h * 0.58);
        final double r = w * 0.26;
        final double start = mirrored ? -math.pi / 2 : math.pi + math.pi / 2;
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: r),
          start,
          math.pi * 1.45,
          false,
          stroke,
        );
        // The arrowhead at the arc's loose end.
        final double tipX = centre.dx + (mirrored ? 1 : -1) * r;
        final Offset tip = Offset(tipX, centre.dy - r * 0.72);
        final double dir = mirrored ? -1 : 1;
        canvas.drawLine(
          tip.translate(-dir * w * 0.02, -h * 0.16),
          tip,
          stroke,
        );
        canvas.drawLine(
          tip.translate(dir * w * 0.18, -h * 0.06),
          tip,
          stroke,
        );
      case ObChromeGlyphKind.play:
        final Path path =
            Path()
              ..moveTo(w * 0.28, h * 0.12)
              ..lineTo(w * 0.85, h * 0.5)
              ..lineTo(w * 0.28, h * 0.88)
              ..close();
        canvas.drawPath(path, fill);
      case ObChromeGlyphKind.stop:
        canvas.drawRect(
          Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.6, h * 0.6),
          fill,
        );
      case ObChromeGlyphKind.loop:
        final Rect loop = Rect.fromLTWH(w * 0.24, h * 0.26, w * 0.52, h * 0.48);
        canvas.drawRRect(
          RRect.fromRectAndRadius(loop, Radius.circular(size.width * 0.14)),
          stroke,
        );
        // Arrowheads breaking the loop's left and right edges.
        for (final double edgeX in <double>[loop.left, loop.right]) {
          final double dir = edgeX == loop.left ? -1 : 1;
          canvas.drawLine(
            Offset(edgeX + dir * w * 0.06, h * 0.5),
            Offset(edgeX - dir * w * 0.08, h * 0.36),
            stroke,
          );
          canvas.drawLine(
            Offset(edgeX + dir * w * 0.06, h * 0.5),
            Offset(edgeX - dir * w * 0.08, h * 0.64),
            stroke,
          );
        }
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

  @override
  bool shouldRepaint(_ChromeGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
