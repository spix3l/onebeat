// The harness smoke golden (UI-A-02 §4).
//
// A trivial render — one themed `Text` — that proves the harness end to end:
// fonts load, the dark theme wraps, and the golden path resolves. A change to
// `loadAppFonts`, `pumpUi`, `uiGolden` or the title type style shows up here as
// a reviewable diff rather than as a silent drift in a dozen component tests.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a themed Text renders as the harness smoke golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      Builder(
        builder: (BuildContext context) {
          final OneBeatTokens tokens = OneBeatTheme.of(context);
          return Text('Harness smoke', style: tokens.type.title);
        },
      ),
      size: const Size(360, 80),
      center: true,
    );
    await tester.pumpAndSettle();

    await expectLater(find.byType(Text), uiGolden('harness_smoke'));
  });
}
