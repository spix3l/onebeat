// ObPopoverMenu — the anchored menu surface (UI-B-11 §6).
//
// Two menus in the mockups use it and they look nothing alike at first glance:
// the LAYOUTS menu is a list of checked options with icon actions under a rule,
// the Tools menu is a flat list with right-aligned shortcuts and one accented
// row. They are the same object — a raised card of rows — so they are one
// widget, and the difference is entirely in the vm.
//
// Presentational only: this draws an open menu. What opens it, where it is
// anchored and what closes it are the shell's business (Phase D).
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'kit_glyphs.dart';

/// How a row reads.
///
/// [normal] is an action, [active] the row that is currently true (the accent
/// fill under `Beatmaking` and `Extension manager…`), [danger] the destructive
/// one. A [checkable] row reserves the checkbox gutter whether or not it is
/// ticked, so a column of options does not jump when the selection moves.
enum ObMenuRowTone { normal, active, danger }

@immutable
class ObMenuRowVm {
  const ObMenuRowVm({
    required this.label,
    this.tone = ObMenuRowTone.normal,
    this.icon,
    this.shortcut,
    this.checkable = false,
    this.checked = false,
  });

  final String label;
  final ObMenuRowTone tone;

  /// The leading mark. Mutually exclusive with [checkable] — a row is either
  /// an option you tick or an action you take.
  final ObKitGlyphKind? icon;

  /// Right-aligned, in mono (`⌘J`, `⇧⌘E`).
  final String? shortcut;

  final bool checkable;
  final bool checked;
}

/// A run of rows under an optional micro-caps header. A section with a null
/// [header] and `separated` true is how the LAYOUTS menu rules off its actions.
@immutable
class ObMenuSectionVm {
  const ObMenuSectionVm({
    required this.rows,
    this.header,
    this.separated = false,
  });

  final List<ObMenuRowVm> rows;
  final String? header;

  /// Draws a hairline above the section.
  final bool separated;
}

@immutable
class ObPopoverMenuVm {
  const ObPopoverMenuVm({required this.sections, this.wide = false});

  final List<ObMenuSectionVm> sections;

  /// [SizeTokens.popoverWideWidth] instead of [SizeTokens.popoverWidth] — the
  /// menus whose rows carry a shortcut need the extra column.
  final bool wide;

  /// Flat row order, so a caller can map an index back to a row.
  List<ObMenuRowVm> get rows =>
      <ObMenuRowVm>[for (final ObMenuSectionVm s in sections) ...s.rows];
}

class ObPopoverMenu extends StatelessWidget {
  const ObPopoverMenu({required this.vm, this.onSelect, super.key});

  final ObPopoverMenuVm vm;

  /// Fired with the row's index in [ObPopoverMenuVm.rows].
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    final List<Widget> children = <Widget>[];
    int index = 0;
    for (final ObMenuSectionVm section in vm.sections) {
      if (section.separated) {
        children.add(_Separator(tokens: tokens));
      }
      final String? header = section.header;
      if (header != null) {
        children.add(
          SizedBox(
            height: tokens.size.popoverSectionHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(header.toUpperCase(), style: tokens.type.microCaps),
              ),
            ),
          ),
        );
      }
      for (final ObMenuRowVm row in section.rows) {
        final int rowIndex = index;
        children.add(
          _Row(
            row: row,
            onTap: onSelect == null ? null : () => onSelect!(rowIndex),
          ),
        );
        index++;
      }
    }

    return Container(
      width: vm.wide ? tokens.size.popoverWideWidth : tokens.size.popoverWidth,
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: color.surfaceRaised,
        borderRadius: BorderRadius.all(tokens.radius.lg),
        border: Border.all(color: color.lineStrong, width: tokens.border.hairline),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.windowShadow,
            blurRadius: tokens.size.windowShadowBlur,
            offset: Offset(0, tokens.size.windowShadowOffset),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      child: Container(
        height: tokens.border.hairline,
        color: tokens.color.line,
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.row, this.onTap});

  final ObMenuRowVm row;
  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final ObMenuRowVm row = widget.row;
    final bool enabled = widget.onTap != null;
    final bool active = row.tone == ObMenuRowTone.active;

    final Color ink;
    switch (row.tone) {
      case ObMenuRowTone.normal:
        ink = color.textPrimary;
      case ObMenuRowTone.active:
        ink = color.textPrimary;
      case ObMenuRowTone.danger:
        ink = color.danger;
    }

    final Color? background =
        active
            ? color.accent
            : (_hover && enabled ? color.surfaceHover : null);
    final String? shortcut = row.shortcut;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          child: Container(
            height: tokens.size.popoverRowHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
            decoration:
                background == null
                    ? null
                    : BoxDecoration(
                      color: background,
                      borderRadius: tokens.radius.controlBorder,
                    ),
            child: Row(
              children: <Widget>[
                if (row.checkable)
                  _CheckBox(checked: row.checked, onAccent: active)
                else if (row.icon != null)
                  SizedBox(
                    width: tokens.size.checkboxSize,
                    child: ObKitGlyph(kind: row.icon!, color: ink),
                  ),
                if (row.checkable || row.icon != null)
                  SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        active
                            ? tokens.type.menuRowActive
                            : tokens.type.menuRow.copyWith(color: ink),
                  ),
                ),
                if (shortcut != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.sm),
                  Text(shortcut, style: tokens.type.extMeta),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The option tick. On an accented row it inverts — a white box on the accent
/// fill — because an accent tick on an accent row is invisible.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked, required this.onAccent});

  final bool checked;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return SizedBox(
      width: tokens.size.checkboxSize,
      height: tokens.size.checkboxSize,
      child: Container(
        decoration: BoxDecoration(
          color:
              checked
                  ? (onAccent ? color.textPrimary : color.accent)
                  : color.none,
          borderRadius: BorderRadius.all(tokens.radius.sm),
          border: Border.all(
            color:
                checked
                    ? (onAccent ? color.textPrimary : color.accent)
                    : color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
        child:
            checked
                ? Center(
                  child: ObKitGlyph(
                    kind: ObKitGlyphKind.check,
                    color: onAccent ? color.accent : color.textPrimary,
                    size: ObKitGlyphSize.inline,
                  ),
                )
                : null,
      ),
    );
  }
}
