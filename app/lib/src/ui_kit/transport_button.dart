// ObTransportButton — the transport-bar control well (UI-B-01).
//
// The 32px rounded square from `components/transport-btn.png`. States: rest
// (well + hairline + caller's glyph), hover (one surface up), active (accent
// fill, e.g. Play in the mockups), and toggled (accent wash for latch-type
// controls). Pure (data, callbacks); the caller supplies the glyph so no icon
// set is coupled into the kit.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObTransportButton extends StatefulWidget {
  const ObTransportButton({
    required this.child,
    this.onTap,
    this.active = false,
    this.toggled = false,
    super.key,
  });

  /// The glyph, already sized and coloured by the caller — this widget only
  /// paints the well underneath it.
  final Widget child;
  final VoidCallback? onTap;

  /// Accent-filled state; the one accented control in the transport bar.
  final bool active;

  /// Latched state (e.g. loop enabled): accent wash rather than full accent.
  final bool toggled;

  @override
  State<ObTransportButton> createState() => _ObTransportButtonState();
}

class _ObTransportButtonState extends State<ObTransportButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double size = tokens.size.transportButtonSize;

    final Color background;
    final Color border;
    if (widget.active) {
      background = color.accent;
      border = color.accentDeep;
    } else if (widget.toggled) {
      background = color.accentWash;
      border = color.accentMuted;
    } else if (_hover) {
      background = color.surfaceHover;
      border = color.lineStrong;
    } else {
      background = color.surfaceWell;
      border = color.lineStrong;
    }

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
            color: background,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(color: border, width: tokens.border.hairline),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
