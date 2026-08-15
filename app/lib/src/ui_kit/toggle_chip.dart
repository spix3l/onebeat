// ObToggleChip — an `M`/`S` mute-solo square (UI-B-01).
//
// Rest is a dim well with a muted letter; on fills with the tone colour and
// drops the letter to the sunken surface so the fill is the signal, not the
// glyph. Danger for mute, amber for solo, per the inspector in
// `screens/export-audio.png`.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Which on-colour a [ObToggleChip] fills with.
enum ObToggleTone { mute, solo }

class ObToggleChip extends StatefulWidget {
  const ObToggleChip({
    required this.tone,
    required this.on,
    this.onTap,
    super.key,
  });

  final ObToggleTone tone;

  /// Whether the control is engaged (muted / soloed).
  final bool on;
  final VoidCallback? onTap;

  @override
  State<ObToggleChip> createState() => _ObToggleChipState();
}

class _ObToggleChipState extends State<ObToggleChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String letter = widget.tone == ObToggleTone.mute ? 'M' : 'S';
    final Color fill = widget.on
        ? (widget.tone == ObToggleTone.mute ? color.danger : color.warning)
        : (_hover && widget.onTap != null ? color.surfaceHover : color.surfaceWell);

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: widget.onTap == null ? null : (_) => setState(() => _hover = true),
      onExit: widget.onTap == null ? null : (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: tokens.size.toggleChipSize,
          height: tokens.size.toggleChipSize,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.all(tokens.radius.sm),
            border: Border.all(
              color: color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: tokens.type.tag.copyWith(
              color: widget.on ? color.surfaceSunken : color.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
