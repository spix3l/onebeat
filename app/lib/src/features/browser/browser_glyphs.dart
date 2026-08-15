// Painted glyphs for the browser rows (UI-B-04).
//
// A folder (closed and open), the four-cell mark that stands for a pattern,
// and the little waveform that trails a sample row. Painted for the same
// reason the rail's are: the shipped families carry none of them, and these
// have to hold their weight at 12px inside a 24px row.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

enum ObBrowserGlyphKind { folder, folderOpen, pattern }

/// A row glyph at [SizeTokens.iconSize], coloured by the caller.
class ObBrowserGlyph extends StatelessWidget {
  const ObBrowserGlyph({required this.kind, required this.color, super.key});

  final ObBrowserGlyphKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.iconSize,
      height: tokens.size.iconSize,
      child: CustomPaint(
        painter: _BrowserGlyphPainter(
          kind: kind,
          color: color,
          stroke: tokens.border.hairline,
        ),
      ),
    );
  }
}

class _BrowserGlyphPainter extends CustomPainter {
  _BrowserGlyphPainter({
    required this.kind,
    required this.color,
    required this.stroke,
  });

  final ObBrowserGlyphKind kind;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final double w = size.width;
    final double h = size.height;

    switch (kind) {
      case ObBrowserGlyphKind.folder:
        final Path folder = Path()
          ..moveTo(w * 0.12, h * 0.76)
          ..lineTo(w * 0.12, h * 0.28)
          ..lineTo(w * 0.44, h * 0.28)
          ..lineTo(w * 0.54, h * 0.40)
          ..lineTo(w * 0.88, h * 0.40)
          ..lineTo(w * 0.88, h * 0.76)
          ..close();
        canvas.drawPath(folder, line);
      case ObBrowserGlyphKind.folderOpen:
        // The open variant tips its front panel forward: same silhouette,
        // sheared lid, so "expanded" reads without a second disclosure mark.
        final Path back = Path()
          ..moveTo(w * 0.12, h * 0.76)
          ..lineTo(w * 0.12, h * 0.28)
          ..lineTo(w * 0.44, h * 0.28)
          ..lineTo(w * 0.54, h * 0.40)
          ..lineTo(w * 0.82, h * 0.40);
        canvas.drawPath(back, line);
        final Path front = Path()
          ..moveTo(w * 0.12, h * 0.76)
          ..lineTo(w * 0.26, h * 0.52)
          ..lineTo(w * 0.96, h * 0.52)
          ..lineTo(w * 0.82, h * 0.76)
          ..close();
        canvas.drawPath(front, line);
      case ObBrowserGlyphKind.pattern:
        // Four cells: the same mark the rail uses for the playlist, because a
        // pattern is what a playlist is made of.
        const double cell = 0.32;
        for (final Offset origin in <Offset>[
          const Offset(0.14, 0.16),
          const Offset(0.54, 0.16),
          const Offset(0.14, 0.56),
          const Offset(0.54, 0.56),
        ]) {
          canvas.drawRect(
            Rect.fromLTWH(
              origin.dx * w,
              origin.dy * h,
              cell * w,
              cell * h,
            ),
            line,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_BrowserGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// The waveform mark at the right edge of a sample row: five mirrored bars,
/// deterministic, standing for "this row is audio".
class ObSampleWaveGlyph extends StatelessWidget {
  const ObSampleWaveGlyph({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.browserWaveWidth,
      height: tokens.size.browserWaveHeight,
      child: CustomPaint(
        painter: _SampleWavePainter(
          color: color,
          stroke: tokens.border.hairline,
        ),
      ),
    );
  }
}

class _SampleWavePainter extends CustomPainter {
  _SampleWavePainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  /// Bar half-heights as a fraction of the glyph, tallest in the middle.
  static const List<double> _bars = <double>[0.24, 0.62, 0.42, 0.9, 0.34];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final double step = size.width / _bars.length;
    final double mid = size.height / 2;
    for (int i = 0; i < _bars.length; i++) {
      final double x = step * (i + 0.5);
      final double half = mid * _bars[i];
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  @override
  bool shouldRepaint(_SampleWavePainter oldDelegate) => oldDelegate.color != color || oldDelegate.stroke != stroke;
}
