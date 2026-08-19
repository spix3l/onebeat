import 'package:flutter/widgets.dart';

import '../../core/shortcuts.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/floating_window.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'stock/generic_editor.dart';
import 'stock/guitar_editor.dart';
import 'stock/lowkey_editor.dart';
import 'stock/organ_editor.dart';
import 'stock/piano_editor.dart';
import 'stock/sampler_editor.dart';
import 'stock/synth_editor.dart';
import 'typing_keyboard.dart';

/// C of the typing keyboard's lower row when a plug-in window opens: MIDI 48,
/// the middle of every stock editor's drawn range.
const int _kTypingBaseOctave = 4;

const List<String> _kNoteNames = <String>['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

String _noteName(int midi) => '${_kNoteNames[midi % 12]}${midi ~/ 12 - 1}';

class PluginBinding extends StatefulWidget {
  const PluginBinding({
    required this.client,
    required this.trackId,
    required this.onClose,
    this.pluginName = 'Synth',
    this.trackName = 'Soft Keys',
    this.sampleName,
    this.isBypassed = false,
    this.parameters = const <HostedParameter>[],
    this.onDragUpdate,
    super.key,
  });

  final EngineClient client;
  final String trackId;
  final String pluginName;
  final String trackName;
  final String? sampleName;
  final bool isBypassed;
  final List<HostedParameter> parameters;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback onClose;

  @override
  State<PluginBinding> createState() => _PluginBindingState();
}

class _PluginBindingState extends State<PluginBinding> {
  late bool _bypassed;
  late List<HostedParameter> _parameters;
  bool _samplerReverse = false;

  /// Where the typing keyboard's lower letter row currently sits. Shown in the
  /// window subtitle, because an octave shift with no readout leaves the user
  /// guessing why the same keys now sound different.
  int _typingBaseKey = _kTypingBaseOctave * 12;
  final Map<String, double> _stockFallbackValues = <String, double>{};

  @override
  void initState() {
    super.initState();
    _bypassed = widget.isBypassed;
    _parameters = widget.parameters;
  }

  /// Audition plays through the engine's *selected* channel, so taking the
  /// keyboard also points the engine at this window's instrument. Doing it on
  /// focus rather than on every key-down keeps it to one command per visit.
  void _selectOwnInstrument() {
    if (widget.trackId.isEmpty) return;
    try {
      widget.client.selectInstrument(widget.trackId);
    } catch (_) {
      // The command is a stub on a fake client.
    }
  }

  @override
  void dispose() {
    // Closing the window hands the keyboard back to whichever editor had it,
    // rather than leaving it on a node that no longer exists — otherwise the
    // rack's shortcuts stay asleep until the user clicks something.
    FocusPolicy.returnToEditor();
    super.dispose();
  }

  void _onToggleBypass() {
    setState(() => _bypassed = !_bypassed);
    widget.client.setInstrumentMuted(widget.trackId, muted: _bypassed);
  }

  void _onParamChanged(int paramId, double value) {
    widget.client.setParameter(paramId, value);
    setState(() {
      _parameters = <HostedParameter>[
        for (final HostedParameter parameter in _parameters)
          parameter.id == paramId
              ? HostedParameter(
                id: parameter.id,
                name: parameter.name,
                module: parameter.module,
                display: parameter.display,
                value: value,
                minimum: parameter.minimum,
                maximum: parameter.maximum,
                defaultValue: parameter.defaultValue,
              )
              : parameter,
      ];
    });
  }

  HostedParameter? _stockParameter(String label) {
    final String key = label.toLowerCase();
    for (final HostedParameter parameter in _parameters) {
      final String name = parameter.name.toLowerCase();
      if (name == key || name.contains(key)) return parameter;
      if (key == 'pitch' && (name.contains('pitch') || name.contains('transpose') || name.contains('tune'))) {
        return parameter;
      }
    }
    return null;
  }

  double _stockValue(String label, double fallback) {
    final double? local = _stockFallbackValues[label];
    if (local != null) return local;
    final HostedParameter? parameter = _stockParameter(label);
    if (parameter == null) return fallback;
    final double span = parameter.maximum - parameter.minimum;
    return span > 0 ? ((parameter.value - parameter.minimum) / span).clamp(0.0, 1.0) : fallback;
  }

  void _onStockChanged(String label, double value) {
    final HostedParameter? parameter = _stockParameter(label);
    if (parameter == null) {
      setState(() => _stockFallbackValues[label] = value);
      return;
    }
    final double next = parameter.minimum + value.clamp(0.0, 1.0) * (parameter.maximum - parameter.minimum);
    _onParamChanged(parameter.id, next);
  }

  void _onPianoPresetSelected(int index) {
    if (index < 0 || index >= kPianoPresets.length) return;
    final PianoPresetData preset = kPianoPresets[index];
    _onStockChanged('preset', index / kPianoPresets.length);
    _onStockChanged('tone', preset.tone);
    _onStockChanged('body', preset.body);
    _onStockChanged('attack', preset.attack);
    _onStockChanged('decay', preset.decay);
    _onStockChanged('sustain', preset.sustain);
    _onStockChanged('release', preset.release);
    _onStockChanged('hammer', preset.hammer);
    _onStockChanged('damper', preset.damper);
    _onStockChanged('detune', preset.detune);
    _onStockChanged('velocity', preset.velocitySens);
    _onStockChanged('room', preset.room);
    _onStockChanged('size', preset.reverbSize);
    _onStockChanged('depth', preset.modDepth);
    _onStockChanged('rate', preset.modRate);
    _onStockChanged('drive', preset.drive);
    _onStockChanged('width', preset.width);
    _onStockChanged('output', preset.output);
  }

  void _onGuitarPresetSelected(int index) {
    if (index < 0 || index >= kGuitarPresets.length) return;
    final GuitarPresetData preset = kGuitarPresets[index];
    _onStockChanged('preset', index / kGuitarPresets.length);
    _onStockChanged('tone', preset.tone);
    _onStockChanged('body', preset.body);
    _onStockChanged('decay', preset.decay);
    _onStockChanged('release', preset.release);
    _onStockChanged('room', preset.room);
    _onStockChanged('width', preset.width);
    _onStockChanged('output', preset.output);
    _onStockChanged('pick position', preset.pickPos);
    _onStockChanged('damping', preset.damping);
    _onStockChanged('pickup', preset.pickup);
    _onStockChanged('drive', preset.drive);
    _onStockChanged('chorus', preset.chorus);
    _onStockChanged('reverb size', preset.reverbSize);
    _onStockChanged('dynamics', preset.dynamics);
    _onStockChanged('pitch', preset.pitch);
    _onStockChanged('mod rate', preset.modRate);
    _onStockChanged('attack', preset.attack);
  }

  void _onLowkeyPresetSelected(int index) {
    if (index < 0 || index >= kLowkeyPresets.length) return;
    final LowkeyPresetData preset = kLowkeyPresets[index];
    _onStockChanged('preset', index / kLowkeyPresets.length);
    _onStockChanged('tone', preset.tone);
    _onStockChanged('body', preset.body);
    _onStockChanged('decay', preset.decay);
    _onStockChanged('release', preset.release);
    _onStockChanged('room', preset.room);
    _onStockChanged('width', preset.width);
    _onStockChanged('output', preset.output);
    _onStockChanged('pick position', preset.pickPos);
    _onStockChanged('damping', preset.damping);
    _onStockChanged('pickup', preset.pickup);
    _onStockChanged('drive', preset.drive);
    _onStockChanged('chorus', preset.chorus);
    _onStockChanged('reverb size', preset.reverbSize);
    _onStockChanged('dynamics', preset.dynamics);
    _onStockChanged('pitch', preset.pitch);
    _onStockChanged('mod rate', preset.modRate);
    _onStockChanged('attack', preset.attack);
  }

  void _onSynthPresetSelected(int index) {
    if (index < 0 || index >= kSynthPresets.length) return;
    final SynthPresetData preset = kSynthPresets[index];
    _onStockChanged('preset', index / kSynthPresets.length);
    _onStockChanged('osc shape', preset.oscShape);
    _onStockChanged('osc mix', preset.oscMix);
    _onStockChanged('detune', preset.detune);
    _onStockChanged('sub', preset.sub);
    _onStockChanged('cutoff', preset.cutoff);
    _onStockChanged('resonance', preset.resonance);
    _onStockChanged('filter env', preset.filterEnv);
    _onStockChanged('attack', preset.attack);
    _onStockChanged('decay', preset.decay);
    _onStockChanged('sustain', preset.sustain);
    _onStockChanged('release', preset.release);
    _onStockChanged('drive', preset.drive);
    _onStockChanged('delay', preset.delay);
    _onStockChanged('width', preset.width);
    _onStockChanged('output', preset.output);
    _onStockChanged('lfo rate', preset.lfoRate);
    _onStockChanged('lfo depth', preset.lfoDepth);
    _onStockChanged('glide', preset.glide);
    _onStockChanged('noise', preset.noise);
  }

  @override
  Widget build(BuildContext context) {
    final String lower = widget.pluginName.toLowerCase();
    final bool isPiano = lower.contains('piano');
    final bool isGuitar = lower.contains('guitar');
    final bool isLowkey = lower.contains('lowkey');
    final bool isSynth = lower.contains('synth');
    final bool isOrgan = lower.contains('organ');

    Widget editorContent;
    if (isOrgan) {
      editorContent = OrganStockEditor(
        preset: _stockValue('preset', 0.0),
        percussion: _stockValue('res', 0.35),
        click: _stockValue('cutoff', 0.20),
        drive: _stockValue('detune', 0.15),
        reverb: _stockValue('lfo', 0.25),
        rotary: _stockValue('lfo rate', 0.50),
        attack: _stockValue('attack', 0.10),
        release: _stockValue('release', 0.35),
        onPresetChanged: (double v) => _onStockChanged('preset', v),
        onPercussionChanged: (double v) => _onStockChanged('res', v),
        onClickChanged: (double v) => _onStockChanged('cutoff', v),
        onDriveChanged: (double v) => _onStockChanged('detune', v),
        onReverbChanged: (double v) => _onStockChanged('lfo', v),
        onRotaryChanged: (double v) => _onStockChanged('lfo rate', v),
        onAttackChanged: (double v) => _onStockChanged('attack', v),
        onReleaseChanged: (double v) => _onStockChanged('release', v),
        onAuditionNoteOn: widget.client.auditionNoteOn,
        onAuditionNoteOff: widget.client.auditionNoteOff,
      );
    } else if (isLowkey) {
      editorContent = LowkeyStockEditor(
        preset: _stockValue('preset', 0.0),
        tone: _stockValue('tone', 0.35),
        body: _stockValue('body', 0.80),
        decay: _stockValue('decay', 0.60),
        release: _stockValue('release', 0.40),
        room: _stockValue('room', 0.10),
        width: _stockValue('width', 0.50),
        output: _stockValue('output', 0.80),
        pickPos: _stockValue('pick position', 0.50),
        damping: _stockValue('damping', 0.60),
        pickup: _stockValue('pickup', 0.10),
        drive: _stockValue('drive', 0.05),
        chorus: _stockValue('chorus', 0.00),
        reverbSize: _stockValue('reverb size', 0.20),
        dynamics: _stockValue('dynamics', 0.80),
        pitch: _stockValue('pitch', 0.50),
        modRate: _stockValue('mod rate', 0.20),
        attack: _stockValue('attack', 0.30),
        onPresetChanged: _onLowkeyPresetSelected,
        onToneChanged: (double v) => _onStockChanged('tone', v),
        onBodyChanged: (double v) => _onStockChanged('body', v),
        onDecayChanged: (double v) => _onStockChanged('decay', v),
        onReleaseChanged: (double v) => _onStockChanged('release', v),
        onRoomChanged: (double v) => _onStockChanged('room', v),
        onWidthChanged: (double v) => _onStockChanged('width', v),
        onOutputChanged: (double v) => _onStockChanged('output', v),
        onPickPosChanged: (double v) => _onStockChanged('pick position', v),
        onDampingChanged: (double v) => _onStockChanged('damping', v),
        onPickupChanged: (double v) => _onStockChanged('pickup', v),
        onDriveChanged: (double v) => _onStockChanged('drive', v),
        onChorusChanged: (double v) => _onStockChanged('chorus', v),
        onReverbSizeChanged: (double v) => _onStockChanged('reverb size', v),
        onDynamicsChanged: (double v) => _onStockChanged('dynamics', v),
        onPitchChanged: (double v) => _onStockChanged('pitch', v),
        onModRateChanged: (double v) => _onStockChanged('mod rate', v),
        onAttackChanged: (double v) => _onStockChanged('attack', v),
        onAuditionNoteOn: widget.client.auditionNoteOn,
        onAuditionNoteOff: widget.client.auditionNoteOff,
      );
    } else if (isPiano) {
      editorContent = PianoStockEditor(
        preset: _stockValue('preset', 0.0),
        tone: _stockValue('tone', 0.65),
        body: _stockValue('body', 0.60),
        decay: _stockValue('decay', 0.60),
        release: _stockValue('release', 0.40),
        room: _stockValue('room', 0.35),
        width: _stockValue('width', 0.70),
        output: _stockValue('output', 0.75),
        attack: _stockValue('attack', 0.05),
        sustain: _stockValue('sustain', 0.00),
        hammer: _stockValue('hammer', 0.50),
        damper: _stockValue('damper', 0.30),
        detune: _stockValue('detune', 0.20),
        velocitySens: _stockValue('velocity', 0.75),
        reverbSize: _stockValue('size', 0.55),
        modDepth: _stockValue('depth', 0.00),
        modRate: _stockValue('rate', 0.30),
        drive: _stockValue('drive', 0.00),
        pitch: _stockValue('pitch', 0.50),
        onPresetChanged: _onPianoPresetSelected,
        onToneChanged: (double v) => _onStockChanged('tone', v),
        onBodyChanged: (double v) => _onStockChanged('body', v),
        onDecayChanged: (double v) => _onStockChanged('decay', v),
        onReleaseChanged: (double v) => _onStockChanged('release', v),
        onRoomChanged: (double v) => _onStockChanged('room', v),
        onWidthChanged: (double v) => _onStockChanged('width', v),
        onOutputChanged: (double v) => _onStockChanged('output', v),
        onAttackChanged: (double v) => _onStockChanged('attack', v),
        onSustainChanged: (double v) => _onStockChanged('sustain', v),
        onHammerChanged: (double v) => _onStockChanged('hammer', v),
        onDamperChanged: (double v) => _onStockChanged('damper', v),
        onDetuneChanged: (double v) => _onStockChanged('detune', v),
        onVelocitySensChanged: (double v) => _onStockChanged('velocity', v),
        onReverbSizeChanged: (double v) => _onStockChanged('size', v),
        onModDepthChanged: (double v) => _onStockChanged('depth', v),
        onModRateChanged: (double v) => _onStockChanged('rate', v),
        onDriveChanged: (double v) => _onStockChanged('drive', v),
        onPitchChanged: (double v) => _onStockChanged('pitch', v),
        onAuditionNoteOn: widget.client.auditionNoteOn,
        onAuditionNoteOff: widget.client.auditionNoteOff,
      );
    } else if (isGuitar) {
      editorContent = GuitarStockEditor(
        preset: _stockValue('preset', 0.0),
        tone: _stockValue('tone', 0.70),
        body: _stockValue('body', 0.65),
        decay: _stockValue('decay', 0.65),
        release: _stockValue('release', 0.35),
        room: _stockValue('room', 0.30),
        width: _stockValue('width', 0.60),
        output: _stockValue('output', 0.80),
        pickPos: _stockValue('pick position', 0.25),
        damping: _stockValue('damping', 0.20),
        pickup: _stockValue('pickup', 0.00),
        drive: _stockValue('drive', 0.00),
        chorus: _stockValue('chorus', 0.00),
        reverbSize: _stockValue('reverb size', 0.50),
        dynamics: _stockValue('dynamics', 0.80),
        pitch: _stockValue('pitch', 0.50),
        modRate: _stockValue('mod rate', 0.30),
        attack: _stockValue('attack', 0.60),
        onPresetChanged: _onGuitarPresetSelected,
        onToneChanged: (double v) => _onStockChanged('tone', v),
        onBodyChanged: (double v) => _onStockChanged('body', v),
        onDecayChanged: (double v) => _onStockChanged('decay', v),
        onReleaseChanged: (double v) => _onStockChanged('release', v),
        onRoomChanged: (double v) => _onStockChanged('room', v),
        onWidthChanged: (double v) => _onStockChanged('width', v),
        onOutputChanged: (double v) => _onStockChanged('output', v),
        onPickPosChanged: (double v) => _onStockChanged('pick position', v),
        onDampingChanged: (double v) => _onStockChanged('damping', v),
        onPickupChanged: (double v) => _onStockChanged('pickup', v),
        onDriveChanged: (double v) => _onStockChanged('drive', v),
        onChorusChanged: (double v) => _onStockChanged('chorus', v),
        onReverbSizeChanged: (double v) => _onStockChanged('reverb size', v),
        onDynamicsChanged: (double v) => _onStockChanged('dynamics', v),
        onPitchChanged: (double v) => _onStockChanged('pitch', v),
        onModRateChanged: (double v) => _onStockChanged('mod rate', v),
        onAttackChanged: (double v) => _onStockChanged('attack', v),
        onAuditionNoteOn: widget.client.auditionNoteOn,
        onAuditionNoteOff: widget.client.auditionNoteOff,
      );
    } else if (isSynth) {
      editorContent = SynthStockEditor(
        preset: _stockValue('preset', 0.0),
        oscShape: _stockValue('osc shape', 0.08),
        oscMix: _stockValue('osc mix', 0.35),
        detune: _stockValue('detune', 0.50),
        sub: _stockValue('sub', 0.72),
        cutoff: _stockValue('cutoff', 0.75),
        resonance: _stockValue('resonance', 0.30),
        filterEnv: _stockValue('filter env', 0.62),
        attack: _stockValue('attack', 0.05),
        decay: _stockValue('decay', 0.30),
        sustain: _stockValue('sustain', 0.80),
        release: _stockValue('release', 0.40),
        drive: _stockValue('drive', 0.20),
        delay: _stockValue('delay', 0.04),
        width: _stockValue('width', 0.28),
        output: _stockValue('output', 0.78),
        lfoRate: _stockValue('lfo rate', 0.18),
        lfoDepth: _stockValue('lfo depth', 0.08),
        glide: _stockValue('glide', 0.00),
        noise: _stockValue('noise', 0.02),
        onPresetChanged: _onSynthPresetSelected,
        onOscShapeChanged: (double value) => _onStockChanged('osc shape', value),
        onOscMixChanged: (double value) => _onStockChanged('osc mix', value),
        onDetuneChanged: (double value) => _onStockChanged('detune', value),
        onSubChanged: (double value) => _onStockChanged('sub', value),
        onCutoffChanged: (double value) => _onStockChanged('cutoff', value),
        onResonanceChanged: (double value) => _onStockChanged('resonance', value),
        onFilterEnvChanged: (double value) => _onStockChanged('filter env', value),
        onAttackChanged: (double value) => _onStockChanged('attack', value),
        onDecayChanged: (double value) => _onStockChanged('decay', value),
        onSustainChanged: (double value) => _onStockChanged('sustain', value),
        onReleaseChanged: (double value) => _onStockChanged('release', value),
        onDriveChanged: (double value) => _onStockChanged('drive', value),
        onDelayChanged: (double value) => _onStockChanged('delay', value),
        onWidthChanged: (double value) => _onStockChanged('width', value),
        onOutputChanged: (double value) => _onStockChanged('output', value),
        onLfoRateChanged: (double value) => _onStockChanged('lfo rate', value),
        onLfoDepthChanged: (double value) => _onStockChanged('lfo depth', value),
        onGlideChanged: (double value) => _onStockChanged('glide', value),
        onNoiseChanged: (double value) => _onStockChanged('noise', value),
        onAuditionNoteOn: widget.client.auditionNoteOn,
        onAuditionNoteOff: widget.client.auditionNoteOff,
      );
    } else if (lower.contains('sampler')) {
      editorContent = SamplerStockEditor(
        sampleName: widget.sampleName,
        pitch: _stockValue('pitch', 0.5),
        startOffset: _stockValue('start', 0.0),
        attack: _stockValue('attack', 0.0),
        decay: _stockValue('decay', 0.25),
        sustain: _stockValue('sustain', 1.0),
        release: _stockValue('release', 0.25),
        reverse: _samplerReverse,
        onPitchChanged: (double value) => _onStockChanged('pitch', value),
        onStartOffsetChanged: (double value) => _onStockChanged('start', value),
        onAttackChanged: (double value) => _onStockChanged('attack', value),
        onDecayChanged: (double value) => _onStockChanged('decay', value),
        onSustainChanged: (double value) => _onStockChanged('sustain', value),
        onReleaseChanged: (double value) => _onStockChanged('release', value),
        onReverseToggle: () => setState(() => _samplerReverse = !_samplerReverse),
      );
    } else {
      editorContent = GenericParamEditor(parameters: _parameters, onParameterChanged: _onParamChanged);
    }

    final ObFloatingWindowVm windowVm = ObFloatingWindowVm(
      title: widget.pluginName,
      subtitle: '${widget.trackName} · ${_bypassed ? "BYPASSED" : "ACTIVE"} · KEYS ${_noteName(_typingBaseKey)}',
      actions: <ObWindowAction>[
        ObWindowAction(icon: ObKitGlyphKind.waveform, onTap: _onToggleBypass, tooltip: _bypassed ? 'Engage' : 'Bypass'),
        ObWindowAction(icon: ObKitGlyphKind.close, onTap: widget.onClose, tooltip: 'Close window'),
      ],
    );

    final OneBeatTokens tokens = OneBeatTheme.of(context);

    // The typing keyboard wraps the whole window, not just the drawn keys: the
    // user's hands are on the letter rows wherever the pointer happens to be,
    // and a generic third-party editor with no on-screen keyboard at all still
    // gets to be played. [ and ] shift its octave.
    return TypingKeyboard(
      baseOctave: _kTypingBaseOctave,
      onNoteOn: widget.client.auditionNoteOn,
      onNoteOff: widget.client.auditionNoteOff,
      onFocusGained: _selectOwnInstrument,
      onBaseKeyChanged: (int key) => setState(() => _typingBaseKey = key),
      child: ObFloatingWindow.plugin(
        vm: windowVm,
        width:
            isPiano
                ? 720
                : (isGuitar
                    ? 860
                    : (isLowkey ? 900 : (isSynth ? tokens.size.synthWindowWidth : tokens.size.pluginWindowWidth))),
        height:
            isPiano
                ? 430
                : (isGuitar
                    ? 520
                    : (isLowkey
                        ? 680
                        : (isOrgan
                            ? 500
                            : (isSynth ? tokens.size.synthWindowHeight : tokens.size.pluginWindowHeight)))),
        onDragUpdate: widget.onDragUpdate,
        child: editorContent,
      ),
    );
  }
}
