// Readouts (UI-B-02): the numeric value/unit pairs the chrome renders.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/readouts.dart';

import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('every readout value and unit comes from the caller', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const Center(
        child: ObReadout(value: '124.00', unit: 'BPM'),
      ),
      size: const Size(200, 100),
    );
    expect(find.text('124.00'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
  });
}
