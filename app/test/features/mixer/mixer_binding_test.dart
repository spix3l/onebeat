import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/mixer/mixer_binding.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakeMixerEngineClient extends FakeEngineClient implements EngineClient {
  _FakeMixerEngineClient({
    this.isPlaying = false,
  }) {
    instruments = <ProjectInstrument>[
      const ProjectInstrument(
        id: 'inst_kick',
        name: 'Kick 808',
        color: '#4FAFF5',
        order: 0,
        pluginId: 'sampler',
        pluginName: 'Sampler',
        pluginVendor: 'OneBeat',
        pluginPath: '/plugins/sampler',
        muted: false,
        selected: false,
        affectedPatterns: 1,
        affectedClips: 1,
        affectedNotes: 4,
      ),
      const ProjectInstrument(
        id: 'inst_snare',
        name: 'Snare',
        color: '#EF6F91',
        order: 1,
        pluginId: 'sampler',
        pluginName: 'Sampler',
        pluginVendor: 'OneBeat',
        pluginPath: '/plugins/sampler',
        muted: false,
        selected: false,
        affectedPatterns: 1,
        affectedClips: 1,
        affectedNotes: 2,
      ),
    ];
  }

  bool isPlaying;
  late List<ProjectInstrument> instruments;
  final List<String> mutedCalls = <String>[];
  double masterGain = 1.0;

  @override
  List<ProjectInstrument> readInstruments() => instruments;

  @override
  void setInstrumentMuted(String id, {required bool muted}) {
    mutedCalls.add('$id:$muted');
  }

  @override
  void setMasterGain(double gain) {
    masterGain = gain;
  }

  @override
  EngineSnapshot readSnapshot() => EngineSnapshot(
        playing: isPlaying,
        loopEnabled: true,
        loopStartBeats: 0,
        loopEndBeats: 4,
        positionFrames: 0,
        positionBeats: 0,
        positionSeconds: 0,
        hostTimeNanos: 0,
        tempoBpm: 120,
        bar: 1,
        beat: 1,
        tick: 0,
        sampleRate: 48000,
        blockFrames: 128,
        activeVoices: 0,
        peakLeft: 0.8,
        peakRight: 0.7,
        rmsLeft: 0.5,
        rmsRight: 0.5,
        cpuLoad: 0,
        xrunCount: 0,
        latencyFramesRoundTrip: 256,
        scheduleEventCount: 0,
      );

  @override
  List<EngineEvent> pollEvents() => const <EngineEvent>[];
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('MixerBinding renders track strips, master strip and routing panel', (
    WidgetTester tester,
  ) async {
    final _FakeMixerEngineClient client = _FakeMixerEngineClient(isPlaying: true);

    await pumpForTest(
      tester,
      MixerBinding(client: client),
    );

    expect(find.text('Kick 808'), findsWidgets);
    expect(find.text('Snare'), findsWidgets);
    expect(find.text('MASTER'), findsOneWidget);
    expect(find.text('ROUTING — KICK 808'), findsOneWidget);
  });

  testWidgets('MixerBinding selects track and updates routing panel', (
    WidgetTester tester,
  ) async {
    final _FakeMixerEngineClient client = _FakeMixerEngineClient();

    await pumpForTest(
      tester,
      MixerBinding(client: client),
    );

    expect(find.text('ROUTING — KICK 808'), findsOneWidget);

    // Tap Snare strip
    await tester.tap(find.text('Snare').first);
    await tester.pump();

    expect(find.text('ROUTING — SNARE'), findsOneWidget);
  });

  testWidgets('MixerBinding toggles mute and switches mode tabs', (
    WidgetTester tester,
  ) async {
    final _FakeMixerEngineClient client = _FakeMixerEngineClient();

    await pumpForTest(
      tester,
      MixerBinding(client: client),
    );

    // Tap Mute on Kick
    await tester.tap(find.text('M').first);
    await tester.pump();

    expect(client.mutedCalls, contains('inst_kick:true'));

    // Switch to Graph tab
    await tester.tap(find.text('Graph'));
    await tester.pump();
  });
}
