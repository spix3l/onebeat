// PrVelocityLane — one stem per note, under the roll (UI-B-07).
//
// The lane shares the grid's x mapping, so a stem sits under its note by
// construction. Its left gutter is the key column's width, which is what keeps
// the two lanes locked together when the roll scrolls.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/tooltip.dart';
import 'note_grid.dart';

/// Which per-note value the stems show and edit.
///
/// [velocity] is the only one the model stores today. [pan] is declared here
/// rather than left out because the lane's shape — bipolar, centred — is a real
/// design decision and the control reads better when the user can see what is
/// coming; it renders unavailable rather than silently showing velocity under
/// another name, which is what it used to do.
enum PrLaneKind {
  velocity,
  pan;

  String get label => switch (this) {
    PrLaneKind.velocity => 'VEL',
    PrLaneKind.pan => 'PAN',
  };

  String get description => switch (this) {
    PrLaneKind.velocity => 'Note velocity — drag a stem to set it',
    PrLaneKind.pan => 'Note pan — not stored per note yet',
  };

  /// Whether the lane can be drawn from real data and edited.
  bool get available => this == PrLaneKind.velocity;

  static PrLaneKind fromLabel(String label) => PrLaneKind.values.firstWhere(
    (PrLaneKind kind) => kind.label == label,
    orElse: () => PrLaneKind.velocity,
  );
}

class PrVelocityLane extends StatelessWidget {
  const PrVelocityLane({
    required this.vm,
    this.lane = 'VEL',
    this.lanes = const <String>['VEL', 'PAN'],
    this.onLaneChanged,
    super.key,
  });

  final PianoRollVm vm;

  /// Which per-note value the stems show.
  final String lane;
  final List<String> lanes;
  final ValueChanged<String>? onLaneChanged;

  PrLaneKind get kind => PrLaneKind.fromLabel(lane);

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
              child: ObTooltip(
                message: kind.description,
                child: _LaneChip(
                  label: lane,
                  onTap:
                      onLaneChanged == null
                          ? null
                          : () => onLaneChanged!(_next()),
                ),
              ),
            ),
          ),
          Expanded(
            child: CustomPaint(
              painter: PrVelocityPainter(
                vm: vm,
                kind: kind,
                color: tokens.color,
                stemWidth: tokens.size.prVelocityStemWidth,
                lineWidth: tokens.border.hairline,
                unavailableStyle: tokens.type.label.copyWith(
                  color: tokens.color.textMuted,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  /// Cycling rather than opening a menu: two lanes, one control, and a popover
  /// can swap in later without the lane changing shape.
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
    this.kind = PrLaneKind.velocity,
    this.unavailableStyle = const TextStyle(),
  });

  final PianoRollVm vm;
  final PrLaneKind kind;
  final ColorTokens color;
  final double stemWidth;
  final double lineWidth;
  final TextStyle unavailableStyle;

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
  late final Paint _stemSounding =
      Paint()
        ..color = color.accentBright
        ..strokeWidth = stemWidth
        ..strokeCap = StrokeCap.round;
  late final Paint _rule =
      Paint()
        ..color = color.gridLine
        ..strokeWidth = lineWidth;
  late final Paint _bed = Paint()..color = color.surfaceSunken;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);

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

    if (!kind.available) {
      _text
        ..text = TextSpan(text: kind.description, style: unavailableStyle)
        ..layout();
      _text.paint(
        canvas,
        Offset(
          (size.width - _text.width) / 2,
          (size.height - _text.height) / 2,
        ),
      );
      return;
    }

    final int? playing = vm.playheadTick;
    final double inset = stemWidth / 2;
    for (final PrNoteVm note in vm.notes) {
      final double x = vm.viewport.xOf(note.startTick) + inset;
      if (x < 0 || x > size.width) {
        continue;
      }
      final double top =
          size.height - (size.height - inset) * note.velocity.clamp(0.0, 1.0);
      final bool sounding =
          playing != null &&
          playing >= note.startTick &&
          playing < note.startTick + note.lengthTicks;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, size.height - inset),
        vm.selected.contains(note.id)
            ? _stemSelected
            : (sounding ? _stemSounding : _stem),
      );
    }
  }

  @override
  bool shouldRepaint(PrVelocityPainter oldDelegate) =>
      !identical(oldDelegate.vm, vm) ||
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.stemWidth != stemWidth;
}
