// ObDropdown — the micro-caps prefixed select field (UI-B-01).
//
// `components/dropdown.png`: a 156×26 well with a `SNAP`-style prefix, the
// current value and a chevron. Tapping opens a token-styled popover below the
// field — raised panel, radius, hairline, and an accent wash plus check mark
// on the selected row (the layouts popover in `screens/workspace-window.png`).
//
// The menu renders inside this widget's own stack, so a dropdown near the
// bottom of a scroll view can be clipped by an ancestor clip; screens own
// that placement, the atom stays free of overlay plumbing until Phase D asks
// for it.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObDropdown extends StatefulWidget {
  const ObDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.onSelected,
    super.key,
  });

  /// The micro-caps prefix (`SNAP`, `SCALE`, `GROUP`).
  final String label;

  /// The currently selected item; expected to appear in [items].
  final String value;

  final List<String> items;
  final ValueChanged<String>? onSelected;

  @override
  State<ObDropdown> createState() => _ObDropdownState();
}

class _ObDropdownState extends State<ObDropdown> {
  bool _open = false;

  void _select(String item) {
    setState(() => _open = false);
    widget.onSelected?.call(item);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double width = tokens.size.dropdownWidth;
    // While open, the box grows to cover the menu: a Stack only hit-tests
    // inside its own bounds, so a menu painted past them (Clip.none) would
    // be visible but untappable. Growing nudges the layout below the field
    // rather than overlapping it — screens that need a true overlay popover
    // get it in Phase D.
    final double menuHeight =
        widget.items.length * tokens.size.menuItemHeight +
        tokens.border.hairline * 2;
    final double height =
        tokens.size.microFieldHeight +
        (_open ? tokens.spacing.xs + menuHeight : 0);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          _Field(
            label: widget.label,
            value: widget.value,
            open: _open,
            // Opening is local UI state, so it works without a callback;
            // only selecting needs one.
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open)
            Positioned(
              left: 0,
              top: tokens.size.microFieldHeight + tokens.spacing.xs,
              width: width,
              child: _Menu(
                items: widget.items,
                selected: widget.value,
                onSelected: widget.onSelected == null ? null : _select,
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.open,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool open;
  final VoidCallback? onTap;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool engaged = widget.open || _hover;

    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter:
          widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit:
          widget.onTap == null ? null : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: tokens.size.microFieldHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          decoration: BoxDecoration(
            color: engaged ? color.surfaceHover : color.surfaceWell,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: widget.open ? color.accentMuted : color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Text(widget.label.toUpperCase(), style: tokens.type.microCaps),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  widget.value,
                  style: tokens.type.label.copyWith(color: color.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              CustomPaint(
                size: Size(tokens.size.iconSize, tokens.size.iconSize),
                painter: _ChevronPainter(
                  color: color.textSecondary,
                  stroke: tokens.border.glyph,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.items, required this.selected, this.onSelected});

  final List<String> items;
  final String selected;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      constraints: BoxConstraints(minWidth: tokens.size.dropdownWidth),
      decoration: BoxDecoration(
        color: tokens.color.surfaceOverlay,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String item in items)
            _MenuRow(
              label: item,
              checked: item == selected,
              onTap: onSelected == null ? null : () => onSelected!(item),
            ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.label, required this.checked, this.onTap});

  final String label;
  final bool checked;
  final VoidCallback? onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool highlight = widget.checked || _hover;

    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter:
          widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit:
          widget.onTap == null ? null : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: tokens.size.menuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          color:
              widget.checked
                  ? color.accentWash
                  : (_hover ? color.surfaceHover : color.none),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: tokens.size.iconSize,
                height: tokens.size.iconSize,
                child:
                    widget.checked
                        ? CustomPaint(
                          painter: _CheckPainter(
                            color: color.accentBright,
                            stroke: tokens.border.glyph,
                          ),
                        )
                        : null,
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                widget.label,
                style: tokens.type.bodySecondary.copyWith(
                  color: highlight ? color.textPrimary : color.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.color, required this.stroke});

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
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    canvas.drawLine(Offset(cx - 3, cy - 1), Offset(cx, cy + 2), paint);
    canvas.drawLine(Offset(cx, cy + 2), Offset(cx + 3, cy - 1), paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.color, required this.stroke});

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
    final Path path =
        Path()
          ..moveTo(size.width * 0.22, size.height * 0.52)
          ..lineTo(size.width * 0.44, size.height * 0.74)
          ..lineTo(size.width * 0.8, size.height * 0.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}
