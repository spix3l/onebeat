// ObSearchField — the rounded search field (UI-B-01).
//
// Magnifier + editable text, with an optional `⌘K`-style shortcut tag at the
// right edge. The compact round variant is [ObSearchIcon].
//
// The field deliberately uses [EditableText] rather than Material's [TextField]:
// OneBeat owns its chrome and does not use the Material theme.
import 'package:flutter/widgets.dart';

import '../core/shortcuts.dart';
import '../design/tokens.dart';
import 'magnifier_glyph.dart';

class ObSearchField extends StatefulWidget {
  const ObSearchField({
    required this.hint,
    this.shortcut,
    this.onTap,
    this.onChanged,
    this.focusNode,
    this.width,
    super.key,
  });

  final String hint;

  /// Optional shortcut caption (`⌘K`); null renders no tag.
  final String? shortcut;

  final VoidCallback? onTap;

  /// Called whenever the user changes the query.
  final ValueChanged<String>? onChanged;

  /// Optional owner-provided focus node, used when another control (such as the
  /// compact search icon) should focus this field.
  final FocusNode? focusNode;

  /// Defaults to [SizeTokens.searchWidth]; shrink-to-fit rows may override.
  final double? width;

  @override
  State<ObSearchField> createState() => _ObSearchFieldState();
}

class _ObSearchFieldState extends State<ObSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _internalFocusNode;
  bool _hover = false;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _internalFocusNode = FocusNode(debugLabel: 'search-field');
  }

  @override
  void dispose() {
    _controller.dispose();
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleTap() {
    _focusNode.requestFocus();
    widget.onTap?.call();
  }

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
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _handleTap(),
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
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    if (_controller.text.isEmpty)
                      IgnorePointer(
                        child: Text(
                          widget.hint,
                          style: tokens.type.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: double.infinity,
                        child: escapeReturnsFocus(
                          child: EditableText(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: tokens.type.label.copyWith(
                              color: color.textSecondary,
                            ),
                            cursorColor: color.accent,
                            backgroundCursorColor: color.surfaceWell,
                            maxLines: 1,
                            onChanged: (String value) {
                              setState(() {});
                              widget.onChanged?.call(value);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
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
