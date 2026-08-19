// ChannelRackScreen — the channel rack workspace surface (UI-C-02, UI-D-02).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/action_registry.dart';
import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/dropdown.dart';
import '../../ui_kit/empty_state.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/prose.dart';
import 'channel_inspector.dart';
import 'channel_rack_screen_vm.dart';
import 'rack_row.dart';
import 'rack_toolbar.dart';

class ChannelRackScreen extends StatelessWidget {
  const ChannelRackScreen({
    required this.vm,
    this.onSelectPattern,
    this.onPatternSecondaryTapDown,
    this.onSelectRow,
    this.onRowDoubleTap,
    this.onTogglePower,
    this.onStepTap,
    this.onVolChanged,
    this.onPanChanged,
    this.onRouteTap,
    this.onAddChannel,
    this.onCreatePattern,
    this.onRowSecondaryTapDown,
    this.onDropInstrument,
    this.onAddInstrument,
    this.onReorderRow,
    this.onChannelType,
    this.onGroup,
    this.onSnap,
    this.onSteps,
    this.onSwing,
    this.onVelocityDelta,
    this.onMixerTap,
    this.onAutomationTap,
    this.onDismissSharedPatternNotice,
    this.onInspectorVol,
    this.onInspectorPan,
    this.onInspectorMute,
    this.onInspectorSolo,
    this.onInspectorOpenPlugin,
    this.onInspectorOpenSampler,
    this.onInspectorFxTap,
    this.onInspectorAddFx,
    this.onInspectorRouteTap,
    this.onInspectorKeyPress,
    this.onInspectorGrid,
    this.onPointerDownStep,
    this.onPointerMoveStep,
    this.onPointerUpStep,
    this.onPointerCancelStep,
    super.key,
  });

  final ChannelRackScreenVm vm;
  final ValueChanged<String>? onSelectPattern;
  final void Function(String patternId, TapDownDetails details)? onPatternSecondaryTapDown;
  final ValueChanged<int>? onSelectRow;

  /// Fired for a lane that hosts a plug-in when it is double-clicked, so the
  /// shell can open the plug-in window. The index is the lane's row index.
  final ValueChanged<int>? onRowDoubleTap;
  final ValueChanged<int>? onTogglePower;
  final void Function(int rowIndex, int stepIndex)? onStepTap;
  final void Function(int rowIndex, double value)? onVolChanged;
  final void Function(int rowIndex, double value)? onPanChanged;
  final ValueChanged<int>? onRouteTap;
  final VoidCallback? onAddChannel;
  final VoidCallback? onCreatePattern;
  final void Function(int rowIndex, TapDownDetails details)? onRowSecondaryTapDown;
  final void Function(int rowIndex, Object data)? onDropInstrument;
  final void Function(Object data)? onAddInstrument;
  final void Function(int oldIndex, int newIndex)? onReorderRow;
  final ValueChanged<String>? onChannelType;
  final ValueChanged<String>? onGroup;
  final ValueChanged<String>? onSnap;
  final ValueChanged<int>? onSteps;
  final ValueChanged<double>? onSwing;
  final ValueChanged<int>? onVelocityDelta;
  final VoidCallback? onMixerTap;
  final VoidCallback? onAutomationTap;
  final VoidCallback? onDismissSharedPatternNotice;
  final ValueChanged<double>? onInspectorVol;
  final ValueChanged<double>? onInspectorPan;
  final VoidCallback? onInspectorMute;
  final VoidCallback? onInspectorSolo;

  /// Opens the selected channel's plug-in window; only wired for channels
  /// that host a plug-in.
  final VoidCallback? onInspectorOpenPlugin;
  final VoidCallback? onInspectorOpenSampler;
  final ValueChanged<int>? onInspectorFxTap;
  final VoidCallback? onInspectorAddFx;
  final VoidCallback? onInspectorRouteTap;
  final ValueChanged<int>? onInspectorKeyPress;

  /// Sets the selected channel's step divisor.
  final ValueChanged<String>? onInspectorGrid;
  final void Function(PointerDownEvent event, int rowIndex, int stepIndex)? onPointerDownStep;
  final void Function(PointerMoveEvent event, int rowIndex, int stepIndex)? onPointerMoveStep;
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
            onSelectPattern: onSelectPattern,
            onPatternSecondaryTapDown: onPatternSecondaryTapDown,
            onAddChannel: onAddChannel,
            onCreatePattern: onCreatePattern,
          ),
          ObRackToolbar(
            vm: vm.toolbar,
            // The rack keeps only controls that change the pattern: step count
            // and the visible Add channel action in the header.
            onGroup: onGroup,
            onSnap: onSnap,
            onSteps: onSteps,
            onSwing: onSwing,
            onVelocityDelta: onVelocityDelta,
          ),
          if (vm.sharedPatternNotice != null)
            _SharedPatternNotice(message: vm.sharedPatternNotice!.message, onDismiss: onDismissSharedPatternNotice),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final OneBeatTokens currentTokens = OneBeatTheme.of(context);
                final double chrome = _rackChromeWidth(currentTokens);
                // Republished for the grid below, so the number strip, the
                // cells, their painter and their hit-test all read one size.
                final OneBeatTokens rackTokens = currentTokens.withSize(
                  fitRackSteps(currentTokens.size, vm.stepCount, constraints.maxWidth - chrome),
                );
                // One width for every lane. The pattern's own grid sets it;
                // lanes on a finer divisor fit their extra cells inside it
                // rather than widening the rack, so the bar ends in the same
                // place on every row and nothing runs off the window.
                final double gridWidth = rackGridWidth(rackTokens.size, vm.stepCount);
                final double contentWidth = chrome + gridWidth;
                return OneBeatTheme(
                  tokens: rackTokens,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(constraints.maxWidth, contentWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ObRackHeader(stepCount: vm.stepCount),
                          Expanded(
                            child: _RackRowsScrollArea(
                              rows: vm.rows,
                              playingStep: vm.playingStep,
                              playingTick: vm.playingTick,
                              onSelectRow: onSelectRow,
                              onRowDoubleTap: onRowDoubleTap,
                              onTogglePower: onTogglePower,
                              onStepTap: onStepTap,
                              onVolChanged: onVolChanged,
                              onPanChanged: onPanChanged,
                              onRouteTap: onRouteTap,
                              gridWidth: gridWidth,
                              gridStepCount: vm.stepCount,
                              stepTicks: vm.stepTicks,
                              onAddChannel: onAddChannel,
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
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (vm.inspector != null)
            ObChannelInspector(
              vm: vm.inspector!,
              onVol: onInspectorVol,
              onPan: onInspectorPan,
              onMute: onInspectorMute,
              onSolo: onInspectorSolo,
              onOpenPlugin: onInspectorOpenPlugin,
              onOpenSampler: onInspectorOpenSampler,
              onFxTap: onInspectorFxTap,
              onAddFx: onInspectorAddFx,
              onRouteTap: onInspectorRouteTap,
              onKeyPress: onInspectorKeyPress,
              onGrid: onInspectorGrid,
            ),
        ],
      ),
    );
  }
}

/// Everything in a lane that is not the step grid: the power well and identity
/// block on the left, the knobs and routing chip on the right.
///
/// Fixed, whatever the step count — which is what makes it the budget the grid
/// has to fit inside.
double _rackChromeWidth(OneBeatTokens tokens) {
  final SizeTokens size = tokens.size;
  return tokens.spacing.md +
      size.rackSelectedEdgeWidth +
      size.rackPowerSize +
      tokens.spacing.sm +
      size.rackColorChipSize +
      tokens.spacing.md +
      size.rackNameWidth +
      tokens.spacing.md +
      size.knobSmall +
      tokens.spacing.sm +
      size.knobSmall +
      tokens.spacing.sm +
      size.rackRouteChipWidth +
      tokens.spacing.md;
}

class _SharedPatternNotice extends StatelessWidget {
  const _SharedPatternNotice({required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.microFieldHeight + tokens.spacing.xs,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      color: tokens.color.accentWash,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis, style: tokens.type.bodySecondary),
          ),
          if (onDismiss != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
                child: Text('Dismiss', style: tokens.type.microCaps),
              ),
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
    this.onSelectPattern,
    this.onPatternSecondaryTapDown,
    this.onAddChannel,
    this.onCreatePattern,
  });

  final String title;
  final List<PatternTabVm> patterns;
  final ValueChanged<String>? onSelectPattern;
  final void Function(String patternId, TapDownDetails details)? onPatternSecondaryTapDown;
  final VoidCallback? onAddChannel;
  final VoidCallback? onCreatePattern;
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
          bottom: BorderSide(color: color.line, width: tokens.border.hairline),
        ),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < tokens.size.rackCompactBreakpoint;
          final Widget row = Row(
            children: <Widget>[
              Text(title, style: tokens.type.title),
              if (compact) SizedBox(width: tokens.spacing.lg) else const Spacer(),
              if (patterns.isNotEmpty) ...<Widget>[
                _PatternSelect(
                  patterns: patterns,
                  onSelect: onSelectPattern,
                  onSecondaryTapDown: onPatternSecondaryTapDown,
                ),
                SizedBox(width: tokens.spacing.sm),
              ],
              _NewPatternButton(onTap: onCreatePattern),
              SizedBox(width: tokens.spacing.xs),
              _AddChannelAccentButton(onTap: onAddChannel),
            ],
          );
          return compact
              ? ClipRect(
                  child: OverflowBox(alignment: Alignment.centerLeft, maxWidth: double.infinity, child: row),
                )
              : row;
        },
      ),
    );
  }
}

class _NewPatternButton extends StatelessWidget {
  const _NewPatternButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      key: actionKey('pattern.create'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md, vertical: tokens.spacing.xs),
        decoration: BoxDecoration(
          color: color.surfaceWell,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(color: color.line, width: tokens.border.hairline),
        ),
        child: Text('+ New pattern  \u2318N', style: tokens.type.body.copyWith(color: color.textSecondary)),
      ),
    );
  }
}

/// The header's pattern select.
///
/// This was a strip of one chip per pattern. A project with more than a handful
/// of patterns — or with patterns named after the samples they hold, which is
/// what happens the moment a user drags a folder in — overflowed the header on
/// any window, so the control that says *which pattern you are editing* was the
/// first thing to fall off the screen. A select holds one row's width whatever
/// the project does.
///
/// Right-click still opens the pattern menu (rename, duplicate, recolor,
/// delete), now targeting the pattern in the field — the one the menu's actions
/// are about anyway.
class _PatternSelect extends StatelessWidget {
  const _PatternSelect({required this.patterns, this.onSelect, this.onSecondaryTapDown});

  final List<PatternTabVm> patterns;
  final ValueChanged<String>? onSelect;
  final void Function(String patternId, TapDownDetails details)? onSecondaryTapDown;

  /// A pattern's row in the menu. The group is a prefix because that is how the
  /// tabs read it, and it is what disambiguates two `Verse` patterns in
  /// different groups.
  static String _label(PatternTabVm pattern) =>
      pattern.group.isEmpty ? pattern.name : '${pattern.group} · ${pattern.name}';

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PatternTabVm current = patterns.firstWhere(
      (PatternTabVm pattern) => pattern.selected,
      orElse: () => patterns.first,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: onSecondaryTapDown == null
          ? null
          : (TapDownDetails details) => onSecondaryTapDown!(current.id, details),
      child: ObDropdown(
        label: 'Pattern',
        value: _label(current),
        items: <String>[for (final PatternTabVm pattern in patterns) _label(pattern)],
        width: tokens.size.rackPatternFieldWidth,
        onSelected: onSelect == null
            ? null
            : (String label) {
                // Labels are what the select speaks; the store speaks ids. Two
                // patterns can carry the same name, and the first match is the
                // only sane reading of a click on a row that says that name.
                for (final PatternTabVm pattern in patterns) {
                  if (_label(pattern) == label) {
                    onSelect!(pattern.id);
                    return;
                  }
                }
              },
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
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md, vertical: tokens.spacing.xs),
        decoration: BoxDecoration(
          color: color.accent,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(color: color.accentBright, width: tokens.border.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '+ Add channel',
              style: tokens.type.body.copyWith(color: color.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
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
    this.onSelectRow,
    this.onRowDoubleTap,
    this.onTogglePower,
    this.onStepTap,
    this.onVolChanged,
    this.onPanChanged,
    this.onRouteTap,
    required this.gridWidth,
    required this.gridStepCount,
    required this.stepTicks,
    this.onAddChannel,
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
  final ValueChanged<int>? onSelectRow;
  final ValueChanged<int>? onRowDoubleTap;
  final ValueChanged<int>? onTogglePower;
  final void Function(int rowIndex, int stepIndex)? onStepTap;
  final void Function(int rowIndex, double value)? onVolChanged;
  final void Function(int rowIndex, double value)? onPanChanged;
  final ValueChanged<int>? onRouteTap;

  /// The width every lane's grid occupies — see [ObRackRow.gridWidth].
  final double gridWidth;

  /// The rack's shared time base — see [ObRackRow.gridStepCount].
  final int gridStepCount;
  final int stepTicks;

  final VoidCallback? onAddChannel;
  final void Function(int rowIndex, TapDownDetails details)? onRowSecondaryTapDown;
  final void Function(int rowIndex, Object data)? onDropInstrument;
  final void Function(Object data)? onAddInstrument;
  final void Function(int oldIndex, int newIndex)? onReorderRow;
  final void Function(PointerDownEvent event, int rowIndex, int stepIndex)? onPointerDownStep;
  final void Function(PointerMoveEvent event, int rowIndex, int stepIndex)? onPointerMoveStep;
  final VoidCallback? onPointerUpStep;
  final VoidCallback? onPointerCancelStep;

  static const ObEmptyStateVm _emptyVm = ObEmptyStateVm(
    icon: ObKitGlyphKind.note,
    heading: 'Add your first instrument',
    body: <ObProseRun>[
      ObProseRun('Drop a sample from the browser, or add an empty channel to start building Pattern 1.'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final void Function(Object)? add = onAddInstrument;

    return DragTarget<Object>(
      onAcceptWithDetails: add == null ? null : (DragTargetDetails<Object> details) => add(details.data),
      builder: (BuildContext context, List<Object?> candidates, List<Object?> rejected) {
        if (rows.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: ObEmptyState(
                vm: _emptyVm,
                actions: <Widget>[
                  ObButton(
                    label: 'Add channel',
                    icon: ObKitGlyphKind.plus,
                    tone: ObButtonTone.primary,
                    onTap: onAddChannel,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
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
                  onRowDoubleTap: onRowDoubleTap,
                  onTogglePower: onTogglePower,
                  onStepTap: onStepTap,
                  onVolChanged: onVolChanged,
                  onPanChanged: onPanChanged,
                  onRouteTap: onRouteTap,
                  gridWidth: gridWidth,
                  gridStepCount: gridStepCount,
                  stepTicks: stepTicks,
                  onSecondaryTapDown: onRowSecondaryTapDown,
                  onDropInstrument: onDropInstrument,
                  onPointerDownStep: onPointerDownStep,
                  onPointerMoveStep: onPointerMoveStep,
                  onPointerUpStep: onPointerUpStep,
                  onPointerCancelStep: onPointerCancelStep,
                ),
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
    this.onRowDoubleTap,
    this.onTogglePower,
    this.onStepTap,
    this.onVolChanged,
    this.onPanChanged,
    this.onRouteTap,
    required this.gridWidth,
    required this.gridStepCount,
    required this.stepTicks,
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
  final ValueChanged<int>? onRowDoubleTap;
  final ValueChanged<int>? onTogglePower;
  final void Function(int rowIndex, int stepIndex)? onStepTap;
  final void Function(int rowIndex, double value)? onVolChanged;
  final void Function(int rowIndex, double value)? onPanChanged;
  final ValueChanged<int>? onRouteTap;
  final double gridWidth;
  final int gridStepCount;
  final int stepTicks;
  final void Function(int rowIndex, TapDownDetails details)? onSecondaryTapDown;
  final void Function(int rowIndex, Object data)? onDropInstrument;
  final void Function(PointerDownEvent event, int rowIndex, int stepIndex)? onPointerDownStep;
  final void Function(PointerMoveEvent event, int rowIndex, int stepIndex)? onPointerMoveStep;
  final VoidCallback? onPointerUpStep;
  final VoidCallback? onPointerCancelStep;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final void Function(int, Object)? drop = onDropInstrument;

    return DragTarget<Object>(
      onAcceptWithDetails: drop == null ? null : (DragTargetDetails<Object> details) => drop(index, details.data),
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
            onPointerUp: onPointerUpStep == null ? null : (_) => onPointerUpStep!(),
            onPointerCancel: onPointerCancelStep == null ? null : (_) => onPointerCancelStep!(),
            child: ObRackRow(
              vm: row,
              reorderIndex: reorderable ? index : null,
              playingStep: playingStep,
              playingTick: playingTick,
              // Selection is driven by the row's raw pointer-down handler so
              // it is immediate even when a double-click editor is available.
              onTap: null,
              onPointerDown: onSelectRow == null
                  ? null
                  : (PointerDownEvent event) {
                      if (event.buttons == 1) onSelectRow!(index);
                    },
              // Only hosted plug-in lanes use a double-tap recognizer.
              onDoubleTap: row.hostsPlugin && onRowDoubleTap != null ? () => onRowDoubleTap!(index) : null,
              onSecondaryTapDown: onSecondaryTapDown == null
                  ? null
                  : (TapDownDetails details) => onSecondaryTapDown!(index, details),
              onPower: onTogglePower == null ? null : () => onTogglePower!(index),
              onStepTap: onStepTap == null ? null : (int step) => onStepTap!(index, step),
              onPointerDownStep: onPointerDownStep == null
                  ? null
                  : (PointerDownEvent event, int step) => onPointerDownStep!(event, index, step),
              onPointerMoveStep: onPointerMoveStep == null
                  ? null
                  : (PointerMoveEvent event, int step) => onPointerMoveStep!(event, index, step),
              onVol: onVolChanged == null ? null : (double val) => onVolChanged!(index, val),
              onPan: onPanChanged == null ? null : (double val) => onPanChanged!(index, val),
              onRouteTap: onRouteTap == null ? null : () => onRouteTap!(index),
              gridWidth: gridWidth,
              gridStepCount: gridStepCount,
              stepTicks: stepTicks,
            ),
          ),
        );
      },
    );
  }
}
