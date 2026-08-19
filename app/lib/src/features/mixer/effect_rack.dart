// ObEffectRack — the insert chain of one mixer track (EPIC-4).
//
// A chain is a *sequence*, and this is the one place in the app where display
// order is the truth rather than a field: slot 1 feeds slot 2. The widget says
// so by numbering the slots and drawing them as a single column with no gaps —
// a grid or a wrap would imply the order does not matter.
//
// Pure view. Every gesture is a callback; nothing here reads the engine, which
// is what lets the whole rack be pumped from a vm in a widget test.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/knob.dart';

@immutable
class EffectParamVm {
  const EffectParamVm({
    required this.id,
    required this.name,
    required this.value,
    required this.display,
    required this.minimum,
    required this.maximum,
  });

  final int id;
  final String name;

  /// The parameter's own value, in its own units.
  final double value;

  /// What the plug-in says that value reads as — "30%", "-3.0 dB", "On".
  final String display;
  final double minimum;
  final double maximum;

  /// 0..1, which is what a knob speaks. A parameter whose range is a single
  /// point sits at the bottom rather than dividing by zero.
  double get unit {
    final double span = maximum - minimum;
    if (span <= 0) return 0;
    return ((value - minimum) / span).clamp(0.0, 1.0);
  }

  double fromUnit(double unit) => minimum + (unit.clamp(0.0, 1.0) * (maximum - minimum));
}

@immutable
class EffectSlotVm {
  const EffectSlotVm({
    required this.id,
    required this.name,
    required this.params,
    this.bypassed = false,
    this.missing = false,
    this.expanded = false,
  });

  /// The slot's identity, not the plug-in's: it survives a reorder, which is
  /// what automation written against this insert depends on.
  final String id;
  final String name;
  final List<EffectParamVm> params;
  final bool bypassed;

  /// The project asks for an effect this build does not have. The slot stays —
  /// dropping it would lose the automation pointing at it — and is silent.
  final bool missing;

  /// Whether this slot's parameters are showing. One at a time: a chain of four
  /// expanded effects is taller than the panel and stops being a chain you can
  /// read at a glance.
  final bool expanded;
}

@immutable
class EffectRackVm {
  const EffectRackVm({
    required this.trackName,
    required this.slots,
    required this.available,
    this.enabled = true,
  });

  final String trackName;
  final List<EffectSlotVm> slots;

  /// What the add-menu can offer.
  final List<EffectChoiceVm> available;

  /// False when there is no track to edit — no project, or nothing selected.
  final bool enabled;
}

@immutable
class EffectChoiceVm {
  const EffectChoiceVm({required this.id, required this.name, required this.summary});

  final String id;
  final String name;
  final String summary;
}

class ObEffectRack extends StatelessWidget {
  const ObEffectRack({
    required this.vm,
    this.onAdd,
    this.onRemove,
    this.onToggleBypass,
    this.onToggleExpanded,
    this.onMove,
    this.onParamChanged,
    super.key,
  });

  final EffectRackVm vm;

  /// Appends the effect with this identifier.
  final ValueChanged<String>? onAdd;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onToggleBypass;
  final ValueChanged<String>? onToggleExpanded;

  /// (slot id, new position in the chain).
  final void Function(String id, int index)? onMove;

  /// (slot id, parameter id, value in the parameter's own units).
  final void Function(String slotId, int paramId, double value)? onParamChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final SpacingTokens space = tokens.spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: space.sm),
          child: Text('INSERTS — ${vm.trackName}', style: tokens.type.microCapsWide),
        ),
        if (vm.slots.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: space.md),
            child: Text(
              vm.enabled ? 'No effects on this track.' : 'Select a mixer track to add effects.',
              style: tokens.type.bodySecondary,
            ),
          )
        else
          for (int index = 0; index < vm.slots.length; index++)
            Padding(
              padding: EdgeInsets.only(bottom: space.xs),
              child: _Slot(
                vm: vm.slots[index],
                position: index,
                count: vm.slots.length,
                onRemove: onRemove,
                onToggleBypass: onToggleBypass,
                onToggleExpanded: onToggleExpanded,
                onMove: onMove,
                onParamChanged: onParamChanged,
              ),
            ),
        if (vm.enabled)
          Padding(
            padding: EdgeInsets.only(top: space.sm),
            child: _AddRow(available: vm.available, onAdd: onAdd, color: color, tokens: tokens),
          ),
      ],
    );
  }
}

/// The add control. A row of buttons rather than a dropdown: there are four
/// stock effects, and a menu that holds four things is a menu that costs a
/// click to tell you it holds four things.
class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.available,
    required this.onAdd,
    required this.color,
    required this.tokens,
  });

  final List<EffectChoiceVm> available;
  final ValueChanged<String>? onAdd;
  final ColorTokens color;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: tokens.spacing.xs,
      runSpacing: tokens.spacing.xs,
      children: <Widget>[
        for (final EffectChoiceVm choice in available)
          ObButton(
            label: '+ ${choice.name}',
            onTap: onAdd == null ? null : () => onAdd!(choice.id),
          ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.vm,
    required this.position,
    required this.count,
    required this.onRemove,
    required this.onToggleBypass,
    required this.onToggleExpanded,
    required this.onMove,
    required this.onParamChanged,
  });

  final EffectSlotVm vm;
  final int position;
  final int count;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onToggleBypass;
  final ValueChanged<String>? onToggleExpanded;
  final void Function(String id, int index)? onMove;
  final void Function(String slotId, int paramId, double value)? onParamChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final SpacingTokens space = tokens.spacing;

    // A bypassed or missing slot is dimmed rather than hidden: it is still in
    // the chain, still in the file, and still the thing automation points at.
    final bool inactive = vm.bypassed || vm.missing;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.surfaceWell,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(color: color.line, width: tokens.border.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: space.sm, vertical: space.xs),
            child: Row(
              children: <Widget>[
                // The chain position, stated. Without it "which one runs first"
                // is answerable only by counting rows.
                SizedBox(
                  width: tokens.size.effectSlotNumberWidth,
                  child: Text('${position + 1}', style: tokens.type.microCaps),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleExpanded == null ? null : () => onToggleExpanded!(vm.id),
                    child: Text(
                      vm.missing ? '${vm.name} (missing)' : vm.name,
                      style: inactive ? tokens.type.bodySecondary : tokens.type.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _MoveButton(
                  label: '▲',
                  enabled: position > 0 && onMove != null,
                  onTap: () => onMove!(vm.id, position - 1),
                ),
                _MoveButton(
                  label: '▼',
                  enabled: position < count - 1 && onMove != null,
                  onTap: () => onMove!(vm.id, position + 1),
                ),
                SizedBox(width: space.xs),
                _BypassChip(
                  bypassed: vm.bypassed,
                  onTap: onToggleBypass == null ? null : () => onToggleBypass!(vm.id),
                ),
                SizedBox(width: space.xs),
                _MoveButton(
                  label: '✕',
                  enabled: onRemove != null,
                  onTap: () => onRemove!(vm.id),
                ),
              ],
            ),
          ),
          if (vm.expanded && vm.params.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(space.sm, space.zero, space.sm, space.sm),
              child: Wrap(
                spacing: space.md,
                runSpacing: space.sm,
                children: <Widget>[
                  for (final EffectParamVm param in vm.params)
                    SizedBox(
                      width: tokens.size.effectParamCellWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ObKnob(
                            value: param.unit,
                            label: param.name.toUpperCase(),
                            onChanged: onParamChanged == null
                                ? null
                                : (double unit) =>
                                      onParamChanged!(vm.id, param.id, param.fromUnit(unit)),
                          ),
                          SizedBox(height: space.xxs),
                          Text(
                            param.display,
                            style: tokens.type.microCaps,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The bypass switch. Its own control rather than [ObToggleChip], which paints
/// the mixer's M and S and is shaped around those two letters — and bypass is
/// neither a mute nor a solo: it takes the effect out of the path, and the
/// signal keeps flowing.
class _BypassChip extends StatelessWidget {
  const _BypassChip({required this.bypassed, required this.onTap});

  final bool bypassed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bypassed ? color.warning : color.surfaceRaised,
          borderRadius: BorderRadius.all(tokens.radius.sm),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xs, vertical: tokens.spacing.xxs),
          child: Text(
            'BYP',
            style: tokens.type.microCaps.copyWith(
              color: bypassed ? color.surfaceSunken : color.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: tokens.size.effectSlotButtonSize,
        height: tokens.size.effectSlotButtonSize,
        child: Center(
          child: Text(
            label,
            style: enabled ? tokens.type.microCaps : tokens.type.microCaps.copyWith(color: tokens.color.textMuted),
          ),
        ),
      ),
    );
  }
}
