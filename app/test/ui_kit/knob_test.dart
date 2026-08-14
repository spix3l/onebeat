// ObKnob: behaviour + a golden of every state (values across the sweep,
// accent tint, labels).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui_kit/knob.dart';

import '../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders every state as the golden', (WidgetTester tester) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      _KnobStates(spacing: tokens.spacing.lg),
      size: const Size(420, 80),
      center: true,
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(_KnobStates), uiGolden('knob'));
  });

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

class _KnobStates extends StatelessWidget {
  const _KnobStates({required this.spacing});

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const ObKnob(value: 0, onChanged: null),
        SizedBox(width: spacing),
        const ObKnob(value: 0.25, onChanged: null),
        SizedBox(width: spacing),
        const ObKnob(value: 0.5, onChanged: null),
        SizedBox(width: spacing),
        const ObKnob(value: 0.75, onChanged: null),
        SizedBox(width: spacing),
        const ObKnob(value: 1, onChanged: null),
        SizedBox(width: spacing),
        const ObKnob(value: 0.6, onChanged: null, accent: true),
        SizedBox(width: spacing),
        const ObKnob(value: 0.4, onChanged: null, label: 'VOL'),
        SizedBox(width: spacing),
        const ObKnob(value: 0.5, onChanged: null, accent: true, label: 'PAN'),
      ],
    );
  }
}
