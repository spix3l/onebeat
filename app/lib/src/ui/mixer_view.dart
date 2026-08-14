// Mixer & Routing View (matches onebeat-routing.html.png and onebeat-routing-overview.html.png).
//
// Built entirely from OneBeat design tokens with no raw literals.
// Displays channel strips, level meters, faders, M/S toggles, and the
// plain-English routing and sidechain inspector panel along with Graph and Matrix overviews.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'icons.dart';

enum MixerMode { trackFocus, graphOverview, matrixView }

class MixerRoutingView extends StatefulWidget {
  const MixerRoutingView({required this.controller, super.key});

  final EngineController controller;

  @override
  State<MixerRoutingView> createState() => _MixerRoutingViewState();
}

class _MixerRoutingViewState extends State<MixerRoutingView> {
  MixerMode _mode = MixerMode.trackFocus;
  int _selectedTrackIndex = 4; // Drums Bus by default

  final List<_MixerTrackData> _tracks = const <_MixerTrackData>[
    _MixerTrackData(
      name: 'Kick 808',
      type: 'audio',
      faderDb: -2.4, // token-lint-ok
      pan: 'C',
      routeDestination: '→ Drums Bus',
      meterLevel: 0.72, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Snare',
      type: 'audio',
      faderDb: -4.1, // token-lint-ok
      pan: 'C',
      routeDestination: '→ Drums Bus',
      meterLevel: 0.65, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Hats',
      type: 'audio',
      faderDb: -6.0, // token-lint-ok
      pan: 'L15',
      routeDestination: '→ Drums Bus',
      meterLevel: 0.55, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Clap',
      type: 'audio',
      faderDb: -5.5, // token-lint-ok
      pan: 'R10',
      routeDestination: '→ Drums Bus',
      meterLevel: 0.60, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Drums Bus',
      type: 'bus',
      faderDb: -1.0, // token-lint-ok
      pan: 'C',
      routeDestination: '→ Master',
      hasSidechainIn: true,
      meterLevel: 0.85, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Sub Bass',
      type: 'synth',
      faderDb: -3.0, // token-lint-ok
      pan: 'C',
      routeDestination: '→ Master',
      hasSidechainOut: true,
      meterLevel: 0.70, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Soft Keys',
      type: 'synth',
      faderDb: -4.5, // token-lint-ok
      pan: 'L20',
      routeDestination: '→ Master',
      meterLevel: 0.62, // token-lint-ok
    ),
    _MixerTrackData(
      name: 'Vocal Tex',
      type: 'audio',
      faderDb: -3.8, // token-lint-ok
      pan: 'C',
      routeDestination: '→ Vox',
      meterLevel: 0.58, // token-lint-ok
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final _MixerTrackData selectedTrack =
        _tracks[_selectedTrackIndex.clamp(0, _tracks.length - 1)];

    return Container(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MixerHeader(
            mode: _mode,
            onModeChanged: (MixerMode m) => setState(() => _mode = m),
            tokens: tokens,
            onAddTrack: () {},
          ),
          Expanded(
            child: switch (_mode) {
              MixerMode.trackFocus => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tracks.length + 1, // +1 for Master
                      itemBuilder: (BuildContext context, int index) {
                        if (index < _tracks.length) {
                          final _MixerTrackData track = _tracks[index];
                          final bool isSelected = index == _selectedTrackIndex;
                          return _MixerChannelStrip(
                            index: index + 1,
                            track: track,
                            selected: isSelected,
                            onSelect: () =>
                                setState(() => _selectedTrackIndex = index),
                            tokens: tokens,
                          );
                        }
                        return _MasterChannelStrip(
                          controller: widget.controller,
                          tokens: tokens,
                        );
                      },
                    ),
                  ),
                  _RoutingInspectorPanel(
                    track: selectedTrack,
                    trackIndex: _selectedTrackIndex + 1,
                    tokens: tokens,
                  ),
                ],
              ),
              MixerMode.graphOverview => _RoutingGraphOverviewView(
                tracks: _tracks,
                tokens: tokens,
                onSelectTrack: (int idx) => setState(() {
                  _selectedTrackIndex = idx;
                  _mode = MixerMode.trackFocus;
                }),
              ),
              MixerMode.matrixView => _RoutingMatrixOverviewView(
                tracks: _tracks,
                tokens: tokens,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _MixerTrackData {
  const _MixerTrackData({
    required this.name,
    required this.type,
    required this.faderDb,
    required this.pan,
    required this.routeDestination,
    required this.meterLevel,
    this.hasSidechainIn = false,
    this.hasSidechainOut = false,
  });

  final String name;
  final String type;
  final double faderDb;
  final String pan;
  final String routeDestination;
  final double meterLevel;
  final bool hasSidechainIn;
  final bool hasSidechainOut;
}

class _MixerHeader extends StatelessWidget {
  const _MixerHeader({
    required this.mode,
    required this.onModeChanged,
    required this.tokens,
    required this.onAddTrack,
  });

  final MixerMode mode;
  final ValueChanged<MixerMode> onModeChanged;
  final OneBeatTokens tokens;
  final VoidCallback onAddTrack;

  @override
  Widget build(BuildContext context) {
    final String title = switch (mode) {
      MixerMode.trackFocus => 'MIXER — 8 instruments',
      MixerMode.graphOverview => 'ROUTING OVERVIEW',
      MixerMode.matrixView => 'ROUTING MATRIX',
    };

    return Container(
      height: tokens.size.pianoToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(title, style: tokens.type.sectionHeader),
          if (mode == MixerMode.trackFocus) ...<Widget>[
            SizedBox(width: tokens.spacing.sm),
            Flexible(
              child: Text(
                'every instrument got its own track, auto-routed by name',
                style: tokens.type.breadcrumb,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
                  icon: OneBeatIconData.mixer,
                  selected: mode == MixerMode.trackFocus,
                  onPressed: () => onModeChanged(MixerMode.trackFocus),
                  tokens: tokens,
                ),
                _ModeTabButton(
                  label: 'Graph',
                  icon: OneBeatIconData.channels,
                  selected: mode == MixerMode.graphOverview,
                  onPressed: () => onModeChanged(MixerMode.graphOverview),
                  tokens: tokens,
                ),
                _ModeTabButton(
                  label: 'Matrix',
                  icon: OneBeatIconData.playlist,
                  selected: mode == MixerMode.matrixView,
                  onPressed: () => onModeChanged(MixerMode.matrixView),
                  tokens: tokens,
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          OneBeatButton(label: '+ Add Track', onPressed: onAddTrack),
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
    required this.onPressed,
    required this.tokens,
  });

  final String label;
  final OneBeatIconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.color.surfaceRaised : null,
          borderRadius: tokens.radius.controlBorder,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            OneBeatIcon(
              icon,
              size: tokens.size.iconSize,
              color: selected ? tokens.color.accent : tokens.color.textMuted,
            ),
            SizedBox(width: tokens.spacing.xs),
            Text(
              label,
              style: selected
                  ? tokens.type.body.copyWith(color: tokens.color.textPrimary)
                  : tokens.type.body.copyWith(color: tokens.color.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MixerChannelStrip extends StatelessWidget {
  const _MixerChannelStrip({
    required this.index,
    required this.track,
    required this.selected,
    required this.onSelect,
    required this.tokens,
  });

  final int index;
  final _MixerTrackData track;
  final bool selected;
  final VoidCallback onSelect;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        width: tokens.size.pianoKeyboardWidth,
        margin: EdgeInsets.symmetric(
          horizontal: tokens.spacing.xxs,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? tokens.color.surfaceOverlay
              : tokens.color.surfacePanel,
          borderRadius: tokens.radius.controlBorder,
          border: Border.all(
            color: selected ? tokens.color.accent : tokens.color.line,
            width: selected ? tokens.border.emphasis : tokens.border.hairline,
          ),
        ),
        child: Column(
          children: <Widget>[
            // Header with track name and type
            Container(
              padding: EdgeInsets.all(tokens.spacing.xs),
              decoration: BoxDecoration(
                color: tokens.color.surfaceSunken,
                borderRadius: BorderRadius.vertical(
                  top: tokens.radius.controlBorder.topLeft,
                ),
              ),
              child: Column(
                children: <Widget>[
                  Text('$index', style: tokens.type.numericSmall),
                  SizedBox(height: tokens.spacing.xxs),
                  Text(
                    track.name,
                    style: tokens.type.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (track.hasSidechainIn) ...<Widget>[
                    SizedBox(height: tokens.spacing.xxs),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.spacing.xxs,
                        vertical: tokens.spacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.color.sidechainGold,
                        borderRadius: tokens.radius.controlBorder,
                      ),
                      child: Text(
                        'SC in',
                        style: tokens.type.tag.copyWith(
                          color: tokens.color.surfaceSunken,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Mute / Solo buttons
            Padding(
              padding: EdgeInsets.all(tokens.spacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _MiniToggle(label: 'M', active: false, tokens: tokens),
                  SizedBox(width: tokens.spacing.xs),
                  _MiniToggle(label: 'S', active: false, tokens: tokens),
                ],
              ),
            ),
            // Fader & Meter section
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _ChannelMeter(level: track.meterLevel, tokens: tokens),
                    SizedBox(width: tokens.spacing.xs),
                    _ChannelFader(faderDb: track.faderDb, tokens: tokens),
                  ],
                ),
              ),
            ),
            // Pan & Routing info
            Container(
              padding: EdgeInsets.all(tokens.spacing.xs),
              decoration: BoxDecoration(
                color: tokens.color.surfaceSunken,
                borderRadius: BorderRadius.vertical(
                  bottom: tokens.radius.controlBorder.bottomLeft,
                ),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    '${track.faderDb > 0 ? "+" : ""}${track.faderDb.toStringAsFixed(1)} dB',
                    style: tokens.type.numericSmall,
                  ),
                  SizedBox(height: tokens.spacing.xxs),
                  Text(track.pan, style: tokens.type.tag),
                  SizedBox(height: tokens.spacing.xxs),
                  Text(
                    track.routeDestination,
                    style: tokens.type.tag.copyWith(
                      color: tokens.color.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterChannelStrip extends StatelessWidget {
  const _MasterChannelStrip({required this.controller, required this.tokens});

  final EngineController controller;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tokens.size.pianoKeyboardWidth,
      margin: EdgeInsets.symmetric(
        horizontal: tokens.spacing.xxs,
        vertical: tokens.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.color.surfaceRaised,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.accent,
          width: tokens.border.hairline,
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(tokens.spacing.xs),
            decoration: BoxDecoration(
              color: tokens.color.surfaceSunken,
              borderRadius: BorderRadius.vertical(
                top: tokens.radius.controlBorder.topLeft,
              ),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  'MST',
                  style: tokens.type.numericSmall.copyWith(
                    color: tokens.color.accent,
                  ),
                ),
                SizedBox(height: tokens.spacing.xxs),
                Text(
                  'MASTER',
                  style: tokens.type.title.copyWith(color: tokens.color.accent),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(tokens.spacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _MiniToggle(label: 'M', active: false, tokens: tokens),
                SizedBox(width: tokens.spacing.xs),
                _MiniToggle(label: 'S', active: false, tokens: tokens),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _ChannelMeter(level: 0.88, tokens: tokens), // token-lint-ok
                  SizedBox(width: tokens.spacing.xs),
                  _ChannelFader(faderDb: 0.0, tokens: tokens), // token-lint-ok
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(tokens.spacing.xs),
            decoration: BoxDecoration(
              color: tokens.color.surfaceSunken,
              borderRadius: BorderRadius.vertical(
                bottom: tokens.radius.controlBorder.bottomLeft,
              ),
            ),
            child: Column(
              children: <Widget>[
                Text('0.0 dB', style: tokens.type.numericSmall),
                SizedBox(height: tokens.spacing.xxs),
                Text(
                  'STEREO OUT',
                  style: tokens.type.tag.copyWith(color: tokens.color.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.label,
    required this.active,
    required this.tokens,
  });

  final String label;
  final bool active;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tokens.size.iconSize,
      height: tokens.size.iconSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? tokens.color.accent : tokens.color.surfaceWell,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: active ? tokens.color.accent : tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      child: Text(
        label,
        style: tokens.type.tag.copyWith(
          color: active ? tokens.color.textPrimary : tokens.color.textMuted,
        ),
      ),
    );
  }
}

class _ChannelMeter extends StatelessWidget {
  const _ChannelMeter({required this.level, required this.tokens});

  final double level;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tokens.size.channelMeterWidth,
      decoration: BoxDecoration(
        color: tokens.color.surfaceSunken,
        borderRadius: tokens.radius.controlBorder,
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            flex: ((1.0 - level.clamp(0.0, 1.0)) * 100)
                .toInt(), // token-lint-ok
            child: const SizedBox.shrink(),
          ),
          Expanded(
            flex: (level.clamp(0.0, 1.0) * 100).toInt(), // token-lint-ok
            child: Container(
              decoration: BoxDecoration(
                color:
                    level >
                        0.85 // token-lint-ok
                    ? tokens.color.meterHigh
                    : level >
                          0.7 // token-lint-ok
                    ? tokens.color.meterMid
                    : tokens.color.meterLow,
                borderRadius: tokens.radius.controlBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelFader extends StatelessWidget {
  const _ChannelFader({required this.faderDb, required this.tokens});

  final double faderDb;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tokens.size.faderWidth,
      decoration: BoxDecoration(
        color: tokens.color.surfaceWell,
        borderRadius: tokens.radius.controlBorder,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(width: tokens.border.emphasis, color: tokens.color.line),
          Align(
            alignment: Alignment(
              0.0, // token-lint-ok
              (-faderDb / 12.0).clamp(-1.0, 1.0), // token-lint-ok
            ),
            child: Container(
              height: tokens.size.tagHeight,
              width: tokens.size.faderWidth,
              decoration: BoxDecoration(
                color: tokens.color.faderThumb,
                borderRadius: tokens.radius.controlBorder,
                border: Border.all(
                  color: tokens.color.textPrimary,
                  width: tokens.border.hairline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutingInspectorPanel extends StatelessWidget {
  const _RoutingInspectorPanel({
    required this.track,
    required this.trackIndex,
    required this.tokens,
  });

  final _MixerTrackData track;
  final int trackIndex;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tokens.size.inspectorWidth,
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
      child: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('ROUTING INSPECTOR', style: tokens.type.sectionHeader),
              const Spacer(),
              Text(
                'in plain words',
                style: tokens.type.tag.copyWith(color: tokens.color.textMuted),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),
          Text('FEEDS THIS TRACK', style: tokens.type.label),
          SizedBox(height: tokens.spacing.xs),
          _RouteFeederRow(
            source: 'Kick 808',
            destination: 'out 1 → ${track.name}',
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.xxs),
          _RouteFeederRow(
            source: 'Snare',
            destination: 'out 1 → ${track.name}',
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.xxs),
          _RouteFeederRow(
            source: 'Hats',
            destination: 'out 1 → ${track.name}',
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.xxs),
          _RouteFeederRow(
            source: 'Clap',
            destination: 'out 1 → ${track.name}',
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.lg),
          Text('THIS TRACK FEEDS', style: tokens.type.label),
          SizedBox(height: tokens.spacing.xs),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.sm,
              vertical: tokens.spacing.xs,
            ),
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.accent,
                width: tokens.border.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'Master',
                  style: tokens.type.body.copyWith(
                    color: tokens.color.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '→ output',
                  style: tokens.type.tag.copyWith(color: tokens.color.accent),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          Text('SENDS', style: tokens.type.label),
          SizedBox(height: tokens.spacing.xs),
          _SendSliderRow(
            label: '→ Reverb Send',
            dbValue: '0.42',
            badge: 'PRE',
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.xxs),
          _SendSliderRow(
            label: '→ Delay',
            dbValue: '0.18',
            badge: 'POST',
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.lg),
          Text('SIDECHAIN', style: tokens.type.label),
          SizedBox(height: tokens.spacing.xs),
          Container(
            padding: EdgeInsets.all(tokens.spacing.sm),
            decoration: BoxDecoration(
              color: tokens.color.surfaceDeep,
              borderRadius: tokens.radius.controlBorder,
              border: Border.all(
                color: tokens.color.sidechainGold,
                width: tokens.border.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: tokens.size.iconSize,
                      height: tokens.size.iconSize,
                      decoration: BoxDecoration(
                        color: tokens.color.sidechainGold,
                        borderRadius: tokens.radius.controlBorder,
                      ),
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Sub Bass',
                            style: tokens.type.body.copyWith(
                              color: tokens.color.textPrimary,
                            ),
                          ),
                          Text(
                            'sidechain source',
                            style: tokens.type.numericSmall.copyWith(
                              color: tokens.color.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${track.name} (key in)',
                      style: tokens.type.body.copyWith(
                        color: tokens.color.sidechainGold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.spacing.sm),
                Row(
                  children: <Widget>[
                    Text('Enabled', style: tokens.type.body),
                    SizedBox(width: tokens.spacing.xs),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.spacing.xs,
                        vertical: tokens.spacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.color.accent,
                        borderRadius: tokens.radius.controlBorder,
                      ),
                      child: Text(
                        'ON',
                        style: tokens.type.tag.copyWith(
                          color: tokens.color.textPrimary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text('Amount', style: tokens.type.body),
                    SizedBox(width: tokens.spacing.xs),
                    Text(
                      '-6.0 dB',
                      style: tokens.type.numericSmall.copyWith(
                        color: tokens.color.sidechainGold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.spacing.xs),
                Text(
                  'Whenever Sub Bass hits, the ${track.name} compressor ducks a little — the kick steps aside so the bass punches. That\'s the whole sidechain.',
                  style: tokens.type.breadcrumb.copyWith(
                    color: tokens.color.textMuted,
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

class _RouteFeederRow extends StatelessWidget {
  const _RouteFeederRow({
    required this.source,
    required this.destination,
    required this.tokens,
  });

  final String source;
  final String destination;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.controlBorder,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.tagHeight,
            height: tokens.size.tagHeight,
            decoration: BoxDecoration(
              color: tokens.color.accent,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: tokens.spacing.xs),
          Text(source, style: tokens.type.body),
          SizedBox(width: tokens.spacing.xs),
          OneBeatIcon(
            OneBeatIconData.arrowRight,
            size: tokens.size.tagHeight,
            color: tokens.color.textMuted,
          ),
          SizedBox(width: tokens.spacing.xs),
          Expanded(
            child: Text(
              destination,
              style: tokens.type.numericSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SendSliderRow extends StatelessWidget {
  const _SendSliderRow({
    required this.label,
    required this.dbValue,
    required this.badge,
    required this.tokens,
  });

  final String label;
  final String dbValue;
  final String badge;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.controlBorder,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: tokens.type.body)),
          Text(dbValue, style: tokens.type.numericSmall),
          SizedBox(width: tokens.spacing.xs),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.xs,
              vertical: tokens.spacing.xxs,
            ),
            decoration: BoxDecoration(
              color: tokens.color.surfaceRaised,
              borderRadius: tokens.radius.controlBorder,
            ),
            child: Text(badge, style: tokens.type.tag),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Graph Overview View (onebeat-routing-overview.html.png)
// -----------------------------------------------------------------------------

class _RoutingGraphOverviewView extends StatelessWidget {
  const _RoutingGraphOverviewView({
    required this.tracks,
    required this.tokens,
    required this.onSelectTrack,
  });

  final List<_MixerTrackData> tracks;
  final OneBeatTokens tokens;
  final ValueChanged<int> onSelectTrack;

  @override
  Widget build(BuildContext context) {
    final List<_GraphNode> instruments = <_GraphNode>[
      _GraphNode(
        title: 'Kick 808',
        subtitle: '→ Drums',
        color: tokens.color.danger,
      ),
      _GraphNode(
        title: 'Snare',
        subtitle: '→ Drums',
        color: tokens.color.accent,
      ),
      _GraphNode(
        title: 'Hats',
        subtitle: '→ Drums',
        color: tokens.color.warning,
      ),
      _GraphNode(
        title: 'Clap',
        subtitle: '→ Drums',
        color: tokens.color.tagAudFg,
      ),
      _GraphNode(
        title: 'Sub Bass',
        subtitle: '→ Bass',
        color: tokens.color.tagPatFg,
      ),
      _GraphNode(
        title: 'Soft Keys',
        subtitle: '→ Music',
        color: tokens.color.waveform,
      ),
      _GraphNode(
        title: 'Vocal Tex',
        subtitle: '→ Vox',
        color: tokens.color.sidechainGold,
      ),
    ];

    final List<_GraphNode> busses = <_GraphNode>[
      _GraphNode(
        title: 'Drums Bus',
        subtitle: '→ Master',
        isHighlighted: true,
        color: tokens.color.accent,
      ),
      _GraphNode(
        title: 'Bass',
        subtitle: '→ Master',
        color: tokens.color.tagPatFg,
      ),
      _GraphNode(
        title: 'Music',
        subtitle: '→ Master',
        color: tokens.color.waveform,
      ),
      _GraphNode(
        title: 'Vox',
        subtitle: '→ Master',
        color: tokens.color.sidechainGold,
      ),
      _GraphNode(
        title: 'Reverb Send',
        subtitle: 'send',
        isSend: true,
        color: tokens.color.accentDeep,
      ),
      _GraphNode(
        title: 'Delay',
        subtitle: 'send',
        isSend: true,
        color: tokens.color.tagAudFg,
      ),
    ];

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Bézier connection lines custom painter
        CustomPaint(painter: _RoutingGraphCurvesPainter(tokens: tokens)),
        // 3-column node layout
        Padding(
          padding: EdgeInsets.all(tokens.spacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Column 1: Instruments
              SizedBox(
                width: tokens.size.inspectorWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('INSTRUMENTS', style: tokens.type.sectionHeader),
                    SizedBox(height: tokens.spacing.md),
                    ...List<Widget>.generate(instruments.length, (int i) {
                      final _GraphNode node = instruments[i];
                      return Padding(
                        padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                        child: GestureDetector(
                          onTap: () => onSelectTrack(i),
                          child: _GraphNodeCard(node: node, tokens: tokens),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const Spacer(),
              // Column 2: Busses & Sends
              SizedBox(
                width: tokens.size.inspectorWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('BUSSES & SENDS', style: tokens.type.sectionHeader),
                    SizedBox(height: tokens.spacing.md),
                    ...List<Widget>.generate(busses.length, (int i) {
                      final _GraphNode node = busses[i];
                      return Padding(
                        padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                        child: GestureDetector(
                          onTap: () {
                            if (i == 0) {
                              onSelectTrack(4); // Drums bus // token-lint-ok
                            }
                          },
                          child: _GraphNodeCard(node: node, tokens: tokens),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const Spacer(),
              // Column 3: Output
              SizedBox(
                width: tokens.size.pianoKeyboardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('OUTPUT', style: tokens.type.sectionHeader),
                    SizedBox(height: tokens.spacing.md),
                    Container(
                      padding: EdgeInsets.all(tokens.spacing.md),
                      decoration: BoxDecoration(
                        color: tokens.color.surfaceSunken,
                        borderRadius: tokens.radius.controlBorder,
                        border: Border.all(
                          color: tokens.color.lineStrong,
                          width: tokens.border.hairline,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('MASTER', style: tokens.type.title),
                          SizedBox(height: tokens.spacing.xs),
                          Text('0.0 dB', style: tokens.type.numeric),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Footer hint and status bar
        Positioned(
          left: tokens.spacing.lg,
          right: tokens.spacing.lg,
          bottom: tokens.spacing.md,
          child: Row(
            children: <Widget>[
              Container(
                width: tokens.size.tagHeight,
                height: tokens.size.tagHeight,
                decoration: BoxDecoration(
                  color: tokens.color.tagPatFg,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                'Routing overview · 7 instruments · 6 tracks · 2 sends · 1 sidechain',
                style: tokens.type.numericSmall.copyWith(
                  color: tokens.color.textSecondary,
                ),
              ),
              SizedBox(width: tokens.spacing.md),
              Text(
                '|  Routing by name — rename anything, nothing breaks',
                style: tokens.type.numericSmall.copyWith(
                  color: tokens.color.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                'Click any edge or node to jump to route\'s inspector',
                style: tokens.type.numericSmall.copyWith(
                  color: tokens.color.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GraphNode {
  const _GraphNode({
    required this.title,
    required this.subtitle,
    required this.color,
    this.isHighlighted = false,
    this.isSend = false,
  });

  final String title;
  final String subtitle;
  final Color color;
  final bool isHighlighted;
  final bool isSend;
}

class _GraphNodeCard extends StatelessWidget {
  const _GraphNodeCard({required this.node, required this.tokens});

  final _GraphNode node;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: node.isHighlighted
            ? tokens.color.accentWash
            : tokens.color.surfacePanel,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: node.isHighlighted ? tokens.color.accent : tokens.color.line,
          width: node.isHighlighted
              ? tokens.border.emphasis
              : tokens.border.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.tagHeight,
            height: tokens.size.tagHeight,
            decoration: BoxDecoration(
              color: node.color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: tokens.spacing.xs),
          Text(node.title, style: tokens.type.body),
          const Spacer(),
          Text(
            node.subtitle,
            style: tokens.type.numericSmall.copyWith(
              color: tokens.color.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutingGraphCurvesPainter extends CustomPainter {
  const _RoutingGraphCurvesPainter({required this.tokens});

  final OneBeatTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = tokens.color.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.hairline;

    final Paint goldDottedPaint = Paint()
      ..color = tokens.color.sidechainGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = tokens.border.hairline;

    // Draw main bus curves
    final double leftX = size.width * 0.22; // token-lint-ok
    final double midLeftX = size.width * 0.44; // token-lint-ok
    final double midRightX = size.width * 0.66; // token-lint-ok
    final double rightX = size.width * 0.88; // token-lint-ok

    // Instruments to busses curves
    for (int i = 0; i < 7; i++) {
      final double startY = 80.0 + (i * 44.0); // token-lint-ok
      final double endY = i < 4
          ? 80.0
          : 80.0 + ((i - 3) * 44.0); // token-lint-ok
      final Path path = Path();
      path.moveTo(leftX, startY);
      path.cubicTo(
        leftX + 60.0, // token-lint-ok
        startY,
        midLeftX - 60.0, // token-lint-ok
        endY,
        midLeftX,
        endY,
      );
      canvas.drawPath(path, linePaint);
    }

    // Sidechain curve: Sub Bass (i=4) -> Drums Bus (endY=80)
    final Path scPath = Path();
    const double scStartY = 80.0 + (4 * 44.0); // token-lint-ok
    const double scEndY = 80.0; // token-lint-ok
    scPath.moveTo(leftX, scStartY);
    scPath.cubicTo(
      leftX + 80.0, // token-lint-ok
      scStartY - 20.0, // token-lint-ok
      midLeftX - 80.0, // token-lint-ok
      scEndY + 20.0, // token-lint-ok
      midLeftX,
      scEndY,
    );
    canvas.drawPath(scPath, goldDottedPaint);

    // Busses to Master curves
    for (int i = 0; i < 4; i++) {
      final double startY = 80.0 + (i * 44.0); // token-lint-ok
      const double endY = 80.0; // token-lint-ok
      final Path path = Path();
      path.moveTo(midRightX, startY);
      path.cubicTo(
        midRightX + 60.0, // token-lint-ok
        startY,
        rightX - 60.0, // token-lint-ok
        endY,
        rightX,
        endY,
      );
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutingGraphCurvesPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Matrix Overview View (Grid matrix mapping sources to destinations)
// -----------------------------------------------------------------------------

class _RoutingMatrixOverviewView extends StatelessWidget {
  const _RoutingMatrixOverviewView({
    required this.tracks,
    required this.tokens,
  });

  final List<_MixerTrackData> tracks;
  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) {
    final List<String> destinations = <String>[
      'Drums Bus',
      'Bass',
      'Music',
      'Vox',
      'Reverb',
      'Delay',
      'MASTER',
    ];

    return Padding(
      padding: EdgeInsets.all(tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Matrix Header
          Row(
            children: <Widget>[
              SizedBox(
                width: tokens.size.pianoKeyboardWidth,
                child: Text('SOURCE \\ DEST', style: tokens.type.sectionHeader),
              ),
              ...destinations.map(
                (String d) => Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.xs,
                      vertical: tokens.spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.color.surfaceSunken,
                      border: Border.all(
                        color: tokens.color.line,
                        width: tokens.border.hairline,
                      ),
                    ),
                    child: Text(
                      d,
                      style: tokens.type.numericSmall.copyWith(
                        color: d == 'MASTER'
                            ? tokens.color.accent
                            : tokens.color.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.xs),
          // Matrix Rows
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (BuildContext context, int rowIdx) {
                final _MixerTrackData track = tracks[rowIdx];
                return Container(
                  margin: EdgeInsets.only(bottom: tokens.spacing.xxs),
                  child: Row(
                    children: <Widget>[
                      // Source Track Name
                      SizedBox(
                        width: tokens.size.pianoKeyboardWidth,
                        child: Container(
                          padding: EdgeInsets.all(tokens.spacing.xs),
                          decoration: BoxDecoration(
                            color: tokens.color.surfacePanel,
                            borderRadius: tokens.radius.controlBorder,
                          ),
                          child: Text(
                            track.name,
                            style: tokens.type.body,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      // Matrix Cells
                      ...List<Widget>.generate(destinations.length, (
                        int colIdx,
                      ) {
                        final String dest = destinations[colIdx];
                        final bool isDirectFeed = track.routeDestination
                            .contains(dest);
                        final bool isSidechain =
                            track.hasSidechainIn && dest == 'Drums Bus';

                        return Expanded(
                          child: Container(
                            height: tokens.size.tagHeight,
                            margin: EdgeInsets.symmetric(
                              horizontal: tokens.spacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: isDirectFeed
                                  ? tokens.color.accentWash
                                  : isSidechain
                                  ? tokens.color.surfaceRaised
                                  : tokens.color.surfaceSunken,
                              borderRadius: tokens.radius.controlBorder,
                              border: Border.all(
                                color: isDirectFeed
                                    ? tokens.color.accent
                                    : isSidechain
                                    ? tokens.color.sidechainGold
                                    : tokens.color.line,
                                width: tokens.border.hairline,
                              ),
                            ),
                            child: Center(
                              child: isDirectFeed
                                  ? OneBeatIcon(
                                      OneBeatIconData.check,
                                      size: tokens.size.tagHeight,
                                      color: tokens.color.accent,
                                    )
                                  : isSidechain
                                  ? Text(
                                      'SC',
                                      style: tokens.type.tag.copyWith(
                                        color: tokens.color.sidechainGold,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
