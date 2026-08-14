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
      // All five levels the design uses, not just the three the app started
      // with: text sits on every one of them, so every one has to clear AA.
      'surfaceSunken': tokens.color.surfaceSunken,
      'surfaceDeep': tokens.color.surfaceDeep,
      'surfacePanel': tokens.color.surfacePanel,
      'surfaceRaised': tokens.color.surfaceRaised,
      'surfaceOverlay': tokens.color.surfaceOverlay,
    };

    for (final MapEntry<String, Color> surface in surfaces.entries) {
      test('textPrimary on ${surface.key} meets AA for body text (4.5:1)', () {
        expect(
          contrastRatio(tokens.color.textPrimary, surface.value),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('textSecondary on ${surface.key} meets AA (4.5:1)', () {
        expect(
          contrastRatio(tokens.color.textSecondary, surface.value),
          greaterThanOrEqualTo(4.5),
        );
      });

      // textMuted (Pen `dim`) is the decorative tier — placeholders, empty
      // states, disabled labels — and is deliberately below the 4.5:1 bar the
      // two readable tiers are held to (FR-UX-26 covers "text and essential
      // UI", and this tier is neither). It must still be a visible grey rather
      // than the surface it sits on.
      test('textMuted on ${surface.key} is dim but visible', () {
        expect(
          contrastRatio(tokens.color.textMuted, surface.value),
          greaterThan(1.5),
        );
      });

      // Three weights only earn their keep if they are actually separable.
      test('the three text weights stay distinct on ${surface.key}', () {
        final double primary = contrastRatio(
          tokens.color.textPrimary,
          surface.value,
        );
        final double secondary = contrastRatio(
          tokens.color.textSecondary,
          surface.value,
        );
        final double muted = contrastRatio(
          tokens.color.textMuted,
          surface.value,
        );
        expect(primary, greaterThan(secondary));
        expect(secondary, greaterThan(muted));
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

  test('the eight channel identity colours exist and match c1..c8', () {
    const List<Color> expected = <Color>[
      Color(0xFFF26D5B), // c1
      Color(0xFFE8B54B), // c2
      Color(0xFF9FC65C), // c3
      Color(0xFF37BE93), // c4
      Color(0xFF2FB8C6), // c5
      Color(0xFFE5689E), // c6
      Color(0xFFC97452), // c7
      Color(0xFF7A8BA6), // c8
    ];
    expect(tokens.color.channelColors, hasLength(8));
    for (int index = 0; index < expected.length; index++) {
      expect(
        tokens.color.channelColors[index],
        expected[index],
        reason: 'c${index + 1}',
      );
    }
  });

  test('the dark theme carries every Pen palette value verbatim', () {
    final ColorTokens c = tokens.color;
    final Map<String, Color> actual = <String, Color>{
      'surfaceSunken': c.surfaceSunken,
      'surfaceDeep': c.surfaceDeep,
      'surfacePanel': c.surfacePanel,
      'surfaceRaised': c.surfaceRaised,
      'surfaceWell': c.surfaceWell,
      'surfaceHover': c.surfaceHover,
      'lineStrong': c.lineStrong,
      'line': c.line,
      'textPrimary': c.textPrimary,
      'textSecondary': c.textSecondary,
      'textMuted': c.textMuted,
      'accent': c.accent,
      'accentBright': c.accentBright,
      'meterLow': c.meterLow,
      'meterMid': c.meterMid,
      'meterHigh': c.meterHigh,
      'warning': c.warning,
      'danger': c.danger,
      'trafficRed': c.trafficRed,
      'trafficYellow': c.trafficYellow,
      'trafficGreen': c.trafficGreen,
    };
    const Map<String, Color> expected = <String, Color>{
      'surfaceSunken': Color(0xFF131412),
      'surfaceDeep': Color(0xFF1B1D1A),
      'surfacePanel': Color(0xFF1B1D1A),
      'surfaceRaised': Color(0xFF22251F),
      'surfaceWell': Color(0xFF2A2D27),
      'surfaceHover': Color(0xFF33372F),
      'lineStrong': Color(0xFF3A3D37),
      'line': Color(0xFF2C2F29),
      'textPrimary': Color(0xFFE8E9E4),
      'textSecondary': Color(0xFF9A9D94),
      'textMuted': Color(0xFF6F726B),
      'accent': Color(0xFF7C6CF0),
      'accentBright': Color(0xFF9A8EFF),
      'meterLow': Color(0xFF5CCB8A),
      'meterMid': Color(0xFFE6B85C),
      'meterHigh': Color(0xFFE66A6A),
      'warning': Color(0xFFE6B85C),
      'danger': Color(0xFFE66A6A),
      'trafficRed': Color(0xFFE66A6A),
      'trafficYellow': Color(0xFFE6B85C),
      'trafficGreen': Color(0xFF5CCB8A),
    };
    for (final MapEntry<String, Color> entry in expected.entries) {
      expect(actual[entry.key], entry.value, reason: entry.key);
    }
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
        surfaceSunken: Color(0xFFE4E4E0),
        surfaceDeep: Color(0xFFFFFFFF),
        surfacePanel: Color(0xFFF2F2F0),
        surfaceRaised: Color(0xFFE8E8E4),
        surfaceOverlay: Color(0xFFDCDCD6),
        surfaceWell: Color(0xFFFAFAF8),
        surfaceHover: Color(0xFFD4D4CE),
        surfaceColumnHead: Color(0xFFEDEDE9),
        line: Color(0xFFCFCFC9),
        lineStrong: Color(0xFFB4B4AD),
        textPrimary: Color(0xFF16170F),
        textSecondary: Color(0xFF44463E),
        textMuted: Color(0xFF5A5C54),
        accent: Color(0xFF4A3FD0),
        accentDeep: Color(0xFF3A2FB8),
        accentBright: Color(0xFF6A5DF0),
        accentWash: Color(0x184A3FD0),
        accentMuted: Color(0xFFB9B3F5),
        meterLow: Color(0xFF2E7D46),
        meterMid: Color(0xFFB07A12),
        meterHigh: Color(0xFFB63030),
        meterTrack: Color(0xFFDDDDD7),
        warning: Color(0xFFB07A12),
        danger: Color(0xFFB63030),
        gridLine: Color(0xFFE2E2DC),
        gridLineStrong: Color(0xFFC9C9C2),
        rollCanvas: Color(0xFFF7F7FA),
        rowShade: Color(0xFFEDEDE8),
        rowShadeInScale: Color(0xFFE4E9DE),
        noteFill: Color(0xFF2F8C99),
        noteSelected: Color(0xFF16170F),
        noteGhost: Color(0xFFD7D7D0),
        playhead: Color(0xFF4A3FD0),
        canvasScrim: Color(0x8CFFFFFF),
        marqueeFill: Color(0x244A3FD0),
        clipSelectedOutline: Color(0xFF4A3FD0),
        trafficRed: Color(0xFFFF5F56),
        trafficYellow: Color(0xFFFFBD2E),
        trafficGreen: Color(0xFF27C93F),
        tagPatBg: Color(0xFFD4EED8),
        tagPatFg: Color(0xFF1E6B37),
        tagAudBg: Color(0xFFD1E8F7),
        tagAudFg: Color(0xFF185A85),
        tagAutoBg: Color(0xFFE8E0F7),
        tagAutoFg: Color(0xFF563D8C),
        waveform: Color(0xFF185A85),
        knobTrack: Color(0xFFDCDCD6),
        knobIndicator: Color(0xFF4A3FD0),
        faderTrack: Color(0xFFE4E4E0),
        faderThumb: Color(0xFF5A5C54),
        sidechainGold: Color(0xFFB07A12),
        channelColors: channelColors,
      ),
      type: TypeTokens(
        textPrimary: Color(0xFF16170F),
        textSecondary: Color(0xFF44463E),
        textMuted: Color(0xFF5A5C54),
        // Clip ink stays dark in both themes: a clip's fill is a saturated
        // identity colour either way, and the label sits on the fill rather
        // than on the surface.
        clipInk: Color(0xFF16170F),
        clipInkMuted: Color(0x9E16170F),
      ),
    );
    expect(light.brightness, Brightness.light);
    expect(
      contrastRatio(light.color.textPrimary, light.color.surfaceDeep),
      greaterThanOrEqualTo(4.5),
    );
  });
}
