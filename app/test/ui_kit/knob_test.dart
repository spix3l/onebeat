// ObKnob behaviour (visual states are on the core-controls board golden).
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui_kit/knob.dart';

import '../support/ui_harness.dart';
import 'package:flutter/widgets.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('reports vertical drags as value changes', (
    WidgetTester tester,
  ) async {
    double? reported;
    await pumpUi(
      tester,
      Center(child: ObKnob(value: 0.5, onChanged: (double v) => reported = v)),
      size: const Size(200, 200),
    );
    final Offset center = tester.getCenter(find.byType(ObKnob));
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -40));
    await gesture.up();
    await tester.pump();
    expect(reported, greaterThan(0.5));
  });

  testWidgets('clamps drags to the 0..1 range', (WidgetTester tester) async {
    double? reported;
    await pumpUi(
      tester,
      Center(child: ObKnob(value: 0.9, onChanged: (double v) => reported = v)),
      size: const Size(200, 200),
    );
    final Offset center = tester.getCenter(find.byType(ObKnob));
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -500));
    await gesture.up();
    await tester.pump();
    expect(reported, 1.0);
  });
}
