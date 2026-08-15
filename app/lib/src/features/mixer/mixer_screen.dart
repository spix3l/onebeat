// MixerScreen — the mixer and routing workspace surface (UI-C-05 / UI-D-05).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/kit_glyphs.dart';
import 'mixer_screen_vm.dart';
import 'mixer_strip.dart';
import 'routing_panel.dart';

class MixerScreen extends StatelessWidget {
  const MixerScreen({
    required this.vm,
    this.onSelectTrack,
    this.onToggleMute,
    this.onToggleSolo,
    this.onFader,
    this.onModeChanged,
    this.onRoutingFeedTap,
    this.onRoutingSendChange,
    this.onRoutingPrePostToggle,
    this.onRoutingSidechainToggle,
    this.onAddTrack,
    super.key,
  });

  final MixerScreenVm vm;
  final ValueChanged<int>? onSelectTrack;
  final ValueChanged<int>? onToggleMute;
  final ValueChanged<int>? onToggleSolo;
  final void Function(int index, double value)? onFader;
  final ValueChanged<MixerMode>? onModeChanged;
  final ValueChanged<int>? onRoutingFeedTap;
  final void Function(int sendIndex, double value)? onRoutingSendChange;
  final ValueChanged<int>? onRoutingPrePostToggle;
  final VoidCallback? onRoutingSidechainToggle;
  final VoidCallback? onAddTrack;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MixerHeader(
            mode: vm.mode,
            title: vm.title,
            onModeChanged: onModeChanged,
            onAddTrack: onAddTrack,
          ),
          Container(
            height: tokens.border.hairline,
            color: tokens.color.line,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.md,
                      vertical: tokens.spacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (int i = 0; i < vm.strips.length; i++) ...<Widget>[
                          ObMixerStrip.meter(
                            vm: vm.strips[i],
                            onTap: onSelectTrack == null ? null : () => onSelectTrack!(i),
                            onMute: onToggleMute == null ? null : () => onToggleMute!(i),
                            onSolo: onToggleSolo == null ? null : () => onToggleSolo!(i),
                            onFader: onFader == null ? null : (double v) => onFader!(i, v),
                          ),
                          SizedBox(width: tokens.spacing.xs),
                        ],
                        ObMixerStrip.meter(
                          vm: vm.masterStrip,
                          onTap: onSelectTrack == null ? null : () => onSelectTrack!(-1),
                          onMute: onToggleMute == null ? null : () => onToggleMute!(-1),
                          onSolo: onToggleSolo == null ? null : () => onToggleSolo!(-1),
                          onFader: onFader == null ? null : (double v) => onFader!(-1, v),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: tokens.border.hairline,
                  color: tokens.color.line,
                ),
                Expanded(
                  child: ObRoutingPanel(
                    vm: vm.routingPanel,
                    onFeedTap: onRoutingFeedTap,
                    onSendChange: onRoutingSendChange,
                    onPrePostToggle: onRoutingPrePostToggle,
                    onSidechainToggle: onRoutingSidechainToggle,
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

class _MixerHeader extends StatelessWidget {
  const _MixerHeader({
    required this.mode,
    required this.title,
    this.onModeChanged,
    this.onAddTrack,
  });

  final MixerMode mode;
  final String title;
  final ValueChanged<MixerMode>? onModeChanged;
  final VoidCallback? onAddTrack;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);

    return Container(
      height: tokens.size.pianoToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      child: Row(
        children: <Widget>[
          Text(title.toUpperCase(), style: tokens.type.sectionHeader),
          SizedBox(width: tokens.spacing.sm),
          Text('auto-routed by track identity', style: tokens.type.label),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ModeTabButton(
                  label: 'Focus',
                  icon: ObKitGlyphKind.menuLines,
                  selected: mode == MixerMode.trackFocus,
                  onPressed: onModeChanged == null ? null : () => onModeChanged!(MixerMode.trackFocus),
                ),
                _ModeTabButton(
                  label: 'Graph',
                  icon: ObKitGlyphKind.grid,
                  selected: mode == MixerMode.graphOverview,
                  onPressed: onModeChanged == null ? null : () => onModeChanged!(MixerMode.graphOverview),
                ),
                _ModeTabButton(
                  label: 'Matrix',
                  icon: ObKitGlyphKind.expand,
                  selected: mode == MixerMode.matrixView,
                  onPressed: onModeChanged == null ? null : () => onModeChanged!(MixerMode.matrixView),
                ),
              ],
            ),
          ),
          if (onAddTrack != null) ...<Widget>[
            SizedBox(width: tokens.spacing.md),
            ObButton(
              label: '+ Add Track',
              onTap: onAddTrack,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    this.onPressed,
  });

  final String label;
  final ObKitGlyphKind icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? color.surfaceRaised : null,
          borderRadius: tokens.radius.controlBorder,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ObKitGlyph(
              kind: icon,
              color: selected ? color.accent : color.textMuted,
              size: ObKitGlyphSize.inline,
            ),
            SizedBox(width: tokens.spacing.xs),
            Text(
              label,
              style: selected
                  ? tokens.type.body.copyWith(color: color.textPrimary)
                  : tokens.type.body.copyWith(color: color.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
