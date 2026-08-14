// ObSearchField — the rounded search field (UI-B-01).
//
// Magnifier + hint, with an optional `⌘K`-style shortcut tag at the right
// edge. Static rendering only — wiring actual text input and focus is Phase
// D territory, so the field paints its hint and accepts a tap callback,
// nothing more. The compact round variant is [ObSearchIcon].
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'magnifier_glyph.dart';

class ObSearchField extends StatefulWidget {
  const ObSearchField({
    required this.hint,
    this.shortcut,
    this.onTap,
    this.width,
    super.key,
  });

  final String hint;

  /// Optional shortcut caption (`⌘K`); null renders no tag.
  final String? shortcut;

  final VoidCallback? onTap;

  /// Defaults to [SizeTokens.searchWidth]; shrink-to-fit rows may override.
  final double? width;

  @override
  State<ObSearchField> createState() => _ObSearchFieldState();
}

class _ObSearchFieldState extends State<ObSearchField> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? shortcut = widget.shortcut;

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
          width: widget.width ?? tokens.size.searchWidth,
          height: tokens.size.searchFieldHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          decoration: BoxDecoration(
            color: _hover ? color.surfaceHover : color.surfaceWell,
            borderRadius: BorderRadius.all(tokens.radius.lg),
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              ObMagnifierGlyph(color: color.textMuted),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  widget.hint,
                  style: tokens.type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (shortcut != null) ...<Widget>[
                SizedBox(width: tokens.spacing.xs),
                _ShortcutTag(label: shortcut),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutTag extends StatelessWidget {
  const _ShortcutTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.tagHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs),
      decoration: BoxDecoration(
        color: tokens.color.surfaceOverlay,
        borderRadius: BorderRadius.all(tokens.radius.sm),
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      alignment: Alignment.center,
      child: Text(label, style: tokens.type.numericSmall),
    );
  }
}
