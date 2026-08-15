// ObFloatingWindow — the chrome around a torn-off panel (UI-B-11 §5).
//
// A detached panel is a real OS window, so the close/minimise/zoom buttons are
// the system's and stay the system's: we do not draw them, we make room for
// them. The window is configured with a full-size content view (see
// MainFlutterWindow.swift), which puts the real controls *inside* this header —
// so the header reserves [SizeTokens.titleBarInset] at its left and starts the
// title after it. That inset is the same one the top chrome uses, which is why
// a detached Mixer's title lines up with the main window's brand mark.
//
// What we own is the frame: radius, hairline, shadow, the title and subtitle,
// and the app's own header buttons at the right.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'kit_glyphs.dart';

/// A header button the app owns, at the right of the title bar.
@immutable
class ObWindowAction {
  const ObWindowAction({required this.icon, this.onTap, this.tooltip});

  final ObKitGlyphKind icon;
  final VoidCallback? onTap;

  /// Not rendered here — carried so Phase D can attach one without changing
  /// the vm shape.
  final String? tooltip;
}

@immutable
class ObFloatingWindowVm {
  const ObFloatingWindowVm({
    required this.title,
    this.subtitle,
    this.actions = const <ObWindowAction>[],
  });

  /// `Mixer` — the panel's own name, not the document's.
  final String title;

  /// The dim `· Drums Bus selected` beside it: what the panel is currently
  /// pointed at, which is the thing you need when the panel is off on its own
  /// and no longer sitting next to its context.
  final String? subtitle;

  final List<ObWindowAction> actions;
}

class ObFloatingWindow extends StatelessWidget {
  /// A torn-off workspace panel (`screens/workspace-window.png`).
  const ObFloatingWindow.panel({
    required this.vm,
    required this.child,
    this.width,
    this.height,
    this.onDragUpdate,
    super.key,
  }) : reserveSystemControls = true;

  /// A window drawn inside the app's own canvas rather than by the OS — the
  /// plugin editor in `screens/plugin-float.png`, which floats over the
  /// document and therefore has no system controls to make room for.
  const ObFloatingWindow.plugin({
    required this.vm,
    required this.child,
    this.width,
    this.height,
    this.onDragUpdate,
    super.key,
  }) : reserveSystemControls = false;

  final ObFloatingWindowVm vm;
  final Widget child;
  final double? width;
  final double? height;
  final ValueChanged<Offset>? onDragUpdate;

  /// Leaves [SizeTokens.titleBarInset] clear at the header's left for the
  /// system's close/minimise/zoom buttons.
  final bool reserveSystemControls;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? subtitle = vm.subtitle;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.surfacePanel,
        borderRadius: BorderRadius.all(tokens.radius.xl),
        border: Border.all(
          color: color.lineStrong,
          width: tokens.border.hairline,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.windowShadow,
            blurRadius: tokens.size.windowShadowBlur,
            offset: Offset(0, tokens.size.windowShadowOffset),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(tokens.radius.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              height: tokens.size.windowHeaderHeight,
              padding: EdgeInsets.only(right: tokens.spacing.sm),
              decoration: BoxDecoration(
                color: color.surfaceRaised,
                border: Border(
                  bottom: BorderSide(
                    color: color.line,
                    width: tokens.border.hairline,
                  ),
                ),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate:
                    onDragUpdate == null
                        ? null
                        : (DragUpdateDetails details) =>
                            onDragUpdate!(details.delta),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width:
                          reserveSystemControls
                              ? tokens.size.titleBarInset
                              : tokens.spacing.md,
                    ),
                    Text(vm.title, style: tokens.type.windowTitle),
                    if (subtitle != null) ...<Widget>[
                      SizedBox(width: tokens.spacing.sm),
                      Flexible(
                        child: Text(
                          '· $subtitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.type.windowSubtitle,
                        ),
                      ),
                    ],
                    const Spacer(),
                    for (final ObWindowAction action in vm.actions)
                      _HeaderButton(action: action),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatefulWidget {
  const _HeaderButton({required this.action});

  final ObWindowAction action;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = widget.action.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.action.onTap,
        child: Container(
          width: tokens.size.windowIconButton,
          height: tokens.size.windowIconButton,
          margin: EdgeInsets.only(left: tokens.spacing.xs),
          decoration: BoxDecoration(
            color: _hover && enabled ? tokens.color.surfaceHover : null,
            borderRadius: BorderRadius.all(tokens.radius.sm),
          ),
          child: Center(
            child: ObKitGlyph(
              kind: widget.action.icon,
              color: tokens.color.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
