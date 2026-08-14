// The tool glyphs (UI-B-07), drawn at 6× so the golden shows the shapes rather
// than three 26px smudges.
//
// They get their own golden because they were redrawn for a specific reported
// failure — "the icon buttons mean nothing, they look broken" — and the toolbar
// golden is too small to catch a regression into that state.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/piano_roll/pr_toolbar.dart';

import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('every tool glyph renders as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      Transform.scale(
        scale: 6,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            PrToolGlyphPreview(tool: PrTool.pencil),
            PrToolGlyphPreview(tool: PrTool.select),
            PrToolGlyphPreview(tool: PrTool.eraser),
          ],
        ),
      ),
      size: const Size(700, 220),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(Transform), uiGolden('pr_tool_glyphs'));
  });

  testWidgets('every tool glyph renders as the golden at its real size', (
    WidgetTester tester,
  ) async {
    // This is the golden that matters and it is deliberately unreadable to a
    // human: the glyphs are 26px on screen, and both regressions so far looked
    // correct when drawn large. The dashed marquee closed up into a plain
    // square here, and the seamed eraser read as stacked layers — neither was
    // visible in the 6x golden above.
    await pumpUi(
      tester,
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PrToolGlyphPreview(tool: PrTool.pencil),
          SizedBox(width: 6),
          PrToolGlyphPreview(tool: PrTool.select),
          SizedBox(width: 6),
          PrToolGlyphPreview(tool: PrTool.eraser),
        ],
      ),
      size: const Size(120, 30),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(Row), uiGolden('pr_tool_glyphs_actual_size'));
  });

  test('every tool names itself and has a key', () {
    for (final PrTool tool in PrTool.values) {
      expect(tool.label, isNotEmpty);
      expect(tool.shortcut, isNotEmpty);
    }
    // The shortcuts have to be distinct or the last one wins silently.
    expect(
      PrTool.values.map((PrTool t) => t.shortcut).toSet().length,
      PrTool.values.length,
    );
  });
}
