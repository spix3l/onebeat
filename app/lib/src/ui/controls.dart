// Chrome controls, built from tokens only.
//
// These are deliberately not Material widgets: Material would bring its own
// colours, ripples and focus theme, and the first literal colour in the app
// would arrive through a default rather than a decision (FR-UX-02).
//
// Focus policy (FR-UX-24): controls are focusable and activate on Enter, never
// on Space. Space belongs to the transport, everywhere, always — including
// right after clicking a button.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'icons.dart';

/// A square icon-only button: dialog closes, row removals, small toolbar
/// affordances. Text-labelled `✕` buttons were doing this job and rendering as
/// a heavy multiplication sign in the middle of a 44px-wide control.
class IconButtonSmall extends StatefulWidget {
  const IconButtonSmall({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.bordered = true,
    super.key,
  });

  final OneBeatIconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool bordered;

  @override
  State<IconButtonSmall> createState() => _IconButtonSmallState();
}

class _IconButtonSmallState extends State<IconButtonSmall> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: tokens.size.controlHeight,
            height: tokens.size.controlHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered && enabled
                  ? tokens.color.surfaceOverlay
                  : widget.bordered
                  ? tokens.color.surfaceRaised
                  : tokens.color.none,
              borderRadius: tokens.radius.controlBorder,
              border: widget.bordered
                  ? Border.all(
                      color: tokens.color.line,
                      width: tokens.border.hairline,
                    )
                  : null,
            ),
            child: OneBeatIcon(
              widget.icon,
              size: tokens.size.iconSize,
              color: enabled ? tokens.color.textPrimary : tokens.color.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

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
            ? tokens.color.surfaceOverlay
            : tokens.color.surfaceRaised;
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

/// A small labelled toggle: lane mute/solo/collapse, loop mode, clip mute.
///
/// Always shows its label. An icon-only toggle would be denser, but "what does
/// this letter mean" is precisely the confusion D-M4 is trying to avoid between
/// the lane's event gate and the mixer's audio mute.
class OneBeatToggle extends StatefulWidget {
  const OneBeatToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
    this.activeColor,
    this.compact = false,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;
  final Color? activeColor;
  final bool compact;

  @override
  State<OneBeatToggle> createState() => _OneBeatToggleState();
}

class _OneBeatToggleState extends State<OneBeatToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = widget.onChanged != null;
    final Color active = widget.activeColor ?? tokens.color.accent;
    final Color background = widget.value
        ? active
        : _hovered
        ? tokens.color.surfaceOverlay
        : tokens.color.surfaceRaised;

    return Semantics(
      button: true,
      toggled: widget.value,
      enabled: enabled,
      label: widget.tooltip ?? widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: Container(
            height: widget.compact
                ? tokens.size.clipBadgeHeight
                : tokens.size.controlHeight,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? tokens.spacing.xs : tokens.spacing.sm,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: widget.value ? active : tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            child: Text(
              widget.label,
              style: tokens.type.labelDense.copyWith(
                color: !enabled
                    ? tokens.color.textMuted
                    : widget.value
                    ? tokens.color.surfaceDeep
                    : tokens.color.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A select rendered as a button that opens a list beneath itself.
///
/// Built on [OverlayPortal] rather than Material's popup so that no Material
/// colour can leak in, and so the closed state is a plain token-styled control
/// that reads as part of the chrome (FR-UX-02).
class OneBeatSelect<T> extends StatefulWidget {
  const OneBeatSelect({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.prefix = '',
    this.minWidth,
    super.key,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// A quiet leading word, e.g. `SNAP` or `SCALE`, so the control says what it
  /// controls without a separate label widget beside it.
  final String prefix;
  final double? minWidth;

  @override
  State<OneBeatSelect<T>> createState() => _OneBeatSelectState<T>();
}

class _OneBeatSelectState<T> extends State<OneBeatSelect<T>> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (BuildContext context) => Stack(
          children: <Widget>[
            // A full-screen dismiss target: clicking anywhere else closes the
            // list, which is what every other menu on the platform does.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _portal.hide,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: Offset(0, tokens.spacing.xs),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  constraints: BoxConstraints(
                    minWidth:
                        widget.minWidth ?? tokens.size.controlMinWidth * 2,
                  ),
                  padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
                  decoration: BoxDecoration(
                    color: tokens.color.surfaceOverlay,
                    borderRadius: tokens.radius.panelBorder,
                    border: Border.all(
                      color: tokens.color.line,
                      width: tokens.border.hairline,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final T option in widget.options)
                        _SelectRow<T>(
                          label: widget.labelOf(option),
                          selected: option == widget.value,
                          onTap: () {
                            _portal.hide();
                            widget.onChanged(option);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _portal.toggle,
            child: Container(
              height: tokens.size.controlHeight,
              constraints: BoxConstraints(
                minWidth: widget.minWidth ?? tokens.size.controlMinWidth,
              ),
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
              decoration: BoxDecoration(
                color: _hovered
                    ? tokens.color.surfaceOverlay
                    : tokens.color.surfaceRaised,
                borderRadius: tokens.radius.controlBorder,
                border: Border.all(
                  color: tokens.color.line,
                  width: tokens.border.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.prefix.isNotEmpty) ...<Widget>[
                    Text(widget.prefix, style: tokens.type.label),
                    SizedBox(width: tokens.spacing.xs),
                  ],
                  Text(
                    widget.labelOf(widget.value),
                    style: tokens.type.labelDense.copyWith(
                      color: tokens.color.textPrimary,
                    ),
                  ),
                  SizedBox(width: tokens.spacing.xs),
                  OneBeatIcon(
                    OneBeatIconData.chevronDown,
                    size: tokens.size.tagHeight,
                    color: tokens.color.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectRow<T> extends StatefulWidget {
  const _SelectRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SelectRow<T>> createState() => _SelectRowState<T>();
}

class _SelectRowState<T> extends State<_SelectRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: tokens.size.patternRowHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          alignment: Alignment.centerLeft,
          color: _hovered ? tokens.color.accent : null,
          child: Text(
            widget.label,
            style: tokens.type.body.copyWith(
              color: _hovered
                  ? tokens.color.surfaceDeep
                  : widget.selected
                  ? tokens.color.textPrimary
                  : tokens.color.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A numeric value with decrement and increment buttons, for the clip
/// inspector. The value is Martian Mono so it does not jitter as it changes
/// (D10), and the buttons exist so every field is reachable by mouse alone.
class OneBeatStepper extends StatelessWidget {
  const OneBeatStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.minimum,
    this.maximum,
    this.step = 1,
    this.suffix = '',
    super.key,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int? minimum;
  final int? maximum;
  final int step;
  final String suffix;

  bool get _canDecrease => minimum == null || value - step >= minimum!;
  bool get _canIncrease => maximum == null || value + step <= maximum!;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Semantics(
      label: '$label, $value$suffix',
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: tokens.type.label)),
          _StepButton(
            glyph: '−',
            onPressed: _canDecrease ? () => onChanged(value - step) : null,
            semanticLabel: 'Decrease $label',
          ),
          SizedBox(width: tokens.spacing.xs),
          SizedBox(
            width: tokens.size.parameterValueWidth * 0.5,
            child: Text(
              '$value$suffix',
              textAlign: TextAlign.center,
              style: tokens.type.numeric,
            ),
          ),
          SizedBox(width: tokens.spacing.xs),
          _StepButton(
            glyph: '+',
            onPressed: _canIncrease ? () => onChanged(value + step) : null,
            semanticLabel: 'Increase $label',
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.glyph,
    required this.onPressed,
    required this.semanticLabel,
  });

  final String glyph;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: tokens.size.iconSize * 1.4,
          height: tokens.size.iconSize * 1.4,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.color.surfaceRaised,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
          ),
          child: Text(
            glyph,
            style: tokens.type.labelDense.copyWith(
              color: enabled ? tokens.color.textPrimary : tokens.color.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A colour swatch row for pattern and lane colours. Uses the shared instrument
/// palette so a project's colours stay a family rather than a free-for-all.
class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Wrap(
      spacing: tokens.spacing.xs,
      runSpacing: tokens.spacing.xs,
      children: <Widget>[
        for (final String hex in instrumentPalette)
          Semantics(
            button: true,
            selected: hex == selected,
            label: 'Colour $hex',
            child: GestureDetector(
              onTap: () => onChanged(hex),
              child: Container(
                width: tokens.size.swatchSize,
                height: tokens.size.swatchSize,
                decoration: BoxDecoration(
                  color: projectColor(hex, tokens.color.accent),
                  borderRadius: BorderRadius.all(tokens.radius.sm),
                  border: Border.all(
                    color: hex == selected
                        ? tokens.color.textPrimary
                        : tokens.color.line,
                    width: hex == selected
                        ? tokens.border.emphasis
                        : tokens.border.hairline,
                  ),
                ),
              ),
            ),
          ),
      ],
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
    text: widget.tempo.toStringAsFixed(2),
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
      _controller.text = widget.tempo.toStringAsFixed(2);
    }
  }

  void _commit() {
    final double? parsed = double.tryParse(
      _controller.text.replaceAll(',', '.'),
    );
    if (parsed == null) {
      _controller.text = widget.tempo.toStringAsFixed(2);
      return;
    }
    final double clamped = parsed.clamp(20.0, 999.0);
    _controller.text = clamped.toStringAsFixed(2);
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
      // No border of its own: the field sits *inside* a ReadoutWell, and two
      // nested outlines is what made the top bar read as boxes-in-boxes rather
      // than as the design's single recessed well. The accent underline is what
      // says "editing" instead.
      child: Container(
        width: measureText(tokens.type.numericLarge, '888.88'),
        height: tokens.size.controlHeight,
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _editing ? tokens.color.accent : tokens.color.none,
              width: tokens.border.emphasis,
            ),
          ),
        ),
        child: EditableText(
          controller: _controller,
          focusNode: _focusNode,
          style: tokens.type.numericLarge,
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

/// Rotary knob control for plugin parameters and mixer sends.
class OneBeatKnob extends StatefulWidget {
  const OneBeatKnob({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.defaultValue = 0.5,
    this.unit = '',
    this.displayValue,
    super.key,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double defaultValue;
  final String unit;
  final String? displayValue;

  @override
  State<OneBeatKnob> createState() => _OneBeatKnobState();
}

class _OneBeatKnobState extends State<OneBeatKnob> {
  double _dragStartY = 0.0;
  double _dragStartValue = 0.0;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double normalized = ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0); // token-lint-ok: math
    final String valStr = widget.displayValue ?? '${widget.value.toStringAsFixed(widget.value.abs() < 10 ? 1 : 0)}${widget.unit}';

    return GestureDetector(
      onDoubleTap: () => widget.onChanged(widget.defaultValue),
      onVerticalDragStart: (DragStartDetails details) {
        _dragStartY = details.localPosition.dy;
        _dragStartValue = widget.value;
      },
      onVerticalDragUpdate: (DragUpdateDetails details) {
        final double deltaY = _dragStartY - details.localPosition.dy;
        final double range = widget.max - widget.min;
        final double deltaVal = (deltaY / 100.0) * range; // token-lint-ok: drag sensitivity
        final double next = (_dragStartValue + deltaVal).clamp(widget.min, widget.max);
        widget.onChanged(next);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(widget.label.toUpperCase(), style: tokens.type.knobLabel),
          SizedBox(height: tokens.spacing.xxs),
          SizedBox(
            width: tokens.size.knobMedium,
            height: tokens.size.knobMedium,
            child: CustomPaint(
              painter: _KnobPainter(
                normalized: normalized,
                tokens: tokens,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.xxs),
          Text(valStr, style: tokens.type.knobValue),
        ],
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({
    required this.normalized,
    required this.tokens,
  });

  final double normalized;
  final OneBeatTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2); // token-lint-ok: center
    final double radius = (size.width / 2) - tokens.border.emphasis; // token-lint-ok: radius

    final Paint trackPaint = Paint()
      ..color = tokens.color.knobTrack
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.emphasis;

    final Paint bodyPaint = Paint()
      ..color = tokens.color.surfacePanel
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, bodyPaint);
    canvas.drawCircle(center, radius, trackPaint);

    // Angle from -135 deg to +135 deg (270 deg span)
    const double startAngle = 0.75 * 3.141592653589793; // token-lint-ok: radian math
    const double sweepAngle = 1.5 * 3.141592653589793; // token-lint-ok: radian math
    final double currentAngle = startAngle + normalized * sweepAngle; // token-lint-ok: angle

    final Paint activePaint = Paint()
      ..color = tokens.color.knobIndicator
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.emphasis
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      normalized * sweepAngle, // token-lint-ok: arc sweep
      false,
      activePaint,
    );

    // Indicator line
    final Offset indicatorEnd = Offset(
      center.dx + (radius - tokens.spacing.xs) * math.cos(currentAngle), // token-lint-ok: trig
      center.dy + (radius - tokens.spacing.xs) * math.sin(currentAngle), // token-lint-ok: trig
    );
    final Offset indicatorStart = Offset(
      center.dx + (radius * 0.4) * math.cos(currentAngle), // token-lint-ok: trig
      center.dy + (radius * 0.4) * math.sin(currentAngle), // token-lint-ok: trig
    );

    final Paint indicatorPaint = Paint()
      ..color = tokens.color.knobIndicator
      ..strokeWidth = tokens.border.emphasis
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(indicatorStart, indicatorEnd, indicatorPaint);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) => oldDelegate.normalized != normalized;
}

/// Linear vertical fader for mixer tracks.
class OneBeatLinearFader extends StatelessWidget {
  const OneBeatLinearFader({
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double normalized = ((value - min) / (max - min)).clamp(0.0, 1.0); // token-lint-ok: math

    return SizedBox(
      width: tokens.size.faderWidth,
      height: tokens.size.faderHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (DragUpdateDetails details) {
          final RenderBox box = context.findRenderObject()! as RenderBox;
          final Offset local = box.globalToLocal(details.globalPosition);
          final double fraction = (1.0 - (local.dy / tokens.size.faderHeight)).clamp(0.0, 1.0); // token-lint-ok: fraction
          onChanged(min + fraction * (max - min));
        },
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Fader groove
            Container(
              width: tokens.spacing.xs,
              height: tokens.size.faderHeight,
              decoration: BoxDecoration(
                color: tokens.color.faderTrack,
                borderRadius: tokens.radius.controlBorder,
              ),
            ),
            // Fader thumb
            Positioned(
              bottom: normalized * (tokens.size.faderHeight - tokens.size.faderThumbHeight), // token-lint-ok: positioning
              child: Container(
                width: tokens.size.faderThumbWidth,
                height: tokens.size.faderThumbHeight,
                decoration: BoxDecoration(
                  color: tokens.color.faderThumb,
                  borderRadius: tokens.radius.controlBorder,
                  border: Border.all(
                    color: tokens.color.line,
                    width: tokens.border.hairline,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: tokens.spacing.md,
                  height: tokens.border.emphasis,
                  color: tokens.color.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Styled checkbox control.
class OneBeatCheckbox extends StatelessWidget {
  const OneBeatCheckbox({
    required this.value,
    required this.onChanged,
    this.label = '',
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: tokens.size.checkboxSize,
            height: tokens.size.checkboxSize,
            decoration: BoxDecoration(
              color: value ? tokens.color.accent : tokens.color.surfaceDeep,
              borderRadius: BorderRadius.all(tokens.radius.sm),
              border: Border.all(
                color: value ? tokens.color.accent : tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            alignment: Alignment.center,
            child: value
                ? OneBeatIcon(
                    OneBeatIconData.check,
                    size: tokens.size.checkboxSize,
                    color: tokens.color.surfaceSunken,
                  )
                : null,
          ),
          if (label.isNotEmpty) ...<Widget>[
            SizedBox(width: tokens.spacing.sm),
            Text(label, style: tokens.type.body),
          ],
        ],
      ),
    );
  }
}

/// Segmented radio/toggle buttons group.
class OneBeatSegmentedControl<T> extends StatelessWidget {
  const OneBeatSegmentedControl({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.subtitleOf,
    super.key,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final T option in options)
          Padding(
            padding: EdgeInsets.only(right: tokens.spacing.xs),
            child: GestureDetector(
              onTap: () => onChanged(option),
              child: Container(
                height: tokens.size.controlHeight,
                padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
                decoration: BoxDecoration(
                  color: option == value
                      ? tokens.color.surfaceOverlay
                      : tokens.color.surfaceRaised,
                  borderRadius: tokens.radius.controlBorder,
                  border: Border.all(
                    color: option == value
                        ? tokens.color.accent
                        : tokens.color.line,
                    width: option == value
                        ? tokens.border.emphasis
                        : tokens.border.hairline,
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      labelOf(option),
                      style: tokens.type.labelDense.copyWith(
                        color: option == value
                            ? tokens.color.textPrimary
                            : tokens.color.textMuted,
                      ),
                    ),
                    if (subtitleOf != null) ...<Widget>[
                      SizedBox(width: tokens.spacing.xs),
                      Text(
                        subtitleOf!(option),
                        style: tokens.type.numericSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

