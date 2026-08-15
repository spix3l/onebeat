// RenameProjectDialog — the one place a project gets its name (OB-3-05 §4).
//
// Small on purpose: a field, the consequence of typing in it, and two buttons.
// The consequence line is the part that earns the dialog — renaming a saved
// project moves the bundle on disk, and a user should read that before pressing
// Rename rather than discover it in Finder afterwards.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/action_registry.dart';
import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'project_files_platform.dart';
import 'project_store.dart';

class RenameProjectDialog extends StatefulWidget {
  const RenameProjectDialog({
    required this.initialName,
    required this.onSubmit,
    required this.onClose,
    this.currentFileName = '',
    super.key,
  });

  final String initialName;

  /// The bundle the project currently lives in, or empty when it has never
  /// been saved — which changes what renaming actually does.
  final String currentFileName;

  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;

  @override
  State<RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<RenameProjectDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialName.length,
      );
    _focusNode = FocusNode(debugLabel: 'rename-project');
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

  void _submit() {
    if (ProjectStore.validateName(_typed) != null) return;
    widget.onSubmit(_typed);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final String? problem = ProjectStore.validateName(_typed);
    final bool saved = widget.currentFileName.isNotEmpty;

    return Container(
      color: tokens.color.canvasScrim,
      alignment: Alignment.center,
      child: Container(
        width: tokens.size.modalWidthMedium,
        decoration: BoxDecoration(
          color: tokens.color.surfacePanel,
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
            _DialogHeader(title: 'Rename project', onClose: widget.onClose),
            Padding(
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Project name', style: tokens.type.microCaps),
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
                    problem ??
                        (saved
                            ? 'The bundle is renamed to '
                                  '“$_typed.$projectExtension” in the same folder.'
                            : 'Used as the file name the first time you save.'),
                    style: tokens.type.label.copyWith(
                      color:
                          problem == null
                              ? tokens.color.textMuted
                              : tokens.color.danger,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      ObButton(label: 'Cancel', onTap: widget.onClose),
                      SizedBox(width: tokens.spacing.sm),
                      ObButton(
                        key: actionKey('project.rename'),
                        label: 'Rename',
                        tone: ObButtonTone.primary,
                        onTap: problem == null ? _submit : null,
                      ),
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
    return Container(
      height: tokens.size.buttonHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: tokens.color.surfaceWell,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.lineStrong,
          width: tokens.border.hairline,
        ),
      ),
      // Escape closes from the field, which is where the keyboard is. Without
      // it the only way out of a modal with focus in a text box is the mouse.
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.escape):
              const DismissIntent(),
        },
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
            cursorColor: tokens.color.accent,
            backgroundCursorColor: tokens.color.surfaceWell,
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
    return Container(
      height: tokens.size.dialogHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(title, style: tokens.type.dialogTitle),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ObKitGlyph(
                kind: ObKitGlyphKind.close,
                color: tokens.color.textMuted,
                size: ObKitGlyphSize.inline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
