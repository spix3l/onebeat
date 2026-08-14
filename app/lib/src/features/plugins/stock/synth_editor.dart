// SynthStockEditor — built-in subtractive synthesizer editor (UI-C-11 / UI-D-08).
import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../ui_kit/knob.dart';

class SynthStockEditor extends StatelessWidget {
  const SynthStockEditor({
    this.cutoff = 0.75,
    this.resonance = 0.3,
    this.attack = 0.05,
    this.decay = 0.3,
    this.sustain = 0.8,
    this.release = 0.4,
    this.onCutoffChanged,
    this.onResonanceChanged,
    this.onAttackChanged,
    this.onDecayChanged,
    this.onSustainChanged,
    this.onReleaseChanged,
    super.key,
  });

  final double cutoff;
  final double resonance;
  final double attack;
  final double decay;
  final double sustain;
  final double release;
  final ValueChanged<double>? onCutoffChanged;
  final ValueChanged<double>? onResonanceChanged;
  final ValueChanged<double>? onAttackChanged;
  final ValueChanged<double>? onDecayChanged;
  final ValueChanged<double>? onSustainChanged;
  final ValueChanged<double>? onReleaseChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      padding: EdgeInsets.all(tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('FILTER & TONE', style: tokens.type.label),
          SizedBox(height: tokens.spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'CUTOFF',
                    value: cutoff,
                    onChanged: onCutoffChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(cutoff * 20000).toInt()} Hz', style: tokens.type.numericSmall),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'RESO',
                    value: resonance,
                    onChanged: onResonanceChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(resonance * 100).toInt()} %', style: tokens.type.numericSmall),
                ],
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
            child: Container(
              height: tokens.border.hairline,
              color: tokens.color.line,
            ),
          ),
          Text('AMPLITUDE ENVELOPE', style: tokens.type.label),
          SizedBox(height: tokens.spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'ATTACK',
                    value: attack,
                    onChanged: onAttackChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(attack * 1000).toInt()} ms', style: tokens.type.numericSmall),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'DECAY',
                    value: decay,
                    onChanged: onDecayChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(decay * 1000).toInt()} ms', style: tokens.type.numericSmall),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'SUSTAIN',
                    value: sustain,
                    onChanged: onSustainChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(sustain * 100).toInt()} %', style: tokens.type.numericSmall),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ObKnob(
                    label: 'RELEASE',
                    value: release,
                    onChanged: onReleaseChanged,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text('${(release * 2000).toInt()} ms', style: tokens.type.numericSmall),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
