// ObFxChip — an FX-chain or route chip (UI-B-01).
//
// `components/fx-chip.png`: colour dot + label on a 26px well. The mono
// variant renders the label in MartianMono for route chips (`→ D1`); FX
// chips use the UI family. The dot colour is passed in by the caller because
// it is *data* (a channel colour), not chrome.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObFxChip extends StatefulWidget {
  const ObFxChip({
    required this.label,
    required this.dotColor,
    this.mono = false,
    this.active = false,
    this.onTap,
    super.key,
  });

  final String label;

  /// Identity colour of the chain entry — a channel colour from
  /// `ColorTokens.channelColors`, resolved by the caller.
  final Color dotColor;

  /// Route-chip variant: label in the numeric family.
  final bool mono;

  /// The chain entry currently being edited: accent outline over an accent
  /// wash. An outline rather than a fill, because the dot beside the label is
  /// already carrying a colour and two saturated fields in one chip fight.
  final bool active;
  final VoidCallback? onTap;

  @override
  State<ObFxChip> createState() => _ObFxChipState();
}

class _ObFxChipState extends State<ObFxChip> {
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
          height: tokens.size.chipHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
          decoration: BoxDecoration(
            color: widget.active ? color.accentWash : (_hover && enabled ? color.surfaceHover : color.surfaceWell),
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: widget.active ? color.accentBright : color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: tokens.size.chipDotSize,
                height: tokens.size.chipDotSize,
                decoration: BoxDecoration(
                  color: widget.dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                widget.label,
                style: widget.mono
                    ? tokens.type.numericSmall.copyWith(
                        color: color.textPrimary,
                      )
                    : tokens.type.label.copyWith(color: color.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
