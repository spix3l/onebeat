// ObClipCard — one block of arrangement (UI-B-08).
//
// The card is the only saturated thing on the playlist canvas, which is the
// whole point: the arrangement is read by colour and shape from across the
// room, and everything around it stays grey so it can be.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

@immutable
class ClipVm {
  const ClipVm({
    required this.id,
    required this.name,
    required this.duration,
    required this.color,
    required this.startBar,
    required this.lengthBars,
    required this.lane,
    this.selected = false,
    this.isAudio = false,
    this.waveform = const <double>[],
  });

  final int id;
  final String name;

  /// Already formatted (`0:08`). The vm owns time formatting; the card owns
  /// only the look.
  final String duration;

  /// The clip's identity colour, from `ColorTokens.channelColors`.
  final Color color;

  /// Position and length in bars — fractional, because the mockup's clips do
  /// not all start on a bar line.
  final double startBar;
  final double lengthBars;

  /// Which row the clip sits on, zero-based.
  final int lane;

  final bool selected;
  final bool isAudio;
  final List<double> waveform;
}

class ObClipCard extends StatefulWidget {
  const ObClipCard({
    required this.vm,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    super.key,
  });

  final ClipVm vm;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onPanCancel;

  @override
  State<ObClipCard> createState() => _ObClipCardState();
}

class _ObClipCardState extends State<ObClipCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null || widget.onPanStart != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: widget.onPanStart,
        onPanUpdate: widget.onPanUpdate,
        onPanEnd: widget.onPanEnd,
        onPanCancel: widget.onPanCancel,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xs,
          ),
          decoration: BoxDecoration(
              // Keep the saturated identity colour, but let the arrangement
              // grid show through the clip body.
              color: widget.vm.color.withValues(alpha: 0.58),
            borderRadius: BorderRadius.all(tokens.radius.lg),
            border: Border.all(
              // Selection brightens the edge rather than the fill: the fill is
              // the clip's identity and must not change when you click it.
              color:
                  widget.vm.selected
                      ? color.clipSelectedOutline
                      : (_hover ? color.textPrimary : color.none),
              width: tokens.border.emphasis,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (widget.vm.isAudio && widget.vm.waveform.isNotEmpty)
                CustomPaint(
                  painter: AudioWaveformPainter(
                    samples: widget.vm.waveform,
                    color: color.clipInkMuted,
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.vm.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.clipName,
                  ),
                  Text(
                    widget.vm.duration,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: tokens.type.clipDuration,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a compact mirrored peak envelope over an audio clip. The samples are
/// normalised peak values, so this painter does not need to know the source
/// sample rate or duration.
class AudioWaveformPainter extends CustomPainter {
  AudioWaveformPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, size.width / samples.length * 0.62);
    final double middle = size.height / 2;
    final double halfHeight = size.height * 0.44;
    for (int index = 0; index < samples.length; index++) {
      final double x = samples.length == 1
          ? size.width / 2
          : index * size.width / (samples.length - 1);
      final double half = halfHeight * samples[index].clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(x, middle - half),
        Offset(x, middle + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.samples, samples);
}
