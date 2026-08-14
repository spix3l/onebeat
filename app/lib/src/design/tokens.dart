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
    required this.surfaceWell,
    required this.surfaceHover,
    required this.surfaceColumnHead,
    required this.line,
    required this.lineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentDeep,
    required this.accentBright,
    required this.accentWash,
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
    required this.trafficRed,
    required this.trafficYellow,
    required this.trafficGreen,
    required this.tagPatBg,
    required this.tagPatFg,
    required this.tagAudBg,
    required this.tagAudFg,
    required this.tagAutoBg,
    required this.tagAutoFg,
    required this.waveform,
    required this.knobTrack,
    required this.knobIndicator,
    required this.faderTrack,
    required this.faderThumb,
    required this.sidechainGold,
    required this.channelColors,
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

  /// Controls at rest: buttons, chips and knob rings (Pen `raised`).
  final Color surfaceWell;

  /// The hover step one level above [surfaceWell] (Pen `raised2`).
  final Color surfaceHover;

  /// Table column headers — the one surface that is darker than its panel.
  final Color surfaceColumnHead;

  /// Hairlines and separators. [lineStrong] is the heavier rule the design uses
  /// under the transport bar and around a focused panel.
  final Color line;
  final Color lineStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// The single accent. Chrome stays chromatically quiet so that user clip
  /// colours are the only saturated thing on screen (PRD §15.3).
  final Color accent;

  /// The dark stop of the accent gradient. The design fills every accented
  /// control with a gradient, not a flat colour — see [GradientTokens].
  final Color accentDeep;

  /// The light stop of the accent gradient and the hover/active shade of an
  /// accented control (Pen `accent2`). Lighter than [accent], unlike
  /// [accentDeep].
  final Color accentBright;

  /// A wash of the accent behind an active chip.
  final Color accentWash;
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

  /// macOS window traffic light dots.
  final Color trafficRed;
  final Color trafficYellow;
  final Color trafficGreen;

  /// Track lane type badges (PAT, AUD, AUTO).
  final Color tagPatBg;
  final Color tagPatFg;
  final Color tagAudBg;
  final Color tagAudFg;
  final Color tagAutoBg;
  final Color tagAutoFg;

  /// Waveforms and automation curves.
  final Color waveform;

  /// Controls: knobs and faders.
  final Color knobTrack;
  final Color knobIndicator;
  final Color faderTrack;
  final Color faderThumb;

  /// Routing and sidechain lines.
  final Color sidechainGold;

  /// The eight channel identity colours (c1…c8): channel, clip and track
  /// identity. Saturated on purpose — these are the one place the design lets
  /// saturated colour live (PRD §15.3). The index is the channel colour index,
  /// so element 0 is c1.
  final List<Color> channelColors;

  /// Fully transparent. A role rather than a literal so that widget code never
  /// has to write `Color(0x00000000)` to switch a border off (FR-UX-02).
  Color get none => const Color(0x00000000);

  /// Ink on a clip. Clip fills are user identity colours and always bright, so
  /// their label is dark — the canvas colour, which is the darkest thing the
  /// eye already associates with "behind". [clipInkMuted] is the same ink at
  /// reading strength for the duration under the name; the alpha lives here
  /// rather than at the call site (FR-UX-02).
  Color get clipInk => surfaceDeep;
  Color get clipInkMuted => surfaceDeep.withValues(alpha: 0.62);

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

  Radius get xs => const Radius.circular(2);
  Radius get sm => const Radius.circular(3);
  Radius get md => const Radius.circular(5);

  /// Chips, buttons and step cells (~6–8 in the mockups; step cells are r8).
  Radius get lg => const Radius.circular(8);

  /// Floating windows and the smaller dialogs (~12 in the mockups).
  Radius get xl => const Radius.circular(12);

  /// The larger modal dialogs (~16 in the mockups).
  Radius get xxl => const Radius.circular(16);
  BorderRadius get controlBorder => BorderRadius.all(md);
  BorderRadius get panelBorder => BorderRadius.all(lg);
  BorderRadius get meterBorder => BorderRadius.all(xs);
}

@immutable
class BorderTokens {
  const BorderTokens();

  double get hairline => 1;
  double get emphasis => 2;

  /// Stroke weight of hand-painted glyphs (chevrons, checks, magnifiers) —
  /// between the hairline and the emphasis rule so they read as ink, not
  /// chrome.
  double get glyph => 1.5;
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
  double get channelMeterWidth => 6;
  double get masterChannelMeterWidth => 10;
  double get focusRingWidth => 2;

  /// Widths of specific chrome elements. They live here rather than at the call
  /// site so that a layout change is a token change (FR-UX-02).
  double get transportReadoutWidth => 124;
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
  double get inspectorWidth => 280;

  /// The rebuilt playlist (UI-B-08), measured off `screens/arrangement.png`.
  /// Lanes are a 50px pitch carrying a 44px card, and four bars of the ruler
  /// span 153px — so a bar is a hair over 38.
  double get playlistLaneHeight => 50;
  double get playlistClipHeight => 44;
  double get playlistPxPerBar => 38.3;
  double get playlistRulerHeight => 20;
  double get playlistHeaderHeight => 32;

  /// The ruler numbers every fourth bar, as the mockup labels them.
  int get playlistBarLabelEvery => 4;

  /// Shared editor chrome.
  double get playheadWidth => 2;
  double get patternSelectorWidth => 236;
  double get patternRowHeight => 30;
  double get viewSwitcherHeight => 34;
  double get viewSwitcherTileWidth => 52;
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
  double get bpmFieldWidth => 130;
  double get signatureWidth => 78;
  double get clockWidth => 236;
  double get searchWidth => 200;
  double get brandWidth => 148;

  /// macOS window traffic light indicators.
  double get trafficLightSize => 11;
  double get trafficLightSpacing => 7;

  /// The gap the real macOS traffic lights need at the left of the top bar.
  /// The window uses a full-size content view (see MainFlutterWindow.swift),
  /// so the close/minimise/zoom buttons sit *inside* the app's own chrome and
  /// the brand mark has to start after them.
  double get titleBarInset => 82;

  /// Transport buttons are square wells in the design, not text buttons — the
  /// play control is the one accented thing in the bar.
  double get transportButtonSize => 32;
  double get transportGlyphSize => 13;

  /// Badges and tags.
  double get tagWidth => 36;
  double get tagHeight => 16;
  double get tagRadius => 3;

  /// Top chrome (UI-B-02). Two stacked bars sit on every screen: the 24px
  /// system/menu bar and the 68px transport bar below it. The readout boxes
  /// are the dark inset wells between them — taller than the old 34px strip
  /// because their numerals are 21px MartianMono.
  double get menuBarHeight => 24;
  double get transportBarHeight => 68;
  double get readoutBoxHeight => 44;

  /// The rounded accent square in the transport bar's title block.
  double get appTileSize => 28;

  /// macOS traffic-light dots as the transport bar itself draws them (the
  /// window's real ones sit inside the app's chrome — see MainFlutterWindow).
  double get trafficLightDotSize => 12;

  /// The master meter sliver pair at the transport bar's right edge: two
  /// hairline-thin vertical L/R bars, as tall as the readout boxes beside them.
  double get masterMeterSliverWidth => 4;
  double get masterMeterSliverGap => 2;

  /// Core controls (UI-B-01). The micro field is the 26px-tall strip the
  /// dropdowns, FX chips and chip rows all sit in — one height so a row of
  /// mixed controls shares a baseline.
  double get microFieldHeight => 26;
  double get dropdownWidth => 156;
  double get chipHeight => 26;
  double get fxChipWidth => 67;
  double get chipDotSize => 6;
  double get toggleChipSize => 18;
  double get railButtonWidth => 42;

  /// Search chrome: the full field, and the compact round icon variant that
  /// sits at the right of the rack header.
  double get searchFieldHeight => 26;
  double get searchIconFieldSize => 26;
  double get browserHeaderHeight => 38;
  double get browserSearchHeight => 32;
  double get exportButtonWidth => 84;

  /// Knobs, faders, and dialog sizes.
  /// The compact knob control: 26px in the mockups (UI-B-01).
  double get knobSmall => 26;
  double get knobMedium => 42;
  double get knobLarge => 56;
  double get faderWidth => 28;
  double get faderHeight => 160;
  double get faderThumbHeight => 16;
  double get faderThumbWidth => 24;

  /// A mixer strip's rotated track name reserves this much vertical run.
  double get mixerNameHeight => 78;
  double get modalWidthLarge => 680;
  double get modalWidthMedium => 540;
  double get dialogHeaderHeight => 48;
  double get menuItemHeight => 28;
  double get checkboxSize => 16;
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
  const TypeTokens({
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.clipInk,
    required this.clipInkMuted,
  });

  final Color textPrimary;

  /// The middle of the three text weights. Row names and prose sit here: loud
  /// enough to read as content, quiet enough that a value beside them wins.
  final Color textSecondary;
  final Color textMuted;

  /// Ink for text that sits on a bright identity fill rather than on a
  /// surface — a playlist clip's label. Mirrors [ColorTokens.clipInk], which
  /// is where the role is defined.
  final Color clipInk;
  final Color clipInkMuted;

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

  /// Row names and running prose — [body] at the middle weight.
  TextStyle get bodySecondary => body.copyWith(color: textSecondary);

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

  /// Rail tile captions. The rail is 60px wide and the captions have to fit on
  /// one line inside it — a wrapped "CHANNEL/S" is the tell that this style was
  /// borrowed from [label] rather than sized for its own column.
  TextStyle get railLabel => TextStyle(
    fontFamily: uiFamily,
    fontSize: 9,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: textMuted,
    fontVariations: const <FontVariation>[FontVariation('wdth', 87)],
  );

  /// A playlist clip's name and the duration under it (UI-B-08). Both take
  /// the dark ink roles rather than a text colour: they sit on a bright
  /// identity fill, not on a surface.
  TextStyle get clipName => TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: clipInk,
  );

  TextStyle get clipDuration => TextStyle(
    fontFamily: numericFamily,
    fontSize: 9,
    fontWeight: FontWeight.w500,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: clipInkMuted,
  );

  /// Tag labels (PAT, AUD, AUTO).
  TextStyle get tag => TextStyle(
    fontFamily: uiFamily,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: textPrimary,
  );

  /// Menu bar items.
  TextStyle get menu => TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  /// Top chrome (UI-B-02). The `OneBeat` wordmark in the menu bar — smaller
  /// and quieter than [brand], which is the title-block treatment.
  TextStyle get wordmark => TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: textPrimary,
  );

  /// The `ONEBEAT` caps line of the transport bar's title block: wide-tracked
  /// small caps, one step down from [brand] so it reads as chrome, not a
  /// headline.
  TextStyle get brandCaps => TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
    color: textPrimary,
  );

  /// The numerals of the top-bar readout boxes (BPM, time signature, the
  /// bar·beat·tick clock): the largest mono in the app at 21px, the size the
  /// design gives the values a user glances at most often. Tightened because
  /// MartianMono runs wide, and at the default line height the value + unit
  /// stack does not fit a 44px box.
  TextStyle get readoutValue => numeric.copyWith(
    fontSize: 21,
    letterSpacing: -0.5,
    height: 1.15,
  );

  /// The unit label under a readout value — [microCaps] on the same tightened
  /// leading so the pair stacks inside the box.
  TextStyle get readoutUnit => microCaps.copyWith(height: 1.2);

  /// Section headers like BROWSER, PLAYLIST.
  TextStyle get sectionHeader => TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
    color: textPrimary,
  );

  /// Breadcrumbs in piano roll and inspectors.
  TextStyle get breadcrumb => TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Knob labels and values.
  TextStyle get knobLabel => TextStyle(
    fontFamily: uiFamily,
    fontSize: 9,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: textMuted,
  );

  /// Micro caps in MartianMono: the `VOL`/`PAN` captions under knobs and the
  /// `SNAP`/`SCALE` prefixes inside dropdown fields. Mono so a column of them
  /// aligns glyph-to-glyph across controls (UI-B-01).
  TextStyle get microCaps => TextStyle(
    fontFamily: numericFamily,
    fontSize: 8,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: textMuted,
  );

  TextStyle get knobValue => TextStyle(
    fontFamily: numericFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  /// Dialog and modal titles.
  TextStyle get dialogTitle => TextStyle(
    fontFamily: uiFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  /// All numerics: tabular figures, fixed width, no jitter as values change.
  TextStyle get numeric => TextStyle(
    fontFamily: numericFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: textPrimary,
  );

  /// The readout size: the tempo field, the time signature, the clock.
  ///
  /// 15, not the 19 this used to be. Measured off the design screens — the
  /// digits there stand 11px tall, which is 15px of MartianMono — and the
  /// difference is not cosmetic: at 19 the three top-bar wells were 64px wider
  /// between them than the design draws, which is most of the reason the bar
  /// could not fit the window's own minimum width.
  TextStyle get numericLarge =>
      numeric.copyWith(fontSize: 15, letterSpacing: -0.5);
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

  static const Color _textPrimaryDark = Color(0xFFE8E9E4); // Pen `text`

  /// Secondary copy: row names, prose (Pen `muted`). The design uses three
  /// text weights, not two — collapsing them is why every caption read as loud
  /// as its value.
  static const Color _textSecondaryDark = Color(0xFF9A9D94); // Pen `muted`

  /// The dimmest tier: placeholders, empty states, disabled labels (Pen
  /// `dim`). Deliberately below the AA bar the contrast test holds the two
  /// readable tiers to — this tier is decorative, not essential, and FR-UX-26
  /// covers "text and essential UI" rather than every dimmed glyph.
  static const Color _textMutedDark = Color(0xFF6F726B); // Pen `dim`

  /// The canvas colour, used as ink on a clip's bright fill (UI-B-08).
  static const Color _clipInkDark = Color(0xFF1B1D1A);
  static const Color _clipInkMutedDark = Color(0x9E1B1D1A);

  static const OneBeatTokens _dark = OneBeatTokens(
    brightness: Brightness.dark,
    color: ColorTokens(
      // Values are the Pen palette (UI-A-01), which is authoritative: where it
      // differs from the values sampled for the stage-3 screens, the palette
      // wins.
      surfaceSunken: Color(0xFF131412), // bg-deep
      surfaceDeep: Color(0xFF1B1D1A), // panel
      surfacePanel: Color(0xFF1B1D1A), // panel
      surfaceRaised: Color(0xFF22251F), // panel2
      surfaceOverlay: Color(0xFF2A2D27),
      surfaceWell: Color(0xFF2A2D27), // raised: buttons, chips at rest
      surfaceHover: Color(0xFF33372F), // raised2
      surfaceColumnHead: Color(0xFF181A16),
      line: Color(0xFF2C2F29), // line2
      lineStrong: Color(0xFF3A3D37), // line
      textSecondary: _textSecondaryDark,
      textPrimary: _textPrimaryDark,
      textMuted: _textMutedDark,
      accent: Color(0xFF7C6CF0), // accent
      accentDeep: Color(0xFF6A5DE0),
      accentBright: Color(0xFF9A8EFF), // accent2: hover/active shade
      accentWash: Color(0x187C6CF0),
      accentMuted: Color(0xFF4A417F),
      meterLow: Color(0xFF5CCB8A),
      meterMid: Color(0xFFE6B85C),
      meterHigh: Color(0xFFE66A6A),
      meterTrack: Color(0xFF0A0B0A),
      warning: Color(0xFFE6B85C),
      danger: Color(0xFFE66A6A),
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
      marqueeFill: Color(0x247C6CF0),
      clipSelectedOutline: Color(0xFFB9AEFF),
      trafficRed: Color(0xFFE66A6A),
      trafficYellow: Color(0xFFE6B85C),
      trafficGreen: Color(0xFF5CCB8A),
      tagPatBg: Color(0xFF1A3323),
      tagPatFg: Color(0xFF65D48E),
      tagAudBg: Color(0xFF162D42),
      tagAudFg: Color(0xFF5ABAE0),
      tagAutoBg: Color(0xFF2B263B),
      tagAutoFg: Color(0xFFB2A3E8),
      waveform: Color(0xFF5ABAE0),
      knobTrack: Color(0xFF24262A),
      knobIndicator: Color(0xFF7C6CF0),
      faderTrack: Color(0xFF101210),
      faderThumb: Color(0xFF5A5C54),
      sidechainGold: Color(0xFFF59E5B),
      channelColors: channelColors,
    ),
    type: TypeTokens(
      textPrimary: _textPrimaryDark,
      textSecondary: _textSecondaryDark,
      textMuted: _textMutedDark,
      clipInk: _clipInkDark,
      clipInkMuted: _clipInkMutedDark,
    ),
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

/// The rendered width of [text] in [style].
///
/// Chrome that holds numbers — the tempo field, the bar/beat/tick clock — used
/// to be sized by a hand-tuned width token, which is a guess about a font's
/// metrics written down in a second place. When the guess was low the digits
/// painted straight over the caption beside them. Measuring costs one layout at
/// build time and cannot be wrong.
double measureText(TextStyle style, String text) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

/// Project colours are user data rather than chrome tokens, but parsing them
/// belongs at the design boundary so UI widgets never invent colour literals.
Color projectColor(String hex, Color fallback) {
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// Channel identity colours (c1…c8) from the Pen palette. Shared by every
/// theme — identity colour does not change with light/dark. Indexed by channel
/// colour index, so element 0 is c1.
const List<Color> channelColors = <Color>[
  Color(0xFFF26D5B), // c1
  Color(0xFFE8B54B), // c2
  Color(0xFF9FC65C), // c3
  Color(0xFF37BE93), // c4
  Color(0xFF2FB8C6), // c5
  Color(0xFFE5689E), // c6
  Color(0xFFC97452), // c7
  Color(0xFF7A8BA6), // c8
];

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
