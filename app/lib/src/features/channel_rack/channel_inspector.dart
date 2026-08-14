// ObChannelInspector — the strip under the rack (UI-B-06).
//
// Everything about the selected channel on one 120px line, left to right:
// what it is, what it sounds like, how loud and where, whether it is heard,
// what is on it, where it goes, and a keyboard to try it. The order is the
// order a musician asks the questions in, which is why the waveform sits
// second and the routing sits last.
//
// Presentational only. Nothing here plays a note, opens a plug-in window or
// reorders a chain; it reports the intent and UI-D-02 wires it.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/fx_chip.dart';
import '../../ui_kit/knob.dart';
import '../../ui_kit/toggle_chip.dart';

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
    required this.waveform,
    required this.vol,
    required this.volText,
    required this.pan,
    required this.panText,
    required this.fx,
    required this.route,
    this.muted = false,
    this.soloed = false,
  });

  final String name;

  /// `EP · channel 5` — what it is and where it lives, in one dim line.
  final String subtitle;

  final Color color;

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

  /// `M1 · Music`: the destination, by name.
  final String route;

  final bool muted;
  final bool soloed;
}

class ObChannelInspector extends StatelessWidget {
  const ObChannelInspector({
    required this.vm,
    this.onVol,
    this.onPan,
    this.onMute,
    this.onSolo,
    this.onFxTap,
    this.onAddFx,
    this.onRouteTap,
    this.onKeyPress,
    super.key,
  });

  final ChannelInspectorVm vm;
  final ValueChanged<double>? onVol;
  final ValueChanged<double>? onPan;
  final VoidCallback? onMute;
  final VoidCallback? onSolo;

  /// Fired with the index of the tapped chain entry.
  final ValueChanged<int>? onFxTap;
  final VoidCallback? onAddFx;
  final VoidCallback? onRouteTap;

  /// Fired with a MIDI note number when a key is pressed.
  final ValueChanged<int>? onKeyPress;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.inspectorHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xl),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          _IdentityTile(color: vm.color),
          SizedBox(width: tokens.spacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(vm.name, maxLines: 1, style: tokens.type.title),
              SizedBox(height: tokens.spacing.xxs),
              Text(vm.subtitle, maxLines: 1, style: tokens.type.label),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: tokens.size.inspectorWaveWidth,
            height: tokens.size.inspectorWaveHeight,
            child: CustomPaint(
              painter: WaveformPainter(
                samples: vm.waveform,
                color: color.accent,
                barPitch: tokens.size.inspectorWaveBarPitch,
                barWidth: tokens.border.emphasis,
              ),
            ),
          ),
          const Spacer(),
          _KnobReadout(
            value: vm.vol,
            valueText: vm.volText,
            label: 'VOL',
            onChanged: onVol,
          ),
          SizedBox(width: tokens.spacing.lg),
          _KnobReadout(
            value: vm.pan,
            valueText: vm.panText,
            label: 'PAN',
            onChanged: onPan,
          ),
          SizedBox(width: tokens.spacing.lg),
          _ToggleStack(
            tone: ObToggleTone.mute,
            on: vm.muted,
            onTap: onMute,
          ),
          SizedBox(width: tokens.spacing.sm),
          _ToggleStack(
            tone: ObToggleTone.solo,
            on: vm.soloed,
            onTap: onSolo,
          ),
          SizedBox(width: tokens.spacing.xl),
          for (int i = 0; i < vm.fx.length; i++) ...<Widget>[
            ObFxChip(
              label: vm.fx[i].name,
              dotColor: vm.fx[i].color,
              active: vm.fx[i].active,
              onTap: onFxTap == null ? null : () => onFxTap!(i),
            ),
            SizedBox(width: tokens.spacing.sm),
          ],
          _AddFxTile(onTap: onAddFx),
          SizedBox(width: tokens.spacing.xl),
          _RouteArrow(color: color.textMuted, stroke: tokens.border.glyph),
          SizedBox(width: tokens.spacing.sm),
          ObFxChip(
            label: vm.route,
            dotColor: color.none,
            mono: true,
            onTap: onRouteTap,
          ),
          const Spacer(),
          MiniKeyboard(onKeyPress: onKeyPress),
        ],
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
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.all(tokens.radius.xl),
      ),
      child: CustomPaint(
        painter: _NoteGlyphPainter(
          color: tokens.color.textPrimary,
          stroke: tokens.border.emphasis,
        ),
      ),
    );
  }
}

/// A knob over its value and its caption. The value is above the caption
/// because the number is what changes; the caption only says what it means.
class _KnobReadout extends StatelessWidget {
  const _KnobReadout({
    required this.value,
    required this.valueText,
    required this.label,
    this.onChanged,
  });

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
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            width: tokens.size.inspectorLampDotSize,
            height: tokens.size.inspectorLampDotSize,
            decoration: BoxDecoration(
              color: on ? lit : color.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddFxTile extends StatelessWidget {
  const _AddFxTile({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          width: tokens.size.chipHeight,
          height: tokens.size.chipHeight,
          decoration: BoxDecoration(
            color: color.surfaceWell,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: CustomPaint(
            painter: _PlusPainter(
              color: color.textSecondary,
              stroke: tokens.border.glyph,
            ),
          ),
        ),
      ),
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
      child: CustomPaint(
        painter: _ArrowPainter(color: color, stroke: stroke),
      ),
    );
  }
}

/// The mirrored bar preview of a channel's sound.
///
/// A bar chart rather than a filled envelope: bars survive being 44px tall in
/// a strip, and they make it obvious the preview is a summary rather than the
/// actual sample.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.samples,
    required this.color,
    required this.barPitch,
    required this.barWidth,
  });

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
      final double amplitude =
          samples[(t * (samples.length - 1)).round()].clamp(0.0, 1.0);
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
  static const List<(int, int)> blackSemitones = <(int, int)>[
    (1, 0),
    (3, 1),
    (6, 3),
    (8, 4),
    (10, 5),
  ];

  int get _whiteCount => whiteSemitones.length * octaves;

  /// The MIDI note under [dx] in a keyboard [width] wide. Black keys win
  /// where they overlap, which is what a finger expects.
  int noteAt(double dx, double width, double height) {
    final double whiteWidth = width / _whiteCount;
    final double blackWidth = whiteWidth * _blackWidthRatio;
    for (int octave = 0; octave < octaves; octave++) {
      for (final (int semitone, int after) in blackSemitones) {
        final double centre =
            (octave * whiteSemitones.length + after + 1) * whiteWidth;
        if ((dx - centre).abs() <= blackWidth / 2) {
          return baseNote + octave * 12 + semitone;
        }
      }
    }
    final int index = (dx / whiteWidth).floor().clamp(0, _whiteCount - 1);
    return baseNote +
        (index ~/ whiteSemitones.length) * 12 +
        whiteSemitones[index % whiteSemitones.length];
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
              : (TapDownDetails details) => onKeyPress!(
                noteAt(details.localPosition.dx, width, height),
              ),
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _KeyboardPainter(
            whiteCount: _whiteCount,
            blacks: <int>[
              for (int octave = 0; octave < octaves; octave++)
                for (final (int _, int after) in blackSemitones)
                  octave * whiteSemitones.length + after,
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
    final RRect body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      radius,
    );
    canvas.drawRRect(body, _whitePaint);
    for (int i = 1; i < whiteCount; i++) {
      final double x = i * whiteWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _linePaint);
    }
    final double blackWidth = whiteWidth * blackWidthRatio;
    for (final int after in blacks) {
      final double centre = (after + 1) * whiteWidth;
      canvas.drawRect(
        Rect.fromLTWH(
          centre - blackWidth / 2,
          0,
          blackWidth,
          size.height * blackHeightRatio,
        ),
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
  bool shouldRepaint(_NoteGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PlusPainter extends CustomPainter {
  _PlusPainter({required this.color, required this.stroke});

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
    canvas.drawLine(Offset(w * 0.5, h * 0.3), Offset(w * 0.5, h * 0.7), paint);
    canvas.drawLine(Offset(w * 0.3, h * 0.5), Offset(w * 0.7, h * 0.5), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => oldDelegate.color != color;
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
