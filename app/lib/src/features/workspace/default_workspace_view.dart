// DefaultWorkspaceView — the initial/empty project arrangement view (UI-C-07 / UI-D-01).
//
// Dual-pane layout: Playlist in the top half with lane track headers, ruler,
// and clip empty-state; Channel Rack in the bottom half with its instrument
// empty-state. Pure presentational widget.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../ui_kit/button.dart';
import '../../ui_kit/empty_state.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/prose.dart';

@immutable
class DefaultWorkspaceVm {
  const DefaultWorkspaceVm({
    this.playlistTitle = 'PLAYLIST',
    this.playlistSubtitle = 'nothing here yet',
    this.rackTitle = 'CHANNEL RACK — Pattern 1 (empty)',
    this.rackSubtitle = 'a step is a note',
  });

  final String playlistTitle;
  final String playlistSubtitle;
  final String rackTitle;
  final String rackSubtitle;
}

class DefaultWorkspaceView extends StatelessWidget {
  const DefaultWorkspaceView({
    required this.vm,
    this.onInsertPatternClip,
    this.onDragAudio,
    this.onAddInstrument,
    this.onBrowseBuiltins,
    this.onAddLane,
    super.key,
  });

  final DefaultWorkspaceVm vm;
  final VoidCallback? onInsertPatternClip;
  final VoidCallback? onDragAudio;
  final VoidCallback? onAddInstrument;
  final VoidCallback? onBrowseBuiltins;
  final VoidCallback? onAddLane;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return ColoredBox(
      color: color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: _PlaylistPane(
              title: vm.playlistTitle,
              subtitle: vm.playlistSubtitle,
              onInsertPatternClip: onInsertPatternClip,
              onDragAudio: onDragAudio,
              onAddLane: onAddLane,
            ),
          ),
          Container(
            height: tokens.border.hairline,
            color: color.lineStrong,
          ),
          Expanded(
            flex: 2,
            child: _ChannelRackPane(
              title: vm.rackTitle,
              subtitle: vm.rackSubtitle,
              onAddInstrument: onAddInstrument,
              onBrowseBuiltins: onBrowseBuiltins,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistPane extends StatelessWidget {
  const _PlaylistPane({
    required this.title,
    required this.subtitle,
    this.onInsertPatternClip,
    this.onDragAudio,
    this.onAddLane,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onInsertPatternClip;
  final VoidCallback? onDragAudio;
  final VoidCallback? onAddLane;

  static const ObEmptyStateVm _clipEmptyVm = ObEmptyStateVm(
    icon: ObKitGlyphKind.grid,
    heading: 'Add your first clip',
    body: <ObProseRun>[
      ObProseRun(
        "Place a pattern you've made, or drop an audio file straight in from Finder.\nClips reference patterns — edit once, it updates everywhere.",
      ),
    ],
    footnote: 'or press ⌘R · the menu bar has it too',
  );

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PaneHeader(title: title, subtitle: subtitle),
        Container(
          height: tokens.border.hairline,
          color: color.line,
        ),
        const _TimelineRuler(),
        Container(
          height: tokens.border.hairline,
          color: color.line,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _LaneHeaderColumn(onAddLane: onAddLane),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(tokens.spacing.sm),
                      child: ObEmptyState(
                        vm: _clipEmptyVm,
                        actions: <Widget>[
                          ObButton(
                            label: 'Insert pattern clip',
                            icon: ObKitGlyphKind.plus,
                            tone: ObButtonTone.primary,
                            onTap: onInsertPatternClip,
                          ),
                          ObButton(
                            label: 'Drag audio here',
                            icon: ObKitGlyphKind.waveform,
                            tone: ObButtonTone.secondary,
                            onTap: onDragAudio,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelRackPane extends StatelessWidget {
  const _ChannelRackPane({
    required this.title,
    required this.subtitle,
    this.onAddInstrument,
    this.onBrowseBuiltins,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onAddInstrument;
  final VoidCallback? onBrowseBuiltins;

  static const ObEmptyStateVm _rackEmptyVm = ObEmptyStateVm(
    icon: ObKitGlyphKind.note,
    heading: 'Add an instrument to Pattern 1',
    body: <ObProseRun>[
      ObProseRun(
        'Patterns hold notes per instrument. Add your first channel and the step grid\n+ piano roll light up together.',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PaneHeader(title: title, subtitle: subtitle),
        Container(
          height: tokens.border.hairline,
          color: color.line,
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(tokens.spacing.sm),
                child: ObEmptyState(
                  vm: _rackEmptyVm,
                  actions: <Widget>[
                    ObButton(
                      label: 'Add instrument',
                      icon: ObKitGlyphKind.plus,
                      tone: ObButtonTone.primary,
                      onTap: onAddInstrument,
                    ),
                    ObButton(
                      label: 'Browse built-ins',
                      icon: ObKitGlyphKind.folder,
                      tone: ObButtonTone.secondary,
                      onTap: onBrowseBuiltins,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.playlistHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      color: color.surfacePanel,
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: tokens.type.sectionHeader.copyWith(
              color: color.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            subtitle,
            style: tokens.type.menu.copyWith(color: color.textMuted),
          ),
        ],
      ),
    );
  }
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler();

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      height: tokens.size.playlistRulerHeight,
      color: color.surfaceSunken,
      padding: EdgeInsets.only(left: tokens.size.laneHeaderWidth),
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: <Widget>[
              for (final int bar in <int>[1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15, 17, 19, 21, 23, 25])
                Container(
                  width: tokens.size.playlistPxPerBar * 2,
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.only(left: tokens.spacing.xs),
                  child: Text(
                    '$bar',
                    style: tokens.type.listRowMeta.copyWith(color: color.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaneHeaderColumn extends StatelessWidget {
  const _LaneHeaderColumn({this.onAddLane});

  final VoidCallback? onAddLane;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ColorTokens color = tokens.color;

    return Container(
      width: tokens.size.laneHeaderWidth,
      decoration: BoxDecoration(
        color: color.surfaceSunken,
        border: Border(
          right: BorderSide(
            color: color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: tokens.size.playlistLaneHeight,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: color.line,
                  width: tokens.border.hairline,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text('1', style: tokens.type.listRowMeta),
                SizedBox(width: tokens.spacing.sm),
                GestureDetector(
                  onTap: onAddLane,
                  child: Container(
                    width: tokens.size.toggleChipSize,
                    height: tokens.size.toggleChipSize,
                    decoration: BoxDecoration(
                      color: color.surfaceWell,
                      borderRadius: tokens.radius.controlBorder,
                      border: Border.all(
                        color: color.lineStrong,
                        width: tokens.border.hairline,
                      ),
                    ),
                    child: Center(
                      child: ObKitGlyph(
                        kind: ObKitGlyphKind.plus,
                        color: color.textSecondary,
                        size: ObKitGlyphSize.inline,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text('Lane 1', style: tokens.type.listRow),
                ),
                Text(
                  'empty',
                  style: tokens.type.listRowMeta.copyWith(color: color.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
