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

  /// The snap subdivision on the roll — the third and faintest weight, under
  /// [gridLine]. A subdivision line has to be visible enough to aim at and
  /// quiet enough that a 1/32 grid does not read as a solid field.
  Color get gridLineSubdivision => gridLine.withValues(alpha: 0.4);

  /// The roll's scroll rails.
  ///
  /// The thumb is [lineStrong] rather than a surface: an always-visible rail
  /// only earns its space if you can find it without looking for it, and at
  /// [surfaceWell] on [surfaceSunken] the contrast was low enough that the rail
  /// read as an empty gutter. Rails are chrome, so the resting thumb stops at
  /// line strength and only reaches text strength under the pointer.
  Color get scrollTrack => surfaceSunken;
  Color get scrollThumb => lineStrong;
  Color get scrollThumbHover => textMuted;

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

  /// The danger family beyond the plain [danger] ink (UI-B-11, UI-C-11).
  ///
  /// A contained failure has to read as *contained*: the crashed extension row
  /// and the crash card are outlined and washed, never filled. A filled red
  /// panel says "your project is on fire", and the whole point of the copy
  /// inside it is that nothing is.
  Color get dangerWash => danger.withValues(alpha: 0.08);
  Color get dangerMuted => danger.withValues(alpha: 0.45);

  /// The accent at outline strength — a selected-but-not-active border, and
  /// the tint behind a dock target while a panel is mid-drag (UI-C-12).
  Color get accentOutline => accent.withValues(alpha: 0.7);

  /// A dragged panel's ghost: the accent at the strength that still lets the
  /// arrangement under it show through, because what you are aiming at is what
  /// matters, not what you are holding.
  Color get dragGhostFill => accent.withValues(alpha: 0.10);

  /// The drop shadow under a floating window. Windows are the one surface in
  /// the app that is allowed a shadow — it is what says "this is above the
  /// document" when every other panel is flush with it.
  Color get windowShadow => const Color(0x73000000);

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

  /// An unlit step cell, on the darker of the two beat bands.
  ///
  /// The rack shades its rest cells in blocks of four and the block alternates,
  /// the way FL Studio's does. It is the single cheapest thing on the surface:
  /// the group gaps tell you *that* there are beats, and the banding tells you
  /// *which one you are on* — you drop a hit on the and-of-three by reading the
  /// band rather than by counting cells across a bar.
  Color get stepRest => surfaceSunken;

  /// An unlit step cell on the lifted band — beats 1 and 3 of every bar, so the
  /// downbeat opens on the brighter shade.
  Color get stepRestLifted => surfaceRaised;

  /// The two stops of a lit step cell's fill, top then bottom.
  ///
  /// The design fills accented controls with a gradient rather than a flat
  /// colour, and a step also has to carry its velocity: quiet steps sit back
  /// toward [accentMuted], loud ones reach the full accent. The floor is 0.4
  /// so that a step at velocity zero still reads as *on* — "lit but quiet" and
  /// "off" must never look the same.
  List<Color> stepGradient(double velocity) {
    final double unit = 0.4 + 0.6 * velocity.clamp(0.0, 1.0);
    return <Color>[Color.lerp(accentMuted, accentDeep, unit)!, Color.lerp(accentMuted, accent, unit)!];
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

  /// The compact title strip above the rack controls. The workspace gutters
  /// provide the breathing room; this row only needs to hold its title and the
  /// pattern select.
  double get rackHeaderHeight => 34;

  /// The header's pattern select. Wider than [dropdownWidth] because a pattern
  /// name is user data — the strip of tabs this replaced could not fit four
  /// sample-named patterns in any window, and truncating the one field that
  /// says which pattern you are editing would repeat that mistake in miniature.
  double get rackPatternFieldWidth => 232;
  double get rackHeaderWidth => 316;
  double get rackRowHeight => 52;
  double get rackStepWidth => 34;
  double get rackStepInset => 3;
  double get rackVelocityHeight => 4;
  double get rackCursorWidth => 2;

  /// The channel inspector strip (UI-B-06), measured off the bottom of
  /// `screens/channel-rack.png`. One row: identity, mix, mute/solo, routing,
  /// keyboard.
  double get inspectorHeight => 120;
  double get inspectorTileSize => 48;
  double get inspectorWaveWidth => 275;
  double get inspectorWaveHeight => 44;

  /// Waveform bars are drawn, not sampled: a fixed bar pitch keeps the
  /// preview legible at any strip width and keeps the paint cost flat.
  double get inspectorWaveBarPitch => 3;

  /// The round state lamps under the M and S chips.
  double get inspectorLampSize => 18;
  double get inspectorLampDotSize => 8;

  /// The channel's step-divisor select. Wide enough for the `GRID` prefix,
  /// `1/16` and the chevron — squeezed narrower it shows a chevron over an
  /// ellipsis, which is a control you cannot read.
  double get inspectorGridFieldWidth => 104;

  /// The two-octave keyboard at the strip's right edge.
  double get inspectorKeyboardWidth => 166;
  double get inspectorKeyboardHeight => 54;

  /// The rebuilt channel rack (UI-B-05), measured off
  /// `components/channel-row.png` — a 919×46 row whose every landmark is
  /// listed here, so a change to the rhythm is a change to one file.
  ///
  /// The lane is 46px, not [rackRowHeight]'s 52: the old rack sized itself,
  /// this one is sized by the design. Both survive until UI-D-09.
  double get rackLaneHeight => 46;

  /// Step cells: 30px squares on a 34px pitch, with a wider gap every four so
  /// the beat groups read without a rule between them.
  double get rackStepCell => 30;
  double get rackStepGap => 4;
  double get rackStepGroupGap => 8;

  /// The lane's left block: power well, identity chip, name column. Their
  /// widths add up to where the grid starts, which is why they live together.
  double get rackPowerSize => 18;
  double get rackColorChipSize => 22;
  double get rackNameWidth => 158;

  /// The mono route chip at the lane's right edge (`→ D1`).
  double get rackRouteChipWidth => 42;
  double get rackCompactBreakpoint => 900;

  /// The accent bar down the left edge of the selected lane.
  double get rackSelectedEdgeWidth => 3;

  /// The rack's own chrome rows: the control toolbar above the grid, the
  /// column-caption strip under it, and the "add a channel" card below.
  double get rackToolbarBarHeight => 38;
  double get rackColumnHeaderHeight => 25;
  double get rackFooterHeight => 44;

  /// The toolbar's three select fields. They differ because their labels do:
  /// `CHANNEL TYPE Sampler` needs room the `SNAP 1/4` field would waste.
  double get rackTypeFieldWidth => 200;
  double get rackGroupFieldWidth => 140;
  double get rackSnapFieldWidth => 130;

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

  /// The grab zone at a note's right edge. Wide enough to hit without aiming;
  /// the roll additionally caps it at a third of the note so a short note is
  /// still mostly draggable rather than all handle.
  double get pianoResizeHandleWidth => 8;

  /// The rebuilt piano roll (UI-B-07), measured off `screens/piano-roll.png`.
  /// [pianoRowHeight] (14) survives unchanged — the mockup's octave spans 168px
  /// — but the key column is 60px there, not [pianoKeyboardWidth]'s 76.
  double get prKeyColumnWidth => 60;
  double get prBarRulerHeight => 24;
  double get prToolbarHeight => 38;
  double get prVelocityLaneHeight => 72;

  /// A note bar inside its 14px row, and the radius that keeps it from
  /// reading as a hard-edged block at this size.
  ///
  /// Nearly fills the row, leaving a hairline of banding above and below. At 8
  /// the bar was a thin stripe floating in the middle of its row: hard to aim
  /// at, and hard to read as occupying a pitch at all.
  double get prNoteHeight => 16;

  /// Black keys are this fraction of the column wide, and the C-label plate
  /// this tall.
  double get prBlackKeyWidth => 36;

  /// The `VEL ▾` selector at the left of the velocity lane.
  double get prVelocityChipWidth => 56;

  /// The velocity stem's width — thick enough to hit, thin enough that a
  /// dense bar stays countable.
  double get prVelocityStemWidth => 5;

  /// The roll toolbar's pattern select. Wider than the default because a
  /// pattern name is user data — `Main Groove` must not truncate to `Main
  /// Gro…` in the one field that says which pattern you are editing.
  double get prPatternFieldWidth => 190;

  /// The roll's always-visible scroll rails. Thin enough to read as chrome,
  /// thick enough to grab without aiming. [prScrollbarMinThumb] is the floor a
  /// thumb never paints below: on 128 rows at a tight zoom the proportional
  /// thumb would otherwise vanish exactly when it is most needed.
  double get prScrollbarThickness => 12;
  double get prScrollbarMinThumb => 28;

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
  double get playlistResizeHandleWidth => 10;
  double get playlistPxPerBar => 38.3;
  double get playlistRulerHeight => 20;
  double get playlistHeaderHeight => 32;

  /// The ruler numbers every fourth bar, as the mockup labels them.
  int get playlistBarLabelEvery => 4;

  /// The track header column, left to right (UI-B-08).
  ///
  /// The lane's identity colour is a spine down the header's left edge rather
  /// than a swatch floating in it: a swatch reads as a button you can press,
  /// and twelve of them stacked read as a column of buttons. A spine reads as
  /// what it is — this row belongs to that colour — and it lines the header up
  /// with the clips that carry the same colour out on the canvas.
  double get playlistLaneSpineWidth => 3;

  /// The disclosure triangle and the lane number get fixed columns so the
  /// names start on one vertical line whether the number is `1` or `12`.
  double get playlistLaneDiscloseSize => 14;
  double get playlistLaneIndexWidth => 18;

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

  /// The hairline rule the rail draws above its last destination (UI-B-03).
  /// Inset from both edges so it reads as a grouping mark rather than as a
  /// second panel border.
  double get railSeparatorWidth => 28;

  /// The status bar's tone dot: bigger than a chip dot because it is the one
  /// thing in the bar a user reads at a glance from across the desk.
  double get statusDotSize => 8;

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

  /// The glyph inside that well. 15 rather than 13: the arrows carry an arc and
  /// a head, and two more pixels is the difference between reading them and
  /// recognising them by position.
  double get transportGlyphSize => 15;

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

  /// The browser panel (UI-B-04). Width and row rhythm are measured off
  /// `screens/channel-rack.png` at the export's 2× scale: a 240px column of
  /// 24px rows, children indented one glyph box per level.
  double get browserWidth => 240;
  double get browserRowHeight => 24;
  double get browserRowIndent => 18;

  /// The identity tick beside a pattern name: a slim vertical bar rather than
  /// a dot, so a colour reads at a glance down a column of rows.
  double get browserTickWidth => 3;
  double get browserTickHeight => 14;

  /// The 8px identity dot on a sample row, and the waveform mark at its right
  /// edge that says "this is audio".
  double get browserDotSize => 8;
  double get browserWaveWidth => 14;
  double get browserWaveHeight => 12;
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

  /// The routing panel (UI-B-10), measured off the right half of
  /// `screens/routing-mixer.png`. Rows are generous on purpose: this is the
  /// one panel in the app that is read as sentences rather than scanned as a
  /// table.
  double get routingRowHeight => 40;
  double get routingHeaderHeight => 32;
  double get routingSectionLabelHeight => 34;
  double get routingDotSize => 12;

  /// A send's slider and the mono value beside it.
  double get routingSliderWidth => 200;
  double get routingSliderTrackHeight => 8;
  double get routingSliderCapSize => 14;
  double get routingValueWidth => 52;

  /// The `PRE`/`POST` tag.
  double get routingTagWidth => 48;

  /// The sidechain card and the switch inside it.
  double get routingSidechainHeight => 72;
  double get routingSwitchWidth => 34;
  double get routingSwitchHeight => 18;

  /// The rebuilt mixer (UI-B-09), measured off `screens/routing-mixer.png`
  /// and the floating window in `screens/workspace-window.png`.
  ///
  /// Two strip variants, two widths: the docked meter strip is a 42px column
  /// on a 46px pitch, and the floating fader strip is 108px because a fader
  /// needs a grabbable target where a meter only needs to be read.
  double get mixerStripWidth => 42;
  double get mixerStripGap => 4;
  double get mixerMasterStripWidth => 50;
  double get mixerFaderStripWidth => 108;

  /// The meter well inside a strip. The master's is wider — it is the one
  /// meter a mix engineer watches continuously.
  double get mixerMeterWidth => 12;
  double get mixerMasterMeterWidth => 14;

  /// The identity bar under a strip's name.
  double get mixerColorBarHeight => 4;

  /// The M/S squares and the round route lamp beside them.
  double get mixerToggleSize => 13;
  double get mixerLampSize => 13;

  /// The fader's track and its cap.
  double get mixerFaderTrackWidth => 6;
  double get mixerFaderCapWidth => 22;
  double get mixerFaderCapHeight => 8;
  double get modalWidthLarge => 680;
  double get modalWidthMedium => 540;
  double get dialogHeaderHeight => 48;
  double get menuItemHeight => 28;
  double get checkboxSize => 16;

  /// Shared overlay chrome (UI-B-11), measured off `screens/workspace-window.png`
  /// and `screens/ext-manager.png`.
  ///
  /// A popover is 230 wide because that is what the LAYOUTS menu needs for
  /// `Reset to default` plus its icon gutter; the Tools menu in the extension
  /// manager is wider because its rows carry a right-aligned shortcut.
  double get popoverWidth => 230;
  double get popoverWideWidth => 300;
  double get popoverRowHeight => 28;
  double get popoverIconGutter => 20;
  double get popoverSectionHeight => 24;

  /// A floating window's title bar, and the square icon buttons in it.
  double get windowHeaderHeight => 38;
  double get windowIconButton => 22;
  double get windowShadowBlur => 32;
  double get windowShadowOffset => 8;

  /// The generic button (UI-B-11): one height for every variant, so a row of
  /// mixed primary/secondary/danger buttons shares a baseline.
  double get buttonHeight => 30;
  double get buttonLargeHeight => 40;
  double get buttonMinWidth => 72;

  /// The empty state (UI-B-11 §3): the hairline icon tile above the heading,
  /// and the prose column the body wraps inside.
  double get emptyTileSize => 92;
  double get emptyGlyphSize => 34;
  double get emptyProseWidth => 640;

  /// The extension manager (UI-C-11), measured off `screens/ext-manager.png`.
  ///
  /// The list is a fixed 334px column against a detail panel that takes the
  /// rest — the list is a table of contents and never earns more width, and
  /// the capability rows below it are the widest thing on the screen.
  double get extListWidth => 334;
  double get extRowHeight => 48;
  double get extRowTileSize => 30;
  double get extDetailTileSize => 44;

  /// Capability and binding rows: two different rhythms on purpose. A
  /// capability is scanned as a column of yes/no, a binding is read as a
  /// sentence, so the binding row is the taller of the two.
  double get extCapabilityRowHeight => 32;
  double get extBindingRowHeight => 36;
  double get extCapabilityMarkSize => 20;

  /// The pill switch that enables an extension, and the `CRASHED` tag beside
  /// the one that is off because it failed.
  double get extSwitchWidth => 34;
  double get extSwitchHeight => 18;
  double get extSwitchKnobSize => 14;
  double get extCrashTagWidth => 62;

  /// A docked extension panel (`screens/ext-panel.png`): the header strip every
  /// panel shares, and the parameter rows inside the extension's own surface.
  double get panelHeaderHeight => 30;
  double get panelGripWidth => 18;
  double get panelParamRowHeight => 20;
  double get panelParamLabelWidth => 70;
  double get panelParamTrackHeight => 7;
  double get panelListRowHeight => 42;
  double get panelMeterWellHeight => 350;

  /// Workspace overlays (UI-C-12), measured off `screens/workspace-window.png`
  /// and `screens/workspace-drag.png`.
  double get layoutsPillWidth => 168;
  double get detachedWindowWidth => 668;
  double get detachedWindowHeight => 760;
  double get pluginWindowWidth => 440;
  double get pluginWindowHeight => 340;

  /// A dock target chip and the ghost of the panel being dragged onto it.
  double get dockChipHeight => 22;
  double get dockChipMinWidth => 68;
  double get dockTabCardWidth => 220;
  double get dockTabCardHeight => 58;
  double get dockTabTileSize => 24;
  double get dragGhostHeaderHeight => 26;
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

  /// How long the pointer must rest on an icon-only control before it names
  /// itself. Long enough that sweeping across a toolbar stays quiet, short
  /// enough that stopping on a glyph feels like asking a question.
  Duration get tooltipDelay => const Duration(milliseconds: 400);

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

  TextStyle get body => TextStyle(fontFamily: uiFamily, fontSize: 13, fontWeight: FontWeight.w400, color: textPrimary);

  /// Row names and running prose — [body] at the middle weight.
  TextStyle get bodySecondary => body.copyWith(color: textSecondary);

  TextStyle get label =>
      TextStyle(fontFamily: uiFamily, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4, color: textMuted);

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
  TextStyle get labelDense => label.copyWith(fontVariations: const <FontVariation>[FontVariation('wdth', 87)]);

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

  /// The rebuilt rail's caption (UI-B-01/03). One step below [railLabel]: the
  /// mockup fits `CHANNELS` inside the 42px tile, and 9px cannot — it wraps to
  /// `CHANNEL/S`, which is the same tell [railLabel] was written to avoid, one
  /// size down. The old chrome keeps [railLabel] until UI-D-09 deletes it.
  /// Tracking comes down with the size: at [railLabel]'s 0.6 the longest
  /// caption still overruns its tile by a letter.
  TextStyle get railCaption => railLabel.copyWith(fontSize: 8, letterSpacing: 0.3);

  /// A row in a dense list: the browser's folders, patterns and samples
  /// (UI-B-04). Smaller than [body] because the mockup's browser rows are
  /// 24px tall — at 13px the names would fill the row edge to edge and the
  /// list would lose the rhythm that makes it scannable.
  TextStyle get listRow =>
      TextStyle(fontFamily: uiFamily, fontSize: 11, fontWeight: FontWeight.w400, color: textSecondary);

  /// The selected row: same size, more weight, full-strength ink. Weight
  /// rather than size, so selection never reflows the list.
  TextStyle get listRowSelected => listRow.copyWith(fontWeight: FontWeight.w700, color: textPrimary);

  /// The dim mono trailing a list row: a count (`12`, `4×`) or a kind tag
  /// (`piano roll`).
  TextStyle get listRowMeta => TextStyle(
    fontFamily: numericFamily,
    fontSize: 9,
    fontWeight: FontWeight.w400,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: textMuted,
  );

  /// A mixer strip's track name (UI-B-09). Small on purpose: a strip is 42px
  /// wide, and the name has to survive in it without truncating `Drums Bus`.
  TextStyle get stripName => TextStyle(
    fontFamily: uiFamily,
    fontSize: 8,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    // Archivo's condensed width axis, the same trick [labelDense] uses: at the
    // normal width `Drums Bus` overruns a 42px strip by a letter, and a track
    // whose name you cannot read is a track you cannot mix.
    fontVariations: const <FontVariation>[FontVariation('wdth', 87)],
    color: textSecondary,
  );

  /// The strip's bottom line: `→ Drums`, `0.0 dB`. Mono, because a column of
  /// them has to line up down the mixer.
  TextStyle get stripRoute => TextStyle(
    fontFamily: numericFamily,
    fontSize: 7,
    fontWeight: FontWeight.w400,
    // MartianMono runs wide even for a mono; narrowed so `→ Drums` fits the
    // strip it belongs to.
    fontVariations: const <FontVariation>[FontVariation('wdth', 75)],
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: textMuted,
  );

  /// A channel lane's name, and the instrument caption under it (UI-B-05).
  /// Two sizes and two colours in a 46px lane: the name is what you scan for,
  /// the type is what you check once.
  TextStyle get rackName =>
      TextStyle(fontFamily: uiFamily, fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary);

  TextStyle get rackCaption =>
      TextStyle(fontFamily: uiFamily, fontSize: 10, fontWeight: FontWeight.w400, color: textMuted);

  /// A playlist clip's name and the duration under it (UI-B-08). Both take
  /// the dark ink roles rather than a text colour: they sit on a bright
  /// identity fill, not on a surface.
  TextStyle get clipName => TextStyle(fontFamily: uiFamily, fontSize: 12, fontWeight: FontWeight.w600, color: clipInk);

  TextStyle get clipDuration => TextStyle(
    fontFamily: numericFamily,
    fontSize: 9,
    fontWeight: FontWeight.w500,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: clipInkMuted,
  );

  /// Tag labels (PAT, AUD, AUTO).
  TextStyle get tag =>
      TextStyle(fontFamily: uiFamily, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: textPrimary);

  /// Menu bar items.
  TextStyle get menu => TextStyle(fontFamily: uiFamily, fontSize: 12, fontWeight: FontWeight.w400, color: textMuted);

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
  TextStyle get readoutValue => numeric.copyWith(fontSize: 21, letterSpacing: -0.5, height: 1.15);

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
  TextStyle get breadcrumb =>
      TextStyle(fontFamily: uiFamily, fontSize: 12, fontWeight: FontWeight.w500, color: textPrimary);

  /// Knob labels and values.
  TextStyle get knobLabel =>
      TextStyle(fontFamily: uiFamily, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: textMuted);

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

  TextStyle get knobValue =>
      TextStyle(fontFamily: numericFamily, fontSize: 11, fontWeight: FontWeight.w600, color: textPrimary);

  /// Dialog and modal titles.
  TextStyle get dialogTitle =>
      TextStyle(fontFamily: uiFamily, fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary);

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
  TextStyle get numericLarge => numeric.copyWith(fontSize: 15, letterSpacing: -0.5);
  TextStyle get numericSmall => numeric.copyWith(fontSize: 11, color: textMuted);

  /// An empty state's headline (UI-B-11 §3). The largest UI type in the app —
  /// an empty screen has one job, and this is where it says it.
  TextStyle get emptyHeading => TextStyle(
    fontFamily: uiFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: textPrimary,
  );

  /// The prose under it: bigger than [body] and generously leaded, because it
  /// is the one block of running text a user actually reads rather than scans.
  /// Bold runs inside it take [proseStrong].
  TextStyle get prose =>
      TextStyle(fontFamily: uiFamily, fontSize: 14, fontWeight: FontWeight.w400, height: 1.55, color: textSecondary);

  TextStyle get proseStrong => prose.copyWith(fontWeight: FontWeight.w700, color: textPrimary);

  /// A popover or overlay row (UI-B-11 §6) and the dim shortcut trailing it.
  TextStyle get menuRow =>
      TextStyle(fontFamily: uiFamily, fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary);

  TextStyle get menuRowActive => menuRow.copyWith(fontWeight: FontWeight.w600, color: textPrimary);

  /// A floating window's title, and the dim `· Drums Bus selected` beside it.
  TextStyle get windowTitle =>
      TextStyle(fontFamily: uiFamily, fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary);

  TextStyle get windowSubtitle =>
      TextStyle(fontFamily: uiFamily, fontSize: 12, fontWeight: FontWeight.w400, color: textMuted);

  /// [microCaps] with the tracking a right-aligned column header needs to read
  /// as a header rather than as a value (`WHAT IT CAN DO TO YOUR PROJECT`).
  TextStyle get microCapsWide => microCaps.copyWith(letterSpacing: 1.4);

  /// An extension's name in the list, and the dim meta line under it. The meta
  /// mixes prose and mono (`by @luma · v1.2.0 · bound to ⇧⌘H`) — it renders as
  /// mono throughout so the version numbers down the column line up.
  TextStyle get extName =>
      TextStyle(fontFamily: uiFamily, fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary);

  TextStyle get extMeta => TextStyle(
    fontFamily: numericFamily,
    fontSize: 9,
    fontWeight: FontWeight.w400,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    color: textMuted,
  );

  /// The detail panel's title — one step up from [extName], because it names
  /// the thing the whole lower half of the screen is describing.
  TextStyle get extDetailName =>
      TextStyle(fontFamily: uiFamily, fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary);

  /// The `GROOVE FETCHER CRASHED — CONTAINED & DISABLED` line, and the
  /// `CRASHED` tag on the row it refers to.
  TextStyle get dangerCaps =>
      const TextStyle(fontFamily: uiFamily, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6);
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

  /// The same tokens with a different size scale, for a subtree that has to
  /// resize itself to what it was given.
  ///
  /// Republishing the theme is how one measurement reaches every widget in that
  /// subtree at once — the alternative is passing a size down through each
  /// layer and hoping the hit-test layer got the same number as the painter.
  OneBeatTokens withSize(SizeTokens value) => OneBeatTokens(
    brightness: brightness,
    color: color,
    type: type,
    spacing: spacing,
    radius: radius,
    border: border,
    size: value,
    motion: motion,
  );

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
    final OneBeatTheme? theme = context.dependOnInheritedWidgetOfExactType<OneBeatTheme>();
    assert(theme != null, 'No OneBeatTheme found. Wrap the app in OneBeatTheme.');
    return theme!.tokens;
  }

  @override
  bool updateShouldNotify(OneBeatTheme oldWidget) => oldWidget.tokens != tokens;
}
