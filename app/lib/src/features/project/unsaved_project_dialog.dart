// UnsavedProjectDialog — protects edits before File > New Project.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';

class UnsavedProjectDialog extends StatelessWidget {
  const UnsavedProjectDialog({
    required this.projectName,
    required this.onSave,
    required this.onDiscard,
    required this.onCancel,
    super.key,
  });

  final String projectName;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
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
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  ObKitGlyph(
                    kind: ObKitGlyphKind.warning,
                    color: tokens.color.warning,
                  ),
                  SizedBox(width: tokens.spacing.sm),
                  Text('Save changes?', style: tokens.type.dialogTitle),
                  const Spacer(),
                  GestureDetector(
                    onTap: onCancel,
                    child: ObKitGlyph(
                      kind: ObKitGlyphKind.close,
                      color: tokens.color.textMuted,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacing.md),
              Text(
                '“$projectName” has unsaved changes. Save it before starting a new project?',
                style: tokens.type.body,
              ),
              SizedBox(height: tokens.spacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  ObButton(label: 'Cancel', onTap: onCancel),
                  SizedBox(width: tokens.spacing.sm),
                  ObButton(
                    label: 'Discard',
                    tone: ObButtonTone.danger,
                    onTap: onDiscard,
                  ),
                  SizedBox(width: tokens.spacing.sm),
                  ObButton(
                    label: 'Save & New',
                    tone: ObButtonTone.primary,
                    onTap: onSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
