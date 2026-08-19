// MixerBinding — wires mixer presentation and routing to the engine (UI-D-05).
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../core/meter_state.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import 'effect_rack.dart';
import 'mixer_screen.dart';
import 'mixer_screen_vm.dart';
import 'mixer_strip.dart';
import 'routing_panel.dart';

class MixerBinding extends StatefulWidget {
  const MixerBinding({
    required this.client,
    this.controller,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;

  @override
  State<MixerBinding> createState() => _MixerBindingState();
}

class _MixerBindingState extends State<MixerBinding> with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  bool _ownsController = false;

  int _selectedTrackIndex = 0;
  MixerMode _mode = MixerMode.trackFocus;
  final Set<String> _mutedInstrumentIds = <String>{};
  final Set<String> _soloedInstrumentIds = <String>{};
  final Map<String, double> _faders = <String, double>{};
  double _masterFader = 0.75;
  bool _masterMuted = false;
  bool _masterSoloed = false;

  /// Which insert has its parameters showing. One at a time: a chain of four
  /// expanded effects is taller than the panel and stops being readable at a
  /// glance. Held by slot ID rather than by index so it survives a reorder.
  String? _expandedEffectId;

  /// The mixer track the insert rack is editing. The strips are per instrument,
  /// so the track is the one the selected instrument routes into — and the
  /// master when the master strip is selected.
  String _selectedTrackId(List<ProjectInstrument> instruments) {
    if (_selectedTrackIndex < 0 || _selectedTrackIndex >= instruments.length) {
      for (final MixerTrackInfo track in widget.client.readMixerTracks()) {
        if (track.isMaster) return track.id;
      }
      return '';
    }
    return instruments[_selectedTrackIndex].routeId;
  }

  String _trackName(String trackId) {
    for (final MixerTrackInfo track in widget.client.readMixerTracks()) {
      if (track.id == trackId) return track.name;
    }
    return 'Master';
  }

  EffectRackVm _buildRackVm() {
    final List<ProjectInstrument> instruments = widget.client.readInstruments();
    final String trackId = _selectedTrackId(instruments);
    if (trackId.isEmpty) {
      return const EffectRackVm(
        trackName: '',
        slots: <EffectSlotVm>[],
        available: <EffectChoiceVm>[],
        enabled: false,
      );
    }

    final List<EffectSlotVm> slots = <EffectSlotVm>[
      for (final EffectInfo effect in widget.client.readMixerEffects(trackId))
        EffectSlotVm(
          id: effect.id,
          name: effect.name,
          bypassed: effect.bypassed,
          missing: effect.missing,
          expanded: effect.id == _expandedEffectId,
          // Parameters are read only for the slot that is showing them: the
          // rack repaints on every engine tick, and reading four chains'
          // worth of knobs to draw none of them is work for nothing.
          params: effect.id == _expandedEffectId
              ? <EffectParamVm>[
                  for (final HostedParameter param
                      in widget.client.readMixerEffectParams(trackId, effect.id))
                    EffectParamVm(
                      id: param.id,
                      name: param.name,
                      value: param.value,
                      display: param.display,
                      minimum: param.minimum,
                      maximum: param.maximum,
                    ),
                ]
              : const <EffectParamVm>[],
        ),
    ];

    return EffectRackVm(
      trackName: _trackName(trackId),
      slots: slots,
      available: <EffectChoiceVm>[
        for (final EffectDescriptor effect in widget.client.readBuiltinEffects())
          EffectChoiceVm(id: effect.id, name: effect.name, summary: effect.summary),
      ],
    );
  }

  void _withSelectedTrack(void Function(String trackId) action) {
    final String trackId = _selectedTrackId(widget.client.readInstruments());
    if (trackId.isEmpty) return;
    action(trackId);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = core.EngineController(
        client: widget.client,
        vsync: this,
        motion: OneBeatTokens.dark().motion,
      );
      _ownsController = true;
    }

    _controller.addListener(_onEngineChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onEngineChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  Color _resolveColor(int index, String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty) {
      final int parsed = int.tryParse(colorStr.replaceFirst('#', ''), radix: 16) ?? 0;
      if (parsed != 0) {
        return Color(0xFF000000 | parsed);
      }
    }
    return channelColors[index % channelColors.length];
  }

  MixerScreenVm _buildVm(OneBeatTokens tokens) {
    final List<ProjectInstrument> instruments = widget.client.readInstruments();
    final EngineSnapshot snapshot = _controller.snapshot;
    final double masterLevel =
        (dbToFraction(_controller.meter.left.levelDb) + dbToFraction(_controller.meter.right.levelDb)) / 2.0;

    final List<MixerStripVm> stripVms = <MixerStripVm>[
      for (int i = 0; i < instruments.length; i++)
        (() {
          final ProjectInstrument inst = instruments[i];
          final bool isSelected = i == _selectedTrackIndex;
          final bool muted = _mutedInstrumentIds.contains(inst.id) || inst.muted;
          final bool soloed = _soloedInstrumentIds.contains(inst.id);
          final double fader = _faders[inst.id] ?? 0.75;
          final Color color = _resolveColor(i, inst.color);

          // Simulated live activity if playing
          final double trackLevel = snapshot.playing && !muted
              ? (masterLevel * (0.6 + (i % 4) * 0.1)).clamp(0.0, 1.0)
              : 0.0;

          return MixerStripVm(
            name: inst.name,
            color: color,
            route: '→ Master',
            level: trackLevel,
            fader: fader,
            muted: muted,
            soloed: soloed,
            routeActive: isSelected,
            selected: isSelected,
            isMaster: false,
            sidechainIn: i == 4, // Visual badge per mockup
          );
        })(),
    ];

    final MixerStripVm masterStripVm = MixerStripVm(
      name: 'MASTER',
      color: tokens.color.accent,
      route: '0.0 dB',
      level: snapshot.playing ? masterLevel.clamp(0.0, 1.0) : 0.0,
      fader: _masterFader,
      muted: _masterMuted,
      soloed: _masterSoloed,
      routeActive: true,
      selected: _selectedTrackIndex == -1,
      isMaster: true,
    );

    // Selected track for routing panel
    final String selectedName = (_selectedTrackIndex >= 0 && _selectedTrackIndex < instruments.length)
        ? instruments[_selectedTrackIndex].name
        : 'Master';

    final RoutingPanelVm routingVm = RoutingPanelVm(
      trackName: selectedName,
      feeds: <FeedVm>[
        for (int i = 0; i < instruments.length.clamp(0, 4); i++)
          FeedVm(
            name: instruments[i].name,
            color: _resolveColor(i, instruments[i].color),
            routeText: 'out 1 → $selectedName',
          ),
      ],
      feedsInto: <FeedVm>[
        FeedVm(
          name: 'Master',
          color: channelColors[7],
          routeText: '→ output',
        ),
      ],
      sends: const <SendVm>[
        SendVm(
          name: '→ Reverb Send',
          value: 0.42,
          valueText: '0.42',
          pre: true,
        ),
        SendVm(
          name: '→ Delay',
          value: 0.18,
          valueText: '0.18',
          pre: false,
        ),
      ],
      caption: 'Feeds to stereo output with 2 auxiliary effect sends.',
      sidechain: _selectedTrackIndex == 4
          ? SidechainVm(
              sourceName: 'Sub Bass',
              sourceColor: channelColors[3],
              targetName: 'Drums Bus',
              targetCaption: 'compressor key input',
              amountText: '−6 dB',
              enabled: true,
            )
          : null,
    );

    return MixerScreenVm(
      title: 'MIXER — ${instruments.length} instruments',
      strips: stripVms,
      masterStrip: masterStripVm,
      selectedTrackIndex: _selectedTrackIndex,
      routingPanel: routingVm,
      mode: _mode,
    );
  }

  void _onToggleMute(int index) {
    if (index == -1) {
      setState(() => _masterMuted = !_masterMuted);
      return;
    }
    final List<ProjectInstrument> instruments = widget.client.readInstruments();
    if (index >= 0 && index < instruments.length) {
      final String id = instruments[index].id;
      final bool nowMuted = !_mutedInstrumentIds.contains(id);
      setState(() {
        if (nowMuted) {
          _mutedInstrumentIds.add(id);
        } else {
          _mutedInstrumentIds.remove(id);
        }
      });
      widget.client.setInstrumentMuted(id, muted: nowMuted);
    }
  }

  void _onToggleSolo(int index) {
    if (index == -1) {
      setState(() => _masterSoloed = !_masterSoloed);
      return;
    }
    final List<ProjectInstrument> instruments = widget.client.readInstruments();
    if (index >= 0 && index < instruments.length) {
      final String id = instruments[index].id;
      setState(() {
        if (_soloedInstrumentIds.contains(id)) {
          _soloedInstrumentIds.remove(id);
        } else {
          _soloedInstrumentIds.add(id);
        }
      });
    }
  }

  void _onFader(int index, double value) {
    if (index == -1) {
      setState(() => _masterFader = value);
      widget.client.setMasterGain(value);
      return;
    }
    final List<ProjectInstrument> instruments = widget.client.readInstruments();
    if (index >= 0 && index < instruments.length) {
      final String id = instruments[index].id;
      setState(() => _faders[id] = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final MixerScreenVm vm = _buildVm(tokens);

    return MixerScreen(
      vm: vm,
      onSelectTrack: (int idx) => setState(() {
        _selectedTrackIndex = idx;
        // The expanded slot belongs to the track that was showing; keeping it
        // would expand an unrelated insert on the new one.
        _expandedEffectId = null;
      }),
      onToggleMute: _onToggleMute,
      onToggleSolo: _onToggleSolo,
      onFader: _onFader,
      onModeChanged: (MixerMode mode) => setState(() => _mode = mode),
      effectRack: ObEffectRack(
        vm: _buildRackVm(),
        onAdd: (String pluginId) =>
            _withSelectedTrack((String track) => widget.client.addMixerEffect(track, pluginId)),
        onRemove: (String effectId) => _withSelectedTrack((String track) {
          widget.client.removeMixerEffect(track, effectId);
          if (_expandedEffectId == effectId) _expandedEffectId = null;
        }),
        onToggleBypass: (String effectId) => _withSelectedTrack((String track) {
          final bool bypassed = widget.client
              .readMixerEffects(track)
              .firstWhere((EffectInfo e) => e.id == effectId)
              .bypassed;
          widget.client.setMixerEffectBypassed(track, effectId, bypassed: !bypassed);
        }),
        onToggleExpanded: (String effectId) =>
            setState(() => _expandedEffectId = _expandedEffectId == effectId ? null : effectId),
        onMove: (String effectId, int index) =>
            _withSelectedTrack((String track) => widget.client.moveMixerEffect(track, effectId, index)),
        onParamChanged: (String effectId, int paramId, double value) => _withSelectedTrack(
          (String track) => widget.client.setMixerEffectParam(track, effectId, paramId, value),
        ),
      ),
    );
  }
}
