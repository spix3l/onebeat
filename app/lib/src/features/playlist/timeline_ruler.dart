// PlaylistHeader and PlaylistRuler — the two strips above the canvas
// (UI-B-08).
//
// The ruler numbers every fourth bar and rules a tick at each one. It is
// painted rather than laid out because it has to share the canvas's bar→x
// mapping exactly: a ruler built from widgets would round each tick to its own
// layout and drift away from the gridlines below it by a pixel or two, which
// is exactly the kind of thing that makes an arrangement feel untrustworthy.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// `PLAYLIST` on the left, the project's own line on the right.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    required this.title,
    required this.right,
    super.key,
  });

  final String title;

  /// `Untitled.onebeat · 124 BPM · 4/4`.
  final String right;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.playlistHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      alignment: Alignment.centerLeft,
      child: Row(
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: tokens.type.sectionHeader.copyWith(
              color: tokens.color.textSecondary,
            ),
          ),
          const Spacer(),
          Text(right, maxLines: 1, style: tokens.type.numericSmall),
        ],
      ),
    );
  }
}

class PlaylistRuler extends StatelessWidget {
  const PlaylistRuler({
    required this.pxPerBar,
    this.labelEvery,
    super.key,
  });

  final double pxPerBar;

  /// How often a bar is numbered; defaults to the token the mockup uses.
  final int? labelEvery;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      height: tokens.size.playlistRulerHeight,
      child: CustomPaint(
        painter: PlaylistRulerPainter(
          pxPerBar: pxPerBar,
          labelEvery: labelEvery ?? tokens.size.playlistBarLabelEvery,
          line: tokens.color.line,
          lineWidth: tokens.border.hairline,
          style: tokens.type.numericSmall,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class PlaylistRulerPainter extends CustomPainter {
  PlaylistRulerPainter({
    required this.pxPerBar,
    required this.labelEvery,
    required this.line,
    required this.lineWidth,
    required this.style,
  });

  final double pxPerBar;
  final int labelEvery;
  final Color line;
  final double lineWidth;
  final TextStyle style;

  late final Paint _rule =
      Paint()
        ..color = line
        ..strokeWidth = lineWidth;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Size size) {
    final int bars = (size.width / pxPerBar).ceil();
    for (int bar = 0; bar <= bars; bar += labelEvery) {
      final double x = bar * pxPerBar;
      _text
        ..text = TextSpan(text: '${bar + 1}', style: style)
        ..layout();
      _text.paint(
        canvas,
        Offset(x + lineWidth * 2, (size.height - _text.height) / 2),
      );
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      _rule,
    );
  }

  @override
  bool shouldRepaint(PlaylistRulerPainter oldDelegate) =>
      oldDelegate.pxPerBar != pxPerBar ||
      oldDelegate.labelEvery != labelEvery ||
      oldDelegate.line != line;
}
