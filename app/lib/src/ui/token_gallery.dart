// The token specimen sheet (OB-1-03 AC: "docs page renders swatches and type
// specimens"). Toggled with F9.
//
// It lives inside the app rather than in a static document on purpose: a
// specimen sheet generated from a copy of the values is a specimen sheet that
// goes stale. This one renders the tokens the app is actually using.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

class TokenGallery extends StatelessWidget {
  const TokenGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      color: tokens.color.surfaceDeep,
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('DESIGN TOKENS  (F9 to close)', style: tokens.type.label),
            SizedBox(height: tokens.spacing.lg),
            _section(tokens, 'Surfaces and text'),
            Wrap(
              spacing: tokens.spacing.md,
              runSpacing: tokens.spacing.md,
              children: <Widget>[
                _swatch(tokens, 'surfaceDeep', tokens.color.surfaceDeep),
                _swatch(tokens, 'surfacePanel', tokens.color.surfacePanel),
                _swatch(tokens, 'surfaceRaised', tokens.color.surfaceRaised),
                _swatch(tokens, 'line', tokens.color.line),
                _swatch(tokens, 'textPrimary', tokens.color.textPrimary),
                _swatch(tokens, 'textMuted', tokens.color.textMuted),
                _swatch(tokens, 'accent', tokens.color.accent),
                _swatch(tokens, 'accentMuted', tokens.color.accentMuted),
              ],
            ),
            SizedBox(height: tokens.spacing.xl),
            _section(tokens, 'Meters — semantic, never restyled'),
            Wrap(
              spacing: tokens.spacing.md,
              runSpacing: tokens.spacing.md,
              children: <Widget>[
                _swatch(tokens, 'meterLow', tokens.color.meterLow),
                _swatch(tokens, 'meterMid', tokens.color.meterMid),
                _swatch(tokens, 'meterHigh', tokens.color.meterHigh),
                _swatch(tokens, 'meterTrack', tokens.color.meterTrack),
                _swatch(tokens, 'warning', tokens.color.warning),
                _swatch(tokens, 'danger', tokens.color.danger),
              ],
            ),
            SizedBox(height: tokens.spacing.xl),
            _section(
              tokens,
              'Type — Archivo for words, Martian Mono for numbers',
            ),
            Text('Title — the quick brown fox', style: tokens.type.title),
            SizedBox(height: tokens.spacing.xs),
            Text(
              'Body — the quick brown fox jumps over the lazy dog',
              style: tokens.type.body,
            ),
            SizedBox(height: tokens.spacing.xs),
            Text('LABEL — SIDECHAIN COMPRESSION', style: tokens.type.label),
            SizedBox(height: tokens.spacing.xs),
            Text(
              'LABEL DENSE — SIDECHAIN COMPRESSION',
              style: tokens.type.labelDense,
            ),
            SizedBox(height: tokens.spacing.xs),
            Text('012.3.480   00:04.75   -6.0 dB', style: tokens.type.numeric),
            SizedBox(height: tokens.spacing.xs),
            Text('001.1.000', style: tokens.type.numericLarge),
            SizedBox(height: tokens.spacing.xs),
            Text(
              '48000 Hz · 128 frames · 5.7 ms',
              style: tokens.type.numericSmall,
            ),
            SizedBox(height: tokens.spacing.xl),
            _section(tokens, 'Spacing'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _spacingBar(tokens, 'xxs', tokens.spacing.xxs),
                _spacingBar(tokens, 'xs', tokens.spacing.xs),
                _spacingBar(tokens, 'sm', tokens.spacing.sm),
                _spacingBar(tokens, 'md', tokens.spacing.md),
                _spacingBar(tokens, 'lg', tokens.spacing.lg),
                _spacingBar(tokens, 'xl', tokens.spacing.xl),
                _spacingBar(tokens, 'xxl', tokens.spacing.xxl),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(OneBeatTokens tokens, String title) => Padding(
    padding: EdgeInsets.only(bottom: tokens.spacing.sm),
    child: Text(title, style: tokens.type.title),
  );

  Widget _swatch(OneBeatTokens tokens, String name, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Container(
        width: tokens.size.overlayLabelWidth * 2,
        height: tokens.size.controlHeight,
        decoration: BoxDecoration(
          color: color,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      SizedBox(height: tokens.spacing.xxs),
      Text(name, style: tokens.type.label),
    ],
  );

  Widget _spacingBar(OneBeatTokens tokens, String name, double value) =>
      Padding(
        padding: EdgeInsets.only(right: tokens.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: value,
              height: tokens.size.controlHeight,
              color: tokens.color.accent,
            ),
            SizedBox(height: tokens.spacing.xxs),
            Text(name, style: tokens.type.label),
          ],
        ),
      );
}
