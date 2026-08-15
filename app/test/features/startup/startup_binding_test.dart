import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/startup/startup_binding.dart';

import '../../support/fake_engine_client.dart';
import '../../support/app_harness.dart';

class _FakeStartupEngineClient extends FakeEngineClient implements EngineClient {}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('StartupBinding renders welcome state and handles actions', (
    WidgetTester tester,
  ) async {
    final _FakeStartupEngineClient client = _FakeStartupEngineClient();
    bool newProjectClicked = false;
    bool openProjectClicked = false;
    bool demoClicked = false;

    await pumpForTest(
      tester,
      StartupBinding(
        client: client,
        onNewProject: () => newProjectClicked = true,
        onOpenProject: () => openProjectClicked = true,
        onLoadDemo: () => demoClicked = true,
      ),
    );

    expect(find.text('Welcome to OneBeat'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
    expect(find.text('Open Project...'), findsOneWidget);
    expect(find.text('Load Demo'), findsOneWidget);

    await tester.tap(find.text('New Project'));
    await tester.pump();
    expect(newProjectClicked, isTrue);

    await tester.tap(find.text('Open Project...'));
    await tester.pump();
    expect(openProjectClicked, isTrue);

    await tester.tap(find.text('Load Demo'));
    await tester.pump();
    expect(demoClicked, isTrue);
  });
}
