// ObRoutingPanel — routing in plain words (UI-B-10).
//
// The panel exists because "route by name, never by number" is a product
// decision, not a layout one: every row here is a sentence about the selected
// track — what feeds it, what it feeds, what it sends, what ducks it — and the
// numbers (`out 1`, `0.42`, `−6 dB`) trail the words rather than leading them.
//
// Presentational only: it is handed a description of the routing and reports
// what the user did to it.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// A track that feeds this one, or the one this feeds.
@immutable
class FeedVm {
  const FeedVm({
    required this.name,
    required this.color,
    required this.routeText,
  });

  final String name;
  final Color color;

  /// The mono trailing note: `out 1 → Drums Bus`, `→ output`.
  final String routeText;
}

@immutable
class SendVm {
  const SendVm({
    required this.name,
    required this.value,
    required this.valueText,
    required this.pre,
  });

  /// `→ Reverb Send`.
  final String name;

  /// 0..1 slider position.
  final double value;

  /// The same value as text (`0.42`) — formatting is the vm's job.
  final String valueText;

  /// Pre-fader when true; the mockup accents the POST tag, because post is
  /// the choice that changes when you move the fader.
  final bool pre;
}

@immutable
class SidechainVm {
  const SidechainVm({
    required this.sourceName,
    required this.sourceColor,
    required this.targetName,
    required this.targetCaption,
    required this.amountText,
    this.enabled = true,
  });

  final String sourceName;
  final Color sourceColor;
  final String targetName;

  /// `compressor key input`.
  final String targetCaption;

  /// `−6 dB`, already formatted.
  final String amountText;

  final bool enabled;
}

@immutable
class RoutingPanelVm {
  const RoutingPanelVm({
    required this.trackName,
    required this.feeds,
    required this.feedsInto,
    required this.sends,
    required this.caption,
    this.sidechain,
    this.note = 'in plain words',
  });

  final String trackName;

  /// What arrives here.
  final List<FeedVm> feeds;

  /// Where this goes. A list because a track can feed more than one place,
  /// even though the mockup shows one.
  final List<FeedVm> feedsInto;

  final List<SendVm> sends;

  /// The one-sentence explanation at the bottom — the panel's whole reason
  /// for existing, so it is part of the vm rather than a hard-coded string.
  final String caption;

  final SidechainVm? sidechain;
  final String note;
}

class ObRoutingPanel extends StatelessWidget {
  const ObRoutingPanel({
    required this.vm,
    this.onFeedTap,
    this.onSendChange,
    this.onPrePostToggle,
    this.onSidechainToggle,
    this.onSidechainAmount,
    super.key,
  });

  final RoutingPanelVm vm;

  /// Fired with the tapped feed's index within [RoutingPanelVm.feeds].
  final ValueChanged<int>? onFeedTap;

  final void Function(int index, double value)? onSendChange;
  final ValueChanged<int>? onPrePostToggle;
  final VoidCallback? onSidechainToggle;
  final VoidCallback? onSidechainAmount;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final SidechainVm? sidechain = vm.sidechain;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      color: tokens.color.surfacePanel,
      child: ListView(
        children: <Widget>[
          _PanelHeader(
            title: 'Routing — ${vm.trackName}',
            note: vm.note,
          ),
          _SectionLabel(
            label: 'Feeds this track',
            right: '${vm.feeds.length} inputs',
          ),
          for (int i = 0; i < vm.feeds.length; i++) ...<Widget>[
            FeedRow(
              vm: vm.feeds[i],
              onTap: onFeedTap == null ? null : () => onFeedTap!(i),
            ),
            SizedBox(height: tokens.spacing.xs),
          ],
          const _SectionLabel(label: 'This track feeds'),
          for (final FeedVm feed in vm.feedsInto) ...<Widget>[
            FeedRow(vm: feed, into: true),
            SizedBox(height: tokens.spacing.xs),
          ],
          const _SectionLabel(label: 'Sends'),
          for (int i = 0; i < vm.sends.length; i++) ...<Widget>[
            SendRow(
              vm: vm.sends[i],
              onChanged:
                  onSendChange == null
                      ? null
                      : (double value) => onSendChange!(i, value),
              onPrePostToggle:
                  onPrePostToggle == null ? null : () => onPrePostToggle!(i),
            ),
            SizedBox(height: tokens.spacing.xs),
          ],
          if (sidechain != null) ...<Widget>[
            const _SectionLabel(label: 'Sidechain'),
            SidechainCard(
              vm: sidechain,
              onToggle: onSidechainToggle,
              onAmount: onSidechainAmount,
            ),
          ],
          SizedBox(height: tokens.spacing.md),
          Text(vm.caption, style: tokens.type.bodySecondary),
          SizedBox(height: tokens.spacing.lg),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.routingHeaderHeight,
      alignment: Alignment.centerLeft,
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
          Text(title.toUpperCase(), style: tokens.type.sectionHeader),
          const Spacer(),
          Text(note, style: tokens.type.label),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.right});

  final String label;

  /// The dim mono count at the right (`4 inputs`).
  final String? right;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final String? right = this.right;
    return SizedBox(
      height: tokens.size.routingSectionLabelHeight,
      child: Row(
        children: <Widget>[
          Text(label.toUpperCase(), style: tokens.type.microCaps),
          const Spacer(),
          if (right != null) Text(right, style: tokens.type.numericSmall),
        ],
      ),
    );
  }
}

/// A raised row naming a track and where its signal goes.
class FeedRow extends StatefulWidget {
  const FeedRow({required this.vm, this.into = false, this.onTap, super.key});

  final FeedVm vm;

  /// The destination variant: accent-tinted, because "where this ends up" is
  /// the one row in the section a user is looking for.
  final bool into;

  final VoidCallback? onTap;

  @override
  State<FeedRow> createState() => _FeedRowState();
}

class _FeedRowState extends State<FeedRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final bool enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: tokens.size.routingRowHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          decoration: BoxDecoration(
            color:
                widget.into
                    ? color.accentWash
                    : (_hover ? color.surfaceWell : color.surfaceRaised),
            borderRadius: tokens.radius.panelBorder,
            border: Border.all(
              color: widget.into ? color.accentMuted : color.line,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              if (!widget.into) ...<Widget>[
                Container(
                  width: tokens.size.routingDotSize,
                  height: tokens.size.routingDotSize,
                  decoration: BoxDecoration(
                    color: widget.vm.color,
                    borderRadius: BorderRadius.all(tokens.radius.sm),
                  ),
                ),
                SizedBox(width: tokens.spacing.md),
              ],
              Text(
                widget.vm.name,
                maxLines: 1,
                style: tokens.type.title,
              ),
              const Spacer(),
              Text(
                widget.vm.routeText,
                maxLines: 1,
                style:
                    widget.into
                        ? tokens.type.numericSmall.copyWith(
                          color: color.accentBright,
                        )
                        : tokens.type.numericSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A send: its name, the amount, and whether it is taken before or after the
/// fader.
class SendRow extends StatelessWidget {
  const SendRow({
    required this.vm,
    this.onChanged,
    this.onPrePostToggle,
    super.key,
  });

  final SendVm vm;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onPrePostToggle;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      height: tokens.size.routingRowHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfaceRaised,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(vm.name, maxLines: 1, style: tokens.type.title),
          const Spacer(),
          _SendSlider(value: vm.value, onChanged: onChanged),
          SizedBox(width: tokens.spacing.lg),
          SizedBox(
            width: tokens.size.routingValueWidth,
            child: Text(
              vm.valueText,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: tokens.type.numeric,
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          _PrePostTag(pre: vm.pre, onTap: onPrePostToggle),
        ],
      ),
    );
  }
}

class _SendSlider extends StatelessWidget {
  const _SendSlider({required this.value, this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double width = tokens.size.routingSliderWidth;
    final double cap = tokens.size.routingSliderCapSize;

    void report(Offset local) {
      if (onChanged == null) {
        return;
      }
      onChanged!((local.dx / width).clamp(0.0, 1.0));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          onChanged == null
              ? null
              : (TapDownDetails d) => report(d.localPosition),
      onHorizontalDragUpdate:
          onChanged == null
              ? null
              : (DragUpdateDetails d) => report(d.localPosition),
      child: SizedBox(
        width: width,
        height: cap,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            Container(
              height: tokens.size.routingSliderTrackHeight,
              decoration: BoxDecoration(
                color: color.meterTrack,
                borderRadius: BorderRadius.all(tokens.radius.md),
              ),
            ),
            Container(
              width: width * value.clamp(0.0, 1.0),
              height: tokens.size.routingSliderTrackHeight,
              decoration: BoxDecoration(
                color: color.accent,
                borderRadius: BorderRadius.all(tokens.radius.md),
              ),
            ),
            Positioned(
              left: (width - cap) * value.clamp(0.0, 1.0),
              child: Container(
                width: cap,
                height: cap,
                decoration: BoxDecoration(
                  color: color.faderThumb,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrePostTag extends StatelessWidget {
  const _PrePostTag({required this.pre, this.onTap});

  final bool pre;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          width: tokens.size.routingTagWidth,
          height: tokens.size.microFieldHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // POST is outlined in the accent: it is the setting that changes
            // when the fader moves, so it is the one worth noticing.
            color: pre ? color.surfaceWell : color.accentWash,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: pre ? color.lineStrong : color.accentBright,
              width: tokens.border.hairline,
            ),
          ),
          child: Text(
            pre ? 'PRE' : 'POST',
            maxLines: 1,
            style: tokens.type.microCaps.copyWith(
              color: pre ? color.textMuted : color.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The amber card: who ducks whom, and by how much.
class SidechainCard extends StatelessWidget {
  const SidechainCard({
    required this.vm,
    this.onToggle,
    this.onAmount,
    super.key,
  });

  final SidechainVm vm;
  final VoidCallback? onToggle;
  final VoidCallback? onAmount;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.routingSidechainHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        // Amber, not accent: a sidechain is the one routing relationship that
        // is neither an input nor an output, and it earns its own colour.
        color: color.surfaceRaised,
        borderRadius: tokens.radius.panelBorder,
        border: Border.all(
          color: color.sidechainGold,
          width: tokens.border.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.routingDotSize,
            height: tokens.size.routingDotSize,
            decoration: BoxDecoration(
              color: vm.sourceColor,
              borderRadius: BorderRadius.all(tokens.radius.sm),
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(vm.sourceName, maxLines: 1, style: tokens.type.title),
              Text('sidechain source', maxLines: 1, style: tokens.type.label),
            ],
          ),
          SizedBox(width: tokens.spacing.lg),
          Expanded(
            child: CustomPaint(
              painter: _ConnectorPainter(
                color: color.sidechainGold,
                stroke: tokens.border.hairline,
                glyph: tokens.border.glyph,
              ),
              child: SizedBox(height: tokens.size.iconSize),
            ),
          ),
          SizedBox(width: tokens.spacing.lg),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(vm.targetName, maxLines: 1, style: tokens.type.title),
              Text(vm.targetCaption, maxLines: 1, style: tokens.type.label),
            ],
          ),
          SizedBox(width: tokens.spacing.lg),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Enabled', style: tokens.type.bodySecondary),
                  SizedBox(width: tokens.spacing.sm),
                  _Switch(on: vm.enabled, onTap: onToggle),
                ],
              ),
              SizedBox(height: tokens.spacing.xs),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAmount,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Amount', style: tokens.type.bodySecondary),
                    SizedBox(width: tokens.spacing.sm),
                    Text(
                      vm.amountText,
                      style: tokens.type.numeric.copyWith(
                        color: color.sidechainGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on, this.onTap});

  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final double height = tokens.size.routingSwitchHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          width: tokens.size.routingSwitchWidth,
          height: height,
          padding: EdgeInsets.all(tokens.spacing.xxs),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: on ? color.accent : color.surfaceWell,
            borderRadius: BorderRadius.all(tokens.radius.lg),
            border: Border.all(
              color: on ? color.accentBright : color.lineStrong,
              width: tokens.border.hairline,
            ),
          ),
          child: Container(
            width: height - tokens.spacing.sm,
            height: height - tokens.spacing.sm,
            decoration: BoxDecoration(
              color: on ? color.textPrimary : color.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// The amber run between source and target, with a chevron at its head.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({
    required this.color,
    required this.stroke,
    required this.glyph,
  });

  final Color color;
  final double stroke;
  final double glyph;

  late final Paint _line =
      Paint()
        ..color = color
        ..strokeWidth = stroke;
  late final Paint _head =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = glyph
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final double mid = size.height / 2;
    final double end = size.width - size.height * 0.6;
    canvas.drawLine(Offset(0, mid), Offset(end, mid), _line);
    canvas.drawLine(
      Offset(end, mid - size.height * 0.22),
      Offset(size.width, mid),
      _head,
    );
    canvas.drawLine(
      Offset(end, mid + size.height * 0.22),
      Offset(size.width, mid),
      _head,
    );
  }

  @override
  bool shouldRepaint(_ConnectorPainter oldDelegate) =>
      oldDelegate.color != color;
}
