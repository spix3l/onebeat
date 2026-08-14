// One ticker, one snapshot read, one notification per frame.
//
// Everything the UI shows in real time (meter, clock, voice count, xruns) comes
// from the *same* snapshot, so nothing can disagree with anything else on
// screen (OB-1-11 §4).
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'arrangement_store.dart';
import 'frame_stats.dart';
import 'meter_state.dart';
import 'pattern_store.dart';
import 'piano_roll_store.dart';
import 'plugin_library_store.dart';
import 'rack_store.dart';

/// Which editor the centre of the shell is showing. Mirrors the design's view
/// switcher (`onebeat-shell.html`): the three Stage 3 surfaces edit the same
/// project through the same command bus, so switching between them is pure
/// presentation and costs nothing.
enum WorkspaceView {
  arrangement,
  rack,
  pianoRoll,
  mixer,
  console,
  plugins,
  extensions,
}

class EngineController extends ChangeNotifier {
  EngineController({
    required this.client,
    required TickerProvider vsync,
    required this.motion,
  }) : library = PluginLibraryStore(client),
       rack = RackStore(client),
       patterns = PatternStore(client) {
    // One PatternStore, shared by the selector, the roll and the arrangement.
    // Not three: D-M6's "warned once this session" set lives in it, and a copy
    // per editor would show the notice once per view instead of once per
    // pattern — which is the nagging the rule exists to prevent.
    arrangement = ArrangementStore(client, patterns);
    pianoRoll = PianoRollStore(client, patterns);
    _ticker = vsync.createTicker(_onFrame)..start();
  }

  final EngineClient client;
  final MotionTokens motion;
  final MeterState meter = MeterState();
  final FrameStats frameStats = FrameStats();

  /// Driven from this controller's frame callback rather than its own ticker.
  final PluginLibraryStore library;
  final RackStore rack;
  final PatternStore patterns;
  late final ArrangementStore arrangement;
  late final PianoRollStore pianoRoll;

  /// Which editor the shell's centre shows.
  ///
  /// The playlist, as the design screens open on: it is the view that shows
  /// the whole project, and the rack is a detail of one pattern within it.
  ///
  /// A notifier of its own, and not just a field read during the shell's
  /// build, because this controller notifies on **every frame** — the meter and
  /// the clock need that. Rebuilding the rail and the whole workspace from
  /// those notifications would repaint every editor at display rate to show a
  /// view that changes once; reading the field without listening at all is
  /// worse still, and was the actual bug: clicking a rail tile moved the top
  /// bar's switcher and left the rail and the editor behind it unchanged.
  final ValueNotifier<WorkspaceView> viewNotifier =
      ValueNotifier<WorkspaceView>(WorkspaceView.arrangement);

  WorkspaceView get view => viewNotifier.value;

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
    // Only while a scan is in flight: an idle app should not be making a native
    // call every frame to be told nothing happened.
    if (library.status.isScanning) {
      library.pump();
    }

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

  void setView(WorkspaceView value) {
    if (view == value) return;
    viewNotifier.value = value;
    // Each editor re-reads on entry rather than staying live: an edit made in
    // another view has already changed the model underneath it.
    switch (value) {
      case WorkspaceView.rack:
        rack.refresh();
      case WorkspaceView.pianoRoll:
        pianoRoll.refresh();
      case WorkspaceView.arrangement:
        arrangement.refresh();
      case WorkspaceView.mixer:
      case WorkspaceView.plugins:
      case WorkspaceView.console:
      case WorkspaceView.extensions:
        break;
    }
    notifyListeners();
  }

  /// Points every editor at one pattern. The clip id travels with it so the
  /// D-M6 notice can offer "Make unique for this clip" when the edit that
  /// follows turns out to touch a shared pattern.
  void openPattern(String patternId, {String fromClipId = ''}) {
    patterns.select(patternId, fromClipId: fromClipId);
    rack.refresh();
    pianoRoll.refresh();
    arrangement.refresh();
    notifyListeners();
  }

  /// Points the piano roll at one instrument's sequence in the current pattern,
  /// and loads the other instruments' notes as the ghost layer.
  void editInPianoRoll(String instrumentId, {String fromClipId = ''}) {
    pianoRoll.load(instrumentId, fromClipId: fromClipId);
    pianoRoll.setGhostNotes(_ghostNotesFor(instrumentId));
    setView(WorkspaceView.pianoRoll);
  }

  List<SequenceNote> _ghostNotesFor(String instrumentId) {
    final List<SequenceNote> ghosts = <SequenceNote>[];
    for (final ProjectInstrument instrument in library.instruments) {
      if (instrument.id == instrumentId) continue;
      ghosts.addAll(client.readNotes(instrument.id));
    }
    return ghosts;
  }

  /// One refresh path for every store, used after undo, redo and any edit that
  /// can reach across editors. Cheap: these are native reads of small lists,
  /// and none of it happens per frame.
  void refreshAll() {
    library.refreshInstance();
    library.refreshInstruments();
    rack.refresh();
    patterns.refresh();
    arrangement.refresh();
    pianoRoll.refresh();
    notifyListeners();
  }

  void undoProject() {
    if (!client.canUndoProject) return;
    client.undoProject();
    refreshAll();
  }

  void redoProject() {
    if (!client.canRedoProject) return;
    client.redoProject();
    refreshAll();
  }

  @override
  void dispose() {
    _ticker.dispose();
    viewNotifier.dispose();
    frameStats.dispose();
    library.cancelScan();
    library.dispose();
    rack.dispose();
    patterns.dispose();
    arrangement.dispose();
    pianoRoll.dispose();
    super.dispose();
  }
}
