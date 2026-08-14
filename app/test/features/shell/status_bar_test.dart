// Status bar (UI-B-03): one golden with both fixture states in it, plus the
// formatting tests the golden cannot make.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/status_bar.dart';

import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders both fixture states as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Column(
        key: Key('statusBars'),
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // The channel-rack mockup's footer.
          ObStatusBar(
            vm: ObStatusBarVm(
              tone: StatusTone.ok,
              primary: 'Playing',
              details: <String>['Main Groove', '8 channels', '16 steps'],
              rightHint: 'Double-click a channel to open its piano roll',
            ),
          ),
          // The routing mockup's footer: idle, with the routing shortcuts.
          ObStatusBar(
            vm: ObStatusBarVm(
              tone: StatusTone.warning,
              primary: 'Inspecting Drums Bus',
              details: <String>['4 inputs', '2 sends'],
              rightHint: '⌘R routing · ⇧⌘R overview',
            ),
          ),
        ],
      ),
      size: const Size(1600, 60),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('statusBars')),
      uiGolden('status_bar'),
    );
  });

  testWidgets('status details render dot-separated after the primary', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObStatusBar(
        vm: ObStatusBarVm(
          tone: StatusTone.danger,
          primary: 'Audio device disconnected',
          details: <String>['no output'],
        ),
      ),
      size: const Size(1600, 26),
    );
    expect(find.text('Audio device disconnected'), findsOneWidget);
    expect(find.text('· no output'), findsOneWidget);
  });
}
