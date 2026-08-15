// The piano roll's canvas and the coordinate system the whole editor shares
// (UI-B-07).
//
// Every lane — keys, grid, velocity — positions itself through [PrViewport],
// so they align by construction rather than by three widgets agreeing to use
// the same arithmetic. A zoom is a change to one field of one object.
//
// The painter follows the rules the old `lib/src/ui/piano_roll.dart` earned:
// paint objects are built once outside `paint`, and `shouldRepaint` compares
// the vm rather than returning true.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// Ticks per quarter-note beat. The roll's whole tick vocabulary is derived
/// from this, so "what is a 16th" is arithmetic rather than a second
/// constant.
///
/// This is 960 because that is what the model and the ABI are (`ob_note.start`
/// is "ticks, pattern-relative, 960 PPQN"). It used to be 240, which meant the
/// painter drew a beat line every 16th and the ruler numbered every
/// quarter-note as a bar.
const int prTicksPerBeat = 960;

/// What part of the roll is on screen, and at what scale.
@immutable
class PrViewport {
  const PrViewport({
    required this.ticksPerPx,
    required this.rowHeight,
    required this.firstVisibleTick,
    required this.topMidiNote,
    this.beatsPerBar = 4,
    this.subdivisionTicks = 0,
  });

  /// Horizontal zoom. Larger means more music per pixel.
  final double ticksPerPx;

  /// Vertical zoom: the height of one semitone row.
  final double rowHeight;

  /// The tick at the canvas's left edge.
  final int firstVisibleTick;

  /// The MIDI note of the top row.
  final int topMidiNote;

  final int beatsPerBar;

  /// The active snap division, in ticks. Drawn as the faintest grid line, so
  /// the canvas shows the resolution an edit will land on. 0 draws no
  /// subdivision — which is what "Snap: Off" looks like.
  final int subdivisionTicks;

  int get ticksPerBar => prTicksPerBeat * beatsPerBar;

  /// Canvas x of [tick].
  double xOf(int tick) => (tick - firstVisibleTick) / ticksPerPx;

  /// The tick at canvas [x]. Inverse of [xOf] to within rounding.
  int tickAt(double x) => firstVisibleTick + (x * ticksPerPx).round();

  /// Canvas y of the top edge of [midiNote]'s row.
  double yOf(int midiNote) => (topMidiNote - midiNote) * rowHeight;

  /// The MIDI note whose row contains canvas [y]. Inverse of [yOf].
  int noteAt(double y) => topMidiNote - (y / rowHeight).floor();

  /// How many whole rows fit in [height].
  int rowsIn(double height) => (height / rowHeight).ceil();

  PrViewport copyWith({
    double? ticksPerPx,
    double? rowHeight,
    int? firstVisibleTick,
    int? topMidiNote,
    int? subdivisionTicks,
  }) => PrViewport(
    ticksPerPx: ticksPerPx ?? this.ticksPerPx,
    rowHeight: rowHeight ?? this.rowHeight,
    firstVisibleTick: firstVisibleTick ?? this.firstVisibleTick,
    topMidiNote: topMidiNote ?? this.topMidiNote,
    beatsPerBar: beatsPerBar,
    subdivisionTicks: subdivisionTicks ?? this.subdivisionTicks,
  );

  @override
  bool operator ==(Object other) =>
      other is PrViewport &&
      other.ticksPerPx == ticksPerPx &&
      other.rowHeight == rowHeight &&
      other.firstVisibleTick == firstVisibleTick &&
      other.topMidiNote == topMidiNote &&
      other.beatsPerBar == beatsPerBar &&
      other.subdivisionTicks == subdivisionTicks;

  @override
  int get hashCode => Object.hash(
    ticksPerPx,
    rowHeight,
    firstVisibleTick,
    topMidiNote,
    beatsPerBar,
    subdivisionTicks,
  );
}

@immutable
class PrNoteVm {
  const PrNoteVm({
    required this.id,
    required this.startTick,
    required this.lengthTicks,
    required this.midiNote,
    this.velocity = 0.8,
  });

  final int id;
  final int startTick;
  final int lengthTicks;
  final int midiNote;

  /// 0..1, drawn as the stem height in the velocity lane.
  final double velocity;
}

@immutable
class PianoRollVm {
  const PianoRollVm({
    required this.notes,
    required this.viewport,
    this.ghostNotes = const <PrNoteVm>[],
    this.playheadTick,
    this.selected = const <int>{},
    this.marqueeRect,
    this.activeKeys = const <int>{},
    this.scaleIntervals = const <int>[],
    this.scaleRoot = 0,
  });

  final List<PrNoteVm> notes;

  /// The other channels' notes, drawn behind: context without competing for
  /// attention.
  final List<PrNoteVm> ghostNotes;

  final PrViewport viewport;
  final int? playheadTick;
  final Set<int> selected;
  final Rect? marqueeRect;

  /// MIDI keys sounding right now — every key the playhead is currently inside
  /// a note of. Their rows light up, which is what makes an audible note
  /// findable on a dense canvas.
  final Set<int> activeKeys;

  /// Semitone offsets of the selected scale, from [scaleRoot]. Empty, or a full
  /// twelve, means chromatic: the banding falls back to the keyboard, because
  /// shading every row identically would say nothing.
  final List<int> scaleIntervals;
  final int scaleRoot;

  /// Whether [midiNote] belongs to the selected scale. Always true when the
  /// scale is chromatic.
  bool inScale(int midiNote) {
    if (scaleIntervals.isEmpty || scaleIntervals.length >= 12) return true;
    return scaleIntervals.contains(((midiNote - scaleRoot) % 12 + 12) % 12);
  }

  /// True when the scale actually distinguishes rows from one another.
  bool get hasScale => scaleIntervals.isNotEmpty && scaleIntervals.length < 12;
}

/// The roll canvas: row banding, grid lines, ghosts, notes, playhead.
class PrNoteGrid extends StatelessWidget {
  const PrNoteGrid({
    required this.vm,
    this.onAddNote,
    this.onSelectNote,
    super.key,
  });

  final PianoRollVm vm;

  /// Fired with (tick, midiNote) when empty canvas is tapped.
  final void Function(int tick, int midiNote)? onAddNote;
  final ValueChanged<int>? onSelectNote;

  /// The note at canvas [local], or null for empty canvas.
  PrNoteVm? noteAt(Offset local) {
    final int tick = vm.viewport.tickAt(local.dx);
    final int midi = vm.viewport.noteAt(local.dy);
    for (final PrNoteVm note in vm.notes) {
      if (note.midiNote == midi && tick >= note.startTick && tick < note.startTick + note.lengthTicks) {
        return note;
      }
    }
    return null;
  }

  void _handleTap(TapUpDetails details) {
    final PrNoteVm? hit = noteAt(details.localPosition);
    if (hit != null) {
      onSelectNote?.call(hit.id);
      return;
    }
    onAddNote?.call(
      vm.viewport.tickAt(details.localPosition.dx),
      vm.viewport.noteAt(details.localPosition.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onAddNote == null && onSelectNote == null ? null : _handleTap,
      // The roll sits against the key column, and a note that starts before the
      // visible area has a negative x. Without a clip the painter would draw it
      // straight over the keys — the one thing a piano roll must never do. The
      // same clip keeps the painter's last (partial) row from spilling into the
      // velocity lane below.
      child: ClipRect(
        child: CustomPaint(
          painter: PrGridPainter(
            vm: vm,
            color: tokens.color,
            noteHeight: tokens.size.prNoteHeight,
            noteRadius: tokens.radius.xs,
            lineWidth: tokens.border.hairline,
            playheadWidth: tokens.size.playheadWidth,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class PrGridPainter extends CustomPainter {
  PrGridPainter({
    required this.vm,
    required this.color,
    required this.noteHeight,
    required this.noteRadius,
    required this.lineWidth,
    required this.playheadWidth,
  });

  final PianoRollVm vm;
  final ColorTokens color;
  final double noteHeight;
  final Radius noteRadius;
  final double lineWidth;
  final double playheadWidth;

  /// Pitch classes drawn on the lifted band.
  ///
  /// These are the white keys that have a black key below them — D, E, G, A,
  /// B. C and F sit straight on their neighbour, and the mockup keeps them on
  /// the darker band so each white-on-white pair reads as a pair. The banding
  /// follows the keyboard rather than the selected scale, which is what the
  /// mockup draws: its scale is C minor, and the shading does not track it.
  static const Set<int> _liftedPitchClasses = <int>{2, 4, 7, 9, 11};

  late final Paint _band = Paint()..color = color.rollCanvas;
  late final Paint _bandDark = Paint()..color = color.surfaceDeep;

  /// The two scale bands. In-scale rows are *lifted* above the canvas and
  /// out-of-scale rows sit below it, so "in the scale" reads as the brighter
  /// surface rather than as a colour the user has to learn.
  late final Paint _bandInScale = Paint()..color = color.rowShadeInScale;
  late final Paint _bandOutOfScale = Paint()..color = color.rowShade;

  /// The row under a sounding note. A wash rather than a fill: it has to be
  /// legible behind the note that caused it.
  late final Paint _activeRow = Paint()..color = color.accentWash;

  late final Paint _rowLine = Paint()
    ..color = color.gridLine
    ..strokeWidth = lineWidth;

  /// The snap division, drawn fainter than a beat. This is the one line whose
  /// spacing changes with the Snap control, which is what makes that control
  /// legible before you draw anything.
  late final Paint _subdivisionLine = Paint()
    ..color = color.gridLineSubdivision
    ..strokeWidth = lineWidth;
  late final Paint _beatLine = Paint()
    ..color = color.gridLine
    ..strokeWidth = lineWidth;
  late final Paint _barLine = Paint()
    ..color = color.gridLineStrong
    ..strokeWidth = lineWidth;
  late final Paint _ghost = Paint()..color = color.noteGhost;
  late final Paint _note = Paint()..color = color.noteFill;
  late final Paint _selected = Paint()..color = color.noteSelected;

  /// A note the playhead is inside. Brighter than at rest but not the
  /// selection colour — "sounding" and "selected" are different facts and the
  /// user acts on them differently.
  late final Paint _sounding = Paint()..color = color.accentBright;
  late final Paint _marqueeFill = Paint()..color = color.marqueeFill;
  late final Paint _marqueeStroke = Paint()
    ..color = color.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = lineWidth;
  late final Paint _playhead = Paint()
    ..color = color.playhead
    ..strokeWidth = playheadWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final PrViewport view = vm.viewport;

    // Rows. When a scale is selected the banding follows *it*; otherwise it
    // follows the keyboard, because shading twelve of twelve rows the same
    // would be a control that changed nothing.
    final int rows = view.rowsIn(size.height);
    final bool byScale = vm.hasScale;
    for (int i = 0; i < rows; i++) {
      final int midi = view.topMidiNote - i;
      final int pitchClass = ((midi % 12) + 12) % 12;
      final double top = i * view.rowHeight;
      final Rect row = Rect.fromLTWH(0, top, size.width, view.rowHeight);
      final Paint band;
      if (byScale) {
        band = vm.inScale(midi) ? _bandInScale : _bandOutOfScale;
      } else {
        band = _liftedPitchClasses.contains(pitchClass) ? _band : _bandDark;
      }
      canvas.drawRect(row, band);
      if (vm.activeKeys.contains(midi)) {
        canvas.drawRect(row, _activeRow);
      }
      canvas.drawLine(Offset(0, top), Offset(size.width, top), _rowLine);
    }

    // Vertical rules, faintest first so a bar line always wins where two
    // coincide. Walking divisions rather than pixels keeps the lines on the
    // music when the zoom is not a whole number of pixels per beat.
    final int lastTick = view.tickAt(size.width);
    final int subdivision = view.subdivisionTicks;
    // Below roughly this spacing the subdivision stops being a grid and starts
    // being a texture, so it drops out rather than filling the canvas.
    if (subdivision > 0 && subdivision / view.ticksPerPx >= 4.0) {
      for (int tick = (view.firstVisibleTick ~/ subdivision) * subdivision; tick <= lastTick; tick += subdivision) {
        if (tick % prTicksPerBeat == 0) continue;
        final double x = view.xOf(tick);
        if (x < 0) continue;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), _subdivisionLine);
      }
    }

    final int firstBeat = view.firstVisibleTick ~/ prTicksPerBeat;
    for (int beat = firstBeat; ; beat++) {
      final int tick = beat * prTicksPerBeat;
      if (tick > lastTick) {
        break;
      }
      final double x = view.xOf(tick);
      if (x < 0) {
        continue;
      }
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        tick % view.ticksPerBar == 0 ? _barLine : _beatLine,
      );
    }

    for (final PrNoteVm ghost in vm.ghostNotes) {
      _paintNote(canvas, view, ghost, _ghost);
    }
    final int? playing = vm.playheadTick;
    for (final PrNoteVm note in vm.notes) {
      final bool sounding = playing != null && playing >= note.startTick && playing < note.startTick + note.lengthTicks;
      _paintNote(
        canvas,
        view,
        note,
        vm.selected.contains(note.id) ? _selected : (sounding ? _sounding : _note),
      );
    }

    final Rect? marquee = vm.marqueeRect;
    if (marquee != null) {
      canvas
        ..drawRect(marquee, _marqueeFill)
        ..drawRect(marquee, _marqueeStroke);
    }

    final int? playhead = vm.playheadTick;
    if (playhead != null) {
      final double x = view.xOf(playhead);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _playhead);
    }
  }

  void _paintNote(
    Canvas canvas,
    PrViewport view,
    PrNoteVm note,
    Paint paint,
  ) {
    final double top = view.yOf(note.midiNote) + (view.rowHeight - noteHeight) / 2;
    final double left = view.xOf(note.startTick);
    final double width = note.lengthTicks / view.ticksPerPx;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, noteHeight),
        noteRadius,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(PrGridPainter oldDelegate) =>
      !identical(oldDelegate.vm, vm) || oldDelegate.color != color || oldDelegate.noteHeight != noteHeight;
}

/// The bar numbers above the canvas, on the same x mapping as the grid.
class PrBarRuler extends StatelessWidget {
  const PrBarRuler({required this.viewport, super.key});

  final PrViewport viewport;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      height: tokens.size.prBarRulerHeight,
      child: CustomPaint(
        painter: _BarRulerPainter(
          viewport: viewport,
          line: tokens.color.gridLineStrong,
          lineWidth: tokens.border.hairline,
          style: tokens.type.numericSmall,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BarRulerPainter extends CustomPainter {
  _BarRulerPainter({
    required this.viewport,
    required this.line,
    required this.lineWidth,
    required this.style,
  });

  final PrViewport viewport;
  final Color line;
  final double lineWidth;
  final TextStyle style;

  late final Paint _rule = Paint()
    ..color = line
    ..strokeWidth = lineWidth;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Size size) {
    final int firstBar = viewport.firstVisibleTick ~/ viewport.ticksPerBar;
    final int lastTick = viewport.tickAt(size.width);
    for (int bar = firstBar; ; bar++) {
      final int tick = bar * viewport.ticksPerBar;
      if (tick > lastTick) {
        break;
      }
      final double x = viewport.xOf(tick);
      if (x < 0) {
        continue;
      }
      canvas.drawLine(Offset(x, size.height * 0.4), Offset(x, size.height), _rule);
      _text
        ..text = TextSpan(text: '${bar + 1}', style: style)
        ..layout();
      _text.paint(
        canvas,
        Offset(x + lineWidth * 4, size.height - _text.height - lineWidth * 2),
      );
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      _rule,
    );
  }

  @override
  bool shouldRepaint(_BarRulerPainter oldDelegate) => oldDelegate.viewport != viewport || oldDelegate.line != line;
}
