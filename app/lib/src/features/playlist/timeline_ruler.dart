// PlaylistHeader and PlaylistRuler — the two strips above the canvas
// (UI-B-08).
//
// The ruler numbers every fourth bar and rules a tick at each one. It is
// painted rather than laid out because it has to share the canvas's bar→x
// mapping exactly: a ruler built from widgets would round each tick to its own
// layout and drift away from the gridlines below it by a pixel or two, which
// is exactly the kind of thing that makes an arrangement feel untrustworthy.
import 'package:flutter/widgets.dart';

import '../../ui_kit/dropdown.dart';

import '../../design/tokens.dart';
import 'playlist_store.dart';

/// `PLAYLIST` on the left, the project's own line on the right.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({required this.title, required this.right, this.snap = '1 bar', this.onSnapChanged, super.key});

  final String title;

  /// `124 BPM · 4/4`.
  final String right;
  final String snap;
  final ValueChanged<String>? onSnapChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.playlistHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      alignment: Alignment.centerLeft,
      child: Row(
        children: <Widget>[
          Text(title.toUpperCase(), style: tokens.type.sectionHeader.copyWith(color: tokens.color.textSecondary)),
          const Spacer(),
          ObDropdown(
            label: 'Snap',
            value: snap,
            items: const <String>['4 bars', '1 bar', '1/4', '1/8', '1/16', 'Off'],
            width: tokens.size.dropdownWidth,
            onSelected: onSnapChanged,
          ),
          SizedBox(width: tokens.spacing.sm),
          Text(right, maxLines: 1, style: tokens.type.numericSmall),
        ],
      ),
    );
  }
}

class PlaylistRuler extends StatelessWidget {
  const PlaylistRuler({required this.pxPerBar, this.scrollTicks = 0, this.labelEvery, this.onSeekBar, super.key});

  final double pxPerBar;
  final double scrollTicks;

  /// How often a bar is numbered; defaults to the token the mockup uses.
  final int? labelEvery;
  final ValueChanged<double>? onSeekBar;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Widget ruler = SizedBox(
      height: tokens.size.playlistRulerHeight,
      child: CustomPaint(
        painter: PlaylistRulerPainter(
          pxPerBar: pxPerBar,
          scrollTicks: scrollTicks,
          labelEvery: labelEvery ?? tokens.size.playlistBarLabelEvery,
          line: tokens.color.line,
          lineWidth: tokens.border.hairline,
          style: tokens.type.numericSmall,
        ),
        child: const SizedBox.expand(),
      ),
    );
    if (onSeekBar == null) return ruler;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (TapDownDetails details) =>
          onSeekBar!(details.localPosition.dx / pxPerBar + scrollTicks / ticksPerBar),
      onHorizontalDragUpdate: (DragUpdateDetails details) =>
          onSeekBar!(details.localPosition.dx / pxPerBar + scrollTicks / ticksPerBar),
      child: ruler,
    );
  }
}

class PlaylistRulerPainter extends CustomPainter {
  PlaylistRulerPainter({
    required this.pxPerBar,
    this.scrollTicks = 0,
    required this.labelEvery,
    required this.line,
    required this.lineWidth,
    required this.style,
  });

  final double pxPerBar;
  final double scrollTicks;
  final int labelEvery;
  final Color line;
  final double lineWidth;
  final TextStyle style;

  late final Paint _rule = Paint()
    ..color = line
    ..strokeWidth = lineWidth;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Size size) {
    final double scrollBars = scrollTicks / ticksPerBar;
    final int firstBar = (scrollBars / labelEvery).floor() * labelEvery;
    final int bars = (size.width / pxPerBar).ceil() + scrollBars.ceil();
    for (int bar = firstBar; bar <= bars; bar += labelEvery) {
      final double x = (bar - scrollBars) * pxPerBar;
      _text
        ..text = TextSpan(text: '${bar + 1}', style: style)
        ..layout();
      _text.paint(canvas, Offset(x + lineWidth * 2, (size.height - _text.height) / 2));
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), _rule);
  }

  @override
  bool shouldRepaint(PlaylistRulerPainter oldDelegate) =>
      oldDelegate.pxPerBar != pxPerBar ||
      oldDelegate.scrollTicks != scrollTicks ||
      oldDelegate.labelEvery != labelEvery ||
      oldDelegate.line != line;
}
