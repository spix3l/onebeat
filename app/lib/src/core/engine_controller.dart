// One ticker, one snapshot read, one notification per frame (OB-1-11 §4).
//
// Everything the UI shows in real time (meter, clock, voice count, xruns) comes
// from the *same* snapshot, so nothing can disagree with anything else on
// screen.
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'frame_stats.dart';
import 'meter_state.dart';

class EngineController extends ChangeNotifier {
  EngineController({
    required this.client,
    required TickerProvider vsync,
    required this.motion,
  }) {
    _ticker = vsync.createTicker(_onFrame)..start();
  }

  final EngineClient client;
  final MotionTokens motion;
  final MeterState meter = MeterState();
  final FrameStats frameStats = FrameStats();

  late final Ticker _ticker;

  EngineSnapshot snapshot = const EngineSnapshot.empty();
  String status = '';
  bool showPerformanceOverlay = false;

  void _onFrame(Duration _) {
    snapshot = client.readSnapshot();
    meter.update(snapshot, motion);

    for (final EngineEvent event in client.pollEvents()) {
      switch (event.type) {
        case evtDeviceLost:
          status =
              'Output device "${event.text}" disappeared. Playing on the default device.';
        case evtDeviceChanged:
          status = 'Output device changed to "${event.text}".';
        case evtError:
          status = event.text;
        case evtSampleLoaded:
          status = 'Loaded "${event.text}".';
      }
    }
    notifyListeners();
  }

  /// Play / stop. Stopping returns the playhead to zero, so the next Space
  /// always starts from the top — the "restart the timer on stop" behaviour.
  void togglePlay() {
    if (snapshot.playing) {
      client.stop();
      client.seekFrames(0);
    } else {
      client.play();
    }
  }

  /// Pause / resume (⌥Space). Unlike [togglePlay], pausing leaves the playhead
  /// where it is, so resuming continues from the same place.
  void togglePause() {
    if (snapshot.playing) {
      client.stop();
    } else {
      client.play();
    }
  }

  void play() => client.play();

  void stop() => client.stop();

  void toggleLoop() {
    client.setLoop(
      snapshot.loopStartBeats,
      snapshot.loopEndBeats,
      enabled: !snapshot.loopEnabled,
    );
  }

  void seekFrames(int frames) => client.seekFrames(frames);

  void setTempo(double bpm) => client.setTempo(bpm);

  void togglePerformanceOverlay() {
    showPerformanceOverlay = !showPerformanceOverlay;
    frameStats.reset();
    notifyListeners();
  }

  void undoProject() {
    if (!client.canUndoProject) return;
    client.undoProject();
    notifyListeners();
  }

  void redoProject() {
    if (!client.canRedoProject) return;
    client.redoProject();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    frameStats.dispose();
    super.dispose();
  }
}
