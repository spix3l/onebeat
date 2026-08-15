import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/preferences/preferences_binding.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakePrefEngineClient extends FakeEngineClient implements EngineClient {
  int bufferSize = 128;

  void setBufferSize(int size) {
    bufferSize = size;
  }

  @override
  EngineSnapshot readSnapshot() => EngineSnapshot(
    playing: false,
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
    blockFrames: bufferSize,
    activeVoices: 0,
    peakLeft: 0,
    peakRight: 0,
    rmsLeft: 0,
    rmsRight: 0,
    cpuLoad: 0,
    xrunCount: 0,
    latencyFramesRoundTrip: 256,
    scheduleEventCount: 0,
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('PreferencesBinding renders tabs and switches buffer sizes', (
    WidgetTester tester,
  ) async {
    final _FakePrefEngineClient client = _FakePrefEngineClient();

    await pumpForTest(
      tester,
      PreferencesBinding(
        client: client,
        onClose: () {},
      ),
    );

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('AUDIO OUTPUT DEVICE'), findsOneWidget);
    expect(find.text('BUFFER SIZE (LATENCY)'), findsOneWidget);

    // Switch buffer to 256
    await tester.tap(find.text('256'));
    await tester.pump();

    expect(find.textContaining('256 samples'), findsOneWidget);
  });

  testWidgets('PreferencesBinding switches tabs and manages folders', (
    WidgetTester tester,
  ) async {
    final _FakePrefEngineClient client = _FakePrefEngineClient();

    await pumpForTest(
      tester,
      PreferencesBinding(
        client: client,
        onClose: () {},
      ),
    );

    // Switch to Sound & Plugins tab
    await tester.tap(find.text('Sound & Plugins'));
    await tester.pump();

    expect(find.text('SAMPLE & PRESET FOLDERS'), findsOneWidget);
    expect(find.text('+ Add Folder...'), findsOneWidget);

    // Add folder
    await tester.tap(find.text('+ Add Folder...'));
    await tester.pump();

    expect(find.text('~/Music/OneBeat/Custom Library 4'), findsOneWidget);

    // Switch to Keys & Shortcuts tab
    await tester.tap(find.text('Keys & Shortcuts'));
    await tester.pump();

    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);
    expect(find.text('Play / Stop'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
  });
}
