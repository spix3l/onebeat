// ObKitGlyph — the painted icon set the overlay surfaces share (UI-B-11).
//
// Neither shipped family carries an icon set, and the screens that live on top
// of the app — popovers, floating windows, the extension manager, the empty
// states — draw about twenty small marks between them. Painting them here
// rather than in each feature keeps one stroke weight across all of them, and
// keeps `features/extensions` from having to import `features/shell` to get a
// close button.
//
// Every glyph is drawn inside a unit box and coloured by the caller: these are
// ink, not chrome, and the surface that places one already knows what tier of
// ink it wants.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Which mark to paint. Grouped by where they came from: affordances first,
/// then the extension-manager set, then the panel controls.
enum ObKitGlyphKind {
  check,
  cross,
  plus,
  close,
  pencil,
  trash,
  reset,
  grid,
  chevronRight,

  /// Extension identities and their bindings.
  waveform,
  cursor,
  note,
  warning,
  keyboard,
  menuLines,
  script,
  folder,

  /// Docked-panel controls.
  play,
  undo,
  expand,
}

/// How big to draw. [inline] matches a text line, [chrome] a button's icon and
/// [feature] the tile at the top of an empty state.
enum ObKitGlyphSize { inline, chrome, feature }

class ObKitGlyph extends StatelessWidget {
  const ObKitGlyph({
    required this.kind,
    required this.color,
    this.size = ObKitGlyphSize.chrome,
    super.key,
  });

  final ObKitGlyphKind kind;
  final Color color;
  final ObKitGlyphSize size;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double side;
    switch (size) {
      case ObKitGlyphSize.inline:
        side = tokens.size.transportGlyphSize;
      case ObKitGlyphSize.chrome:
        side = tokens.size.iconSize;
      case ObKitGlyphSize.feature:
        side = tokens.size.emptyGlyphSize;
    }
    return SizedBox(
      width: side,
      height: side,
      child: CustomPaint(
        painter: KitGlyphPainter(
          kind: kind,
          color: color,
          stroke: tokens.border.glyph,
        ),
      ),
    );
  }
}

/// Public so the paint-cost and repaint tests can construct one directly.
class KitGlyphPainter extends CustomPainter {
  KitGlyphPainter({
    required this.kind,
    required this.color,
    required this.stroke,
  });

  final ObKitGlyphKind kind;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    // Strokes scale with the box so a glyph at [ObKitGlyphSize.feature] does
    // not read as a hairline drawing of the same mark.
    final Paint line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * (w / 16)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final Paint fill = Paint()..color = color;

    void poly(List<Offset> points, {bool closed = false}) {
      final Path path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final Offset point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (closed) {
        path.close();
      }
      canvas.drawPath(path, line);
    }

    switch (kind) {
      case ObKitGlyphKind.check:
        poly(<Offset>[
          Offset(w * 0.22, h * 0.52),
          Offset(w * 0.42, h * 0.72),
          Offset(w * 0.78, h * 0.28),
        ]);
      case ObKitGlyphKind.cross:
      case ObKitGlyphKind.close:
        canvas.drawLine(
          Offset(w * 0.26, h * 0.26),
          Offset(w * 0.74, h * 0.74),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.74, h * 0.26),
          Offset(w * 0.26, h * 0.74),
          line,
        );
      case ObKitGlyphKind.plus:
        canvas.drawLine(Offset(w * 0.5, h * 0.2), Offset(w * 0.5, h * 0.8), line);
        canvas.drawLine(Offset(w * 0.2, h * 0.5), Offset(w * 0.8, h * 0.5), line);
      case ObKitGlyphKind.pencil:
        // A nib on a shaft, with the tip left open so it reads as a point.
        poly(<Offset>[
          Offset(w * 0.24, h * 0.76),
          Offset(w * 0.66, h * 0.20),
          Offset(w * 0.80, h * 0.32),
          Offset(w * 0.38, h * 0.86),
          Offset(w * 0.20, h * 0.88),
          Offset(w * 0.24, h * 0.76),
        ], closed: true);
      case ObKitGlyphKind.trash:
        canvas.drawLine(
          Offset(w * 0.18, h * 0.28),
          Offset(w * 0.82, h * 0.28),
          line,
        );
        poly(<Offset>[
          Offset(w * 0.28, h * 0.28),
          Offset(w * 0.33, h * 0.84),
          Offset(w * 0.67, h * 0.84),
          Offset(w * 0.72, h * 0.28),
        ]);
        // The lid handle: what makes a bin a bin rather than a bucket.
        poly(<Offset>[
          Offset(w * 0.40, h * 0.28),
          Offset(w * 0.42, h * 0.14),
          Offset(w * 0.58, h * 0.14),
          Offset(w * 0.60, h * 0.28),
        ]);
      case ObKitGlyphKind.reset:
        // A three-quarter arc with the arrowhead at its open end — undo as a
        // circle rather than as an arrow, because it returns to a state.
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w / 2, h / 2), radius: w * 0.30),
          -3.0,
          5.0,
          false,
          line,
        );
        poly(<Offset>[
          Offset(w * 0.20, h * 0.20),
          Offset(w * 0.21, h * 0.44),
          Offset(w * 0.45, h * 0.42),
        ]);
      case ObKitGlyphKind.grid:
        final double cell = w * 0.34;
        for (final Offset origin in <Offset>[
          Offset(w * 0.12, h * 0.12),
          Offset(w * 0.54, h * 0.12),
          Offset(w * 0.12, h * 0.54),
          Offset(w * 0.54, h * 0.54),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(origin.dx, origin.dy, cell, cell),
              Radius.circular(w * 0.06),
            ),
            fill,
          );
        }
      case ObKitGlyphKind.chevronRight:
        poly(<Offset>[
          Offset(w * 0.38, h * 0.24),
          Offset(w * 0.66, h * 0.5),
          Offset(w * 0.38, h * 0.76),
        ]);
      case ObKitGlyphKind.waveform:
        // A signal: three peaks of falling amplitude across the box. This is
        // the mark the mockup gives Harmonizer, and it is the closest thing
        // the app has to "does something to your sound".
        poly(<Offset>[
          Offset(w * 0.10, h * 0.50),
          Offset(w * 0.26, h * 0.50),
          Offset(w * 0.36, h * 0.18),
          Offset(w * 0.48, h * 0.82),
          Offset(w * 0.60, h * 0.34),
          Offset(w * 0.70, h * 0.62),
          Offset(w * 0.78, h * 0.50),
          Offset(w * 0.90, h * 0.50),
        ]);
      case ObKitGlyphKind.cursor:
        poly(<Offset>[
          Offset(w * 0.30, h * 0.16),
          Offset(w * 0.30, h * 0.78),
          Offset(w * 0.45, h * 0.63),
          Offset(w * 0.56, h * 0.86),
          Offset(w * 0.68, h * 0.80),
          Offset(w * 0.57, h * 0.58),
          Offset(w * 0.76, h * 0.55),
        ], closed: true);
      case ObKitGlyphKind.note:
        canvas.drawLine(
          Offset(w * 0.66, h * 0.18),
          Offset(w * 0.66, h * 0.68),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.36, h * 0.30),
          Offset(w * 0.36, h * 0.74),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.36, h * 0.30),
          Offset(w * 0.66, h * 0.18),
          line,
        );
        canvas.drawCircle(Offset(w * 0.26, h * 0.76), w * 0.12, line);
        canvas.drawCircle(Offset(w * 0.56, h * 0.70), w * 0.12, line);
      case ObKitGlyphKind.warning:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.38, line);
        canvas.drawLine(
          Offset(w * 0.5, h * 0.28),
          Offset(w * 0.5, h * 0.56),
          line,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.70), stroke * (w / 16) * 0.6, fill);
      case ObKitGlyphKind.keyboard:
        // Two rows of keys inside a case — the mark on the `Keyboard shortcut`
        // binding row.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.10, h * 0.26, w * 0.80, h * 0.48),
            Radius.circular(w * 0.08),
          ),
          line,
        );
        for (final double x in <double>[0.24, 0.42, 0.60]) {
          canvas.drawLine(
            Offset(w * x, h * 0.42),
            Offset(w * (x + 0.06), h * 0.42),
            line,
          );
        }
        canvas.drawLine(
          Offset(w * 0.30, h * 0.60),
          Offset(w * 0.70, h * 0.60),
          line,
        );
      case ObKitGlyphKind.menuLines:
        for (int i = 0; i < 3; i++) {
          final double y = h * (0.28 + i * 0.22);
          // Ragged right: a list of actions, not a paragraph.
          final double right = i == 1 ? 0.66 : 0.84;
          canvas.drawLine(Offset(w * 0.16, y), Offset(w * right, y), line);
        }
      case ObKitGlyphKind.script:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.12, w * 0.56, h * 0.76),
            Radius.circular(w * 0.10),
          ),
          line,
        );
        for (int i = 0; i < 3; i++) {
          final double y = h * (0.32 + i * 0.18);
          canvas.drawLine(Offset(w * 0.36, y), Offset(w * 0.64, y), line);
        }
      case ObKitGlyphKind.folder:
        poly(<Offset>[
          Offset(w * 0.12, h * 0.78),
          Offset(w * 0.12, h * 0.24),
          Offset(w * 0.42, h * 0.24),
          Offset(w * 0.52, h * 0.36),
          Offset(w * 0.88, h * 0.36),
          Offset(w * 0.88, h * 0.78),
        ], closed: true);
      case ObKitGlyphKind.play:
        final Path path =
            Path()
              ..moveTo(w * 0.30, h * 0.16)
              ..lineTo(w * 0.84, h * 0.5)
              ..lineTo(w * 0.30, h * 0.84)
              ..close();
        canvas.drawPath(path, fill);
      case ObKitGlyphKind.undo:
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.5, h * 0.56), radius: w * 0.28),
          3.4,
          4.6,
          false,
          line,
        );
        poly(<Offset>[
          Offset(w * 0.10, h * 0.34),
          Offset(w * 0.23, h * 0.30),
          Offset(w * 0.26, h * 0.52),
        ]);
      case ObKitGlyphKind.expand:
        // Two opposing corners: the universal "make this bigger".
        poly(<Offset>[
          Offset(w * 0.44, h * 0.18),
          Offset(w * 0.82, h * 0.18),
          Offset(w * 0.82, h * 0.56),
        ]);
        poly(<Offset>[
          Offset(w * 0.56, h * 0.82),
          Offset(w * 0.18, h * 0.82),
          Offset(w * 0.18, h * 0.44),
        ]);
    }
  }

  @override
  bool shouldRepaint(KitGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.stroke != stroke;
}
