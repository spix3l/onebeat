// PianoStockEditor — Stock acoustic & electric piano editor (UI-C-11 / UI-D-08).
import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../ui_kit/knob.dart';

class PianoPresetData {
  const PianoPresetData({
    required this.name,
    required this.description,
    required this.tone,
    required this.body,
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
    required this.hammer,
    required this.damper,
    required this.detune,
    required this.velocitySens,
    required this.room,
    required this.reverbSize,
    required this.modDepth,
    required this.modRate,
    required this.drive,
    required this.width,
    required this.output,
  });

  final String name;
  final String description;
  final double tone;
  final double body;
  final double attack;
  final double decay;
  final double sustain;
  final double release;
  final double hammer;
  final double damper;
  final double detune;
  final double velocitySens;
  final double room;
  final double reverbSize;
  final double modDepth;
  final double modRate;
  final double drive;
  final double width;
  final double output;
}

const List<PianoPresetData> kPianoPresets = <PianoPresetData>[
  PianoPresetData(
    name: 'Concert Grand',
    description: '9-foot acoustic grand with inharmonic string resonance',
    tone: 0.65,
    body: 0.60,
    attack: 0.04,
    decay: 0.60,
    sustain: 0.00,
    release: 0.40,
    hammer: 0.50,
    damper: 0.30,
    detune: 0.20,
    velocitySens: 0.75,
    room: 0.35,
    reverbSize: 0.55,
    modDepth: 0.00,
    modRate: 0.30,
    drive: 0.00,
    width: 0.70,
    output: 0.75,
  ),
  PianoPresetData(
    name: 'Felt Upright',
    description: 'Intimate studio upright with soft felt hammers',
    tone: 0.35,
    body: 0.75,
    attack: 0.08,
    decay: 0.50,
    sustain: 0.00,
    release: 0.35,
    hammer: 0.20,
    damper: 0.55,
    detune: 0.30,
    velocitySens: 0.80,
    room: 0.25,
    reverbSize: 0.40,
    modDepth: 0.00,
    modRate: 0.30,
    drive: 0.05,
    width: 0.60,
    output: 0.80,
  ),
  PianoPresetData(
    name: 'Classic Rhodes',
    description: 'Vintage 70s tines with warm body and bell tone',
    tone: 0.55,
    body: 0.70,
    attack: 0.02,
    decay: 0.70,
    sustain: 0.25,
    release: 0.45,
    hammer: 0.65,
    damper: 0.10,
    detune: 0.15,
    velocitySens: 0.85,
    room: 0.40,
    reverbSize: 0.50,
    modDepth: 0.35,
    modRate: 0.25,
    drive: 0.20,
    width: 0.80,
    output: 0.75,
  ),
  PianoPresetData(
    name: 'FM DX Tines',
    description: '80s digital crystalline FM electric piano',
    tone: 0.80,
    body: 0.40,
    attack: 0.01,
    decay: 0.65,
    sustain: 0.10,
    release: 0.50,
    hammer: 0.80,
    damper: 0.05,
    detune: 0.10,
    velocitySens: 0.90,
    room: 0.50,
    reverbSize: 0.65,
    modDepth: 0.40,
    modRate: 0.40,
    drive: 0.00,
    width: 0.85,
    output: 0.75,
  ),
  PianoPresetData(
    name: 'Vintage Wurlitzer',
    description: 'Classic reed piano with dynamic harmonic bark',
    tone: 0.60,
    body: 0.65,
    attack: 0.02,
    decay: 0.55,
    sustain: 0.15,
    release: 0.30,
    hammer: 0.55,
    damper: 0.20,
    detune: 0.25,
    velocitySens: 0.85,
    room: 0.30,
    reverbSize: 0.45,
    modDepth: 0.50,
    modRate: 0.55,
    drive: 0.35,
    width: 0.75,
    output: 0.75,
  ),
  PianoPresetData(
    name: 'Honky-Tonk',
    description: 'Saloon piano with triple detuned strings',
    tone: 0.75,
    body: 0.55,
    attack: 0.02,
    decay: 0.45,
    sustain: 0.00,
    release: 0.25,
    hammer: 0.85,
    damper: 0.40,
    detune: 0.75,
    velocitySens: 0.70,
    room: 0.20,
    reverbSize: 0.35,
    modDepth: 0.20,
    modRate: 0.60,
    drive: 0.15,
    width: 0.70,
    output: 0.75,
  ),
  PianoPresetData(
    name: 'Dream Cloud',
    description: 'Ambient soundtrack felt piano with lush tail',
    tone: 0.40,
    body: 0.70,
    attack: 0.45,
    decay: 0.85,
    sustain: 0.40,
    release: 0.80,
    hammer: 0.10,
    damper: 0.10,
    detune: 0.35,
    velocitySens: 0.65,
    room: 0.80,
    reverbSize: 0.90,
    modDepth: 0.30,
    modRate: 0.15,
    drive: 0.00,
    width: 0.95,
    output: 0.75,
  ),
  PianoPresetData(
    name: 'Pop Grand',
    description: 'Snappy modern grand with presence and punch',
    tone: 0.85,
    body: 0.50,
    attack: 0.01,
    decay: 0.55,
    sustain: 0.00,
    release: 0.35,
    hammer: 0.75,
    damper: 0.25,
    detune: 0.15,
    velocitySens: 0.80,
    room: 0.35,
    reverbSize: 0.50,
    modDepth: 0.00,
    modRate: 0.30,
    drive: 0.10,
    width: 0.80,
    output: 0.80,
  ),
  PianoPresetData(
    name: 'Harpsichord',
    description: 'Plucked baroque keyboard with bright brilliance',
    tone: 0.90,
    body: 0.30,
    attack: 0.00,
    decay: 0.35,
    sustain: 0.00,
    release: 0.15,
    hammer: 0.95,
    damper: 0.05,
    detune: 0.20,
    velocitySens: 0.10,
    room: 0.30,
    reverbSize: 0.45,
    modDepth: 0.00,
    modRate: 0.30,
    drive: 0.00,
    width: 0.70,
    output: 0.70,
  ),
  PianoPresetData(
    name: 'Synth Keys',
    description: 'Warm analog synthesizer keys with resonant filter',
    tone: 0.65,
    body: 0.60,
    attack: 0.20,
    decay: 0.70,
    sustain: 0.60,
    release: 0.60,
    hammer: 0.10,
    damper: 0.00,
    detune: 0.40,
    velocitySens: 0.75,
    room: 0.60,
    reverbSize: 0.70,
    modDepth: 0.45,
    modRate: 0.35,
    drive: 0.15,
    width: 0.85,
    output: 0.75,
  ),
];

class PianoStockEditor extends StatelessWidget {
  const PianoStockEditor({
    this.preset = 0.0,
    this.tone = 0.65,
    this.body = 0.60,
    this.decay = 0.60,
    this.release = 0.40,
    this.room = 0.35,
    this.width = 0.70,
    this.output = 0.75,
    this.attack = 0.05,
    this.sustain = 0.00,
    this.hammer = 0.50,
    this.damper = 0.30,
    this.detune = 0.20,
    this.velocitySens = 0.75,
    this.reverbSize = 0.55,
    this.modDepth = 0.00,
    this.modRate = 0.30,
    this.drive = 0.00,
    this.onPresetChanged,
    this.onToneChanged,
    this.onBodyChanged,
    this.onDecayChanged,
    this.onReleaseChanged,
    this.onRoomChanged,
    this.onWidthChanged,
    this.onOutputChanged,
    this.onAttackChanged,
    this.onSustainChanged,
    this.onHammerChanged,
    this.onDamperChanged,
    this.onDetuneChanged,
    this.onVelocitySensChanged,
    this.onReverbSizeChanged,
    this.onModDepthChanged,
    this.onModRateChanged,
    this.onDriveChanged,
    this.onAuditionNoteOn,
    this.onAuditionNoteOff,
    super.key,
  });

  final double preset;
  final double tone;
  final double body;
  final double decay;
  final double release;
  final double room;
  final double width;
  final double output;
  final double attack;
  final double sustain;
  final double hammer;
  final double damper;
  final double detune;
  final double velocitySens;
  final double reverbSize;
  final double modDepth;
  final double modRate;
  final double drive;

  final ValueChanged<int>? onPresetChanged;
  final ValueChanged<double>? onToneChanged;
  final ValueChanged<double>? onBodyChanged;
  final ValueChanged<double>? onDecayChanged;
  final ValueChanged<double>? onReleaseChanged;
  final ValueChanged<double>? onRoomChanged;
  final ValueChanged<double>? onWidthChanged;
  final ValueChanged<double>? onOutputChanged;
  final ValueChanged<double>? onAttackChanged;
  final ValueChanged<double>? onSustainChanged;
  final ValueChanged<double>? onHammerChanged;
  final ValueChanged<double>? onDamperChanged;
  final ValueChanged<double>? onDetuneChanged;
  final ValueChanged<double>? onVelocitySensChanged;
  final ValueChanged<double>? onReverbSizeChanged;
  final ValueChanged<double>? onModDepthChanged;
  final ValueChanged<double>? onModRateChanged;
  final ValueChanged<double>? onDriveChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final void Function(int key)? onAuditionNoteOff;

  int get _presetIndex =>
      (preset * kPianoPresets.length).floor().clamp(0, kPianoPresets.length - 1);

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int activeIdx = _presetIndex;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Preset selector strip
          PianoPresetBar(
            currentIndex: activeIdx,
            onSelectPreset: onPresetChanged,
          ),
          SizedBox(height: tokens.spacing.sm),

          // Macro controls row: Timbre & Character
          const PianoSectionHeader(title: 'TIMBRE & ACOUSTICS'),
          SizedBox(height: tokens.spacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              PianoKnobControl(
                label: 'TONE',
                value: tone,
                displayValue: '${(tone * 100).toInt()} %',
                onChanged: onToneChanged,
              ),
              PianoKnobControl(
                label: 'BODY',
                value: body,
                displayValue: '${(body * 100).toInt()} %',
                onChanged: onBodyChanged,
              ),
              PianoKnobControl(
                label: 'HAMMER',
                value: hammer,
                displayValue: '${(hammer * 100).toInt()} %',
                onChanged: onHammerChanged,
              ),
              PianoKnobControl(
                label: 'DETUNE',
                value: detune,
                displayValue: '${(detune * 100).toInt()} %',
                onChanged: onDetuneChanged,
              ),
              PianoKnobControl(
                label: 'DRIVE',
                value: drive,
                displayValue: '${(drive * 100).toInt()} %',
                onChanged: onDriveChanged,
                accent: drive > 0.05,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),

          // ADSR Envelope section with graph
          const PianoSectionHeader(title: 'AMPLITUDE ENVELOPE (ADSR)'),
          SizedBox(height: tokens.spacing.xs),
          Row(
            children: <Widget>[
              // ADSR visual graph
              Expanded(
                flex: 4,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: tokens.color.surfaceDeep,
                    borderRadius: tokens.radius.controlBorder,
                    border: Border.all(
                      color: tokens.color.line,
                      width: tokens.border.hairline,
                    ),
                  ),
                  padding: EdgeInsets.all(tokens.spacing.xs),
                  child: PianoAdsrGraph(
                    attack: attack,
                    decay: decay,
                    sustain: sustain,
                    release: release,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.md),
              // ADSR Knobs
              Expanded(
                flex: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    PianoKnobControl(
                      label: 'ATTACK',
                      value: attack,
                      displayValue:
                          '${((0.001 + attack * attack * 0.4) * 1000).toInt()} ms',
                      onChanged: onAttackChanged,
                    ),
                    PianoKnobControl(
                      label: 'DECAY',
                      value: decay,
                      displayValue:
                          '${(0.12 + decay * decay * 12.0).toStringAsFixed(1)} s',
                      onChanged: onDecayChanged,
                    ),
                    PianoKnobControl(
                      label: 'SUSTAIN',
                      value: sustain,
                      displayValue: '${(sustain * 100).toInt()} %',
                      onChanged: onSustainChanged,
                    ),
                    PianoKnobControl(
                      label: 'RELEASE',
                      value: release,
                      displayValue:
                          '${(0.03 + release * release * 5.0).toStringAsFixed(1)} s',
                      onChanged: onReleaseChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),

          // Space, Modulation & Dynamics
          const PianoSectionHeader(title: 'SPACE & DYNAMICS'),
          SizedBox(height: tokens.spacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              PianoKnobControl(
                label: 'REVERB',
                value: room,
                displayValue: '${(room * 100).toInt()} %',
                onChanged: onRoomChanged,
              ),
              PianoKnobControl(
                label: 'SIZE',
                value: reverbSize,
                displayValue: '${(reverbSize * 100).toInt()} %',
                onChanged: onReverbSizeChanged,
              ),
              PianoKnobControl(
                label: 'MOD DEPTH',
                value: modDepth,
                displayValue: '${(modDepth * 100).toInt()} %',
                onChanged: onModDepthChanged,
              ),
              PianoKnobControl(
                label: 'MOD RATE',
                value: modRate,
                displayValue:
                    '${(0.2 + modRate * 7.8).toStringAsFixed(1)} Hz',
                onChanged: onModRateChanged,
              ),
              PianoKnobControl(
                label: 'WIDTH',
                value: width,
                displayValue: '${(width * 100).toInt()} %',
                onChanged: onWidthChanged,
              ),
              PianoKnobControl(
                label: 'OUTPUT',
                value: output,
                displayValue: '${(output * 100).toInt()} %',
                onChanged: onOutputChanged,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),

          // Interactive mini piano keyboard
          PianoPreviewKeyboard(
            onNoteOn: onAuditionNoteOn,
            onNoteOff: onAuditionNoteOff,
          ),
        ],
      ),
    );
  }
}

class PianoSectionHeader extends StatelessWidget {
  const PianoSectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Row(
      children: <Widget>[
        Text(
          title,
          style: tokens.type.label.copyWith(
            color: tokens.color.textMuted,
            fontSize: 9.5,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(width: tokens.spacing.sm),
        Expanded(
          child: Container(
            height: tokens.border.hairline,
            color: tokens.color.line,
          ),
        ),
      ],
    );
  }
}

class PianoPresetBar extends StatelessWidget {
  const PianoPresetBar({
    required this.currentIndex,
    this.onSelectPreset,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int>? onSelectPreset;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      padding: EdgeInsets.all(tokens.spacing.xxs),
      child: Wrap(
        spacing: tokens.spacing.xxs,
        runSpacing: tokens.spacing.xxs,
        children: <Widget>[
          for (int i = 0; i < kPianoPresets.length; ++i)
            PianoPresetChip(
              index: i,
              name: kPianoPresets[i].name,
              isSelected: i == currentIndex,
              onTap: onSelectPreset == null ? null : () => onSelectPreset!(i),
            ),
        ],
      ),
    );
  }
}

class PianoPresetChip extends StatelessWidget {
  const PianoPresetChip({
    required this.index,
    required this.name,
    required this.isSelected,
    this.onTap,
    super.key,
  });

  final int index;
  final String name;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.xs,
          vertical: tokens.spacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? tokens.color.accent : tokens.color.surfaceRaised,
          borderRadius: tokens.radius.controlBorder,
        ),
        child: Text(
          name,
          style: tokens.type.listRow.copyWith(
            color: isSelected ? tokens.color.surfaceDeep : tokens.color.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}

class PianoKnobControl extends StatelessWidget {
  const PianoKnobControl({
    required this.label,
    required this.value,
    required this.displayValue,
    this.onChanged,
    this.accent = false,
    super.key,
  });

  final String label;
  final double value;
  final String displayValue;
  final ValueChanged<double>? onChanged;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ObKnob(
          value: value,
          onChanged: onChanged,
          accent: accent,
        ),
        SizedBox(height: tokens.spacing.xxs),
        Text(
          label,
          style: tokens.type.label.copyWith(fontSize: 8.5),
        ),
        Text(
          displayValue,
          style: tokens.type.numericSmall.copyWith(
            color: tokens.color.textMuted,
            fontSize: 9.0,
          ),
        ),
      ],
    );
  }
}

class PianoAdsrGraph extends StatelessWidget {
  const PianoAdsrGraph({
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
    super.key,
  });

  final double attack;
  final double decay;
  final double sustain;
  final double release;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return CustomPaint(
      painter: _PianoAdsrPainter(
        attack: attack,
        decay: decay,
        sustain: sustain,
        release: release,
        lineColor: tokens.color.accent,
        fillColor: tokens.color.accent.withValues(alpha: 0.15),
      ),
    );
  }
}

class _PianoAdsrPainter extends CustomPainter {
  const _PianoAdsrPainter({
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
    required this.lineColor,
    required this.fillColor,
  });

  final double attack;
  final double decay;
  final double sustain;
  final double release;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double w = size.width;
    final double h = size.height;

    // Normalised partition
    final double aW = (0.1 + attack * 0.25) * w;
    final double dW = (0.1 + decay * 0.25) * w;
    final double sW = 0.25 * w;
    final double rW = (0.1 + release * 0.3) * w;

    final double scale = w / (aW + dW + sW + rW);
    final double aX = aW * scale;
    final double dX = aX + dW * scale;
    final double sX = dX + sW * scale;
    final double rX = w;

    final double sY = h * (1.0 - sustain.clamp(0.0, 1.0));

    final Path path = Path();
    path.moveTo(0, h);
    path.lineTo(aX, 0); // Attack peak
    path.lineTo(dX, sY); // Decay to sustain
    path.lineTo(sX, sY); // Hold sustain
    path.lineTo(rX, h); // Release to zero

    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final Path fillPath = Path.from(path)..lineTo(0, h);
    canvas.drawPath(fillPath, fillPaint);

    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _PianoAdsrPainter oldDelegate) {
    return oldDelegate.attack != attack ||
        oldDelegate.decay != decay ||
        oldDelegate.sustain != sustain ||
        oldDelegate.release != release ||
        oldDelegate.lineColor != lineColor;
  }
}

class PianoPreviewKeyboard extends StatefulWidget {
  const PianoPreviewKeyboard({
    this.onNoteOn,
    this.onNoteOff,
    super.key,
  });

  final void Function(int key, double velocity)? onNoteOn;
  final void Function(int key)? onNoteOff;

  @override
  State<PianoPreviewKeyboard> createState() => _PianoPreviewKeyboardState();
}

class _PianoPreviewKeyboardState extends State<PianoPreviewKeyboard> {
  int _baseOctave = 4; // C4 default (key 60)
  final Set<int> _activeKeys = <int>{};

  void _shiftOctave(int delta) {
    setState(() {
      _baseOctave = (_baseOctave + delta).clamp(1, 6);
    });
  }

  void _pressKey(int midiKey) {
    if (_activeKeys.contains(midiKey)) return;
    setState(() => _activeKeys.add(midiKey));
    widget.onNoteOn?.call(midiKey, 0.85);
  }

  void _releaseKey(int midiKey) {
    if (!_activeKeys.contains(midiKey)) return;
    setState(() => _activeKeys.remove(midiKey));
    widget.onNoteOff?.call(midiKey);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int startNote = _baseOctave * 12; // e.g. 48 for C3, 60 for C4

    return Column(
      children: <Widget>[
        // Octave shift toolbar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'PREVIEW KEYBOARD',
              style: tokens.type.label.copyWith(fontSize: 8.5),
            ),
            Row(
              children: <Widget>[
                PianoOctaveButton(
                  label: '◀ OCT',
                  onTap: _baseOctave > 1 ? () => _shiftOctave(-1) : null,
                ),
                SizedBox(width: tokens.spacing.xs),
                Text(
                  'C$_baseOctave - B${_baseOctave + 1}',
                  style: tokens.type.numericSmall.copyWith(
                    color: tokens.color.accent,
                    fontSize: 9.5,
                  ),
                ),
                SizedBox(width: tokens.spacing.xs),
                PianoOctaveButton(
                  label: 'OCT ▶',
                  onTap: _baseOctave < 6 ? () => _shiftOctave(1) : null,
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.xxs),
        // 2-Octave (24 semitones, 14 white keys) piano keys strip
        Container(
          height: 64,
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              // 14 white keys in 2 octaves
              const int whiteKeyCount = 14;
              final double whiteKeyWidth = width / whiteKeyCount;
              final double blackKeyWidth = whiteKeyWidth * 0.65;
              const double blackKeyHeight = 38.0;

              // White note MIDI offsets in 2 octaves: C, D, E, F, G, A, B x2
              const List<int> whiteKeyOffsets = <int>[
                0, 2, 4, 5, 7, 9, 11,
                12, 14, 16, 17, 19, 21, 23,
              ];

              // Black note MIDI offsets and white-key index positions
              // C#, D#, F#, G#, A# for Octave 1 and Octave 2
              const List<_BlackKeyInfo> blackKeyInfos = <_BlackKeyInfo>[
                _BlackKeyInfo(semitoneOffset: 1, leftWhiteKeyIndex: 0),
                _BlackKeyInfo(semitoneOffset: 3, leftWhiteKeyIndex: 1),
                _BlackKeyInfo(semitoneOffset: 6, leftWhiteKeyIndex: 3),
                _BlackKeyInfo(semitoneOffset: 8, leftWhiteKeyIndex: 4),
                _BlackKeyInfo(semitoneOffset: 10, leftWhiteKeyIndex: 5),
                _BlackKeyInfo(semitoneOffset: 13, leftWhiteKeyIndex: 7),
                _BlackKeyInfo(semitoneOffset: 15, leftWhiteKeyIndex: 8),
                _BlackKeyInfo(semitoneOffset: 18, leftWhiteKeyIndex: 10),
                _BlackKeyInfo(semitoneOffset: 20, leftWhiteKeyIndex: 11),
                _BlackKeyInfo(semitoneOffset: 22, leftWhiteKeyIndex: 12),
              ];

              return Stack(
                children: <Widget>[
                  // White keys row
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < whiteKeyCount; ++i)
                        Expanded(
                          child: PianoWhiteKey(
                            midiKey: startNote + whiteKeyOffsets[i],
                            isPressed:
                                _activeKeys.contains(startNote + whiteKeyOffsets[i]),
                            onPointerDown: () =>
                                _pressKey(startNote + whiteKeyOffsets[i]),
                            onPointerUp: () =>
                                _releaseKey(startNote + whiteKeyOffsets[i]),
                          ),
                        ),
                    ],
                  ),
                  // Black keys overlay
                  for (final _BlackKeyInfo info in blackKeyInfos)
                    Positioned(
                      left: (info.leftWhiteKeyIndex + 1) * whiteKeyWidth -
                          (blackKeyWidth / 2),
                      top: 0,
                      width: blackKeyWidth,
                      height: blackKeyHeight,
                      child: PianoBlackKey(
                        midiKey: startNote + info.semitoneOffset,
                        isPressed: _activeKeys
                            .contains(startNote + info.semitoneOffset),
                        onPointerDown: () =>
                            _pressKey(startNote + info.semitoneOffset),
                        onPointerUp: () =>
                            _releaseKey(startNote + info.semitoneOffset),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BlackKeyInfo {
  const _BlackKeyInfo({
    required this.semitoneOffset,
    required this.leftWhiteKeyIndex,
  });

  final int semitoneOffset;
  final int leftWhiteKeyIndex;
}

class PianoWhiteKey extends StatelessWidget {
  const PianoWhiteKey({
    required this.midiKey,
    required this.isPressed,
    required this.onPointerDown,
    required this.onPointerUp,
    super.key,
  });

  final int midiKey;
  final bool isPressed;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPointerDown(),
      onPointerUp: (_) => onPointerUp(),
      onPointerCancel: (_) => onPointerUp(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          color: isPressed
              ? tokens.color.accent
              : const Color(0xFFDCDCDC),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(2),
            bottomRight: Radius.circular(2),
          ),
          border: Border.all(
            color: const Color(0xFF222222),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}

class PianoBlackKey extends StatelessWidget {
  const PianoBlackKey({
    required this.midiKey,
    required this.isPressed,
    required this.onPointerDown,
    required this.onPointerUp,
    super.key,
  });

  final int midiKey;
  final bool isPressed;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPointerDown(),
      onPointerUp: (_) => onPointerUp(),
      onPointerCancel: (_) => onPointerUp(),
      child: Container(
        decoration: BoxDecoration(
          color: isPressed ? tokens.color.accent : const Color(0xFF1E1E1E),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(2),
            bottomRight: Radius.circular(2),
          ),
          border: Border.all(
            color: const Color(0xFF111111),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}

class PianoOctaveButton extends StatelessWidget {
  const PianoOctaveButton({
    required this.label,
    this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.xs,
          vertical: tokens.spacing.xxs,
        ),
        decoration: BoxDecoration(
          color: onTap != null
              ? tokens.color.surfaceRaised
              : tokens.color.surfaceDeep,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
        child: Text(
          label,
          style: tokens.type.listRow.copyWith(
            color: onTap != null
                ? tokens.color.textPrimary
                : tokens.color.textMuted,
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
