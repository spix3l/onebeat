// PlaylistCanvas — the free-form arrangement surface (UI-B-08).
//
// Clips are positioned from `(startBar, lane)` on a gridline background, with
// the playhead drawn over everything. Free-form on purpose: there are no lane
// headers and no track list, because in this design a clip's lane is where you
// put it, not a row you had to create first.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'clip_card.dart';

@immutable
class PlaylistVm {
  const PlaylistVm({
    required this.clips,
    required this.pxPerBar,
    this.playheadBar16ths,
    this.headerTitle = 'Playlist',
    this.headerRight = '',
  });

  final List<ClipVm> clips;

  /// Horizontal zoom. A double so a zoom step never has to round to a whole
  /// pixel per bar.
  final double pxPerBar;

  /// The playhead, in sixteenths of a bar from the start; null hides it.
  /// Sixteenths rather than bars because that is the finest thing the
  /// transport reports, and a playhead that can only stop on a bar line is
  /// a playhead nobody believes.
  final int? playheadBar16ths;

  final String headerTitle;

  /// `Untitled.onebeat · 124 BPM · 4/4`.
  final String headerRight;

  /// The lane count the canvas has to make room for.
  int get laneCount =>
      clips.isEmpty
          ? 0
          : clips.map((ClipVm c) => c.lane).reduce((int a, int b) => a > b ? a : b) +
              1;
}

class PlaylistCanvas extends StatelessWidget {
  const PlaylistCanvas({
    required this.vm,
    this.onClipTap,
    this.onBackgroundTap,
    super.key,
  });

  final PlaylistVm vm;
  final ValueChanged<int>? onClipTap;

  /// Fired with the (bar, lane) of a tap on empty canvas — fractional bar,
  /// because snapping is the store's decision, not the canvas's.
  final void Function(double bar, int lane)? onBackgroundTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final SizeTokens size = tokens.size;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp:
          onBackgroundTap == null
              ? null
              : (TapUpDetails details) => onBackgroundTap!(
                details.localPosition.dx / vm.pxPerBar,
                (details.localPosition.dy / size.playlistLaneHeight).floor(),
              ),
      child: CustomPaint(
        painter: _PlaylistBackgroundPainter(
          pxPerBar: vm.pxPerBar,
          labelEvery: size.playlistBarLabelEvery,
          gridLine: tokens.color.gridLine,
          lineWidth: tokens.border.hairline,
        ),
        foregroundPainter:
            vm.playheadBar16ths == null
                ? null
                : _PlayheadPainter(
                  x: vm.playheadBar16ths! * vm.pxPerBar / 16,
                  color: tokens.color.playhead,
                  width: size.playheadWidth,
                ),
        child: Stack(
          children: <Widget>[
            for (final ClipVm clip in vm.clips)
              Positioned(
                left: clip.startBar * vm.pxPerBar,
                top:
                    clip.lane * size.playlistLaneHeight +
                    (size.playlistLaneHeight - size.playlistClipHeight) / 2,
                width: clip.lengthBars * vm.pxPerBar,
                height: size.playlistClipHeight,
                child: ObClipCard(
                  vm: clip,
                  onTap:
                      onClipTap == null ? null : () => onClipTap!(clip.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistBackgroundPainter extends CustomPainter {
  _PlaylistBackgroundPainter({
    required this.pxPerBar,
    required this.labelEvery,
    required this.gridLine,
    required this.lineWidth,
  });

  final double pxPerBar;

  /// Labelled bars get the gridline; the ones between them stay clean, which
  /// is what keeps a 33-bar arrangement from reading as a fence.
  final int labelEvery;
  final Color gridLine;
  final double lineWidth;

  late final Paint _line =
      Paint()
        ..color = gridLine
        ..strokeWidth = lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final int bars = (size.width / pxPerBar).ceil();
    for (int bar = 0; bar <= bars; bar += labelEvery) {
      final double x = bar * pxPerBar;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _line);
    }
  }

  @override
  bool shouldRepaint(_PlaylistBackgroundPainter oldDelegate) =>
      oldDelegate.pxPerBar != pxPerBar ||
      oldDelegate.labelEvery != labelEvery ||
      oldDelegate.gridLine != gridLine;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.x,
    required this.color,
    required this.width,
  });

  final double x;
  final Color color;
  final double width;

  late final Paint _paint =
      Paint()
        ..color = color
        ..strokeWidth = width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), _paint);
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) =>
      oldDelegate.x != x || oldDelegate.color != color;
}
