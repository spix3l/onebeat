// ObSearchField: behaviour + a golden of the plain field and the ⌘K
// shortcut-tag variant, hints verbatim from the mockups.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/search_field.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders both variants as the golden', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _SearchFieldStates(spacing: tokens.spacing.md),
      size: const Size(480, 80),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_SearchFieldStates),
      uiGolden('search_field'),
    );
  });

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObSearchField(
          hint: 'Search samples, presets…',
          onTap: () => fired++,
        ),
      ),
      size: const Size(400, 200),
    );
    await tester.tap(find.byType(ObSearchField));
    expect(fired, 1);
  });

  testWidgets('accepts focus and text input', (WidgetTester tester) async {
    String? query;
    await pumpUi(
      tester,
      Center(
        child: ObSearchField(
          hint: 'Search samples, presets…',
          onChanged: (String value) => query = value,
        ),
      ),
      size: const Size(400, 200),
    );

    await tester.tap(find.byType(ObSearchField));
    await tester.enterText(find.byType(EditableText), 'kick');

    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(query, 'kick');
  });

  testWidgets('renders the shortcut tag only when given one', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObSearchField(hint: 'Search actions', shortcut: '⌘K'),
      ),
      size: const Size(400, 200),
    );
    expect(find.text('⌘K'), findsOneWidget);
  });
}

class _SearchFieldStates extends StatelessWidget {
  const _SearchFieldStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const ObSearchField(hint: 'Search samples, presets…', onTap: null),
        SizedBox(width: spacing),
        const ObSearchField(
          hint: 'Search actions',
          shortcut: '⌘K',
          onTap: null,
        ),
      ],
    );
  }
}
