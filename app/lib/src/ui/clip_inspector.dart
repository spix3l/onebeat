// The clip inspector (OB-3-13 §3).
//
// Start, length, offset, loop mode, mute and transpose for the selected clip,
// plus `Make unique` sitting **beside** the transforms rather than in a menu
// somewhere else. That placement is the point of D-M3: varying a clip without
// cloning is the default path, and cloning is the explicit one you reach for
// when varying is not enough. Putting them side by side is what makes the
// choice legible.
//
// Reserved transform fields (velocity scale, nudge, probability) are *absent*,
// not disabled: DM-Q3 keeps them in the schema, and OB-3-13 §5 is explicit that
// no dead UI ships for them.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'action_registry.dart';
import 'arrangement_store.dart';
import 'controls.dart';
import 'pattern_store.dart';
import 'piano_roll_store.dart' show ticksPerBar, ticksPerQuarter;

class ClipInspector extends StatelessWidget {
  const ClipInspector({
    required this.store,
    required this.patterns,
    super.key,
  });

  final ArrangementStore store;
  final PatternStore patterns;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: tokens.size.clipInspectorWidth,
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(
          left: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: _buildBody(context, tokens),
      ),
    );
  }

  Widget _buildBody(BuildContext context, OneBeatTokens tokens) {
    final int count = store.selectedClipIds.length;
    if (count == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('CLIP', style: tokens.type.label),
          SizedBox(height: tokens.spacing.sm),
          Text(
            'Select a clip to window, loop or transpose it.',
            style: tokens.type.body.copyWith(color: tokens.color.textMuted),
          ),
        ],
      );
    }

    // A multi-selection gets Make unique and nothing else: the per-field
    // controls would have to invent a "mixed" state for every value, and the
    // one action that genuinely means something across a selection is the one
    // FR-SEQ-04 defines for it (one clone, all repointed).
    if (count > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$count CLIPS', style: tokens.type.label),
          SizedBox(height: tokens.spacing.md),
          _makeUniqueButton(tokens, store.selectedClipIds.toList()),
          SizedBox(height: tokens.spacing.sm),
          Text(
            ActionRegistry.byId('clip.makeUnique').description,
            style: tokens.type.label,
          ),
        ],
      );
    }

    final ArrangementClip? clip = store.selectedClip;
    if (clip == null || !clip.isPattern) {
      return Text('CLIP', style: tokens.type.label);
    }
    return _buildFields(tokens, clip);
  }

  Widget _buildFields(OneBeatTokens tokens, ArrangementClip clip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('CLIP', style: tokens.type.label),
        SizedBox(height: tokens.spacing.xs),
        Row(
          children: <Widget>[
            Container(
              width: tokens.size.swatchSize,
              height: tokens.size.swatchSize,
              decoration: BoxDecoration(
                color: projectColor(clip.color, tokens.color.accent),
                borderRadius: BorderRadius.all(tokens.radius.sm),
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: Text(
                clip.name,
                overflow: TextOverflow.ellipsis,
                style: tokens.type.title,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.xs),
        Text(
          clip.isShared
              ? 'Pattern used in ${clip.usageCount} clips'
              : 'Pattern used once',
          style: tokens.type.label,
        ),

        _divider(tokens),

        // Positions are shown in bars because that is how a musician reads an
        // arrangement; the model stays in ticks throughout.
        OneBeatStepper(
          key: actionKey('clip.start'),
          label: 'Start',
          value: _bars(clip.startTicks),
          suffix: ' bar',
          minimum: 0,
          onChanged: (int bars) =>
              store.setClipStart(clip.id, bars * ticksPerBar),
        ),
        SizedBox(height: tokens.spacing.sm),
        OneBeatStepper(
          key: actionKey('clip.length'),
          label: 'Length',
          value: _bars(clip.lengthTicks),
          suffix: ' bar',
          minimum: 1,
          onChanged: (int bars) =>
              store.resizeClip(clip.id, bars * ticksPerBar),
        ),
        SizedBox(height: tokens.spacing.sm),
        OneBeatStepper(
          key: actionKey('clip.offset'),
          label: 'Offset',
          value: _beats(clip.windowStartTicks),
          suffix: ' beat',
          minimum: 0,
          onChanged: (int beats) =>
              store.setClipWindowStart(clip.id, beats * ticksPerQuarter),
        ),
        SizedBox(height: tokens.spacing.xs),
        Text(
          ActionRegistry.byId('clip.offset').description,
          style: tokens.type.label,
        ),

        _divider(tokens),

        Row(
          children: <Widget>[
            Expanded(child: Text('Loop', style: tokens.type.label)),
            OneBeatToggle(
              key: actionKey('clip.loop'),
              label: clip.loop ? 'LOOP' : 'HOLD-OFF',
              value: clip.loop,
              tooltip: ActionRegistry.byId('clip.loop').description,
              onChanged: (bool value) =>
                  store.setClipLoop(clip.id, loop: value),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.sm),
        Row(
          children: <Widget>[
            Expanded(child: Text('Mute', style: tokens.type.label)),
            OneBeatToggle(
              key: actionKey('clip.mute'),
              label: clip.muted ? 'MUTED' : 'ON',
              value: clip.muted,
              activeColor: tokens.color.warning,
              onChanged: (_) => store.toggleClipMute(clip),
            ),
          ],
        ),

        _divider(tokens),

        OneBeatStepper(
          key: actionKey('clip.transpose'),
          label: 'Transpose',
          value: clip.transpose,
          suffix: ' st',
          minimum: -48,
          maximum: 48,
          onChanged: (int semitones) =>
              store.setClipTranspose(clip.id, semitones),
        ),
        SizedBox(height: tokens.spacing.xs),
        Text(
          'Non-destructive: the pattern is untouched, and only this clip '
          'sounds transposed.',
          style: tokens.type.label,
        ),

        SizedBox(height: tokens.spacing.md),
        _makeUniqueButton(tokens, <String>[clip.id]),
        SizedBox(height: tokens.spacing.xs),
        Text(
          clip.isShared
              ? ActionRegistry.byId('clip.makeUnique').description
              : 'This clip already has the pattern to itself.',
          style: tokens.type.label,
        ),
      ],
    );
  }

  Widget _makeUniqueButton(OneBeatTokens tokens, List<String> clipIds) =>
      SizedBox(
        width: double.infinity,
        child: OneBeatButton(
          key: actionKey('clip.makeUnique'),
          label: ActionRegistry.byId('clip.makeUnique').label,
          semanticLabel: ActionRegistry.byId('clip.makeUnique').tooltip,
          onPressed: () {
            patterns.makeUnique(clipIds);
            store.refresh();
          },
        ),
      );

  Widget _divider(OneBeatTokens tokens) => Padding(
    padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
    child: Container(
      height: tokens.border.hairline,
      color: tokens.color.line,
    ),
  );

  /// Rounded up: a clip that is one tick over a bar is shown as two, because
  /// showing "1" for something that plainly extends past the bar line is worse
  /// than being a rounding off.
  static int _bars(int ticks) =>
      ticks <= 0 ? 0 : ((ticks + ticksPerBar - 1) ~/ ticksPerBar);

  static int _beats(int ticks) => ticks ~/ ticksPerQuarter;
}
