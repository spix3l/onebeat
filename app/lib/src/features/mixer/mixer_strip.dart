// ObMixerStrip — one channel of the mixer, in either of its two shapes
// (UI-B-09).
//
// The docked mixer shows *meter* strips: narrow columns you read. The detached
// window shows *fader* strips: wider columns you grab. Same vm, same order of
// parts — name, identity bar, M/S/route, the tall thing, the destination —
// because a strip has to be recognisable as the same object in both places.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/toggle_chip.dart';
import 'strip_meter.dart';

@immutable
class MixerStripVm {
  const MixerStripVm({
    required this.name,
    required this.color,
    required this.route,
    this.level = 0,
    this.fader = 0.75,
    this.muted = false,
    this.soloed = false,
    this.routeActive = false,
    this.selected = false,
    this.isMaster = false,
    this.sidechainIn = false,
  });

  final String name;

  /// Identity colour, drawn as the bar under the name.
  final Color color;

  /// The bottom line: `→ Drums` for a track, `0.0 dB` for the master.
  final String route;

  /// 0..1 meter level.
  final double level;

  /// 0..1 fader position.
  final double fader;

  final bool muted;
  final bool soloed;

  /// The round lamp beside M and S: lit when this strip is a routing
  /// destination for something else.
  final bool routeActive;

  final bool selected;
  final bool isMaster;

  /// Draws the `↓ SC in` tag — this track is being ducked by another.
  final bool sidechainIn;
}

/// Which shape the strip takes.
enum MixerStripKind { meter, fader }

class ObMixerStrip extends StatelessWidget {
  const ObMixerStrip.meter({
    required this.vm,
    this.onTap,
    this.onMute,
    this.onSolo,
    this.onFader,
    super.key,
  }) : kind = MixerStripKind.meter;

  const ObMixerStrip.fader({
    required this.vm,
    this.onTap,
    this.onMute,
    this.onSolo,
    this.onFader,
    super.key,
  }) : kind = MixerStripKind.fader;

  final MixerStripKind kind;
  final MixerStripVm vm;
  final VoidCallback? onTap;
  final VoidCallback? onMute;
  final VoidCallback? onSolo;
  final ValueChanged<double>? onFader;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final SizeTokens size = tokens.size;
    final bool fader = kind == MixerStripKind.fader;

    final double width =
        fader
            ? size.mixerFaderStripWidth
            : (vm.isMaster ? size.mixerMasterStripWidth : size.mixerStripWidth);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        // A 42px column has almost no width to give away: the padding is the
        // smallest step on the scale so that `Drums Bus` and `→ Drums` both
        // fit without truncating, the way the mockup draws them.
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.xxs,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          // Selected is an accent outline over an accent wash, not a fill: the
          // meter inside is already carrying three saturated colours.
          color: vm.selected ? color.accentWash : color.surfaceRaised,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: vm.selected ? color.accent : color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              vm.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  vm.selected || vm.isMaster
                      ? tokens.type.stripName.copyWith(
                        color: color.textPrimary,
                      )
                      : tokens.type.stripName,
            ),
            SizedBox(height: tokens.spacing.xs),
            Container(
              height: size.mixerColorBarHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: vm.color,
                borderRadius: BorderRadius.all(tokens.radius.xs),
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            _ToggleRow(
              muted: vm.muted,
              soloed: vm.soloed,
              routeActive: vm.routeActive,
              onMute: onMute,
              onSolo: onSolo,
            ),
            if (vm.sidechainIn) ...<Widget>[
              SizedBox(height: tokens.spacing.xs),
              Text(
                '↓ SC in',
                maxLines: 1,
                style: tokens.type.stripRoute.copyWith(
                  color: color.sidechainGold,
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.sm),
            Expanded(
              child:
                  fader
                      ? StripFader(
                        position: vm.fader,
                        selected: vm.selected,
                        onChanged: onFader,
                      )
                      : Center(
                        child: StripMeter(
                          level: vm.level,
                          width:
                              vm.isMaster
                                  ? size.mixerMasterMeterWidth
                                  : size.mixerMeterWidth,
                        ),
                      ),
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              vm.route,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.stripRoute,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.muted,
    required this.soloed,
    required this.routeActive,
    this.onMute,
    this.onSolo,
  });

  final bool muted;
  final bool soloed;
  final bool routeActive;
  final VoidCallback? onMute;
  final VoidCallback? onSolo;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    // Three controls across a 42px column is tight by design; scaling down is
    // how the row stays intact in the narrow strip and still fills the wide
    // one, rather than clipping its third control in one and not the other.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: tokens.size.mixerToggleSize,
            height: tokens.size.mixerToggleSize,
            child: FittedBox(
              child: ObToggleChip(
                tone: ObToggleTone.mute,
                on: muted,
                onTap: onMute,
              ),
            ),
          ),
          SizedBox(width: tokens.spacing.xxs),
          SizedBox(
            width: tokens.size.mixerToggleSize,
            height: tokens.size.mixerToggleSize,
            child: FittedBox(
              child: ObToggleChip(
                tone: ObToggleTone.solo,
                on: soloed,
                onTap: onSolo,
              ),
            ),
          ),
          SizedBox(width: tokens.spacing.xxs),
          Container(
            width: tokens.size.mixerLampSize,
            height: tokens.size.mixerLampSize,
            decoration: BoxDecoration(
              color: routeActive ? color.accent : color.surfaceWell,
              shape: BoxShape.circle,
              border: Border.all(
                color: routeActive ? color.accentBright : color.lineStrong,
                width: tokens.border.hairline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
