// PrToolbar — the roll's header row (UI-B-07).
//
// Left: where you are (`Piano roll › Main Groove › Soft Keys`). Right: what
// you are doing with it — the pattern, the four tools, the scale and snap the
// edits obey, the zoom, and the way back. The breadcrumb dims from left to
// right so the *current* thing is the quietest: you already know what you are
// editing; the crumbs are how you leave.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/dropdown.dart';
import '../../ui_kit/tooltip.dart';

/// The editing tools.
///
/// There were four. The fourth — `tag` — was a diamond glyph wired to nothing:
/// selecting it made the roll inert, because every gesture path branched on
/// pencil or eraser and fell through. A control that cannot be explained is a
/// control that should not ship, so the tools are now the three the roll
/// actually implements.
enum PrTool {
  pencil,
  select,
  eraser;

  /// What the tool does, in the imperative. This is the tooltip and it is the
  /// only reason the glyph is legible on first sight.
  String get label => switch (this) {
    PrTool.pencil => 'Draw notes',
    PrTool.select => 'Select notes',
    PrTool.eraser => 'Erase notes',
  };

  /// The key that picks it up, shown alongside the label.
  String get shortcut => switch (this) {
    PrTool.pencil => 'P',
    PrTool.select => 'E',
    PrTool.eraser => 'D',
  };
}

@immutable
class PrToolbarVm {
  const PrToolbarVm({
    required this.crumbs,
    required this.pattern,
    required this.scale,
    required this.snap,
    this.tool = PrTool.pencil,
    this.patterns = const <String>['Main Groove', 'Bass Motif'],
    this.scales = const <String>['C min', 'C maj', 'A min', 'Chromatic'],
    this.snaps = const <String>['1/4', '1/8', '1/16', 'None'],
    this.backLabel = 'Back to playlist',
  });

  /// Trail from the outermost place inwards; the last is where you are.
  final List<String> crumbs;

  final String pattern;
  final String scale;
  final String snap;
  final PrTool tool;
  final List<String> patterns;
  final List<String> scales;
  final List<String> snaps;
  final String backLabel;
}

class PrToolbar extends StatelessWidget {
  const PrToolbar({
    required this.vm,
    this.channelColor,
    this.onPattern,
    this.onTool,
    this.onScale,
    this.onSnap,
    this.onZoomIn,
    this.onZoomOut,
    this.onBack,
    super.key,
  });

  final PrToolbarVm vm;

  /// The tile at the far left carries the edited channel's identity colour.
  final Color? channelColor;

  final ValueChanged<String>? onPattern;
  final ValueChanged<PrTool>? onTool;
  final ValueChanged<String>? onScale;
  final ValueChanged<String>? onSnap;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.prToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
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
          _ChannelTile(color: channelColor ?? color.accent),
          SizedBox(width: tokens.spacing.sm),
          for (int i = 0; i < vm.crumbs.length; i++) ...<Widget>[
            if (i > 0) ...<Widget>[
              SizedBox(width: tokens.spacing.xs),
              Text('›', style: tokens.type.label),
              SizedBox(width: tokens.spacing.xs),
            ],
            Text(
              vm.crumbs[i],
              maxLines: 1,
              style: tokens.type.breadcrumb.copyWith(
                color:
                    i == vm.crumbs.length - 1
                        ? color.textMuted
                        : (i == 0 ? color.textPrimary : color.textSecondary),
                fontWeight:
                    i == 0 ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          ObDropdown(
            label: 'Pattern',
            value: vm.pattern,
            items: vm.patterns,
            width: tokens.size.prPatternFieldWidth,
            onSelected: onPattern,
          ),
          SizedBox(width: tokens.spacing.sm),
          for (final PrTool tool in PrTool.values) ...<Widget>[
            ObTooltip(
              message: tool.label,
              shortcut: tool.shortcut,
              child: _ToolButton(
                tool: tool,
                active: tool == vm.tool,
                onTap: onTool == null ? null : () => onTool!(tool),
              ),
            ),
            SizedBox(width: tokens.spacing.xs),
          ],
          SizedBox(width: tokens.spacing.xs),
          ObDropdown(
            label: 'Scale',
            value: vm.scale,
            items: vm.scales,
            onSelected: onScale,
          ),
          SizedBox(width: tokens.spacing.sm),
          ObDropdown(
            label: 'Snap',
            value: vm.snap,
            items: vm.snaps,
            onSelected: onSnap,
          ),
          SizedBox(width: tokens.spacing.sm),
          ObTooltip(
            message: 'Zoom out',
            shortcut: '⌘−',
            child: _ZoomButton(zoomIn: false, onTap: onZoomOut),
          ),
          SizedBox(width: tokens.spacing.xs),
          ObTooltip(
            message: 'Zoom in',
            shortcut: '⌘+',
            child: _ZoomButton(zoomIn: true, onTap: onZoomIn),
          ),
          SizedBox(width: tokens.spacing.sm),
          _BackButton(label: vm.backLabel, onTap: onBack),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: tokens.size.microFieldHeight,
      height: tokens.size.microFieldHeight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: tokens.radius.controlBorder,
      ),
      child: CustomPaint(
        painter: _NotePainter(
          color: tokens.color.textPrimary,
          stroke: tokens.border.glyph,
        ),
      ),
    );
  }
}

class _ToolButton extends StatefulWidget {
  const _ToolButton({required this.tool, required this.active, this.onTap});

  final PrTool tool;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null;
    final Color fill;
    if (widget.active) {
      fill = _hover && enabled ? color.accentBright : color.accent;
    } else {
      fill = _hover && enabled ? color.surfaceHover : color.surfaceWell;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: tokens.size.microFieldHeight,
          height: tokens.size.microFieldHeight,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: widget.active ? color.accentBright : color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: CustomPaint(
            painter: _ToolPainter(
              tool: widget.tool,
              color: widget.active ? color.textPrimary : color.textSecondary,
              stroke: tokens.border.glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.zoomIn, this.onTap});

  final bool zoomIn;
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
          width: tokens.size.microFieldHeight,
          height: tokens.size.microFieldHeight,
          decoration: BoxDecoration(
            color: color.surfaceWell,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: CustomPaint(
            painter: _PlusMinusPainter(
              plus: zoomIn,
              color: color.textSecondary,
              stroke: tokens.border.glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
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
          height: tokens.size.microFieldHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          decoration: BoxDecoration(
            color: _hover && enabled ? color.surfaceHover : color.surfaceWell,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: tokens.size.iconSize,
                height: tokens.size.iconSize,
                child: CustomPaint(
                  painter: _CrossPainter(
                    color: color.textMuted,
                    stroke: tokens.border.glyph,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                widget.label,
                maxLines: 1,
                style: tokens.type.label.copyWith(color: color.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolPainter extends CustomPainter {
  _ToolPainter({
    required this.tool,
    required this.color,
    required this.stroke,
  });

  final PrTool tool;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color;
    final Paint fill = Paint()..color = color;

    // The glyphs are drawn inside a square inset from the 26px button, rather
    // than in fractions of the button itself. The old glyphs occupied the
    // middle ~45% — about 12px — which at a 1.5px stroke left three-pixel
    // segments that read as a broken shape rather than as a pencil.
    final double side = size.shortestSide;
    final double inset = side * 0.22;
    final Rect box = Rect.fromLTWH(
      (size.width - side) / 2 + inset,
      (size.height - side) / 2 + inset,
      side - inset * 2,
      side - inset * 2,
    );
    double x(double t) => box.left + box.width * t;
    double y(double t) => box.top + box.height * t;

    switch (tool) {
      case PrTool.pencil:
        // A pencil pointing down-left: a body with two parallel edges, a
        // ferrule across it, and a closed tip. Closed and continuous, so it
        // survives being 14px across.
        final Path body =
            Path()
              ..moveTo(x(0.72), y(0.0))
              ..lineTo(x(1.0), y(0.28))
              ..lineTo(x(0.34), y(0.94))
              ..lineTo(x(0.0), y(1.0))
              ..lineTo(x(0.06), y(0.66))
              ..close();
        canvas.drawPath(body, line);
        // The ferrule: where the wood stops and the metal starts.
        canvas.drawLine(Offset(x(0.52), y(0.2)), Offset(x(0.8), y(0.48)), line);
        // The graphite tip, filled so the business end reads at a glance.
        final Path tip =
            Path()
              ..moveTo(x(0.0), y(1.0))
              ..lineTo(x(0.06), y(0.66))
              ..lineTo(x(0.34), y(0.94))
              ..close();
        canvas.drawPath(tip, fill);

      case PrTool.select:
        // A marquee as four corner brackets. Dashes were tried first and at
        // 14px the gaps close up into a plain square — the corners have to
        // carry the whole idea, so the gap in the middle of each edge is made
        // large enough that it cannot fill in.
        final Rect marquee = Rect.fromLTRB(x(0.0), y(0.06), x(1.0), y(0.94));
        const double arm = 0.32;
        for (final (Offset corner, double dx, double dy) in <(
          Offset,
          double,
          double,
        )>[
          (marquee.topLeft, 1, 1),
          (marquee.topRight, -1, 1),
          (marquee.bottomLeft, 1, -1),
          (marquee.bottomRight, -1, -1),
        ]) {
          canvas
            ..drawLine(
              corner,
              corner.translate(dx * marquee.width * arm, 0),
              line,
            )
            ..drawLine(
              corner,
              corner.translate(0, dy * marquee.height * arm),
              line,
            );
        }

      case PrTool.eraser:
        // A block eraser held at an angle over the line it is clearing.
        //
        // The rubber end is *filled* rather than divided from the body by a
        // seam: an outlined block with a line through it reads as stacked
        // layers at this size, which is exactly what the previous glyph looked
        // like. One solid end and one hollow one cannot be mistaken for a
        // stack.
        final Path body =
            Path()
              ..moveTo(x(0.34), y(0.04))
              ..lineTo(x(1.0), y(0.38))
              ..lineTo(x(0.66), y(0.74))
              ..lineTo(x(0.0), y(0.4))
              ..close();
        final Path nib =
            Path()
              ..moveTo(x(0.0), y(0.4))
              ..lineTo(x(0.24), y(0.14))
              ..lineTo(x(0.9), y(0.48))
              ..lineTo(x(0.66), y(0.74))
              ..close();
        canvas
          ..drawPath(body, line)
          ..drawPath(nib, fill)
          // The surface being erased.
          ..drawLine(Offset(x(0.1), y(0.97)), Offset(x(1.0), y(0.97)), line);
    }
  }

  @override
  bool shouldRepaint(_ToolPainter oldDelegate) =>
      oldDelegate.tool != tool || oldDelegate.color != color;
}

class _PlusMinusPainter extends CustomPainter {
  _PlusMinusPainter({
    required this.plus,
    required this.color,
    required this.stroke,
  });

  final bool plus;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;
    canvas.drawLine(Offset(w * 0.3, h * 0.5), Offset(w * 0.7, h * 0.5), line);
    if (plus) {
      canvas.drawLine(Offset(w * 0.5, h * 0.3), Offset(w * 0.5, h * 0.7), line);
    }
  }

  @override
  bool shouldRepaint(_PlusMinusPainter oldDelegate) =>
      oldDelegate.plus != plus || oldDelegate.color != color;
}

class _CrossPainter extends CustomPainter {
  _CrossPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;
    canvas.drawLine(Offset(w * 0.32, h * 0.32), Offset(w * 0.68, h * 0.68), line);
    canvas.drawLine(Offset(w * 0.68, h * 0.32), Offset(w * 0.32, h * 0.68), line);
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}

class _NotePainter extends CustomPainter {
  _NotePainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;
    canvas.drawLine(Offset(w * 0.4, h * 0.66), Offset(w * 0.4, h * 0.32), line);
    canvas.drawLine(Offset(w * 0.68, h * 0.6), Offset(w * 0.68, h * 0.26), line);
    canvas.drawLine(Offset(w * 0.4, h * 0.32), Offset(w * 0.68, h * 0.26), line);
    canvas.drawCircle(Offset(w * 0.33, h * 0.68), w * 0.08, line);
    canvas.drawCircle(Offset(w * 0.61, h * 0.62), w * 0.08, line);
  }

  @override
  bool shouldRepaint(_NotePainter oldDelegate) => oldDelegate.color != color;
}

/// Renders one tool glyph on its own. Exists so the glyphs can be inspected and
/// golden-tested at size, independent of the button that carries them.
@visibleForTesting
class PrToolGlyphPreview extends StatelessWidget {
  const PrToolGlyphPreview({required this.tool, super.key});

  final PrTool tool;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.microFieldHeight,
      height: tokens.size.microFieldHeight,
      child: CustomPaint(
        painter: _ToolPainter(
          tool: tool,
          color: tokens.color.textSecondary,
          stroke: tokens.border.glyph,
        ),
      ),
    );
  }
}
