// StripMeter — the vertical level meter inside a mixer strip (UI-B-09).
//
// The bar grows up from the bottom of a near-black well, and its fill carries
// the conventional green-amber-red ramp with green at the *top* of the bar:
// that is what the mockups draw, and it means a quiet signal is a short bar
// that is still mostly green rather than a stub of red.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

class StripMeter extends StatelessWidget {
  const StripMeter({required this.level, this.width, super.key});

  /// 0..1.
  final double level;

  /// Defaults to [SizeTokens.mixerMeterWidth]; the master's is wider.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: width ?? tokens.size.mixerMeterWidth,
      child: CustomPaint(
        painter: StripMeterPainter(
          level: level,
          track: tokens.color.meterTrack,
          low: tokens.color.meterLow,
          mid: tokens.color.meterMid,
          high: tokens.color.meterHigh,
          radius: tokens.radius.xs,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class StripMeterPainter extends CustomPainter {
  StripMeterPainter({
    required this.level,
    required this.track,
    required this.low,
    required this.mid,
    required this.high,
    required this.radius,
  });

  final double level;
  final Color track;
  final Color low;
  final Color mid;
  final Color high;
  final Radius radius;

  // Allocated once. A mixer paints a dozen of these every frame the transport
  // is running, so `paint` must not build objects.
  late final Paint _trackPaint = Paint()..color = track;
  late final Paint _fillPaint = Paint();
  late final List<Color> _stops = <Color>[low, mid, high];

  @override
  void paint(Canvas canvas, Size size) {
    final RRect well = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      radius,
    );
    canvas.drawRRect(well, _trackPaint);

    final double unit = level.clamp(0.0, 1.0);
    if (unit <= 0) {
      return;
    }
    final Rect bar = Rect.fromLTWH(
      0,
      size.height * (1 - unit),
      size.width,
      size.height * unit,
    );
    // The gradient is built against the bar, not the well: the ramp belongs to
    // the signal that is there, so a short bar still shows its own head.
    _fillPaint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _stops,
    ).createShader(bar);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, radius), _fillPaint);
  }

  @override
  bool shouldRepaint(StripMeterPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.track != track ||
      oldDelegate.low != low ||
      oldDelegate.mid != mid ||
      oldDelegate.high != high;
}

/// The floating window's fader: the same ramp under a draggable cap, with the
/// track above the cap left dark so the cap reads as a position rather than as
/// a second bar.
class StripFader extends StatelessWidget {
  const StripFader({
    required this.position,
    this.selected = false,
    this.onChanged,
    super.key,
  });

  /// 0..1, bottom to top.
  final double position;

  /// A selected strip's cap takes the accent, which is how the mockup marks
  /// the strip the routing panel is describing.
  final bool selected;

  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        void report(Offset local) {
          if (onChanged == null || constraints.maxHeight <= 0) {
            return;
          }
          onChanged!(
            (1 - local.dy / constraints.maxHeight).clamp(0.0, 1.0),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: onChanged == null ? null : (DragUpdateDetails d) => report(d.localPosition),
          onTapDown: onChanged == null ? null : (TapDownDetails d) => report(d.localPosition),
          child: CustomPaint(
            painter: _FaderPainter(
              position: position,
              track: color.meterTrack,
              low: color.meterLow,
              mid: color.meterMid,
              high: color.meterHigh,
              cap: selected ? color.accent : color.textPrimary,
              trackWidth: tokens.size.mixerFaderTrackWidth,
              capWidth: tokens.size.mixerFaderCapWidth,
              capHeight: tokens.size.mixerFaderCapHeight,
              radius: tokens.radius.xs,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _FaderPainter extends CustomPainter {
  _FaderPainter({
    required this.position,
    required this.track,
    required this.low,
    required this.mid,
    required this.high,
    required this.cap,
    required this.trackWidth,
    required this.capWidth,
    required this.capHeight,
    required this.radius,
  });

  final double position;
  final Color track;
  final Color low;
  final Color mid;
  final Color high;
  final Color cap;
  final double trackWidth;
  final double capWidth;
  final double capHeight;
  final Radius radius;

  late final Paint _trackPaint = Paint()..color = track;
  late final Paint _fillPaint = Paint();
  late final Paint _capPaint = Paint()..color = cap;
  late final List<Color> _stops = <Color>[low, mid, high];

  @override
  void paint(Canvas canvas, Size size) {
    final double left = (size.width - trackWidth) / 2;
    final Rect column = Rect.fromLTWH(left, 0, trackWidth, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(column, radius),
      _trackPaint,
    );

    final double unit = position.clamp(0.0, 1.0);
    final double capCentre = size.height * (1 - unit);
    final Rect fill = Rect.fromLTRB(
      left,
      capCentre,
      left + trackWidth,
      size.height,
    );
    if (fill.height > 0) {
      _fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _stops,
      ).createShader(fill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, radius),
        _fillPaint,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, capCentre),
          width: capWidth,
          height: capHeight,
        ),
        radius,
      ),
      _capPaint,
    );
  }

  @override
  bool shouldRepaint(_FaderPainter oldDelegate) => oldDelegate.position != position || oldDelegate.cap != cap;
}
