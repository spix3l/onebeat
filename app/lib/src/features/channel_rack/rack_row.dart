// ObRackRow — one channel lane of the rack (UI-B-05).
//
// The 919×46 strip of `components/channel-row.png`, left to right: power,
// identity chip, name block, sixteen step cells grouped four-by-four, volume
// and pan knobs, route chip. Every landmark in it comes from a token, so the
// lane's rhythm is one file's decision rather than sixteen call sites'.
//
// Presentational only: the row is handed a vm and reports taps. Drag-painting
// steps and the right-click velocity gesture are UI-D-02.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/knob.dart';

/// One step cell.
@immutable
class StepVm {
  const StepVm({required this.on, this.velocity = 1});

  final bool on;

  /// 0..1. Modulates the lit cell's fill, so a quiet step reads as quiet
  /// without a second control to look at.
  final double velocity;

/// A step that is off; `const StepVm.off()` reads better in a fixture than
/// `StepVm(on: false)` sixteen times.
  const StepVm.off() : this(on: false);
}

/// One note in a channel's piano-roll preview (UI-C-02). Pitch and time are
/// plain integers so the rack row needs no engine types.
@immutable
class RackPreviewNoteVm {
  const RackPreviewNoteVm({
    required this.startTick,
    required this.lengthTicks,
    required this.midiNote,
  });

  final int startTick;
  final int lengthTicks;
  final int midiNote;
}

@immutable
class RackRowVm {
  const RackRowVm({
    required this.name,
    required this.type,
    required this.color,
    required this.steps,
    required this.vol,
    required this.pan,
    required this.route,
    this.powered = true,
    this.selected = false,
    this.previewNotes,
  });

  final String name;

  /// The instrument caption under the name (`Sampler`, `Reese CLAP`).
  final String type;

  /// Identity colour, resolved by the caller from `ColorTokens.channelColors`.
  final Color color;

  final List<StepVm> steps;

  /// 0..1 knob positions.
  final double vol;
  final double pan;

  /// The mixer destination, already formatted (`→ D1`).
  final String route;

  final bool powered;
  final bool selected;

  /// When non-null the row is a melody and shows a mini piano roll instead of
  /// the step grid.
  final List<RackPreviewNoteVm>? previewNotes;
}

class ObRackRow extends StatelessWidget {
  const ObRackRow({
    required this.vm,
    this.playingStep,
    this.onTap,
    this.onSecondaryTapDown,
    this.onPower,
    this.onStepTap,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.onVol,
    this.onPan,
    this.onRouteTap,
    super.key,
  });

  final RackRowVm vm;

  /// The step column the transport is on, zero-based; null draws no ring.
  /// Passed per row rather than held here so every lane agrees about it.
  final int? playingStep;

  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onPower;
  final ValueChanged<int>? onStepTap;
  final void Function(PointerDownEvent event, int stepIndex)?
      onPointerDownStep;
  final void Function(PointerMoveEvent event, int stepIndex)? onPointerMoveStep;
  final ValueChanged<double>? onVol;
  final ValueChanged<double>? onPan;
  final VoidCallback? onRouteTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        height: tokens.size.rackLaneHeight,
        decoration: BoxDecoration(
          // The selected lane is washed with the accent rather than filled:
          // sixteen saturated cells already live on it, and a solid selection
          // would drown them.
          color: vm.selected ? color.accentWash : color.none,
          border: Border(
            bottom: BorderSide(
              color: color.line,
              width: tokens.border.hairline,
            ),
            left: BorderSide(
              color: vm.selected ? color.accentBright : color.none,
              width: tokens.size.rackSelectedEdgeWidth,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(width: tokens.spacing.md),
            _PowerButton(on: vm.powered, onTap: onPower),
            SizedBox(width: tokens.spacing.sm),
            Container(
              width: tokens.size.rackColorChipSize,
              height: tokens.size.rackColorChipSize,
              decoration: BoxDecoration(
                color: vm.color,
                borderRadius: tokens.radius.controlBorder,
              ),
            ),
            SizedBox(width: tokens.spacing.md),
            SizedBox(
              width: tokens.size.rackNameWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    vm.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.rackName,
                  ),
                  Text(
                    vm.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.rackCaption,
                  ),
                ],
              ),
            ),
            if (vm.previewNotes != null)
              RackPianoPreview(
                notes: vm.previewNotes!,
                color: vm.color,
                stepCount: vm.steps.length,
              )
            else
              ObStepGrid(
                steps: vm.steps,
                playingStep: playingStep,
                onStepTap: onStepTap,
                onPointerDownStep: onPointerDownStep,
                onPointerMoveStep: onPointerMoveStep,
              ),
            SizedBox(width: tokens.spacing.md),
            ObKnob(value: vm.vol, onChanged: onVol),
            SizedBox(width: tokens.spacing.sm),
            ObKnob(value: vm.pan, onChanged: onPan),
            SizedBox(width: tokens.spacing.sm),
            _RouteChip(label: vm.route, onTap: onRouteTap),
            SizedBox(width: tokens.spacing.md),
          ],
        ),
      ),
    );
  }
}

/// The sixteen cells, grouped four-by-four.
///
/// Public so the column-caption strip can lay its numbers out against the
/// same widths — both read the gap rule off [SizeTokens], so neither can
/// drift out of step with the other.
class ObStepGrid extends StatelessWidget {
  const ObStepGrid({
    required this.steps,
    this.playingStep,
    this.onStepTap,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.groupSize = 4,
    super.key,
  });

  final List<StepVm> steps;
  final int? playingStep;
  final ValueChanged<int>? onStepTap;
  final void Function(PointerDownEvent event, int stepIndex)?
      onPointerDownStep;
  final void Function(PointerMoveEvent event, int stepIndex)? onPointerMoveStep;

  /// Cells per visual group. Four in every mockup; a parameter because a
  /// triplet grid is the same widget with a different number.
  final int groupSize;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool painting =
        onPointerDownStep != null || onPointerMoveStep != null;
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < steps.length; i++) {
      if (i > 0) {
        cells.add(
          SizedBox(
            width:
                i % groupSize == 0
                    ? tokens.size.rackStepGroupGap
                    : tokens.size.rackStepGap,
          ),
        );
      }
      cells.add(
        _StepCell(
          step: steps[i],
          playing: playingStep == i,
          // A binding that paints from pointer events must not also run the
          // ordinary tap toggle, or one click would add and remove the step.
          onTap: painting || onStepTap == null
              ? null
              : () => onStepTap!(i),
        ),
      );
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onPointerDownStep == null
          ? null
          : (PointerDownEvent event) {
              final int? step = _stepAt(event.localPosition, tokens.size);
              if (step != null) onPointerDownStep!(event, step);
            },
      onPointerMove: onPointerMoveStep == null
          ? null
          : (PointerMoveEvent event) {
              final int? step = _stepAt(event.localPosition, tokens.size);
              if (step != null) onPointerMoveStep!(event, step);
            },
      child: Row(
        children: <Widget>[
          for (final Widget cell in cells) cell,
        ],
      ),
    );
  }

  int? _stepAt(Offset position, SizeTokens size) {
    if (position.dy < 0 || position.dy > size.rackStepCell) return null;
    double left = 0;
    for (int index = 0; index < steps.length; index++) {
      final double right = left + size.rackStepCell;
      if (position.dx >= left && position.dx < right) return index;
      left = right;
      if (index < steps.length - 1) {
        left += index % groupSize == groupSize - 1
            ? size.rackStepGroupGap
            : size.rackStepGap;
      }
    }
    return null;
  }
}

/// The compact piano-roll preview a melody channel shows in place of its step
/// grid: the same notes as the piano roll, scaled into one strip.
class RackPianoPreview extends StatelessWidget {
  const RackPianoPreview({
    required this.notes,
    required this.color,
    this.stepCount = 16,
    super.key,
  });

  final List<RackPreviewNoteVm> notes;
  final Color color;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: _rackGridWidth(tokens.size, stepCount),
      height: tokens.size.rackStepCell,
      child: CustomPaint(
        painter: _RackPianoPreviewPainter(
          notes: notes,
          color: color,
          noteRadius: tokens.radius.xs,
        ),
      ),
    );
  }
}

/// The width of the step grid for [count] steps, so the preview and the grid it
/// replaces occupy identical space.
double _rackGridWidth(SizeTokens size, int count) {
  double width = 0;
  for (int i = 0; i < count; i++) {
    if (i > 0) {
      width += i % 4 == 0 ? size.rackStepGroupGap : size.rackStepGap;
    }
    width += size.rackStepCell;
  }
  return width;
}

class _RackPianoPreviewPainter extends CustomPainter {
  _RackPianoPreviewPainter({
    required this.notes,
    required this.color,
    required this.noteRadius,
  });

  final List<RackPreviewNoteVm> notes;
  final Color color;
  final Radius noteRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) return;
    int low = 1 << 30;
    int high = -(1 << 30);
    int end = 1;
    for (final RackPreviewNoteVm note in notes) {
      if (note.midiNote < low) low = note.midiNote;
      if (note.midiNote > high) high = note.midiNote;
      final int noteEnd = note.startTick + note.lengthTicks;
      if (noteEnd > end) end = noteEnd;
    }
    final int pitchSpan = (high - low) + 1;
    final double rowHeight = size.height / pitchSpan;
    final Paint paint = Paint()..color = color;

    for (final RackPreviewNoteVm note in notes) {
      final double x = (note.startTick / end) * size.width;
      final double width = (note.lengthTicks / end) * size.width;
      final double y = (high - note.midiNote) * rowHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            y + rowHeight * 0.15,
            width < 2 ? 2 : width,
            rowHeight * 0.7,
          ),
          noteRadius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RackPianoPreviewPainter oldDelegate) =>
      oldDelegate.notes != notes || oldDelegate.color != color;
}

class _StepCell extends StatelessWidget {
  const _StepCell({required this.step, required this.playing, this.onTap});

  final StepVm step;
  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double side = tokens.size.rackStepCell;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: step.on ? null : color.surfaceDeep,
            gradient:
                step.on
                    ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: color.stepGradient(step.velocity),
                    )
                    : null,
            borderRadius: BorderRadius.all(tokens.radius.lg),
            border: Border.all(
              // The playing column outlines every cell in it, lit or not —
              // that is what makes it read as a column rather than as a
              // brighter step.
              color:
                  playing
                      ? color.textSecondary
                      : (step.on ? color.accentBright : color.surfaceWell),
              width:
                  playing ? tokens.border.emphasis : tokens.border.hairline,
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular power well. Lit is [ColorTokens.danger] on purpose: a power
/// indicator is red on every piece of hardware a musician owns.
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.on, this.onTap});

  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double side = tokens.size.rackPowerSize;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: color.surfaceWell,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: CustomPaint(
            painter: _PowerGlyphPainter(
              color: on ? color.danger : color.textMuted,
              stroke: tokens.border.glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerGlyphPainter extends CustomPainter {
  _PowerGlyphPainter({required this.color, required this.stroke});

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
    // A ring broken at the top, with the stem through the break.
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(w / 2, h * 0.54),
        radius: w * 0.26,
      ),
      -math.pi / 2 + _arcGap,
      math.pi * 2 - _arcGap * 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(w / 2, h * 0.2), Offset(w / 2, h * 0.5), paint);
  }

  @override
  bool shouldRepaint(_PowerGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// Half the break in the power glyph's ring, in radians. Named so the gap
/// stays symmetric about the stem.
const double _arcGap = 0.9;

/// The mono destination chip at the lane's right edge.
class _RouteChip extends StatefulWidget {
  const _RouteChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_RouteChip> createState() => _RouteChipState();
}

class _RouteChipState extends State<_RouteChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: tokens.size.rackRouteChipWidth,
          height: tokens.size.tagHeight,
          decoration: BoxDecoration(
            color: _hover ? color.surfaceWell : color.surfaceRaised,
            borderRadius: BorderRadius.all(tokens.radius.md),
            border: Border.all(
              color: color.line,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            maxLines: 1,
            style: tokens.type.numericSmall,
          ),
        ),
      ),
    );
  }
}
