// The rack's own chrome (UI-B-05): the control toolbar above the grid, the
// column-caption strip under it, and the "grow the rack" card below the last
// lane.
//
// All three exist to frame `ObRackRow`, and all three take their geometry from
// the same tokens the lane does — the caption strip in particular lays its
// step numbers out against the cell width and the group-gap rule, so it cannot
// drift out of alignment with the columns it names.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/dropdown.dart';
import '../../core/snap_grid.dart';

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
          ObDropdown(
            label: 'Channel type',
            value: vm.channelType,
            items: vm.channelTypes,
            width: tokens.size.rackTypeFieldWidth,
            onSelected: onChannelType,
          ),
          SizedBox(width: tokens.spacing.sm),
          ObDropdown(
            label: 'Group',
            value: vm.group,
            items: vm.groups,
            width: tokens.size.rackGroupFieldWidth,
            onSelected: onGroup,
          ),
          SizedBox(width: tokens.spacing.sm),
          ObDropdown(
            label: 'Snap',
            value: vm.snap,
            items: vm.snapLabels,
            width: tokens.size.rackSnapFieldWidth,
            onSelected: onSnap,
          ),
          SizedBox(width: tokens.spacing.md),
          _IconButton(kind: RackToolKind.mixer, onTap: onMixerTap),
          SizedBox(width: tokens.spacing.sm),
          _IconButton(
            kind: RackToolKind.add,
            accent: true,
            onTap: onAddChannel,
          ),
          SizedBox(width: tokens.spacing.sm),
          _IconButton(kind: RackToolKind.automation, onTap: onAutomationTap),
          SizedBox(width: tokens.spacing.sm),
          const Spacer(),
          ObDropdown(
            label: 'Steps',
            value: '${vm.steps}',
            items: <String>[
              for (final int option in RackToolbarVm.stepOptions) '$option',
            ],
            width: tokens.size.rackSnapFieldWidth,
            onSelected:
                onSteps == null
                    ? null
                    : (String value) {
                      final int? parsed = int.tryParse(value);
                      if (parsed != null) onSteps!(parsed);
                    },
          ),
          SizedBox(width: tokens.spacing.sm),
          Text('· loop', maxLines: 1, style: tokens.type.numericSmall),
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
            width:
                size.rackPowerSize +
                tokens.spacing.sm +
                size.rackColorChipSize +
                tokens.spacing.md,
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
            _IconButton(kind: RackToolKind.add, onTap: onAddChannel),
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

/// Which glyph a toolbar button carries.
enum RackToolKind { mixer, add, automation }

class _IconButton extends StatefulWidget {
  const _IconButton({required this.kind, this.accent = false, this.onTap});

  final RackToolKind kind;

  /// The one accented button in the row: adding a channel is the action the
  /// toolbar exists for.
  final bool accent;
  final VoidCallback? onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null;
    final Color fill;
    if (widget.accent) {
      fill = _hover && enabled ? color.accentBright : color.accent;
    } else {
      fill = _hover && enabled ? color.surfaceHover : color.surfaceWell;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: tokens.size.microFieldHeight,
          height: tokens.size.microFieldHeight,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: widget.accent ? color.accentBright : color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: CustomPaint(
            painter: _RackToolPainter(
              kind: widget.kind,
              color: widget.accent ? color.textPrimary : color.textSecondary,
              stroke: tokens.border.glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class _RackToolPainter extends CustomPainter {
  _RackToolPainter({
    required this.kind,
    required this.color,
    required this.stroke,
  });

  final RackToolKind kind;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color;
    final double w = size.width;
    final double h = size.height;

    switch (kind) {
      case RackToolKind.mixer:
        // Three rails with caps: the same idea as the rail's mixer glyph, at
        // button scale.
        final List<double> rows = <double>[h * 0.34, h * 0.5, h * 0.66];
        final List<double> caps = <double>[w * 0.62, w * 0.38, w * 0.56];
        for (int i = 0; i < rows.length; i++) {
          canvas.drawLine(
            Offset(w * 0.28, rows[i]),
            Offset(w * 0.72, rows[i]),
            line,
          );
          canvas.drawLine(
            Offset(caps[i], rows[i] - h * 0.07),
            Offset(caps[i], rows[i] + h * 0.07),
            line,
          );
        }
      case RackToolKind.add:
        canvas.drawLine(
          Offset(w * 0.5, h * 0.28),
          Offset(w * 0.5, h * 0.72),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.28, h * 0.5),
          Offset(w * 0.72, h * 0.5),
          line,
        );
      case RackToolKind.automation:
        // A single pulse: flat, spike, flat — automation as "a value that
        // moves".
        final Path path =
            Path()
              ..moveTo(w * 0.24, h * 0.5)
              ..lineTo(w * 0.38, h * 0.5)
              ..lineTo(w * 0.46, h * 0.28)
              ..lineTo(w * 0.56, h * 0.72)
              ..lineTo(w * 0.64, h * 0.5)
              ..lineTo(w * 0.76, h * 0.5);
        canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_RackToolPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.stroke != stroke;
}
