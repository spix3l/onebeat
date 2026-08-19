// MixerBinding — wires mixer presentation and routing to the engine (UI-D-05).
import 'dart:math' as math;

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

  /// The model, read once per change rather than once per frame.
  ///
  /// The engine's ticker rebuilds this widget every frame so the meters move;
  /// the rack and the mixer behind it only move when the user edits something.
  /// Reading them unconditionally is O(project) FFI work at 60 Hz — a few
  /// hundred Dart objects per frame on a large song — and it is the difference
  /// between the app scaling and not.
  int _modelRevision = -1;
  int _rackKey = -1;
  List<ProjectInstrument> _instruments = const <ProjectInstrument>[];
  List<MixerTrackInfo> _tracks = const <MixerTrackInfo>[];
  List<EffectDescriptor> _availableEffects = const <EffectDescriptor>[];
  EffectRackVm? _rackVm;

  void _refreshModelIfStale() {
    final int revision = widget.client.modelRevision;
    if (revision == _modelRevision) return;
    _modelRevision = revision;
    _instruments = widget.client.readInstruments();
    _tracks = widget.client.readMixerTracks();
    // The catalogue is fixed for the life of the build, but it is cheap and
    // reading it here keeps every model read in one place.
    _availableEffects = widget.client.readBuiltinEffects();
    _rackVm = null;
  }

  /// The mixer track the insert rack is editing. The strips are per instrument,
  /// so the track is the one the selected instrument routes into — and the
  /// master when the master strip is selected.
  String _selectedTrackId(List<ProjectInstrument> instruments) {
    if (_selectedTrackIndex < 0 || _selectedTrackIndex >= instruments.length) {
      return _masterTrack()?.id ?? '';
    }
    final String routeId = instruments[_selectedTrackIndex].routeId;
    return routeId.isNotEmpty ? routeId : (_masterTrack()?.id ?? '');
  }

  MixerTrackInfo? _trackById(String trackId) {
    for (final MixerTrackInfo track in _tracks) {
      if (track.id == trackId) return track;
    }
    return null;
  }

  String _trackName(String trackId) => _trackById(trackId)?.name ?? 'Master';

  MixerTrackInfo? _masterTrack() {
    for (final MixerTrackInfo track in _tracks) {
      if (track.isMaster) return track;
    }
    return null;
  }

  String _gainText(double gain) {
    if (gain <= 0.0) return '−∞ dB';
    final double db = 20.0 * math.log(gain) / math.ln10;
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  String _instrumentRoute(ProjectInstrument instrument) {
    final String name = instrument.routeName.trim();
    if (name.isNotEmpty) return '→ $name';
    if (instrument.routeId.isNotEmpty) return '→ ${_trackName(instrument.routeId)}';
    return '→ Unrouted';
  }

  EffectRackVm _buildRackVm() {
    // Keyed on the model *and* on what is selected and expanded, because those
    // change the rack without changing the project.
    final int key = Object.hash(_modelRevision, _selectedTrackIndex, _expandedEffectId);
    final EffectRackVm? cached = _rackVm;
    if (cached != null && key == _rackKey) return cached;
    final EffectRackVm built = _buildRackVmUncached();
    _rackVm = built;
    _rackKey = key;
    return built;
  }

  EffectRackVm _buildRackVmUncached() {
    final List<ProjectInstrument> instruments = _instruments;
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
        for (final EffectDescriptor effect in _availableEffects)
          EffectChoiceVm(id: effect.id, name: effect.name, summary: effect.summary),
      ],
    );
  }

  void _withSelectedTrack(void Function(String trackId) action) {
    _refreshModelIfStale();
    final String trackId = _selectedTrackId(_instruments);
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
    final List<ProjectInstrument> instruments = _instruments;
    final EngineSnapshot snapshot = _controller.snapshot;
    final double masterLevel =
        (dbToFraction(_controller.meter.left.levelDb) + dbToFraction(_controller.meter.right.levelDb)) / 2.0;

    final List<MixerStripVm> stripVms = <MixerStripVm>[
      for (int i = 0; i < instruments.length; i++)
        (() {
          final ProjectInstrument inst = instruments[i];
          final bool isSelected = i == _selectedTrackIndex;
          final bool muted = _mutedInstrumentIds.contains(inst.id) || inst.muted;
          final bool soloed = _soloedInstrumentIds.contains(inst.id) || inst.soloed;
          final double fader = _faders[inst.id] ?? inst.gain.clamp(0.0, 1.0);
          final Color color = _resolveColor(i, inst.color);

          // Simulated live activity if playing
          final double trackLevel = snapshot.playing && !muted
              ? (masterLevel * (0.6 + (i % 4) * 0.1)).clamp(0.0, 1.0)
              : 0.0;

          return MixerStripVm(
            name: inst.name,
            color: color,
            route: _instrumentRoute(inst),
            level: trackLevel,
            fader: fader,
            muted: muted,
            soloed: soloed,
            routeActive: isSelected,
            selected: isSelected,
            isMaster: false,
            sidechainIn: false,
          );
        })(),
    ];

    final MixerTrackInfo? masterTrack = _masterTrack();
    final double masterGain = masterTrack?.gain ?? _masterFader;
    final MixerStripVm masterStripVm = MixerStripVm(
      // Track names are model data; the master strip's label is a UI role and
      // stays uppercase like the rest of the mixer chrome.
      name: 'MASTER',
      color: tokens.color.accent,
      route: _gainText(masterGain),
      level: snapshot.playing ? masterLevel.clamp(0.0, 1.0) : 0.0,
      fader: _masterFader == 0.75 && masterTrack != null ? masterGain.clamp(0.0, 1.0) : _masterFader,
      muted: masterTrack?.muted ?? _masterMuted,
      soloed: masterTrack?.soloed ?? _masterSoloed,
      routeActive: true,
      selected: _selectedTrackIndex == -1,
      isMaster: true,
    );

    // Selected track for routing panel. Every row is derived from the model:
    // the panel must not claim that every instrument feeds the selected strip,
    // or that every strip feeds Master, when the project has a real graph.
    final String selectedTrackId = _selectedTrackId(instruments);
    final MixerTrackInfo? selectedTrack = _trackById(selectedTrackId);
    final String selectedName = (_selectedTrackIndex >= 0 && _selectedTrackIndex < instruments.length)
        ? instruments[_selectedTrackIndex].name
        : (selectedTrack?.name ?? 'Master');
    final List<ProjectInstrument> routedInto = instruments
        .where((ProjectInstrument instrument) =>
            selectedTrackId.isEmpty ? instrument.routeId.isEmpty : instrument.routeId == selectedTrackId)
        .toList(growable: false);
    final MixerTrackInfo? outputTrack =
        selectedTrack == null || selectedTrack.outputId.isEmpty ? null : _trackById(selectedTrack.outputId);

    final RoutingPanelVm routingVm = RoutingPanelVm(
      trackName: selectedName,
      feeds: <FeedVm>[
        for (int i = 0; i < routedInto.length && i < 4; i++)
          FeedVm(
            name: routedInto[i].name,
            color: _resolveColor(
              instruments.indexWhere((ProjectInstrument instrument) => instrument.id == routedInto[i].id),
              routedInto[i].color,
            ),
            routeText: 'out 1 → ${selectedTrack?.name ?? selectedName}',
          ),
      ],
      feedsInto: <FeedVm>[
        FeedVm(
          name: outputTrack?.name ?? (selectedTrack == null ? 'Unrouted' : 'Master'),
          color: outputTrack == null ? channelColors[7] : _resolveColor(0, outputTrack.name),
          routeText: outputTrack == null ? '→ output' : '→ ${outputTrack.name}',
        ),
      ],
      // Sends and sidechains are intentionally empty until their native model
      // fields exist. Showing plausible names here made the routing panel lie
      // about the project graph.
      sends: const <SendVm>[],
      caption: selectedTrack == null
          ? 'This instrument has no mixer destination.'
          : outputTrack == null
              ? 'This track has no output destination.'
              : 'Feeds ${outputTrack.name}.',
      sidechain: null,
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
      final MixerTrackInfo? master = _masterTrack();
      final bool next = !(master?.muted ?? _masterMuted);
      setState(() => _masterMuted = next);
      if (master != null) {
        widget.client.setMixerTrackMuted(master.id, muted: next);
      }
      return;
    }
    final List<ProjectInstrument> instruments = _instruments;
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
      final MixerTrackInfo? master = _masterTrack();
      final bool next = !(master?.soloed ?? _masterSoloed);
      setState(() {
        _masterSoloed = next;
        if (next) _soloedInstrumentIds.clear();
      });
      if (next) {
        for (final ProjectInstrument instrument in _instruments) {
          if (instrument.soloed) {
            widget.client.setInstrumentSoloed(instrument.id, soloed: false);
          }
        }
      }
      if (master != null) {
        widget.client.setMixerTrackSoloed(master.id, soloed: next);
      }
      return;
    }
    final List<ProjectInstrument> instruments = _instruments;
    if (index >= 0 && index < instruments.length) {
      final ProjectInstrument instrument = instruments[index];
      final String id = instrument.id;
      final bool next = !(_soloedInstrumentIds.contains(id) || instrument.soloed);
      setState(() {
        if (next) {
          _soloedInstrumentIds
            ..clear()
            ..add(id);
          _masterSoloed = false;
          final MixerTrackInfo? master = _masterTrack();
          if (master?.soloed == true) {
            widget.client.setMixerTrackSoloed(master!.id, soloed: false);
          }
        } else {
          _soloedInstrumentIds.remove(id);
        }
      });
      // Keep the engine-backed channel state in step with the mixer when this
      // view is the one that changes solo. Enabling one channel clears every
      // other channel, so both surfaces obey the same exclusive-solo rule.
      if (next) {
        for (final ProjectInstrument other in instruments) {
          if (other.id != id && other.soloed) {
            widget.client.setInstrumentSoloed(other.id, soloed: false);
          }
        }
      }
      widget.client.setInstrumentSoloed(id, soloed: next);
    }
  }

  void _onFader(int index, double value) {
    if (index == -1) {
      setState(() => _masterFader = value);
      final MixerTrackInfo? master = _masterTrack();
      if (master != null) {
        widget.client.setMixerTrackGain(master.id, value);
      } else {
        widget.client.setMasterGain(value);
      }
      return;
    }
    final List<ProjectInstrument> instruments = _instruments;
    if (index >= 0 && index < instruments.length) {
      final String id = instruments[index].id;
      setState(() => _faders[id] = value);
      widget.client.setInstrumentGain(id, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    _refreshModelIfStale();
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
