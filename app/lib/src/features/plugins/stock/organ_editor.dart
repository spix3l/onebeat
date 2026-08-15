// OrganStockEditor — compact tonewheel organ editor for the built-in Organ.
import 'package:flutter/widgets.dart';

import '../../../design/tokens.dart';
import '../../../ui_kit/button.dart';
import '../../../ui_kit/knob.dart';

class OrganStockEditor extends StatelessWidget {
  const OrganStockEditor({
    this.preset = 0.0,
    this.percussion = 0.35,
    this.click = 0.2,
    this.drive = 0.15,
    this.reverb = 0.25,
    this.rotary = 0.5,
    this.attack = 0.1,
    this.release = 0.35,
    this.onPresetChanged,
    this.onPercussionChanged,
    this.onClickChanged,
    this.onDriveChanged,
    this.onReverbChanged,
    this.onRotaryChanged,
    this.onAttackChanged,
    this.onReleaseChanged,
    this.onAuditionNoteOn,
    this.onAuditionNoteOff,
    super.key,
  });

  final double preset;
  final double percussion;
  final double click;
  final double drive;
  final double reverb;
  final double rotary;
  final double attack;
  final double release;
  final ValueChanged<double>? onPresetChanged;
  final ValueChanged<double>? onPercussionChanged;
  final ValueChanged<double>? onClickChanged;
  final ValueChanged<double>? onDriveChanged;
  final ValueChanged<double>? onReverbChanged;
  final ValueChanged<double>? onRotaryChanged;
  final ValueChanged<double>? onAttackChanged;
  final ValueChanged<double>? onReleaseChanged;
  final void Function(int key, double velocity)? onAuditionNoteOn;
  final ValueChanged<int>? onAuditionNoteOff;

  static const List<String> _presetNames = <String>[
    'Church / 888000000',
    'Jazz / 888800000',
    'Gospel / 888888888',
    'Cinema / 808004000',
  ];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int presetIndex = (preset * _presetNames.length).floor().clamp(0, _presetNames.length - 1);

    return Padding(
      padding: EdgeInsets.fromLTRB(tokens.spacing.lg, tokens.spacing.md, tokens.spacing.lg, tokens.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(tokens: tokens),
          SizedBox(height: tokens.spacing.md),
          _PresetRail(
            tokens: tokens,
            name: _presetNames[presetIndex],
            onPrevious:
                onPresetChanged == null
                    ? null
                    : () => onPresetChanged!((presetIndex - 1).clamp(0, _presetNames.length - 1) / _presetNames.length),
            onNext:
                onPresetChanged == null
                    ? null
                    : () => onPresetChanged!((presetIndex + 1).clamp(0, _presetNames.length - 1) / _presetNames.length),
          ),
          SizedBox(height: tokens.spacing.md),
          _Section(
            tokens: tokens,
            title: 'DRAWBARS',
            trailing: 'HARMONIC MIX',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _Drawbar(label: '16\'', value: preset, onChanged: onPresetChanged),
                _Drawbar(label: '5 1/3\'', value: percussion, onChanged: onPercussionChanged),
                _Drawbar(label: '8\'', value: click, onChanged: onClickChanged),
                _Drawbar(label: '4\'', value: drive, onChanged: onDriveChanged),
                _Drawbar(label: '2\'', value: reverb, onChanged: onReverbChanged),
              ],
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _Section(
                    tokens: tokens,
                    title: 'CHARACTER',
                    trailing: 'AIR + GRIT',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        _KnobControl(label: 'ATTACK', value: attack, onChanged: onAttackChanged),
                        _KnobControl(label: 'RELEASE', value: release, onChanged: onReleaseChanged),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: _Section(
                    tokens: tokens,
                    title: 'CABINET',
                    trailing: rotary > 0.5 ? 'FAST' : 'SLOW',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('ROTARY SPEAKER', style: tokens.type.microCaps),
                        SizedBox(height: tokens.spacing.xs),
                        ObButton(
                          label: rotary > 0.5 ? 'FAST' : 'SLOW',
                          tone: ObButtonTone.accentOutline,
                          width: double.infinity,
                          onTap: onRotaryChanged == null ? null : () => onRotaryChanged!(rotary > 0.5 ? 0.2 : 0.8),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          _Section(
            tokens: tokens,
            title: 'PREVIEW',
            trailing: 'C3 — D5',
            child: _MiniKeyboard(onNoteOn: onAuditionNoteOn, onNoteOff: onAuditionNoteOff),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Text('TONEWHEEL ORGAN', style: tokens.type.title.copyWith(letterSpacing: 1.2)),
      const Spacer(),
      Text('OB / 01', style: tokens.type.numericSmall.copyWith(color: tokens.color.accentBright)),
    ],
  );
}

class _PresetRail extends StatelessWidget {
  const _PresetRail({required this.tokens, required this.name, this.onPrevious, this.onNext});

  final OneBeatTokens tokens;
  final String name;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
    decoration: BoxDecoration(
      color: tokens.color.surfaceSunken,
      borderRadius: tokens.radius.controlBorder,
      border: Border.all(color: tokens.color.lineStrong, width: tokens.border.hairline),
    ),
    child: Row(
      children: <Widget>[
        Text('PATCH', style: tokens.type.microCaps.copyWith(color: tokens.color.accentBright)),
        SizedBox(width: tokens.spacing.sm),
        Expanded(child: Text(name, style: tokens.type.numeric, overflow: TextOverflow.ellipsis)),
        ObButton(label: '<', tone: ObButtonTone.quiet, onTap: onPrevious),
        ObButton(label: '>', tone: ObButtonTone.quiet, onTap: onNext),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.tokens, required this.title, required this.trailing, required this.child});

  final OneBeatTokens tokens;
  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(tokens.spacing.sm),
    decoration: BoxDecoration(
      color: tokens.color.surfacePanel,
      borderRadius: tokens.radius.controlBorder,
      border: Border.all(color: tokens.color.line, width: tokens.border.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(title, style: tokens.type.label),
            const Spacer(),
            Text(trailing, style: tokens.type.microCaps.copyWith(color: tokens.color.textMuted)),
          ],
        ),
        SizedBox(height: tokens.spacing.sm),
        child,
      ],
    ),
  );
}

class _Drawbar extends StatelessWidget {
  const _Drawbar({required this.label, required this.value, this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('${(value.clamp(0.0, 1.0) * 8).round()}', style: tokens.type.numericSmall),
        SizedBox(height: tokens.spacing.xxs),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate:
              onChanged == null
                  ? null
                  : (DragUpdateDetails details) => onChanged!((value - details.delta.dy / 64).clamp(0.0, 1.0)),
          child: SizedBox(
            width: 28,
            height: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.color.surfaceSunken,
                borderRadius: tokens.radius.controlBorder,
                border: Border.all(color: tokens.color.lineStrong, width: tokens.border.hairline),
              ),
              child: Align(
                alignment: Alignment(0, 1 - value.clamp(0.0, 1.0) * 2),
                child: Container(
                  width: 22,
                  height: 12,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: tokens.color.accent, borderRadius: tokens.radius.controlBorder),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: tokens.spacing.xs),
        Text(label, style: tokens.type.microCaps),
      ],
    );
  }
}

class _KnobControl extends StatelessWidget {
  const _KnobControl({required this.label, required this.value, this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => ObKnob(label: label, value: value, onChanged: onChanged);
}

class _MiniKeyboard extends StatelessWidget {
  const _MiniKeyboard({this.onNoteOn, this.onNoteOff});

  final void Function(int key, double velocity)? onNoteOn;
  final ValueChanged<int>? onNoteOff;

  static const List<int> _blackAfterWhite = <int>[0, 1, 3, 4, 5, 7, 8, 10, 11, 12];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    const int firstNote = 48;
    const int whiteCount = 15;
    return SizedBox(
      key: const Key('organ-mini-keyboard'),
      height: 68,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double whiteWidth = constraints.maxWidth / whiteCount;
          return Stack(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int index = 0; index < whiteCount; index++)
                    _PianoKey(
                      note: firstNote + _whiteNote(index),
                      width: whiteWidth,
                      black: false,
                      tokens: tokens,
                      onNoteOn: onNoteOn,
                      onNoteOff: onNoteOff,
                    ),
                ],
              ),
              for (final int whiteIndex in _blackAfterWhite)
                Positioned(
                  left: (whiteIndex + 0.68) * whiteWidth,
                  top: 0,
                  child: _PianoKey(
                    note: firstNote + _whiteNote(whiteIndex) + 1,
                    width: whiteWidth * 0.62,
                    black: true,
                    tokens: tokens,
                    onNoteOn: onNoteOn,
                    onNoteOff: onNoteOff,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static int _whiteNote(int index) {
    const List<int> offsets = <int>[0, 2, 4, 5, 7, 9, 11];
    return (index ~/ 7) * 12 + offsets[index % 7];
  }
}

class _PianoKey extends StatelessWidget {
  const _PianoKey({
    required this.note,
    required this.width,
    required this.black,
    required this.tokens,
    this.onNoteOn,
    this.onNoteOff,
  });

  final int note;
  final double width;
  final bool black;
  final OneBeatTokens tokens;
  final void Function(int key, double velocity)? onNoteOn;
  final ValueChanged<int>? onNoteOff;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => onNoteOn?.call(note, black ? 0.78 : 0.9),
    onPointerUp: (_) => onNoteOff?.call(note),
    onPointerCancel: (_) => onNoteOff?.call(note),
    child: Container(
      width: width,
      height: black ? 42 : 68,
      decoration: BoxDecoration(
        color: black ? tokens.color.surfaceSunken : tokens.color.textPrimary,
        borderRadius: black ? tokens.radius.controlBorder : null,
        border: Border.all(color: black ? tokens.color.lineStrong : tokens.color.line, width: tokens.border.hairline),
      ),
    ),
  );
}
