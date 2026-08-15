// SamplerStockEditor — built-in sampler editor (UI-C-11 / UI-D-08).
import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../ui_kit/button.dart';
import '../../../ui_kit/knob.dart';

class SamplerStockEditor extends StatelessWidget {
  const SamplerStockEditor({
    this.sampleName,
    this.pitch = 0.5,
    this.startOffset = 0.0,
    this.attack = 0.0,
    this.decay = 0.25,
    this.sustain = 1.0,
    this.release = 0.25,
    this.reverse = false,
    this.onPitchChanged,
    this.onStartOffsetChanged,
    this.onAttackChanged,
    this.onDecayChanged,
    this.onSustainChanged,
    this.onReleaseChanged,
    this.onReverseToggle,
    super.key,
  });

  final String? sampleName;
  final double pitch;
  final double startOffset;
  final double attack;
  final double decay;
  final double sustain;
  final double release;
  final bool reverse;
  final ValueChanged<double>? onPitchChanged;
  final ValueChanged<double>? onStartOffsetChanged;
  final ValueChanged<double>? onAttackChanged;
  final ValueChanged<double>? onDecayChanged;
  final ValueChanged<double>? onSustainChanged;
  final ValueChanged<double>? onReleaseChanged;
  final VoidCallback? onReverseToggle;

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
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md, vertical: tokens.spacing.sm),
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
            ),
            child: Text(sampleName ?? '808_Kick_Punchy.wav', style: tokens.type.numeric),
          ),
          SizedBox(height: tokens.spacing.lg),
          _ControlRow(
            controls: <Widget>[
              _KnobValue(
                label: 'TUNE',
                value: pitch,
                text: '${((pitch - 0.5) * 24).toStringAsFixed(1)} st',
                onChanged: onPitchChanged,
              ),
              _KnobValue(
                label: 'START',
                value: startOffset,
                text: '${(startOffset * 100).toInt()} %',
                onChanged: onStartOffsetChanged,
              ),
              _KnobValue(
                label: 'ATTACK',
                value: attack,
                text: '${(attack * 1000).toInt()} ms',
                onChanged: onAttackChanged,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.lg),
          _ControlRow(
            controls: <Widget>[
              _KnobValue(label: 'DECAY', value: decay, text: '${(decay * 1000).toInt()} ms', onChanged: onDecayChanged),
              _KnobValue(
                label: 'SUSTAIN',
                value: sustain,
                text: '${(sustain * 100).toInt()} %',
                onChanged: onSustainChanged,
              ),
              _KnobValue(
                label: 'RELEASE',
                value: release,
                text: '${(release * 2000).toInt()} ms',
                onChanged: onReleaseChanged,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.lg),
          ObButton(label: reverse ? 'REVERSE: ON' : 'REVERSE: OFF', onTap: onReverseToggle),
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.controls});
  final List<Widget> controls;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: controls);
}

class _KnobValue extends StatelessWidget {
  const _KnobValue({required this.label, required this.value, required this.text, this.onChanged});
  final String label;
  final double value;
  final String text;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ObKnob(label: label, value: value, onChanged: onChanged),
        SizedBox(height: tokens.spacing.xxs),
        Text(text, style: tokens.type.numericSmall),
      ],
    );
  }
}
