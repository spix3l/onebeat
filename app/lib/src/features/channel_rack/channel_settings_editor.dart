import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/dropdown.dart';
import '../../ui_kit/toggle_chip.dart';

/// The advanced settings surface deliberately edits one immutable value at a
/// time. The binding can therefore send the whole settings record as one
/// undoable native command when the user applies the sheet.
class ChannelSettingsEditor extends StatefulWidget {
  const ChannelSettingsEditor({
    required this.channelName,
    required this.initial,
    required this.onApply,
    required this.onClose,
    this.embedded = false,
    super.key,
  });

  final String channelName;
  final InstrumentSettings initial;
  final ValueChanged<InstrumentSettings> onApply;
  final VoidCallback onClose;

  /// Omits the modal scrim and centering when used as a tab in the shared
  /// channel editor.
  final bool embedded;

  @override
  State<ChannelSettingsEditor> createState() => _ChannelSettingsEditorState();
}

class _ChannelSettingsEditorState extends State<ChannelSettingsEditor> {
  late InstrumentSettings _settings = widget.initial;

  void _update(InstrumentSettings Function(InstrumentSettings) change) {
    setState(() => _settings = change(_settings));
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    final Widget panel = Container(
      padding: EdgeInsets.all(tokens.spacing.xl),
      decoration: BoxDecoration(
        color: color.surfacePanel,
        borderRadius: tokens.radius.panelBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('CHANNEL SETTINGS', style: tokens.type.sectionHeader),
                    SizedBox(height: tokens.spacing.xs),
                    Text(widget.channelName, style: tokens.type.title),
                  ],
                ),
              ),
              ObButton(label: 'Close', onTap: widget.onClose),
            ],
          ),
          SizedBox(height: tokens.spacing.lg),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Section(
                    title: 'Voice',
                    children: <Widget>[
                      _ChoiceRow(
                        label: 'Gate',
                        value: '${_settings.gatePercent}%',
                        items: const <String>['25%', '50%', '75%', '100%'],
                        onSelected: (String value) => _update(
                          (InstrumentSettings current) => InstrumentSettings(
                            gatePercent: int.parse(value.replaceAll('%', '')),
                            shiftTicks: current.shiftTicks,
                            cutGroup: current.cutGroup,
                            cutByGroup: current.cutByGroup,
                            maxPolyphony: current.maxPolyphony,
                            mono: current.mono,
                            portamento: current.portamento,
                            rootKey: current.rootKey,
                            keyLow: current.keyLow,
                            keyHigh: current.keyHigh,
                            fineTuneCents: current.fineTuneCents,
                            velocityTracking: current.velocityTracking,
                            modX: current.modX,
                            modY: current.modY,
                            arpeggiator: current.arpeggiator,
                            arpeggiatorTimeTicks: current.arpeggiatorTimeTicks,
                            arpeggiatorGatePercent: current.arpeggiatorGatePercent,
                            echoTimeTicks: current.echoTimeTicks,
                            echoFeedbackPercent: current.echoFeedbackPercent,
                          ),
                        ),
                      ),
                      _ToggleRow(
                        label: 'Mono',
                        on: _settings.mono,
                        onTap: () => _update((InstrumentSettings current) => _copy(current, mono: !current.mono)),
                      ),
                      _ToggleRow(
                        label: 'Portamento',
                        on: _settings.portamento,
                        onTap: () => _update(
                          (InstrumentSettings current) => _copy(current, portamento: !current.portamento),
                        ),
                      ),
                      _ChoiceRow(
                        label: 'Max polyphony',
                        value: _settings.maxPolyphony == 0 ? 'Unlimited' : '${_settings.maxPolyphony}',
                        items: const <String>['Unlimited', '1', '2', '4', '8', '16'],
                        onSelected: (String value) => _update(
                          (InstrumentSettings current) => _copy(
                            current,
                            maxPolyphony: value == 'Unlimited' ? 0 : int.parse(value),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Tuning and range',
                    children: <Widget>[
                      _ChoiceRow(
                        label: 'Root key',
                        value: '${_settings.rootKey}',
                        items: <String>[for (int key = 0; key <= 127; key++) '$key'],
                        onSelected: (String value) => _update(
                          (InstrumentSettings current) => _copy(current, rootKey: int.parse(value)),
                        ),
                      ),
                      _ChoiceRow(
                        label: 'Key range',
                        value: '${_settings.keyLow}–${_settings.keyHigh}',
                        items: <String>[
                          for (final (int low, int high) in const <(int, int)>[
                            (0, 127),
                            (36, 96),
                            (48, 84),
                            (60, 72),
                          ])
                            '$low–$high',
                        ],
                        onSelected: (String value) {
                          final List<String> parts = value.split('–');
                          _update(
                            (InstrumentSettings current) =>
                                _copy(current, keyLow: int.parse(parts[0]), keyHigh: int.parse(parts[1])),
                          );
                        },
                      ),
                      _ChoiceRow(
                        label: 'Fine tune',
                        value: '${_settings.fineTuneCents} cents',
                        items: const <String>['-100 cents', '0 cents', '100 cents'],
                        onSelected: (String value) => _update(
                          (InstrumentSettings current) =>
                              _copy(current, fineTuneCents: int.parse(value.split(' ').first)),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Arpeggiator and echo',
                    children: <Widget>[
                      _ToggleRow(
                        label: 'Arpeggiator',
                        on: _settings.arpeggiator,
                        onTap: () => _update(
                          (InstrumentSettings current) => _copy(current, arpeggiator: !current.arpeggiator),
                        ),
                      ),
                      _ChoiceRow(
                        label: 'Arp gate',
                        value: '${_settings.arpeggiatorGatePercent}%',
                        items: const <String>['25%', '50%', '75%', '100%'],
                        onSelected: (String value) => _update(
                          (InstrumentSettings current) => _copy(
                            current,
                            arpeggiatorGatePercent: int.parse(value.replaceAll('%', '')),
                          ),
                        ),
                      ),
                      _ChoiceRow(
                        label: 'Echo feedback',
                        value: '${_settings.echoFeedbackPercent}%',
                        items: const <String>['0%', '25%', '50%', '75%'],
                        onSelected: (String value) => _update(
                          (InstrumentSettings current) => _copy(
                            current,
                            echoFeedbackPercent: int.parse(value.replaceAll('%', '')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              ObButton(label: 'Cancel', onTap: widget.onClose),
              SizedBox(width: tokens.spacing.sm),
              ObButton(label: 'Apply settings', tone: ObButtonTone.primary, onTap: () => widget.onApply(_settings)),
            ],
          ),
        ],
      ),
    );
    return widget.embedded
        ? panel
        : ColoredBox(
            color: color.canvasScrim,
            child: Center(child: panel),
          );
  }

  InstrumentSettings _copy(
    InstrumentSettings current, {
    int? gatePercent,
    int? maxPolyphony,
    bool? mono,
    bool? portamento,
    int? rootKey,
    int? keyLow,
    int? keyHigh,
    int? fineTuneCents,
    bool? arpeggiator,
    int? arpeggiatorGatePercent,
    int? echoFeedbackPercent,
  }) => InstrumentSettings(
    gatePercent: gatePercent ?? current.gatePercent,
    shiftTicks: current.shiftTicks,
    cutGroup: current.cutGroup,
    cutByGroup: current.cutByGroup,
    maxPolyphony: maxPolyphony ?? current.maxPolyphony,
    mono: mono ?? current.mono,
    portamento: portamento ?? current.portamento,
    rootKey: rootKey ?? current.rootKey,
    keyLow: keyLow ?? current.keyLow,
    keyHigh: keyHigh ?? current.keyHigh,
    fineTuneCents: fineTuneCents ?? current.fineTuneCents,
    velocityTracking: current.velocityTracking,
    modX: current.modX,
    modY: current.modY,
    arpeggiator: arpeggiator ?? current.arpeggiator,
    arpeggiatorTimeTicks: current.arpeggiatorTimeTicks,
    arpeggiatorGatePercent: arpeggiatorGatePercent ?? current.arpeggiatorGatePercent,
    echoTimeTicks: current.echoTimeTicks,
    echoFeedbackPercent: echoFeedbackPercent ?? current.echoFeedbackPercent,
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title.toUpperCase(), style: tokens.type.microCaps),
          SizedBox(height: tokens.spacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.value, required this.items, required this.onSelected});
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: tokens.type.body)),
          ObDropdown(label: label, value: value, items: items, width: 180, onSelected: onSelected),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: tokens.type.body)),
          ObToggleChip(tone: ObToggleTone.solo, on: on, onTap: onTap),
        ],
      ),
    );
  }
}
