// The OneBeat design token system (OB-1-03, FR-UX-01/02, PRD §8.1.1).
//
// Every colour, size, spacing, radius, duration and type style in the app comes
// from here. Widget code may not contain a literal colour or dimension —
// tools/token_lint.py fails the build on `Color(0x…)`, hex literals and raw
// numeric EdgeInsets/SizedBox/fontSize under lib/src/ui/.
//
// Structure note (FR-UX-04): tokens are *semantic roles* resolved through a
// theme object, not global constants. Only the dark theme ships in v0.1, but a
// light theme is a second `OneBeatTokens` instance and touches no widget code.
import 'package:flutter/widgets.dart';

/// Semantic colour roles. Names describe the job, never the value: `surfacePanel`
/// rather than `grey900`, so a light theme can invert without renaming anything.
@immutable
class ColorTokens {
  const ColorTokens({
    required this.surfaceDeep,
    required this.surfacePanel,
    required this.surfaceRaised,
    required this.line,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.accentMuted,
    required this.meterLow,
    required this.meterMid,
    required this.meterHigh,
    required this.meterTrack,
    required this.warning,
    required this.danger,
  });

  /// Deepest background: the window itself.
  final Color surfaceDeep;

  /// Panels sitting on the deep surface.
  final Color surfacePanel;

  /// Controls and cards raised above a panel.
  final Color surfaceRaised;

  /// Hairlines and separators.
  final Color line;

  final Color textPrimary;
  final Color textMuted;

  /// The single accent. Chrome stays chromatically quiet so that user clip
  /// colours are the only saturated thing on screen (PRD §15.3).
  final Color accent;
  final Color accentMuted;

  /// Meter colours are conventional and semantic: green below −12 dB, amber
  /// approaching 0, red at clipping. Never restyled for taste (PRD §15.3).
  final Color meterLow;
  final Color meterMid;
  final Color meterHigh;
  final Color meterTrack;

  final Color warning;
  final Color danger;
}

/// Spacing scale. Every gap in the app is one of these.
@immutable
class SpacingTokens {
  const SpacingTokens();

  double get xxs => 2;
  double get xs => 4;
  double get sm => 8;
  double get md => 12;
  double get lg => 16;
  double get xl => 24;
  double get xxl => 32;
}

@immutable
class RadiusTokens {
  const RadiusTokens();

  Radius get sm => const Radius.circular(3);
  Radius get md => const Radius.circular(5);
  Radius get lg => const Radius.circular(8);
  BorderRadius get controlBorder => BorderRadius.all(md);
  BorderRadius get panelBorder => BorderRadius.all(lg);
}

@immutable
class BorderTokens {
  const BorderTokens();

  double get hairline => 1;
  double get emphasis => 2;
}

/// Sizes of the chrome itself: bar heights, control sizes, meter geometry.
@immutable
class SizeTokens {
  const SizeTokens();

  double get topBarHeight => 52;
  double get statusBarHeight => 26;
  double get controlHeight => 30;
  double get controlMinWidth => 44;
  double get iconSize => 16;
  double get meterWidth => 132;
  double get meterChannelHeight => 7;
  double get meterGap => 3;
  double get focusRingWidth => 2;

  /// Widths of specific chrome elements. They live here rather than at the call
  /// site so that a layout change is a token change (FR-UX-02).
  double get transportReadoutWidth => 148;
  double get overlayLabelWidth => 66;
  double get proseWidth => 420;
  double get dialogProseWidth => 460;
  double get pluginBrowserWidth => 860;
  double get pluginEditorWidth => 760;
  double get pluginEditorHeight => 620;
  double get pluginRowHeight => 54;
  double get parameterRowHeight => 42;
  double get searchHeight => 34;
  double get parameterLabelWidth => 210;
  double get parameterValueWidth => 104;
  double get sliderHeight => 18;
}

/// Motion tokens (FR-UX-06 groundwork). Durations are short on purpose: a DAW
/// is a tool, and animation must never sit between an intent and its result.
@immutable
class MotionTokens {
  const MotionTokens();

  Duration get instant => const Duration(milliseconds: 80);
  Duration get quick => const Duration(milliseconds: 140);
  Duration get settled => const Duration(milliseconds: 240);
  Curve get standard => Curves.easeOutCubic;
  Curve get emphasized => Curves.easeOutBack;

  /// Meter ballistics, in decibels per second, applied against wall-clock time
  /// so that a dropped frame cannot change the decay rate (OB-1-11 §3).
  double get meterDecayDbPerSecond => 40;
  double get meterPeakHoldSeconds => 1.2;
  double get meterAttackDbPerSecond => 600;
}

/// Type scale. Archivo for UI, Martian Mono for anything numeric or time-based
/// so that digits do not jitter as they change (D10).
@immutable
class TypeTokens {
  const TypeTokens({required this.textPrimary, required this.textMuted});

  final Color textPrimary;
  final Color textMuted;

  static const String uiFamily = 'Archivo';
  static const String numericFamily = 'MartianMono';

  TextStyle get title => TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: textPrimary,
  );

  TextStyle get body => TextStyle(
    fontFamily: uiFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  TextStyle get label => TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    color: textMuted,
  );

  /// Dense chrome labels use the condensed width axis of Archivo.
  TextStyle get labelDense => label.copyWith(
    fontVariations: const <FontVariation>[FontVariation('wdth', 87)],
  );

  /// All numerics: tabular figures, fixed width, no jitter as values change.
  TextStyle get numeric => TextStyle(
    fontFamily: numericFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: textPrimary,
  );

  TextStyle get numericLarge =>
      numeric.copyWith(fontSize: 19, letterSpacing: -0.5);
  TextStyle get numericSmall =>
      numeric.copyWith(fontSize: 11, color: textMuted);
}

/// The resolved token set for one theme.
@immutable
class OneBeatTokens {
  const OneBeatTokens({
    required this.brightness,
    required this.color,
    required this.type,
    this.spacing = const SpacingTokens(),
    this.radius = const RadiusTokens(),
    this.border = const BorderTokens(),
    this.size = const SizeTokens(),
    this.motion = const MotionTokens(),
  });

  /// The dark theme — the only one that ships in v0.1. Values are PRD §8.1.1.
  /// A light theme (FR-UX-04) is a second factory here and nothing else.
  factory OneBeatTokens.dark() => _dark;

  static const Color _textPrimaryDark = Color(0xFFE8E9E4);
  static const Color _textMutedDark = Color(0xFF9A9D94);

  static const OneBeatTokens _dark = OneBeatTokens(
    brightness: Brightness.dark,
    color: ColorTokens(
      surfaceDeep: Color(0xFF131412),
      surfacePanel: Color(0xFF1D1F1C),
      surfaceRaised: Color(0xFF2A2C28),
      line: Color(0xFF3A3D37),
      textPrimary: _textPrimaryDark,
      textMuted: _textMutedDark,
      accent: Color(0xFF7C6CF0),
      accentMuted: Color(0xFF4A417F),
      meterLow: Color(0xFF4CAF6A),
      meterMid: Color(0xFFE0A83C),
      meterHigh: Color(0xFFE05252),
      meterTrack: Color(0xFF15170F),
      warning: Color(0xFFE0A83C),
      danger: Color(0xFFE05252),
    ),
    type: TypeTokens(textPrimary: _textPrimaryDark, textMuted: _textMutedDark),
  );

  final Brightness brightness;
  final ColorTokens color;
  final TypeTokens type;
  final SpacingTokens spacing;
  final RadiusTokens radius;
  final BorderTokens border;
  final SizeTokens size;
  final MotionTokens motion;
}

/// Exposes tokens to the widget tree. Material's theme is not used at all: the
/// app is built on `WidgetsApp`, so no Material default can leak a colour that
/// is not a token.
class OneBeatTheme extends InheritedWidget {
  const OneBeatTheme({required this.tokens, required super.child, super.key});

  final OneBeatTokens tokens;

  static OneBeatTokens of(BuildContext context) {
    final OneBeatTheme? theme =
        context.dependOnInheritedWidgetOfExactType<OneBeatTheme>();
    assert(
      theme != null,
      'No OneBeatTheme found. Wrap the app in OneBeatTheme.',
    );
    return theme!.tokens;
  }

  @override
  bool updateShouldNotify(OneBeatTheme oldWidget) => oldWidget.tokens != tokens;
}
