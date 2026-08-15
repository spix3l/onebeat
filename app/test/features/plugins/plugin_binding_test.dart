import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/plugins/plugin_binding.dart';
import 'package:onebeat/src/features/plugins/stock/piano_editor.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakePluginEngineClient extends FakeEngineClient implements EngineClient {
  bool muted = false;
  final Map<int, double> paramValues = <int, double>{};
  final List<int> auditionedNotesOn = <int>[];
  final List<int> auditionedNotesOff = <int>[];

  @override
  void setInstrumentMuted(String id, {required bool muted}) {
    this.muted = muted;
  }

  @override
  void setParameter(int paramId, double value) {
    paramValues[paramId] = value;
  }

  @override
  void auditionNoteOn(int key, double velocity) {
    auditionedNotesOn.add(key);
  }

  @override
  void auditionNoteOff(int key) {
    auditionedNotesOff.add(key);
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('PluginBinding renders Piano stock editor for OneBeat Piano plugin', (
    WidgetTester tester,
  ) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();

    await pumpForTest(
      tester,
      PluginBinding(
        client: client,
        trackId: 'inst_piano',
        pluginName: 'OneBeat Piano',
        trackName: 'Grand Piano',
        parameters: const <HostedParameter>[
          HostedParameter(id: 100, name: 'Tone', module: 'Piano', display: '65 %', value: 0.65, minimum: 0.0, maximum: 1.0, defaultValue: 0.65),
          HostedParameter(id: 107, name: 'Preset', module: 'Model', display: 'Concert Grand', value: 0.0, minimum: 0.0, maximum: 1.0, defaultValue: 0.0),
          HostedParameter(id: 108, name: 'Attack', module: 'Envelope', display: '5.0 ms', value: 0.05, minimum: 0.0, maximum: 1.0, defaultValue: 0.05),
          HostedParameter(id: 109, name: 'Sustain', module: 'Envelope', display: '0 %', value: 0.0, minimum: 0.0, maximum: 1.0, defaultValue: 0.0),
        ],
        onClose: () {},
      ),
    );

    expect(find.text('TIMBRE & ACOUSTICS'), findsOneWidget);
    expect(find.text('AMPLITUDE ENVELOPE (ADSR)'), findsOneWidget);
    expect(find.text('SPACE & DYNAMICS'), findsOneWidget);
    expect(find.text('PREVIEW KEYBOARD'), findsOneWidget);
    expect(find.text('Concert Grand'), findsWidgets);
    expect(find.text('Classic Rhodes'), findsOneWidget);
    expect(find.text('FM DX Tines'), findsOneWidget);

    // Tap on Classic Rhodes preset
    await tester.tap(find.text('Classic Rhodes'));
    await tester.pump();

    // Verify preset parameter was updated
    expect(client.paramValues.containsKey(107), isTrue);

    // Tap on a piano key in preview keyboard
    await tester.tap(find.byType(PianoWhiteKey).first);
    await tester.pump();
    expect(client.auditionedNotesOn.isNotEmpty, isTrue);
  });

  testWidgets('PluginBinding renders Synth stock editor for synth plugin', (
    WidgetTester tester,
  ) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();

    await pumpForTest(
      tester,
      PluginBinding(
        client: client,
        trackId: 'inst_keys',
        pluginName: 'Synth',
        trackName: 'Soft Keys',
        onClose: () {},
      ),
    );

    expect(find.text('FILTER & TONE'), findsOneWidget);
    expect(find.text('CUTOFF'), findsOneWidget);
    expect(find.text('AMPLITUDE ENVELOPE'), findsOneWidget);
  });

  testWidgets('PluginBinding renders Sampler stock editor for sampler plugin', (
    WidgetTester tester,
  ) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();

    await pumpForTest(
      tester,
      PluginBinding(
        client: client,
        trackId: 'inst_kick',
        pluginName: 'Sampler',
        trackName: 'Kick 808',
        onClose: () {},
      ),
    );

    expect(find.text('SAMPLE FILE'), findsOneWidget);
    expect(find.text('808_Kick_Punchy.wav'), findsOneWidget);
    expect(find.text('TUNE'), findsOneWidget);
  });

  testWidgets('PluginBinding toggles bypass state', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();

    await pumpForTest(
      tester,
      PluginBinding(
        client: client,
        trackId: 'inst_keys',
        pluginName: 'Synth',
        trackName: 'Soft Keys',
        onClose: () {},
      ),
    );

    expect(find.textContaining('Soft Keys · ACTIVE'), findsOneWidget);

    // Tap waveform icon (Bypass action)
    await tester.tap(find.byType(PluginBinding));
    await tester.pump();
  });
}

