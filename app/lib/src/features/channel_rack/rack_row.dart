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
  const RackPreviewNoteVm({required this.startTick, required this.lengthTicks, required this.midiNote});

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
    this.hostsPlugin = false,
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

  /// Whether the lane hosts a plug-in (as opposed to the built-in sample
  /// player or an empty lane). Only these lanes get a double-tap that opens the
  /// plug-in window — and only these lanes pay for the double-tap recognizer
  /// delaying their single-click select by the double-tap window.
  final bool hostsPlugin;
}

class ObRackRow extends StatelessWidget {
  const ObRackRow({
    required this.vm,
    this.playingStep,
    this.playingTick,
    this.onTap,
    this.onPointerDown,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.onPower,
    this.onStepTap,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.onVol,
    this.onPan,
    this.onRouteTap,
    this.reorderIndex,
    this.gridWidth,
    this.gridStepCount,
    this.stepTicks,
    super.key,
  });

  final RackRowVm vm;

  /// The width every lane's grid occupies, whatever it holds.
  ///
  /// Lanes do not agree about how many steps they have — a lane at a finer
  /// divisor covers the same bar in more of them — but they must agree about
  /// how much of the window that bar takes, or a fine lane runs off the right
  /// edge of a window sized for the coarse ones. The rack passes one width and
  /// each lane fits its own cells into it. Null sizes the lane to its own
  /// steps, which is what a lane rendered on its own wants.
  final double? gridWidth;

  /// The rack's shared time base: how many columns the pattern's own grid has,
  /// and how many ticks each of them covers. A piano-roll lane has no columns
  /// of its own to count, so this is what tells it where bar one ends — the
  /// same answer the step lanes and the header are giving. Null leaves a lane
  /// drawn on its own to fall back on its notes' extent.
  final int? gridStepCount;
  final int? stepTicks;

  /// This lane's position in the rack, when the rack is reorderable. Non-null
  /// makes the name block a drag handle. The handle is the *name*, not the
  /// whole lane: the lane's step cells are a paint surface, and a drag that
  /// started there would reorder channels instead of drawing steps.
  final int? reorderIndex;

  /// The step column the transport is on, zero-based; null draws no ring.
  /// Passed per row rather than held here so every lane agrees about it.
  final int? playingStep;

  /// The loop-wrapped transport tick, for rows that draw a piano-roll preview
  /// instead of a step grid (where a step index has no meaning). Null hides the
  /// read head.
  final int? playingTick;
  final VoidCallback? onTap;
  final void Function(PointerDownEvent event)? onPointerDown;

  /// Double-click opens the lane's plug-in window. Wired only for lanes that
  /// host a plug-in — see [RackRowVm.hostsPlugin].
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onPower;
  final ValueChanged<int>? onStepTap;
  final void Function(PointerDownEvent event, int stepIndex)? onPointerDownStep;
  final void Function(PointerMoveEvent event, int stepIndex)? onPointerMoveStep;
  final ValueChanged<double>? onVol;
  final ValueChanged<double>? onPan;
  final VoidCallback? onRouteTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double width = gridWidth ?? rackGridWidth(tokens.size, vm.steps.length);
    final int columns = gridStepCount ?? vm.steps.length;

    return _RackGestureLayer(
      onPointerDown: onPointerDown,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        height: tokens.size.rackLaneHeight,
        decoration: BoxDecoration(
          // The selected lane is washed with the accent rather than filled:
          // sixteen saturated cells already live on it, and a solid selection
          // would drown them.
          color: vm.selected ? color.accentWash : color.none,
          border: Border(
            bottom: BorderSide(color: color.line, width: tokens.border.hairline),
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
              decoration: BoxDecoration(color: vm.color, borderRadius: tokens.radius.controlBorder),
            ),
            SizedBox(width: tokens.spacing.md),
            _NameBlock(vm: vm, reorderIndex: reorderIndex),
            if (vm.previewNotes != null)
              RackPianoPreview(
                notes: vm.previewNotes!,
                color: vm.color,
                width: width,
                stepCount: columns,
                spanTicks: stepTicks == null ? null : columns * stepTicks!,
                playingTick: playingTick,
              )
            else
              ObStepGrid(
                steps: vm.steps,
                width: width,
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

class _RackGestureLayer extends StatefulWidget {
  const _RackGestureLayer({
    required this.child,
    this.onPointerDown,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
  });

  final Widget child;
  final void Function(PointerDownEvent event)? onPointerDown;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<_RackGestureLayer> createState() => _RackGestureLayerState();
}

class _RackGestureLayerState extends State<_RackGestureLayer> {
  Duration? _lastTapTime;
  Offset? _lastTapPosition;
  late Duration _doubleTapWindow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _doubleTapWindow = OneBeatTheme.of(context).motion.doubleTapWindow;
  }

  void _onPointerUp(PointerUpEvent event) {
    final Duration? lastTime = _lastTapTime;
    final Offset? lastPosition = _lastTapPosition;
    final bool isDouble =
        lastTime != null &&
        event.timeStamp - lastTime < _doubleTapWindow &&
        lastPosition != null &&
        (event.position - lastPosition).distance < 24;
    if (isDouble) {
      _lastTapTime = null;
      _lastTapPosition = null;
      widget.onDoubleTap?.call();
    } else {
      _lastTapTime = event.timeStamp;
      _lastTapPosition = event.position;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _lastTapTime = null;
    _lastTapPosition = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: widget.onPointerDown,
    onPointerUp: _onPointerUp,
    onPointerCancel: _onPointerCancel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      child: widget.child,
    ),
  );
}

/// The lane's name and instrument caption, and — when the rack is reorderable
/// — the grip the lane is dragged by.
class _NameBlock extends StatelessWidget {
  const _NameBlock({required this.vm, this.reorderIndex});

  final RackRowVm vm;
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Widget block = SizedBox(
      width: tokens.size.rackNameWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(vm.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tokens.type.rackName),
          Text(vm.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: tokens.type.rackCaption),
        ],
      ),
    );

    final int? index = reorderIndex;
    if (index == null) return block;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: ReorderableDragStartListener(index: index, child: block),
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
    this.width,
    this.playingStep,
    this.onStepTap,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.groupSize = kRackGroupSize,
    super.key,
  });

  final List<StepVm> steps;

  /// The width the cells must fit into, whatever their number. Null draws them
  /// at the token pitch and takes whatever width that comes to.
  final double? width;

  final int? playingStep;
  final ValueChanged<int>? onStepTap;
  final void Function(PointerDownEvent event, int stepIndex)? onPointerDownStep;
  final void Function(PointerMoveEvent event, int stepIndex)? onPointerMoveStep;

  /// Cells per visual group. Four in every mockup; a parameter because a
  /// triplet grid is the same widget with a different number.
  final int groupSize;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens outer = OneBeatTheme.of(context);
    // A lane at a finer divisor holds more steps than the rack was measured
    // for; it shrinks its own cells to the shared width rather than running
    // off the edge of it. Republished so the cells, the hit-test below and
    // anything the cells build all read the same pitch.
    final double? target = width;
    final OneBeatTokens tokens =
        target == null ? outer : outer.withSize(fitRackStepsToWidth(outer.size, steps.length, target));
    final bool painting = onPointerDownStep != null || onPointerMoveStep != null;
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < steps.length; i++) {
      if (i > 0) {
        cells.add(SizedBox(width: i % groupSize == 0 ? tokens.size.rackStepGroupGap : tokens.size.rackStepGap));
      }
      cells.add(
        _StepCell(
          step: steps[i],
          playing: playingStep == i,
          // The band turns over every group, so a bar reads light-dark-light-
          // dark and the downbeat is always the lifted one.
          lifted: (i ~/ groupSize).isEven,
          // A binding that paints from pointer events must not also run the
          // ordinary tap toggle, or one click would add and remove the step.
          onTap: painting || onStepTap == null ? null : () => onStepTap!(i),
        ),
      );
    }
    return OneBeatTheme(
      tokens: tokens,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown:
            onPointerDownStep == null
                ? null
                : (PointerDownEvent event) {
                  final int? step = _stepAt(event.localPosition, tokens.size);
                  if (step != null) onPointerDownStep!(event, step);
                },
        onPointerMove:
            onPointerMoveStep == null
                ? null
                : (PointerMoveEvent event) {
                  final int? step = _stepAt(event.localPosition, tokens.size);
                  if (step != null) onPointerMoveStep!(event, step);
                },
        child: SizedBox(width: target, child: Row(children: <Widget>[for (final Widget cell in cells) cell])),
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
        left += index % groupSize == groupSize - 1 ? size.rackStepGroupGap : size.rackStepGap;
      }
    }
    return null;
  }
}

/// Cells per visual group, everywhere in the rack: the step grid's banding,
/// the header's numbers and the preview's columns all break on the beat.
const int kRackGroupSize = 4;

/// The compact piano-roll preview a melody channel shows in place of its step
/// grid: the same notes as the piano roll, laid out on the rack's own columns.
///
/// The time base is [spanTicks] — the stretch of the pattern the lane's grid
/// covers — and not the notes' own extent. Normalising to the last note was
/// what made the preview a lane unto itself: a riff that stopped on beat two
/// filled the strip, so it disagreed with the step lanes beside it about where
/// bar one ended, and its read head crossed the lane at a different speed from
/// the playing column ring. Both now come from the same arithmetic the grid
/// uses.
class RackPianoPreview extends StatelessWidget {
  const RackPianoPreview({
    required this.notes,
    required this.color,
    this.width,
    this.stepCount = 16,
    this.spanTicks,
    this.playingTick,
    super.key,
  });

  final List<RackPreviewNoteVm> notes;
  final Color color;

  /// The shared grid width. The preview fits the rack's columns into whatever
  /// it is given, so it takes the width directly rather than a step count it
  /// would only convert — the count it used to take was the lane's own, which
  /// is how a fine lane came to paint a strip wider than the window.
  final double? width;

  /// The pattern's own column count: the same one the header numbers and the
  /// playing-column ring are counted in.
  final int stepCount;

  /// The ticks those columns span. Null falls back to the notes' own extent,
  /// which is all a lane rendered outside a rack — a fixture, a component
  /// gallery — can know.
  final int? spanTicks;

  /// The loop-wrapped transport tick, drawn as a read head over the notes.
  final int? playingTick;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int columns = stepCount > 0 ? stepCount : 16;
    final double target = width ?? rackGridWidth(tokens.size, columns);
    // The same fit the neighbouring step lanes make, so a note lands on the
    // column its step would have.
    final SizeTokens size = fitRackStepsToWidth(tokens.size, columns, target);
    return SizedBox(
      width: target,
      height: tokens.size.rackStepCell,
      child: CustomPaint(
        painter: _RackPianoPreviewPainter(
          notes: notes,
          color: color,
          noteRadius: tokens.radius.xs,
          columns: columns,
          spanTicks: spanTicks,
          size: size,
          playingTick: playingTick,
          playheadColor: tokens.color.playhead,
          playheadWidth: tokens.size.playheadWidth,
        ),
      ),
    );
  }
}

/// The width of the step grid for [count] steps, so the preview, the number
/// strip above it and the grid itself all occupy identical space.
double rackGridWidth(SizeTokens size, int count) {
  double width = 0;
  for (int i = 0; i < count; i++) {
    if (i > 0) {
      width += i % 4 == 0 ? size.rackStepGroupGap : size.rackStepGap;
    }
    width += size.rackStepCell;
  }
  return width;
}

/// The left edge of column [index] in a lane laid out with [size]: the cells
/// before it, plus the gap that precedes it — a plain one, or the wider group
/// gap on a beat break.
///
/// [rackGridWidth] measures whole lanes; this places a single column inside
/// one. Both the step grid and the piano-roll preview lay out through here, so
/// the two lane kinds cannot drift apart by a gap.
double rackColumnStart(SizeTokens size, int index) =>
    index * size.rackStepCell +
    (index ~/ kRackGroupSize) * size.rackStepGroupGap +
    (index - index ~/ kRackGroupSize) * size.rackStepGap;

/// Where [tick] falls on a lane of [columns] columns covering [spanTicks].
///
/// The gaps between cells are not time, so this maps through the columns
/// rather than across the raw width: a note lands on the column of the step
/// that plays it, not a gap's worth of pixels away from it. Ticks outside the
/// span clamp to the lane's ends.
double rackTickX(SizeTokens size, {required int columns, required int spanTicks, required num tick}) {
  if (columns <= 0 || spanTicks <= 0) return 0;
  final double column = (tick / spanTicks) * columns;
  if (column <= 0) return 0;
  if (column >= columns) return rackColumnStart(size, columns - 1) + size.rackStepCell;
  final int index = column.floor();
  return rackColumnStart(size, index) + (column - index) * size.rackStepCell;
}

/// The smallest step cell the rack will draw of its own accord.
///
/// Below this a cell stops being a target you can hit and starts being a
/// texture, and scrolling is the better answer.
const double _minRackStepCell = 16;

/// The smallest cell a lane will shrink to when it is *given* a width.
///
/// A lane at a fine divisor has no say in how wide the rack is — the rack is
/// sized for the pattern's own grid — so the alternative to a cell this small
/// is a lane that overflows the window. Below the hittable size it reads as a
/// density strip, which is honest: that lane is edited in the piano roll.
const double _minBoundStepCell = 2;

/// Step sizes that fit [stepCount] cells into [available], never larger than
/// the design's own.
///
/// A 32-step pattern at the full 30px pitch is wider than most windows, and the
/// horizontal scroll that answered it hid half the bar — you cannot write a
/// rhythm you have to scroll to see. So the grid gives up pitch before it gives
/// up being whole, down to [_minRackStepCell]; past that the scroll returns.
SizeTokens fitRackSteps(SizeTokens base, int stepCount, double available) =>
    _fitRackSteps(base, stepCount, available, _minRackStepCell) ?? _RackStepSizes(base, _minRackStepCell);

/// Step sizes that fit [stepCount] cells into exactly [width], however many
/// there are.
///
/// This is the promise a lane makes to the rack: whatever divisor it is on, its
/// cells occupy the width every other lane occupies. When even the smallest
/// banded cell will not fit, the gaps go — a lane that dense is a texture, and
/// a texture that fits beats a grid that overflows.
SizeTokens fitRackStepsToWidth(SizeTokens base, int stepCount, double width) {
  if (stepCount <= 0 || width <= 0) return base;
  return _fitRackSteps(base, stepCount, width, _minBoundStepCell) ?? _RackDenseStepSizes(width / stepCount);
}

/// The first whole-pixel cell size at or below the base that fits, or null when
/// none down to [floor] does.
///
/// A whole number of pixels per cell is what keeps the cells crisp and the gaps
/// even; solving for a fractional cell and rounding afterwards does neither.
SizeTokens? _fitRackSteps(SizeTokens base, int stepCount, double available, double floor) {
  if (stepCount <= 0 || available <= 0) return base;
  if (rackGridWidth(base, stepCount) <= available) return base;
  for (double cell = base.rackStepCell - 1; cell >= floor; cell--) {
    final SizeTokens candidate = _RackStepSizes(base, cell);
    if (rackGridWidth(candidate, stepCount) <= available) return candidate;
  }
  return null;
}

/// [SizeTokens] with the step grid rescaled — the gaps follow the cell, so the
/// beat grouping stays legible at every size.
class _RackStepSizes extends SizeTokens {
  const _RackStepSizes(this._base, this._cell);

  final SizeTokens _base;
  final double _cell;

  double get _scale => _cell / _base.rackStepCell;

  @override
  double get rackStepCell => _cell;

  @override
  double get rackStepGap {
    final double scaled = (_base.rackStepGap * _scale).floorToDouble();
    return scaled < 2 ? 2 : scaled;
  }

  @override
  double get rackStepGroupGap {
    final double scaled = (_base.rackStepGroupGap * _scale).floorToDouble();
    // Always visibly wider than the plain gap: the group break is the only
    // thing telling you where the beat is.
    final double floor = rackStepGap + 2;
    return scaled < floor ? floor : scaled;
  }
}

/// The last resort: cells packed edge to edge at whatever fraction of a pixel
/// the width allows. No gaps, so the arithmetic is exact and the lane cannot
/// overflow by a rounding error.
class _RackDenseStepSizes extends SizeTokens {
  const _RackDenseStepSizes(this._cell);

  final double _cell;

  @override
  double get rackStepCell => _cell;

  @override
  double get rackStepGap => 0;

  @override
  double get rackStepGroupGap => 0;
}

class _RackPianoPreviewPainter extends CustomPainter {
  _RackPianoPreviewPainter({
    required this.notes,
    required this.color,
    required this.noteRadius,
    required this.columns,
    required this.size,
    this.spanTicks,
    this.playingTick,
    this.playheadColor,
    this.playheadWidth = 1,
  });

  final List<RackPreviewNoteVm> notes;
  final Color color;
  final Radius noteRadius;

  /// The rack's columns, and the geometry they are drawn with — cell pitch and
  /// the two gaps — copied from the step grid so the two lane kinds cannot
  /// drift apart.
  final int columns;
  final SizeTokens size;

  final int? spanTicks;
  final int? playingTick;
  final Color? playheadColor;
  final double playheadWidth;

  double _x(num tick, int span) => rackTickX(size, columns: columns, spanTicks: span, tick: tick);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // No cells: a melody lane is a piano roll, and drawing the step grid under
    // it makes the lane look like a grid you can click. The columns are still
    // what the notes are placed on — they are just not drawn.
    if (notes.isEmpty) return;
    int low = 1 << 30;
    int high = -(1 << 30);
    int extent = 1;
    for (final RackPreviewNoteVm note in notes) {
      if (note.midiNote < low) low = note.midiNote;
      if (note.midiNote > high) high = note.midiNote;
      final int noteEnd = note.startTick + note.lengthTicks;
      if (noteEnd > extent) extent = noteEnd;
    }
    // The pattern's span when the rack gave one; the notes' own only when the
    // lane is drawn outside a rack and there is nothing else to go on.
    final int span = (spanTicks ?? 0) > 0 ? spanTicks! : extent;
    final int pitchSpan = (high - low) + 1;
    final double rowHeight = canvasSize.height / pitchSpan;
    final Paint paint = Paint()..color = color;

    for (final RackPreviewNoteVm note in notes) {
      // A note past the end of the pattern is not played, and drawing it piled
      // up against the right edge would claim it is.
      if (note.startTick >= span) continue;
      final double x = _x(note.startTick, span);
      final double end = _x(note.startTick + note.lengthTicks, span);
      final double width = end - x;
      final double y = (high - note.midiNote) * rowHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + rowHeight * 0.15, width < 2 ? 2 : width, rowHeight * 0.7),
          noteRadius,
        ),
        paint,
      );
    }

    final int? tick = playingTick;
    final Color? head = playheadColor;
    if (tick != null && head != null) {
      final double x = _x(tick, span);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, canvasSize.height),
        Paint()
          ..color = head
          ..strokeWidth = playheadWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_RackPianoPreviewPainter oldDelegate) =>
      oldDelegate.notes != notes ||
      oldDelegate.color != color ||
      oldDelegate.columns != columns ||
      oldDelegate.size.rackStepCell != size.rackStepCell ||
      oldDelegate.size.rackStepGap != size.rackStepGap ||
      oldDelegate.size.rackStepGroupGap != size.rackStepGroupGap ||
      oldDelegate.spanTicks != spanTicks ||
      oldDelegate.playingTick != playingTick ||
      oldDelegate.playheadColor != playheadColor;
}

class _StepCell extends StatelessWidget {
  const _StepCell({required this.step, required this.playing, required this.lifted, this.onTap});

  final StepVm step;
  final bool playing;

  /// Which of the two beat bands this cell sits on. Only an unlit cell shows
  /// it — a lit one is already the loudest thing in the lane.
  final bool lifted;

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
            color: step.on ? null : (lifted ? color.stepRestLifted : color.stepRest),
            gradient:
                step.on
                    ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: color.stepGradient(step.velocity),
                    )
                    : null,
            // The corner follows the cell. r8 on the design's 30px square is a
            // rounded square; the same 8 on a shrunk cell is a circle, and a
            // grid of circles stops reading as a row of steps.
            borderRadius: BorderRadius.circular(math.min(tokens.radius.lg.x, side * 0.27)),
            border: Border.all(
              // The playing column outlines every cell in it, lit or not —
              // that is what makes it read as a column rather than as a
              // brighter step.
              color: playing ? color.textSecondary : (step.on ? color.accentBright : color.surfaceWell),
              width: playing ? tokens.border.emphasis : tokens.border.hairline,
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
            border: Border.all(color: color.lineStrong, width: tokens.border.hairline),
          ),
          child: CustomPaint(
            painter: _PowerGlyphPainter(color: on ? color.danger : color.textMuted, stroke: tokens.border.glyph),
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
      Rect.fromCircle(center: Offset(w / 2, h * 0.54), radius: w * 0.26),
      -math.pi / 2 + _arcGap,
      math.pi * 2 - _arcGap * 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(w / 2, h * 0.2), Offset(w / 2, h * 0.5), paint);
  }

  @override
  bool shouldRepaint(_PowerGlyphPainter oldDelegate) => oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// Half the break in the power glyph's ring, in radians. Named so the gap
/// stays symmetric about the stem.
const double _arcGap = 0.9;

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
            border: Border.all(color: color.line, width: tokens.border.hairline),
          ),
          alignment: Alignment.center,
          child: Text(widget.label, maxLines: 1, style: tokens.type.numericSmall),
        ),
      ),
    );
  }
}
