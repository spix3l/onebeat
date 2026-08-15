import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/export/export_binding.dart';
import 'package:onebeat/src/features/export/export_folder_platform.dart';

import '../../support/app_harness.dart';
import '../../support/fake_engine_client.dart';

class _FakeExportEngineClient extends FakeEngineClient implements EngineClient {}

/// Answers the folder panel with a fixed path, or with a cancellation.
class _ScriptedFolders implements ExportFolderPicker {
  _ScriptedFolders(this.chosen);

  final String? chosen;
  String? openedAt;

  @override
  Future<String?> pickExportFolder({String directory = ''}) async {
    openedAt = directory;
    return chosen;
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpBinding(
    WidgetTester tester,
    _FakeExportEngineClient client, {
    ExportFolderPicker? folders,
    VoidCallback? onClose,
    ValueChanged<String>? onExportDone,
  }) {
    return pumpForTest(
      tester,
      ExportBinding(
        client: client,
        folders: folders ?? _ScriptedFolders(null),
        initialDirectory: '/tmp/onebeat-export-test',
        onClose: onClose ?? () {},
        onExportDone: onExportDone,
      ),
    );
  }

  testWidgets('ExportBinding offers a format, a rate and a folder — and nothing else', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient()..name = 'Night Drive';
    await pumpBinding(tester, client);

    expect(find.text('Export audio · Night Drive'), findsOneWidget);
    expect(find.text('FORMAT'), findsOneWidget);
    expect(find.text('SAMPLE RATE'), findsOneWidget);
    expect(find.text('DESTINATION'), findsOneWidget);
    // The settings that were never rendered are gone rather than disabled.
    expect(find.text('BIT DEPTH'), findsNothing);
    expect(find.text('RANGE'), findsNothing);
    expect(find.text('STEMS · PER TRACK'), findsNothing);

    expect(find.text('/tmp/onebeat-export-test'), findsOneWidget);
    expect(find.text('Night Drive.wav'), findsOneWidget);

    await tester.tap(find.text('AIFF'));
    await tester.pump();
    expect(find.text('Night Drive.aiff'), findsOneWidget);
  });

  testWidgets('Choosing a folder changes where the export will land', (WidgetTester tester) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();
    final _ScriptedFolders folders = _ScriptedFolders('/Users/test/Music/Bounces');
    await pumpBinding(tester, client, folders: folders);

    await tester.tap(find.text('Choose Folder…'));
    await tester.pumpAndSettle();

    expect(folders.openedAt, '/tmp/onebeat-export-test');
    expect(find.text('/Users/test/Music/Bounces'), findsOneWidget);

    await tester.tap(find.text('44.1 kHz'));
    await tester.pump();
    await tester.tap(find.text('Export'));
    await tester.pump();

    expect(client.exportedDirectory, '/Users/test/Music/Bounces');
    expect(client.exportedFormat, ExportFormat.wav);
    expect(client.exportedSampleRate, 44100);
  });

  testWidgets('Settings -> progress -> done follows the engine', (WidgetTester tester) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient()..name = 'Night Drive';
    String? exported;
    await pumpBinding(tester, client, onExportDone: (String path) => exported = path);

    await tester.tap(find.text('Export'));
    await tester.pump();
    expect(find.text('Exporting audio...'), findsOneWidget);

    client.exportStatus = const ExportStatus(
      state: ExportState.running,
      progress: 0.5,
      path: '',
      error: '',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('50% complete'), findsOneWidget);

    client.exportStatus = const ExportStatus(
      state: ExportState.done,
      progress: 1,
      path: '/tmp/onebeat-export-test/Night Drive.wav',
      error: '',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Export complete'), findsOneWidget);
    expect(find.text('/tmp/onebeat-export-test/Night Drive.wav'), findsOneWidget);
    expect(find.text('WAV 24-bit · 48 kHz'), findsOneWidget);
    expect(exported, '/tmp/onebeat-export-test/Night Drive.wav');
  });

  testWidgets('A failed export shows the engine message and can be retried', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();
    await pumpBinding(tester, client);

    await tester.tap(find.text('Export'));
    await tester.pump();

    client.exportStatus = const ExportStatus(
      state: ExportState.failed,
      progress: 0.2,
      path: '',
      error: 'The destination folder does not exist.',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Export failed'), findsOneWidget);
    expect(find.text('The destination folder does not exist.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Exporting audio...'), findsOneWidget);
  });

  testWidgets('Closing the dialog mid-render cancels it rather than orphaning it', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();
    await pumpBinding(tester, client);

    await tester.tap(find.text('Export'));
    await tester.pump();
    expect(find.text('Cancel Render'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(client.exportCancels, 1);
  });

  testWidgets('Cancel mid-progress stops the render and returns to the settings', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();
    await pumpBinding(tester, client);

    await tester.tap(find.text('Export'));
    await tester.pump();
    expect(find.text('Cancel Render'), findsOneWidget);

    await tester.tap(find.text('Cancel Render'));
    await tester.pump();

    expect(client.exportCancels, 1);
    expect(find.text('Export audio · Untitled'), findsOneWidget);
  });
}
