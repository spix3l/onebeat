// PrVelocityLane — one stem per note, under the roll (UI-B-07).
//
// The lane shares the grid's x mapping, so a stem sits under its note by
// construction. Its left gutter is the key column's width, which is what keeps
// the two lanes locked together when the roll scrolls.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'note_grid.dart';

class PrVelocityLane extends StatelessWidget {
  const PrVelocityLane({
    required this.vm,
    this.lane = 'VEL',
    this.lanes = const <String>['VEL', 'PAN', 'MOD'],
    this.onLaneChanged,
    super.key,
  });

  final PianoRollVm vm;

  /// Which per-note value the stems show.
  final String lane;
  final List<String> lanes;
  final ValueChanged<String>? onLaneChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      height: tokens.size.prVelocityLaneHeight,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: tokens.size.prKeyColumnWidth,
            child: Center(
              child: _LaneChip(
                label: lane,
                onTap:
                    onLaneChanged == null
                        ? null
                        : () => onLaneChanged!(_next()),
              ),
            ),
          ),
          Expanded(
            child: CustomPaint(
              painter: PrVelocityPainter(
                vm: vm,
                color: tokens.color,
                stemWidth: tokens.size.prVelocityStemWidth,
                lineWidth: tokens.border.hairline,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  /// Cycling rather than opening a menu: three lanes, one control, and Phase
  /// D can swap in a popover without the lane changing shape.
  String _next() {
    final int index = lanes.indexOf(lane);
    return lanes[(index + 1) % lanes.length];
  }
}

class _LaneChip extends StatelessWidget {
  const _LaneChip({required this.label, this.onTap});

  final String label;
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
          width: tokens.size.prVelocityChipWidth,
          height: tokens.size.microFieldHeight,
          decoration: BoxDecoration(
            color: color.surfaceWell,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: tokens.type.label.copyWith(color: color.textPrimary),
          ),
        ),
      ),
    );
  }
}

class PrVelocityPainter extends CustomPainter {
  PrVelocityPainter({
    required this.vm,
    required this.color,
    required this.stemWidth,
    required this.lineWidth,
  });

  final PianoRollVm vm;
  final ColorTokens color;
  final double stemWidth;
  final double lineWidth;

  late final Paint _stem =
      Paint()
        ..color = color.noteFill
        ..strokeWidth = stemWidth
        ..strokeCap = StrokeCap.round;
  late final Paint _stemSelected =
      Paint()
        ..color = color.noteSelected
        ..strokeWidth = stemWidth
        ..strokeCap = StrokeCap.round;
  late final Paint _rule =
      Paint()
        ..color = color.gridLine
        ..strokeWidth = lineWidth;
  late final Paint _bed = Paint()..color = color.surfaceSunken;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _bed);
    // A half-height rule: the eye reads "loud" and "quiet" against it without
    // a scale down the side.
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      _rule,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      _rule,
    );

    final double inset = stemWidth / 2;
    for (final PrNoteVm note in vm.notes) {
      final double x = vm.viewport.xOf(note.startTick) + inset;
      if (x < 0 || x > size.width) {
        continue;
      }
      final double top =
          size.height - (size.height - inset) * note.velocity.clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, size.height - inset),
        vm.selected.contains(note.id) ? _stemSelected : _stem,
      );
    }
  }

  @override
  bool shouldRepaint(PrVelocityPainter oldDelegate) =>
      !identical(oldDelegate.vm, vm) ||
      oldDelegate.color != color ||
      oldDelegate.stemWidth != stemWidth;
}
