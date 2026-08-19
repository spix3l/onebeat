// SynthStockEditor — a focused, hardware-like editor for OneBeat Drill Synth.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../ui_kit/knob.dart';
import '../typing_keyboard.dart';

class SynthPresetData {
  const SynthPresetData({
    required this.name,
    required this.cutoff,
    required this.resonance,
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
    required this.oscShape,
    required this.oscMix,
    required this.detune,
    required this.sub,
    required this.filterEnv,
    required this.drive,
    required this.delay,
    required this.width,
    required this.output,
    required this.lfoRate,
    required this.lfoDepth,
    required this.glide,
    required this.noise,
  });

  final String name;
  final double cutoff, resonance, attack, decay, sustain, release;
  final double oscShape, oscMix, detune, sub, filterEnv;
  final double drive, delay, width, output, lfoRate, lfoDepth, glide, noise;
}

const List<SynthPresetData> kSynthPresets = <SynthPresetData>[
  SynthPresetData(
    name: 'Drill Sub', cutoff: .15, resonance: .12, attack: .005, decay: .48, sustain: .20, release: .18,
    oscShape: .05, oscMix: .16, detune: .50, sub: .96, filterEnv: .52, drive: .28, delay: .02,
    width: .12, output: .80, lfoRate: .13, lfoDepth: .03, glide: .03, noise: .00,
  ),
  SynthPresetData(
    name: 'Frosted Bell', cutoff: .68, resonance: .22, attack: .002, decay: .18, sustain: .08, release: .20,
    oscShape: .92, oscMix: .68, detune: .54, sub: .18, filterEnv: .35, drive: .08, delay: .25,
    width: .46, output: .72, lfoRate: .26, lfoDepth: .06, glide: .00, noise: .05,
  ),
  SynthPresetData(
    name: 'Dark Pluck', cutoff: .31, resonance: .18, attack: .003, decay: .24, sustain: .06, release: .16,
    oscShape: .10, oscMix: .36, detune: .50, sub: .24, filterEnv: .78, drive: .24, delay: .12,
    width: .28, output: .76, lfoRate: .20, lfoDepth: .04, glide: .00, noise: .01,
  ),
  SynthPresetData(
    name: '808 Glide', cutoff: .12, resonance: .08, attack: .004, decay: .66, sustain: .22, release: .38,
    oscShape: .02, oscMix: .10, detune: .50, sub: .99, filterEnv: .40, drive: .48, delay: .01,
    width: .10, output: .78, lfoRate: .10, lfoDepth: .02, glide: .16, noise: .00,
  ),
  SynthPresetData(
    name: 'Hollow Pad', cutoff: .29, resonance: .20, attack: .34, decay: .64, sustain: .74, release: .70,
    oscShape: .08, oscMix: .72, detune: .62, sub: .42, filterEnv: .64, drive: .10, delay: .34,
    width: .92, output: .62, lfoRate: .24, lfoDepth: .18, glide: .00, noise: .01,
  ),
  SynthPresetData(
    name: 'Cold Keys', cutoff: .48, resonance: .20, attack: .01, decay: .38, sustain: .46, release: .32,
    oscShape: .36, oscMix: .46, detune: .48, sub: .10, filterEnv: .48, drive: .12, delay: .18,
    width: .55, output: .70, lfoRate: .18, lfoDepth: .08, glide: .00, noise: .00,
  ),
  SynthPresetData(
    name: 'Siren Lead', cutoff: .55, resonance: .62, attack: .025, decay: .30, sustain: .62, release: .28,
    oscShape: .18, oscMix: .58, detune: .56, sub: .12, filterEnv: .72, drive: .14, delay: .20,
    width: .64, output: .70, lfoRate: .42, lfoDepth: .18, glide: .05, noise: .01,
  ),
  SynthPresetData(
    name: 'Choir Mist', cutoff: .38, resonance: .16, attack: .46, decay: .70, sustain: .82, release: .88,
    oscShape: .98, oscMix: .50, detune: .50, sub: .26, filterEnv: .74, drive: .04, delay: .52,
    width: .86, output: .58, lfoRate: .16, lfoDepth: .12, glide: .00, noise: .11,
  ),
];

class SynthStockEditor extends StatelessWidget {
  const SynthStockEditor({
    this.preset = 0.0,
    this.oscShape = .08,
    this.oscMix = .35,
    this.detune = .50,
    this.sub = .72,
    this.cutoff = .75,
    this.resonance = .30,
    this.filterEnv = .62,
    this.attack = .05,
    this.decay = .30,
    this.sustain = .80,
    this.release = .40,
    this.drive = .20,
    this.delay = .04,
    this.width = .28,
    this.output = .78,
    this.lfoRate = .18,
    this.lfoDepth = .08,
    this.glide = .00,
    this.noise = .02,
    this.onPresetChanged,
    this.onOscShapeChanged,
    this.onOscMixChanged,
    this.onDetuneChanged,
    this.onSubChanged,
    this.onCutoffChanged,
    this.onResonanceChanged,
    this.onFilterEnvChanged,
    this.onAttackChanged,
    this.onDecayChanged,
    this.onSustainChanged,
    this.onReleaseChanged,
    this.onDriveChanged,
    this.onDelayChanged,
    this.onWidthChanged,
    this.onOutputChanged,
    this.onLfoRateChanged,
    this.onLfoDepthChanged,
    this.onGlideChanged,
    this.onNoiseChanged,
    this.onAuditionNoteOn,
    this.onAuditionNoteOff,
    super.key,
  });

  final double preset;
  final double oscShape, oscMix, detune, sub;
  final double cutoff, resonance, filterEnv;
  final double attack, decay, sustain, release;
  final double drive, delay, width, output;
  final double lfoRate, lfoDepth, glide, noise;
  final ValueChanged<int>? onPresetChanged;
  final ValueChanged<double>? onOscShapeChanged, onOscMixChanged, onDetuneChanged, onSubChanged;
  final ValueChanged<double>? onCutoffChanged, onResonanceChanged, onFilterEnvChanged;
  final ValueChanged<double>? onAttackChanged, onDecayChanged, onSustainChanged, onReleaseChanged;
  final ValueChanged<double>? onDriveChanged, onDelayChanged, onWidthChanged, onOutputChanged;
  final ValueChanged<double>? onLfoRateChanged, onLfoDepthChanged, onGlideChanged, onNoiseChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final void Function(int key)? onAuditionNoteOff;

  int get _presetIndex => (preset * kSynthPresets.length).floor().clamp(0, kSynthPresets.length - 1);

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int index = _presetIndex;
    final SynthPresetData current = kSynthPresets[index];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        border: Border.all(color: tokens.color.lineStrong, width: tokens.border.hairline),
        borderRadius: tokens.radius.panelBorder,
      ),
      child: Column(
        children: <Widget>[
          _SynthHeader(
            current: current,
            index: index,
            onPrevious: onPresetChanged == null
                ? null
                : () => onPresetChanged!((index - 1 + kSynthPresets.length) % kSynthPresets.length),
            onNext: onPresetChanged == null
                ? null
                : () => onPresetChanged!((index + 1) % kSynthPresets.length),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact = constraints.maxWidth < 640;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(tokens.spacing.md),
                  child: Column(
                    children: <Widget>[
                      _SynthHero(
                        compact: compact,
                        preset: current,
                        cutoff: cutoff,
                        resonance: resonance,
                        onCutoff: onCutoffChanged,
                        onResonance: onResonanceChanged,
                      ),
                      SizedBox(height: tokens.spacing.md),
                      _SynthPanel(
                        title: 'OSCILLATORS',
                        meta: 'TWO VOICE / SUB READY',
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: _ShapeSelector(value: oscShape, onChanged: onOscShapeChanged),
                            ),
                            Expanded(child: _ValueKnob(label: 'MIX', value: oscMix, onChanged: onOscMixChanged)),
                            Expanded(child: _ValueKnob(label: 'DETUNE', value: detune, onChanged: onDetuneChanged, display: '${((detune - .5) * 2).toStringAsFixed(1)} ST')),
                            Expanded(child: _ValueKnob(label: 'SUB', value: sub, onChanged: onSubChanged)),
                            Expanded(child: _ValueKnob(label: 'NOISE', value: noise, onChanged: onNoiseChanged)),
                          ],
                        ),
                      ),
                      SizedBox(height: tokens.spacing.md),
                      _SynthPanel(
                        title: 'AMP ENVELOPE',
                        meta: 'TRANSIENT / TAIL',
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: tokens.size.synthHeroHeight - tokens.spacing.md,
                                child: CustomPaint(
                                  painter: _EnvelopePainter(
                                    tokens: tokens,
                                    attack: attack,
                                    decay: decay,
                                    sustain: sustain,
                                    release: release,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(child: _ValueKnob(label: 'ATTACK', value: attack, onChanged: onAttackChanged, display: _seconds(attack, 1.5, .001))),
                            Expanded(child: _ValueKnob(label: 'DECAY', value: decay, onChanged: onDecayChanged, display: _seconds(decay, 2.5, .03))),
                            Expanded(child: _ValueKnob(label: 'SUSTAIN', value: sustain, onChanged: onSustainChanged)),
                            Expanded(child: _ValueKnob(label: 'RELEASE', value: release, onChanged: onReleaseChanged, display: _seconds(release, 4.0, .02))),
                          ],
                        ),
                      ),
                      SizedBox(height: tokens.spacing.md),
                      _SynthPanel(
                        title: 'MOVEMENT / SPACE',
                        meta: 'SUBTLE IS LOUDER',
                        child: Row(
                          children: <Widget>[
                            Expanded(child: _ValueKnob(label: 'FILTER ENV', value: filterEnv, onChanged: onFilterEnvChanged)),
                            Expanded(child: _ValueKnob(label: 'LFO RATE', value: lfoRate, onChanged: onLfoRateChanged, display: '${(.1 + lfoRate * 9.9).toStringAsFixed(1)} HZ')),
                            Expanded(child: _ValueKnob(label: 'LFO DEPTH', value: lfoDepth, onChanged: onLfoDepthChanged)),
                            Expanded(child: _ValueKnob(label: 'GLIDE', value: glide, onChanged: onGlideChanged)),
                            Expanded(child: _ValueKnob(label: 'DRIVE', value: drive, onChanged: onDriveChanged)),
                            Expanded(child: _ValueKnob(label: 'DELAY', value: delay, onChanged: onDelayChanged)),
                            Expanded(child: _ValueKnob(label: 'WIDTH', value: width, onChanged: onWidthChanged)),
                            Expanded(child: _ValueKnob(label: 'OUT', value: output, onChanged: onOutputChanged)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _SynthKeyboard(
            onNoteOn: onAuditionNoteOn,
            onNoteOff: onAuditionNoteOff,
          ),
        ],
      ),
    );
  }

  static String _seconds(double value, double range, double floor) => '${(floor + value * value * range).toStringAsFixed(2)} S';
}

class _SynthHeader extends StatelessWidget {
  const _SynthHeader({required this.current, required this.index, this.onPrevious, this.onNext});

  final SynthPresetData current;
  final int index;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.synthHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        border: Border(bottom: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Container(width: tokens.border.emphasis, height: tokens.size.synthHeaderHeight - tokens.spacing.md, color: tokens.color.accent),
          SizedBox(width: tokens.spacing.sm),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('DRILL//SYNTH', style: tokens.type.brand),
              Text('SAMPLE-FREE · 32 VOICES', style: tokens.type.microCaps),
            ],
          ),
          SizedBox(width: tokens.spacing.xl),
          Expanded(
            child: _PresetDisplay(index: index, current: current, onPrevious: onPrevious, onNext: onNext),
          ),
          SizedBox(width: tokens.spacing.lg),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: tokens.size.statusDotSize, height: tokens.size.statusDotSize, decoration: BoxDecoration(color: tokens.color.accentBright, shape: BoxShape.circle)),
              SizedBox(width: tokens.spacing.xs),
              Text('ACTIVE', style: tokens.type.microCaps.copyWith(color: tokens.color.accentBright)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetDisplay extends StatelessWidget {
  const _PresetDisplay({required this.index, required this.current, this.onPrevious, this.onNext});

  final int index;
  final SynthPresetData current;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.controlHeight + tokens.spacing.sm,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        border: Border.all(color: tokens.color.lineStrong, width: tokens.border.hairline),
        borderRadius: tokens.radius.controlBorder,
      ),
      child: Row(
        children: <Widget>[
          Text('PATCH', style: tokens.type.microCaps.copyWith(color: tokens.color.accentBright)),
          SizedBox(width: tokens.spacing.sm),
          Expanded(child: Text(current.name, style: tokens.type.title, overflow: TextOverflow.ellipsis)),
          Text('${(index + 1).toString().padLeft(2, '0')} / ${kSynthPresets.length.toString().padLeft(2, '0')}', style: tokens.type.numericSmall),
          SizedBox(width: tokens.spacing.sm),
          _HeaderButton(label: '‹', onTap: onPrevious),
          _HeaderButton(label: '›', onTap: onNext),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: tokens.size.controlMinWidth,
        height: tokens.size.controlHeight,
        child: Center(child: Text(label, style: tokens.type.title.copyWith(color: tokens.color.accentBright))),
      ),
    );
  }
}

class _SynthHero extends StatelessWidget {
  const _SynthHero({required this.compact, required this.preset, required this.cutoff, required this.resonance, this.onCutoff, this.onResonance});

  final bool compact;
  final SynthPresetData preset;
  final double cutoff;
  final double resonance;
  final ValueChanged<double>? onCutoff;
  final ValueChanged<double>? onResonance;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Widget trace = _SynthPanel(
      title: 'SIGNAL TRACE',
      meta: 'LIVE SHAPE / FILTER',
      child: CustomPaint(
        painter: _TracePainter(tokens: tokens, shape: preset.oscShape, cutoff: cutoff, resonance: resonance),
      ),
    );
    final Widget filter = _SynthPanel(
      title: 'FILTER',
      meta: 'LOW-PASS / 24 DB',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _LargeDial(label: 'CUTOFF', value: cutoff, display: _cutoff(cutoff), onChanged: onCutoff),
          _LargeDial(label: 'RESONANCE', value: resonance, display: '${(resonance * 100).round()} %', onChanged: onResonance),
        ],
      ),
    );
    if (compact) {
      return Column(children: <Widget>[SizedBox(height: tokens.size.synthHeroHeight, child: trace), SizedBox(height: tokens.spacing.md), filter]);
    }
    return SizedBox(
      height: tokens.size.synthHeroHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[Expanded(flex: 5, child: trace), SizedBox(width: tokens.spacing.md), Expanded(flex: 3, child: filter)],
      ),
    );
  }

  static String _cutoff(double value) {
    final double hz = 35 * math.pow(520, value).toDouble();
    return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} K' : '${hz.round()} HZ';
  }
}

class _SynthPanel extends StatelessWidget {
  const _SynthPanel({required this.title, required this.meta, required this.child});

  final String title;
  final String meta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(tokens.spacing.md, tokens.spacing.sm, tokens.spacing.md, tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
        borderRadius: tokens.radius.panelBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(title, style: tokens.type.sectionHeader),
              const Spacer(),
              Text(meta, style: tokens.type.microCaps),
            ],
          ),
          SizedBox(height: tokens.spacing.md),
          child,
        ],
      ),
    );
  }
}

class _LargeDial extends StatelessWidget {
  const _LargeDial({required this.label, required this.value, required this.display, this.onChanged});

  final String label;
  final double value;
  final String display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onChanged == null ? null : (DragUpdateDetails details) => onChanged!((value - details.delta.dy * .008).clamp(0.0, 1.0)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CustomPaint(size: Size(tokens.size.synthDialSize, tokens.size.synthDialSize), painter: _LargeDialPainter(tokens: tokens, value: value)),
          SizedBox(height: tokens.spacing.sm),
          Text(label, style: tokens.type.microCapsWide),
          SizedBox(height: tokens.spacing.xxs),
          Text(display, style: tokens.type.numericLarge.copyWith(color: tokens.color.accentBright)),
        ],
      ),
    );
  }
}

class _LargeDialPainter extends CustomPainter {
  const _LargeDialPainter({required this.tokens, required this.value});

  final OneBeatTokens tokens;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - tokens.border.emphasis;
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.emphasis
      ..strokeCap = StrokeCap.round
      ..color = tokens.color.lineStrong;
    final Paint active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.emphasis
      ..strokeCap = StrokeCap.round
      ..color = tokens.color.accent;
    final Rect bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(bounds, math.pi * .75, math.pi * 1.5, false, track);
    canvas.drawArc(bounds, math.pi * .75, math.pi * 1.5 * value.clamp(0.0, 1.0), false, active);
    canvas.drawCircle(center, radius - tokens.spacing.sm, Paint()..color = tokens.color.surfaceRaised);
    final double angle = math.pi * .75 + math.pi * 1.5 * value.clamp(0.0, 1.0);
    canvas.drawLine(
      center,
      Offset(center.dx + (radius - tokens.spacing.md) * math.cos(angle), center.dy + (radius - tokens.spacing.md) * math.sin(angle)),
      Paint()
        ..color = tokens.color.accentBright
        ..strokeWidth = tokens.border.emphasis
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LargeDialPainter oldDelegate) => oldDelegate.value != value;
}

class _ValueKnob extends StatelessWidget {
  const _ValueKnob({required this.label, required this.value, this.display, this.onChanged});

  final String label;
  final double value;
  final String? display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ObKnob(value: value, onChanged: onChanged, accent: true),
        SizedBox(height: tokens.spacing.xxs),
        Text(label, style: tokens.type.microCaps, overflow: TextOverflow.ellipsis),
        SizedBox(height: tokens.spacing.xxs),
        Text(display ?? '${(value * 100).round()} %', style: tokens.type.numericSmall.copyWith(color: tokens.color.textPrimary)),
      ],
    );
  }
}

class _ShapeSelector extends StatelessWidget {
  const _ShapeSelector({required this.value, this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  static const List<String> _labels = <String>['SAW', 'SQR', 'TRI', 'SIN'];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int selected = (value * 3).round().clamp(0, 3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int index = 0; index < _labels.length; index++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onChanged == null ? null : () => onChanged!(index / 3),
                  child: Container(
                    height: tokens.size.controlHeight,
                    margin: EdgeInsets.only(right: index == _labels.length - 1 ? 0 : tokens.spacing.xxs),
                    decoration: BoxDecoration(
                      color: index == selected ? tokens.color.accentWash : tokens.color.surfaceSunken,
                      border: Border.all(color: index == selected ? tokens.color.accent : tokens.color.line, width: tokens.border.hairline),
                      borderRadius: tokens.radius.controlBorder,
                    ),
                    child: Center(child: Text(_labels[index], style: tokens.type.microCaps.copyWith(color: index == selected ? tokens.color.accentBright : tokens.color.textMuted))),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.xs),
        Text('WAVEFORM', style: tokens.type.microCaps),
      ],
    );
  }
}

class _TracePainter extends CustomPainter {
  const _TracePainter({required this.tokens, required this.shape, required this.cutoff, required this.resonance});

  final OneBeatTokens tokens;
  final double shape;
  final double cutoff;
  final double resonance;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = tokens.color.line
      ..strokeWidth = tokens.border.hairline;
    for (int index = 1; index < 5; index++) {
      final double y = size.height * index / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (int index = 1; index < 8; index++) {
      final double x = size.width * index / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final Path path = Path();
    final double amplitude = .24 + resonance * .32;
    for (int index = 0; index <= 72; index++) {
      final double x = size.width * index / 72;
      final double phase = index / 72;
      final double sine = math.sin(phase * math.pi * 2);
      final double saw = phase * 2 - 1;
      final double square = phase < .5 ? 1 : -1;
      final double wave = sine * shape + saw * (1 - shape) * .45 + square * (shape < .2 ? .3 : 0);
      final double y = size.height / 2 - wave * size.height * amplitude * (.55 + cutoff * .45);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = tokens.color.accentBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = tokens.border.emphasis
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TracePainter oldDelegate) => oldDelegate.shape != shape || oldDelegate.cutoff != cutoff || oldDelegate.resonance != resonance;
}

class _EnvelopePainter extends CustomPainter {
  const _EnvelopePainter({required this.tokens, required this.attack, required this.decay, required this.sustain, required this.release});

  final OneBeatTokens tokens;
  final double attack, decay, sustain, release;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint guide = Paint()
      ..color = tokens.color.line
      ..strokeWidth = tokens.border.hairline;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), guide);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), guide);

    final double attackX = size.width * (.12 + attack * .18);
    final double decayX = attackX + size.width * (.12 + decay * .18);
    final double releaseX = size.width * (.82 + release * .12).clamp(.82, .98);
    final double sustainY = size.height * (.18 + (1 - sustain) * .60);
    final Path path = Path()
      ..moveTo(0, size.height)
      ..lineTo(attackX, 0)
      ..lineTo(decayX, sustainY)
      ..lineTo(releaseX, sustainY)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = tokens.color.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = tokens.border.emphasis
        ..strokeCap = StrokeCap.round,
    );
    for (final Offset point in <Offset>[
      Offset(attackX, 0),
      Offset(decayX, sustainY),
      Offset(releaseX, sustainY),
    ]) {
      canvas.drawCircle(point, tokens.spacing.xs, Paint()..color = tokens.color.accentBright);
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter oldDelegate) => oldDelegate.attack != attack || oldDelegate.decay != decay || oldDelegate.sustain != sustain || oldDelegate.release != release;
}

class _SynthKeyboard extends StatefulWidget {
  const _SynthKeyboard({this.onNoteOn, this.onNoteOff});

  final void Function(int key, double velocity)? onNoteOn;
  final void Function(int key)? onNoteOff;

  @override
  State<_SynthKeyboard> createState() => _SynthKeyboardState();
}

class _SynthKeyboardState extends State<_SynthKeyboard> {
  static const List<int> _whiteOffsets = <int>[0, 2, 4, 5, 7, 9, 11];
  static const List<int> _blackPositions = <int>[0, 1, 3, 4, 5, 7, 8, 10, 11, 12];
  final Set<int> _held = <int>{};

  /// Pointer-held keys plus the computer keyboard's, which plays the same
  /// instrument and should light the same keys.
  Set<int> _down(BuildContext context) => <int>{..._held, ...TypingKeysScope.of(context)};

  int _whiteKey(int index) => 36 + (index ~/ _whiteOffsets.length) * 12 + _whiteOffsets[index % _whiteOffsets.length];

  void _press(int key, double velocity) {
    setState(() => _held.add(key));
    widget.onNoteOn?.call(key, velocity);
  }

  void _release(int key) {
    if (!_held.contains(key)) return;
    setState(() => _held.remove(key));
    widget.onNoteOff?.call(key);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Set<int> down = _down(context);
    return Container(
      height: tokens.size.synthKeyboardHeight,
      padding: EdgeInsets.fromLTRB(tokens.spacing.md, tokens.spacing.sm, tokens.spacing.md, tokens.spacing.sm),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        border: Border(top: BorderSide(color: tokens.color.line, width: tokens.border.hairline)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          const int whiteCount = 15;
          final double whiteWidth = constraints.maxWidth / whiteCount;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('PREVIEW KEYBOARD', style: tokens.type.microCapsWide),
                  const Spacer(),
                  Text('C2 — D4', style: tokens.type.numericSmall),
                ],
              ),
              SizedBox(height: tokens.spacing.xs),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List<Widget>.generate(whiteCount, (int index) {
                        final int key = _whiteKey(index);
                        final bool held = down.contains(key);
                        return Expanded(
                          child: GestureDetector(
                            onTapDown: (_) => _press(key, .82),
                            onTapUp: (_) => _release(key),
                            onTapCancel: () => _release(key),
                            child: Container(
                              margin: EdgeInsets.only(right: tokens.spacing.xxs),
                              decoration: BoxDecoration(
                                color: held ? tokens.color.accentWash : tokens.color.surfaceRaised,
                                border: Border.all(color: held ? tokens.color.accent : tokens.color.lineStrong, width: tokens.border.hairline),
                                borderRadius: tokens.radius.controlBorder,
                              ),
                              alignment: Alignment.bottomCenter,
                              padding: EdgeInsets.only(bottom: tokens.spacing.xxs),
                              child: index % _whiteOffsets.length == 0
                                  ? Text('C${2 + index ~/ _whiteOffsets.length}', style: tokens.type.microCaps)
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ),
                    for (final int position in _blackPositions)
                      Positioned(
                        left: (position + 1) * whiteWidth - whiteWidth * .28,
                        top: 0,
                        width: whiteWidth * .56,
                        height: tokens.size.synthKeyboardBlackHeight,
                        child: _BlackKey(
                          keyNumber: _whiteKey(position) + 1,
                          held: down.contains(_whiteKey(position) + 1),
                          onPress: _press,
                          onRelease: _release,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BlackKey extends StatelessWidget {
  const _BlackKey({required this.keyNumber, required this.held, required this.onPress, required this.onRelease});

  final int keyNumber;
  final bool held;
  final void Function(int key, double velocity) onPress;
  final void Function(int key) onRelease;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      onTapDown: (_) => onPress(keyNumber, .78),
      onTapUp: (_) => onRelease(keyNumber),
      onTapCancel: () => onRelease(keyNumber),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: held ? tokens.color.accent : tokens.color.surfaceSunken,
          border: Border.all(color: held ? tokens.color.accentBright : tokens.color.lineStrong, width: tokens.border.hairline),
          borderRadius: BorderRadius.vertical(bottom: tokens.radius.controlBorder.bottomLeft),
        ),
      ),
    );
  }
}
