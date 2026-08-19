// ObReadout — the dark inset value boxes of the transport bar (UI-B-02).
//
// BPM, time signature and the bar·beat·tick clock: values you read far more
// often than you set, drawn as recessed wells with large mono numerals and a
// dim micro-caps unit label beneath. Values arrive as text — the vm owns
// formatting, this widget owns only the look.
import 'package:flutter/widgets.dart';

import '../../core/shortcuts.dart';
import '../../design/tokens.dart';

class ObReadout extends StatefulWidget {
  const ObReadout({
    required this.value,
    required this.unit,
    this.onSubmitted,
    super.key,
  });

  /// The value, already formatted (`124.00`, `4/4`, `02:01:218`).
  final String value;

  /// The micro-caps unit label (`BPM`, `SIG`, `BAR · BEAT · TICK`).
  final String unit;

  final ValueChanged<String>? onSubmitted;

  @override
  State<ObReadout> createState() => _ObReadoutState();
}

class _ObReadoutState extends State<ObReadout> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'readout');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_commitOnFocusLoss);
  }

  void _commitOnFocusLoss() {
    if (!_focusNode.hasFocus) widget.onSubmitted?.call(_controller.text);
  }

  @override
  void didUpdateWidget(covariant ObReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text == oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_commitOnFocusLoss);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ValueChanged<String>? onSubmit = widget.onSubmitted;
    return Container(
      height: tokens.size.readoutBoxHeight,
      // No vertical padding: the border and the 21px numerals claim most of
      // the box, so the column centres itself in what remains.
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        // Lift the readouts one step from the bar so the four instruments read
        // as a coherent control group rather than disappearing into chrome.
        color: tokens.color.surfaceColumnHead,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(
          color: tokens.color.lineStrong,
          width: tokens.border.hairline,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          onSubmit == null
              ? Text(widget.value, maxLines: 1, style: tokens.type.readoutValue)
              : SizedBox(
                  width: 92, // token-lint-ok: fixed editable readout width
                  height: 25, // token-lint-ok: fixed editable readout height
                  child: _EditableReadout(
                    controller: _controller,
                    focusNode: _focusNode,
                    onSubmit: onSubmit,
                  ),
                ),
          SizedBox(height: tokens.spacing.xxs),
          Text(widget.unit, maxLines: 1, style: tokens.type.readoutUnit),
        ],
      ),
    );
  }
}

/// The editable readout value.
///
/// Enter commits and hands the keyboard back to the editor — a readout keeps
/// focus after submit, and a field that keeps focus leaves every bare-key
/// shortcut dead until the user clicks the canvas. Escape does the same thing
/// without committing (the value is committed on focus loss anyway).
class _EditableReadout extends StatelessWidget {
  const _EditableReadout({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return escapeReturnsFocus(
      child: EditableText(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: (String value) {
          onSubmit(value);
          FocusPolicy.returnToEditor();
        },
        textAlign: TextAlign.center,
        maxLines: 1,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: tokens.type.readoutValue,
        cursorColor: tokens.color.accentBright,
        backgroundCursorColor: tokens.color.textSecondary,
      ),
    );
  }
}
