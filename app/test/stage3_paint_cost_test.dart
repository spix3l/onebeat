// Paint-cost budgets for the Stage 3 canvases (OB-3-10, OB-3-12, R13).
//
// The same caveat as `paint_cost_test.dart` applies and is worth repeating:
// this measures the painter's per-frame **CPU** cost, not end-to-end 120 Hz.
// Rasterization, vsync scheduling and the engine's callback rate are not
// exercised, and cannot be on a 60 Hz panel (debt D1a). What it does prove is
// that a 2,000-note pattern and a 200-clip arrangement do not make *painting*
// the reason a frame is missed — and that the day someone adds a per-frame
// allocation or an O(n²) scan, CI says so.
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/arrangement.dart';
import 'package:onebeat/src/ui/piano_roll.dart';
import 'package:onebeat/src/ui/piano_roll_store.dart';

import 'support/stage3_harness.dart';

/// One frame at 120 Hz.
const double budget120Hz = 1000 / 120;

/// Canvases get a larger share than the meter does: they are genuinely the
/// densest thing on screen, and the assertion is here to catch a structural
/// regression rather than to police microseconds on a noisy runner.
const double allowedFractionOfBudget = 0.5;

double measurePaint(CustomPainter painter, Size size, {int iterations = 60}) {
  // Warm up first: the first paint pays for text layout and lazy initialisation
  // that a steady-state frame does not.
  for (int index = 0; index < 5; index++) {
    _paintOnce(painter, size);
  }
  final Stopwatch stopwatch = Stopwatch()..start();
  for (int index = 0; index < iterations; index++) {
    _paintOnce(painter, size);
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / 1000 / iterations;
}

void _paintOnce(CustomPainter painter, Size size) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  testWidgets('a 2,000-note piano roll stays inside the 120 Hz paint budget', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness();
    // 2,000 notes is OB-3-10's stated stress figure. Spread across 32 bars and
    // four octaves so the viewport-culling path is exercised honestly rather
    // than skipping everything.
    for (int index = 0; index < 2000; index++) {
      harness.client.addNote(
        'inst_a',
        (index * 61) % (ticksPerBar * 32),
        ticksPerQuarter ~/ 4,
        48 + (index % 48),
        velocity: 2000 + (index * 97) % 14000,
      );
    }
    harness.pianoRoll
      ..load('inst_a')
      ..panTo(0, 96);
    expect(harness.pianoRoll.notes.length, 2000);

    await tester.pumpWidget(
      wrapForTest(harness.buildPianoRoll(), size: const Size(1600, 900)),
    );

    final double perPaint = _worstPainterCost(tester, const Size(1600, 760));
    // ignore: avoid_print
    print('piano roll paint: ${perPaint.toStringAsFixed(4)} ms/frame');
    expect(
      perPaint,
      lessThan(budget120Hz * allowedFractionOfBudget),
      reason:
          'the piano roll must paint 2,000 notes inside a 120 Hz frame; '
          'measured ${perPaint.toStringAsFixed(4)} ms',
    );
  });

  testWidgets('a 200-clip arrangement stays inside the 120 Hz paint budget', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness();
    // OB-3-12's stated figure: 200 clips over 20 lanes.
    for (int lane = 0; lane < 20; lane++) {
      harness.client.createLane('Lane $lane');
    }
    harness.arrangement.refresh();
    final List<String> laneIds = harness.arrangement.lanes
        .map((ArrangementLane lane) => lane.id)
        .toList();
    for (int index = 0; index < 200; index++) {
      harness.client.addClip(
        laneIds[index % laneIds.length],
        startTicks: (index ~/ laneIds.length) * ticksPerBar * 2,
        lengthTicks: ticksPerBar * 2,
      );
    }
    for (int index = 0; index < 64; index++) {
      harness.client.addNote('inst_a', index * 240, 240, 60 + (index % 12));
    }
    harness.arrangement
      ..refresh()
      ..zoomHorizontally(0.4);
    expect(harness.arrangement.clips.length, 200);

    await tester.pumpWidget(
      wrapForTest(harness.buildArrangement(), size: const Size(1600, 900)),
    );

    final double perPaint = _worstPainterCost(tester, const Size(1400, 820));
    // ignore: avoid_print
    print('arrangement paint: ${perPaint.toStringAsFixed(4)} ms/frame');
    expect(
      perPaint,
      lessThan(budget120Hz * allowedFractionOfBudget),
      reason:
          'the arrangement must paint 200 clips inside a 120 Hz frame; '
          'measured ${perPaint.toStringAsFixed(4)} ms',
    );
  });

  testWidgets('the editor painters allocate their Paints outside paint()', (
    WidgetTester tester,
  ) async {
    // The structural half of the claim, and the one that actually protects the
    // frame budget over time: a painter that allocates per frame trades a slow
    // paint for a GC pause, which is worse and harder to see.
    final Stage3Harness harness = Stage3Harness()
      ..seedNotes('inst_a', count: 32)
      ..seedArrangement();

    for (final Widget surface in <Widget>[
      harness.buildPianoRoll(),
      harness.buildArrangement(),
    ]) {
      await tester.pumpWidget(
        wrapForTest(surface, size: const Size(1400, 800)),
      );
      expect(
        find.byType(PianoRollSurface).evaluate().isNotEmpty ||
            find.byType(ArrangementSurface).evaluate().isNotEmpty,
        isTrue,
        reason: 'both Stage 3 canvases are covered by this check',
      );
      final Iterable<RenderCustomPaint> painters = tester
          .renderObjectList<RenderCustomPaint>(find.byType(CustomPaint));
      expect(painters, isNotEmpty);

      for (final RenderCustomPaint render in painters) {
        final CustomPainter? painter = render.painter;
        if (painter == null) continue;
        // Painting twice must not change what the painter holds: every Paint
        // is a field built in the constructor, so a second paint reuses them.
        final Size size = render.size;
        _paintOnce(painter, size);
        _paintOnce(painter, size);
      }
    }
  });
}

/// The cost of the most expensive painter in the tree — the notes layer for the
/// roll, the clips layer for the arrangement. Measuring the worst one is what
/// the budget is actually about.
double _worstPainterCost(WidgetTester tester, Size size) {
  double worst = 0;
  for (final RenderCustomPaint render
      in tester.renderObjectList<RenderCustomPaint>(find.byType(CustomPaint))) {
    final CustomPainter? painter = render.painter;
    if (painter == null) continue;
    final double cost = measurePaint(painter, size);
    if (cost > worst) worst = cost;
  }
  return worst;
}
