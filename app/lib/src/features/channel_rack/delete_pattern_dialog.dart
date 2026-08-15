import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';

class DeletePatternDialog extends StatelessWidget {
  const DeletePatternDialog({
    required this.patternName,
    required this.usageCount,
    required this.onDelete,
    required this.onClose,
    super.key,
  });

  final String patternName;
  final int usageCount;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final String placements = usageCount == 1 ? '1 playlist clip' : '$usageCount playlist clips';

    return ColoredBox(
      color: tokens.color.canvasScrim,
      child: Center(
        child: Container(
          width: tokens.size.modalWidthMedium,
          padding: EdgeInsets.all(tokens.spacing.lg),
          decoration: BoxDecoration(
            color: tokens.color.surfacePanel,
            borderRadius: tokens.radius.panelBorder,
            border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Delete pattern?', style: tokens.type.title),
              SizedBox(height: tokens.spacing.md),
              Text('Delete “$patternName” and its $placements? The playlist clips will also be removed. You can restore this with Undo.', style: tokens.type.body),
              SizedBox(height: tokens.spacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  ObButton(label: 'Cancel', onTap: onClose),
                  SizedBox(width: tokens.spacing.sm),
                  ObButton(label: 'Delete pattern', tone: ObButtonTone.danger, onTap: onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
