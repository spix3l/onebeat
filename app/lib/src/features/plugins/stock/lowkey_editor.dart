import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class LowkeyPresetData {
  const LowkeyPresetData({
    required this.name,
    required this.tag,
    required this.description,
    required this.tone,
    required this.body,
    required this.decay,
    required this.release,
    required this.room,
    required this.width,
    required this.output,
    required this.pickPos,
    required this.damping,
    required this.pickup,
    required this.drive,
    required this.chorus,
    required this.reverbSize,
    required this.dynamics,
    required this.pitch,
    required this.modRate,
    required this.attack,
  });

  final String name;
  final String tag;
  final String description;
  final double tone, body, decay, release, room, width, output;
  final double pickPos, damping, pickup, drive, chorus, reverbSize;
  final double dynamics, pitch, modRate, attack;
  String get displayName => name;
}

const List<LowkeyPresetData> kLowkeyPresets = <LowkeyPresetData>[
  LowkeyPresetData(
    name: 'Deep Pocket',
    tag: 'FOUNDATION',
    description: 'Round, controlled sub bass for grooves that need to sit low.',
    tone: .28,
    body: .88,
    decay: .62,
    release: .38,
    room: .08,
    width: .42,
    output: .82,
    pickPos: .50,
    damping: .72,
    pickup: .08,
    drive: .04,
    chorus: .00,
    reverbSize: .18,
    dynamics: .82,
    pitch: .50,
    modRate: .20,
    attack: .25,
  ),
  LowkeyPresetData(
    name: 'Tape Sub',
    tag: 'WARM',
    description: 'Soft-edged low end with a little wobble and tape weight.',
    tone: .34,
    body: .84,
    decay: .70,
    release: .50,
    room: .18,
    width: .52,
    output: .80,
    pickPos: .58,
    damping: .62,
    pickup: .14,
    drive: .24,
    chorus: .12,
    reverbSize: .28,
    dynamics: .74,
    pitch: .50,
    modRate: .16,
    attack: .20,
  ),
  LowkeyPresetData(
    name: 'Picked Modern',
    tag: 'POP',
    description: 'Defined pick attack that locks to modern drums.',
    tone: .72,
    body: .66,
    decay: .48,
    release: .28,
    room: .12,
    width: .55,
    output: .79,
    pickPos: .14,
    damping: .22,
    pickup: .36,
    drive: .10,
    chorus: .04,
    reverbSize: .20,
    dynamics: .88,
    pitch: .50,
    modRate: .25,
    attack: .84,
  ),
  LowkeyPresetData(
    name: 'Neon Fretless',
    tag: 'EXPRESSIVE',
    description: 'Fluid, singing mids with a wide late-night glow.',
    tone: .52,
    body: .72,
    decay: .74,
    release: .62,
    room: .42,
    width: .80,
    output: .76,
    pickPos: .62,
    damping: .28,
    pickup: .62,
    drive: .08,
    chorus: .48,
    reverbSize: .58,
    dynamics: .72,
    pitch: .50,
    modRate: .34,
    attack: .40,
  ),
  LowkeyPresetData(
    name: 'Grit Room',
    tag: 'AMPED',
    description: 'Small-room amp bark with enough dirt to speak through a mix.',
    tone: .64,
    body: .60,
    decay: .56,
    release: .34,
    room: .30,
    width: .58,
    output: .74,
    pickPos: .20,
    damping: .18,
    pickup: .86,
    drive: .62,
    chorus: .06,
    reverbSize: .34,
    dynamics: .76,
    pitch: .50,
    modRate: .28,
    attack: .78,
  ),
  LowkeyPresetData(
    name: 'Synth Bass',
    tag: 'HYBRID',
    description: 'A plucked string core pushed into a smooth mono synth shape.',
    tone: .46,
    body: .76,
    decay: .66,
    release: .44,
    room: .10,
    width: .46,
    output: .82,
    pickPos: .70,
    damping: .54,
    pickup: .42,
    drive: .18,
    chorus: .16,
    reverbSize: .22,
    dynamics: .68,
    pitch: .50,
    modRate: .22,
    attack: .18,
  ),
  LowkeyPresetData(
    name: 'Wide Chorus',
    tag: 'STEREO',
    description: 'Glossy doubled bass for hooks, intros, and spacious arrangements.',
    tone: .68,
    body: .62,
    decay: .72,
    release: .58,
    room: .38,
    width: .94,
    output: .75,
    pickPos: .36,
    damping: .12,
    pickup: .54,
    drive: .12,
    chorus: .78,
    reverbSize: .62,
    dynamics: .70,
    pitch: .50,
    modRate: .42,
    attack: .62,
  ),
  LowkeyPresetData(
    name: '808 Lowkey',
    tag: 'SUB',
    description: 'Long, clean low-end bloom with a clipped front edge.',
    tone: .24,
    body: .96,
    decay: .88,
    release: .72,
    room: .04,
    width: .38,
    output: .78,
    pickPos: .82,
    damping: .82,
    pickup: .10,
    drive: .30,
    chorus: .00,
    reverbSize: .12,
    dynamics: .64,
    pitch: .50,
    modRate: .12,
    attack: .12,
  ),
  LowkeyPresetData(
    name: 'Moog Pressure',
    tag: 'SYNTH',
    description: 'Dense resonant pressure with a warm, slightly broken edge.',
    tone: .58,
    body: .80,
    decay: .78,
    release: .66,
    room: .16,
    width: .58,
    output: .77,
    pickPos: .76,
    damping: .44,
    pickup: .72,
    drive: .42,
    chorus: .22,
    reverbSize: .26,
    dynamics: .62,
    pitch: .50,
    modRate: .30,
    attack: .22,
  ),
  LowkeyPresetData(
    name: 'Rubber Band',
    tag: 'FUNK',
    description: 'Springy, muted attack for playful syncopated lines.',
    tone: .76,
    body: .55,
    decay: .38,
    release: .22,
    room: .14,
    width: .48,
    output: .80,
    pickPos: .10,
    damping: .76,
    pickup: .34,
    drive: .16,
    chorus: .08,
    reverbSize: .20,
    dynamics: .92,
    pitch: .50,
    modRate: .26,
    attack: .90,
  ),
  LowkeyPresetData(
    name: 'Dub Siren',
    tag: 'DUB',
    description: 'Dark, slow and spacious with a smoky feedback trail.',
    tone: .20,
    body: .82,
    decay: .82,
    release: .88,
    room: .74,
    width: .88,
    output: .72,
    pickPos: .64,
    damping: .86,
    pickup: .26,
    drive: .20,
    chorus: .34,
    reverbSize: .92,
    dynamics: .58,
    pitch: .50,
    modRate: .18,
    attack: .16,
  ),
  LowkeyPresetData(
    name: 'Dark Cinema',
    tag: 'ATMOSPHERE',
    description: 'Cinematic low strings with ominous movement and width.',
    tone: .30,
    body: .90,
    decay: .90,
    release: .82,
    room: .68,
    width: .92,
    output: .70,
    pickPos: .56,
    damping: .68,
    pickup: .48,
    drive: .14,
    chorus: .28,
    reverbSize: .86,
    dynamics: .60,
    pitch: .50,
    modRate: .14,
    attack: .12,
  ),
  LowkeyPresetData(
    name: 'Slap Snap',
    tag: 'ATTACK',
    description: 'Bright thumb and pop articulation with a tight tail.',
    tone: .90,
    body: .48,
    decay: .34,
    release: .18,
    room: .12,
    width: .60,
    output: .78,
    pickPos: .06,
    damping: .08,
    pickup: .28,
    drive: .12,
    chorus: .02,
    reverbSize: .18,
    dynamics: .96,
    pitch: .50,
    modRate: .30,
    attack: .96,
  ),
  LowkeyPresetData(
    name: 'Acid Low End',
    tag: 'MOVEMENT',
    description: 'Rubbery resonance and bite for restless bass patterns.',
    tone: .78,
    body: .64,
    decay: .54,
    release: .40,
    room: .10,
    width: .50,
    output: .76,
    pickPos: .18,
    damping: .20,
    pickup: .78,
    drive: .52,
    chorus: .10,
    reverbSize: .24,
    dynamics: .74,
    pitch: .50,
    modRate: .62,
    attack: .68,
  ),
  LowkeyPresetData(
    name: 'Clean Fingerstyle',
    tag: 'NATURAL',
    description: 'Detailed fingers, woody body and an honest studio room.',
    tone: .58,
    body: .86,
    decay: .52,
    release: .30,
    room: .26,
    width: .56,
    output: .83,
    pickPos: .48,
    damping: .18,
    pickup: .22,
    drive: .00,
    chorus: .00,
    reverbSize: .30,
    dynamics: .94,
    pitch: .50,
    modRate: .20,
    attack: .48,
  ),
  LowkeyPresetData(
    name: 'Submarine',
    tag: 'DEEP',
    description: 'A submerged pulse with soft transients and huge body.',
    tone: .16,
    body: .98,
    decay: .84,
    release: .76,
    room: .22,
    width: .66,
    output: .74,
    pickPos: .72,
    damping: .92,
    pickup: .06,
    drive: .10,
    chorus: .18,
    reverbSize: .46,
    dynamics: .56,
    pitch: .50,
    modRate: .10,
    attack: .10,
  ),
];

class LowkeyStockEditor extends StatefulWidget {
  const LowkeyStockEditor({
    this.preset = 0,
    this.tone = .35,
    this.body = .8,
    this.decay = .6,
    this.release = .4,
    this.room = .1,
    this.width = .5,
    this.output = .8,
    this.pickPos = .5,
    this.damping = .6,
    this.pickup = .1,
    this.drive = .05,
    this.chorus = 0,
    this.reverbSize = .2,
    this.dynamics = .8,
    this.pitch = .5,
    this.modRate = .2,
    this.attack = .3,
    this.onPresetChanged,
    this.onToneChanged,
    this.onBodyChanged,
    this.onDecayChanged,
    this.onReleaseChanged,
    this.onRoomChanged,
    this.onWidthChanged,
    this.onOutputChanged,
    this.onPickPosChanged,
    this.onDampingChanged,
    this.onPickupChanged,
    this.onDriveChanged,
    this.onChorusChanged,
    this.onReverbSizeChanged,
    this.onDynamicsChanged,
    this.onPitchChanged,
    this.onModRateChanged,
    this.onAttackChanged,
    this.onAuditionNoteOn,
    this.onAuditionNoteOff,
    super.key,
  });
  final double preset,
      tone,
      body,
      decay,
      release,
      room,
      width,
      output,
      pickPos,
      damping,
      pickup,
      drive,
      chorus,
      reverbSize,
      dynamics,
      pitch,
      modRate,
      attack;
  final ValueChanged<int>? onPresetChanged;
  final ValueChanged<double>? onToneChanged,
      onBodyChanged,
      onDecayChanged,
      onReleaseChanged,
      onRoomChanged,
      onWidthChanged,
      onOutputChanged,
      onPickPosChanged,
      onDampingChanged,
      onPickupChanged,
      onDriveChanged,
      onChorusChanged,
      onReverbSizeChanged,
      onDynamicsChanged,
      onPitchChanged,
      onModRateChanged,
      onAttackChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final void Function(int key)? onAuditionNoteOff;
  @override
  State<LowkeyStockEditor> createState() => _LowkeyStockEditorState();
}

class _LowkeyStockEditorState extends State<LowkeyStockEditor> {
  bool menu = false;
  int get index => (widget.preset * kLowkeyPresets.length).floor().clamp(
    0,
    kLowkeyPresets.length - 1,
  );
  void select(int value) {
    setState(() => menu = false);
    widget.onPresetChanged?.call(value);
  }

  void step(int amount) => select((index + amount + kLowkeyPresets.length) % kLowkeyPresets.length);

  @override
  Widget build(BuildContext context) {
    final LowkeyPresetData current = kLowkeyPresets[index];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff101316),
        border: Border.all(color: const Color(0xff313b3d)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            children: [
              _LowkeyHeader(
                current: current,
                index: index,
                menu: menu,
                onMenu: () => setState(() => menu = !menu),
                onPrev: () => step(-1),
                onNext: () => step(1),
                pitch: widget.pitch,
                output: widget.output,
                onPitch: widget.onPitchChanged,
                onOutput: widget.onOutputChanged,
              ),
              Expanded(
                child: _LowkeyBody(
                  preset: current,
                  tone: widget.tone,
                  body: widget.body,
                  pickPos: widget.pickPos,
                  damping: widget.damping,
                  pickup: widget.pickup,
                  drive: widget.drive,
                  attack: widget.attack,
                  decay: widget.decay,
                  release: widget.release,
                  room: widget.room,
                  chorus: widget.chorus,
                  reverbSize: widget.reverbSize,
                  dynamics: widget.dynamics,
                  width: widget.width,
                  onTone: widget.onToneChanged,
                  onBody: widget.onBodyChanged,
                  onPickPos: widget.onPickPosChanged,
                  onDamping: widget.onDampingChanged,
                  onPickup: widget.onPickupChanged,
                  onDrive: widget.onDriveChanged,
                  onAttack: widget.onAttackChanged,
                  onDecay: widget.onDecayChanged,
                  onRelease: widget.onReleaseChanged,
                  onRoom: widget.onRoomChanged,
                  onChorus: widget.onChorusChanged,
                  onReverbSize: widget.onReverbSizeChanged,
                  onDynamics: widget.onDynamicsChanged,
                  onWidth: widget.onWidthChanged,
                  onNoteOn: widget.onAuditionNoteOn,
                  onNoteOff: widget.onAuditionNoteOff,
                ),
              ),
            ],
          ),
          if (menu)
            Positioned(
              left: 18,
              top: 78,
              right: 18,
              child: _PresetMenu(selected: index, onSelect: select),
            ),
        ],
      ),
    );
  }
}

class _LowkeyBody extends StatelessWidget {
  const _LowkeyBody({
    required this.preset,
    required this.tone,
    required this.body,
    required this.pickPos,
    required this.damping,
    required this.pickup,
    required this.drive,
    required this.attack,
    required this.decay,
    required this.release,
    required this.room,
    required this.chorus,
    required this.reverbSize,
    required this.dynamics,
    required this.width,
    this.onTone,
    this.onBody,
    this.onPickPos,
    this.onDamping,
    this.onPickup,
    this.onDrive,
    this.onAttack,
    this.onDecay,
    this.onRelease,
    this.onRoom,
    this.onChorus,
    this.onReverbSize,
    this.onDynamics,
    this.onWidth,
    this.onNoteOn,
    this.onNoteOff,
  });

  final LowkeyPresetData preset;
  final double tone, body, pickPos, damping, pickup, drive;
  final double attack, decay, release, room, chorus, reverbSize, dynamics, width;
  final ValueChanged<double>? onTone, onBody, onPickPos, onDamping, onPickup, onDrive;
  final ValueChanged<double>? onAttack, onDecay, onRelease, onRoom, onChorus;
  final ValueChanged<double>? onReverbSize, onDynamics, onWidth;
  final void Function(int, double)? onNoteOn;
  final void Function(int)? onNoteOff;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xff101416),
    child: Builder(
      builder: (context) {
        final bool compact = MediaQuery.sizeOf(context).width < 720;
        final Widget deck = _InstrumentDeck(
          preset: preset,
          tone: tone,
          body: body,
          onTone: onTone,
          onBody: onBody,
        );
        final Widget shape = _ShapeRack(
          pickPos: pickPos,
          damping: damping,
          pickup: pickup,
          drive: drive,
          onPickPos: onPickPos,
          onDamping: onDamping,
          onPickup: onPickup,
          onDrive: onDrive,
        );
        final Widget envelope = _RackSection(
          title: 'ENVELOPE',
          accent: const Color(0xff6ee7d0),
          knobs: [
            _Knob(label: 'ATTACK', value: attack, onChanged: onAttack),
            _Knob(label: 'DECAY', value: decay, onChanged: onDecay),
            _Knob(label: 'RELEASE', value: release, onChanged: onRelease),
            _Knob(label: 'DYNAMICS', value: dynamics, onChanged: onDynamics),
          ],
        );
        final Widget space = _RackSection(
          title: 'SPACE / WIDTH',
          accent: const Color(0xff6ee7d0),
          knobs: [
            _Knob(label: 'ROOM', value: room, onChanged: onRoom),
            _Knob(label: 'CHORUS', value: chorus, onChanged: onChorus),
            _Knob(label: 'REVERB', value: reverbSize, onChanged: onReverbSize),
            _Knob(label: 'WIDTH', value: width, onChanged: onWidth),
          ],
        );
        final Widget top = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [deck, const SizedBox(height: 12), shape],
              )
            : SizedBox(
                height: 260,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: deck),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: shape),
                  ],
                ),
              );
        final Widget lower = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [envelope, const SizedBox(height: 12), space],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: envelope),
                  const SizedBox(width: 14),
                  Expanded(child: space),
                ],
              );
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              top,
              const SizedBox(height: 12),
              lower,
              const SizedBox(height: 12),
              _BassKeyboard(onNoteOn: onNoteOn, onNoteOff: onNoteOff),
            ],
          ),
        );
      },
    ),
  );
}

class _InstrumentDeck extends StatelessWidget {
  const _InstrumentDeck({
    required this.preset,
    required this.tone,
    required this.body,
    this.onTone,
    this.onBody,
  });
  final LowkeyPresetData preset;
  final double tone, body;
  final ValueChanged<double>? onTone, onBody;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 200),
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    decoration: BoxDecoration(
      color: const Color(0xff192022),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff30403f)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'LOW FREQUENCY ENGINE',
              style: TextStyle(
                color: Color(0xff8ca49d),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              preset.tag,
              style: const TextStyle(
                color: Color(0xffc3f26b),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: Center(
            child: Row(
              children: [
                const _LevelMeter(label: 'SUB', value: .78, color: Color(0xffc3f26b)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LargeDial(value: body, color: const Color(0xff6ee7d0), onChanged: onBody),
                      const SizedBox(height: 8),
                      const Text(
                        'BODY',
                        style: TextStyle(
                          color: Color(0xff9eb2aa),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        '${(body * 100).round()}',
                        style: const TextStyle(
                          color: Color(0xff6ee7d0),
                          fontSize: 13,
                          fontFamily: 'MartianMono',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LargeDial(
                        value: tone,
                        color: const Color(0xffc3f26b),
                        onChanged: onTone,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'TONE',
                        style: TextStyle(
                          color: Color(0xff9eb2aa),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        '${(tone * 100).round()}',
                        style: const TextStyle(
                          color: Color(0xffc3f26b),
                          fontSize: 13,
                          fontFamily: 'MartianMono',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const _LevelMeter(
                  label: 'OUT',
                  value: .64,
                  color: Color(0xff6ee7d0),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            preset.description,
            style: const TextStyle(
              color: Color(0xffb4c4bd),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ShapeRack extends StatelessWidget {
  const _ShapeRack({
    required this.pickPos,
    required this.damping,
    required this.pickup,
    required this.drive,
    this.onPickPos,
    this.onDamping,
    this.onPickup,
    this.onDrive,
  });

  final double pickPos, damping, pickup, drive;
  final ValueChanged<double>? onPickPos, onDamping, onPickup, onDrive;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 200),
    padding: const EdgeInsets.fromLTRB(14, 16, 18, 18),
    decoration: BoxDecoration(
      color: const Color(0xff192022),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff30403f)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SHAPE',
          style: TextStyle(color: Color(0xffc3f26b), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.55,
          crossAxisSpacing: 8,
          mainAxisSpacing: 4,
          children: [
            _Knob(label: 'PLUCK', value: pickPos, size: 58, onChanged: onPickPos),
            _Knob(label: 'DAMP', value: damping, size: 58, onChanged: onDamping),
            _Knob(label: 'PICKUP', value: pickup, size: 58, onChanged: onPickup),
            _Knob(label: 'DRIVE', value: drive, size: 58, onChanged: onDrive),
          ],
        ),
      ],
    ),
  );
}

class _RackSection extends StatelessWidget {
  const _RackSection({
    required this.title,
    required this.accent,
    required this.knobs,
  });
  final String title;
  final Color accent;
  final List<Widget> knobs;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: const Color(0xff192022),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff30403f)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: accent,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final Widget knob in knobs) Expanded(child: Center(child: knob)),
          ],
        ),
      ],
    ),
  );
}

class _LargeDial extends StatelessWidget {
  const _LargeDial({required this.value, required this.color, this.onChanged});
  final double value;
  final Color color;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragUpdate: onChanged == null ? null : (d) => onChanged!((value - d.primaryDelta! / 160).clamp(0.0, 1.0)),
    child: CustomPaint(
      size: const Size(92, 92),
      painter: _LargeDialPainter(value: value, color: color),
    ),
  );
}

class _LargeDialPainter extends CustomPainter {
  const _LargeDialPainter({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 7;
    final Paint track = Paint()
      ..color = const Color(0xff2c3a3a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final Paint active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.35,
      3.8,
      false,
      track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.35,
      3.8 * value,
      false,
      active,
    );
    canvas.drawCircle(
      center,
      radius - 10,
      Paint()..color = const Color(0xff202a2a),
    );
    final double angle = 2.35 + 3.8 * value;
    canvas.drawLine(
      center,
      Offset(
        center.dx + (radius - 18) * math.cos(angle),
        center.dy + (radius - 18) * math.sin(angle),
      ),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_LargeDialPainter old) => old.value != value || old.color != color;
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 8,
        height: 62,
        child: CustomPaint(
          painter: _MeterPainter(value: value, color: color),
        ),
      ),
      const SizedBox(height: 7),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xff879e96),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint off = Paint()..color = const Color(0xff2b3737);
    final Paint on = Paint()..color = color;
    for (int i = 0; i < 12; i++) {
      final double y = size.height - i * 7 - 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y, size.width, 4),
          const Radius.circular(2),
        ),
        i / 12 < value ? on : off,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.value != value || old.color != color;
}

class _LowkeyHeader extends StatelessWidget {
  const _LowkeyHeader({
    required this.current,
    required this.index,
    required this.menu,
    required this.onMenu,
    required this.onPrev,
    required this.onNext,
    required this.pitch,
    required this.output,
    this.onPitch,
    this.onOutput,
  });
  final LowkeyPresetData current;
  final int index;
  final bool menu;
  final VoidCallback onMenu, onPrev, onNext;
  final double pitch, output;
  final ValueChanged<double>? onPitch, onOutput;
  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      color: Color(0xff171d1f),
      border: Border(bottom: BorderSide(color: Color(0xff2b3535))),
    ),
    child: Row(
      children: [
        const Text(
          'LOWKEY',
          style: TextStyle(
            color: Color(0xffc3f26b),
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: GestureDetector(
            onTap: onMenu,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xff20292a),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    '${(index + 1).toString().padLeft(2, '0')}  ${current.name}',
                    style: const TextStyle(
                      color: Color(0xfff0f4e9),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    current.tag,
                    style: const TextStyle(
                      color: Color(0xff83a297),
                      fontSize: 10,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    menu ? '▲' : '▼',
                    style: const TextStyle(
                      color: Color(0xffc3f26b),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _Arrow(icon: '‹', onTap: onPrev),
        _Arrow(icon: '›', onTap: onNext),
        const SizedBox(width: 12),
        _MiniKnob(label: 'TUNE', value: pitch, onChanged: onPitch),
        _MiniKnob(label: 'OUT', value: output, onChanged: onOutput),
      ],
    ),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final String icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        icon,
        style: const TextStyle(
          color: Color(0xff9ab2aa),
          fontSize: 28,
          height: .8,
        ),
      ),
    ),
  );
}

class _MiniKnob extends StatelessWidget {
  const _MiniKnob({required this.label, required this.value, this.onChanged});
  final String label;
  final double value;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    child: _Knob(label: label, value: value, size: 28, onChanged: onChanged),
  );
}

class _Knob extends StatelessWidget {
  const _Knob({
    required this.label,
    required this.value,
    this.size = 44,
    this.onChanged,
  });
  final String label;
  final double value, size;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragUpdate: onChanged == null ? null : (d) => onChanged!((value - d.primaryDelta! / 140).clamp(0.0, 1.0)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _KnobPainter(value: value, color: const Color(0xff6ee7d0)),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: const Color(0xff9aaca5),
            fontSize: size < 35 ? 8 : 9,
            letterSpacing: .8,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${(value * 100).round()}',
          style: const TextStyle(
            color: Color(0xff6ee7d0),
            fontSize: 9,
            fontFamily: 'MartianMono',
          ),
        ),
      ],
    ),
  );
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 3;
    final base = Paint()
      ..color = const Color(0xff2c3737)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    c.drawArc(
      Rect.fromCircle(center: center, radius: r),
      2.35,
      2.7,
      false,
      base,
    );
    final active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    c.drawArc(
      Rect.fromCircle(center: center, radius: r),
      2.35,
      2.7 * value,
      false,
      active,
    );
    c.drawCircle(center, r - 5, Paint()..color = const Color(0xff202829));
    final a = 2.35 + 2.7 * value;
    c.drawLine(
      center,
      Offset(center.dx + (r - 7) * _cos(a), center.dy + (r - 7) * _sin(a)),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  double _cos(double v) => _Trig.cos(v);
  double _sin(double v) => _Trig.sin(v);
  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value || old.color != color;
}

class _Trig {
  static double cos(double v) => math.cos(v);
  static double sin(double v) => math.sin(v);
}

class _PresetMenu extends StatelessWidget {
  const _PresetMenu({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 330),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xff20292a),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff536a62)),
      boxShadow: const [BoxShadow(color: Color(0xaa000000), blurRadius: 20)],
    ),
    child: ListView.builder(
      itemCount: kLowkeyPresets.length,
      itemBuilder: (context, i) {
        final p = kLowkeyPresets[i];
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: i == selected ? const Color(0xff33443d) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Text(
                  (i + 1).toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: Color(0xff76938a),
                    fontFamily: 'MartianMono',
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      color: Color(0xffedf4e9),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  p.tag,
                  style: const TextStyle(
                    color: Color(0xff91aba0),
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _BassKeyboard extends StatelessWidget {
  const _BassKeyboard({this.onNoteOn, this.onNoteOff});
  final void Function(int, double)? onNoteOn;
  final void Function(int)? onNoteOff;
  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(
      color: const Color(0xff151c1d),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff2e3c3c)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const int whiteCount = 15;
        const List<int> blackOffsets = [0, 1, 3, 4, 5, 7, 8, 10, 11, 12];
        final double whiteWidth = constraints.maxWidth / whiteCount;
        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(whiteCount, (index) {
                final int key = 36 + index + (index ~/ 7);
                return Expanded(
                  child: GestureDetector(
                    onTapDown: (_) => onNoteOn?.call(key, .82),
                    onTapUp: (_) => onNoteOff?.call(key),
                    onTapCancel: () => onNoteOff?.call(key),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xffe4ece4),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xffc1d0c5)),
                      ),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: 5),
                      child: index % 7 == 0
                          ? const Text(
                              'C',
                              style: TextStyle(
                                color: Color(0xff78877f),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                  ),
                );
              }),
            ),
            ...blackOffsets.map((offset) {
              final int key = 37 + offset + (offset ~/ 7);
              return Positioned(
                left: (offset + 1) * whiteWidth - whiteWidth * .30,
                top: 0,
                width: whiteWidth * .60,
                height: 62,
                child: GestureDetector(
                  onTapDown: (_) => onNoteOn?.call(key, .8),
                  onTapUp: (_) => onNoteOff?.call(key),
                  onTapCancel: () => onNoteOff?.call(key),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xff263232),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(4),
                      ),
                      border: Border.all(color: const Color(0xff3b4b49)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    ),
  );
}
