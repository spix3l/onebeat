// ObTagChip — a small mono counter or badge (UI-B-01).
//
// `4 tracks`, `12` — the counts that trail browser folders and list rows.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class ObTagChip extends StatelessWidget {
  const ObTagChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.tagHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs),
      decoration: BoxDecoration(
        color: tokens.color.surfaceOverlay,
        borderRadius: BorderRadius.all(tokens.radius.sm),
      ),
      alignment: Alignment.center,
      child: Text(label, style: tokens.type.numericSmall, maxLines: 1),
    );
  }
}
