// ObProse — running text with bold runs inside it (UI-B-11).
//
// The empty states and the extension descriptions are the only places in the
// app where copy is *read* rather than scanned, and they emphasise a phrase
// mid-sentence: "extensions are just scripts with **your project as the API**".
// A vm cannot hand a widget a `TextSpan` tree without importing painting types
// into what is meant to be plain data, so it hands over a list of runs instead
// and this turns them into one paragraph.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// One stretch of copy at one emphasis.
@immutable
class ObProseRun {
  const ObProseRun(this.text, {this.strong = false});

  final String text;

  /// Renders in [TypeTokens.proseStrong] — heavier and at full ink.
  final bool strong;

  @override
  bool operator ==(Object other) =>
      other is ObProseRun && other.text == text && other.strong == strong;

  @override
  int get hashCode => Object.hash(text, strong);
}

class ObProse extends StatelessWidget {
  const ObProse({
    required this.runs,
    this.align = TextAlign.left,
    this.style,
    this.strongStyle,
    super.key,
  });

  final List<ObProseRun> runs;
  final TextAlign align;

  /// Overrides for surfaces that set prose at a different size — the extension
  /// description line is [TypeTokens.body], not the empty state's larger
  /// [TypeTokens.prose].
  final TextStyle? style;
  final TextStyle? strongStyle;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final TextStyle base = style ?? tokens.type.prose;
    final TextStyle strong =
        strongStyle ??
        (style == null
            ? tokens.type.proseStrong
            : base.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.color.textPrimary,
            ));
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final ObProseRun run in runs)
            TextSpan(text: run.text, style: run.strong ? strong : base),
        ],
      ),
      textAlign: align,
    );
  }
}
