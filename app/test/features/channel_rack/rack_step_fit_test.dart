// The rack's step grid resizes itself to the window (UI-B-05): a 32-step
// pattern has to be visible in one piece, and a scroll that hides half the bar
// is not a rhythm you can write.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';

void main() {
  const SizeTokens base = SizeTokens();

  test('a grid that already fits keeps the design size', () {
    final double full = rackGridWidth(base, 32);
    final SizeTokens fitted = fitRackSteps(base, 32, full + 100);

    expect(fitted.rackStepCell, base.rackStepCell);
    expect(fitted.rackStepGap, base.rackStepGap);
    expect(fitted.rackStepGroupGap, base.rackStepGroupGap);
  });

  test('32 steps fit a grid budget a typical window leaves them', () {
    // ~1150pt of workspace less the lane's fixed chrome.
    const double available = 780;
    expect(
      rackGridWidth(base, 32),
      greaterThan(available),
      reason: 'the design size is what made this scroll',
    );

    final SizeTokens fitted = fitRackSteps(base, 32, available);

    expect(rackGridWidth(fitted, 32), lessThanOrEqualTo(available));
    expect(fitted.rackStepCell, lessThan(base.rackStepCell));
    expect(
      fitted.rackStepGroupGap,
      greaterThan(fitted.rackStepGap),
      reason: 'the beat grouping has to survive the shrink',
    );
  });

  test('the cell takes every pixel it can rather than shrinking to a floor', () {
    const double available = 780;
    final SizeTokens fitted = fitRackSteps(base, 32, available);
    final SizeTokens oneBigger = _cellOf(fitted.rackStepCell + 1);

    expect(
      rackGridWidth(oneBigger, 32),
      greaterThan(available),
      reason: 'one pixel more per cell would not have fitted',
    );
  });

  test('below the smallest usable cell it stops shrinking and scrolls', () {
    final SizeTokens fitted = fitRackSteps(base, 32, 100);

    expect(fitted.rackStepCell, 16);
    expect(
      rackGridWidth(fitted, 32),
      greaterThan(100),
      reason: 'the scroll is the answer past this point, not a 3px cell',
    );
  });

  test('the sizes are whole pixels, so cells stay crisp', () {
    for (double available = 400; available <= 1100; available += 17) {
      final SizeTokens fitted = fitRackSteps(base, 32, available);
      expect(fitted.rackStepCell % 1, 0);
      expect(fitted.rackStepGap % 1, 0);
      expect(fitted.rackStepGroupGap % 1, 0);
    }
  });

  group('a lane bound to the rack width', () {
    test('fits more steps than the pattern has into the same span', () {
      final double shared = rackGridWidth(base, 16);
      final SizeTokens fitted = fitRackStepsToWidth(base, 128, shared);
      expect(rackGridWidth(fitted, 128), lessThanOrEqualTo(shared));
    });

    test('drops the gaps rather than overflow when even the smallest cell will not fit', () {
      final double shared = rackGridWidth(base, 16);
      final SizeTokens fitted = fitRackStepsToWidth(base, 512, shared);
      expect(rackGridWidth(fitted, 512), lessThanOrEqualTo(shared));
      expect(fitted.rackStepGap, 0);
    });

    test('keeps the design size when the lane matches the pattern', () {
      final double shared = rackGridWidth(base, 16);
      expect(fitRackStepsToWidth(base, 16, shared).rackStepCell, base.rackStepCell);
    });
  });

}

/// The fitted tokens for an exact cell size, reached through the public entry
/// point by asking for exactly the width that cell needs.
SizeTokens _cellOf(double cell) {
  const SizeTokens base = SizeTokens();
  if (cell >= base.rackStepCell) return base;
  for (double available = 200; available <= 1200; available += 1) {
    final SizeTokens fitted = fitRackSteps(base, 32, available);
    if (fitted.rackStepCell == cell) return fitted;
  }
  fail('no width produces a $cell px cell');

}
