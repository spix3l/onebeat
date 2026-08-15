// ObSearchIcon — the compact round search button (UI-B-01).
//
// The icon-only variant at the top right of the rack header; the full field
// is [ObSearchField].
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'magnifier_glyph.dart';

class ObSearchIcon extends StatefulWidget {
  const ObSearchIcon({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  State<ObSearchIcon> createState() => _ObSearchIconState();
}

class _ObSearchIconState extends State<ObSearchIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double size = tokens.size.searchIconFieldSize;

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null ? null : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _hover ? color.surfaceHover : color.surfaceWell,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: ObMagnifierGlyph(
            color: _hover ? color.textSecondary : color.textMuted,
          ),
        ),
      ),
    );
  }
}
