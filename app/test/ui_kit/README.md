# `ui_kit` golden tests

Component goldens live here (one file per component ticket, plus the harness
smoke golden). Two rules keep every golden in this folder consistent:

1. Every test starts with `setUpAll(loadAppFonts)` — real Archivo and
   Martian Mono, not the test fallback's fixed-width boxes.
2. Every golden goes through `pumpUi` + `uiGolden` — the dark theme, a
   `devicePixelRatio: 1.0` surface, disabled animations, and a golden in the
   colocated `goldens/` folder. Never `pumpWidget` + `matchesGoldenFile`
   directly.

```dart
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders', (WidgetTester tester) async {
    await pumpUi(tester, const MyComponent(), center: true);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MyComponent), uiGolden('my_component'));
  });
}
```

Screen goldens live under `test/features/<feature>/` and follow the same two
rules, with `center: false` (they fill the surface).
