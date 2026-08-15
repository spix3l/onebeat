import 'dart:math' as math;
import 'package:flutter/widgets.dart';

class GuitarPresetData {
  const GuitarPresetData({
    required this.id,
    required this.category,
    required this.name,
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

  final String id;
  final String category;
  final String name;
  final String description;
  final double tone;
  final double body;
  final double decay;
  final double release;
  final double room;
  final double width;
  final double output;
  final double pickPos;
  final double damping;
  final double pickup;
  final double drive;
  final double chorus;
  final double reverbSize;
  final double dynamics;
  final double pitch;
  final double modRate;
  final double attack;

  String get displayName => '* $category: $name *';
}

const List<GuitarPresetData> kGuitarPresets = <GuitarPresetData>[
  GuitarPresetData(
    id: '01',
    category: 'Acoustic',
    name: 'Steel String Pluck',
    description:
        'Crisp, resonant dreadnought acoustic steel strings with full body resonance',
    tone: 0.75,
    body: 0.70,
    decay: 0.65,
    release: 0.35,
    room: 0.30,
    width: 0.65,
    output: 0.80,
    pickPos: 0.25,
    damping: 0.15,
    pickup: 0.00,
    drive: 0.00,
    chorus: 0.00,
    reverbSize: 0.50,
    dynamics: 0.80,
    pitch: 0.50,
    modRate: 0.30,
    attack: 0.65,
  ),
  GuitarPresetData(
    id: '02',
    category: 'Acoustic',
    name: 'Nylon Fingerstyle',
    description:
        'Intimate, warm classical nylon guitar with delicate fingerstyle transients',
    tone: 0.45,
    body: 0.80,
    decay: 0.55,
    release: 0.30,
    room: 0.25,
    width: 0.55,
    output: 0.82,
    pickPos: 0.40,
    damping: 0.10,
    pickup: 0.00,
    drive: 0.00,
    chorus: 0.00,
    reverbSize: 0.45,
    dynamics: 0.85,
    pitch: 0.50,
    modRate: 0.30,
    attack: 0.40,
  ),
  GuitarPresetData(
    id: '03',
    category: 'Acoustic',
    name: '12-String Shimmer',
    description:
        'Chimey, shimmering 12-string acoustic with octave resonance and stereo spread',
    tone: 0.85,
    body: 0.60,
    decay: 0.75,
    release: 0.45,
    room: 0.45,
    width: 0.85,
    output: 0.78,
    pickPos: 0.20,
    damping: 0.10,
    pickup: 0.00,
    drive: 0.05,
    chorus: 0.55,
    reverbSize: 0.65,
    dynamics: 0.75,
    pitch: 0.50,
    modRate: 0.35,
    attack: 0.70,
  ),
  GuitarPresetData(
    id: '04',
    category: 'Acoustic',
    name: 'Muted Folk',
    description:
        'Tight palm-muted acoustic rhythm guitar with punchy percussive attack',
    tone: 0.50,
    body: 0.65,
    decay: 0.35,
    release: 0.20,
    room: 0.20,
    width: 0.50,
    output: 0.85,
    pickPos: 0.15,
    damping: 0.75,
    pickup: 0.00,
    drive: 0.00,
    chorus: 0.00,
    reverbSize: 0.30,
    dynamics: 0.90,
    pitch: 0.50,
    modRate: 0.30,
    attack: 0.80,
  ),
  GuitarPresetData(
    id: '05',
    category: 'Acoustic',
    name: 'Resonator Slide',
    description:
        'Metallic dobro-style resonator guitar with rich mid harmonics and slide sustain',
    tone: 0.80,
    body: 0.50,
    decay: 0.80,
    release: 0.50,
    room: 0.40,
    width: 0.70,
    output: 0.78,
    pickPos: 0.18,
    damping: 0.05,
    pickup: 0.20,
    drive: 0.15,
    chorus: 0.10,
    reverbSize: 0.60,
    dynamics: 0.70,
    pitch: 0.50,
    modRate: 0.40,
    attack: 0.75,
  ),
  GuitarPresetData(
    id: '06',
    category: 'Electric',
    name: 'Clean Strat Pluck',
    description:
        'Glassy single-coil electric tone with bell-like attack and transparent presence',
    tone: 0.75,
    body: 0.40,
    decay: 0.60,
    release: 0.35,
    room: 0.35,
    width: 0.65,
    output: 0.80,
    pickPos: 0.30,
    damping: 0.10,
    pickup: 0.50,
    drive: 0.10,
    chorus: 0.15,
    reverbSize: 0.50,
    dynamics: 0.80,
    pitch: 0.50,
    modRate: 0.30,
    attack: 0.60,
  ),
  GuitarPresetData(
    id: '07',
    category: 'Electric',
    name: 'Warm Jazz Archtop',
    description:
        'Mellow hollowbody jazz guitar with neck humbucker and dark woody warmth',
    tone: 0.40,
    body: 0.75,
    decay: 0.70,
    release: 0.40,
    room: 0.30,
    width: 0.60,
    output: 0.82,
    pickPos: 0.45,
    damping: 0.15,
    pickup: 0.85,
    drive: 0.05,
    chorus: 0.00,
    reverbSize: 0.45,
    dynamics: 0.85,
    pitch: 0.50,
    modRate: 0.25,
    attack: 0.45,
  ),
  GuitarPresetData(
    id: '08',
    category: 'Electric',
    name: 'Overdriven Lead',
    description:
        'Saturated singing tube overdrive lead guitar with harmonic sustain and crunch',
    tone: 0.70,
    body: 0.55,
    decay: 0.85,
    release: 0.45,
    room: 0.40,
    width: 0.75,
    output: 0.76,
    pickPos: 0.22,
    damping: 0.05,
    pickup: 0.90,
    drive: 0.65,
    chorus: 0.20,
    reverbSize: 0.55,
    dynamics: 0.65,
    pitch: 0.50,
    modRate: 0.45,
    attack: 0.70,
  ),
  GuitarPresetData(
    id: '09',
    category: 'Electric',
    name: '80s Chorus Dream',
    description:
        'Lush stereo modulated chorus electric guitar with ambient shimmering space',
    tone: 0.80,
    body: 0.45,
    decay: 0.75,
    release: 0.50,
    room: 0.60,
    width: 0.90,
    output: 0.78,
    pickPos: 0.28,
    damping: 0.05,
    pickup: 0.60,
    drive: 0.15,
    chorus: 0.70,
    reverbSize: 0.70,
    dynamics: 0.75,
    pitch: 0.50,
    modRate: 0.40,
    attack: 0.60,
  ),
  GuitarPresetData(
    id: '10',
    category: 'Electric',
    name: 'Ambient Slide',
    description:
        'Cavernous ambient swelling guitar with wide plate reverberation and long tail',
    tone: 0.60,
    body: 0.60,
    decay: 0.90,
    release: 0.75,
    room: 0.80,
    width: 0.95,
    output: 0.75,
    pickPos: 0.35,
    damping: 0.00,
    pickup: 0.70,
    drive: 0.25,
    chorus: 0.50,
    reverbSize: 0.90,
    dynamics: 0.70,
    pitch: 0.50,
    modRate: 0.25,
    attack: 0.35,
  ),
  GuitarPresetData(
    id: '11',
    category: 'Acoustic',
    name: 'Flamenco Passion',
    description:
        'High-tension spanish flamenco nylon guitar with aggressive rasp and snap attack',
    tone: 0.70,
    body: 0.70,
    decay: 0.50,
    release: 0.25,
    room: 0.30,
    width: 0.60,
    output: 0.82,
    pickPos: 0.18,
    damping: 0.20,
    pickup: 0.00,
    drive: 0.05,
    chorus: 0.00,
    reverbSize: 0.40,
    dynamics: 0.90,
    pitch: 0.50,
    modRate: 0.30,
    attack: 0.85,
  ),
  GuitarPresetData(
    id: '12',
    category: 'Electric',
    name: 'Lo-Fi Muted',
    description:
        'Warm vintage vinyl-filtered electric guitar with subtle tape flutter and saturation',
    tone: 0.35,
    body: 0.65,
    decay: 0.45,
    release: 0.30,
    room: 0.35,
    width: 0.50,
    output: 0.80,
    pickPos: 0.30,
    damping: 0.60,
    pickup: 0.75,
    drive: 0.30,
    chorus: 0.30,
    reverbSize: 0.40,
    dynamics: 0.85,
    pitch: 0.50,
    modRate: 0.20,
    attack: 0.55,
  ),
];

class GuitarStockEditor extends StatefulWidget {
  const GuitarStockEditor({
    this.preset = 0.0,
    this.tone = 0.70,
    this.body = 0.65,
    this.decay = 0.65,
    this.release = 0.35,
    this.room = 0.30,
    this.width = 0.60,
    this.output = 0.80,
    this.pickPos = 0.25,
    this.damping = 0.20,
    this.pickup = 0.00,
    this.drive = 0.00,
    this.chorus = 0.00,
    this.reverbSize = 0.50,
    this.dynamics = 0.80,
    this.pitch = 0.50,
    this.modRate = 0.30,
    this.attack = 0.60,
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

  final double preset;
  final double tone;
  final double body;
  final double decay;
  final double release;
  final double room;
  final double width;
  final double output;
  final double pickPos;
  final double damping;
  final double pickup;
  final double drive;
  final double chorus;
  final double reverbSize;
  final double dynamics;
  final double pitch;
  final double modRate;
  final double attack;

  final ValueChanged<int>? onPresetChanged;
  final ValueChanged<double>? onToneChanged;
  final ValueChanged<double>? onBodyChanged;
  final ValueChanged<double>? onDecayChanged;
  final ValueChanged<double>? onReleaseChanged;
  final ValueChanged<double>? onRoomChanged;
  final ValueChanged<double>? onWidthChanged;
  final ValueChanged<double>? onOutputChanged;
  final ValueChanged<double>? onPickPosChanged;
  final ValueChanged<double>? onDampingChanged;
  final ValueChanged<double>? onPickupChanged;
  final ValueChanged<double>? onDriveChanged;
  final ValueChanged<double>? onChorusChanged;
  final ValueChanged<double>? onReverbSizeChanged;
  final ValueChanged<double>? onDynamicsChanged;
  final ValueChanged<double>? onPitchChanged;
  final ValueChanged<double>? onModRateChanged;
  final ValueChanged<double>? onAttackChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final void Function(int key)? onAuditionNoteOff;

  @override
  State<GuitarStockEditor> createState() => _GuitarStockEditorState();
}

class _GuitarStockEditorState extends State<GuitarStockEditor> {
  bool _isPresetMenuOpen = false;
  int _octaveShift = 0;
  double _pitchBend = 0.5;
  double _modWheel = 0.0;

  int get _presetIndex => (widget.preset * kGuitarPresets.length).floor().clamp(
    0,
    kGuitarPresets.length - 1,
  );

  void _handlePresetSelect(int index) {
    setState(() => _isPresetMenuOpen = false);
    widget.onPresetChanged?.call(index);
  }

  void _handlePrevPreset() {
    final int next =
        (_presetIndex - 1 + kGuitarPresets.length) % kGuitarPresets.length;
    widget.onPresetChanged?.call(next);
  }

  void _handleNextPreset() {
    final int next = (_presetIndex + 1) % kGuitarPresets.length;
    widget.onPresetChanged?.call(next);
  }

  void _togglePresetMenu() {
    setState(() => _isPresetMenuOpen = !_isPresetMenuOpen);
  }

  void _handleOctaveDown() {
    if (_octaveShift > -2) {
      setState(() => _octaveShift--);
    }
  }

  void _handleOctaveUp() {
    if (_octaveShift < 2) {
      setState(() => _octaveShift++);
    }
  }

  void _handlePitchBend(double value) {
    setState(() => _pitchBend = value);
    widget.onPitchChanged?.call(value);
  }

  void _handleModWheel(double value) {
    setState(() => _modWheel = value);
    widget.onChorusChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final int currentIdx = _presetIndex;
    final GuitarPresetData currentPreset = kGuitarPresets[currentIdx];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1EFEA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E2024), width: 1.0),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // Top System Bar (One Audio Dark Bar)
              _OneAudioTopBar(
                tune: widget.pitch,
                pan: widget.width,
                volume: widget.output,
                onTuneChanged: widget.onPitchChanged,
                onPanChanged: widget.onWidthChanged,
                onVolumeChanged: widget.onOutputChanged,
              ),

              // Preset Header Pill Bar
              _PresetHeaderBar(
                presetName: currentPreset.displayName,
                isMenuOpen: _isPresetMenuOpen,
                onToggleMenu: _togglePresetMenu,
                onPrev: _handlePrevPreset,
                onNext: _handleNextPreset,
              ),

              // Main Light Canvas (Dual Faders + Big Central Wheel)
              Expanded(
                child: _MainControlCanvas(
                  dynamics: widget.dynamics,
                  reverb: widget.room,
                  toneWheel: widget.tone,
                  onDynamicsChanged: widget.onDynamicsChanged,
                  onReverbChanged: widget.onRoomChanged,
                  onToneWheelChanged: widget.onToneChanged,
                ),
              ),

              // Bottom Virtual Keyboard & Controls
              _BottomKeyboardBar(
                octaveShift: _octaveShift,
                pitchBend: _pitchBend,
                modWheel: _modWheel,
                onOctaveDown: _handleOctaveDown,
                onOctaveUp: _handleOctaveUp,
                onPitchBendChanged: _handlePitchBend,
                onModWheelChanged: _handleModWheel,
                onAuditionNoteOn: widget.onAuditionNoteOn,
                onAuditionNoteOff: widget.onAuditionNoteOff,
              ),
            ],
          ),

          // Preset Selection Dropdown (Directly anchored below the preset bar)
          if (_isPresetMenuOpen)
            _PresetDropdownPanel(
              selectedIndex: currentIdx,
              presets: kGuitarPresets,
              onSelect: _handlePresetSelect,
              onClose: _togglePresetMenu,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top System Bar (One Audio Dark Header)
// ---------------------------------------------------------------------------
class _OneAudioTopBar extends StatelessWidget {
  const _OneAudioTopBar({
    required this.tune,
    required this.pan,
    required this.volume,
    this.onTuneChanged,
    this.onPanChanged,
    this.onVolumeChanged,
  });

  final double tune;
  final double pan;
  final double volume;
  final ValueChanged<double>? onTuneChanged;
  final ValueChanged<double>? onPanChanged;
  final ValueChanged<double>? onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141517),
        border: Border(bottom: BorderSide(color: Color(0xFF22252A), width: 1)),
      ),
      child: Row(
        children: <Widget>[
          // Brand Label
          const Text(
            'ONE AUDIO',
            style: TextStyle(
              color: Color(0xFFE2E4E8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.8,
              fontFamily: 'Inter',
            ),
          ),

          const Spacer(),

          // TUNE Mini Knob
          _TopMiniKnob(label: 'TUNE', value: tune, onChanged: onTuneChanged),
          const SizedBox(width: 16),

          // PAN Mini Knob
          _TopMiniKnob(label: 'PAN', value: pan, onChanged: onPanChanged),
          const SizedBox(width: 16),

          // VOL Mini Slider
          _TopMiniSlider(
            label: 'VOL',
            value: volume,
            onChanged: onVolumeChanged,
          ),
        ],
      ),
    );
  }
}

class _TopMiniKnob extends StatelessWidget {
  const _TopMiniKnob({
    required this.label,
    required this.value,
    this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        onVerticalDragUpdate: (DragUpdateDetails details) {
          final double next = (value - details.primaryDelta! * 0.01).clamp(
            0.0,
            1.0,
          );
          onChanged?.call(next);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$label ',
              style: const TextStyle(
                color: Color(0xFF8E929B),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF24272D),
                border: Border.all(color: const Color(0xFF4A4E57), width: 1),
              ),
              child: CustomPaint(painter: _MiniKnobPainter(value: value)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniKnobPainter extends CustomPainter {
  _MiniKnobPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double angle = -math.pi * 0.75 + value * (math.pi * 1.5);
    final double r = size.width / 2 - 3;
    final Offset dot = Offset(
      center.dx + r * math.cos(angle),
      center.dy + r * math.sin(angle),
    );
    final Paint dotPaint = Paint()
      ..color = const Color(0xFFE2E4E8)
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dot, 1.5, dotPaint);
  }

  @override
  bool shouldRepaint(_MiniKnobPainter oldDelegate) =>
      oldDelegate.value != value;
}

class _TopMiniSlider extends StatelessWidget {
  const _TopMiniSlider({
    required this.label,
    required this.value,
    this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          final double next = (value + details.primaryDelta! * 0.02).clamp(
            0.0,
            1.0,
          );
          onChanged?.call(next);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$label ',
              style: const TextStyle(
                color: Color(0xFF8E929B),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF24272D),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                children: <Widget>[
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E4E8),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preset Header Bar (Slate-Toned Pill with Vector Chevrons & Hover States)
// ---------------------------------------------------------------------------
class _PresetHeaderBar extends StatefulWidget {
  const _PresetHeaderBar({
    required this.presetName,
    required this.isMenuOpen,
    required this.onToggleMenu,
    required this.onPrev,
    required this.onNext,
  });

  final String presetName;
  final bool isMenuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  State<_PresetHeaderBar> createState() => _PresetHeaderBarState();
}

class _PresetHeaderBarState extends State<_PresetHeaderBar> {
  bool _isPillHovered = false;
  bool _isDownHovered = false;
  bool _isPrevHovered = false;
  bool _isNextHovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      height: 38,
      decoration: BoxDecoration(
        color: _isPillHovered
            ? const Color(0xFFBDCBD5)
            : const Color(0xFFB0BFC9),
        borderRadius: BorderRadius.circular(5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          // Down vector arrow for dropdown
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isDownHovered = true),
            onExit: (_) => setState(() => _isDownHovered = false),
            child: GestureDetector(
              onTap: widget.onToggleMenu,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _isDownHovered
                      ? const Color(0x18000000)
                      : const Color(0x00000000),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    bottomLeft: Radius.circular(5),
                  ),
                ),
                child: _ChevronArrow(
                  direction: widget.isMenuOpen
                      ? _ChevronDirection.up
                      : _ChevronDirection.down,
                  color: _isDownHovered
                      ? const Color(0xFF14181D)
                      : const Color(0xFF2C343B),
                  size: 11,
                  strokeWidth: 2.0,
                ),
              ),
            ),
          ),

          // Preset Name Display
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isPillHovered = true),
              onExit: (_) => setState(() => _isPillHovered = false),
              child: GestureDetector(
                onTap: widget.onToggleMenu,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: Text(
                    widget.presetName,
                    style: TextStyle(
                      color: _isPillHovered
                          ? const Color(0xFF1A2228)
                          : const Color(0xFF2C343B),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      fontFamily: 'Inter',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),

          // Previous Preset (Vector Left Chevron)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isPrevHovered = true),
            onExit: (_) => setState(() => _isPrevHovered = false),
            child: GestureDetector(
              onTap: widget.onPrev,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _isPrevHovered
                      ? const Color(0x18000000)
                      : const Color(0x00000000),
                ),
                child: _ChevronArrow(
                  direction: _ChevronDirection.left,
                  color: _isPrevHovered
                      ? const Color(0xFF14181D)
                      : const Color(0xFF3B454F),
                  size: 10,
                  strokeWidth: 2.0,
                ),
              ),
            ),
          ),

          // Next Preset (Vector Right Chevron)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isNextHovered = true),
            onExit: (_) => setState(() => _isNextHovered = false),
            child: GestureDetector(
              onTap: widget.onNext,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
                decoration: BoxDecoration(
                  color: _isNextHovered
                      ? const Color(0x18000000)
                      : const Color(0x00000000),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(5),
                    bottomRight: Radius.circular(5),
                  ),
                ),
                child: _ChevronArrow(
                  direction: _ChevronDirection.right,
                  color: _isNextHovered
                      ? const Color(0xFF14181D)
                      : const Color(0xFF3B454F),
                  size: 10,
                  strokeWidth: 2.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main Control Canvas (Dual Faders + Massive Tactile Center Knob)
// ---------------------------------------------------------------------------
class _MainControlCanvas extends StatelessWidget {
  const _MainControlCanvas({
    required this.dynamics,
    required this.reverb,
    required this.toneWheel,
    this.onDynamicsChanged,
    this.onReverbChanged,
    this.onToneWheelChanged,
  });

  final double dynamics;
  final double reverb;
  final double toneWheel;
  final ValueChanged<double>? onDynamicsChanged;
  final ValueChanged<double>? onReverbChanged;
  final ValueChanged<double>? onToneWheelChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 4, 48, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Dual Vertical Faders
          SizedBox(
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Fader 1: Dynamics / Expression
                _VerticalFader(
                  value: dynamics,
                  accentColor: const Color(0xFF26C6DA), // Cyan
                  glyphKind: _GlyphKind.trinity,
                  label: 'DYNAMICS',
                  onChanged: onDynamicsChanged,
                ),
                const SizedBox(width: 32),

                // Fader 2: Reverb / Space
                _VerticalFader(
                  value: reverb,
                  accentColor: const Color(0xFFFF5252), // Coral
                  glyphKind: _GlyphKind.aperture,
                  label: 'REVERB',
                  onChanged: onReverbChanged,
                ),
              ],
            ),
          ),

          // Center-Right Hero Wheel
          Expanded(
            child: Center(
              child: _BigWheelKnob(
                value: toneWheel,
                onChanged: onToneWheelChanged,
              ),
            ),
          ),

          // Version Tag at bottom-right
          const Align(
            alignment: Alignment.bottomRight,
            child: Text(
              'v 1.0.0',
              style: TextStyle(
                color: Color(0xFF9E9FA4),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vertical Fader with Dotted Scale and Tactile Thumb Cap
// ---------------------------------------------------------------------------
enum _GlyphKind { trinity, aperture, target }

class _VerticalFader extends StatefulWidget {
  const _VerticalFader({
    required this.value,
    required this.accentColor,
    required this.glyphKind,
    required this.label,
    this.onChanged,
  });

  final double value;
  final Color accentColor;
  final _GlyphKind glyphKind;
  final String label;
  final ValueChanged<double>? onChanged;

  @override
  State<_VerticalFader> createState() => _VerticalFaderState();
}

class _VerticalFaderState extends State<_VerticalFader> {
  void _handleDrag(DragUpdateDetails details, double trackHeight) {
    if (trackHeight <= 0) return;
    final double delta = -details.primaryDelta! / trackHeight;
    final double next = (widget.value + delta).clamp(0.0, 1.0);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    const double faderHeight = 150.0;
    const double faderWidth = 32.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Fader Track + Thumb
        MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            onVerticalDragUpdate: (DragUpdateDetails d) =>
                _handleDrag(d, faderHeight),
            child: SizedBox(
              width: faderWidth,
              height: faderHeight,
              child: CustomPaint(
                painter: _FaderTrackPainter(
                  value: widget.value,
                  accentColor: widget.accentColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Geometric Emblem Glyph
        _GeometricGlyph(kind: widget.glyphKind, color: widget.accentColor),
      ],
    );
  }
}

class _FaderTrackPainter extends CustomPainter {
  _FaderTrackPainter({required this.value, required this.accentColor});

  final double value;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double midX = size.width / 2;
    const double topY = 12.0;
    final double bottomY = size.height - 12.0;
    final double trackSpan = bottomY - topY;

    // Track Background Slot
    final Paint trackPaint = Paint()
      ..color = const Color(0xFFD6D3CB)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(midX - 5, topY),
      Offset(midX - 5, bottomY),
      trackPaint,
    );

    // Dotted Scale next to track
    final Paint dotPaint = Paint()..style = PaintingStyle.fill;
    const int dotCount = 18;
    for (int i = 0; i <= dotCount; i++) {
      final double y = topY + (trackSpan * i / dotCount);
      if (i == 0) {
        dotPaint.color = accentColor;
        canvas.drawCircle(Offset(midX + 5, y), 2.2, dotPaint);
      } else {
        dotPaint.color = const Color(0xFF4A4E55);
        canvas.drawCircle(Offset(midX + 5, y), 1.2, dotPaint);
      }
    }

    // Thumb Position
    final double thumbY = bottomY - (value * trackSpan);

    // Thumb Shadow
    final RRect thumbRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(midX - 5, thumbY), width: 14, height: 26),
      const Radius.circular(5),
    );

    final Paint shadowPaint = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(thumbRRect.shift(const Offset(0, 2)), shadowPaint);

    // Thumb Body (Aluminium / Soft White Bevel)
    final Paint thumbBodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFFFFFFFF),
          Color(0xFFEDECE8),
          Color(0xFFDFDCD5),
        ],
      ).createShader(thumbRRect.outerRect);
    canvas.drawRRect(thumbRRect, thumbBodyPaint);

    // Thumb Border
    final Paint borderPaint = Paint()
      ..color = const Color(0xFFBEBAB0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(thumbRRect, borderPaint);

    // Thumb Center Notch
    final Paint notchPaint = Paint()
      ..color = const Color(0xFF9E9A90)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(midX - 10, thumbY),
      Offset(midX, thumbY),
      notchPaint,
    );
  }

  @override
  bool shouldRepaint(_FaderTrackPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.accentColor != accentColor;
}

class _GeometricGlyph extends StatelessWidget {
  const _GeometricGlyph({required this.kind, required this.color});

  final _GlyphKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _GlyphPainter(kind: kind, color: color),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.kind, required this.color});

  final _GlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    switch (kind) {
      case _GlyphKind.trinity:
        // Three interlocking circles
        const double r = 5.0;
        canvas.drawCircle(Offset(c.dx, c.dy - 3), r, p);
        canvas.drawCircle(Offset(c.dx - 3.5, c.dy + 3), r, p);
        canvas.drawCircle(Offset(c.dx + 3.5, c.dy + 3), r, p);
        break;

      case _GlyphKind.aperture:
        // Aperture spiral petals
        canvas.drawCircle(c, 7.5, p);
        for (int i = 0; i < 6; i++) {
          final double angle = i * (math.pi / 3);
          canvas.drawLine(
            Offset(c.dx + 7.5 * math.cos(angle), c.dy + 7.5 * math.sin(angle)),
            Offset(
              c.dx + 3.0 * math.cos(angle + 0.8),
              c.dy + 3.0 * math.sin(angle + 0.8),
            ),
            p,
          );
        }
        break;

      case _GlyphKind.target:
        // Target / bullseye
        canvas.drawCircle(c, 7.5, p);
        canvas.drawCircle(c, 3.5, p);
        break;
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Massive Tactile Dish Knob (Big Center Hero Wheel)
// ---------------------------------------------------------------------------
class _BigWheelKnob extends StatefulWidget {
  const _BigWheelKnob({required this.value, this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  State<_BigWheelKnob> createState() => _BigWheelKnobState();
}

class _BigWheelKnobState extends State<_BigWheelKnob> {
  Offset? _dragStart;
  double _startValue = 0.0;

  void _onPanStart(DragStartDetails details) {
    _dragStart = details.localPosition;
    _startValue = widget.value;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null) return;
    final double dy = _dragStart!.dy - details.localPosition.dy;
    final double next = (_startValue + dy * 0.006).clamp(0.0, 1.0);
    widget.onChanged?.call(next);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragStart = null;
  }

  @override
  Widget build(BuildContext context) {
    const double wheelSize = 176.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: SizedBox(
              width: wheelSize,
              height: wheelSize,
              child: CustomPaint(
                painter: _BigWheelPainter(value: widget.value),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Indicator glyph under wheel
        const _GeometricGlyph(
          kind: _GlyphKind.target,
          color: Color(0xFF42A5F5),
        ),
      ],
    );
  }
}

class _BigWheelPainter extends CustomPainter {
  _BigWheelPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    // 1. Outer Dotted Radial Scale
    const double arcStart = math.pi * 0.70;
    const double arcEnd = math.pi * 2.30;
    const double arcTotal = arcEnd - arcStart;
    const int numDots = 38;

    final Paint scaleDotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i <= numDots; i++) {
      final double frac = i / numDots;
      final double angle = arcStart + frac * arcTotal;
      final double r = radius - 14.0;
      final Offset dotPos = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );

      if (frac <= value) {
        scaleDotPaint.color = const Color(0xFF26C6DA);
        canvas.drawCircle(dotPos, 2.0, scaleDotPaint);
      } else {
        scaleDotPaint.color = const Color(0xFF3B4048);
        canvas.drawCircle(dotPos, 1.4, scaleDotPaint);
      }
    }

    // 2. Outer Progress Arc Track
    final Paint arcTrackPaint = Paint()
      ..color = const Color(0xFFD6D2C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final Rect arcRect = Rect.fromCircle(center: center, radius: radius - 6.0);
    canvas.drawArc(arcRect, arcStart, arcTotal, false, arcTrackPaint);

    // Active progress on arc
    final Paint arcActivePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, arcStart, arcTotal * value, false, arcActivePaint);

    // 3. Indicator Pip on the Outer Ring
    final double pipAngle = arcStart + arcTotal * value;
    final double pipR = radius - 6.0;
    final Offset pipPos = Offset(
      center.dx + pipR * math.cos(pipAngle),
      center.dy + pipR * math.sin(pipAngle),
    );
    final Paint pipPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final Paint pipBorder = Paint()
      ..color = const Color(0xFFC7C3B9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pipPos, 6.0, pipPaint);
    canvas.drawCircle(pipPos, 6.0, pipBorder);

    // 4. Large Sunken Dish Dial
    final double dishRadius = radius - 30.0;

    // Drop shadow
    final Paint dishShadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center + const Offset(0, 4), dishRadius, dishShadow);

    // Dish Outer Bevel Gradient
    final Paint dishBevel = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.2, -0.3),
        colors: <Color>[
          Color(0xFFFFFFFF),
          Color(0xFFEDECE8),
          Color(0xFFDAD6CE),
        ],
        stops: <double>[0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dishRadius));
    canvas.drawCircle(center, dishRadius, dishBevel);

    // Sunken Inner Cavity
    final double innerRadius = dishRadius - 16.0;
    final Paint cavityPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, 0.0),
        colors: <Color>[
          Color(0xFFFFFFFF),
          Color(0xFFF6F5F2),
          Color(0xFFE4E0D7),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawCircle(center, innerRadius, cavityPaint);

    // 5. Center Emblem Badge (Gold Thin Ring + Guitar Pluck Motif)
    const double emblemRadius = 24.0;
    final Paint goldRing = Paint()
      ..color =
          const Color(0xFFFFCA28) // Gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, emblemRadius, goldRing);

    // Stylized Wave / Strings Motif in Center
    final Paint wavePaint = Paint()
      ..color = const Color(0xFF374151)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final Path wavePath1 = Path();
    wavePath1.moveTo(center.dx - 12, center.dy - 3);
    wavePath1.cubicTo(
      center.dx - 4,
      center.dy - 10,
      center.dx + 4,
      center.dy + 8,
      center.dx + 12,
      center.dy + 2,
    );
    canvas.drawPath(wavePath1, wavePaint);

    final Path wavePath2 = Path();
    wavePath2.moveTo(center.dx - 12, center.dy + 4);
    wavePath2.cubicTo(
      center.dx - 4,
      center.dy - 3,
      center.dx + 4,
      center.dy + 12,
      center.dx + 12,
      center.dy + 5,
    );
    canvas.drawPath(wavePath2, wavePaint);
  }

  @override
  bool shouldRepaint(_BigWheelPainter oldDelegate) =>
      oldDelegate.value != value;
}

// ---------------------------------------------------------------------------
// Bottom Keyboard Bar (Interactive Virtual Piano Keys + Wheels)
// ---------------------------------------------------------------------------
class _BottomKeyboardBar extends StatelessWidget {
  const _BottomKeyboardBar({
    required this.octaveShift,
    required this.pitchBend,
    required this.modWheel,
    required this.onOctaveDown,
    required this.onOctaveUp,
    required this.onPitchBendChanged,
    required this.onModWheelChanged,
    this.onAuditionNoteOn,
    this.onAuditionNoteOff,
  });

  final int octaveShift;
  final double pitchBend;
  final double modWheel;
  final VoidCallback onOctaveDown;
  final VoidCallback onOctaveUp;
  final ValueChanged<double> onPitchBendChanged;
  final ValueChanged<double> onModWheelChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final void Function(int key)? onAuditionNoteOff;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF1E2024),
        border: Border(top: BorderSide(color: Color(0xFF141517), width: 1.5)),
      ),
      child: Row(
        children: <Widget>[
          // Left Wheel Controls & Octave Stepper
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                // Octave Stepper (< 0 >)
                _OctaveStepper(
                  octave: octaveShift,
                  onDown: onOctaveDown,
                  onUp: onOctaveUp,
                ),
                const SizedBox(width: 8),

                // Pitch Wheel
                _ModPitchWheel(
                  label: 'PITCH',
                  value: pitchBend,
                  hasCenterNotch: true,
                  onChanged: onPitchBendChanged,
                ),
                const SizedBox(width: 6),

                // Mod Wheel
                _ModPitchWheel(
                  label: 'MOD',
                  value: modWheel,
                  hasCenterNotch: false,
                  onChanged: onModWheelChanged,
                ),
              ],
            ),
          ),

          // Interactive Keyboard Strip
          Expanded(
            child: _GuitarKeyboardStrip(
              octaveShift: octaveShift,
              onNoteOn: onAuditionNoteOn,
              onNoteOff: onAuditionNoteOff,
            ),
          ),
        ],
      ),
    );
  }
}

class _OctaveStepper extends StatelessWidget {
  const _OctaveStepper({
    required this.octave,
    required this.onDown,
    required this.onUp,
  });

  final int octave;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        GestureDetector(
          onTap: onUp,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: _ChevronArrow(
              direction: _ChevronDirection.up,
              color: Color(0xFF9EACB7),
              size: 8,
              strokeWidth: 1.8,
            ),
          ),
        ),
        Text(
          '$octave',
          style: const TextStyle(
            color: Color(0xFFD6D8DC),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        GestureDetector(
          onTap: onDown,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: _ChevronArrow(
              direction: _ChevronDirection.down,
              color: Color(0xFF9EACB7),
              size: 8,
              strokeWidth: 1.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModPitchWheel extends StatelessWidget {
  const _ModPitchWheel({
    required this.label,
    required this.value,
    required this.hasCenterNotch,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool hasCenterNotch;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (DragUpdateDetails details) {
        final double next = (value - details.primaryDelta! * 0.02).clamp(
          0.0,
          1.0,
        );
        onChanged(next);
      },
      onVerticalDragEnd: (DragEndDetails details) {
        if (hasCenterNotch) {
          onChanged(0.5); // Snap pitch wheel back to center
        }
      },
      child: Container(
        width: 14,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF141517),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF333842), width: 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Thumb Indicator
            Positioned(
              top: (1.0 - value) * 40.0 + 2.0,
              child: Container(
                width: 10,
                height: 12,
                decoration: BoxDecoration(
                  color: hasCenterNotch && (value - 0.5).abs() > 0.05
                      ? const Color(0xFFFF5252)
                      : const Color(0xFF8E929B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive Keyboard Strip with Highlighted Guitar Range
// ---------------------------------------------------------------------------
class _GuitarKeyboardStrip extends StatefulWidget {
  const _GuitarKeyboardStrip({
    required this.octaveShift,
    this.onNoteOn,
    this.onNoteOff,
  });

  final int octaveShift;
  final void Function(int key, double velocity)? onNoteOn;
  final void Function(int key)? onNoteOff;

  @override
  State<_GuitarKeyboardStrip> createState() => _GuitarKeyboardStripState();
}

class _GuitarKeyboardStripState extends State<_GuitarKeyboardStrip> {
  int? _activeKey;

  // 6-String Guitar Standard Range: E2 (MIDI 40) to E6 (MIDI 88)
  static const int kMinActiveGuitarKey = 40;
  static const int kMaxActiveGuitarKey = 88;

  void _handlePointerDown(int midiKey) {
    setState(() => _activeKey = midiKey);
    widget.onNoteOn?.call(midiKey, 0.85);
  }

  void _handlePointerUp(int midiKey) {
    if (_activeKey == midiKey) {
      setState(() => _activeKey = null);
    }
    widget.onNoteOff?.call(midiKey);
  }

  @override
  Widget build(BuildContext context) {
    // 60-key full keyboard display from C1 (24) to C7 (96)
    const int startMidi = 24;
    const int endMidi = 96;

    final List<int> whiteKeys = <int>[];
    for (int k = startMidi; k <= endMidi; k++) {
      final int noteInOctave = k % 12;
      final bool isBlack =
          noteInOctave == 1 ||
          noteInOctave == 3 ||
          noteInOctave == 6 ||
          noteInOctave == 8 ||
          noteInOctave == 10;
      if (!isBlack) {
        whiteKeys.add(k);
      }
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double keyWidth = constraints.maxWidth / whiteKeys.length;

        return Stack(
          children: <Widget>[
            // White Keys
            Row(
              children: <Widget>[
                for (final int midi in whiteKeys)
                  _WhiteKeyWidget(
                    midiKey: midi,
                    width: keyWidth,
                    isActiveRange:
                        midi >= kMinActiveGuitarKey &&
                        midi <= kMaxActiveGuitarKey,
                    isPressed: _activeKey == midi,
                    onDown: () => _handlePointerDown(midi),
                    onUp: () => _handlePointerUp(midi),
                  ),
              ],
            ),

            // Black Keys Overlay
            for (int k = startMidi; k <= endMidi; k++)
              if (k % 12 == 1 ||
                  k % 12 == 3 ||
                  k % 12 == 6 ||
                  k % 12 == 8 ||
                  k % 12 == 10)
                _BlackKeyPositionedWidget(
                  midiKey: k,
                  whiteKeys: whiteKeys,
                  keyWidth: keyWidth,
                  minActive: kMinActiveGuitarKey,
                  maxActive: kMaxActiveGuitarKey,
                  isPressed: _activeKey == k,
                  onDown: () => _handlePointerDown(k),
                  onUp: () => _handlePointerUp(k),
                ),
          ],
        );
      },
    );
  }
}

class _BlackKeyPositionedWidget extends StatelessWidget {
  const _BlackKeyPositionedWidget({
    required this.midiKey,
    required this.whiteKeys,
    required this.keyWidth,
    required this.minActive,
    required this.maxActive,
    required this.isPressed,
    required this.onDown,
    required this.onUp,
  });

  final int midiKey;
  final List<int> whiteKeys;
  final double keyWidth;
  final int minActive;
  final int maxActive;
  final bool isPressed;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final int prevWhiteIdx = whiteKeys.indexOf(midiKey - 1);
    if (prevWhiteIdx < 0) return const SizedBox.shrink();

    final double left = (prevWhiteIdx + 1) * keyWidth - (keyWidth * 0.35);
    final bool inRange = midiKey >= minActive && midiKey <= maxActive;

    return Positioned(
      left: left,
      top: 0,
      width: keyWidth * 0.70,
      height: 44,
      child: _BlackKeyWidget(
        midiKey: midiKey,
        isActiveRange: inRange,
        isPressed: isPressed,
        onDown: onDown,
        onUp: onUp,
      ),
    );
  }
}

class _WhiteKeyWidget extends StatefulWidget {
  const _WhiteKeyWidget({
    required this.midiKey,
    required this.width,
    required this.isActiveRange,
    required this.isPressed,
    required this.onDown,
    required this.onUp,
  });

  final int midiKey;
  final double width;
  final bool isActiveRange;
  final bool isPressed;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_WhiteKeyWidget> createState() => _WhiteKeyWidgetState();
}

class _WhiteKeyWidgetState extends State<_WhiteKeyWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isPressed
        ? const Color(0xFF26C6DA)
        : (_isHovered && widget.isActiveRange)
        ? const Color(0xFFF7F8F9)
        : widget.isActiveRange
        ? const Color(0xFFEBEAE6)
        : const Color(0xFF5A5F6B); // Subdued outer range

    return MouseRegion(
      cursor: widget.isActiveRange
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => widget.onDown(),
        onTapUp: (_) => widget.onUp(),
        onTapCancel: widget.onUp,
        child: Container(
          width: widget.width,
          height: 72,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: const Color(0xFF141517), width: 0.5),
          ),
        ),
      ),
    );
  }
}

class _BlackKeyWidget extends StatefulWidget {
  const _BlackKeyWidget({
    required this.midiKey,
    required this.isActiveRange,
    required this.isPressed,
    required this.onDown,
    required this.onUp,
  });

  final int midiKey;
  final bool isActiveRange;
  final bool isPressed;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_BlackKeyWidget> createState() => _BlackKeyWidgetState();
}

class _BlackKeyWidgetState extends State<_BlackKeyWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isPressed
        ? const Color(0xFF00ACC1)
        : (_isHovered && widget.isActiveRange)
        ? const Color(0xFF2E323A)
        : widget.isActiveRange
        ? const Color(0xFF202227)
        : const Color(0xFF383C45);

    return MouseRegion(
      cursor: widget.isActiveRange
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => widget.onDown(),
        onTapUp: (_) => widget.onUp(),
        onTapCancel: widget.onUp,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
            border: Border.all(color: const Color(0xFF0E0F11), width: 0.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preset Dropdown Panel (Anchored Directly Underneath Preset Bar)
// ---------------------------------------------------------------------------
class _PresetDropdownPanel extends StatelessWidget {
  const _PresetDropdownPanel({
    required this.selectedIndex,
    required this.presets,
    required this.onSelect,
    required this.onClose,
  });

  final int selectedIndex;
  final List<GuitarPresetData> presets;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final List<int> acousticIndices = <int>[];
    final List<int> electricIndices = <int>[];
    for (int i = 0; i < presets.length; i++) {
      if (presets[i].category == 'Acoustic') {
        acousticIndices.add(i);
      } else {
        electricIndices.add(i);
      }
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: const Color(0x00000000), // Transparent dismiss barrier
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.fromLTRB(16, 50, 16, 0),
          child: GestureDetector(
            onTap: () {}, // Prevent dismissal on clicking inside dropdown
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 340),
              decoration: BoxDecoration(
                color: const Color(0xFF16181D),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: const Color(0xFF2C323D), width: 1),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  children: <Widget>[
                    const _DropdownCategoryHeader(title: 'ACOUSTIC GUITARS'),
                    const SizedBox(height: 4),
                    for (final int idx in acousticIndices) ...<Widget>[
                      _PresetListItem(
                        preset: presets[idx],
                        isSelected: idx == selectedIndex,
                        onTap: () => onSelect(idx),
                      ),
                      const SizedBox(height: 2),
                    ],

                    const SizedBox(height: 8),
                    const _DropdownCategoryHeader(
                      title: 'ELECTRIC & AMBIENT GUITARS',
                    ),
                    const SizedBox(height: 4),
                    for (final int idx in electricIndices) ...<Widget>[
                      _PresetListItem(
                        preset: presets[idx],
                        isSelected: idx == selectedIndex,
                        onTap: () => onSelect(idx),
                      ),
                      const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownCategoryHeader extends StatelessWidget {
  const _DropdownCategoryHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF727A8A),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: const Color(0xFF22262E))),
        ],
      ),
    );
  }
}

class _PresetListItem extends StatefulWidget {
  const _PresetListItem({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final GuitarPresetData preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_PresetListItem> createState() => _PresetListItemState();
}

class _PresetListItemState extends State<_PresetListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isSelected
        ? const Color(0xFF1E2833)
        : (_isHovered ? const Color(0xFF22262E) : const Color(0x00000000));

    final Color textColor = widget.isSelected
        ? const Color(0xFF26C6DA)
        : (_isHovered ? const Color(0xFFFFFFFF) : const Color(0xFFE2E4E8));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: widget.isSelected
                ? Border.all(color: const Color(0x6626C6DA), width: 1)
                : null,
          ),
          child: Row(
            children: <Widget>[
              // Category Dot
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.preset.category == 'Acoustic'
                      ? const Color(0xFF81C784)
                      : const Color(0xFFCE93D8),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),

              // Name & Description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.preset.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12.5,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.preset.description,
                      style: TextStyle(
                        color: _isHovered
                            ? const Color(0xFFA6ABB6)
                            : const Color(0xFF7A808C),
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              if (widget.isSelected)
                const Text(
                  '✓',
                  style: TextStyle(
                    color: Color(0xFF26C6DA),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
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
// Precision Vector Chevron Arrow Widget
// ---------------------------------------------------------------------------
enum _ChevronDirection { down, up, left, right }

class _ChevronArrow extends StatelessWidget {
  const _ChevronArrow({
    required this.direction,
    required this.color,
    this.size = 12.0,
    this.strokeWidth = 1.8,
  });

  final _ChevronDirection direction;
  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ChevronPainter(
          direction: direction,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({
    required this.direction,
    required this.color,
    required this.strokeWidth,
  });

  final _ChevronDirection direction;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    final double w = size.width;
    final double h = size.height;

    switch (direction) {
      case _ChevronDirection.down:
        path.moveTo(w * 0.15, h * 0.35);
        path.lineTo(w * 0.50, h * 0.70);
        path.lineTo(w * 0.85, h * 0.35);
        break;
      case _ChevronDirection.up:
        path.moveTo(w * 0.15, h * 0.65);
        path.lineTo(w * 0.50, h * 0.30);
        path.lineTo(w * 0.85, h * 0.65);
        break;
      case _ChevronDirection.left:
        path.moveTo(w * 0.65, h * 0.15);
        path.lineTo(w * 0.30, h * 0.50);
        path.lineTo(w * 0.65, h * 0.85);
        break;
      case _ChevronDirection.right:
        path.moveTo(w * 0.35, h * 0.15);
        path.lineTo(w * 0.70, h * 0.50);
        path.lineTo(w * 0.35, h * 0.85);
        break;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.direction != direction ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
