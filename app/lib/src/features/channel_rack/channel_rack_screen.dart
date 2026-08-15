// ChannelRackScreen — the channel rack workspace surface (UI-C-02, UI-D-02).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/action_registry.dart';
import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
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
    this.onMixerTap,
    this.onAutomationTap,
    this.onInspectorVol,
    this.onInspectorPan,
    this.onInspectorMute,
    this.onInspectorSolo,
    this.onInspectorOpenPlugin,
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
  final VoidCallback? onMixerTap;
  final VoidCallback? onAutomationTap;
  final ValueChanged<double>? onInspectorVol;
  final ValueChanged<double>? onInspectorPan;
  final VoidCallback? onInspectorMute;
  final VoidCallback? onInspectorSolo;

  /// Opens the selected channel's plug-in window; only wired for channels
  /// that host a plug-in.
  final VoidCallback? onInspectorOpenPlugin;
  final ValueChanged<int>? onInspectorFxTap;
  final VoidCallback? onInspectorAddFx;
  final VoidCallback? onInspectorRouteTap;
  final ValueChanged<int>? onInspectorKeyPress;
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
            onSteps: onSteps,
          ),
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
                final double contentWidth = chrome + rackGridWidth(rackTokens.size, vm.stepCount);
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

/// The smallest step cell the rack will draw.
///
/// Below this a cell stops being a target you can hit and starts being a
/// texture, and scrolling is the better answer.
const double _minRackStepCell = 16;

/// Step sizes that fit [stepCount] cells into [available], never larger than
/// the design's own.
///
/// A 32-step pattern at the full 30px pitch is wider than most windows, and the
/// horizontal scroll that answered it hid half the bar — you cannot write a
/// rhythm you have to scroll to see. So the grid gives up pitch before it gives
/// up being whole, down to [_minRackStepCell]; past that the scroll returns.
SizeTokens fitRackSteps(SizeTokens base, int stepCount, double available) {
  if (stepCount <= 0 || available <= 0) return base;
  if (rackGridWidth(base, stepCount) <= available) return base;
  // Walk down a pixel at a time and take the first size that fits. A whole
  // number of pixels per cell is what keeps the cells crisp and the gaps even;
  // solving for a fractional cell and rounding afterwards does neither.
  for (double cell = base.rackStepCell - 1; cell >= _minRackStepCell; cell--) {
    final SizeTokens candidate = _RackStepSizes(base, cell);
    if (rackGridWidth(candidate, stepCount) <= available) return candidate;
  }
  return _RackStepSizes(base, _minRackStepCell);
}

/// [SizeTokens] with the step grid rescaled — the gaps follow the cell, so the
/// beat grouping stays legible at every size.
class _RackStepSizes extends SizeTokens {
  const _RackStepSizes(this._base, this._cell);

  final SizeTokens _base;
  final double _cell;

  double get _scale => _cell / _base.rackStepCell;

  @override
  double get rackStepCell => _cell;

  @override
  double get rackStepGap {
    final double scaled = (_base.rackStepGap * _scale).floorToDouble();
    return scaled < 2 ? 2 : scaled;
  }

  @override
  double get rackStepGroupGap {
    final double scaled = (_base.rackStepGroupGap * _scale).floorToDouble();
    // Always visibly wider than the plain gap: the group break is the only
    // thing telling you where the beat is.
    final double floor = rackStepGap + 2;
    return scaled < floor ? floor : scaled;
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
        border: Border(bottom: BorderSide(color: color.line, width: tokens.border.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Text(title, style: tokens.type.title),
          SizedBox(width: tokens.spacing.lg),
          for (final PatternTabVm pattern in patterns) ...<Widget>[
            _PatternTab(
              tab: pattern,
              onTap: onSelectPattern == null ? null : () => onSelectPattern!(pattern.id),
              onSecondaryTapDown:
                  onPatternSecondaryTapDown == null
                      ? null
                      : (TapDownDetails details) => onPatternSecondaryTapDown!(pattern.id, details),
            ),
            SizedBox(width: tokens.spacing.xs),
          ],
          const Spacer(),
          _NewPatternButton(onTap: onCreatePattern),
          SizedBox(width: tokens.spacing.xs),
          _AddChannelAccentButton(onTap: onAddChannel),
        ],
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

class _PatternTab extends StatelessWidget {
  const _PatternTab({required this.tab, this.onTap, this.onSecondaryTapDown});

  final PatternTabVm tab;
  final VoidCallback? onTap;
  final ValueChanged<TapDownDetails>? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm, vertical: tokens.spacing.xs),
        decoration: BoxDecoration(
          color: tab.selected ? color.accent : color.surfaceWell,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(color: tab.selected ? color.accentBright : color.line, width: tokens.border.hairline),
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
                  style: tokens.type.numericSmall.copyWith(color: tab.selected ? color.textPrimary : color.textMuted),
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
                itemBuilder:
                    (BuildContext context, int i) => _RackRowItem(
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
              onTap:
                  onSelectRow == null
                      ? null
                      : () {
                        onSelectRow!(index);
                        // Samples have a built-in editor rather than a
                        // hosted instance, so opening them on the row tap
                        // avoids making every ordinary sample click wait
                        // for a double-tap timeout.
                        if (row.hostsPlugin && row.type.toLowerCase().contains('sampler')) {
                          onRowDoubleTap?.call(index);
                        }
                      },
              // Only hosted plug-in lanes use a double-tap recognizer.
              onDoubleTap:
                  row.hostsPlugin && !row.type.toLowerCase().contains('sampler') && onRowDoubleTap != null
                      ? () => onRowDoubleTap!(index)
                      : null,
              onSecondaryTapDown:
                  onSecondaryTapDown == null ? null : (TapDownDetails details) => onSecondaryTapDown!(index, details),
              onPower: onTogglePower == null ? null : () => onTogglePower!(index),
              onStepTap: onStepTap == null ? null : (int step) => onStepTap!(index, step),
              onPointerDownStep:
                  onPointerDownStep == null
                      ? null
                      : (PointerDownEvent event, int step) => onPointerDownStep!(event, index, step),
              onPointerMoveStep:
                  onPointerMoveStep == null
                      ? null
                      : (PointerMoveEvent event, int step) => onPointerMoveStep!(event, index, step),
              onVol: onVolChanged == null ? null : (double val) => onVolChanged!(index, val),
              onPan: onPanChanged == null ? null : (double val) => onPanChanged!(index, val),
              onRouteTap: onRouteTap == null ? null : () => onRouteTap!(index),
            ),
          ),
        );
      },
    );
  }
}
