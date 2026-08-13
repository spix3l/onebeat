// Meter ballistics must depend on wall-clock time, not on how many frames the
// UI managed to draw (OB-1-11 §3).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/meter_state.dart';

EngineSnapshot snapshotAt(int nanos, double peak) => EngineSnapshot(
      playing: true,
      loopEnabled: true,
      positionFrames: 0,
      positionBeats: 0,
      positionSeconds: 0,
      hostTimeNanos: nanos,
      tempoBpm: 120,
      bar: 1,
      beat: 1,
      tick: 0,
      sampleRate: 48000,
      blockFrames: 128,
      activeVoices: 0,
      peakLeft: peak,
      peakRight: peak,
      rmsLeft: peak,
      rmsRight: peak,
      cpuLoad: 0,
      xrunCount: 0,
      latencyFramesRoundTrip: 256,
      scheduleEventCount: 0,
    );

void main() {
  const MotionTokens motion = MotionTokens();

  test('dB mapping is anchored at 0 dBFS and the -60 dB floor', () {
    expect(amplitudeToDb(1.0), closeTo(0, 0.001));
    expect(amplitudeToDb(0.5), closeTo(-6.02, 0.01));
    expect(amplitudeToDb(0), minimumDb);
    expect(dbToFraction(0), 1.0);
    expect(dbToFraction(-60), 0.0);
    expect(dbToFraction(-30), closeTo(0.5, 0.001));
  });

  test('decay over one second is the same whether drawn at 120 Hz or at 12 Hz', () {
    const int oneSecond = 1000000000;

    final MeterState fast = MeterState()
      ..update(snapshotAt(0, 1.0), motion)
      ..update(snapshotAt(1000000, 1.0), motion);
    final MeterState slow = MeterState()
      ..update(snapshotAt(0, 1.0), motion)
      ..update(snapshotAt(1000000, 1.0), motion);

    // 120 frames of silence across one second.
    for (int frame = 1; frame <= 120; frame++) {
      fast.update(snapshotAt(1000000 + (oneSecond ~/ 120) * frame, 0), motion);
    }
    // 12 frames of silence across the same second — a badly stuttering UI.
    for (int frame = 1; frame <= 12; frame++) {
      slow.update(snapshotAt(1000000 + (oneSecond ~/ 12) * frame, 0), motion);
    }

    expect(fast.left.levelDb, closeTo(slow.left.levelDb, 0.5));
  });

  test('a stalled engine timestamp still decays the meter', () {
    final MeterState meter = MeterState()..update(snapshotAt(1000, 1.0), motion);
    final double afterPeak = meter.left.levelDb;
    for (int frame = 0; frame < 200; frame++) {
      meter.update(snapshotAt(1000, 0), motion); // timestamp never advances
    }
    expect(meter.left.levelDb, lessThan(afterPeak));
  });

  test('peak hold sits above the level and then falls', () {
    const int step = 8333333; // 120 Hz
    final MeterState meter = MeterState()..update(snapshotAt(step, 1.0), motion);
    for (int frame = 2; frame < 60; frame++) {
      meter.update(snapshotAt(step * frame, 0), motion);
    }
    expect(meter.left.peakHoldDb, greaterThan(meter.left.levelDb));

    for (int frame = 60; frame < 600; frame++) {
      meter.update(snapshotAt(step * frame, 0), motion);
    }
    expect(meter.left.peakHoldDb, lessThan(-40));
  });

  test('clipping is reported at and above full scale', () {
    final MeterState meter = MeterState()..update(snapshotAt(1000, 1.0), motion);
    expect(meter.clipping, isTrue);
    meter.update(snapshotAt(2000, 0.5), motion);
    expect(meter.clipping, isFalse);
  });
}
