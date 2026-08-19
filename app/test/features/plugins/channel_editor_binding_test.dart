import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/plugins/channel_editor_binding.dart';

import '../../support/app_harness.dart';
import '../../support/fake_engine_client.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shared channel editor switches between plugin and settings tabs', (WidgetTester tester) async {
    final FakeEngineClient client = FakeEngineClient();
    const HostedInstance plugin = HostedInstance(
      id: 1,
      pluginId: 'dev.onebeat.synth',
      name: 'Synth',
      vendor: 'OneBeat',
      path: '/plugins/synth.clap',
      format: PluginFormat.clap,
      missing: false,
      hasEditor: true,
      needsRestart: false,
      paramCount: 0,
    );

    ChannelEditorTab? lastTab;
    await pumpForTest(
      tester,
      ChannelEditorBinding(
        client: client,
        trackId: 'inst_kick',
        channelName: 'Kick 808',
        plugin: plugin,
        initialSettings: const InstrumentSettings(),
        onApplySettings: (_) {},
        onClose: () {},
        onTabChanged: (ChannelEditorTab tab) => lastTab = tab,
      ),
      size: const Size(1200, 900),
    );

    expect(find.text('Kick 808'), findsWidgets);
    expect(find.text('Plugin'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Open native editor'), findsOneWidget);
    expect(find.text('CHANNEL SETTINGS'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(lastTab, ChannelEditorTab.settings);
    expect(find.text('CHANNEL SETTINGS'), findsOneWidget);
    expect(find.text('VOICE'), findsOneWidget);

    await tester.tap(find.text('Plugin'));
    await tester.pump();

    expect(find.text('CHANNEL SETTINGS'), findsNothing);
  });
}
