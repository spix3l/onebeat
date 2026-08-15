// RenameChannelDialog — the small modal that renames a rack channel.
//
// The RenameProjectDialog sibling worries about bundles and file names on disk;
// a channel has none of that, so this is the same shape with the disk talk
// removed: a field, a one-line consequence, and two buttons.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';

class RenameChannelDialog extends StatefulWidget {
  const RenameChannelDialog({
    required this.initialName,
    required this.onSubmit,
    required this.onClose,
    this.title = 'Rename channel',
    this.fieldLabel = 'Channel name',
    super.key,
  });

  final String initialName;

  /// Fired with the trimmed name when the user confirms.
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;
  final String title;
  final String fieldLabel;

  @override
  State<RenameChannelDialog> createState() => _RenameChannelDialogState();
}

class _RenameChannelDialogState extends State<RenameChannelDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
    _focusNode = FocusNode(debugLabel: 'rename-channel');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _typed => _controller.text.trim();

  bool get _valid => _typed.isNotEmpty;

  void _submit() {
    if (!_valid) return;
    widget.onSubmit(_typed);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool valid = _valid;

    return Container(
      color: color.canvasScrim,
      alignment: Alignment.center,
      child: Container(
        width: tokens.size.modalWidthMedium,
        decoration: BoxDecoration(
          color: color.surfacePanel,
          borderRadius: tokens.radius.panelBorder,
          border: Border.all(color: color.line, width: tokens.border.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DialogHeader(title: widget.title, onClose: widget.onClose),
            Padding(
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.fieldLabel, style: tokens.type.microCaps),
                  SizedBox(height: tokens.spacing.xs),
                  _NameField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    onCancel: widget.onClose,
                  ),
                  SizedBox(height: tokens.spacing.sm),
                  Text(
                    valid ? 'Applies everywhere this channel appears.' : 'Give the channel a name.',
                    style: tokens.type.label.copyWith(color: valid ? color.textMuted : color.danger),
                  ),
                  SizedBox(height: tokens.spacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      ObButton(label: 'Cancel', onTap: widget.onClose),
                      SizedBox(width: tokens.spacing.sm),
                      ObButton(label: 'Rename', tone: ObButtonTone.primary, onTap: valid ? _submit : null),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field itself. [EditableText] rather than Material's `TextField`, as
/// everywhere else in the app: OneBeat owns its chrome.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      height: tokens.size.buttonHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color.surfaceWell,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.lineStrong, width: tokens.border.hairline),
      ),
      // Escape closes from the field, which is where the keyboard is. Without
      // it the only way out of a modal with focus in a text box is the mouse.
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent()},
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                onCancel();
                return null;
              },
            ),
          },
          child: EditableText(
            controller: controller,
            focusNode: focusNode,
            style: tokens.type.body,
            cursorColor: color.accent,
            selectionColor: color.accentMuted,
            backgroundCursorColor: color.surfaceWell,
            maxLines: 1,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return Container(
      height: tokens.size.dialogHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color.line, width: tokens.border.hairline))),
      child: Row(
        children: <Widget>[
          Text(title, style: tokens.type.dialogTitle),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ObKitGlyph(kind: ObKitGlyphKind.close, color: color.textMuted, size: ObKitGlyphSize.inline),
            ),
          ),
        ],
      ),
    );
  }
}
