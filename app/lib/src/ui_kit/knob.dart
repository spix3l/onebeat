// ObKnob — the compact circular knob (UI-B-01).
//
// 26px across, matching `ui-files/components/knob.png`: a dark well with a
// hairline ring and a single pointer line that sweeps with the value. Drag
// vertically to change; there is deliberately no arc, no fill gauge and no
// radial-drag gesture — the mockup shows a pointer, so a pointer is all this
// paints.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// The pointer sweeps this many degrees, centred on straight up, so `value`
/// 0, 0.5 and 1 point to seven-o'clock, twelve and five-o'clock.
const double _knobSweepDegrees = 270;

/// How much of the value range one logical pixel of drag is worth.
const double _dragSensitivity = 0.005;

class ObKnob extends StatefulWidget {
  const ObKnob({
    required this.value,
    required this.onChanged,
    this.accent = false,
    this.label,
    super.key,
  });

  /// 0..1. Clamped on drag; painted as-is when passed directly.
  final double value;
  final ValueChanged<double>? onChanged;

  /// Tints the pointer with the accent rather than the standard indicator.
  final bool accent;

  /// Optional micro-caps caption under the knob (`VOL`, `PAN`).
  final String? label;

  @override
  State<ObKnob> createState() => _ObKnobState();
}

class _ObKnobState extends State<ObKnob> {
  double _dragValue = 0;

  void _onDrag(DragUpdateDetails details) {
    if (widget.onChanged == null) {
      return;
    }
    _dragValue = (_dragValue - details.delta.dy * _dragSensitivity).clamp(
      0.0,
      1.0,
    );
    widget.onChanged!(_dragValue);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double size = tokens.size.knobSmall;
    final Widget knob = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragValue = widget.value.clamp(0.0, 1.0),
      onVerticalDragUpdate: widget.onChanged == null ? null : _onDrag,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _KnobPainter(
            tokens: tokens,
            value: widget.value,
            accent: widget.accent,
          ),
        ),
      ),
    );
    final String? label = widget.label;
    if (label == null) {
      return knob;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        knob,
        SizedBox(height: tokens.spacing.xxs),
        Text(label.toUpperCase(), style: tokens.type.microCaps),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({
    required this.tokens,
    required this.value,
    required this.accent,
  });

  final OneBeatTokens tokens;
  final double value;
  final bool accent;

  @override
  void paint(Canvas canvas, Size size) {
    final ColorTokens color = tokens.color;
    final double stroke = tokens.border.hairline;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - stroke;

    final Paint fill = Paint()..color = color.knobTrack;
    canvas.drawCircle(center, radius, fill);

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.lineStrong;
    canvas.drawCircle(center, radius, ring);

    // The pointer runs from the centre out to the ring; a hub dot keeps the
    // centre from reading as hollow when the pointer is near vertical.
    final double angle = -math.pi / 2 + _knobSweepDegrees * math.pi / 180 * (value.clamp(0.0, 1.0) - 0.5);
    final Offset tip = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    final Paint pointer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.emphasis
      ..strokeCap = StrokeCap.round
      ..color = accent ? color.accentBright : color.knobIndicator;
    canvas.drawLine(center, tip, pointer);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) => oldDelegate.value != value || oldDelegate.accent != accent;
}
