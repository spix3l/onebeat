// Bars.beats.ticks and minutes:seconds, painted rather than rebuilt.
//
// Both values come from the same snapshot the meter used in the same frame, so
// the clock and the meter can never disagree. The painter caches its
// TextPainters and only re-lays-out a line when its string actually changes,
// which keeps a 120 Hz clock off the widget-rebuild path entirely.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'engine_controller.dart';

class TransportReadout extends StatelessWidget {
  const TransportReadout({required this.controller, super.key});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.transportReadoutWidth,
      height: tokens.size.controlHeight,
      child: CustomPaint(
        painter: _ReadoutPainter(
          repaint: controller,
          controller: controller,
          tokens: tokens,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _ReadoutPainter extends CustomPainter {
  _ReadoutPainter({
    required Listenable repaint,
    required this.controller,
    required this.tokens,
    required this.textDirection,
  }) : super(repaint: repaint);

  final EngineController controller;
  final OneBeatTokens tokens;
  final TextDirection textDirection;

  final TextPainter _position = TextPainter();
  final TextPainter _clock = TextPainter();
  String _positionText = '';
  String _clockText = '';

  @override
  void paint(Canvas canvas, Size size) {
    final String position = _formatPosition();
    final String clock = _formatClock();

    if (position != _positionText) {
      _positionText = position;
      _position
        ..text = TextSpan(text: position, style: tokens.type.numericLarge)
        ..textDirection = textDirection
        ..layout();
    }
    if (clock != _clockText) {
      _clockText = clock;
      _clock
        ..text = TextSpan(text: clock, style: tokens.type.numericSmall)
        ..textDirection = textDirection
        ..layout();
    }

    _position.paint(canvas, Offset.zero);
    _clock.paint(canvas, Offset(0, _position.height + tokens.spacing.xxs));
  }

  String _formatPosition() {
    final int bar = controller.snapshot.bar;
    final int beat = controller.snapshot.beat;
    final int tick = controller.snapshot.tick;
    return '${bar.toString().padLeft(3, '0')}.$beat.${tick.toString().padLeft(3, '0')}';
  }

  String _formatClock() {
    final double seconds = controller.snapshot.positionSeconds;
    final int minutes = seconds ~/ 60;
    final double remainder = seconds - (minutes * 60);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toStringAsFixed(2).padLeft(5, '0')}';
  }

  @override
  bool shouldRepaint(_ReadoutPainter oldDelegate) => false; // driven by `repaint`
}
