import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui/controls.dart';
import '../../ui/plugin_library_store.dart';

class OneBeatPianoEditor extends StatelessWidget {
  const OneBeatPianoEditor({required this.library, super.key});
  final PluginLibraryStore library;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final List<HostedParameter> parameters = library.parameters;
    return Container(
      color: t.color.surfaceDeep,
      alignment: Alignment.topCenter,
      padding: EdgeInsets.all(t.spacing.xl),
      child: SizedBox(
        width: t.size.pluginBrowserWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('ONEBEAT', style: t.type.title),
                SizedBox(width: t.spacing.lg),
                Text('STOCK INSTRUMENT / 01', style: t.type.label),
                const Spacer(),
                Text('32 VOICES', style: t.type.numericSmall),
                SizedBox(width: t.spacing.lg),
                OneBeatButton(
                  label: 'BACK',
                  semanticLabel: 'Close OneBeat Piano',
                  onPressed: library.closeParameters,
                ),
              ],
            ),
            SizedBox(height: t.spacing.xxl),
            Text('PIANO', style: t.type.numericLarge),
            SizedBox(height: t.spacing.sm),
            Text(
              'A compact, responsive piano for sketching the first idea.',
              style: t.type.body.copyWith(color: t.color.textMuted),
            ),
            SizedBox(height: t.spacing.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                for (final HostedParameter parameter in parameters)
                  _StockControl(parameter: parameter, library: library),
              ],
            ),
            SizedBox(height: t.spacing.xxl),
            Row(
              children: <Widget>[
                Text('PLAYABLE RANGE  C3 — B4', style: t.type.label),
                const Spacer(),
                Text('PRESS AND HOLD TO AUDITION', style: t.type.label),
              ],
            ),
            SizedBox(height: t.spacing.sm),
            SizedBox(
              height: t.size.stockPianoKeyboardHeight,
              child: _StockKeyboard(library: library),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockControl extends StatelessWidget {
  const _StockControl({required this.parameter, required this.library});
  final HostedParameter parameter;
  final PluginLibraryStore library;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final double normalized =
        (parameter.value - parameter.minimum) /
        (parameter.maximum - parameter.minimum);
    return Semantics(
      label: parameter.name,
      value: parameter.display,
      slider: true,
      child: GestureDetector(
        onVerticalDragStart: (_) => library.beginParameterGesture(parameter.id),
        onVerticalDragUpdate: (DragUpdateDetails details) {
          final double range = parameter.maximum - parameter.minimum;
          library.setParameter(
            parameter,
            (parameter.value - details.delta.dy * range / 160)
                .clamp(parameter.minimum, parameter.maximum)
                .toDouble(),
          );
        },
        onVerticalDragEnd: (_) => library.endParameterGesture(parameter.id),
        child: Column(
          children: <Widget>[
            CustomPaint(
              size: Size.square(t.size.stockPianoControlSize),
              painter: _StockDialPainter(tokens: t, value: normalized),
              child: SizedBox.square(
                dimension: t.size.stockPianoControlSize,
                child: Center(
                  child: Text(
                    '${(normalized * 100).round()}',
                    style: t.type.numericSmall.copyWith(
                      color: t.color.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: t.spacing.sm),
            Text(parameter.name, style: t.type.label),
          ],
        ),
      ),
    );
  }
}

class _StockDialPainter extends CustomPainter {
  const _StockDialPainter({required this.tokens, required this.value});
  final OneBeatTokens tokens;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = tokens.color.surfaceRaised,
    );
    canvas.drawCircle(
      center,
      radius - tokens.border.hairline,
      Paint()
        ..color = tokens.color.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = tokens.border.hairline,
    );
    final double angle = (-0.75 + value * 1.5) * 3.141592653589793;
    final Offset start = center + Offset.fromDirection(angle, radius * 0.48);
    final Offset end = center + Offset.fromDirection(angle, radius * 0.82);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = tokens.color.accent
        ..strokeWidth = tokens.border.emphasis
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StockDialPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.tokens != tokens;
}

class _StockKeyboard extends StatelessWidget {
  const _StockKeyboard({required this.library});
  final PluginLibraryStore library;
  static const List<int> _notes = <int>[
    48,
    50,
    52,
    53,
    55,
    57,
    59,
    60,
    62,
    64,
    65,
    67,
    69,
    71,
  ];
  static const List<int> _blackAfter = <int>[0, 1, 3, 4, 5, 7, 8, 10, 11, 12];
  static const List<int> _blackNotes = <int>[
    49,
    51,
    54,
    56,
    58,
    61,
    63,
    66,
    68,
    70,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double whiteWidth = constraints.maxWidth / _notes.length;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final int note in _notes)
                    Expanded(
                      child: _PianoKey(
                        note: note,
                        dark: false,
                        library: library,
                      ),
                    ),
                ],
              ),
            ),
            for (int index = 0; index < _blackAfter.length; ++index)
              Positioned(
                left: (_blackAfter[index] + 1) * whiteWidth - whiteWidth * 0.29,
                top: 0,
                width: whiteWidth * 0.58,
                height: constraints.maxHeight * 0.62,
                child: _PianoKey(
                  note: _blackNotes[index],
                  dark: true,
                  library: library,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PianoKey extends StatelessWidget {
  const _PianoKey({
    required this.note,
    required this.dark,
    required this.library,
  });
  final int note;
  final bool dark;
  final PluginLibraryStore library;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return Listener(
      onPointerDown: (_) => library.auditionNoteOn(note),
      onPointerUp: (_) => library.auditionNoteOff(note),
      onPointerCancel: (_) => library.auditionNoteOff(note),
      child: Container(
        margin: EdgeInsets.only(right: t.spacing.xxs),
        decoration: BoxDecoration(
          color: dark ? t.color.surfaceDeep : t.color.textPrimary,
          border: Border.all(color: t.color.line),
          borderRadius: BorderRadius.vertical(bottom: t.radius.sm),
        ),
        alignment: Alignment.bottomCenter,
        padding: EdgeInsets.only(bottom: t.spacing.sm),
        child:
            dark
                ? null
                : Text(
                  '$note',
                  style: t.type.numericSmall.copyWith(
                    color: t.color.surfaceRaised,
                  ),
                ),
      ),
    );
  }
}
