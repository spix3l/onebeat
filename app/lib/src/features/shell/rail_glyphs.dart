// Painted glyphs for the left rail (UI-B-03).
//
// The rail's project destinations carry the shapes the mockups draw: a grid
// for the playlist, a circled query mark for the channel rack, a beamed note
// pair for the piano roll, a slider stack for the mixer, and a folder glyph
// retained for other shell surfaces that need one.
// They are painted rather than typed because neither shipped family carries
// them, and because a destination icon that changes weight with the font would
// break the rail's rhythm.
//
// Each honours the [IconTheme] `ObRailButton` wraps its icon in, so the active
// tile's white and the resting tile's dim both arrive from the button rather
// than from here.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// Which rail destination glyph to paint.
///
/// [script] and [extension] are the two destinations the extension screens add
/// to the rail (UI-C-11). They are here rather than in the extensions feature
/// because the rail is shell chrome, and a rail whose glyphs came from two
/// places would drift in weight the first time either was touched.
enum ObRailGlyphKind { grid, help, note, sliders, folder, script, extension }

class ObRailGlyph extends StatelessWidget {
  const ObRailGlyph({required this.kind, super.key});

  final ObRailGlyphKind kind;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Color color = IconTheme.of(context).color ?? tokens.color.textMuted;
    return SizedBox(
      width: tokens.size.railGlyphSize,
      height: tokens.size.railGlyphSize,
      child: CustomPaint(
        painter: _RailGlyphPainter(
          kind: kind,
          color: color,
          stroke: tokens.border.glyph,
        ),
      ),
    );
  }
}

class _RailGlyphPainter extends CustomPainter {
  _RailGlyphPainter({
    required this.kind,
    required this.color,
    required this.stroke,
  });

  final ObRailGlyphKind kind;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final Paint fill = Paint()..color = color;
    final double w = size.width;
    final double h = size.height;

    switch (kind) {
      case ObRailGlyphKind.grid:
        // Four rounded cells with a gap of their own width between them.
        final double cell = w * 0.38;
        final double gap = w - cell * 2;
        for (final Offset origin in <Offset>[
          Offset(w * 0.06, h * 0.06),
          Offset(w * 0.06 + cell + gap * 0.88, h * 0.06),
          Offset(w * 0.06, h * 0.06 + cell + gap * 0.88),
          Offset(w * 0.06 + cell + gap * 0.88, h * 0.06 + cell + gap * 0.88),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(origin.dx, origin.dy, cell, cell),
              Radius.circular(w * 0.08),
            ),
            line,
          );
        }
      case ObRailGlyphKind.help:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.42, line);
        // The query mark: a hook over the bowl and a dot under it.
        final Path hook = Path()
          ..moveTo(w * 0.38, h * 0.38)
          ..cubicTo(w * 0.40, h * 0.24, w * 0.66, h * 0.26, w * 0.62, h * 0.42)
          ..cubicTo(w * 0.60, h * 0.52, w * 0.50, h * 0.52, w * 0.50, h * 0.62);
        canvas.drawPath(hook, line);
        canvas.drawCircle(Offset(w * 0.50, h * 0.74), stroke * 0.7, fill);
      case ObRailGlyphKind.note:
        // Two stems joined by a beam, each with a filled head.
        final double stemTop = h * 0.14;
        final double leftX = w * 0.30;
        final double rightX = w * 0.76;
        canvas.drawLine(
          Offset(leftX, stemTop + h * 0.06),
          Offset(leftX, h * 0.70),
          line,
        );
        canvas.drawLine(Offset(rightX, stemTop), Offset(rightX, h * 0.62), line);
        canvas.drawLine(
          Offset(leftX, stemTop + h * 0.06),
          Offset(rightX, stemTop),
          line,
        );
        canvas.drawCircle(Offset(leftX - w * 0.10, h * 0.72), w * 0.13, line);
        canvas.drawCircle(Offset(rightX - w * 0.10, h * 0.64), w * 0.13, line);
      case ObRailGlyphKind.sliders:
        // Three rails, each with a cap at a different position — the mixer as
        // "a set of things at different settings".
        final List<double> rows = <double>[h * 0.26, h * 0.5, h * 0.74];
        final List<double> caps = <double>[w * 0.68, w * 0.36, w * 0.60];
        for (int i = 0; i < rows.length; i++) {
          canvas.drawLine(
            Offset(w * 0.12, rows[i]),
            Offset(w * 0.88, rows[i]),
            line,
          );
          canvas.drawLine(
            Offset(caps[i], rows[i] - h * 0.11),
            Offset(caps[i], rows[i] + h * 0.11),
            line,
          );
        }
      case ObRailGlyphKind.script:
        // A page with a prompt caret on it: the console is a place you type.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.16, h * 0.12, w * 0.68, h * 0.76),
            Radius.circular(w * 0.12),
          ),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.32, h * 0.36),
          Offset(w * 0.44, h * 0.48),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.44, h * 0.48),
          Offset(w * 0.32, h * 0.60),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.52, h * 0.64),
          Offset(w * 0.68, h * 0.64),
          line,
        );
      case ObRailGlyphKind.extension:
        // A rounded tile with a tab on its edge — a block that plugs into
        // something, which is the whole idea.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.18, w * 0.64, h * 0.64),
            Radius.circular(w * 0.14),
          ),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.50, h * 0.06),
          Offset(w * 0.50, h * 0.18),
          line,
        );
      case ObRailGlyphKind.folder:
        final Path folder = Path()
          ..moveTo(w * 0.10, h * 0.78)
          ..lineTo(w * 0.10, h * 0.26)
          ..lineTo(w * 0.42, h * 0.26)
          ..lineTo(w * 0.52, h * 0.38)
          ..lineTo(w * 0.90, h * 0.38)
          ..lineTo(w * 0.90, h * 0.78)
          ..close();
        canvas.drawPath(folder, line);
    }
  }

  @override
  bool shouldRepaint(_RailGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color || oldDelegate.stroke != stroke;
}
