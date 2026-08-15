// The rack's own chrome (UI-B-05): the control toolbar above the grid, the
// column-caption strip under it, and the "grow the rack" card below the last
// lane.
//
// All three exist to frame `ObRackRow`, and all three take their geometry from
// the same tokens the lane does — the caption strip in particular lays its
// step numbers out against the cell width and the group-gap rule, so it cannot
// drift out of alignment with the columns it names.
import 'package:flutter/widgets.dart';

import '../../core/snap_grid.dart';
import '../../design/tokens.dart';
import '../../ui_kit/dropdown.dart';

/// The dropdown row above the grid.
@immutable
class RackToolbarVm {
  const RackToolbarVm({
    required this.channelType,
    required this.group,
    required this.snap,
    required this.steps,
    this.channelTypes = const <String>['Sampler', 'Synth', 'Audio clip'],
    this.groups = const <String>['All', 'Drums', 'Music'],
    this.snaps,
  });

  final String channelType;
  final String group;
  final String snap;

  /// How many steps the pattern is, as the engine's control accepts it. Not a
  /// caption: this used to be a formatted string next to a grid that was always
  /// 16 wide, which read as a setting but was only ever a label.
  final int steps;

  /// The lengths `ob_engine_rack_set_length` accepts. Anything else is rejected
  /// at the ABI, so the control offers exactly these.
  static const List<int> stepOptions = <int>[16, 32, 64];

  final List<String> channelTypes;
  final List<String> groups;
  final List<String>? snaps;

  // Legacy values remain in the VM so older fixtures can still construct it;
  // the rack no longer renders the non-functional filters in production.
  List<String> get snapLabels => snaps ?? SnapGridChoice.rackLabels;
}

class ObRackToolbar extends StatelessWidget {
  const ObRackToolbar({
    required this.vm,
    this.onChannelType,
    this.onGroup,
    this.onSnap,
    this.onMixerTap,
    this.onAddChannel,
    this.onAutomationTap,
    this.onSteps,
    super.key,
  });

  final RackToolbarVm vm;
  final ValueChanged<String>? onChannelType;
  final ValueChanged<String>? onGroup;
  final ValueChanged<String>? onSnap;
  final VoidCallback? onMixerTap;
  final VoidCallback? onAddChannel;
  final VoidCallback? onAutomationTap;
  final ValueChanged<int>? onSteps;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      height: tokens.size.rackToolbarBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          // Channel type, group, mixer and automation were never wired to rack
          // behaviour. They are intentionally absent rather than disabled.
          // Keep the callback-gated snap control for older isolated widget
          // fixtures; RackBinding does not provide this callback anymore.
          if (onSnap != null) ...<Widget>[
            ObDropdown(
              label: 'Snap',
              value: vm.snap,
              items: vm.snapLabels,
              width: tokens.size.rackSnapFieldWidth,
              onSelected: onSnap,
            ),
            SizedBox(width: tokens.spacing.md),
          ],
          const Spacer(),
          ObDropdown(
            label: 'Steps',
            value: '${vm.steps}',
            items: <String>[
              for (final int option in RackToolbarVm.stepOptions) '$option',
            ],
            width: tokens.size.rackSnapFieldWidth,
            onSelected: onSteps == null
                ? null
                : (String value) {
                    final int? parsed = int.tryParse(value);
                    if (parsed != null) onSteps!(parsed);
                  },
          ),
        ],
      ),
    );
  }
}

/// The column-caption strip: `PWR CHANNEL 1…16 VOL PAN SEND`.
///
/// Takes the same step count the lanes do so its numbers cannot drift out of
/// alignment with the cells they name.
class ObRackHeader extends StatelessWidget {
  const ObRackHeader({this.stepCount = 16, super.key});

  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final SizeTokens size = tokens.size;
    final TextStyle style = tokens.type.microCaps;

    return Container(
      height: size.rackColumnHeaderHeight,
      decoration: BoxDecoration(
        color: tokens.color.surfaceColumnHead,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: tokens.spacing.md),
          // `PWR` names the power column but is wider than it; it takes the
          // whole power-plus-chip block so the caption fits without pushing
          // `CHANNEL` off the name column.
          SizedBox(
            width: size.rackPowerSize + tokens.spacing.sm + size.rackColorChipSize + tokens.spacing.md,
            child: Text('PWR', style: style, maxLines: 1),
          ),
          SizedBox(
            width: size.rackNameWidth,
            child: Text('CHANNEL', style: style, maxLines: 1),
          ),
          // One number per column, centred on the cell it names.
          for (int i = 0; i < stepCount; i++) ...<Widget>[
            if (i > 0)
              SizedBox(
                width: i % 4 == 0 ? size.rackStepGroupGap : size.rackStepGap,
              ),
            SizedBox(
              width: size.rackStepCell,
              child: Text(
                '${i + 1}',
                style: style,
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
          SizedBox(width: tokens.spacing.md),
          SizedBox(
            width: size.knobSmall,
            child: Text(
              'VOL',
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          SizedBox(
            width: size.knobSmall,
            child: Text(
              'PAN',
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          SizedBox(
            width: size.rackRouteChipWidth,
            child: Text(
              'SEND',
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          SizedBox(width: tokens.spacing.md),
        ],
      ),
    );
  }
}

/// The card under the last lane: how to add the next channel, and the
/// shortcut that does it without the mouse.
class ObRackFooter extends StatelessWidget {
  const ObRackFooter({
    this.lead = 'Double-click, or use',
    this.action = 'Add channel',
    this.trail = 'to grow the rack',
    this.shortcut = '⌘A',
    this.onAddChannel,
    this.onDoubleTap,
    super.key,
  });

  final String lead;

  /// The one emphasised phrase in the sentence — the thing to click.
  final String action;
  final String trail;
  final String shortcut;
  final VoidCallback? onAddChannel;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAddChannel,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: tokens.size.rackFooterHeight,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
        decoration: BoxDecoration(
          color: color.surfaceRaised,
          borderRadius: tokens.radius.panelBorder,
          border: Border.all(color: color.line, width: tokens.border.hairline),
        ),
        child: Row(
          children: <Widget>[
            Text('+', style: tokens.type.title),
            SizedBox(width: tokens.spacing.md),
            Text(lead, maxLines: 1, style: tokens.type.bodySecondary),
            SizedBox(width: tokens.spacing.sm),
            Text(
              action,
              maxLines: 1,
              style: tokens.type.body.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(width: tokens.spacing.sm),
            Text(trail, maxLines: 1, style: tokens.type.bodySecondary),
            const Spacer(),
            Text(shortcut, maxLines: 1, style: tokens.type.numericSmall),
          ],
        ),
      ),
    );
  }
}
