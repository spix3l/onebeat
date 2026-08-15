// ObMagnifierGlyph — the search magnifier, painted (UI-B-01).
//
// A widget rather than an icon font glyph so the kit stays on WidgetsApp and
// goldens render without extra fonts. Shared by the search field and the
// round search icon; B-04's browser search reuses it too.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObMagnifierGlyph extends StatelessWidget {
  const ObMagnifierGlyph({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return CustomPaint(
      size: Size(tokens.size.iconSize, tokens.size.iconSize),
      painter: _MagnifierPainter(color: color, stroke: tokens.border.glyph),
    );
  }
}

class _MagnifierPainter extends CustomPainter {
  _MagnifierPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final double lens = size.width * 0.62;
    final Offset lensCenter = Offset(size.width * 0.42, size.height * 0.42);
    canvas.drawCircle(lensCenter, lens / 2, paint);
    canvas.drawLine(
      Offset(lensCenter.dx + lens * 0.35, lensCenter.dy + lens * 0.35),
      Offset(size.width * 0.88, size.height * 0.88),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MagnifierPainter oldDelegate) => oldDelegate.color != color || oldDelegate.stroke != stroke;
}
