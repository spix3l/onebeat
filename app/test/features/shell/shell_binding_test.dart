// Shell binding tests (UI-D-01).
//
// Proves the mapping between the engine client and the ShellScreenVm, tests
// that callbacks (play, stop, undo, redo, rail select) reach the engine and
// change workspace views.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/shell/shell_binding.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

import '../../support/stage3_harness.dart';

class _FakeEngineClient implements EngineClient {
  bool isPlaying = false;
  bool isLooping = false;
  double bpm = 124.0;
  int bar = 2;
  int beat = 1;
  int tick = 218;
  int undoCount = 0;
  int redoCount = 0;
  int seekFramesCount = 0;

  @override
  bool get canUndoProject => true;

  @override
  bool get canRedoProject => true;

  @override
  String get undoProjectName => 'Add Note';

  @override
  String get redoProjectName => 'Add Note';

  @override
  EngineSnapshot readSnapshot() => EngineSnapshot(
        playing: isPlaying,
        loopEnabled: isLooping,
        loopStartBeats: 0,
        loopEndBeats: 4,
        positionFrames: 0,
        positionBeats: 4.5,
        positionSeconds: 2.25,
        hostTimeNanos: 1000000,
        tempoBpm: bpm,
        bar: bar,
        beat: beat,
        tick: tick,
        sampleRate: 48000,
        blockFrames: 128,
        activeVoices: 2,
        peakLeft: 0.55,
        peakRight: 0.48,
        rmsLeft: 0.4,
        rmsRight: 0.4,
        cpuLoad: 0.04,
        xrunCount: 0,
        latencyFramesRoundTrip: 256,
        scheduleEventCount: 0,
      );

  @override
  List<EngineEvent> pollEvents() => const <EngineEvent>[];

  @override
  void play() => isPlaying = true;

  @override
  void stop() => isPlaying = false;

  @override
  void setTempo(double tempo) => bpm = tempo;

  @override
  void setLoop(double startBeats, double endBeats, {bool enabled = true}) {
    isLooping = enabled;
  }

  @override
  void seekFrames(int frames) => seekFramesCount++;

  @override
  void undoProject() => undoCount++;

  @override
  void redoProject() => redoCount++;

  @override
  void cancelPluginScan() {}

  @override
  void loadPluginCache() {}

  @override
  PluginScanStatus readPluginScanStatus() => const PluginScanStatus.idle();

  @override
  List<PluginListing> readPluginList(int count) => const <PluginListing>[];

  @override
  RackPattern readRackPattern() => const RackPattern(
        id: 'pattern',
        name: 'Pattern 1',
        lengthTicks: 3840,
        baseGridTicks: 240,
        swing: 0,
      );

  @override
  List<RackRow> readRackRows() => const <RackRow>[];

  @override
  List<PatternSummary> readPatterns() => const <PatternSummary>[];

  @override
  List<ArrangementLane> readLanes() => const <ArrangementLane>[];

  @override
  List<ArrangementClip> readClips() => const <ArrangementClip>[];

  @override
  List<SequenceNote> readNotes(String instrumentId) => const <SequenceNote>[];

  @override
  List<ProjectInstrument> readInstruments() => const <ProjectInstrument>[];

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('ShellBinding formats readouts and propagates transport state', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient();

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    // BPM, SIG, and Position formatting
    expect(find.text('124.00'), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);
    expect(find.text('02:01:218'), findsOneWidget);

    // Initial transport status
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('play and loop callbacks reach the engine client', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient();

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    expect(client.isPlaying, isFalse);

    // Tap Play button (index 2 in the transport cluster: undo, redo, play, stop, loop)
    await tester.tap(find.byType(ObTransportButton).at(2));
    await tester.pump();
    expect(client.isPlaying, isTrue);

    // Tap Loop button (index 4)
    await tester.tap(find.byType(ObTransportButton).at(4));
    await tester.pump();
    expect(client.isLooping, isTrue);

    // Tap Stop button (index 3)
    await tester.tap(find.byType(ObTransportButton).at(3));
    await tester.pump();
    expect(client.isPlaying, isFalse);
  });

  testWidgets('undo and redo callbacks reach the engine client', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient();

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    // Tap Undo (index 0)
    await tester.tap(find.byType(ObTransportButton).at(0));
    await tester.pump();
    expect(client.undoCount, 1);

    // Tap Redo (index 1)
    await tester.tap(find.byType(ObTransportButton).at(1));
    await tester.pump();
    expect(client.redoCount, 1);
  });

  testWidgets('rail selection switches active index', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient();

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    // Initial state: Playlist active (index 0)
    final ObSideRail railInitial = tester.widget(find.byType(ObSideRail));
    expect(railInitial.vm.activeIndex, 0);

    // Tap Channels (index 1)
    await tester.tap(find.text('CHANNELS'));
    await tester.pump();

    final ObSideRail railChannels = tester.widget(find.byType(ObSideRail));
    expect(railChannels.vm.activeIndex, 1);

    // Tap Piano (index 2)
    await tester.tap(find.text('PIANO'));
    await tester.pump();

    final ObSideRail railPiano = tester.widget(find.byType(ObSideRail));
    expect(railPiano.vm.activeIndex, 2);

    // Tap Mixer (index 3)
    await tester.tap(find.text('MIXER'));
    await tester.pump();

    final ObSideRail railMixer = tester.widget(find.byType(ObSideRail));
    expect(railMixer.vm.activeIndex, 3);
  });
}
