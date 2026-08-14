// ObTransportButton: behaviour + a golden of rest / active / toggled states.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

import '../support/ui_glyphs.dart';
import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders every state as the golden', (WidgetTester tester) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _TransportStates(spacing: tokens.spacing.md),
      size: const Size(260, 80),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_TransportStates),
      uiGolden('transport_button'),
    );
  });

  testWidgets('fires onTap when tapped', (WidgetTester tester) async {
    int fired = 0;
    await pumpUi(
      tester,
      Center(
        child: ObTransportButton(
          onTap: () => fired++,
          child: const SizedBox.shrink(),
        ),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObTransportButton));
    expect(fired, 1);
  });

  testWidgets('without onTap it renders but stays inert', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObTransportButton(active: true, child: SizedBox.shrink()),
      ),
      size: const Size(200, 200),
    );
    await tester.tap(find.byType(ObTransportButton));
    expect(find.byType(ObTransportButton), findsOneWidget);
  });
}

class _TransportStates extends StatelessWidget {
  const _TransportStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    final ColorTokens color = OneBeatTheme.of(context).color;
    return Row(
      children: <Widget>[
        ObTransportButton(
          onTap: () {},
          child: TransportGlyph(
            kind: GlyphKind.skipBack,
            color: color.textSecondary,
          ),
        ),
        SizedBox(width: spacing),
        ObTransportButton(
          onTap: () {},
          active: true,
          child: TransportGlyph(kind: GlyphKind.play, color: color.textPrimary),
        ),
        SizedBox(width: spacing),
        ObTransportButton(
          onTap: () {},
          child: TransportGlyph(
            kind: GlyphKind.stop,
            color: color.textSecondary,
          ),
        ),
        SizedBox(width: spacing),
        ObTransportButton(
          onTap: () {},
          toggled: true,
          child: TransportGlyph(kind: GlyphKind.record, color: color.danger),
        ),
        SizedBox(width: spacing),
        ObTransportButton(
          onTap: () {},
          child: TransportGlyph(
            kind: GlyphKind.loop,
            color: color.textSecondary,
          ),
        ),
      ],
    );
  }
}
