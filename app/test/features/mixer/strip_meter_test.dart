// StripMeter painter: the paint-cost contract against the 120 Hz frame budget.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/meter_state.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/mixer/strip_meter.dart';

/// One frame at 120 Hz.
const double budget120Hz = 1000 / 120;

/// The painter may use this fraction of the budget.
const double allowedFractionOfBudget = 0.1;

void main() {
  testWidgets('the painter costs a negligible fraction of a 120 Hz frame', (
    WidgetTester tester,
  ) async {
    final MeterState meter = MeterState();
    final OneBeatTokens tokens = OneBeatTokens.dark();

    meter.left.levelDb = -1.5;
    meter.left.peakHoldDb = -0.5;
    meter.right.levelDb = -8;
    meter.right.peakHoldDb = -6;

    final StripMeterPainter painter = StripMeterPainter(
      level: dbToFraction(meter.left.levelDb),
      track: tokens.color.meterTrack,
      low: tokens.color.meterLow,
      mid: tokens.color.meterMid,
      high: tokens.color.meterHigh,
      radius: tokens.radius.xs,
    );
    const Size size = Size(8, 200);

    const int warmup = 200;
    const int iterations = 2000;

    for (int i = 0; i < warmup; i++) {
      _paintOnce(painter, size);
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    for (int i = 0; i < iterations; i++) {
      _paintOnce(painter, size);
    }
    stopwatch.stop();

    final double perPaintMillis = stopwatch.elapsedMicroseconds / 1000.0 / iterations;
    final double percentOfBudget = perPaintMillis / budget120Hz * 100;

    debugPrint(
      'meter paint: ${perPaintMillis.toStringAsFixed(4)} ms/frame '
      '(${percentOfBudget.toStringAsFixed(2)}% of the 8.33 ms budget)',
    );

    expect(
      perPaintMillis,
      lessThan(budget120Hz * allowedFractionOfBudget),
      reason:
          'the meter painter must stay far inside a 120 Hz frame; '
          'measured ${perPaintMillis.toStringAsFixed(4)} ms',
    );
  });

  testWidgets('painting allocates no new Paint objects per frame', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final StripMeterPainter painter = StripMeterPainter(
      level: 0.8,
      track: tokens.color.meterTrack,
      low: tokens.color.meterLow,
      mid: tokens.color.meterMid,
      high: tokens.color.meterHigh,
      radius: tokens.radius.xs,
    );

    expect(painter.shouldRepaint(painter), isFalse);
  });
}

void _paintOnce(CustomPainter painter, Size size) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}
