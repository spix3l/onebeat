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
  OverlayEntry? _entry;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _remove();
    super.dispose();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _schedule() {
    _timer?.cancel();
    final Duration delay =
        widget.waitDuration ?? OneBeatTheme.of(context).motion.tooltipDelay;
    _timer = Timer(delay, _show);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _remove();
  }

  void _show() {
    if (!mounted || _entry != null) return;
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    _entry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        // Anchored below the control and centred on it. `followerAnchor`
        // does the centring, so a long label grows both ways rather than
        // running off the right edge of a toolbar.
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
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _schedule(),
        onExit: (_) => _hide(),
        child: widget.child,
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
