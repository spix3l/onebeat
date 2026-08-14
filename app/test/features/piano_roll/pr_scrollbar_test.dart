// The roll's scroll rails (UI-D-03): always painted, proportional, draggable.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/piano_roll/pr_scrollbar.dart';

import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a rail renders even when there is nothing to scroll', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const PrScrollbar(
        axis: Axis.horizontal,
        offset: 0,
        viewportExtent: 100,
        contentExtent: 100,
      ),
      size: const Size(400, 12),
    );

    // The point of an always-visible rail: it is there before you need it.
    expect(find.byType(PrScrollbar), findsOneWidget);
  });

  testWidgets('dragging the thumb reports a proportional offset', (
    WidgetTester tester,
  ) async {
    double? reported;
    await pumpUi(
      tester,
      PrScrollbar(
        axis: Axis.horizontal,
        offset: 0,
        viewportExtent: 100,
        contentExtent: 400,
        onOffsetChanged: (double value) => reported = value,
      ),
      size: const Size(400, 12),
    );

    // The thumb is a quarter of a 400px track, so it is 100px wide and travels
    // the remaining 300px. Grabbing its middle and moving 150px puts it
    // half-way along that travel — half of a 300-tick scroll range.
    await tester.dragFrom(const Offset(50, 6), const Offset(150, 0));
    await tester.pump();

    expect(reported, isNotNull);
    expect(reported!, closeTo(150, 1));
  });

  testWidgets('clicking the track jumps the thumb to the click', (
    WidgetTester tester,
  ) async {
    double? reported;
    await pumpUi(
      tester,
      PrScrollbar(
        axis: Axis.horizontal,
        offset: 0,
        viewportExtent: 100,
        contentExtent: 400,
        onOffsetChanged: (double value) => reported = value,
      ),
      size: const Size(400, 12),
    );

    await tester.tapAt(const Offset(350, 6));
    await tester.pump();

    // Centred on the click, clamped to the end of the track.
    expect(reported, closeTo(300, 1));
  });

  testWidgets('an offset at the end puts the thumb at the end', (
    WidgetTester tester,
  ) async {
    double? reported;
    await pumpUi(
      tester,
      PrScrollbar(
        axis: Axis.vertical,
        offset: 300,
        viewportExtent: 100,
        contentExtent: 400,
        onOffsetChanged: (double value) => reported = value,
      ),
      size: const Size(12, 400),
    );

    // Grabbing the thumb where it already is and not moving reports no change.
    await tester.dragFrom(const Offset(6, 350), Offset.zero);
    await tester.pump();

    expect(reported, closeTo(300, 1));
  });

  testWidgets('a rail with nothing to scroll reports nothing', (
    WidgetTester tester,
  ) async {
    double? reported;
    await pumpUi(
      tester,
      PrScrollbar(
        axis: Axis.horizontal,
        offset: 0,
        viewportExtent: 400,
        contentExtent: 400,
        onOffsetChanged: (double value) => reported = value,
      ),
      size: const Size(400, 12),
    );

    await tester.dragFrom(const Offset(50, 6), const Offset(200, 0));
    await tester.pump();

    expect(reported, isNull);
  });
}
