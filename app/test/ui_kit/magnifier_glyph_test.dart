// ObMagnifierGlyph: it renders inside the search goldens, so this only
// checks it builds and paints without exceptions.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/magnifier_glyph.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders', (WidgetTester tester) async {
    final ColorTokens color = OneBeatTokens.dark().color;
    await pumpUi(
      tester,
      Center(child: ObMagnifierGlyph(color: color.textMuted)),
      size: const Size(80, 80),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ObMagnifierGlyph), findsOneWidget);
  });
}
