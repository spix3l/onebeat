// RackBinding — wires the channel rack presentation to the core engine (UI-D-02).
//
// Owns the mapping from the engine snapshot and RackStore to ChannelRackScreenVm.
// Listens to the EngineController for real-time playback cursor updates,
// and routes gestures and user interactions to RackStore commands.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/popover_menu.dart';
import 'channel_inspector.dart';
import 'channel_rack_screen.dart';
import 'channel_rack_screen_vm.dart';
import 'rack_row.dart';
import 'rack_store.dart';
import 'rack_toolbar.dart';

class RackBinding extends StatefulWidget {
  const RackBinding({
    required this.client,
    this.controller,
    this.store,
    this.onBrowsePlugins,
    this.onOpenMixer,
    this.onOpenPianoRoll,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;
  final RackStore? store;
  final VoidCallback? onBrowsePlugins;
  final VoidCallback? onOpenMixer;
  final void Function(String instrumentId)? onOpenPianoRoll;

  @override
  State<RackBinding> createState() => _RackBindingState();
}

class _RackBindingState extends State<RackBinding>
    with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final RackStore _store;
  bool _ownsController = false;
  bool _ownsStore = false;

  String _selectedGroup = 'All';
  String _selectedType = 'Sampler';
  String _selectedSnap = '1/16';

  OverlayEntry? _contextMenuEntry;

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

    if (widget.store != null) {
      _store = widget.store!;
    } else {
      _store = RackStore(widget.client)..load();
      _ownsStore = true;
    }

    _controller.addListener(_onEngineChanged);
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _hideContextMenu();
    _controller.removeListener(_onEngineChanged);
    _store.removeListener(_onStoreChanged);
    if (_ownsStore) {
      _store.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int? _calculatePlayingStep() {
    final EngineSnapshot snapshot = _controller.snapshot;
    if (!snapshot.playing) return null;
    final RackPattern? pattern = _store.pattern;
    final int baseStepCount = pattern?.baseStepCount ?? 16;
    if (baseStepCount <= 0) return null;

    final int lengthTicks = pattern?.lengthTicks ?? (baseStepCount * 240);
    if (lengthTicks <= 0) return null;

    final double currentTicks = snapshot.positionBeats * 960.0;
    final double loopTicks = currentTicks % lengthTicks;
    final int gridTicks = pattern?.baseGridTicks ?? 240;
    if (gridTicks <= 0) return null;

    final int step = (loopTicks / gridTicks).floor();
    return step.clamp(0, baseStepCount - 1);
  }

  Color _resolveInstrumentColor(int index, String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty) {
      final int parsed = int.tryParse(colorStr.replaceFirst('#', ''), radix: 16) ?? 0;
      if (parsed != 0) {
        return Color(0xFF000000 | parsed);
      }
    }
    return channelColors[index % channelColors.length];
  }

  List<double> _defaultWaveform() {
    const int count = 96;
    return <double>[
      for (int i = 0; i < count; i++)
        _waveSample(i / (count - 1)),
    ];
  }

  double _waveSample(double t) {
    double amp = 0.12;
    const List<(double, double, double)> lobes = <(double, double, double)>[
      (0.16, 0.13, 0.88),
      (0.44, 0.10, 0.66),
      (0.68, 0.11, 1.0),
      (0.88, 0.05, 0.42),
    ];
    for (final (double centre, double width, double height) in lobes) {
      final double d = (t - centre) / width;
      amp = math.max(amp, height * math.exp(-d * d));
    }
    return amp;
  }

  ChannelRackScreenVm _buildVm() {
    final RackPattern? pattern = _store.pattern;
    final int stepCount = pattern?.baseStepCount ?? 16;
    final int? playingStep = _calculatePlayingStep();

    final List<PatternTabVm> patternTabs = <PatternTabVm>[];
    if (_store.patterns.isNotEmpty) {
      for (final PatternSummary p in _store.patterns) {
        patternTabs.add(
          PatternTabVm(
            id: p.id,
            name: p.name,
            selected: p.isCurrent,
            count: p.usageCount,
          ),
        );
      }
    } else if (pattern != null) {
      patternTabs.add(
        PatternTabVm(
          id: pattern.id,
          name: pattern.name,
          selected: true,
        ),
      );
    }

    final List<RackRow> visibleRows =
        _store.rows.where(_store.isVisible).toList();

    final List<RackRowVm> rowVms = <RackRowVm>[];
    for (int i = 0; i < visibleRows.length; i++) {
      final RackRow row = visibleRows[i];
      final ProjectInstrument? inst = _store.instrumentFor(row.instrumentId);
      final Color color = _resolveInstrumentColor(i, inst?.color);

      final List<StepVm> stepVms = <StepVm>[
        for (int s = 0; s < row.steps.length; s++)
          StepVm(
            on: row.steps[s].active,
            velocity: row.steps[s].velocity / 16383.0,
          ),
      ];

      rowVms.add(
        RackRowVm(
          name: inst?.name ?? row.instrumentId,
          type: inst?.pluginName.isNotEmpty == true
              ? inst!.pluginName
              : 'Sampler',
          color: color,
          steps: stepVms,
          vol: 0.75,
          pan: 0.5,
          route: '→ D1',
          powered: !(inst?.muted ?? false),
          selected: _store.selectedInstrumentId == row.instrumentId,
        ),
      );
    }

    ChannelInspectorVm? inspectorVm;
    final String? selectedId = _store.selectedInstrumentId;
    if (selectedId != null) {
      final ProjectInstrument? selectedInst = _store.instrumentFor(selectedId);
      final int instIndex = _store.instruments.indexWhere(
        (ProjectInstrument inst) => inst.id == selectedId,
      );
      final Color inspColor = _resolveInstrumentColor(
        instIndex >= 0 ? instIndex : 0,
        selectedInst?.color,
      );

      inspectorVm = ChannelInspectorVm(
        name: selectedInst?.name ?? selectedId,
        subtitle: '${selectedInst?.pluginName.isNotEmpty == true ? selectedInst!.pluginName : "Sampler"} · channel ${(selectedInst?.order ?? (instIndex >= 0 ? instIndex : 0)) + 1}',
        color: inspColor,
        waveform: _defaultWaveform(),
        vol: 0.78,
        volText: '78',
        pan: 0.5,
        panText: '· C',
        fx: <FxVm>[
          FxVm(name: 'Chorus', color: inspColor, active: true),
          FxVm(name: 'EQ 4', color: channelColors[2]),
        ],
        route: 'M1 · Music',
        muted: selectedInst?.muted ?? false,
        soloed: false,
      );
    }

    final RackToolbarVm toolbarVm = RackToolbarVm(
      channelType: _selectedType,
      group: _selectedGroup,
      snap: _selectedSnap,
      caption: '$stepCount steps · loop',
    );

    return ChannelRackScreenVm(
      patterns: patternTabs,
      toolbar: toolbarVm,
      stepCount: stepCount,
      rows: rowVms,
      playingStep: playingStep,
      inspector: inspectorVm,
      canUndo: _store.canUndo,
      canRedo: _store.canRedo,
    );
  }

  void _onStepTap(int rowIndex, int stepIndex) {
    final List<RackRow> visible = _store.rows.where(_store.isVisible).toList();
    if (rowIndex >= 0 && rowIndex < visible.length) {
      _store.toggleStep(visible[rowIndex].instrumentId, stepIndex);
    }
  }

  void _onSelectRow(int rowIndex) {
    final List<RackRow> visible = _store.rows.where(_store.isVisible).toList();
    if (rowIndex >= 0 && rowIndex < visible.length) {
      _store.selectInstrument(visible[rowIndex].instrumentId);
    }
  }

  /// The first usable built-in plug-in, for adding a channel or an instrument
  /// without browsing. Falls back to any usable plug-in.
  PluginListing? _firstBuiltin() {
    final PluginScanStatus status = widget.client.readPluginScanStatus();
    if (status.pluginCount <= 0) return null;
    final List<PluginListing> plugins = widget.client.readPluginList(
      status.pluginCount,
    );
    PluginListing? fallback;
    for (final PluginListing p in plugins) {
      if (!p.isUsable) continue;
      if (p.format == PluginFormat.builtin) return p;
      fallback ??= p;
    }
    return fallback;
  }

  /// Adds the default instrument as a new, empty channel. When no usable
  /// plug-in has been discovered yet, falls back to opening the browser.
  void _addInstrument() {
    final PluginListing? plugin = _firstBuiltin();
    if (plugin == null) {
      widget.onBrowsePlugins?.call();
      return;
    }
    widget.client.addPluginByPath(plugin.path, plugin.id);
    _store.refresh();
    if (_store.instruments.isNotEmpty) {
      _store.selectInstrument(_store.instruments.last.id);
    }
  }

  void _onAddChannel() => _addInstrument();

  void _onDoubleTap() => _addInstrument();

  void _onRowSecondaryTapDown(int rowIndex, TapDownDetails details) {
    final List<RackRow> visible = _store.rows.where(_store.isVisible).toList();
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    _showContextMenu(visible[rowIndex].instrumentId, details.globalPosition);
  }

  void _onDropInstrument(int rowIndex, Object data) {
    if (data is! PluginListing) return;
    final List<RackRow> visible = _store.rows.where(_store.isVisible).toList();
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    widget.client.replaceInstrument(visible[rowIndex].instrumentId, data);
    _store.refresh();
  }

  void _showContextMenu(String instrumentId, Offset globalPosition) {
    _hideContextMenu();
    final OverlayState overlay = Overlay.of(context);
    _contextMenuEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hideContextMenu,
                onSecondaryTapDown: (_) => _hideContextMenu(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: ObPopoverMenu(
                vm: const ObPopoverMenuVm(
                  sections: <ObMenuSectionVm>[
                    ObMenuSectionVm(
                      rows: <ObMenuRowVm>[
                        ObMenuRowVm(
                          label: 'Open in piano roll',
                          icon: ObKitGlyphKind.note,
                        ),
                      ],
                    ),
                  ],
                ),
                onSelect: (int index) {
                  _hideContextMenu();
                  if (index == 0) {
                    widget.onOpenPianoRoll?.call(instrumentId);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_contextMenuEntry!);
  }

  void _hideContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final ChannelRackScreenVm vm = _buildVm();

    return ChannelRackScreen(
      vm: vm,
      onSelectPattern: (String id) => _store.selectPattern(id),
      onSelectRow: _onSelectRow,
      onStepTap: _onStepTap,
      onAddChannel: _onAddChannel,
      onDoubleTap: _onDoubleTap,
      onRowSecondaryTapDown: _onRowSecondaryTapDown,
      onDropInstrument: _onDropInstrument,
      onChannelType: (String val) => setState(() => _selectedType = val),
      onGroup: (String val) => setState(() => _selectedGroup = val),
      onSnap: (String val) {
        setState(() => _selectedSnap = val);
        final int ticks = switch (val) {
          '1/4' => 960,
          '1/8' => 480,
          '1/16' => 240,
          '1/32' => 120,
          _ => 240,
        };
        if (_store.selectedInstrumentId != null) {
          _store.setGrid(_store.selectedInstrumentId!, ticks);
        }
      },
      onMixerTap: widget.onOpenMixer,
      onInspectorKeyPress: (int note) => _store.auditionNote(note),
      onPointerDownStep: (PointerDownEvent event, int rowIndex, int stepIndex) {
        final List<RackRow> visible =
            _store.rows.where(_store.isVisible).toList();
        if (rowIndex < 0 || rowIndex >= visible.length) return;
        final RackRow row = visible[rowIndex];
        final bool velocityMode = event.buttons == kSecondaryMouseButton ||
            HardwareKeyboard.instance.isAltPressed;
        if (velocityMode) {
          _store.beginVelocityPaint();
          _store.setVelocity(row.instrumentId, stepIndex, 12900);
        } else {
          final bool active =
              stepIndex < row.steps.length ? !row.steps[stepIndex].active : true;
          _store.beginPaint(row.instrumentId, stepIndex, active: active);
        }
      },
      onPointerMoveStep: (PointerMoveEvent event, int rowIndex, int stepIndex) {
        final List<RackRow> visible =
            _store.rows.where(_store.isVisible).toList();
        if (rowIndex < 0 || rowIndex >= visible.length) return;
        final RackRow row = visible[rowIndex];
        if (event.buttons == kSecondaryMouseButton ||
            HardwareKeyboard.instance.isAltPressed) {
          _store.setVelocity(row.instrumentId, stepIndex, 12900);
        } else {
          _store.paintStep(row.instrumentId, stepIndex);
        }
      },
      onPointerUpStep: () {
        _store.commitPaint();
        _store.commitVelocityPaint();
      },
      onPointerCancelStep: () {
        _store.abortPaint();
        _store.abortVelocityPaint();
      },
    );
  }
}
