// ObEmptyState — the centred "there is nothing here yet" surface (UI-B-11 §3).
//
// The mockups treat an empty screen as the app's best chance to explain itself,
// not as an error: an icon tile, a headline that says what the place is for,
// a paragraph of real prose, the two or three things you could do, and a dim
// footnote. Everything below the actions is optional, because a first-setup
// screen wants a footnote where the extensions screen wants three numbered
// steps and a keyboard hint.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'kit_glyphs.dart';
import 'prose.dart';

@immutable
class ObEmptyStateVm {
  const ObEmptyStateVm({
    required this.icon,
    required this.heading,
    required this.body,
    this.footnote,
  });

  final ObKitGlyphKind icon;
  final String heading;

  /// Prose runs — see [ObProse]. Bold phrases are part of the copy.
  final List<ObProseRun> body;

  final String? footnote;
}

class ObEmptyState extends StatelessWidget {
  const ObEmptyState({
    required this.vm,
    this.actions = const <Widget>[],
    this.extra,
    super.key,
  });

  final ObEmptyStateVm vm;

  /// The call-to-action row. Built by the caller so it can pick its own
  /// [ObButton] tones — which one is the primary is a copy decision.
  final List<Widget> actions;

  /// Anything below the actions: the numbered steps under the extensions
  /// empty state, a device list under the audio one.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? footnote = vm.footnote;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: tokens.size.emptyTileSize,
            height: tokens.size.emptyTileSize,
            decoration: BoxDecoration(
              color: color.accentWash,
              borderRadius: BorderRadius.all(tokens.radius.xxl),
              border: Border.all(
                color: color.accentMuted,
                width: tokens.border.hairline,
              ),
            ),
            child: Center(
              child: ObKitGlyph(
                kind: vm.icon,
                color: color.accentBright,
                size: ObKitGlyphSize.feature,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          Text(vm.heading, style: tokens.type.emptyHeading),
          SizedBox(height: tokens.spacing.md),
          SizedBox(
            width: tokens.size.emptyProseWidth,
            child: ObProse(runs: vm.body, align: TextAlign.center),
          ),
          if (actions.isNotEmpty) ...<Widget>[
            SizedBox(height: tokens.spacing.xl),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < actions.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: tokens.spacing.sm),
                  actions[i],
                ],
              ],
            ),
          ],
          if (extra != null) ...<Widget>[
            SizedBox(height: tokens.spacing.xxl),
            extra!,
          ],
          if (footnote != null) ...<Widget>[
            SizedBox(height: tokens.spacing.xl),
            Text(footnote, style: tokens.type.menu),
          ],
        ],
      ),
    );
  }
}
