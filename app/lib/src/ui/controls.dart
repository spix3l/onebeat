// Chrome controls, built from tokens only.
//
// These are deliberately not Material widgets: Material would bring its own
// colours, ripples and focus theme, and the first literal colour in the app
// would arrive through a default rather than a decision (FR-UX-02).
//
// Focus policy (FR-UX-24): controls are focusable and activate on Enter, never
// on Space. Space belongs to the transport, everywhere, always — including
// right after clicking a button.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class OneBeatButton extends StatefulWidget {
  const OneBeatButton({
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.active = false,
    this.wide = false,
    super.key,
  });

  final String label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final bool active;
  final bool wide;

  @override
  State<OneBeatButton> createState() => _OneBeatButtonState();
}

class _OneBeatButtonState extends State<OneBeatButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = widget.onPressed != null;
    final Color background =
        widget.active && enabled
            ? tokens.color.accent
            : _hovered
            ? tokens.color.surfaceRaised
            : tokens.color.surfacePanel;
    final Color foreground =
        !enabled
            ? tokens.color.textMuted
            : widget.active
            ? tokens.color.surfaceDeep
            : tokens.color.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: FocusableActionDetector(
        onShowHoverHighlight: (bool value) => setState(() => _hovered = value),
        onShowFocusHighlight: (bool value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: tokens.motion.instant,
            curve: tokens.motion.standard,
            height: tokens.size.controlHeight,
            constraints: BoxConstraints(
              minWidth:
                  widget.wide
                      ? tokens.size.controlMinWidth * 2
                      : tokens.size.controlMinWidth,
            ),
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            decoration: BoxDecoration(
              color: background,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: _focused ? tokens.color.accent : tokens.color.line,
                width:
                    _focused
                        ? tokens.size.focusRingWidth
                        : tokens.border.hairline,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: tokens.type.labelDense.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// A numeric field for tempo. Commits on Enter or on losing focus, reverts on
/// Escape, and never lets an unparseable value reach the engine.
class TempoField extends StatefulWidget {
  const TempoField({required this.tempo, required this.onChanged, super.key});

  final double tempo;
  final ValueChanged<double> onChanged;

  @override
  State<TempoField> createState() => _TempoFieldState();
}

class _TempoFieldState extends State<TempoField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.tempo.toStringAsFixed(1),
  );
  final FocusNode _focusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _commit();
      }
      setState(() => _editing = _focusNode.hasFocus);
    });
  }

  @override
  void didUpdateWidget(TempoField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.tempo != oldWidget.tempo) {
      _controller.text = widget.tempo.toStringAsFixed(1);
    }
  }

  void _commit() {
    final double? parsed = double.tryParse(
      _controller.text.replaceAll(',', '.'),
    );
    if (parsed == null) {
      _controller.text = widget.tempo.toStringAsFixed(1);
      return;
    }
    final double clamped = parsed.clamp(20.0, 999.0);
    _controller.text = clamped.toStringAsFixed(1);
    widget.onChanged(clamped);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Semantics(
      label: 'Tempo in beats per minute',
      textField: true,
      child: Container(
        width: tokens.size.controlMinWidth * 1.7,
        height: tokens.size.controlHeight,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: tokens.color.surfacePanel,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: _editing ? tokens.color.accent : tokens.color.line,
            width:
                _editing ? tokens.size.focusRingWidth : tokens.border.hairline,
          ),
        ),
        child: EditableText(
          controller: _controller,
          focusNode: _focusNode,
          style: tokens.type.numeric,
          cursorColor: tokens.color.accent,
          backgroundCursorColor: tokens.color.line,
          selectionColor: tokens.color.accentMuted,
          textAlign: TextAlign.right,
          maxLines: 1,
          keyboardType: TextInputType.number,
          onSubmitted: (_) {
            _commit();
            _focusNode.unfocus();
          },
        ),
      ),
    );
  }
}
