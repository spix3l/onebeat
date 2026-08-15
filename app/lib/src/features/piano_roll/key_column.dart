// PrKeyColumn — the keyboard down the roll's left edge (UI-B-07).
//
// Its only job is to say which row is which note. It shares [PrViewport] with
// the grid, so a key and its row cannot drift apart: both are `yOf(midi)`.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'note_grid.dart';

class PrKeyColumn extends StatelessWidget {
  const PrKeyColumn({
    required this.viewport,
    this.onKeyPress,
    this.activeKeys = const <int>{},
    super.key,
  });

  final PrViewport viewport;
  final ValueChanged<int>? onKeyPress;

  /// The keys sounding right now. Drawn held-down, which is the keyboard's own
  /// vocabulary for it — no legend required.
  final Set<int> activeKeys;

  /// Semitone offsets that are black keys, from C.
  static const Set<int> blackPitchClasses = <int>{1, 3, 6, 8, 10};

  static bool isBlack(int midiNote) => blackPitchClasses.contains(((midiNote % 12) + 12) % 12);

  /// `C5` for MIDI 72 — the label the mockup prints on every C row.
  static String octaveLabel(int midiNote) => 'C${midiNote ~/ 12 - 1}';

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onKeyPress == null
          ? null
          : (TapDownDetails details) => onKeyPress!(viewport.noteAt(details.localPosition.dy)),
      child: SizedBox(
        width: tokens.size.prKeyColumnWidth,
        child: CustomPaint(
          painter: _KeyColumnPainter(
            viewport: viewport,
            white: tokens.color.textPrimary,
            black: tokens.color.surfaceSunken,
            line: tokens.color.lineStrong,
            lineWidth: tokens.border.hairline,
            blackWidth: tokens.size.prBlackKeyWidth,
            labelStyle: tokens.type.microCaps,
            activeKeys: activeKeys,
            active: tokens.color.accent,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _KeyColumnPainter extends CustomPainter {
  _KeyColumnPainter({
    required this.viewport,
    required this.white,
    required this.black,
    required this.line,
    required this.lineWidth,
    required this.blackWidth,
    required this.labelStyle,
    required this.activeKeys,
    required this.active,
  });

  final PrViewport viewport;
  final Color white;
  final Color black;
  final Color line;
  final double lineWidth;
  final double blackWidth;
  final TextStyle labelStyle;
  final Set<int> activeKeys;
  final Color active;

  late final Paint _white = Paint()..color = white;
  late final Paint _black = Paint()..color = black;
  late final Paint _active = Paint()..color = active;
  late final Paint _line = Paint()
    ..color = line
    ..strokeWidth = lineWidth;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Size size) {
    // The white bed first, then the black keys over it: drawing a key per row
    // would leave a hairline of canvas between white neighbours.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _white);

    final int rows = viewport.rowsIn(size.height);
    for (int i = 0; i < rows; i++) {
      final int midi = viewport.topMidiNote - i;
      final double top = i * viewport.rowHeight;
      final bool sounding = activeKeys.contains(midi);
      if (PrKeyColumn.isBlack(midi)) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, blackWidth, viewport.rowHeight),
          sounding ? _active : _black,
        );
        continue;
      }
      // A white key lights across its full width; the black keys are already
      // painted over it, so the accent reads as the key going down.
      if (sounding) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, viewport.rowHeight),
          _active,
        );
      }
      // A separator only between white keys — a black key already separates
      // the two it sits between.
      if (!PrKeyColumn.isBlack(midi + 1)) {
        canvas.drawLine(Offset(0, top), Offset(size.width, top), _line);
      }
      if (midi % 12 == 0) {
        _text
          ..text = TextSpan(
            text: PrKeyColumn.octaveLabel(midi),
            style: labelStyle,
          )
          ..layout();
        _text.paint(
          canvas,
          Offset(
            size.width - _text.width - lineWidth * 6,
            top + (viewport.rowHeight - _text.height) / 2,
          ),
        );
      }
    }
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, size.height),
      _line,
    );
  }

  @override
  bool shouldRepaint(_KeyColumnPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.white != white ||
      oldDelegate.black != black ||
      !setEquals(oldDelegate.activeKeys, activeKeys);
}
