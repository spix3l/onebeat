// ObClipCard — one block of arrangement (UI-B-08).
//
// The card is the only saturated thing on the playlist canvas, which is the
// whole point: the arrangement is read by colour and shape from across the
// room, and everything around it stays grey so it can be.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

@immutable
class ClipVm {
  const ClipVm({
    required this.id,
    required this.name,
    required this.duration,
    required this.color,
    required this.startBar,
    required this.lengthBars,
    required this.lane,
    this.selected = false,
  });

  final int id;
  final String name;

  /// Already formatted (`0:08`). The vm owns time formatting; the card owns
  /// only the look.
  final String duration;

  /// The clip's identity colour, from `ColorTokens.channelColors`.
  final Color color;

  /// Position and length in bars — fractional, because the mockup's clips do
  /// not all start on a bar line.
  final double startBar;
  final double lengthBars;

  /// Which row the clip sits on, zero-based.
  final int lane;

  final bool selected;
}

class ObClipCard extends StatefulWidget {
  const ObClipCard({required this.vm, this.onTap, super.key});

  final ClipVm vm;
  final VoidCallback? onTap;

  @override
  State<ObClipCard> createState() => _ObClipCardState();
}

class _ObClipCardState extends State<ObClipCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xs,
          ),
          decoration: BoxDecoration(
            color: widget.vm.color,
            borderRadius: BorderRadius.all(tokens.radius.lg),
            border: Border.all(
              // Selection brightens the edge rather than the fill: the fill is
              // the clip's identity and must not change when you click it.
              color:
                  widget.vm.selected
                      ? color.clipSelectedOutline
                      : (_hover ? color.textPrimary : color.none),
              width: tokens.border.emphasis,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.vm.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.type.clipName,
              ),
              Text(
                widget.vm.duration,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: tokens.type.clipDuration,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
