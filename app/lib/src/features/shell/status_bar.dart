// ObStatusBar — the 26px footer (UI-B-03).
//
// One line, three jobs: a tone dot and a bold word for *what the app is doing*,
// a dim dot-separated run of detail for *what it is doing it to*, and a dim
// right-aligned hint for *what you could do next*. The three tiers are
// deliberately different weights — a status bar where everything is the same
// colour is a status bar nobody reads.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// The colour of the leading dot: how worried to be about the state.
enum StatusTone { ok, warning, danger }

@immutable
class ObStatusBarVm {
  const ObStatusBarVm({
    required this.tone,
    required this.primary,
    this.details = const <String>[],
    this.rightHint,
  });

  final StatusTone tone;

  /// The bold lead word (`Ready`, `Playing`, `Inspecting Drums Bus`).
  final String primary;

  /// Detail fragments; rendered `· a · b · c`, dimmer than [primary].
  final List<String> details;

  /// The dim right-aligned hint (`⌘R routing · ⇧⌘R overview`).
  final String? rightHint;
}

class ObStatusBar extends StatelessWidget {
  const ObStatusBar({required this.vm, super.key});

  final ObStatusBarVm vm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;
    final String? hint = vm.rightHint;

    return Container(
      height: tokens.size.statusBarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: color.surfaceSunken,
        border: Border(
          top: BorderSide(color: color.line, width: tokens.border.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.statusDotSize,
            height: tokens.size.statusDotSize,
            decoration: BoxDecoration(
              color: _toneColor(color, vm.tone),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          Text(
            vm.primary,
            maxLines: 1,
            style: tokens.type.wordmark,
          ),
          if (vm.details.isNotEmpty) ...<Widget>[
            SizedBox(width: tokens.spacing.md),
            Flexible(
              child: Text(
                // The leading separator is part of the pattern: the details
                // trail the primary rather than starting a new sentence.
                '· ${vm.details.join(' · ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.type.menu.copyWith(color: color.textSecondary),
              ),
            ),
          ],
          const Spacer(),
          if (hint != null)
            Text(hint, maxLines: 1, style: tokens.type.menu),
        ],
      ),
    );
  }

  static Color _toneColor(ColorTokens color, StatusTone tone) {
    switch (tone) {
      case StatusTone.ok:
        return color.trafficGreen;
      case StatusTone.warning:
        return color.warning;
      case StatusTone.danger:
        return color.danger;
    }
  }
}
