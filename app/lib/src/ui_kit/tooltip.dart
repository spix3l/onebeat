// ObTooltip — the name of an icon-only control (FR-UX-02).
//
// The app is built on `flutter/widgets`, which does not export Material's
// Tooltip, so the kit owns one. It exists for a specific failure: a row of
// glyph buttons with no labels is unreadable until you have clicked every one
// of them and memorised the result. A glyph may be the *fastest* label once
// learned; it is never the first one.
//
// Hover-only on purpose. This is a pointer-driven desktop app, and a tooltip
// that also fires on tap would fight the control it is describing.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Wraps [child] with a label that appears on hover.
class ObTooltip extends StatefulWidget {
  const ObTooltip({
    required this.message,
    required this.child,
    this.shortcut,
    this.waitDuration,
    super.key,
  });

  /// What the control does, in the imperative ("Erase notes"), not what it is.
  final String message;

  /// Right-aligned in mono next to the message (`⌘1`), when there is one.
  final String? shortcut;

  /// Overrides `tokens.motion.tooltipDelay` — only for a control that has a
  /// reason to be quicker or slower than the rest of the app.
  final Duration? waitDuration;
  final Widget child;

  @override
  State<ObTooltip> createState() => _ObTooltipState();
}

class _ObTooltipState extends State<ObTooltip> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final Duration delay =
        widget.waitDuration ?? OneBeatTheme.of(context).motion.tooltipDelay;
    _timer = Timer(delay, () {
      if (mounted) _portal.show();
    });
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _schedule(),
        onExit: (_) => _hide(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (BuildContext context) {
            final OneBeatTokens tokens = OneBeatTheme.of(context);
            // Anchored under the control and centred on it, so a long label
            // grows both ways rather than off the right edge of a toolbar.
            //
            // The `Align` is load-bearing: an overlay child is laid out against
            // the *whole surface* with tight constraints, so without a
            // shrink-wrap the card stretches to fill the window and the label
            // ends up floating in the middle of the canvas. This is the same
            // shape ObDropdown uses for the same reason.
            // The `Positioned` is what makes the centring correct, and it is
            // easy to lose.
            //
            // An overlay child is laid out with *tight* full-surface
            // constraints. Under those, a shrink-wrapping `Align` is ignored
            // and the follower measures the size of the window — so
            // `followerAnchor: topCenter` shifted the card left by half the
            // screen rather than half the card, and the tooltip appeared
            // hundreds of pixels from the control it named. `Positioned` inside
            // a `Stack` hands down *loose* constraints, so the card measures
            // itself and the anchor maths is about the card.
            return Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  child: CompositedTransformFollower(
                    link: _link,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomCenter,
                    followerAnchor: Alignment.topCenter,
                    offset: Offset(0, tokens.spacing.xs),
                    child: _TooltipCard(
                      message: widget.message,
                      shortcut: widget.shortcut,
                      tokens: tokens,
                    ),
                  ),
                ),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.message,
    required this.shortcut,
    required this.tokens,
  });

  final String message;
  final String? shortcut;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    final ColorTokens color = tokens.color;
    final String? keys = shortcut;
    return IgnorePointer(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.surfaceOverlay,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              maxLines: 1,
              style: tokens.type.label.copyWith(color: color.textPrimary),
            ),
            if (keys != null) ...<Widget>[
              SizedBox(width: tokens.spacing.sm),
              Text(
                keys,
                maxLines: 1,
                style: tokens.type.numericSmall.copyWith(
                  color: color.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
