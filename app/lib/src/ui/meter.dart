// The master meter (OB-1-11 §3).
//
// A CustomPainter driven directly by the per-frame Listenable, so the widget
// tree does not rebuild at 120 Hz — only this painter repaints. Every Paint and
// Rect it needs is created once in the constructor; paint() allocates nothing.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'engine_controller.dart';
import 'meter_state.dart';

class MasterMeter extends StatelessWidget {
  const MasterMeter({required this.repaint, required this.meter, super.key});

  /// Takes the level source and the repaint signal rather than the whole
  /// controller: the meter needs nothing else, and the narrower dependency is
  /// what lets the paint-cost benchmark drive it without an engine.
  MasterMeter.of(EngineController controller, {Key? key})
      : this(repaint: controller, meter: controller.meter, key: key);

  final Listenable repaint;
  final MeterState meter;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Semantics(
      label: 'Master output level',
      child: SizedBox(
        width: tokens.size.meterWidth,
        height: (tokens.size.meterChannelHeight * 2) + tokens.size.meterGap,
        child: CustomPaint(
          painter: _MeterPainter(
            repaint: repaint,
            meter: meter,
            tokens: tokens,
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required Listenable repaint,
    required this.meter,
    required this.tokens,
  })  : _track = Paint()..color = tokens.color.meterTrack,
        _low = Paint()..color = tokens.color.meterLow,
        _mid = Paint()..color = tokens.color.meterMid,
        _high = Paint()..color = tokens.color.meterHigh,
        _hold = Paint()..color = tokens.color.textPrimary,
        super(repaint: repaint);

  final MeterState meter;
  final OneBeatTokens tokens;

  // Conventional segmentation, never restyled (PRD §15.3): green up to -12 dB,
  // amber from -12 to -3, red above -3.
  static const double _amberDb = -12;
  static const double _redDb = -3;

  final Paint _track;
  final Paint _low;
  final Paint _mid;
  final Paint _high;
  final Paint _hold;

  @override
  void paint(Canvas canvas, Size size) {
    final double channelHeight = tokens.size.meterChannelHeight;
    final double gap = tokens.size.meterGap;
    _paintChannel(canvas, size, 0, channelHeight, meter.left);
    _paintChannel(canvas, size, channelHeight + gap, channelHeight, meter.right);
  }

  void _paintChannel(Canvas canvas, Size size, double top, double height, ChannelMeter channel) {
    canvas.drawRect(Rect.fromLTWH(0, top, size.width, height), _track);

    final double level = dbToFraction(channel.levelDb) * size.width;
    if (level > 0) {
      final double amber = dbToFraction(_amberDb) * size.width;
      final double red = dbToFraction(_redDb) * size.width;

      canvas.drawRect(Rect.fromLTWH(0, top, level.clamp(0, amber), height), _low);
      if (level > amber) {
        canvas.drawRect(
          Rect.fromLTWH(amber, top, (level - amber).clamp(0, red - amber), height),
          _mid,
        );
      }
      if (level > red) {
        canvas.drawRect(Rect.fromLTWH(red, top, level - red, height), _high);
      }
    }

    // Peak hold: a one-pixel marker at the highest recent level.
    final double hold = dbToFraction(channel.peakHoldDb) * size.width;
    if (hold > 0) {
      canvas.drawRect(
        Rect.fromLTWH((hold - 1).clamp(0, size.width - 1), top, 1, height),
        channel.peakHoldDb >= _redDb ? _high : _hold,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) => false; // driven by `repaint`

  @override
  bool shouldRebuildSemantics(_MeterPainter oldDelegate) => false;
}
