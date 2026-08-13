// Meter ballistics (OB-1-11 §3).
//
// The rule that matters here: decay is computed from the *snapshot's* wall-clock
// timestamp, never from a frame counter. If the UI drops frames, the meter must
// fall at the same rate it always does — a meter that decays faster on a slow
// machine is lying about the signal.
import 'dart:math' as math;

import '../design/tokens.dart';
import '../engine/engine_client.dart';

/// Linear amplitude to dBFS, floored so silence is a number rather than -inf.
double amplitudeToDb(double amplitude) {
  if (amplitude <= 0.000015849) {
    return minimumDb;
  }
  return 20.0 * (math.log(amplitude) / math.ln10);
}

const double minimumDb = -96.0;
const double meterFloorDb = -60.0;

/// Position of a dB value on the meter, 0 at the floor and 1 at 0 dBFS.
double dbToFraction(double db) {
  if (db <= meterFloorDb) {
    return 0;
  }
  if (db >= 0) {
    return 1;
  }
  return 1.0 - (db / meterFloorDb);
}

class ChannelMeter {
  double levelDb = minimumDb;
  double peakHoldDb = minimumDb;
  double _peakHoldAgeSeconds = 0;

  void update(double amplitudeDb, double deltaSeconds, MotionTokens motion) {
    final double attack = motion.meterAttackDbPerSecond * deltaSeconds;
    final double decay = motion.meterDecayDbPerSecond * deltaSeconds;

    if (amplitudeDb > levelDb) {
      levelDb = math.min(amplitudeDb, levelDb + attack);
    } else {
      levelDb = math.max(amplitudeDb, levelDb - decay);
    }

    _peakHoldAgeSeconds += deltaSeconds;
    if (amplitudeDb >= peakHoldDb) {
      peakHoldDb = amplitudeDb;
      _peakHoldAgeSeconds = 0;
    } else if (_peakHoldAgeSeconds > motion.meterPeakHoldSeconds) {
      peakHoldDb = math.max(amplitudeDb, peakHoldDb - decay);
    }
  }

  void reset() {
    levelDb = minimumDb;
    peakHoldDb = minimumDb;
    _peakHoldAgeSeconds = 0;
  }
}

/// Stereo meter state. Mutated in place once per frame: no allocation on the
/// paint path (OB-1-11 AC).
class MeterState {
  final ChannelMeter left = ChannelMeter();
  final ChannelMeter right = ChannelMeter();

  bool clipping = false;
  int _lastHostTimeNanos = 0;

  void update(EngineSnapshot snapshot, MotionTokens motion) {
    double deltaSeconds;
    if (_lastHostTimeNanos == 0 ||
        snapshot.hostTimeNanos <= _lastHostTimeNanos) {
      // First frame, or the engine has not published since the last read: use a
      // nominal 120 Hz step rather than zero so a stalled engine still decays.
      deltaSeconds = 1 / 120;
    } else {
      deltaSeconds =
          (snapshot.hostTimeNanos - _lastHostTimeNanos) / 1000000000.0;
      // Clamp: a paused debugger or a backgrounded window must not make the
      // meter jump to silence in one frame.
      deltaSeconds = deltaSeconds.clamp(0.0, 0.25);
    }
    if (snapshot.hostTimeNanos != 0) {
      _lastHostTimeNanos = snapshot.hostTimeNanos;
    }

    left.update(amplitudeToDb(snapshot.peakLeft), deltaSeconds, motion);
    right.update(amplitudeToDb(snapshot.peakRight), deltaSeconds, motion);
    clipping = snapshot.peakLeft >= 1.0 || snapshot.peakRight >= 1.0;
  }

  void reset() {
    left.reset();
    right.reset();
    clipping = false;
    _lastHostTimeNanos = 0;
  }
}
