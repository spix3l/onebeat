import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/plugins/plugin_binding.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakePluginEngineClient extends FakeEngineClient implements EngineClient {
  bool muted = false;
  final Map<int, double> paramValues = <int, double>{};

  @override
  void setInstrumentMuted(String id, {required bool muted}) {
    this.muted = muted;
  }

  @override
  void setParameter(int paramId, double value) {
    paramValues[paramId] = value;
  }
}

void main() {
  setUpAll(loadAppFonts);

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
