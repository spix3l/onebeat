// ObMenuBar — the 24px system/menu bar (UI-B-02).
//
// Pure chrome at the top of every screen: app dot + wordmark at the left, the
// menu titles beside it (the active one on a raised pill), the mono clock at
// the right. Menu popups are Phase D — here an item is a tap target and
// nothing more. Every string arrives via the vm; the `14:02` clock in the
// mockups is a fixture value, not a live time.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'glyphs.dart';

/// What the menu bar shows. `menus` are the item titles; a title may end in
/// `▾` to ask for a dropdown chevron (e.g. `Mixer ▾`), which renders as a
/// painted glyph rather than a text character. `activeIndex` is the item on
/// the raised pill, null when no menu is active.
@immutable
class ObMenuBarVm {
  const ObMenuBarVm({
    required this.menus,
    required this.clock,
    this.activeIndex,
  });

  final List<String> menus;
  final int? activeIndex;
  final String clock;
}

class ObMenuBar extends StatelessWidget {
  const ObMenuBar({required this.vm, this.onMenuTap, super.key});

  final ObMenuBarVm vm;

  /// Fired with the tapped item's index. Null renders the items inert.
  final ValueChanged<int>? onMenuTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.menuBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          _WordMark(tokens: tokens),
          SizedBox(width: tokens.spacing.xl),
          for (int i = 0; i < vm.menus.length; i++)
            _MenuItem(
              label: vm.menus[i],
              active: vm.activeIndex == i,
              onTap: onMenuTap == null ? null : () => onMenuTap!(i),
            ),
          const Spacer(),
          Text(vm.clock, style: tokens.type.numericSmall),
        ],
      ),
    );
  }
}

/// The app dot and `OneBeat` wordmark.
class _WordMark extends StatelessWidget {
  const _WordMark({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: tokens.size.chipDotSize,
          height: tokens.size.chipDotSize,
          decoration: BoxDecoration(
            color: tokens.color.accent,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: tokens.spacing.xs),
        Text('OneBeat', style: tokens.type.wordmark),
      ],
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  static const String _chevronSuffix = ' ▾';

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool hasChevron = widget.label.endsWith(_chevronSuffix);
    final String title = hasChevron
        ? widget.label.substring(0, widget.label.length - _chevronSuffix.length)
        : widget.label;
    final bool highlighted = widget.active || _hover;

    return Padding(
      padding: EdgeInsets.only(right: tokens.spacing.sm),
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: widget.onTap == null ? null : (_) => setState(() => _hover = true),
        onExit: widget.onTap == null ? null : (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.sm,
              vertical: tokens.spacing.xxs,
            ),
            decoration: highlighted
                ? BoxDecoration(
                    color: tokens.color.surfaceWell,
                    borderRadius: tokens.radius.controlBorder,
                    border: Border.all(
                      color: tokens.color.lineStrong,
                      width: tokens.border.hairline,
                    ),
                  )
                : null,
            child: Row(
              children: <Widget>[
                Text(
                  title,
                  style: tokens.type.menu.copyWith(
                    color: highlighted ? tokens.color.textPrimary : tokens.color.textMuted,
                  ),
                ),
                if (hasChevron) ...<Widget>[
                  SizedBox(width: tokens.spacing.xxs),
                  ObChromeGlyph(
                    kind: ObChromeGlyphKind.chevronDown,
                    color: highlighted ? tokens.color.textPrimary : tokens.color.textMuted,
                    scale: ObGlyphScale.chrome,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
