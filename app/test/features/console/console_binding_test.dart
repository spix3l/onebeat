import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/console/console_binding.dart';

import '../../support/app_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('ConsoleBinding renders log output and submits commands', (
    WidgetTester tester,
  ) async {
    String? executedScript;

    await pumpForTest(
      tester,
      ConsoleBinding(
        onExecuteScript: (String cmd) => executedScript = cmd,
      ),
    );

    expect(find.text('SCRIPT CONSOLE'), findsOneWidget);
    expect(find.textContaining('Initialized audio device'), findsOneWidget);

    // Enter REPL command
    await tester.enterText(find.byType(ConsoleBinding), 'engine.tempo = 128');
    await tester.tap(find.text('Run'));
    await tester.pump();

    expect(executedScript, 'engine.tempo = 128');
    expect(find.text('> engine.tempo = 128'), findsOneWidget);

    // Clear logs
    await tester.tap(find.text('Clear'));
    await tester.pump();

    expect(find.text('> engine.tempo = 128'), findsNothing);
  });
}
