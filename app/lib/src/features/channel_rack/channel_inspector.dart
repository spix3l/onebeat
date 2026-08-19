// ObChannelInspector — the strip under the rack (UI-B-06).
//
// Everything about the selected channel on one 120px line, left to right:
// what it is, how loud and where, whether it is heard, where it goes, and a
// keyboard to try it.
//
// Presentational only. Nothing here plays a note, opens a plug-in window or
// reorders a chain; it reports the intent and UI-D-02 wires it.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/dropdown.dart';
import '../../ui_kit/fx_chip.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/knob.dart';
import '../../ui_kit/toggle_chip.dart';
import '../../ui_kit/tooltip.dart';

/// One entry in the FX chain.
@immutable
class FxVm {
  const FxVm({required this.name, required this.color, this.active = false});

  final String name;

  /// The entry's identity dot — a channel colour, resolved by the caller.
  final Color color;

  /// The entry whose editor is open.
  final bool active;
}

@immutable
class ChannelInspectorVm {
  const ChannelInspectorVm({
    required this.name,
    required this.subtitle,
    required this.color,
    this.waveform = const <double>[],
    required this.vol,
    required this.volText,
    required this.pan,
    required this.panText,
    this.fx = const <FxVm>[],
    required this.route,
    this.routeOptions = const <String>[],
    this.muted = false,
    this.soloed = false,
    this.hostsPlugin = false,
    this.hostsSampler = false,
    this.gridLabel = '1/16',
  });

  final String name;

  /// `EP · channel 5` — what it is and where it lives, in one dim line.
  final String subtitle;

  final Color color;

  /// True when the channel runs a hosted plug-in rather than a sample or an
  /// empty slot — the only channels that have a plug-in window to open.
  final bool hostsPlugin;

  /// True when the channel uses OneBeat's built-in sampler editor.
  final bool hostsSampler;

  /// Normalised 0..1 envelope samples. Drawn mirrored about the centre line;
  /// deterministic, so the same vm always paints the same preview.
  final List<double> waveform;

  final double vol;

  /// The value under the knob, already formatted (`78`).
  final String volText;

  final double pan;

  /// `· C` — the mockup writes centre as a dot and a letter, not as `0`.
  final String panText;

  final List<FxVm> fx;

  /// The destination, by name.
  final String route;

  /// Available mixer destinations. Empty keeps the inspector's route chip for
  /// callers that only want to open the mixer.
  final List<String> routeOptions;

  final bool muted;
  final bool soloed;

  /// The divisor this channel's steps sit on (`1/16`). Per channel, not per
  /// pattern: a hat lane can run at 1/32 under a 1/16 kick. It lives here
  /// rather than on the lane because it is a setting you visit, not a control
  /// you reach for while writing a rhythm.
  final String gridLabel;
}

class ObChannelInspector extends StatelessWidget {
  const ObChannelInspector({
    required this.vm,
    this.onVol,
    this.onPan,
    this.onMute,
    this.onSolo,
    this.onOpenPlugin,
    this.onOpenSampler,
    this.onFxTap,
    this.onAddFx,
    this.onRouteTap,
    this.onRouteSelected,
    this.onKeyPress,
    this.onGrid,
    super.key,
  });

  final ChannelInspectorVm vm;
  final ValueChanged<double>? onVol;
  final ValueChanged<double>? onPan;
  final VoidCallback? onMute;
  final VoidCallback? onSolo;

  /// Opens the selected channel's plug-in window. Only wired for channels
  /// that host a plug-in ([ChannelInspectorVm.hostsPlugin]).
  final VoidCallback? onOpenPlugin;
  final VoidCallback? onOpenSampler;

  /// Fired with the index of the tapped chain entry.
  final ValueChanged<int>? onFxTap;
  final VoidCallback? onAddFx;
  final VoidCallback? onRouteTap;

  /// Assigns the selected channel to a mixer destination by its display name.
  final ValueChanged<String>? onRouteSelected;

  /// Fired with a MIDI note number when a key is pressed.
  final ValueChanged<int>? onKeyPress;

  /// Fired with the new divisor label for the selected channel.
  final ValueChanged<String>? onGrid;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.inspectorHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xl),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: color.lineStrong, width: tokens.border.hairline)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 1180;
          final Widget identity = Expanded(
            child: Row(
              children: <Widget>[
                _IdentityTile(color: vm.color),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(vm.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tokens.type.title),
                      SizedBox(height: tokens.spacing.xxs),
                      Text(vm.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tokens.type.label),
                    ],
                  ),
                ),
                if ((vm.hostsPlugin && onOpenPlugin != null) || (vm.hostsSampler && onOpenSampler != null)) ...<Widget>[
                  SizedBox(width: tokens.spacing.md),
                  ObTooltip(
                    message: vm.hostsSampler ? 'Open sampler' : 'Open plugin window',
                    child: ObButton(
                      label: vm.hostsSampler ? 'Open sampler' : 'Open plugin',
                      icon: vm.hostsSampler ? ObKitGlyphKind.waveform : ObKitGlyphKind.keyboard,
                      tone: ObButtonTone.secondary,
                      onTap: vm.hostsSampler ? onOpenSampler : onOpenPlugin,
                    ),
                  ),
                ],
              ],
            ),
          );

          final Widget controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (onGrid != null) ...<Widget>[
                ObTooltip(
                  message: 'Step grid for this channel',
                  child: ObDropdown(
                    label: 'Grid',
                    value: vm.gridLabel,
                    items: const <String>['1/8', '1/16', '1/32'],
                    width: tokens.size.inspectorGridFieldWidth,
                    onSelected: onGrid,
                  ),
                ),
                SizedBox(width: tokens.spacing.lg),
              ],
              _KnobReadout(value: vm.vol, valueText: vm.volText, label: 'VOL', onChanged: onVol),
              SizedBox(width: tokens.spacing.lg),
              _KnobReadout(value: vm.pan, valueText: vm.panText, label: 'PAN', onChanged: onPan),
              SizedBox(width: tokens.spacing.lg),
              ObTooltip(
                message: 'Mute channel',
                child: _ToggleStack(tone: ObToggleTone.mute, on: vm.muted, onTap: onMute),
              ),
              SizedBox(width: tokens.spacing.sm),
              ObTooltip(
                message: 'Solo channel',
                child: _ToggleStack(tone: ObToggleTone.solo, on: vm.soloed, onTap: onSolo),
              ),
              SizedBox(width: tokens.spacing.xl),
              _RouteArrow(color: color.textMuted, stroke: tokens.border.glyph),
              SizedBox(width: tokens.spacing.sm),
              if (vm.routeOptions.isNotEmpty && onRouteSelected != null)
                ObDropdown(
                  label: 'Route',
                  value: vm.route,
                  items: vm.routeOptions,
                  width: tokens.size.inspectorGridFieldWidth,
                  onSelected: onRouteSelected,
                )
              else
                ObFxChip(label: vm.route, dotColor: color.none, mono: true, onTap: onRouteTap),
            ],
          );

          if (compact) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(children: <Widget>[identity]),
                SizedBox(height: tokens.spacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    controls,
                    SizedBox(width: tokens.spacing.lg),
                    MiniKeyboard(onKeyPress: onKeyPress),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: <Widget>[
              identity,
              SizedBox(width: tokens.spacing.lg),
              controls,
              SizedBox(width: tokens.spacing.lg),
              MiniKeyboard(onKeyPress: onKeyPress),
            ],
          );
        },
      ),
    );
  }
}

/// The 48px identity tile: the channel's colour, with a note on it.
class _IdentityTile extends StatelessWidget {
  const _IdentityTile({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double side = tokens.size.inspectorTileSize;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.all(tokens.radius.xl)),
      child: CustomPaint(painter: _NoteGlyphPainter(color: tokens.color.textPrimary, stroke: tokens.border.emphasis)),
    );
  }
}

/// A knob over its value and its caption. The value is above the caption
/// because the number is what changes; the caption only says what it means.
class _KnobReadout extends StatelessWidget {
  const _KnobReadout({required this.value, required this.valueText, required this.label, this.onChanged});

  final double value;
  final String valueText;
  final String label;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ObKnob(value: value, onChanged: onChanged),
        SizedBox(height: tokens.spacing.xs),
        Text(valueText, maxLines: 1, style: tokens.type.knobValue),
        Text(label, maxLines: 1, style: tokens.type.microCaps),
      ],
    );
  }
}

/// An M or S chip over its state lamp. The chip is the control; the lamp is
/// the answer to "is it on right now" from across the room.
class _ToggleStack extends StatelessWidget {
  const _ToggleStack({required this.tone, required this.on, this.onTap});

  final ObToggleTone tone;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final Color lit = tone == ObToggleTone.mute ? color.danger : color.warning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ObToggleChip(tone: tone, on: on, onTap: onTap),
        SizedBox(height: tokens.spacing.xs),
        Container(
          width: tokens.size.inspectorLampSize,
          height: tokens.size.inspectorLampSize,
          decoration: BoxDecoration(
            color: color.surfaceWell,
            borderRadius: BorderRadius.all(tokens.radius.sm),
            border: Border.all(color: color.lineStrong, width: tokens.border.hairline),
          ),
          alignment: Alignment.center,
          child: Container(
            width: tokens.size.inspectorLampDotSize,
            height: tokens.size.inspectorLampDotSize,
            decoration: BoxDecoration(color: on ? lit : color.textMuted, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}

class _RouteArrow extends StatelessWidget {
  const _RouteArrow({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final double side = OneBeatTheme.of(context).size.iconSize;
    return SizedBox(
      width: side,
      height: side,
      child: CustomPaint(painter: _ArrowPainter(color: color, stroke: stroke)),
    );
  }
}

/// The mirrored bar preview of a channel's sound.
///
/// A bar chart rather than a filled envelope: bars survive being 44px tall in
/// a strip, and they make it obvious the preview is a summary rather than the
/// actual sample.
class WaveformPainter extends CustomPainter {
  WaveformPainter({required this.samples, required this.color, required this.barPitch, required this.barWidth});

  final List<double> samples;
  final Color color;
  final double barPitch;
  final double barWidth;

  // Allocated once: `paint` runs on every frame the strip is on screen and
  // must not allocate.
  late final Paint _bar =
      Paint()
        ..color = color
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      return;
    }
    final int bars = (size.width / barPitch).floor();
    final double mid = size.height / 2;
    for (int i = 0; i < bars; i++) {
      // Sample position mapped across the preview, so the same envelope fills
      // whatever width the strip gives it.
      final double t = bars == 1 ? 0 : i / (bars - 1);
      final double amplitude = samples[(t * (samples.length - 1)).round()].clamp(0.0, 1.0);
      final double half = mid * amplitude;
      final double x = i * barPitch + barPitch / 2;
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), _bar);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.barPitch != barPitch ||
      oldDelegate.barWidth != barWidth ||
      !identical(oldDelegate.samples, samples);
}

/// Two octaves of keys, tapped to audition.
///
/// The x→note map is the widget's own arithmetic rather than a stack of
/// gesture detectors: black keys overlap their neighbours, and a widget per
/// key would need the same arithmetic to decide who won anyway.
class MiniKeyboard extends StatelessWidget {
  const MiniKeyboard({this.baseNote = 60, this.octaves = 2, this.onKeyPress, super.key});

  /// MIDI note of the leftmost white key. 60 is middle C.
  final int baseNote;
  final int octaves;
  final ValueChanged<int>? onKeyPress;

  /// Semitone offsets of the white keys within an octave.
  static const List<int> whiteSemitones = <int>[0, 2, 4, 5, 7, 9, 11];

  /// Semitone offsets of the black keys, paired with the index of the white
  /// key they sit after.
  static const List<(int, int)> blackSemitones = <(int, int)>[(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)];

  int get _whiteCount => whiteSemitones.length * octaves;

  /// The MIDI note under [dx] in a keyboard [width] wide. Black keys win
  /// where they overlap, which is what a finger expects.
  int noteAt(double dx, double width, double height) {
    final double whiteWidth = width / _whiteCount;
    final double blackWidth = whiteWidth * _blackWidthRatio;
    for (int octave = 0; octave < octaves; octave++) {
      for (final (int semitone, int after) in blackSemitones) {
        final double centre = (octave * whiteSemitones.length + after + 1) * whiteWidth;
        if ((dx - centre).abs() <= blackWidth / 2) {
          return baseNote + octave * 12 + semitone;
        }
      }
    }
    final int index = (dx / whiteWidth).floor().clamp(0, _whiteCount - 1);
    return baseNote + (index ~/ whiteSemitones.length) * 12 + whiteSemitones[index % whiteSemitones.length];
  }

  static const double _blackWidthRatio = 0.62;
  static const double _blackHeightRatio = 0.6;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double width = tokens.size.inspectorKeyboardWidth;
    final double height = tokens.size.inspectorKeyboardHeight;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          onKeyPress == null
              ? null
              : (TapDownDetails details) => onKeyPress!(noteAt(details.localPosition.dx, width, height)),
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _KeyboardPainter(
            whiteCount: _whiteCount,
            blacks: <int>[
              for (int octave = 0; octave < octaves; octave++)
                for (final (int _, int after) in blackSemitones) octave * whiteSemitones.length + after,
            ],
            white: tokens.color.textPrimary,
            black: tokens.color.surfaceSunken,
            line: tokens.color.lineStrong,
            stroke: tokens.border.hairline,
            radius: tokens.radius.sm,
            blackWidthRatio: _blackWidthRatio,
            blackHeightRatio: _blackHeightRatio,
          ),
        ),
      ),
    );
  }
}

class _KeyboardPainter extends CustomPainter {
  _KeyboardPainter({
    required this.whiteCount,
    required this.blacks,
    required this.white,
    required this.black,
    required this.line,
    required this.stroke,
    required this.radius,
    required this.blackWidthRatio,
    required this.blackHeightRatio,
  });

  final int whiteCount;

  /// Indices of the white keys each black key sits after.
  final List<int> blacks;
  final Color white;
  final Color black;
  final Color line;
  final double stroke;
  final Radius radius;
  final double blackWidthRatio;
  final double blackHeightRatio;

  late final Paint _whitePaint = Paint()..color = white;
  late final Paint _blackPaint = Paint()..color = black;
  late final Paint _linePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = line;

  @override
  void paint(Canvas canvas, Size size) {
    final double whiteWidth = size.width / whiteCount;
    final RRect body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), radius);
    canvas.drawRRect(body, _whitePaint);
    for (int i = 1; i < whiteCount; i++) {
      final double x = i * whiteWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _linePaint);
    }
    final double blackWidth = whiteWidth * blackWidthRatio;
    for (final int after in blacks) {
      final double centre = (after + 1) * whiteWidth;
      canvas.drawRect(
        Rect.fromLTWH(centre - blackWidth / 2, 0, blackWidth, size.height * blackHeightRatio),
        _blackPaint,
      );
    }
    canvas.drawRRect(body, _linePaint);
  }

  @override
  bool shouldRepaint(_KeyboardPainter oldDelegate) =>
      oldDelegate.whiteCount != whiteCount ||
      oldDelegate.white != white ||
      oldDelegate.black != black ||
      oldDelegate.line != line;
}

class _NoteGlyphPainter extends CustomPainter {
  _NoteGlyphPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;
    canvas.drawLine(Offset(w * 0.40, h * 0.62), Offset(w * 0.40, h * 0.33), paint);
    canvas.drawLine(Offset(w * 0.66, h * 0.56), Offset(w * 0.66, h * 0.28), paint);
    canvas.drawLine(Offset(w * 0.40, h * 0.33), Offset(w * 0.66, h * 0.28), paint);
    canvas.drawCircle(Offset(w * 0.34, h * 0.64), w * 0.07, paint);
    canvas.drawCircle(Offset(w * 0.60, h * 0.58), w * 0.07, paint);
  }

  @override
  bool shouldRepaint(_NoteGlyphPainter oldDelegate) => oldDelegate.color != color;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;
    canvas.drawLine(Offset(w * 0.16, h * 0.5), Offset(w * 0.84, h * 0.5), paint);
    canvas.drawLine(Offset(w * 0.6, h * 0.3), Offset(w * 0.84, h * 0.5), paint);
    canvas.drawLine(Offset(w * 0.6, h * 0.7), Offset(w * 0.84, h * 0.5), paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
}
