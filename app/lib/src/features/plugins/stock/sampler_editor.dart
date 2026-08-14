// SamplerStockEditor — built-in sampler editor (UI-C-11 / UI-D-08).
import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../ui_kit/knob.dart';

class SamplerStockEditor extends StatelessWidget {
  const SamplerStockEditor({
    this.sampleName = '808_Kick_Punchy.wav',
    this.pitch = 0.5,
    this.startOffset = 0.0,
    this.loop = false,
    this.onPitchChanged,
    this.onStartOffsetChanged,
    this.onLoopToggle,
    super.key,
  });

  final String sampleName;
  final double pitch;
  final double startOffset;
  final bool loop;
  final ValueChanged<double>? onPitchChanged;
  final ValueChanged<double>? onStartOffsetChanged;
  final ValueChanged<bool>? onLoopToggle;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      padding: EdgeInsets.all(tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('SAMPLE FILE', style: tokens.type.label),
          SizedBox(height: tokens.spacing.xs),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.md,
              vertical: tokens.spacing.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Text(sampleName, style: tokens.type.numeric),
              ],
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'TUNE',
                    value: pitch,
                    onChanged: onPitchChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${((pitch - 0.5) * 24).toStringAsFixed(1)} st', style: tokens.type.numericSmall),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'START',
                    value: startOffset,
                    onChanged: onStartOffsetChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(startOffset * 100).toInt()} %', style: tokens.type.numericSmall),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
