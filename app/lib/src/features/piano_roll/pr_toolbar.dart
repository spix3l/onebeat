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
    final double w = size.width;
    final double h = size.height;

    switch (tool) {
      case PrTool.pencil:
        canvas.drawLine(
          Offset(w * 0.3, h * 0.7),
          Offset(w * 0.68, h * 0.32),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.62, h * 0.26),
          Offset(w * 0.74, h * 0.38),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.3, h * 0.7),
          Offset(w * 0.26, h * 0.74),
          line,
        );
      case PrTool.select:
        // A marquee: a dashed-looking box drawn as four corner brackets.
        final Rect box = Rect.fromLTWH(w * 0.26, h * 0.26, w * 0.48, h * 0.48);
        for (final (Offset from, Offset to) in <(Offset, Offset)>[
          (box.topLeft, box.topLeft.translate(w * 0.16, 0)),
          (box.topLeft, box.topLeft.translate(0, h * 0.16)),
          (box.bottomRight, box.bottomRight.translate(-w * 0.16, 0)),
          (box.bottomRight, box.bottomRight.translate(0, -h * 0.16)),
        ]) {
          canvas.drawLine(from, to, line);
        }
      case PrTool.eraser:
        final Path body =
            Path()
              ..moveTo(w * 0.24, h * 0.62)
              ..lineTo(w * 0.52, h * 0.3)
              ..lineTo(w * 0.76, h * 0.5)
              ..lineTo(w * 0.5, h * 0.74)
              ..close();
        canvas.drawPath(body, line);
        canvas.drawLine(
          Offset(w * 0.36, h * 0.74),
          Offset(w * 0.76, h * 0.74),
          line,
        );
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
