// ObRailButton — a left-rail destination tile (UI-B-01).
//
// The 42×44 icon+caption stack from `components/rail-button.png`, in situ on
// the channel-rack rail. Rest is deliberately dim — the rail is a column of
// destinations, not a list of actions, and only the active destination earns
// any ink. Active fills the tile with the accent and turns both glyph and
// caption white.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObRailButton extends StatefulWidget {
  const ObRailButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    super.key,
  });

  /// The glyph at [SizeTokens.railGlyphSize]. It is wrapped in an
  /// [IconTheme] carrying the tile's foreground colour, so glyphs should
  /// honour `IconTheme.of` rather than colour themselves.
  final Widget icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<ObRailButton> createState() => _ObRailButtonState();
}

class _ObRailButtonState extends State<ObRailButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final Color foreground = widget.active ? color.textPrimary : (_hover ? color.textSecondary : color.textMuted);

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null ? null : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: tokens.size.railButtonWidth,
          height: tokens.size.railTileSize,
          decoration: BoxDecoration(
            color: widget.active ? color.accent : color.none,
            borderRadius: tokens.radius.panelBorder,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: tokens.size.railGlyphSize,
                height: tokens.size.railGlyphSize,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: foreground,
                      size: tokens.size.railGlyphSize,
                    ),
                    child: widget.icon,
                  ),
                ),
              ),
              SizedBox(height: tokens.spacing.xxs),
              Text(
                widget.label.toUpperCase(),
                // A destination caption is one word and must stay one line:
                // `CHANNELS` broken across two lines reads as two rails.
                maxLines: 1,
                softWrap: false,
                style: tokens.type.railCaption.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
