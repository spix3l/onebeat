// Piano roll key column (UI-B-07): audition taps and the keyboard geography.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/piano_roll/key_column.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the key column reports the note under a tap', (
    WidgetTester tester,
  ) async {
    final List<int> pressed = <int>[];
    await pumpUi(
      tester,
      PrKeyColumn(viewport: demoViewport, onKeyPress: pressed.add),
      size: const Size(60, 700),
    );
    await tester.tapAt(
      Offset(20, demoViewport.yOf(72) + demoViewport.rowHeight / 2),
    );
    expect(pressed, <int>[72]);
  });

  test('the key column knows its blacks and labels its Cs', () {
    expect(PrKeyColumn.isBlack(73), isTrue);
    expect(PrKeyColumn.isBlack(72), isFalse);
    expect(PrKeyColumn.octaveLabel(72), 'C5');
    expect(PrKeyColumn.octaveLabel(60), 'C4');
  });
}
