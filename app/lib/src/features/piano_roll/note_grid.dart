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
const int prTicksPerBeat = 240;

/// What part of the roll is on screen, and at what scale.
@immutable
class PrViewport {
  const PrViewport({
    required this.ticksPerPx,
    required this.rowHeight,
    required this.firstVisibleTick,
    required this.topMidiNote,
    this.beatsPerBar = 4,
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
  }) => PrViewport(
    ticksPerPx: ticksPerPx ?? this.ticksPerPx,
    rowHeight: rowHeight ?? this.rowHeight,
    firstVisibleTick: firstVisibleTick ?? this.firstVisibleTick,
    topMidiNote: topMidiNote ?? this.topMidiNote,
    beatsPerBar: beatsPerBar,
  );

  @override
  bool operator ==(Object other) =>
      other is PrViewport &&
      other.ticksPerPx == ticksPerPx &&
      other.rowHeight == rowHeight &&
      other.firstVisibleTick == firstVisibleTick &&
      other.topMidiNote == topMidiNote &&
      other.beatsPerBar == beatsPerBar;

  @override
  int get hashCode => Object.hash(
    ticksPerPx,
    rowHeight,
    firstVisibleTick,
    topMidiNote,
    beatsPerBar,
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
  });

  final List<PrNoteVm> notes;

  /// The other channels' notes, drawn behind: context without competing for
  /// attention.
  final List<PrNoteVm> ghostNotes;

  final PrViewport viewport;
  final int? playheadTick;
  final Set<int> selected;
  final Rect? marqueeRect;
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
      if (note.midiNote == midi &&
          tick >= note.startTick &&
          tick < note.startTick + note.lengthTicks) {
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
      onTapUp:
          onAddNote == null && onSelectNote == null ? null : _handleTap,
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
  late final Paint _rowLine =
      Paint()
        ..color = color.gridLine
        ..strokeWidth = lineWidth;
  late final Paint _beatLine =
      Paint()
        ..color = color.gridLine
        ..strokeWidth = lineWidth;
  late final Paint _barLine =
      Paint()
        ..color = color.gridLineStrong
        ..strokeWidth = lineWidth;
  late final Paint _ghost = Paint()..color = color.noteGhost;
  late final Paint _note = Paint()..color = color.noteFill;
  late final Paint _selected = Paint()..color = color.noteSelected;
  late final Paint _marqueeFill = Paint()..color = color.marqueeFill;
  late final Paint _marqueeStroke =
      Paint()
        ..color = color.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth;
  late final Paint _playhead =
      Paint()
        ..color = color.playhead
        ..strokeWidth = playheadWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final PrViewport view = vm.viewport;

    // Rows.
    final int rows = view.rowsIn(size.height);
    for (int i = 0; i < rows; i++) {
      final int midi = view.topMidiNote - i;
      final int pitchClass = ((midi % 12) + 12) % 12;
      final double top = i * view.rowHeight;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, view.rowHeight),
        _liftedPitchClasses.contains(pitchClass) ? _band : _bandDark,
      );
      canvas.drawLine(Offset(0, top), Offset(size.width, top), _rowLine);
    }

    // Beat and bar lines. Walking beats rather than pixels keeps the lines on
    // the music when the zoom is not a whole number of pixels per beat.
    final int firstBeat = vm.viewport.firstVisibleTick ~/ prTicksPerBeat;
    final int lastTick = view.tickAt(size.width);
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
    for (final PrNoteVm note in vm.notes) {
      _paintNote(
        canvas,
        view,
        note,
        vm.selected.contains(note.id) ? _selected : _note,
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
    final double top =
        view.yOf(note.midiNote) + (view.rowHeight - noteHeight) / 2;
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
      !identical(oldDelegate.vm, vm) ||
      oldDelegate.color != color ||
      oldDelegate.noteHeight != noteHeight;
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

  late final Paint _rule =
      Paint()
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
  bool shouldRepaint(_BarRulerPainter oldDelegate) =>
      oldDelegate.viewport != viewport || oldDelegate.line != line;
}
