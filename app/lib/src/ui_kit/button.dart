// ObButton — the app's one text button, in the five tones the screens use
// (UI-B-11).
//
// Everything from `Export` to `Uninstall` to `Try again once` is this widget at
// a different tone. Keeping them one widget is what makes a row of mixed
// buttons share a baseline and a corner radius; splitting them by screen is how
// an app ends up with four different 30px buttons.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'kit_glyphs.dart';

/// How loud the button is.
///
/// [accentOutline] is the odd one: an accent border over the resting surface,
/// used for a state that is *currently true* rather than an action you are
/// invited to take (`Enabled`, the `Layouts Beatmaking` pill). It has to look
/// different from [primary] for exactly that reason.
enum ObButtonTone { primary, secondary, danger, accentOutline, quiet }

class ObButton extends StatefulWidget {
  const ObButton({
    required this.label,
    this.onTap,
    this.tone = ObButtonTone.secondary,
    this.icon,
    this.prefix,
    this.large = false,
    this.width,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final ObButtonTone tone;

  /// An optional leading mark, drawn at the button's ink colour.
  final ObKitGlyphKind? icon;

  /// A dim micro-caps word before the label — the `Layouts` in
  /// `Layouts Beatmaking`, where the label is the value and this is what it
  /// names.
  final String? prefix;

  /// [SizeTokens.buttonLargeHeight] instead of [SizeTokens.buttonHeight]: the
  /// empty states give their calls to action more room than a toolbar does.
  final bool large;

  /// Fixed width; otherwise the button hugs its content.
  final double? width;

  @override
  State<ObButton> createState() => _ObButtonState();
}

class _ObButtonState extends State<ObButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null;
    final bool hot = _hover && enabled;

    late final Color background;
    late final Color border;
    late final Color ink;
    switch (widget.tone) {
      case ObButtonTone.primary:
        background = hot ? color.accentBright : color.accent;
        border = color.accentDeep;
        ink = color.textPrimary;
      case ObButtonTone.secondary:
        background = hot ? color.surfaceHover : color.surfaceWell;
        border = color.lineStrong;
        ink = color.textPrimary;
      case ObButtonTone.danger:
        background = hot ? color.dangerWash : color.surfaceWell;
        border = color.dangerMuted;
        ink = color.danger;
      case ObButtonTone.accentOutline:
        background = hot ? color.accentWash : color.none;
        border = color.accent;
        ink = color.accentBright;
      case ObButtonTone.quiet:
        background = hot ? color.surfaceWell : color.none;
        border = color.none;
        ink = color.textSecondary;
    }

    final String? prefix = widget.prefix;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height:
              widget.large
                  ? tokens.size.buttonLargeHeight
                  : tokens.size.buttonHeight,
          constraints: BoxConstraints(minWidth: tokens.size.buttonMinWidth),
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: border, width: tokens.border.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                ObKitGlyph(kind: widget.icon!, color: ink),
                SizedBox(width: tokens.spacing.xs),
              ],
              if (prefix != null) ...<Widget>[
                Text(prefix, style: tokens.type.menu),
                SizedBox(width: tokens.spacing.xs),
              ],
              Text(
                widget.label,
                maxLines: 1,
                style: tokens.type.menuRowActive.copyWith(color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
