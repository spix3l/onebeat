import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/floating_window.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'stock/generic_editor.dart';
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
    super.key,
  });

  final EngineClient client;
  final String trackId;
  final String pluginName;
  final String trackName;
  final bool isBypassed;
  final List<HostedParameter> parameters;
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
  }

  @override
  Widget build(BuildContext context) {
    final String lower = widget.pluginName.toLowerCase();

    Widget editorContent;
    if (lower.contains('synth')) {
      editorContent = const SynthStockEditor();
    } else if (lower.contains('sampler')) {
      editorContent = const SamplerStockEditor();
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
      width: tokens.size.pluginWindowWidth,
      height: tokens.size.pluginWindowHeight,
      child: editorContent,
    );
  }
}
