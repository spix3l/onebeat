# `ui_kit` golden tests

Component goldens live here — one test file per component, mirroring
`lib/src/ui_kit/` one-to-one (plus the harness smoke golden). Each component's
golden shows it in every state on a `surfaceSunken` background, and every
variant a test exercises lands in the **same** png: a golden test file owns
exactly one `<name>.png`, with its variants — states, content, themes —
composed side by side (or stacked) inside it. Two rules keep every golden in
this folder consistent:

1. Every test starts with `setUpAll(loadAppFonts)` — real Archivo and
   Martian Mono, not the test fallback's fixed-width boxes.
2. Every golden goes through `pumpUi` + `uiGolden` — the dark theme, a
   `devicePixelRatio: 1.0` surface, disabled animations, and a golden in the
   colocated `goldens/` folder. Never `pumpWidget` + `matchesGoldenFile`
   directly.
3. Regenerate with the **Flutter version CI pins** (the `FLUTTER_VERSION` in
   `.github/workflows/ci.yml`). Text layout changes between Flutter patches, so
   a golden written on any other version is pixel-different on the runner:
   `flutter test --update-goldens` on the pinned version, then commit only the
   pngs whose widget actually changed.

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
