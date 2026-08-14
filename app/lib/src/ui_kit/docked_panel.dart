// ObDockedPanel — the frame every docked panel shares (UI-B-11, UI-C-11 §4).
//
// `screens/ext-panel.png` is the argument for this widget existing: the channel
// rack, an extension's own panel and a compressor sit side by side, and they
// have the same header — a drag grip, a micro-caps title, optional marks after
// it, and a right-aligned dim note. That is the point the screen is making.
// An extension panel is "docked like any other", and it can only look that way
// if it is drawn by the same code.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObDockedPanel extends StatelessWidget {
  const ObDockedPanel({
    required this.title,
    required this.child,
    this.badge,
    this.rightNote,
    this.actions = const <Widget>[],
    this.width,
    super.key,
  });

  /// Rendered upper-case in [TypeTokens.sectionHeader].
  final String title;
  final Widget child;

  /// A mark after the title — the accent-outlined `EXT` tag that says this
  /// panel came from an extension rather than from the app.
  final Widget? badge;

  /// Dim, right-aligned: `native`, `by @luma`.
  final String? rightNote;

  /// Header buttons after [rightNote].
  final List<Widget> actions;

  final double? width;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? note = rightNote;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: color.surfacePanel,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(color: color.lineStrong, width: tokens.border.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: tokens.size.panelHeaderHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                ObPanelGrip(color: color.textMuted),
                SizedBox(width: tokens.spacing.sm),
                Text(
                  title.toUpperCase(),
                  style: tokens.type.sectionHeader.copyWith(
                    color: color.textSecondary,
                  ),
                ),
                if (badge != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.sm),
                  badge!,
                ],
                const Spacer(),
                if (note != null) Text(note, style: tokens.type.menu),
                ...actions,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The dotted drag handle at the left of a panel header. Six dots rather than
/// the two-rule grip the rest of the industry draws: at this size a rule reads
/// as a divider, and this one has to read as "you can pick this up".
class ObPanelGrip extends StatelessWidget {
  const ObPanelGrip({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.panelGripWidth,
      height: tokens.size.iconSize,
      child: CustomPaint(
        painter: PanelGripPainter(color: color, dot: tokens.border.hairline),
      ),
    );
  }
}

class PanelGripPainter extends CustomPainter {
  PanelGripPainter({required this.color, required this.dot});

  final Color color;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    const int columns = 5;
    final double step = size.width / columns;
    for (int i = 0; i < columns; i++) {
      canvas.drawCircle(
        Offset(step * (i + 0.5), size.height / 2),
        dot * 0.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PanelGripPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dot != dot;
}
