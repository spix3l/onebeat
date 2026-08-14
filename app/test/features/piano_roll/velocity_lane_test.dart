// Piano roll velocity lane (UI-B-07): the lane selector the body stacks below
// the canvas.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/piano_roll/velocity_lane.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the velocity lane cycles its value selector', (
    WidgetTester tester,
  ) async {
    final List<String> lanes = <String>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      PrVelocityLane(vm: demoPianoRoll, onLaneChanged: lanes.add),
      size: Size(1200, tokens.size.prVelocityLaneHeight),
    );
    await tester.tap(find.text('VEL'));
    expect(lanes, <String>['PAN']);
  });
}
