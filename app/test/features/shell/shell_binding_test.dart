// Shell binding tests (UI-D-01).
//
// Proves the mapping between the engine client and the ShellScreenVm, tests
// that callbacks (play, stop, undo, redo, rail select) reach the engine and
// change workspace views.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/shortcuts.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/project/rename_project_dialog.dart';
import 'package:onebeat/src/features/shell/shell_binding.dart';
import 'package:onebeat/src/features/shell/shell_screen.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

import '../../support/app_harness.dart';

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
  List<PatternSummary> readPatterns() => const <PatternSummary>[
    PatternSummary(
      id: 'pat_a',
      name: 'Main Groove',
      color: '#EF6F91',
      lengthTicks: 3840,
      swing: 0,
      usageCount: 1,
      noteCount: 0,
      isCurrent: true,
    ),
  ];

  @override
  List<ArrangementLane> readLanes() => const <ArrangementLane>[];

  @override
  List<ArrangementClip> readClips() => const <ArrangementClip>[];

  @override
  List<SequenceNote> readNotes(String instrumentId) => const <SequenceNote>[];

  @override
  List<ProjectInstrument> readInstruments() => const <ProjectInstrument>[];

  // ----- project files ------------------------------------------------------

  String projectPathValue = '';
  String projectNameValue = 'Untitled';
  bool projectModified = false;
  final List<String> savedTo = <String>[];

  @override
  String get projectPath => projectPathValue;

  @override
  String get projectName => projectNameValue;

  @override
  bool get isProjectModified => projectModified;

  @override
  void setProjectName(String name) => projectNameValue = name;

  @override
  void saveProject(String path) {
    savedTo.add(path);
    projectPathValue = path;
    projectModified = false;
  }

  @override
  void openProject(String path) => projectPathValue = path;

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

    // The status bar names the project rather than inventing a file name.
    expect(find.text('Untitled'), findsOneWidget);
    expect(find.textContaining('Untitled.obt'), findsOneWidget);
  });

  testWidgets('⌘S saves in place once the project has a file', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient()
      ..projectPathValue = '/Music/Night Drive.obt'
      ..projectNameValue = 'Night Drive';

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    // Not pumpAndSettle: the shell's engine ticker never settles.
    await tester.pump();
    await tester.pump();

    expect(client.savedTo, <String>['/Music/Night Drive.obt']);
  });

  testWidgets('the rename dialog renames the project and its bundle', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient()
      ..projectPathValue = '/Music/Old.obt'
      ..projectNameValue = 'Old';

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    // Reached the way the menu reaches it: the registry intent, not a tap on
    // chrome the platform draws.
    final BuildContext context = tester.element(find.byType(ShellScreen));
    Actions.invoke(context, const RenameProjectIntent());
    await tester.pump();
    expect(find.byType(RenameProjectDialog), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, 'New');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('action:project.rename')));
    await tester.pump();
    await tester.pump();

    expect(client.projectNameValue, 'New');
    expect(client.savedTo, <String>['/Music/New.obt']);
    expect(find.byType(RenameProjectDialog), findsNothing);
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

  testWidgets('Current Project is shown only on Playlist', (
    WidgetTester tester,
  ) async {
    final _FakeEngineClient client = _FakeEngineClient();

    await pumpForTest(
      tester,
      ShellBinding(client: client),
      size: const Size(1600, 1000),
    );
    await tester.pump();

    expect(find.text('Current Project'), findsNothing);
    await tester.tap(find.text('PLAYLIST'));
    await tester.pump();
    expect(find.text('Current Project'), findsOneWidget);

    await tester.tap(find.text('CHANNELS'));
    await tester.pump();
    expect(find.text('Current Project'), findsNothing);
  });

  testWidgets('the browser restores and stores which rows are open', (
    WidgetTester tester,
  ) async {
    const MethodChannel channel = MethodChannel('onebeat/sample_packs');
    Map<String, bool> stored = <String, bool>{'current-project': false};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      switch (call.method) {
        case 'loadBrowserExpansion':
          return stored;
        case 'saveBrowserExpansion':
          stored = Map<String, bool>.from(call.arguments as Map<Object?, Object?>);
          return null;
        case 'loadSampleFolders':
          return <String>[];
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await pumpForTest(
      tester,
      ShellBinding(client: _FakeEngineClient()),
      size: const Size(1600, 1000),
    );
    // Two pumps: one for the shell's first frame, one for the restored
    // expansion that the platform read hands back after it.
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('PLAYLIST'));
    await tester.pump();

    // Closed in the last session, so closed now: the section header is there
    // and its patterns are not.
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Main Groove'), findsNothing);

    await tester.tap(find.text('Current Project'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Main Groove'), findsOneWidget);
    expect(stored['current-project'], isTrue);
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

    // Initial state: Channels active (index 0), the composition home
    final ObSideRail railInitial = tester.widget(find.byType(ObSideRail));
    expect(railInitial.vm.activeIndex, 0);

    // Tap Playlist (index 1)
    await tester.tap(find.text('PLAYLIST'));
    await tester.pump();

    final ObSideRail railPlaylist = tester.widget(find.byType(ObSideRail));
    expect(railPlaylist.vm.activeIndex, 1);

    // Tap Mixer (index 2)
    await tester.tap(find.text('MIXER'));
    await tester.pump();

    final ObSideRail railMixer = tester.widget(find.byType(ObSideRail));
    expect(railMixer.vm.activeIndex, 2);

    // Tap Channels (index 0)
    await tester.tap(find.text('CHANNELS'));
    await tester.pump();

    final ObSideRail railChannels = tester.widget(find.byType(ObSideRail));
    expect(railChannels.vm.activeIndex, 0);
  });
}
