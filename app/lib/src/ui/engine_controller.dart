// One ticker, one snapshot read, one notification per frame.
//
// Everything the UI shows in real time (meter, clock, voice count, xruns) comes
// from the *same* snapshot, so nothing can disagree with anything else on
// screen (OB-1-11 §4).
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'frame_stats.dart';
import 'meter_state.dart';

class EngineController extends ChangeNotifier {
  EngineController({required this.client, required TickerProvider vsync, required this.motion}) {
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

  /// The pattern the demo pads and the transport play. v0.1 content model.
  static const List<int> demoPattern = <int>[
    127, 0, 60, 0, 100, 0, 60, 40, //
    127, 0, 60, 0, 100, 30, 60, 0,
  ];

  void _onFrame(Duration _) {
    snapshot = client.readSnapshot();
    meter.update(snapshot, motion);

    for (final EngineEvent event in client.pollEvents()) {
      switch (event.type) {
        case evtDeviceLost:
          status = 'Output device "${event.text}" disappeared. Playing on the default device.';
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

  void togglePlay() {
    if (snapshot.playing) {
      client.stop();
    } else {
      client.play();
    }
  }

  void togglePerformanceOverlay() {
    showPerformanceOverlay = !showPerformanceOverlay;
    frameStats.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    frameStats.dispose();
    super.dispose();
  }
}
