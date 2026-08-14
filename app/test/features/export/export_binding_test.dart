import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/export/export_binding.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakeExportEngineClient extends FakeEngineClient implements EngineClient {
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('ExportBinding renders settings and updates selection', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();
    bool closed = false;

    await pumpForTest(
      tester,
      ExportBinding(
        client: client,
        onClose: () => closed = true,
      ),
    );

    expect(find.text('Export audio · Project.onebeat'), findsOneWidget);
    expect(find.text('FORMAT'), findsOneWidget);
    expect(find.text('BIT DEPTH'), findsOneWidget);
    expect(find.text('SAMPLE RATE'), findsOneWidget);
    expect(closed, isFalse);

    // Change format to FLAC
    await tester.tap(find.text('FLAC'));
    await tester.pump();

    expect(find.text('1 (FLAC 24-bit)'), findsOneWidget);

    // Toggle a stem
    await tester.tap(find.text('Drums Bus'));
    await tester.pump();

    expect(find.text('2 (FLAC 24-bit)'), findsOneWidget);
  });

  testWidgets('ExportBinding start -> progress -> done workflow', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();
    String? exportedFile;

    await pumpForTest(
      tester,
      ExportBinding(
        client: client,
        onClose: () {},
        onExportDone: (String path) => exportedFile = path,
      ),
    );

    // Click export button
    await tester.tap(find.text('Export'));
    await tester.pump();

    expect(find.text('Exporting audio...'), findsOneWidget);
    expect(find.text('Rendering audio mix...'), findsOneWidget);

    // Advance timers
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Export complete'), findsOneWidget);
    expect(find.text('Audio Exported Successfully'), findsOneWidget);
    expect(exportedFile, isNotNull);
  });

  testWidgets('ExportBinding cancel mid-progress restores settings', (
    WidgetTester tester,
  ) async {
    final _FakeExportEngineClient client = _FakeExportEngineClient();

    await pumpForTest(
      tester,
      ExportBinding(
        client: client,
        onClose: () {},
      ),
    );

    await tester.tap(find.text('Export'));
    await tester.pump();

    expect(find.text('Cancel Render'), findsOneWidget);

    await tester.tap(find.text('Cancel Render'));
    await tester.pump();

    expect(find.text('Export audio · Project.onebeat'), findsOneWidget);
  });
}
