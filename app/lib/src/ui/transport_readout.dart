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

  /// Every digit at its widest, in the format [_ReadoutPainter] paints.
  static const String _widestReading = '88:88:888';

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      // Sized to the widest reading the clock can ever show, so the digits
      // never grow into the caption beside them.
      width: measureText(tokens.type.numericLarge, _widestReading),
      height: tokens.size.readoutHeight,
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
  String _positionText = '';

  @override
  void paint(Canvas canvas, Size size) {
    final String position = _formatPosition();
    if (position != _positionText) {
      _positionText = position;
      _position
        ..text = TextSpan(text: position, style: tokens.type.numericLarge)
        ..textDirection = textDirection
        ..layout();
    }
    // One line, vertically centred in the well. There used to be a second line
    // of wall-clock time under it, which did not fit inside a 34px well and so
    // spilled over the bar's lower edge.
    _position.paint(canvas, Offset(0, (size.height - _position.height) / 2));
  }

  /// `02:01:218` — bars, beats, ticks, colon-separated as the design draws it.
  String _formatPosition() {
    final int bar = controller.snapshot.bar;
    final int beat = controller.snapshot.beat;
    final int tick = controller.snapshot.tick;
    return '${bar.toString().padLeft(2, '0')}:'
        '${beat.toString().padLeft(2, '0')}:'
        '${tick.toString().padLeft(3, '0')}';
  }

  @override
  bool shouldRepaint(_ReadoutPainter oldDelegate) => false; // driven by `repaint`
}
