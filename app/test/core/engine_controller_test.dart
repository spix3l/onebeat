// Core engine controller unit tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/engine_controller.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';

class _FakeEngineClient implements EngineClient {
  bool isPlaying = false;
  bool isLooping = false;
  double bpm = 120.0;
  int seekTarget = 0;
  int undoCount = 0;
  int redoCount = 0;

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
        positionFrames: seekTarget,
        positionBeats: 0,
        positionSeconds: 0,
        hostTimeNanos: 1000,
        tempoBpm: bpm,
        bar: 1,
        beat: 1,
        tick: 0,
        sampleRate: 48000,
        blockFrames: 128,
        activeVoices: 0,
        peakLeft: 0.5,
        peakRight: 0.5,
        rmsLeft: 0.4,
        rmsRight: 0.4,
        cpuLoad: 0.05,
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
  void seekFrames(int frames) => seekTarget = frames;

  @override
  void undoProject() => undoCount++;

  @override
  void redoProject() => redoCount++;

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('EngineController drives transport and client actions', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient fakeClient = _FakeEngineClient();
    final EngineController controller = EngineController(
      client: fakeClient,
      vsync: const TestVSync(),
      motion: const MotionTokens(),
    );

    // Initial state
    expect(controller.snapshot.playing, isFalse);

    // Toggle play
    controller.togglePlay();
    expect(fakeClient.isPlaying, isTrue);

    // Toggle loop
    controller.toggleLoop();
    expect(fakeClient.isLooping, isTrue);

    // Seek & Tempo
    controller.seekFrames(512);
    expect(fakeClient.seekTarget, 512);

    controller.setTempo(140.0);
    expect(fakeClient.bpm, 140.0);

    // Undo / Redo
    controller.undoProject();
    expect(fakeClient.undoCount, 1);

    controller.redoProject();
    expect(fakeClient.redoCount, 1);

    // Performance overlay toggle
    expect(controller.showPerformanceOverlay, isFalse);
    controller.togglePerformanceOverlay();
    expect(controller.showPerformanceOverlay, isTrue);

    controller.dispose();
  });

  testWidgets('Space restarts the timer on stop; pause keeps position', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient fakeClient = _FakeEngineClient();
    final EngineController controller = EngineController(
      client: fakeClient,
      vsync: const TestVSync(),
      motion: const MotionTokens(),
    );

    controller.togglePlay();
    expect(fakeClient.isPlaying, isTrue);
    await tester.pump();

    // Move the playhead, then stop with Space: it returns to zero.
    controller.seekFrames(512);
    controller.togglePlay();
    expect(fakeClient.isPlaying, isFalse);
    expect(fakeClient.seekTarget, 0);
    await tester.pump();

    // Pause instead: resume from the same place.
    controller.togglePause();
    await tester.pump();
    controller.seekFrames(1024);
    controller.togglePause();
    expect(fakeClient.isPlaying, isFalse);
    expect(fakeClient.seekTarget, 1024);

    controller.dispose();
  });
}
