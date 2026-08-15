import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/floating_window.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'stock/generic_editor.dart';
import 'stock/guitar_editor.dart';
import 'stock/piano_editor.dart';
import 'stock/sampler_editor.dart';
import 'stock/synth_editor.dart';

class PluginBinding extends StatefulWidget {
  const PluginBinding({
    required this.client,
    required this.trackId,
    required this.onClose,
    this.pluginName = 'Synth',
    this.trackName = 'Soft Keys',
    this.isBypassed = false,
    this.parameters = const <HostedParameter>[],
    this.onDragUpdate,
    super.key,
  });

  final EngineClient client;
  final String trackId;
  final String pluginName;
  final String trackName;
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

  @override
  void initState() {
    super.initState();
    _bypassed = widget.isBypassed;
    _parameters = widget.parameters;
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
      if (key == 'pitch' &&
          (name.contains('pitch') ||
              name.contains('transpose') ||
              name.contains('tune'))) {
        return parameter;
      }
    }
    return null;
  }

  double _stockValue(String label, double fallback) {
    final HostedParameter? parameter = _stockParameter(label);
    if (parameter == null) return fallback;
    final double span = parameter.maximum - parameter.minimum;
    return span > 0
        ? ((parameter.value - parameter.minimum) / span).clamp(0.0, 1.0)
        : fallback;
  }

  void _onStockChanged(String label, double value) {
    final HostedParameter? parameter = _stockParameter(label);
    if (parameter == null) return;
    final double next =
        parameter.minimum +
        value.clamp(0.0, 1.0) * (parameter.maximum - parameter.minimum);
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

  @override
  Widget build(BuildContext context) {
    final String lower = widget.pluginName.toLowerCase();
    final bool isPiano = lower.contains('piano');
    final bool isGuitar = lower.contains('guitar');

    Widget editorContent;
    if (isPiano) {
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
    } else if (lower.contains('synth')) {
      editorContent = SynthStockEditor(
        cutoff: _stockValue('cutoff', 0.75),
        resonance: _stockValue('res', 0.3),
        attack: _stockValue('attack', 0.05),
        decay: _stockValue('decay', 0.3),
        sustain: _stockValue('sustain', 0.8),
        release: _stockValue('release', 0.4),
        onCutoffChanged: (double value) => _onStockChanged('cutoff', value),
        onResonanceChanged: (double value) => _onStockChanged('res', value),
        onAttackChanged: (double value) => _onStockChanged('attack', value),
        onDecayChanged: (double value) => _onStockChanged('decay', value),
        onSustainChanged: (double value) => _onStockChanged('sustain', value),
        onReleaseChanged: (double value) => _onStockChanged('release', value),
      );
    } else if (lower.contains('sampler')) {
      editorContent = SamplerStockEditor(
        pitch: _stockValue('pitch', 0.5),
        startOffset: _stockValue('start', 0.0),
        onPitchChanged: (double value) => _onStockChanged('pitch', value),
        onStartOffsetChanged: (double value) => _onStockChanged('start', value),
      );
    } else {
      editorContent = GenericParamEditor(
        parameters: _parameters,
        onParameterChanged: _onParamChanged,
      );
    }

    final ObFloatingWindowVm windowVm = ObFloatingWindowVm(
      title: widget.pluginName,
      subtitle: '${widget.trackName} · ${_bypassed ? "BYPASSED" : "ACTIVE"}',
      actions: <ObWindowAction>[
        ObWindowAction(
          icon: ObKitGlyphKind.waveform,
          onTap: _onToggleBypass,
          tooltip: _bypassed ? 'Engage' : 'Bypass',
        ),
        ObWindowAction(
          icon: ObKitGlyphKind.close,
          onTap: widget.onClose,
          tooltip: 'Close window',
        ),
      ],
    );

    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return ObFloatingWindow.plugin(
      vm: windowVm,
      width: isPiano ? 720 : (isGuitar ? 860 : tokens.size.pluginWindowWidth),
      height: isPiano ? 430 : (isGuitar ? 520 : tokens.size.pluginWindowHeight),
      onDragUpdate: widget.onDragUpdate,
      child: editorContent,
    );
  }
}
