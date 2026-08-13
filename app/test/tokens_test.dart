// The contrast requirement is a test, not a paragraph (FR-UX-26, OB-1-03 AC).
// If someone darkens a surface or lightens muted text past the AA threshold,
// this fails in CI rather than in a user's eyes.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';

/// WCAG relative luminance.
double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return (0.2126 * channel(color.r)) +
      (0.7152 * channel(color.g)) +
      (0.0722 * channel(color.b));
}

double contrastRatio(Color foreground, Color background) {
  final double a = _luminance(foreground);
  final double b = _luminance(background);
  final double lighter = math.max(a, b);
  final double darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final OneBeatTokens tokens = OneBeatTokens.dark();

  group('WCAG AA contrast on every surface', () {
    final Map<String, Color> surfaces = <String, Color>{
      'surfaceDeep': tokens.color.surfaceDeep,
      'surfacePanel': tokens.color.surfacePanel,
      'surfaceRaised': tokens.color.surfaceRaised,
    };

    for (final MapEntry<String, Color> surface in surfaces.entries) {
      test('textPrimary on ${surface.key} meets AA for body text (4.5:1)', () {
        expect(
          contrastRatio(tokens.color.textPrimary, surface.value),
          greaterThanOrEqualTo(4.5),
        );
      });

      // Muted text is used for labels and secondary values at >=11px; AA for
      // that size is still 4.5:1, so it is held to the same bar.
      test('textMuted on ${surface.key} meets AA (4.5:1)', () {
        expect(
          contrastRatio(tokens.color.textMuted, surface.value),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  test('meter colours stay conventional green/amber/red', () {
    // Green must be the greenest channel, red the reddest: the meter is the one
    // place in the app where colour carries meaning by convention (PRD §15.3).
    expect(tokens.color.meterLow.g, greaterThan(tokens.color.meterLow.r));
    expect(tokens.color.meterHigh.r, greaterThan(tokens.color.meterHigh.g));
    expect(tokens.color.meterMid.r, greaterThan(tokens.color.meterMid.b));
    expect(tokens.color.meterMid.g, greaterThan(tokens.color.meterMid.b));
  });

  test('the type scale uses the two chosen families and tabular numerics', () {
    expect(tokens.type.body.fontFamily, 'Archivo');
    expect(tokens.type.numeric.fontFamily, 'MartianMono');
    expect(
      tokens.type.numeric.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  test('a second theme can be resolved without touching widget code', () {
    // FR-UX-04 structural check: tokens are a value, not a set of globals, so a
    // light theme is another instance and nothing else.
    const OneBeatTokens light = OneBeatTokens(
      brightness: Brightness.light,
      color: ColorTokens(
        surfaceDeep: Color(0xFFFFFFFF),
        surfacePanel: Color(0xFFF2F2F0),
        surfaceRaised: Color(0xFFE8E8E4),
        line: Color(0xFFCFCFC9),
        textPrimary: Color(0xFF16170F),
        textMuted: Color(0xFF5A5C54),
        accent: Color(0xFF4A3FD0),
        accentMuted: Color(0xFFB9B3F5),
        meterLow: Color(0xFF2E7D46),
        meterMid: Color(0xFFB07A12),
        meterHigh: Color(0xFFB63030),
        meterTrack: Color(0xFFDDDDD7),
        warning: Color(0xFFB07A12),
        danger: Color(0xFFB63030),
      ),
      type: TypeTokens(
        textPrimary: Color(0xFF16170F),
        textMuted: Color(0xFF5A5C54),
      ),
    );
    expect(light.brightness, Brightness.light);
    expect(
      contrastRatio(light.color.textPrimary, light.color.surfaceDeep),
      greaterThanOrEqualTo(4.5),
    );
  });
}
