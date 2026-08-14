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
    required this.surfaceSunken,
    required this.surfaceDeep,
    required this.surfacePanel,
    required this.surfaceRaised,
    required this.surfaceOverlay,
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
    required this.gridLine,
    required this.gridLineStrong,
    required this.rollCanvas,
    required this.rowShade,
    required this.rowShadeInScale,
    required this.noteFill,
    required this.noteSelected,
    required this.noteGhost,
    required this.playhead,
    required this.canvasScrim,
    required this.marqueeFill,
    required this.clipSelectedOutline,
  });

  /// Recessed: the top bar and anything that reads as an input well. The
  /// design screens put the chrome *below* the canvas in depth, not above it,
  /// which is why this is darker than [surfaceDeep] rather than lighter.
  final Color surfaceSunken;

  /// The canvas: arrangement, rack and roll backgrounds.
  final Color surfaceDeep;

  /// Panels sitting on the deep surface.
  final Color surfacePanel;

  /// Controls and cards raised above a panel: the left rail, toolbar wells.
  final Color surfaceRaised;

  /// The topmost level: chips, hover and selected rows, and popup menus. The
  /// design screens use five surface levels, not three, and collapsing them was
  /// why hover states used to read as "selected".
  final Color surfaceOverlay;

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

  /// Canvas chrome for the piano roll and the arrangement. Beat lines and bar
  /// lines are two different weights of the same idea, which is why they are
  /// two tokens rather than one with an opacity applied at the call site.
  final Color gridLine;
  final Color gridLineStrong;

  /// The piano roll's canvas. Deliberately cooler than the chrome, which is
  /// how the design screens separate "the thing you are editing" from "the
  /// tool you are editing it with" — the roll is the only surface that does
  /// this, and it is the one users stare at longest.
  final Color rollCanvas;

  /// Banding on the roll, both relative to [rollCanvas]: accidental rows sit
  /// *below* it and in-scale rows *above* it, so the scale reads as a lift
  /// rather than as a second colour (OB-3-10 §1).
  final Color rowShade;
  final Color rowShadeInScale;

  /// Notes. `noteGhost` draws the other instruments' notes behind the edited
  /// sequence — context without competing for attention.
  final Color noteFill;
  final Color noteSelected;
  final Color noteGhost;

  final Color playhead;

  /// Dims the canvas past the end of the pattern or the arrangement: the region
  /// stays visible (so the user sees where content stops) without reading as
  /// editable space.
  final Color canvasScrim;

  /// Lasso fill. Translucent by construction, resolved here rather than at the
  /// call site so no widget derives its own opacity (FR-UX-02).
  final Color marqueeFill;

  /// The accent outline on a selected clip, and on every clip of the selected
  /// pattern (D-M6 instance highlighting).
  final Color clipSelectedOutline;

  /// Velocity reads as opacity on a note. The ramp lives here because "how
  /// loud looks how solid" is a design decision, not a painter detail; `unit`
  /// is 0..1.
  Color noteAtVelocity(double unit) {
    final double clamped = unit.clamp(0.0, 1.0);
    return noteFill.withValues(alpha: 0.45 + 0.55 * clamped);
  }
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
  double get instrumentStripWidth => 264;
  double get parameterRowHeight => 42;
  double get searchHeight => 34;
  double get parameterLabelWidth => 210;
  double get parameterValueWidth => 104;
  double get sliderHeight => 18;
  double get stockPianoControlSize => 72;
  double get stockPianoKeyboardHeight => 150;
  double get rackToolbarHeight => 58;
  double get rackHeaderWidth => 316;
  double get rackRowHeight => 52;
  double get rackStepWidth => 34;
  double get rackStepInset => 3;
  double get rackVelocityHeight => 4;
  double get rackCursorWidth => 2;

  /// Piano roll (OB-3-10). Row height and key width are the two numbers the
  /// whole canvas is derived from, so zoom is a multiplier on these rather than
  /// a second set of constants.
  double get pianoRowHeight => 14;
  double get pianoKeyboardWidth => 76;
  double get pianoRulerHeight => 24;
  double get pianoVelocityStripHeight => 96;
  double get pianoNoteInset => 1;
  double get pianoNoteRadius => 2;
  double get pianoToolbarHeight => 44;
  double get pianoResizeHandleWidth => 6;

  /// Arrangement (OB-3-12).
  double get laneHeaderWidth => 208;
  double get laneDefaultHeight => 72;
  double get laneCollapsedHeight => 26;
  double get arrangementRulerHeight => 28;
  double get clipRadius => 4;
  double get clipInspectorWidth => 268;
  double get clipBadgeHeight => 16;

  /// Shared editor chrome.
  double get playheadWidth => 2;
  double get patternSelectorWidth => 236;
  double get patternRowHeight => 30;
  double get viewSwitcherHeight => 34;
  double get noticeHeight => 34;
  double get swatchSize => 18;

  /// The left icon rail from the design screens: a fixed column of destination
  /// tiles down the window's left edge.
  double get railWidth => 60;
  double get railTileSize => 44;
  double get railGlyphSize => 20;

  /// Top-bar readouts. The design shows BPM, time signature and the
  /// BAR·BEAT·TICK clock as three separate wells rather than one strip.
  double get readoutHeight => 34;
  double get bpmFieldWidth => 108;
  double get signatureWidth => 74;
  double get clockWidth => 208;
  double get searchWidth => 200;
  double get brandWidth => 148;
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

  /// The wordmark. Wide-tracked and uppercase, which is the one place in the
  /// app where letter-spacing is a deliberate identity choice rather than a
  /// readability one.
  TextStyle get brand => TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: textPrimary,
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
      // Sampled from the design screens rather than transcribed by eye. The
      // family is the warm neutral PRD §8.1.1 always specified; what the
      // screens add is a fifth level — a *sunken* surface for the top bar and
      // input wells — and slightly lighter panel and raised steps.
      surfaceSunken: Color(0xFF101210),
      surfaceDeep: Color(0xFF161814),
      surfacePanel: Color(0xFF1B1D1A),
      surfaceRaised: Color(0xFF20231F),
      surfaceOverlay: Color(0xFF2A2D27),
      line: Color(0xFF3A3D37),
      textPrimary: _textPrimaryDark,
      textMuted: _textMutedDark,
      accent: Color(0xFF7264E8),
      accentMuted: Color(0xFF4A417F),
      meterLow: Color(0xFF4CAF6A),
      meterMid: Color(0xFFE0A83C),
      meterHigh: Color(0xFFE05252),
      meterTrack: Color(0xFF15170F),
      warning: Color(0xFFE0A83C),
      danger: Color(0xFFE05252),
      // Canvas chrome (OB-3-10/12). Kept inside PRD §8.1.1's warm-neutral
      // family: the design screens render a cooler black, but §8.1.1 is
      // normative and retinting the whole app is an owner decision, not a
      // side effect of building the piano roll.
      gridLine: Color(0xFF24262A),
      gridLineStrong: Color(0xFF383B44),
      rollCanvas: Color(0xFF1B1C20),
      rowShade: Color(0xFF16181C),
      rowShadeInScale: Color(0xFF232426),
      noteFill: Color(0xFF48BCD2),
      noteSelected: Color(0xFFE7ECF7),
      noteGhost: Color(0xFF2F3138),
      playhead: Color(0xFF9A8EFF),
      canvasScrim: Color(0x8C101210),
      marqueeFill: Color(0x247264E8),
      clipSelectedOutline: Color(0xFFB9AEFF),
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

/// Project colours are user data rather than chrome tokens, but parsing them
/// belongs at the design boundary so UI widgets never invent colour literals.
Color projectColor(String hex, Color fallback) {
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

const List<String> instrumentPalette = <String>[
  '#6C8CFF',
  '#B779F2',
  '#EF6F91',
  '#F59E5B',
  '#E7C75F',
  '#66C58F',
  '#50B8C6',
  '#8294B8',
];

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
