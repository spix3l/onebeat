// ObSideRail — the left destination rail (UI-B-03).
//
// A column of project destinations down the window's left edge. Library
// content such as plug-ins and sample packs is shown in the browser panel
// alongside the project, rather than treated as a separate destination.
//
// Presentational only: the rail knows which index is active and reports taps.
// Which view that index means is the shell's business (UI-C-01).
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/rail_button.dart';
import 'rail_glyphs.dart';

/// One destination in the rail.
@immutable
class RailItemVm {
  const RailItemVm({required this.icon, required this.label});

  final ObRailGlyphKind icon;

  /// Shown in micro-caps under the glyph; upper-cased by [ObRailButton].
  final String label;

  @override
  bool operator ==(Object other) => other is RailItemVm && other.icon == icon && other.label == label;

  @override
  int get hashCode => Object.hash(icon, label);
}

@immutable
class ObSideRailVm {
  const ObSideRailVm({
    required this.items,
    required this.activeIndex,
    this.separatorBefore,
  });

  final List<RailItemVm> items;

  /// The destination currently on screen. Out-of-range means "none active",
  /// which is what a detached-window layout shows.
  final int activeIndex;

  /// Index the grouping hairline is drawn above; null draws none.
  final int? separatorBefore;
}

class ObSideRail extends StatelessWidget {
  const ObSideRail({required this.vm, this.onSelect, super.key});

  final ObSideRailVm vm;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final List<Widget> children = <Widget>[
      SizedBox(height: tokens.spacing.sm),
    ];
    for (int i = 0; i < vm.items.length; i++) {
      if (vm.separatorBefore == i) {
        children.add(_RailSeparator(tokens: tokens));
      }
      final RailItemVm item = vm.items[i];
      children.add(
        ObRailButton(
          icon: ObRailGlyph(kind: item.icon),
          label: item.label,
          active: i == vm.activeIndex,
          onTap: onSelect == null ? null : () => onSelect!(i),
        ),
      );
      children.add(SizedBox(height: tokens.spacing.sm));
    }

    return Container(
      width: tokens.size.railWidth,
      decoration: BoxDecoration(
        color: tokens.color.surfaceRaised,
        border: Border(
          right: BorderSide(
            color: tokens.color.lineStrong,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}

/// An optional inset hairline for grouping rail destinations.
class _RailSeparator extends StatelessWidget {
  const _RailSeparator({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
      child: Container(
        width: tokens.size.railSeparatorWidth,
        height: tokens.border.hairline,
        color: tokens.color.lineStrong,
      ),
    );
  }
}
