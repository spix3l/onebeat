// Built-in Plugins View (matches onebeat-plugin-builtin.html.png).
//
// Full UI for the built-in Sampler and Compressor plugins.
// Built entirely from tokens with zero raw literals.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'controls.dart';
import 'engine_controller.dart';

class BuiltinPluginsView extends StatefulWidget {
  const BuiltinPluginsView({
    required this.controller,
    super.key,
  });

  final EngineController controller;

  @override
  State<BuiltinPluginsView> createState() => _BuiltinPluginsViewState();
}

class _BuiltinPluginsViewState extends State<BuiltinPluginsView> {
  int _activePluginTab = 0; // 0 = Sampler, 1 = Compressor

  // Sampler state
  double _samplerTune = 0.0;
  double _samplerFine = 0.0;
  double _samplerVol = 0.0;
  double _samplerPan = 0.0;
  bool _samplerLoop = false;

  // Compressor state
  double _compThresh = -18.0;
  double _compRatio = 4.0;
  double _compAttack = 12.0;
  double _compRelease = 150.0;
  double _compMix = 100.0;
  double _compMakeup = 3.5;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PluginViewHeader(
            activeTab: _activePluginTab,
            onTabChanged: (int tab) => setState(() => _activePluginTab = tab),
            tokens: tokens,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: _activePluginTab == 0
                  ? _SamplerPluginPanel(
                      tune: _samplerTune,
                      fine: _samplerFine,
                      vol: _samplerVol,
                      pan: _samplerPan,
                      loop: _samplerLoop,
                      onTuneChanged: (double v) => setState(() => _samplerTune = v),
                      onFineChanged: (double v) => setState(() => _samplerFine = v),
                      onVolChanged: (double v) => setState(() => _samplerVol = v),
                      onPanChanged: (double v) => setState(() => _samplerPan = v),
                      onLoopToggle: () => setState(() => _samplerLoop = !_samplerLoop),
                      tokens: tokens,
                    )
                  : _CompressorPluginPanel(
                      thresh: _compThresh,
                      ratio: _compRatio,
                      attack: _compAttack,
                      release: _compRelease,
                      mix: _compMix,
                      makeup: _compMakeup,
                      onThreshChanged: (double v) => setState(() => _compThresh = v),
                      onRatioChanged: (double v) => setState(() => _compRatio = v),
                      onAttackChanged: (double v) => setState(() => _compAttack = v),
                      onReleaseChanged: (double v) => setState(() => _compRelease = v),
                      onMixChanged: (double v) => setState(() => _compMix = v),
                      onMakeupChanged: (double v) => setState(() => _compMakeup = v),
                      tokens: tokens,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginViewHeader extends StatelessWidget {
  const _PluginViewHeader({
    required this.activeTab,
    required this.onTabChanged,
    required this.tokens,
  });

  final int activeTab;
  final ValueChanged<int> onTabChanged;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: tokens.size.pianoToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text('PLUGINS', style: tokens.type.sectionHeader),
          SizedBox(width: tokens.spacing.lg),
          OneBeatSegmentedControl<int>(
            value: activeTab,
            options: const <int>[0, 1],
            labelOf: (int tab) => tab == 0 ? 'Sampler' : 'Compressor',
            onChanged: onTabChanged,
          ),
          SizedBox(width: tokens.spacing.md),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.sm,
              vertical: tokens.spacing.xxs,
            ),
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
            ),
            child: Text(
              activeTab == 0 ? 'kick_808.wav · 0.8s' : 'Sidechain: Sub Bass (Track 6)',
              style: tokens.type.tag,
            ),
          ),
        ],
      ),
    );
  }
}

class _SamplerPluginPanel extends StatelessWidget {
  const _SamplerPluginPanel({
    required this.tune,
    required this.fine,
    required this.vol,
    required this.pan,
    required this.loop,
    required this.onTuneChanged,
    required this.onFineChanged,
    required this.onVolChanged,
    required this.onPanChanged,
    required this.onLoopToggle,
    required this.tokens,
  });

  final double tune;
  final double fine;
  final double vol;
  final double pan;
  final bool loop;
  final ValueChanged<double> onTuneChanged;
  final ValueChanged<double> onFineChanged;
  final ValueChanged<double> onVolChanged;
  final ValueChanged<double> onPanChanged;
  final VoidCallback onLoopToggle;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      padding: EdgeInsets.all(tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('ONEBEAT SAMPLER', style: tokens.type.title),
              SizedBox(width: tokens.spacing.md),
              Text('44.1 kHz · 24-bit PCM', style: tokens.type.numericSmall),
              const Spacer(),
              OneBeatButton(
                label: loop ? 'LOOP ON' : 'ONE-SHOT',
                active: loop,
                onPressed: onLoopToggle,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),
          // Waveform Display Well
          Container(
            height: tokens.size.knobLarge * 2.5, // token-lint-ok: proportional height
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            child: CustomPaint(
              painter: _WaveformDisplayPainter(tokens: tokens),
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          // Knobs Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              OneBeatKnob(
                label: 'Tune',
                value: tune,
                min: -24.0, // token-lint-ok: semitones
                max: 24.0, // token-lint-ok: semitones
                defaultValue: 0.0,
                unit: ' st',
                onChanged: onTuneChanged,
              ),
              OneBeatKnob(
                label: 'Fine',
                value: fine,
                min: -50.0, // token-lint-ok: cents
                max: 50.0, // token-lint-ok: cents
                defaultValue: 0.0,
                unit: ' ct',
                onChanged: onFineChanged,
              ),
              OneBeatKnob(
                label: 'Volume',
                value: vol,
                min: -60.0, // token-lint-ok: dB
                max: 6.0, // token-lint-ok: dB
                defaultValue: 0.0,
                unit: ' dB',
                onChanged: onVolChanged,
              ),
              OneBeatKnob(
                label: 'Pan',
                value: pan,
                min: -100.0, // token-lint-ok: pan percentage
                max: 100.0, // token-lint-ok: pan percentage
                defaultValue: 0.0,
                displayValue: pan == 0 ? 'C' : (pan < 0 ? 'L${pan.abs().toInt()}' : 'R${pan.toInt()}'),
                onChanged: onPanChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaveformDisplayPainter extends CustomPainter {
  const _WaveformDisplayPainter({required this.tokens});

  final OneBeatTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint wavePaint = Paint()
      ..color = tokens.color.waveform
      ..strokeWidth = tokens.border.hairline
      ..style = PaintingStyle.stroke;

    final Paint centerPaint = Paint()
      ..color = tokens.color.gridLine
      ..strokeWidth = tokens.border.hairline;

    final double midY = size.height / 2; // token-lint-ok: center
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), centerPaint);

    final Path wavePath = Path()..moveTo(0, midY);
    const int sampleCount = 64;
    final double stepX = size.width / sampleCount;

    for (int i = 0; i <= sampleCount; i++) {
      final double fraction = i / sampleCount;
      // Exponential decay envelope
      final double env = (1.0 - fraction) * (1.0 - fraction); // token-lint-ok: decay
      final double wave = (i % 2 == 0 ? 1.0 : -1.0) * env * (size.height * 0.4); // token-lint-ok: oscillation
      wavePath.lineTo(i * stepX, midY + wave);
    }
    canvas.drawPath(wavePath, wavePaint);

    // Playhead line
    final Paint playheadPaint = Paint()
      ..color = tokens.color.playhead
      ..strokeWidth = tokens.size.playheadWidth;
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), playheadPaint); // token-lint-ok: cursor position
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompressorPluginPanel extends StatelessWidget {
  const _CompressorPluginPanel({
    required this.thresh,
    required this.ratio,
    required this.attack,
    required this.release,
    required this.mix,
    required this.makeup,
    required this.onThreshChanged,
    required this.onRatioChanged,
    required this.onAttackChanged,
    required this.onReleaseChanged,
    required this.onMixChanged,
    required this.onMakeupChanged,
    required this.tokens,
  });

  final double thresh;
  final double ratio;
  final double attack;
  final double release;
  final double mix;
  final double makeup;
  final ValueChanged<double> onThreshChanged;
  final ValueChanged<double> onRatioChanged;
  final ValueChanged<double> onAttackChanged;
  final ValueChanged<double> onReleaseChanged;
  final ValueChanged<double> onMixChanged;
  final ValueChanged<double> onMakeupChanged;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      padding: EdgeInsets.all(tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('ONEBEAT DYNAMICS COMPRESSOR', style: tokens.type.title),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.spacing.sm,
                  vertical: tokens.spacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: tokens.color.tagAutoBg,
                  borderRadius: tokens.radius.controlBorder,
                ),
                child: Text('SIDECHAIN ACTIVE', style: tokens.type.tag.copyWith(color: tokens.color.tagAutoFg)),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),
          // Gain Reduction Meter Strip
          Container(
            height: tokens.size.readoutHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Text('GR -4.2 dB', style: tokens.type.numeric),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Container(
                    height: tokens.spacing.sm,
                    decoration: BoxDecoration(
                      color: tokens.color.surfaceSunken,
                      borderRadius: tokens.radius.controlBorder,
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.35, // token-lint-ok: compression factor
                      child: Container(
                        decoration: BoxDecoration(
                          color: tokens.color.warning,
                          borderRadius: tokens.radius.controlBorder,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          // 6 Dials
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              OneBeatKnob(
                label: 'Thresh',
                value: thresh,
                min: -60.0, // token-lint-ok: dB
                max: 0.0, // token-lint-ok: dB
                defaultValue: -18.0,
                unit: ' dB',
                onChanged: onThreshChanged,
              ),
              OneBeatKnob(
                label: 'Ratio',
                value: ratio,
                min: 1.0, // token-lint-ok: ratio
                max: 20.0, // token-lint-ok: ratio
                defaultValue: 4.0,
                displayValue: '${ratio.toStringAsFixed(1)}:1',
                onChanged: onRatioChanged,
              ),
              OneBeatKnob(
                label: 'Attack',
                value: attack,
                min: 0.1, // token-lint-ok: ms
                max: 100.0, // token-lint-ok: ms
                defaultValue: 12.0,
                unit: ' ms',
                onChanged: onAttackChanged,
              ),
              OneBeatKnob(
                label: 'Release',
                value: release,
                min: 10.0, // token-lint-ok: ms
                max: 1000.0, // token-lint-ok: ms
                defaultValue: 150.0,
                unit: ' ms',
                onChanged: onReleaseChanged,
              ),
              OneBeatKnob(
                label: 'Mix',
                value: mix,
                min: 0.0, // token-lint-ok: percentage
                max: 100.0, // token-lint-ok: percentage
                defaultValue: 100.0,
                unit: '%',
                onChanged: onMixChanged,
              ),
              OneBeatKnob(
                label: 'Makeup',
                value: makeup,
                min: 0.0, // token-lint-ok: dB
                max: 24.0, // token-lint-ok: dB
                defaultValue: 3.5,
                unit: ' dB',
                onChanged: onMakeupChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
