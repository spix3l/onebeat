// Frame-timing instrumentation (OB-1-11 §5).
//
// Kept for every future UI ticket, not just this one: the 120 Hz claim is only
// worth something if it stays measured. Debug builds show the overlay; the
// numbers come from Flutter's own frame timings, not from our own stopwatch.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class FrameStats extends ChangeNotifier {
  FrameStats() {
    _callback = _onTimings;
    SchedulerBinding.instance.addTimingsCallback(_callback);
  }

  late final ui.TimingsCallback _callback;

  static const int _windowSize = 240;

  final List<double> _buildMillis = <double>[];
  final List<double> _rasterMillis = <double>[];

  int totalFrames = 0;
  int droppedFrames = 0;
  double worstFrameMillis = 0;
  double budgetMillis = 1000 / 120;

  double get averageBuildMillis => _average(_buildMillis);
  double get averageRasterMillis => _average(_rasterMillis);

  /// Refresh rate is read from the display so the budget is right on a 60 Hz
  /// external monitor as well as on a 120 Hz laptop panel.
  void syncToDisplay(ui.FlutterView view) {
    final double refreshRate = view.display.refreshRate;
    if (refreshRate > 1) {
      budgetMillis = 1000 / refreshRate;
    }
  }

  void reset() {
    _buildMillis.clear();
    _rasterMillis.clear();
    totalFrames = 0;
    droppedFrames = 0;
    worstFrameMillis = 0;
    notifyListeners();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      final double build = timing.buildDuration.inMicroseconds / 1000.0;
      final double raster = timing.rasterDuration.inMicroseconds / 1000.0;
      final double total = timing.totalSpan.inMicroseconds / 1000.0;

      _push(_buildMillis, build);
      _push(_rasterMillis, raster);
      totalFrames++;
      if (total > worstFrameMillis) {
        worstFrameMillis = total;
      }
      // A frame is dropped when the whole span exceeds one refresh interval,
      // with a small tolerance for measurement noise.
      if (total > budgetMillis * 1.5) {
        droppedFrames++;
      }
    }
    notifyListeners();
  }

  static void _push(List<double> samples, double value) {
    samples.add(value);
    if (samples.length > _windowSize) {
      samples.removeAt(0);
    }
  }

  static double _average(List<double> samples) {
    if (samples.isEmpty) {
      return 0;
    }
    double sum = 0;
    for (final double sample in samples) {
      sum += sample;
    }
    return sum / samples.length;
  }

  @override
  void dispose() {
    try {
      SchedulerBinding.instance.removeTimingsCallback(_callback);
    } catch (_) {
      // Ignored if binding was reset during tests.
    }
    super.dispose();
  }
}
