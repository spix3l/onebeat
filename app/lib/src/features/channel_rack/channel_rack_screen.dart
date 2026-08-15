// ChannelRackScreen — the channel rack workspace surface (UI-C-02, UI-D-02).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import 'channel_inspector.dart';
import 'channel_rack_screen_vm.dart';
import 'rack_row.dart';
import 'rack_toolbar.dart';

class ChannelRackScreen extends StatelessWidget {
  const ChannelRackScreen({
    required this.vm,
    this.onSelectPattern,
    this.onSelectRow,
    this.onTogglePower,
    this.onStepTap,
    this.onVolChanged,
    this.onPanChanged,
    this.onRouteTap,
    this.onAddChannel,
    this.onDoubleTap,
    this.onRowSecondaryTapDown,
    this.onDropInstrument,
    this.onAddInstrument,
    this.onReorderRow,
    this.onSearchTap,
    this.onChannelType,
    this.onGroup,
    this.onSnap,
    this.onSteps,
    this.onMixerTap,
    this.onAutomationTap,
    this.onInspectorVol,
    this.onInspectorPan,
    this.onInspectorMute,
    this.onInspectorSolo,
    this.onInspectorFxTap,
    this.onInspectorAddFx,
    this.onInspectorRouteTap,
    this.onInspectorKeyPress,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.onPointerUpStep,
    this.onPointerCancelStep,
    super.key,
  });

  final ChannelRackScreenVm vm;
  final ValueChanged<String>? onSelectPattern;
  final ValueChanged<int>? onSelectRow;
  final ValueChanged<int>? onTogglePower;
  final void Function(int rowIndex, int stepIndex)? onStepTap;
  final void Function(int rowIndex, double value)? onVolChanged;
  final void Function(int rowIndex, double value)? onPanChanged;
  final ValueChanged<int>? onRouteTap;
  final VoidCallback? onAddChannel;
  final VoidCallback? onDoubleTap;
  final void Function(int rowIndex, TapDownDetails details)?
      onRowSecondaryTapDown;
  final void Function(int rowIndex, Object data)? onDropInstrument;
  final void Function(Object data)? onAddInstrument;
  final void Function(int oldIndex, int newIndex)? onReorderRow;
  final VoidCallback? onSearchTap;
  final ValueChanged<String>? onChannelType;
  final ValueChanged<String>? onGroup;
  final ValueChanged<String>? onSnap;
  final ValueChanged<int>? onSteps;
  final VoidCallback? onMixerTap;
  final VoidCallback? onAutomationTap;
  final ValueChanged<double>? onInspectorVol;
  final ValueChanged<double>? onInspectorPan;
  final VoidCallback? onInspectorMute;
  final VoidCallback? onInspectorSolo;
  final ValueChanged<int>? onInspectorFxTap;
  final VoidCallback? onInspectorAddFx;
  final VoidCallback? onInspectorRouteTap;
  final ValueChanged<int>? onInspectorKeyPress;
  final void Function(PointerDownEvent event, int rowIndex, int stepIndex)?
      onPointerDownStep;
  final void Function(PointerMoveEvent event, int rowIndex, int stepIndex)?
      onPointerMoveStep;
  final VoidCallback? onPointerUpStep;
  final VoidCallback? onPointerCancelStep;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return ColoredBox(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ChannelRackHeader(
            title: vm.title,
            patterns: vm.patterns,
            hint: vm.hint,
            onSelectPattern: onSelectPattern,
            onAddChannel: onAddChannel,
            onSearchTap: onSearchTap,
          ),
          ObRackToolbar(
            vm: vm.toolbar,
            onChannelType: onChannelType,
            onGroup: onGroup,
            onSnap: onSnap,
            onSteps: onSteps,
            onMixerTap: onMixerTap,
            onAddChannel: onAddChannel,
            onAutomationTap: onAutomationTap,
          ),
          ObRackHeader(stepCount: vm.stepCount),
          Expanded(
            child: _RackRowsScrollArea(
              rows: vm.rows,
              playingStep: vm.playingStep,
              playingTick: vm.playingTick,
              footerLead: vm.footerLead,
              footerAction: vm.footerAction,
              footerTrail: vm.footerTrail,
              footerShortcut: vm.footerShortcut,
              onSelectRow: onSelectRow,
              onTogglePower: onTogglePower,
              onStepTap: onStepTap,
              onVolChanged: onVolChanged,
              onPanChanged: onPanChanged,
              onRouteTap: onRouteTap,
              onAddChannel: onAddChannel,
              onDoubleTap: onDoubleTap,
              onRowSecondaryTapDown: onRowSecondaryTapDown,
              onDropInstrument: onDropInstrument,
              onAddInstrument: onAddInstrument,
              onReorderRow: onReorderRow,
              onPointerDownStep: onPointerDownStep,
              onPointerMoveStep: onPointerMoveStep,
              onPointerUpStep: onPointerUpStep,
              onPointerCancelStep: onPointerCancelStep,
            ),
          ),
          if (vm.inspector != null)
            ObChannelInspector(
              vm: vm.inspector!,
              onVol: onInspectorVol,
              onPan: onInspectorPan,
              onMute: onInspectorMute,
              onSolo: onInspectorSolo,
              onFxTap: onInspectorFxTap,
              onAddFx: onInspectorAddFx,
              onRouteTap: onInspectorRouteTap,
              onKeyPress: onInspectorKeyPress,
            ),
        ],
      ),
    );
  }
}

class _ChannelRackHeader extends StatelessWidget {
  const _ChannelRackHeader({
    required this.title,
    required this.patterns,
    required this.hint,
    this.onSelectPattern,
    this.onAddChannel,
    this.onSearchTap,
  });

  final String title;
  final List<PatternTabVm> patterns;
  final String hint;
  final ValueChanged<String>? onSelectPattern;
  final VoidCallback? onAddChannel;
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.rackHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: color.surfacePanel,
        border: Border(
          bottom: BorderSide(
            color: color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(title, style: tokens.type.title),
          SizedBox(width: tokens.spacing.lg),
          for (final PatternTabVm pattern in patterns) ...<Widget>[
            _PatternTab(
              tab: pattern,
              onTap: onSelectPattern == null
                  ? null
                  : () => onSelectPattern!(pattern.id),
            ),
            SizedBox(width: tokens.spacing.xs),
          ],
          const Spacer(),
          Text(hint, style: tokens.type.rackCaption),
          SizedBox(width: tokens.spacing.md),
          _AddChannelAccentButton(onTap: onAddChannel),
          SizedBox(width: tokens.spacing.sm),
          _RoundSearchButton(onTap: onSearchTap),
        ],
      ),
    );
  }
}

class _PatternTab extends StatelessWidget {
  const _PatternTab({
    required this.tab,
    this.onTap,
  });

  final PatternTabVm tab;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: tab.selected ? color.accent : color.surfaceWell,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: tab.selected ? color.accentBright : color.line,
            width: tokens.border.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              tab.name,
              style: tokens.type.body.copyWith(
                color: tab.selected ? color.textPrimary : color.textSecondary,
                fontWeight: tab.selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (tab.count != null) ...<Widget>[
              SizedBox(width: tokens.spacing.xs),
              Container(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacing.xxs),
                decoration: BoxDecoration(
                  color: tab.selected ? color.accentBright : color.surfaceRaised,
                  borderRadius: tokens.radius.controlBorder,
                ),
                child: Text(
                  '${tab.count}',
                  style: tokens.type.numericSmall.copyWith(
                    color: tab.selected ? color.textPrimary : color.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddChannelAccentButton extends StatelessWidget {
  const _AddChannelAccentButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.accent,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: color.accentBright,
            width: tokens.border.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '+ Add channel',
              style: tokens.type.body.copyWith(
                color: color.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundSearchButton extends StatelessWidget {
  const _RoundSearchButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: tokens.size.rackPowerSize,
        height: tokens.size.rackPowerSize,
        decoration: BoxDecoration(
          color: color.surfaceWell,
          shape: BoxShape.circle,
          border: Border.all(
            color: color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
        child: Center(
          child: Text('⌕', style: tokens.type.microCaps),
        ),
      ),
    );
  }
}

class _RackRowsScrollArea extends StatelessWidget {
  const _RackRowsScrollArea({
    required this.rows,
    required this.playingStep,
    required this.playingTick,
    required this.footerLead,
    required this.footerAction,
    required this.footerTrail,
    required this.footerShortcut,
    this.onSelectRow,
    this.onTogglePower,
    this.onStepTap,
    this.onVolChanged,
    this.onPanChanged,
    this.onRouteTap,
    this.onAddChannel,
    this.onDoubleTap,
    this.onRowSecondaryTapDown,
    this.onDropInstrument,
    this.onAddInstrument,
    this.onReorderRow,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.onPointerUpStep,
    this.onPointerCancelStep,
  });

  final List<RackRowVm> rows;
  final int? playingStep;
  final int? playingTick;
  final String footerLead;
  final String footerAction;
  final String footerTrail;
  final String footerShortcut;
  final ValueChanged<int>? onSelectRow;
  final ValueChanged<int>? onTogglePower;
  final void Function(int rowIndex, int stepIndex)? onStepTap;
  final void Function(int rowIndex, double value)? onVolChanged;
  final void Function(int rowIndex, double value)? onPanChanged;
  final ValueChanged<int>? onRouteTap;
  final VoidCallback? onAddChannel;
  final VoidCallback? onDoubleTap;
  final void Function(int rowIndex, TapDownDetails details)?
      onRowSecondaryTapDown;
  final void Function(int rowIndex, Object data)? onDropInstrument;
  final void Function(Object data)? onAddInstrument;
  final void Function(int oldIndex, int newIndex)? onReorderRow;
  final void Function(PointerDownEvent event, int rowIndex, int stepIndex)?
      onPointerDownStep;
  final void Function(PointerMoveEvent event, int rowIndex, int stepIndex)?
      onPointerMoveStep;
  final VoidCallback? onPointerUpStep;
  final VoidCallback? onPointerCancelStep;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final void Function(Object)? add = onAddInstrument;

    return DragTarget<Object>(
      onAcceptWithDetails:
          add == null
              ? null
              : (DragTargetDetails<Object> details) => add(details.data),
      builder: (
        BuildContext context,
        List<Object?> candidates,
        List<Object?> rejected,
      ) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The rows own the scroll. The footer stays attached to the bottom
            // of the rack, matching the reference instead of travelling away
            // after the last channel.
            // A reorderable list rather than a plain Column: the lanes are the
            // channel order, and the order is data the user edits. This list
            // adds no drag handles of its own — the name block opts in via
            // ObRackRow.reorderIndex — so dragging across the step cells still
            // paints steps.
            Expanded(
              child: ReorderableList(
                itemCount: rows.length,
                // onReorderItem, not onReorder: it hands back a newIndex that
                // already accounts for the dragged row being lifted out.
                onReorderItem: onReorderRow ?? (int _, int _) {},
                itemBuilder: (BuildContext context, int i) => _RackRowItem(
                  key: ValueKey<String>('rack-row-${rows[i].name}-$i'),
                  index: i,
                  row: rows[i],
                  reorderable: onReorderRow != null,
                  playingStep: playingStep,
                  playingTick: playingTick,
                  onSelectRow: onSelectRow,
                  onTogglePower: onTogglePower,
                  onStepTap: onStepTap,
                  onVolChanged: onVolChanged,
                  onPanChanged: onPanChanged,
                  onRouteTap: onRouteTap,
                  onSecondaryTapDown: onRowSecondaryTapDown,
                  onDropInstrument: onDropInstrument,
                  onPointerDownStep: onPointerDownStep,
                  onPointerMoveStep: onPointerMoveStep,
                  onPointerUpStep: onPointerUpStep,
                  onPointerCancelStep: onPointerCancelStep,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
              child: ObRackFooter(
                lead: footerLead,
                action: footerAction,
                trail: footerTrail,
                shortcut: footerShortcut,
                onAddChannel: onAddChannel,
                onDoubleTap: onDoubleTap,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RackRowItem extends StatelessWidget {
  const _RackRowItem({
    required this.index,
    required this.row,
    required this.playingStep,
    required this.playingTick,
    this.reorderable = false,
    super.key,
    this.onSelectRow,
    this.onTogglePower,
    this.onStepTap,
    this.onVolChanged,
    this.onPanChanged,
    this.onRouteTap,
    this.onSecondaryTapDown,
    this.onDropInstrument,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.onPointerUpStep,
    this.onPointerCancelStep,
  });

  final int index;
  final RackRowVm row;
  final bool reorderable;
  final int? playingStep;
  final int? playingTick;
  final ValueChanged<int>? onSelectRow;
  final ValueChanged<int>? onTogglePower;
  final void Function(int rowIndex, int stepIndex)? onStepTap;
  final void Function(int rowIndex, double value)? onVolChanged;
  final void Function(int rowIndex, double value)? onPanChanged;
  final ValueChanged<int>? onRouteTap;
  final void Function(int rowIndex, TapDownDetails details)?
      onSecondaryTapDown;
  final void Function(int rowIndex, Object data)? onDropInstrument;
  final void Function(PointerDownEvent event, int rowIndex, int stepIndex)?
      onPointerDownStep;
  final void Function(PointerMoveEvent event, int rowIndex, int stepIndex)?
      onPointerMoveStep;
  final VoidCallback? onPointerUpStep;
  final VoidCallback? onPointerCancelStep;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final void Function(int, Object)? drop = onDropInstrument;

    return DragTarget<Object>(
      onAcceptWithDetails:
          drop == null
              ? null
              : (DragTargetDetails<Object> details) =>
                    drop(index, details.data),
      builder: (BuildContext context, List<Object?> candidates, List<Object?> rejected) {
        final bool hovering = candidates.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: hovering ? tokens.color.accent : tokens.color.none,
              width: hovering ? tokens.border.emphasis : 0,
            ),
          ),
          child: Listener(
            onPointerUp:
                onPointerUpStep == null ? null : (_) => onPointerUpStep!(),
            onPointerCancel:
                onPointerCancelStep == null
                    ? null
                    : (_) => onPointerCancelStep!(),
            child: ObRackRow(
              vm: row,
              reorderIndex: reorderable ? index : null,
              playingStep: playingStep,
              playingTick: playingTick,
              onTap: onSelectRow == null ? null : () => onSelectRow!(index),
              onSecondaryTapDown: onSecondaryTapDown == null
                  ? null
                  : (TapDownDetails details) =>
                        onSecondaryTapDown!(index, details),
              onPower: onTogglePower == null
                  ? null
                  : () => onTogglePower!(index),
              onStepTap: onStepTap == null
                  ? null
                  : (int step) => onStepTap!(index, step),
              onPointerDownStep: onPointerDownStep == null
                  ? null
                  : (PointerDownEvent event, int step) =>
                        onPointerDownStep!(event, index, step),
              onPointerMoveStep: onPointerMoveStep == null
                  ? null
                  : (PointerMoveEvent event, int step) =>
                        onPointerMoveStep!(event, index, step),
              onVol: onVolChanged == null
                  ? null
                  : (double val) => onVolChanged!(index, val),
              onPan: onPanChanged == null
                  ? null
                  : (double val) => onPanChanged!(index, val),
              onRouteTap: onRouteTap == null
                  ? null
                  : () => onRouteTap!(index),
            ),
          ),
        );
      },
    );
  }
}
