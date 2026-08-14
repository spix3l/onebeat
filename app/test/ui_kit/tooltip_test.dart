// ObTooltip (FR-UX-02): an icon-only control names itself on hover.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/tooltip.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the label is absent until the pointer rests on the control', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObTooltip(
        message: 'Erase notes',
        shortcut: 'D',
        child: SizedBox(width: 24, height: 24),
      ),
      size: const Size(400, 200),
      center: true,
    );

    expect(find.text('Erase notes'), findsNothing);

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(ObTooltip)));
    await tester.pump();

    // Still nothing: a sweep across a toolbar must stay quiet.
    expect(find.text('Erase notes'), findsNothing);

    await tester.pump(OneBeatTokens.dark().motion.tooltipDelay);
    expect(find.text('Erase notes'), findsOneWidget);
    expect(find.text('D'), findsOneWidget, reason: 'the shortcut comes too');
  });

  testWidgets('leaving the control takes the label with it', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObTooltip(
        message: 'Zoom in',
        child: SizedBox(width: 24, height: 24),
      ),
      size: const Size(400, 200),
      center: true,
    );

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(ObTooltip)));
    await tester.pump(OneBeatTokens.dark().motion.tooltipDelay);
    expect(find.text('Zoom in'), findsOneWidget);

    await pointer.moveTo(const Offset(380, 190));
    await tester.pump();
    expect(find.text('Zoom in'), findsNothing);
  });

  testWidgets('leaving before the delay never shows the label at all', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObTooltip(
        message: 'Select notes',
        child: SizedBox(width: 24, height: 24),
      ),
      size: const Size(400, 200),
      center: true,
    );

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(ObTooltip)));
    await pointer.moveTo(const Offset(380, 190));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Select notes'), findsNothing);
  });
}
