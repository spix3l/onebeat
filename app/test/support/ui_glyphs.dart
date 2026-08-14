// Painted glyphs for ui_kit tests (UI-B-01).
//
// Transport and rail controls take a caller-supplied glyph; these painted
// stand-ins keep the kit free of an icon font and render in goldens without
// extra font loading. Screens in Phase C reuse them where the mockups show
// the same glyph.
import 'package:flutter/widgets.dart';
import 'package:onebeat/src/design/tokens.dart';

enum GlyphKind { skipBack, play, stop, record, loop }

/// A transport-bar glyph at [SizeTokens.transportGlyphSize].
class TransportGlyph extends StatelessWidget {
  const TransportGlyph({required this.kind, required this.color, super.key});

  final GlyphKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final SizeTokens size = OneBeatTheme.of(context).size;
    return SizedBox(
      width: size.transportGlyphSize,
      height: size.transportGlyphSize,
      child: CustomPaint(
        painter: _TransportGlyphPainter(kind: kind, color: color),
      ),
    );
  }
}

class _TransportGlyphPainter extends CustomPainter {
  _TransportGlyphPainter({required this.kind, required this.color});

  final GlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double w = size.width;
    final double h = size.height;
    switch (kind) {
      case GlyphKind.play:
        final Path path =
            Path()
              ..moveTo(w * 0.28, h * 0.12)
              ..lineTo(w * 0.85, h * 0.5)
              ..lineTo(w * 0.28, h * 0.88)
              ..close();
        canvas.drawPath(path, paint);
      case GlyphKind.stop:
        canvas.drawRect(
          Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.6, h * 0.6),
          paint,
        );
      case GlyphKind.record:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.32, paint);
      case GlyphKind.skipBack:
        canvas.drawRect(
          Rect.fromLTWH(w * 0.16, h * 0.14, w * 0.12, h * 0.72),
          paint,
        );
        final Path path =
            Path()
              ..moveTo(w * 0.88, h * 0.12)
              ..lineTo(w * 0.36, h * 0.5)
              ..lineTo(w * 0.88, h * 0.88)
              ..close();
        canvas.drawPath(path, paint);
      case GlyphKind.loop:
        final Paint stroke =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size.width / 8
              ..strokeCap = StrokeCap.round
              ..color = color;
        final Rect loop = Rect.fromLTWH(w * 0.24, h * 0.26, w * 0.52, h * 0.48);
        canvas.drawRRect(
          RRect.fromRectAndRadius(loop, Radius.circular(size.width * 0.14)),
          stroke,
        );
        // Arrowheads breaking the loop's left and right edges.
        canvas.drawLine(
          Offset(loop.left - w * 0.06, h * 0.5),
          Offset(loop.left + w * 0.08, h * 0.36),
          stroke,
        );
        canvas.drawLine(
          Offset(loop.left - w * 0.06, h * 0.5),
          Offset(loop.left + w * 0.08, h * 0.64),
          stroke,
        );
        canvas.drawLine(
          Offset(loop.right + w * 0.06, h * 0.5),
          Offset(loop.right - w * 0.08, h * 0.36),
          stroke,
        );
        canvas.drawLine(
          Offset(loop.right + w * 0.06, h * 0.5),
          Offset(loop.right - w * 0.08, h * 0.64),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_TransportGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

/// A rail glyph at [SizeTokens.railGlyphSize]; honours the IconTheme that
/// ObRailButton wraps it in.
class RailGlyph extends StatelessWidget {
  const RailGlyph(this._builder, {super.key});

  final CustomPainter Function(Color color) _builder;

  static RailGlyph grid() =>
      RailGlyph((color) => _RailGridPainter(color: color));
  static RailGlyph sliders() =>
      RailGlyph((color) => _RailSlidersPainter(color: color));
  static RailGlyph wave() =>
      RailGlyph((color) => _RailWavePainter(color: color));

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final SizeTokens size = OneBeatTheme.of(context).size;
    return SizedBox(
      width: size.railGlyphSize,
      height: size.railGlyphSize,
      child: CustomPaint(painter: _builder(iconTheme.color!)),
    );
  }
}

class _RailGridPainter extends CustomPainter {
  _RailGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double cell = size.width * 0.42;
    final double gap = size.width - cell * 2;
    for (final Offset offset in <Offset>[
      Offset.zero,
      Offset(cell + gap, 0),
      Offset(0, cell + gap),
      Offset(cell + gap, cell + gap),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(offset.dx, offset.dy, cell, cell),
          Radius.circular(size.width * 0.12),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RailGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RailSlidersPainter extends CustomPainter {
  _RailSlidersPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.09
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double inset = size.width * 0.2;
    final double x1 = size.width * 0.3;
    final double x2 = size.width * 0.7;
    canvas.drawLine(Offset(x1, inset), Offset(x1, size.height - inset), stroke);
    canvas.drawLine(
      Offset(x2, size.height * 0.3),
      Offset(x2, size.height * 0.7),
      stroke,
    );
    canvas.drawOval(
      Rect.fromCircle(
        center: Offset(x1, size.height * 0.32),
        radius: size.width * 0.11,
      ),
      stroke,
    );
    canvas.drawOval(
      Rect.fromCircle(
        center: Offset(x2, size.height * 0.66),
        radius: size.width * 0.11,
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_RailSlidersPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RailWavePainter extends CustomPainter {
  _RailWavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.09
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double midX = size.width / 2;
    final double inset = size.width * 0.18;
    canvas.drawLine(
      Offset(inset, size.height / 2),
      Offset(size.width * 0.35, size.height / 2),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, size.height / 2),
      Offset(size.width - inset, size.height / 2),
      stroke,
    );
    canvas.drawLine(
      Offset(midX, size.height * 0.22),
      Offset(midX, size.height * 0.78),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_RailWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
