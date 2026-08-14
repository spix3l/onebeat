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

  testWidgets('the label sits under the control, centred on it', (
    WidgetTester tester,
  ) async {
    // Off to one side of a wide surface: a follower that measures the *window*
    // instead of itself lands near the middle, which is the bug this pins.
    await pumpUi(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 80, top: 12),
          child: ObTooltip(
            message: 'Erase notes',
            shortcut: 'D',
            child: Container(width: 26, height: 26, color: const Color(0xFF222222)),
          ),
        ),
      ),
      size: const Size(1400, 400),
    );

    final TestGesture pointer = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    final Rect target = tester.getRect(find.byType(ObTooltip));
    await pointer.moveTo(target.center);
    await tester.pump(OneBeatTokens.dark().motion.tooltipDelay);

    final Rect card = tester.getRect(find.text('Erase notes'));
    expect(
      card.center.dx,
      closeTo(target.center.dx, 40),
      reason: 'centred on the control, not on the window',
    );
    expect(card.top, greaterThanOrEqualTo(target.bottom));
    expect(card.width, lessThan(300), reason: 'a label, not a banner');
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
