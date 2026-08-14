// The app's icon set, painted rather than typeset.
//
// The design screens draw line icons — a grid for the playlist, faders for the
// mixer, a triangle for play. The app used to type those as text glyphs
// (`▤`, `🎛`, `↶`), which meant every one of them depended on whether the
// shipped typefaces happened to carry that codepoint: several did not, and
// rendered as tofu or as a colour emoji sitting oddly among the line work.
//
// These are paths instead. Two dozen shapes, one stroke weight, one size
// token — and no third font dependency (FR-UX-02: the geometry comes from the
// tokens, only the path shape lives here).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// The shapes the chrome needs. Named for the job, like the colour tokens:
/// [OneBeatIconData.playlist], not "grid".
enum OneBeatIconData {
  playlist,
  piano,
  channels,
  mixer,
  plugins,
  console,
  extensions,
  packs,
  effects,
  preferences,
  search,
  export,
  play,
  pause,
  stop,
  loop,
  undo,
  redo,
  folder,
  folderOpen,
  chevronDown,
  close,
  plus,
  minus,
  check,
  lock,
  audio,
  keyboard,
  arrowUp,
  arrowDown,
  arrowRight,
  dot,
}

/// A painted icon. [size] defaults to the icon size token; [color] to the
/// muted text role, which is what the design uses for inactive chrome.
class OneBeatIcon extends StatelessWidget {
  const OneBeatIcon(this.icon, {this.size, this.color, super.key});

  final OneBeatIconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double resolved = size ?? tokens.size.iconSize;
    return SizedBox(
      width: resolved,
      height: resolved,
      child: CustomPaint(
        painter: _IconPainter(
          icon: icon,
          color: color ?? tokens.color.textMuted,
          strokeWidth: tokens.border.emphasis * _strokeRatio,
        ),
      ),
    );
  }

  /// Line icons at this scale read best a shade under 2px; the ratio keeps the
  /// weight tied to the border token rather than to a literal.
  static const double _strokeRatio = 0.75;
}

class _IconPainter extends CustomPainter {
  _IconPainter({
    required this.icon,
    required this.color,
    required this.strokeWidth,
  });

  final OneBeatIconData icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Every shape is authored on a 16-unit grid and scaled, so one set of
    // coordinates serves a 12px rail glyph and a 20px transport button.
    final double u = size.width / 16;
    Offset p(double x, double y) => Offset(x * u, y * u);
    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * u, y * u, w * u, h * u);

    switch (icon) {
      case OneBeatIconData.playlist:
        // Four blocks: the arrangement's clips, abstracted.
        for (final List<double> box in const <List<double>>[
          <double>[2, 2.5, 5, 4.5],
          <double>[8.5, 2.5, 5.5, 4.5],
          <double>[2, 9, 5.5, 4.5],
          <double>[9, 9, 5, 4.5],
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              r(box[0], box[1], box[2], box[3]),
              Radius.circular(u),
            ),
            fill,
          );
        }
      case OneBeatIconData.piano:
        // A beamed pair of notes.
        canvas
          ..drawLine(p(5.5, 12), p(5.5, 3), stroke)
          ..drawLine(p(12.5, 10), p(12.5, 2), stroke)
          ..drawLine(p(5.5, 3), p(12.5, 2), stroke)
          ..drawOval(r(3, 10.5, 5, 3.5), fill)
          ..drawOval(r(10, 8.5, 5, 3.5), fill);
      case OneBeatIconData.channels:
        // Stacked step rows.
        for (double y = 3; y <= 13; y += 3.5) {
          canvas
            ..drawRRect(
              RRect.fromRectAndRadius(r(2, y - 1, 3, 2), Radius.circular(u / 2)),
              fill,
            )
            ..drawRRect(
              RRect.fromRectAndRadius(
                r(6.5, y - 1, 7.5, 2),
                Radius.circular(u / 2),
              ),
              stroke,
            );
        }
      case OneBeatIconData.mixer:
        // Three faders, thumbs at different heights.
        for (final List<double> fader in const <List<double>>[
          <double>[4, 6],
          <double>[8, 9.5],
          <double>[12, 4],
        ]) {
          canvas
            ..drawLine(p(fader[0], 2.5), p(fader[0], 13.5), stroke)
            ..drawLine(
              p(fader[0] - 2, fader[1]),
              p(fader[0] + 2, fader[1]),
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth * 2
                ..strokeCap = StrokeCap.round,
            );
        }
      case OneBeatIconData.plugins:
        // A plug: body plus two pins.
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(r(4, 6, 8, 8), Radius.circular(u * 1.5)),
            stroke,
          )
          ..drawLine(p(6.5, 6), p(6.5, 2), stroke)
          ..drawLine(p(9.5, 6), p(9.5, 2), stroke);
      case OneBeatIconData.console:
        // A prompt: chevron and a line.
        canvas
          ..drawLine(p(3, 4), p(7, 8), stroke)
          ..drawLine(p(7, 8), p(3, 12), stroke)
          ..drawLine(p(8.5, 12), p(13.5, 12), stroke);
      case OneBeatIconData.extensions:
        // Two interlocking squares: something added to the app.
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(r(2, 2, 7, 7), Radius.circular(u)),
            stroke,
          )
          ..drawRRect(
            RRect.fromRectAndRadius(r(7, 7, 7, 7), Radius.circular(u)),
            stroke,
          );
      case OneBeatIconData.packs:
      case OneBeatIconData.folder:
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(r(2, 4.5, 12, 9), Radius.circular(u * 1.2)),
            stroke,
          )
          ..drawLine(p(2, 4.5), p(6, 4.5), stroke)
          ..drawLine(p(6, 4.5), p(7.2, 2.8), stroke);
      case OneBeatIconData.effects:
        // A waveform: the signal something is being done to.
        for (final List<double> bar in const <List<double>>[
          <double>[3, 5],
          <double>[6, 2],
          <double>[9, 3.5],
          <double>[12, 6],
        ]) {
          canvas.drawLine(
            p(bar[0], bar[1]),
            p(bar[0], 16 - bar[1]),
            stroke,
          );
        }
      case OneBeatIconData.preferences:
        // A gear, drawn as a ring with teeth rather than a filled cog: the
        // design's chrome is all line work.
        canvas.drawCircle(p(8, 8), 3.4 * u, stroke);
        for (int tooth = 0; tooth < 8; tooth++) {
          final double angle = tooth * math.pi / 4;
          canvas.drawLine(
            p(8 + 4.4 * math.cos(angle), 8 + 4.4 * math.sin(angle)),
            p(8 + 5.8 * math.cos(angle), 8 + 5.8 * math.sin(angle)),
            stroke,
          );
        }
      case OneBeatIconData.search:
        canvas
          ..drawCircle(p(7, 7), 4 * u, stroke)
          ..drawLine(p(10, 10), p(13.5, 13.5), stroke);
      case OneBeatIconData.export:
        canvas
          ..drawLine(p(8, 2), p(8, 10), stroke)
          ..drawLine(p(4.5, 6.5), p(8, 10), stroke)
          ..drawLine(p(11.5, 6.5), p(8, 10), stroke)
          ..drawLine(p(3, 13), p(13, 13), stroke);
      case OneBeatIconData.play:
        canvas.drawPath(
          Path()
            ..moveTo(5 * u, 3 * u)
            ..lineTo(13 * u, 8 * u)
            ..lineTo(5 * u, 13 * u)
            ..close(),
          fill,
        );
      case OneBeatIconData.pause:
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(r(4.5, 3, 2.5, 10), Radius.circular(u / 2)),
            fill,
          )
          ..drawRRect(
            RRect.fromRectAndRadius(r(9, 3, 2.5, 10), Radius.circular(u / 2)),
            fill,
          );
      case OneBeatIconData.stop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(4, 4, 8, 8), Radius.circular(u)),
          fill,
        );
      case OneBeatIconData.loop:
        // A rounded rectangle broken at the top right, with an arrowhead: the
        // "it comes back round" shape the transport uses.
        canvas
          ..drawArc(
            Rect.fromLTWH(3 * u, 3 * u, 10 * u, 10 * u),
            -math.pi / 3,
            math.pi * 1.72,
            false,
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(9.2 * u, 2.6 * u)
              ..lineTo(11.6 * u, 5.2 * u)
              ..lineTo(8.2 * u, 5.8 * u),
            stroke,
          );
      case OneBeatIconData.undo:
      case OneBeatIconData.redo:
        // One arc, mirrored for redo — so the pair can never drift apart.
        final bool mirrored = icon == OneBeatIconData.redo;
        canvas.save();
        if (mirrored) {
          canvas
            ..translate(size.width, 0)
            ..scale(-1, 1);
        }
        canvas
          // The arc starts at its west point, which is exactly where the
          // arrowhead sits — drawn apart, they used to float unconnected.
          ..drawArc(
            Rect.fromLTWH(3 * u, 5 * u, 10 * u, 9 * u),
            math.pi,
            math.pi * 1.15,
            false,
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(6 * u, 6.8 * u)
              ..lineTo(3 * u, 9.5 * u)
              ..lineTo(6.6 * u, 11.4 * u),
            stroke,
          );
        canvas.restore();
      case OneBeatIconData.chevronDown:
        canvas
          ..drawLine(p(4, 6.5), p(8, 10), stroke)
          ..drawLine(p(8, 10), p(12, 6.5), stroke);
      case OneBeatIconData.close:
        canvas
          ..drawLine(p(4, 4), p(12, 12), stroke)
          ..drawLine(p(12, 4), p(4, 12), stroke);
      case OneBeatIconData.plus:
        canvas
          ..drawLine(p(8, 3.5), p(8, 12.5), stroke)
          ..drawLine(p(3.5, 8), p(12.5, 8), stroke);
      case OneBeatIconData.minus:
        canvas.drawLine(p(3.5, 8), p(12.5, 8), stroke);
      case OneBeatIconData.check:
        canvas
          ..drawLine(p(3.5, 8.5), p(6.5, 11.5), stroke)
          ..drawLine(p(6.5, 11.5), p(12.5, 4.5), stroke);
      case OneBeatIconData.folderOpen:
        canvas
          ..drawLine(p(2, 13), p(2, 4.5), stroke)
          ..drawLine(p(2, 4.5), p(6, 4.5), stroke)
          ..drawLine(p(6, 4.5), p(7.2, 2.8), stroke)
          ..drawPath(
            Path()
              ..moveTo(2 * u, 13 * u)
              ..lineTo(4.5 * u, 7 * u)
              ..lineTo(15 * u, 7 * u)
              ..lineTo(12.5 * u, 13 * u)
              ..close(),
            stroke,
          );
      case OneBeatIconData.lock:
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(r(3.5, 7, 9, 7), Radius.circular(u * 1.2)),
            stroke,
          )
          ..drawArc(
            Rect.fromLTWH(5.5 * u, 2.5 * u, 5 * u, 5 * u),
            math.pi,
            math.pi,
            false,
            stroke,
          );
      case OneBeatIconData.audio:
        // A speaker cone and one arc of sound.
        canvas
          ..drawPath(
            Path()
              ..moveTo(3 * u, 6 * u)
              ..lineTo(5.5 * u, 6 * u)
              ..lineTo(8.5 * u, 3 * u)
              ..lineTo(8.5 * u, 13 * u)
              ..lineTo(5.5 * u, 10 * u)
              ..lineTo(3 * u, 10 * u)
              ..close(),
            stroke,
          )
          ..drawArc(
            Rect.fromLTWH(8 * u, 5 * u, 6 * u, 6 * u),
            -math.pi / 3,
            math.pi * 2 / 3,
            false,
            stroke,
          );
      case OneBeatIconData.keyboard:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(1.5, 4, 13, 8), Radius.circular(u * 1.2)),
          stroke,
        );
        for (double x = 4; x <= 12; x += 2.5) {
          canvas.drawLine(p(x, 6.5), p(x, 6.5), stroke);
        }
        canvas.drawLine(p(5, 9.5), p(11, 9.5), stroke);
      case OneBeatIconData.arrowUp:
        canvas
          ..drawLine(p(8, 13), p(8, 3), stroke)
          ..drawLine(p(4, 7), p(8, 3), stroke)
          ..drawLine(p(12, 7), p(8, 3), stroke);
      case OneBeatIconData.arrowDown:
        canvas
          ..drawLine(p(8, 3), p(8, 13), stroke)
          ..drawLine(p(4, 9), p(8, 13), stroke)
          ..drawLine(p(12, 9), p(8, 13), stroke);
      case OneBeatIconData.arrowRight:
        canvas
          ..drawLine(p(3, 8), p(13, 8), stroke)
          ..drawLine(p(9, 4), p(13, 8), stroke)
          ..drawLine(p(9, 12), p(13, 8), stroke);
      case OneBeatIconData.dot:
        canvas.drawCircle(p(8, 8), 3 * u, fill);
    }
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
