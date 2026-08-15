// PianoStockEditor — Premium Hardware-Inspired Piano Instrument (UI-C-11 / UI-D-08).
import 'dart:math' as math;
import 'package:flutter/widgets.dart';

class PianoPresetData {
  const PianoPresetData({
    required this.id,
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

  final String id;
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
    id: '01',
    name: 'CONCERT GRAND',
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
    id: '02',
    name: 'FELT UPRIGHT',
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
    id: '03',
    name: 'CLASSIC RHODES',
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
    id: '04',
    name: 'FM DX TINES',
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
    id: '05',
    name: 'VINTAGE WURLI',
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
    id: '06',
    name: 'HONKY-TONK',
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
    id: '07',
    name: 'DREAM CLOUD',
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
    id: '08',
    name: 'POP GRAND',
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
    id: '09',
    name: 'HARPSICHORD',
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
    id: '10',
    name: 'SYNTH KEYS',
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
    this.pitch = 0.50,
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
    this.onPitchChanged,
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
  final double pitch;

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
  final ValueChanged<double>? onPitchChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final void Function(int key)? onAuditionNoteOff;

  int get _presetIndex => (preset * kPianoPresets.length).floor().clamp(
    0,
    kPianoPresets.length - 1,
  );

  @override
  Widget build(BuildContext context) {
    final int currentIdx = _presetIndex;
    final PianoPresetData currentPreset = kPianoPresets[currentIdx];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE4E1DA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC7C3BA), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          // Top Hardware Chassis Panel (Matte Warm-Grey / Off-White)
          Expanded(
            child: Container(
              color: const Color(0xFFE4E1DA),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                children: <Widget>[
                  // Header Row: Brand Title, LCD Preset Display, Speaker Grille
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      // Brand Title
                      const Text(
                        'ONEBEAT PIANO',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.2,
                          color: Color(0xFF2C2A29),
                        ),
                      ),
                      // Center LCD Preset Stepper
                      PianoLcdPresetDisplay(
                        presetId: currentPreset.id,
                        presetName: currentPreset.name,
                        currentIndex: currentIdx,
                        onPrev: onPresetChanged == null
                            ? null
                            : () => onPresetChanged!(
                                (currentIdx - 1 + kPianoPresets.length) % kPianoPresets.length,
                              ),
                        onNext: onPresetChanged == null
                            ? null
                            : () => onPresetChanged!(
                                (currentIdx + 1) % kPianoPresets.length,
                              ),
                        onSelectPreset: onPresetChanged,
                      ),
                      // Right Speaker Grille
                      const PianoSpeakerGrille(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Control Cards Grid
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // Card 1: ACOUSTICS / MODEL
                        Expanded(
                          flex: 3,
                          child: PianoHardwareCard(
                            title: 'ACOUSTICS',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: <Widget>[
                                PianoHardwareKnob(
                                  label: 'TONE',
                                  value: tone,
                                  displayValue: '${(tone * 100).toInt()}%',
                                  onChanged: onToneChanged,
                                ),
                                PianoHardwareKnob(
                                  label: 'BODY',
                                  value: body,
                                  displayValue: '${(body * 100).toInt()}%',
                                  onChanged: onBodyChanged,
                                ),
                                PianoHardwareKnob(
                                  label: 'HAMMER',
                                  value: hammer,
                                  displayValue: '${(hammer * 100).toInt()}%',
                                  onChanged: onHammerChanged,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Card 2: TIMBRE & DRIVE
                        Expanded(
                          flex: 3,
                          child: PianoHardwareCard(
                            title: 'TIMBRE',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: <Widget>[
                                PianoHardwareKnob(
                                  label: 'DETUNE',
                                  value: detune,
                                  displayValue: '${(detune * 100).toInt()}%',
                                  onChanged: onDetuneChanged,
                                ),
                                PianoHardwareKnob(
                                  label: 'DRIVE',
                                  value: drive,
                                  displayValue: '${(drive * 100).toInt()}%',
                                  onChanged: onDriveChanged,
                                ),
                                PianoHardwareKnob(
                                  label: 'VELOCITY',
                                  value: velocitySens,
                                  displayValue: '${(velocitySens * 100).toInt()}%',
                                  onChanged: onVelocitySensChanged,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Card 3: ENVELOPE (Faders ADSR)
                        Expanded(
                          flex: 4,
                          child: PianoHardwareCard(
                            title: 'ENVELOPE',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: <Widget>[
                                PianoHardwareFader(
                                  label: 'A',
                                  value: attack,
                                  displayValue: '${((0.001 + attack * attack * 0.4) * 1000).toInt()}MS',
                                  onChanged: onAttackChanged,
                                ),
                                PianoHardwareFader(
                                  label: 'D',
                                  value: decay,
                                  displayValue: '${(0.12 + decay * decay * 12.0).toStringAsFixed(1)}S',
                                  onChanged: onDecayChanged,
                                ),
                                PianoHardwareFader(
                                  label: 'S',
                                  value: sustain,
                                  displayValue: '${(sustain * 100).toInt()}%',
                                  onChanged: onSustainChanged,
                                ),
                                PianoHardwareFader(
                                  label: 'R',
                                  value: release,
                                  displayValue: '${(0.03 + release * release * 5.0).toStringAsFixed(1)}S',
                                  onChanged: onReleaseChanged,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Card 4: SPACE / LFO (Reverb & Modulation)
                        Expanded(
                          flex: 3,
                          child: PianoHardwareCard(
                            title: 'SPACE / LFO',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: <Widget>[
                                PianoHardwareKnob(
                                  label: 'REVERB',
                                  value: room,
                                  displayValue: '${(room * 100).toInt()}%',
                                  onChanged: onRoomChanged,
                                ),
                                PianoHardwareKnob(
                                  label: 'SIZE',
                                  value: reverbSize,
                                  displayValue: '${(reverbSize * 100).toInt()}%',
                                  onChanged: onReverbSizeChanged,
                                ),
                                PianoHardwareKnob(
                                  label: 'MOD',
                                  value: modDepth,
                                  displayValue: '${(modDepth * 100).toInt()}%',
                                  onChanged: onModDepthChanged,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom Hardware Chassis Strip (Dark Charcoal with Wheels, Octave Mode, Piano Keys & Master Vol)
          Container(
            color: const Color(0xFF2C2A29),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: PianoBottomSection(
              output: output,
              pitch: pitch,
              onOutputChanged: onOutputChanged,
              onPitchChanged: onPitchChanged,
              onNoteOn: onAuditionNoteOn,
              onNoteOff: onAuditionNoteOff,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HARDWARE CARD (Framed Section with Notch Title)
// ---------------------------------------------------------------------------
class PianoHardwareCard extends StatelessWidget {
  const PianoHardwareCard({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE4E1DA),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFB3ADA3), width: 1.2),
          ),
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
          child: child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              color: const Color(0xFFE4E1DA),
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Color(0xFF4A4643),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HARDWARE ROTARY KNOB (Industrial Charcoal Dial)
// ---------------------------------------------------------------------------
class PianoHardwareKnob extends StatefulWidget {
  const PianoHardwareKnob({
    required this.label,
    required this.value,
    required this.displayValue,
    this.onChanged,
    this.diameter = 32.0,
    super.key,
  });

  final String label;
  final double value;
  final String displayValue;
  final ValueChanged<double>? onChanged;
  final double diameter;

  @override
  State<PianoHardwareKnob> createState() => _PianoHardwareKnobState();
}

class _PianoHardwareKnobState extends State<PianoHardwareKnob> {
  double _dragValue = 0.0;

  void _onDrag(DragUpdateDetails d) {
    if (widget.onChanged == null) return;
    _dragValue = (_dragValue - d.delta.dy * 0.006).clamp(0.0, 1.0);
    widget.onChanged!(_dragValue);
  }

  @override
  Widget build(BuildContext context) {
    _dragValue = widget.value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragValue = widget.value,
      onVerticalDragUpdate: _onDrag,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            widget.label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFF4A4643),
            ),
          ),
          const SizedBox(height: 3),
          CustomPaint(
            size: Size(widget.diameter, widget.diameter),
            painter: _PianoKnobPainter(value: widget.value),
          ),
          const SizedBox(height: 3),
          Text(
            widget.displayValue,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 7.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B655F),
            ),
          ),
        ],
      ),
    );
  }
}

class _PianoKnobPainter extends CustomPainter {
  const _PianoKnobPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2.0;
    final Offset center = Offset(radius, radius);

    // Outer subtle shadow/rim
    final Paint rimPaint = Paint()
      ..color = const Color(0xFFC7C3BA)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, rimPaint);

    // Knob Cap (Charcoal matte)
    final Paint capPaint = Paint()
      ..color = const Color(0xFF33302E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 1.0, capPaint);

    // Pointer Angle (from -135 deg to +135 deg)
    final double sweep = -2.35619 + value.clamp(0.0, 1.0) * 4.71239; // -135 to +135 deg in rad
    final double pointerLength = radius * 0.72;
    final Offset pointerEnd = Offset(
      center.dx + pointerLength * math.sin(sweep),
      center.dy - pointerLength * math.cos(sweep),
    );

    final Paint pointerPaint = Paint()
      ..color = const Color(0xFFE4E1DA)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, pointerEnd, pointerPaint);
  }

  @override
  bool shouldRepaint(covariant _PianoKnobPainter oldDelegate) => oldDelegate.value != value;
}

// ---------------------------------------------------------------------------
// HARDWARE VERTICAL FADER (ADSR Sliders)
// ---------------------------------------------------------------------------
class PianoHardwareFader extends StatefulWidget {
  const PianoHardwareFader({
    required this.label,
    required this.value,
    required this.displayValue,
    this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final String displayValue;
  final ValueChanged<double>? onChanged;

  @override
  State<PianoHardwareFader> createState() => _PianoHardwareFaderState();
}

class _PianoHardwareFaderState extends State<PianoHardwareFader> {
  void _onDrag(DragUpdateDetails d, double trackHeight) {
    if (widget.onChanged == null || trackHeight <= 0) return;
    final double delta = -d.delta.dy / trackHeight;
    final double next = (widget.value + delta).clamp(0.0, 1.0);
    widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          widget.label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 8.0,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4A4643),
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double trackHeight = constraints.maxHeight;
              final double thumbY = (1.0 - widget.value.clamp(0.0, 1.0)) * (trackHeight - 12.0);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (DragUpdateDetails d) => _onDrag(d, trackHeight - 12.0),
                child: SizedBox(
                  width: 22,
                  height: trackHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      // Center groove line
                      Container(
                        width: 2.5,
                        height: trackHeight,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A4643),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      // Draggable Fader Cap
                      Positioned(
                        top: thumbY,
                        child: Container(
                          width: 18,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2A29),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x33000000),
                                offset: Offset(0, 1),
                                blurRadius: 1.5,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 1.5,
                              color: const Color(0xFFE4E1DA),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.displayValue,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 7.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B655F),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HARDWARE LCD PRESET DISPLAY WITH DROPDOWN
// ---------------------------------------------------------------------------
class PianoLcdPresetDisplay extends StatefulWidget {
  const PianoLcdPresetDisplay({
    required this.presetId,
    required this.presetName,
    required this.currentIndex,
    this.onPrev,
    this.onNext,
    this.onSelectPreset,
    super.key,
  });

  final String presetId;
  final String presetName;
  final int currentIndex;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int>? onSelectPreset;

  @override
  State<PianoLcdPresetDisplay> createState() => _PianoLcdPresetDisplayState();
}

class _PianoLcdPresetDisplayState extends State<PianoLcdPresetDisplay> {
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  bool _isOpen = false;

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      setState(() => _isOpen = true);
      _portalController.show();
    }
  }

  void _close() {
    if (!_isOpen) return;
    setState(() => _isOpen = false);
    _portalController.hide();
  }

  void _select(int index) {
    _close();
    widget.onSelectPreset?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (BuildContext context) {
          return Stack(
            children: <Widget>[
              // Full surface transparent dismissal barrier
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: const SizedBox.expand(),
                ),
              ),
              // Anchored dropdown menu popover
              CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: Alignment.bottomCenter,
                followerAnchor: Alignment.topCenter,
                offset: const Offset(0, 4),
                showWhenUnlinked: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  widthFactor: 1.0,
                  heightFactor: 1.0,
                  child: _PianoPresetDropdownMenu(
                    currentIndex: widget.currentIndex,
                    onSelect: _select,
                  ),
                ),
              ),
            ],
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2C2A29),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _isOpen ? const Color(0xFF8A847C) : const Color(0xFF4A4643),
              width: 1.0,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Interactive dropdown trigger area (Hamburger icon + preset name + chevron)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Clean 3-line vector hamburger icon
                      const CustomPaint(
                        size: Size(12, 12),
                        painter: _HamburgerIconPainter(
                          color: Color(0xFFA6A097),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Preset Id & Name
                      Text(
                        '${widget.presetId} ${widget.presetName}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Color(0xFFE4E1DA),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Small chevron down icon
                      const CustomPaint(
                        size: Size(8, 8),
                        painter: _ChevronDownPainter(color: Color(0xFFA6A097)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Stepper Divider
              Container(width: 1, height: 14, color: const Color(0xFF4A4643)),
              const SizedBox(width: 4),
              // Stepper Left
              PianoPresetStepperButton(
                isLeft: true,
                onTap: widget.onPrev,
              ),
              const SizedBox(width: 2),
              // Stepper Right
              PianoPresetStepperButton(
                isLeft: false,
                onTap: widget.onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PianoPresetStepperButton extends StatefulWidget {
  const PianoPresetStepperButton({
    required this.isLeft,
    this.onTap,
    super.key,
  });

  final bool isLeft;
  final VoidCallback? onTap;

  @override
  State<PianoPresetStepperButton> createState() => _PianoPresetStepperButtonState();
}

class _PianoPresetStepperButtonState extends State<PianoPresetStepperButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _hover && widget.onTap != null ? const Color(0xFF3D3A38) : const Color(0x00000000),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(6, 9),
            painter: _StepperArrowPainter(
              isLeft: widget.isLeft,
              color: _hover ? const Color(0xFFE4E1DA) : const Color(0xFFA6A097),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperArrowPainter extends CustomPainter {
  const _StepperArrowPainter({
    required this.isLeft,
    required this.color,
  });

  final bool isLeft;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final Path path = Path();
    final double midY = size.height / 2.0;

    if (isLeft) {
      path.moveTo(size.width - 0.5, 0.5);
      path.lineTo(0.5, midY);
      path.lineTo(size.width - 0.5, size.height - 0.5);
    } else {
      path.moveTo(0.5, 0.5);
      path.lineTo(size.width - 0.5, midY);
      path.lineTo(0.5, size.height - 0.5);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StepperArrowPainter oldDelegate) =>
      oldDelegate.isLeft != isLeft || oldDelegate.color != color;
}

class _HamburgerIconPainter extends CustomPainter {
  const _HamburgerIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const double w = 12.0;
    canvas.drawLine(const Offset(0, 2), const Offset(w, 2), paint);
    canvas.drawLine(const Offset(0, 6.0), const Offset(w, 6.0), paint);
    canvas.drawLine(const Offset(0, 10), const Offset(w, 10), paint);
  }

  @override
  bool shouldRepaint(covariant _HamburgerIconPainter oldDelegate) => oldDelegate.color != color;
}

class _ChevronDownPainter extends CustomPainter {
  const _ChevronDownPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final Path path = Path();
    final double midX = size.width / 2.0;
    final double midY = size.height / 2.0;

    path.moveTo(0.5, midY - 1.5);
    path.lineTo(midX, midY + 2.0);
    path.lineTo(size.width - 0.5, midY - 1.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronDownPainter oldDelegate) => oldDelegate.color != color;
}

class _PianoPresetDropdownMenu extends StatelessWidget {
  const _PianoPresetDropdownMenu({
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF252322),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4A4643), width: 1.0),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x77000000),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < kPianoPresets.length; ++i)
            _PianoPresetMenuItem(
              index: i,
              preset: kPianoPresets[i],
              isSelected: i == currentIndex,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _PianoPresetMenuItem extends StatefulWidget {
  const _PianoPresetMenuItem({
    required this.index,
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final PianoPresetData preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_PianoPresetMenuItem> createState() => _PianoPresetMenuItemState();
}

class _PianoPresetMenuItemState extends State<_PianoPresetMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.isSelected ? const Color(0xFF383533) : (_hover ? const Color(0xFF2E2B2A) : null),
          ),
          child: Row(
            children: <Widget>[
              // Index
              Text(
                widget.preset.id,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: widget.isSelected ? const Color(0xFFE4E1DA) : const Color(0xFF7A746C),
                ),
              ),
              const SizedBox(width: 8),
              // Name
              Expanded(
                child: Text(
                  widget.preset.name,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.0,
                    fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.5,
                    color: widget.isSelected ? const Color(0xFFE4E1DA) : const Color(0xFFA6A097),
                  ),
                ),
              ),
              if (widget.isSelected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE4E1DA),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SPEAKER GRILLE MATRIX
// ---------------------------------------------------------------------------
class PianoSpeakerGrille extends StatelessWidget {
  const PianoSpeakerGrille({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int r = 0; r < 4; ++r)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int c = 0; c < 8; ++c)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.0),
                    width: 2.8,
                    height: 2.8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4A4643),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// BOTTOM SECTION (Dark Chassis with Mod Wheels, Octave Mode & Keyboard)
// ---------------------------------------------------------------------------
class PianoBottomSection extends StatefulWidget {
  const PianoBottomSection({
    required this.output,
    this.pitch = 0.5,
    this.onOutputChanged,
    this.onPitchChanged,
    this.onNoteOn,
    this.onNoteOff,
    super.key,
  });

  final double output;
  final double pitch;
  final ValueChanged<double>? onOutputChanged;
  final ValueChanged<double>? onPitchChanged;
  final void Function(int key, double velocity)? onNoteOn;
  final void Function(int key)? onNoteOff;

  @override
  State<PianoBottomSection> createState() => _PianoBottomSectionState();
}

class _PianoBottomSectionState extends State<PianoBottomSection> {
  int _octave = 4; // C4 default

  void _setOctave(int oct) {
    setState(() => _octave = oct);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Top Toolbar: Octave Pills
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'OCTAVE',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 8.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF8A847C),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1C1B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF4A4643), width: 1),
              ),
              padding: const EdgeInsets.all(1.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int oct = 2; oct <= 6; ++oct)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setOctave(oct),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _octave == oct ? const Color(0xFFE4E1DA) : const Color(0xFF1E1C1B),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'C$oct',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 8.0,
                            fontWeight: FontWeight.w700,
                            color: _octave == oct ? const Color(0xFF2C2A29) : const Color(0xFF8A847C),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // Main Row: Pitch/Mod Wheels, Piano Keys, Master Vol
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Pitch & Mod Wheel Ribbons
            PianoPitchModWheels(
              pitch: widget.pitch,
              onPitchChanged: widget.onPitchChanged,
            ),
            const SizedBox(width: 8),
            // Responsive Piano Keyboard
            Expanded(
              child: PianoHardwareKeyboard(
                baseOctave: _octave,
                onNoteOn: widget.onNoteOn,
                onNoteOff: widget.onNoteOff,
              ),
            ),
            const SizedBox(width: 10),
            // Big Master Vol Knob
            PianoBigVolKnob(
              value: widget.output,
              onChanged: widget.onOutputChanged,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PITCH & MOD WHEELS
// ---------------------------------------------------------------------------
class PianoPitchModWheels extends StatefulWidget {
  const PianoPitchModWheels({
    this.pitch = 0.5,
    this.onPitchChanged,
    super.key,
  });

  final double pitch;
  final ValueChanged<double>? onPitchChanged;

  @override
  State<PianoPitchModWheels> createState() => _PianoPitchModWheelsState();
}

class _PianoPitchModWheelsState extends State<PianoPitchModWheels> {
  double _pitch = 0.5;
  double _mod = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _pitch = widget.pitch;
  }

  @override
  void didUpdateWidget(covariant PianoPitchModWheels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.pitch != widget.pitch) {
      _pitch = widget.pitch;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double pitchSt = (_pitch - 0.5) * 48.0;
    final String pitchLabel = pitchSt.abs() < 0.05 ? '0 ST' : '${pitchSt > 0 ? '+' : ''}${pitchSt.round()} ST';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildWheel(
          'PITCH',
          _pitch,
          (double v) {
            setState(() => _pitch = v);
            widget.onPitchChanged?.call(v);
          },
          displayValue: pitchLabel,
          onDoubleTap: () {
            setState(() => _pitch = 0.5);
            widget.onPitchChanged?.call(0.5);
          },
        ),
        const SizedBox(width: 4),
        _buildWheel(
          'MOD',
          _mod,
          (double v) => setState(() => _mod = v),
          onDoubleTap: () => setState(() => _mod = 0.0),
        ),
      ],
    );
  }

  Widget _buildWheel(
    String label,
    double val,
    ValueChanged<double> onUpdate, {
    VoidCallback? onDoubleTap,
    String? displayValue,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onDoubleTap,
          onVerticalDragStart: (_) => _isDragging = true,
          onVerticalDragUpdate: (DragUpdateDetails d) {
            final double next = (val - d.delta.dy * 0.015).clamp(0.0, 1.0);
            onUpdate(next);
          },
          onVerticalDragEnd: (_) => _isDragging = false,
          onVerticalDragCancel: () => _isDragging = false,
          child: Container(
            width: 16,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1C1B),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF4A4643), width: 1),
            ),
            child: Stack(
              children: <Widget>[
                // Center zero line for pitch ribbon
                if (label == 'PITCH')
                  Positioned(
                    top: 25,
                    left: 2,
                    right: 2,
                    child: Container(
                      height: 1.5,
                      color: const Color(0xFF4A4643),
                    ),
                  ),
                Positioned(
                  top: (1.0 - val.clamp(0.0, 1.0)) * (52.0 - 14.0),
                  left: 1,
                  right: 1,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4E1DA),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x44000000),
                          offset: Offset(0, 1),
                          blurRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 6.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A847C),
          ),
        ),
        if (displayValue != null)
          Text(
            displayValue,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 6.0,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE4E1DA),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// BIG MASTER VOL KNOB (On Dark Chassis)
// ---------------------------------------------------------------------------
class PianoBigVolKnob extends StatefulWidget {
  const PianoBigVolKnob({required this.value, this.onChanged, super.key});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  State<PianoBigVolKnob> createState() => _PianoBigVolKnobState();
}

class _PianoBigVolKnobState extends State<PianoBigVolKnob> {
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    _dragValue = widget.value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragValue = widget.value,
      onVerticalDragUpdate: (DragUpdateDetails d) {
        if (widget.onChanged == null) return;
        _dragValue = (_dragValue - d.delta.dy * 0.006).clamp(0.0, 1.0);
        widget.onChanged!(_dragValue);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'VOL',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A847C),
            ),
          ),
          const SizedBox(height: 2),
          CustomPaint(
            size: const Size(36, 36),
            painter: _BigVolPainter(value: widget.value),
          ),
          const SizedBox(height: 2),
          Text(
            '${(widget.value * 100).toInt()}%',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A847C),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigVolPainter extends CustomPainter {
  const _BigVolPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2.0;
    final Offset center = Offset(radius, radius);

    // Outer Dial Base (Light off-white dial cap)
    final Paint capPaint = Paint()
      ..color = const Color(0xFFE4E1DA)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, capPaint);

    // Pointer line
    final double sweep = -2.35619 + value.clamp(0.0, 1.0) * 4.71239;
    final double pointerLength = radius * 0.75;
    final Offset pointerEnd = Offset(
      center.dx + pointerLength * math.sin(sweep),
      center.dy - pointerLength * math.cos(sweep),
    );

    final Paint pointerPaint = Paint()
      ..color = const Color(0xFF2C2A29)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, pointerEnd, pointerPaint);
  }

  @override
  bool shouldRepaint(covariant _BigVolPainter oldDelegate) => oldDelegate.value != value;
}

// ---------------------------------------------------------------------------
// PRO-GRADE PIANO KEYBOARD
// ---------------------------------------------------------------------------
class PianoHardwareKeyboard extends StatefulWidget {
  const PianoHardwareKeyboard({
    required this.baseOctave,
    this.onNoteOn,
    this.onNoteOff,
    super.key,
  });

  final int baseOctave;
  final void Function(int key, double velocity)? onNoteOn;
  final void Function(int key)? onNoteOff;

  @override
  State<PianoHardwareKeyboard> createState() => _PianoHardwareKeyboardState();
}

class _PianoHardwareKeyboardState extends State<PianoHardwareKeyboard> {
  final Set<int> _activeKeys = <int>{};

  void _press(int key) {
    if (_activeKeys.contains(key)) return;
    setState(() => _activeKeys.add(key));
    widget.onNoteOn?.call(key, 0.85);
  }

  void _release(int key) {
    if (!_activeKeys.contains(key)) return;
    setState(() => _activeKeys.remove(key));
    widget.onNoteOff?.call(key);
  }

  @override
  Widget build(BuildContext context) {
    final int startMidi = widget.baseOctave * 12; // C_base

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1817),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double totalWidth = constraints.maxWidth;
          // 2.5 Octaves: 18 white keys (C to F)
          const int whiteKeyCount = 18;
          final double whiteKeyWidth = totalWidth / whiteKeyCount;
          final double blackKeyWidth = whiteKeyWidth * 0.62;
          const double blackKeyHeight = 33.0;

          // 18 white keys semitone offsets from root
          const List<int> whiteKeyOffsets = <int>[
            0,
            2,
            4,
            5,
            7,
            9,
            11,
            12,
            14,
            16,
            17,
            19,
            21,
            23,
            24,
            26,
            28,
            29,
          ];

          // Black keys offsets and left white key index
          const List<_BlackKeyPos> blackKeys = <_BlackKeyPos>[
            _BlackKeyPos(semitone: 1, whiteIdx: 0),
            _BlackKeyPos(semitone: 3, whiteIdx: 1),
            _BlackKeyPos(semitone: 6, whiteIdx: 3),
            _BlackKeyPos(semitone: 8, whiteIdx: 4),
            _BlackKeyPos(semitone: 10, whiteIdx: 5),
            _BlackKeyPos(semitone: 13, whiteIdx: 7),
            _BlackKeyPos(semitone: 15, whiteIdx: 8),
            _BlackKeyPos(semitone: 18, whiteIdx: 10),
            _BlackKeyPos(semitone: 20, whiteIdx: 11),
            _BlackKeyPos(semitone: 22, whiteIdx: 12),
            _BlackKeyPos(semitone: 25, whiteIdx: 14),
            _BlackKeyPos(semitone: 27, whiteIdx: 15),
          ];

          return Stack(
            children: <Widget>[
              // White Keys
              Row(
                children: <Widget>[
                  for (int i = 0; i < whiteKeyCount; ++i)
                    Expanded(
                      child: PianoWhiteKey(
                        midiKey: startMidi + whiteKeyOffsets[i],
                        isPressed: _activeKeys.contains(
                          startMidi + whiteKeyOffsets[i],
                        ),
                        onPointerDown: () => _press(startMidi + whiteKeyOffsets[i]),
                        onPointerUp: () => _release(startMidi + whiteKeyOffsets[i]),
                      ),
                    ),
                ],
              ),
              // Black Keys
              for (final _BlackKeyPos bp in blackKeys)
                Positioned(
                  left: (bp.whiteIdx + 1) * whiteKeyWidth - (blackKeyWidth / 2),
                  top: 0,
                  width: blackKeyWidth,
                  height: blackKeyHeight,
                  child: PianoBlackKey(
                    midiKey: startMidi + bp.semitone,
                    isPressed: _activeKeys.contains(startMidi + bp.semitone),
                    onPointerDown: () => _press(startMidi + bp.semitone),
                    onPointerUp: () => _release(startMidi + bp.semitone),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BlackKeyPos {
  const _BlackKeyPos({required this.semitone, required this.whiteIdx});
  final int semitone;
  final int whiteIdx;
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
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPointerDown(),
      onPointerUp: (_) => onPointerUp(),
      onPointerCancel: (_) => onPointerUp(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          color: isPressed ? const Color(0xFFC7C1B5) : const Color(0xFFEDE9E3),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(2.5),
            bottomRight: Radius.circular(2.5),
          ),
          border: Border.all(color: const Color(0xFF2C2A29), width: 0.5),
          boxShadow: isPressed
              ? const <BoxShadow>[]
              : const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x33000000),
                    offset: Offset(0, 1),
                    blurRadius: 1,
                  ),
                ],
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
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPointerDown(),
      onPointerUp: (_) => onPointerUp(),
      onPointerCancel: (_) => onPointerUp(),
      child: Container(
        decoration: BoxDecoration(
          color: isPressed ? const Color(0xFF4A4643) : const Color(0xFF232120),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(2),
            bottomRight: Radius.circular(2),
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 2),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
