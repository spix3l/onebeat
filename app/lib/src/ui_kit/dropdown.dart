// ObDropdown — the micro-caps prefixed select field (UI-B-01).
//
// `components/dropdown.png`: a 156×26 well with a `SNAP`-style prefix, the
// current value and a chevron. Tapping opens a token-styled popover below the
// field — raised panel, radius, hairline, and an accent wash plus check mark
// on the selected row (the layouts popover in `screens/workspace-window.png`).
//
// The menu renders in the nearest `Overlay` via `OverlayPortal`, anchored
// below the field with `CompositedTransformFollower`. That keeps the field's
// own box at its closed size — opening does not reflow the toolbar row it
// sits in — and paints the menu above whatever content follows it. The two
// bugs the first in-stack version had (a vertical jump on open, and the menu
// dropping behind the lane below) are both structural properties of an
// overlay, not per-screen fixes.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObDropdown extends StatefulWidget {
  const ObDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.onSelected,
    this.width,
    super.key,
  });

  /// The micro-caps prefix (`SNAP`, `SCALE`, `GROUP`).
  final String label;

  /// The currently selected item; expected to appear in [items].
  final String value;

  final List<String> items;
  final ValueChanged<String>? onSelected;

  /// Defaults to [SizeTokens.dropdownWidth]. A toolbar whose fields hold
  /// labels of very different lengths sizes them itself — `CHANNEL TYPE
  /// Sampler` does not fit the default, and truncating a select's current
  /// value to `Sa…` defeats the control.
  final double? width;

  @override
  State<ObDropdown> createState() => _ObDropdownState();
}

class _ObDropdownState extends State<ObDropdown> {
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      setState(() => _open = true);
      _portalController.show();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _portalController.hide();
  }

  void _select(String item) {
    _close();
    widget.onSelected?.call(item);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double width = widget.width ?? tokens.size.dropdownWidth;
    // The field stays a fixed 26px box; the menu is a separate overlay child
    // anchored below it, so opening never reflows this widget's parent row.
    // The SizedBox pins both axes explicitly — the width is what the field's
    // `Expanded` value text needs, and the height keeps the box from growing
    // to a stretchy parent, now that the field no longer inflates to hold its
    // own menu.
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: width,
        height: tokens.size.microFieldHeight,
        child: OverlayPortal(
          controller: _portalController,
          overlayChildBuilder: (BuildContext context) {
            // A full-surface tap barrier sits behind the menu so a click
            // anywhere else in the window closes the dropdown; the menu rows
            // (stacked on top) still take their own taps. `Align` shrink-wraps
            // the menu so the `SizedBox` can pin it to the field's width
            // rather than the overlay's full-surface constraints.
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: const SizedBox.expand(),
                  ),
                ),
                CompositedTransformFollower(
                  link: _layerLink,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: Offset(0, tokens.spacing.xs),
                  showWhenUnlinked: false,
                  child: Align(
                    alignment: Alignment.topLeft,
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: SizedBox(
                      width: width,
                      child: _Menu(
                        items: widget.items,
                        selected: widget.value,
                        onSelected: widget.onSelected == null ? null : _select,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: _Field(
            label: widget.label,
            value: widget.value,
            open: _open,
            // Opening is local UI state, so it works without a callback; only
            // selecting needs one.
            onTap: _toggle,
          ),
        ),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({required this.label, required this.value, required this.open, required this.onTap});

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
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null ? null : (_) => setState(() => _hover = false),
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
              if (widget.label.isNotEmpty) ...<Widget>[
                Text(widget.label.toUpperCase(), style: tokens.type.microCaps),
                SizedBox(width: tokens.spacing.sm),
              ],
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
                painter: _ChevronPainter(color: color.textSecondary, stroke: tokens.border.glyph),
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
    // No width constraint here: the overlay child wraps this in a `SizedBox`
    // set to the field's width, so the open menu is exactly as wide as the
    // field that opened it — never a fixed 156px minimum that overhangs a
    // narrower field.
    return Container(
      decoration: BoxDecoration(
        color: tokens.color.surfaceOverlay,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
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
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null ? null : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: tokens.size.menuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          color: widget.checked ? color.accentWash : (_hover ? color.surfaceHover : color.none),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: tokens.size.iconSize,
                height: tokens.size.iconSize,
                child:
                    widget.checked
                        ? CustomPaint(painter: _CheckPainter(color: color.accentBright, stroke: tokens.border.glyph))
                        : null,
              ),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.type.bodySecondary.copyWith(color: highlight ? color.textPrimary : color.textSecondary),
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
