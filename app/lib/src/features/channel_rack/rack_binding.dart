// RackBinding — wires the channel rack presentation to the core engine (UI-D-02).
//
// Owns the mapping from the engine snapshot and RackStore to ChannelRackScreenVm.
// Listens to the EngineController for real-time playback cursor updates,
// and routes gestures and user interactions to RackStore commands.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../core/action_registry.dart';
import '../../core/shortcuts.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/popover_menu.dart';
import '../browser/sample_pack.dart';
import 'channel_inspector.dart';
import 'channel_rack_screen.dart';
import 'channel_rack_screen_vm.dart';
import 'delete_pattern_dialog.dart';
import 'rack_row.dart';
import 'rack_store.dart';
import 'rack_toolbar.dart';
import 'rename_channel_dialog.dart';

/// The engine's built-in sample player. A lane whose plug-in is this is a WAV
/// channel, not a hosted plug-in, so double-clicking it has no plug-in window
/// to open.
const String _kSamplePluginId = 'onebeat.sample';

class RackBinding extends StatefulWidget {
  const RackBinding({
    required this.client,
    this.controller,
    this.store,
    this.onBrowsePlugins,
    this.onOpenMixer,
    this.onOpenPianoRoll,
    this.onOpenPlugin,
    this.onOpenSampler,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;
  final RackStore? store;
  final VoidCallback? onBrowsePlugins;
  final VoidCallback? onOpenMixer;
  final void Function(String instrumentId)? onOpenPianoRoll;

  /// Opens the plug-in window for a lane's instrument. Double-clicking a lane
  /// that hosts a plug-in reports the instrument here; the shell owns the
  /// floating window.
  final void Function(String instrumentId)? onOpenPlugin;

  /// Opens the built-in sampler editor for a sample lane. Kept separate from
  /// hosted plug-ins so a sample lane never masquerades as a CLAP instance.
  final void Function(String instrumentId)? onOpenSampler;

  @override
  State<RackBinding> createState() => _RackBindingState();
}

class _RackBindingState extends State<RackBinding> with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final RackStore _store;
  bool _ownsController = false;
  bool _ownsStore = false;

  final Map<String, double> _gains = <String, double>{};
  final Map<String, double> _pans = <String, double>{};

  OverlayEntry? _contextMenuEntry;

  /// The channel the rename dialog is pointed at, while it is open. Solo is a
  /// mixer-track audio gate (v0.4), so the rack models it locally for now —
  /// the same way the mixer does — so the menu's check and the inspector's S
  /// chip can at least reflect the choice.
  bool _showRenameDialog = false;
  bool _renamePattern = false;
  bool _showDeletePatternDialog = false;
  String? _deletePatternId;
  String? _renameInstrumentId;
  String? _renamePatternId;
  final Set<String> _soloedInstrumentIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = core.EngineController(client: widget.client, vsync: this, motion: OneBeatTokens.dark().motion);
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
      // The engine can change the instrument set without a store action.
      // Refresh cheaply when the set moved, then rebuild either way.
      _store.refreshIfInstrumentsChanged();
      setState(() {});
    }
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onCreatePattern() {
    final int nextNumber = _store.patterns.length + 1;
    widget.client.createPattern('Pattern $nextNumber');
    _store.refresh();
  }

  void _requestDeletePattern([String? patternId]) {
    final PatternSummary? pattern = _store.patterns.cast<PatternSummary?>().firstWhere(
      (PatternSummary? item) => item?.id == (patternId ?? _store.pattern?.id),
      orElse: () => null,
    );
    if (pattern == null) return;
    setState(() {
      _deletePatternId = pattern.id;
      _showDeletePatternDialog = true;
    });
  }

  void _confirmDeletePattern() {
    final String? patternId = _deletePatternId;
    if (patternId == null) return;
    try {
      widget.client.removePattern(patternId);
    } catch (_) {
      return;
    }
    _store.refresh();
    setState(() {
      _deletePatternId = null;
      _showDeletePatternDialog = false;
    });
  }

  void _closeDeletePatternDialog() {
    setState(() {
      _deletePatternId = null;
      _showDeletePatternDialog = false;
    });
  }

  int? _calculatePlayingStep() {
    final int? tick = _calculatePlayingTick();
    if (tick == null) return null;
    final RackPattern? pattern = _store.pattern;
    final int gridTicks = pattern?.baseGridTicks ?? 240;
    if (gridTicks <= 0) return null;
    final int stepCount = pattern?.baseStepCount ?? 16;
    if (stepCount <= 0) return null;
    final int step = (tick / gridTicks).floor();
    return step.clamp(0, stepCount - 1);
  }

  /// The transport's position wrapped onto the loop region, in ticks. Shared by
  /// the step grid's column ring and the piano-roll preview's read head, so both
  /// agree about where the audio actually is.
  int? _calculatePlayingTick() {
    final EngineSnapshot snapshot = _controller.snapshot;
    if (!snapshot.playing) return null;

    // The playhead loops on the transport's *loop region* — the same [start,
    // end) the engine wraps the audio on — not on the pattern's stored length,
    // which is a fixed default and can differ from where the audio loops.
    final double startBeats = snapshot.loopStartBeats;
    final double endBeats = snapshot.loopEndBeats;
    final double loopLengthBeats = endBeats > startBeats ? endBeats - startBeats : 0.0;
    final double inLoop = snapshot.positionBeats - startBeats;
    final double looped = loopLengthBeats > 0.0 ? inLoop % loopLengthBeats : inLoop;
    final double currentTicks = (looped < 0.0 ? 0.0 : looped) * 960.0;
    return currentTicks.round();
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

  ChannelRackScreenVm _buildVm() {
    final RackPattern? pattern = _store.pattern;
    final int stepCount = pattern?.baseStepCount ?? 16;
    final int? playingStep = _calculatePlayingStep();
    final int? playingTick = _calculatePlayingTick();

    final List<PatternTabVm> patternTabs = <PatternTabVm>[];
    if (_store.patterns.isNotEmpty) {
      for (final PatternSummary p in _store.patterns) {
        patternTabs.add(PatternTabVm(id: p.id, name: p.name, selected: p.isCurrent, count: p.usageCount));
      }
    } else if (pattern != null) {
      patternTabs.add(PatternTabVm(id: pattern.id, name: pattern.name, selected: true));
    }

    final List<RackRow> visibleRows = _store.rows;

    final List<RackRowVm> rowVms = <RackRowVm>[];
    for (int i = 0; i < visibleRows.length; i++) {
      final RackRow row = visibleRows[i];
      final ProjectInstrument? inst = _store.instrumentFor(row.instrumentId);
      final Color color = _resolveInstrumentColor(i, inst?.color);

      final List<StepVm> stepVms = <StepVm>[
        for (int s = 0; s < row.steps.length; s++)
          StepVm(on: row.steps[s].active, velocity: row.steps[s].velocity / 16383.0),
      ];

      rowVms.add(
        RackRowVm(
          name: inst?.name ?? row.instrumentId,
          type:
              inst?.pluginId == _kSamplePluginId
                  ? 'Sampler'
                  : (inst != null && inst.pluginName.isNotEmpty ? inst.pluginName : 'Empty channel'),

          color: color,
          steps: stepVms,
          vol: _gains[row.instrumentId] ?? (inst != null ? inst.gain.clamp(0.0, 1.0) : 1.0),
          pan: _pans[row.instrumentId] ?? (inst != null ? ((inst.pan.clamp(-1.0, 1.0) + 1.0) / 2.0) : 0.5),
          route: '→ D1',
          powered: !(inst?.muted ?? false),
          selected: _store.selectedInstrumentId == row.instrumentId,
          previewNotes: _previewNotesFor(row), // Sample lanes open the built-in sampler; hosted lanes open their
          // plug-in editor. Empty lanes remain non-openable.
          hostsPlugin: inst != null && inst.pluginId.isNotEmpty,
        ),
      );
    }

    ChannelInspectorVm? inspectorVm;
    final String? selectedId = _store.selectedInstrumentId;
    if (selectedId != null) {
      final ProjectInstrument? selectedInst = _store.instrumentFor(selectedId);
      final int instIndex = _store.instruments.indexWhere((ProjectInstrument inst) => inst.id == selectedId);
      final Color inspColor = _resolveInstrumentColor(instIndex >= 0 ? instIndex : 0, selectedInst?.color);

      inspectorVm = ChannelInspectorVm(
        name: selectedInst?.name ?? selectedId,
        subtitle:
            '${selectedInst?.pluginId == _kSamplePluginId ? "Sampler" : (selectedInst?.pluginName.isNotEmpty == true ? selectedInst!.pluginName : "Sampler")} · channel ${(selectedInst?.order ?? (instIndex >= 0 ? instIndex : 0)) + 1}',
        color: inspColor,
        vol: _gains[selectedId] ?? (selectedInst != null ? selectedInst.gain.clamp(0.0, 1.0) : 0.78),
        volText: _volText(selectedId, selectedInst),
        pan: _pans[selectedId] ?? (selectedInst != null ? ((selectedInst.pan.clamp(-1.0, 1.0) + 1.0) / 2.0) : 0.5),
        panText: _panText(selectedId, selectedInst),
        route: 'M1 · Music',
        muted: selectedInst?.muted ?? false,
        soloed: _soloedInstrumentIds.contains(selectedId),
        // The row itself can open a sample's built-in editor, but the
        // inspector's hosted-plugin action is reserved for real plug-ins.
        hostsPlugin:
            selectedInst != null && selectedInst.pluginId.isNotEmpty && selectedInst.pluginId != _kSamplePluginId,
      );
    }

    final RackToolbarVm toolbarVm = RackToolbarVm(
      // These legacy fields are retained for older view-model fixtures; the
      // toolbar deliberately does not render them.
      channelType: 'Sampler',
      group: 'All',
      snap: '1/16',
      steps: stepCount,
    );

    return ChannelRackScreenVm(
      patterns: patternTabs,
      toolbar: toolbarVm,
      stepCount: stepCount,
      rows: rowVms,
      playingStep: playingStep,
      playingTick: playingTick,
      inspector: inspectorVm,
      canUndo: _store.canUndo,
      canRedo: _store.canRedo,
    );
  }

  /// The value under the inspector's VOL knob, formatted as the rounded
  /// percentage the mockup shows.
  String _volText(String id, ProjectInstrument? inst) {
    final double v = _gains[id] ?? (inst != null ? inst.gain.clamp(0.0, 1.0) : 0.78);
    return '${(v * 100).round()}';
  }

  /// The value under the inspector's PAN knob: `· C` for centre, else `L`/`R`
  /// with the magnitude.
  String _panText(String id, ProjectInstrument? inst) {
    final double p = _pans[id] ?? (inst != null ? ((inst.pan.clamp(-1.0, 1.0) + 1.0) / 2.0) : 0.5);
    final double signed = (p - 0.5) * 2.0;
    if (signed.abs() < 0.02) return '· C';
    return signed < 0 ? '· L' : '· R';
  }

  /// A piano-roll preview for a row whose notes read as a melody rather than a
  /// step grid: off-grid timing or more than one pitch. Null keeps the grid.
  List<RackPreviewNoteVm>? _previewNotesFor(RackRow row) {
    if (!row.hasSequence) return null;
    final List<SequenceNote> notes = _store.notesFor(row.instrumentId);
    if (notes.isEmpty) return null;

    final bool offGrid = row.offGridCount > 0;
    bool multiPitch = false;
    int? firstKey;
    for (final SequenceNote note in notes) {
      if (firstKey == null) {
        firstKey = note.key;
      } else if (note.key != firstKey) {
        multiPitch = true;
        break;
      }
    }
    if (!offGrid && !multiPitch) return null;

    return <RackPreviewNoteVm>[
      for (final SequenceNote note in notes)
        RackPreviewNoteVm(startTick: note.startTicks, lengthTicks: note.lengthTicks, midiNote: note.key),
    ];
  }

  void _onStepTap(int rowIndex, int stepIndex) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex >= 0 && rowIndex < visible.length) {
      _store.toggleStep(visible[rowIndex].instrumentId, stepIndex);
    }
  }

  void _onSelectRow(int rowIndex) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex >= 0 && rowIndex < visible.length) {
      _store.selectInstrument(visible[rowIndex].instrumentId);
    }
  }

  /// A double-click on a lane that hosts a plug-in selects it and hands the
  /// instrument to the shell, which opens the plug-in window. The row only
  /// wires the double-tap for plug-in lanes ([RackRowVm.hostsPlugin]), but the
  /// guard keeps this robust if that ever drifts.
  void _onRowDoubleTap(int rowIndex) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    final String instrumentId = visible[rowIndex].instrumentId;
    _store.selectInstrument(instrumentId);
    final ProjectInstrument? inst = _store.instrumentFor(instrumentId);
    if (inst?.pluginId == _kSamplePluginId) {
      widget.onOpenSampler?.call(instrumentId);
    } else {
      widget.onOpenPlugin?.call(instrumentId);
    }
  }

  /// Adds a new, empty channel (no plug-in) as a visible blank lane. Creating
  /// a lane must not select an instrument: the inspector belongs to an
  /// explicit row selection, not to the add action.
  void _addChannelLane() {
    final int index = _store.instruments.length + 1;
    try {
      widget.client.addEmptyInstrument('Channel $index');
    } catch (_) {
      widget.onBrowsePlugins?.call();
      return;
    }
    _store.refresh();
  }

  /// Moves the lane at [oldIndex] to [newIndex]. Rack rows are in instrument
  /// order, so the row's new position *is* the instrument's new `order`.
  void _onReorderRow(int oldIndex, int newIndex) {
    final List<RackRow> rows = _store.rows;
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex == oldIndex || newIndex < 0 || newIndex >= rows.length) return;
    try {
      widget.client.reorderInstrument(rows[oldIndex].instrumentId, newIndex);
    } catch (_) {
      // The command is a stub on a fake client.
      return;
    }
    _store.refresh();
  }

  void _onAddChannel() => _addChannelLane();

  void _onVolChanged(int rowIndex, double value) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    final String id = visible[rowIndex].instrumentId;
    setState(() => _gains[id] = value.clamp(0.0, 1.0));
    try {
      widget.client.setInstrumentGain(id, value.clamp(0.0, 1.0));
    } catch (_) {
      // Stub when the fake client has no gain command.
    }
  }

  void _onPanChanged(int rowIndex, double value) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    final String id = visible[rowIndex].instrumentId;
    setState(() => _pans[id] = value.clamp(0.0, 1.0));
    try {
      widget.client.setInstrumentPan(id, (value.clamp(0.0, 1.0) - 0.5) * 2.0);
    } catch (_) {
      // Stub when the fake client has no pan command.
    }
  }

  void _onTogglePower(int rowIndex) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    final String id = visible[rowIndex].instrumentId;
    final ProjectInstrument? inst = _store.instrumentFor(id);
    final bool next = !(inst?.muted ?? false);
    try {
      widget.client.setInstrumentMuted(id, muted: next);
    } catch (_) {
      // Stub when the fake client has no mute command.
    }
    _store.refresh();
  }

  void _onInspectorVol(double value) {
    final String? id = _store.selectedInstrumentId;
    if (id == null) return;
    setState(() => _gains[id] = value.clamp(0.0, 1.0));
    try {
      widget.client.setInstrumentGain(id, value.clamp(0.0, 1.0));
    } catch (_) {
      // Stub when the fake client has no gain command.
    }
  }

  void _onInspectorPan(double value) {
    final String? id = _store.selectedInstrumentId;
    if (id == null) return;
    setState(() => _pans[id] = value.clamp(0.0, 1.0));
    try {
      widget.client.setInstrumentPan(id, (value.clamp(0.0, 1.0) - 0.5) * 2.0);
    } catch (_) {
      // Stub when the fake client has no pan command.
    }
  }

  void _onInspectorMute() {
    final String? id = _store.selectedInstrumentId;
    if (id == null) return;
    final ProjectInstrument? inst = _store.instrumentFor(id);
    final bool next = !(inst?.muted ?? false);
    try {
      widget.client.setInstrumentMuted(id, muted: next);
    } catch (_) {
      // Stub when the fake client has no mute command.
    }
    _store.refresh();
  }

  void _onInspectorSolo() {
    final String? id = _store.selectedInstrumentId;
    if (id == null) return;
    _toggleSolo(id);
  }

  /// Opens the selected channel's plug-in window from the inspector. The
  /// inspector's Open plugin button only renders for plug-in channels, so the
  /// guard mirrors the same test the row uses.
  void _onInspectorOpenPlugin() {
    final String? id = _store.selectedInstrumentId;
    if (id == null) return;
    final ProjectInstrument? inst = _store.instrumentFor(id);
    if (inst == null || inst.pluginId.isEmpty) return;
    _openPluginFromMenu(id);
  }

  /// Flips the local solo flag for [instrumentId]. Engine-backed solo arrives
  /// with mixer-track audio gates (v0.4); until then this is UI state so the
  /// channel rack and mixer can draw the choice without faking audio.
  void _toggleSolo(String instrumentId) {
    setState(() {
      if (_soloedInstrumentIds.contains(instrumentId)) {
        _soloedInstrumentIds.remove(instrumentId);
      } else {
        _soloedInstrumentIds.add(instrumentId);
      }
    });
  }

  void _onAddInstrument(Object data) {
    try {
      if (data is PluginListing) {
        widget.client.addPluginByPath(data.path, data.id);
      } else if (data is SampleAsset) {
        widget.client.addSampleInstrument(data.name, data.path);
      } else {
        return;
      }
      // A dropped asset is an instrument, so it is a lane — no "include" step.
      // Selection stays a separate action so the inspector does not appear
      // unexpectedly.
      _store.refresh();
    } catch (_) {
      // Hosting or sample loading failed; ignore the drop.
    }
  }

  void _onRowSecondaryTapDown(int rowIndex, TapDownDetails details) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    _showContextMenu(visible[rowIndex].instrumentId, details.globalPosition);
  }

  void _onPatternSecondaryTapDown(String patternId, TapDownDetails details) {
    _hideContextMenu();
    final OverlayState overlay = Overlay.of(context);
    _contextMenuEntry = OverlayEntry(
      builder:
          (BuildContext overlayContext) => Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _hideContextMenu,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: details.globalPosition.dx,
                top: details.globalPosition.dy,
                child: ObPopoverMenu(
                  vm: const ObPopoverMenuVm(
                    sections: <ObMenuSectionVm>[
                      ObMenuSectionVm(
                        rows: <ObMenuRowVm>[
                          ObMenuRowVm(label: 'Rename', icon: ObKitGlyphKind.pencil),
                          ObMenuRowVm(label: 'Delete', icon: ObKitGlyphKind.trash, tone: ObMenuRowTone.danger),
                        ],
                      ),
                    ],
                  ),
                  onSelect: (int index) {
                    _hideContextMenu();
                    if (index == 0) {
                      _beginPatternRename(patternId);
                    } else {
                      _requestDeletePattern(patternId);
                    }
                  },
                ),
              ),
            ],
          ),
    );
    overlay.insert(_contextMenuEntry!);
  }

  void _beginPatternRename(String patternId) {
    _store.selectPattern(patternId);
    setState(() {
      _renamePatternId = patternId;
      _renamePattern = true;
      _showRenameDialog = true;
    });
  }

  void _onDropInstrument(int rowIndex, Object data) {
    final List<RackRow> visible = _store.rows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    try {
      if (data is PluginListing) {
        widget.client.replaceInstrument(visible[rowIndex].instrumentId, data);
      } else if (data is SampleAsset) {
        widget.client.replaceSampleInstrument(visible[rowIndex].instrumentId, data.name, data.path);
      } else {
        return;
      }
    } catch (_) {
      // Hosting or sample loading failed; leave the lane as it was.
    }
    _store.refresh();
  }

  void _showContextMenu(String instrumentId, Offset globalPosition) {
    _hideContextMenu();
    final ProjectInstrument? inst = _store.instrumentFor(instrumentId);
    // A lane that hosts a plug-in gets the window-opening row; a sample lane
    // opens the built-in sampler, while an empty lane has no editor.
    final bool hostsPlugin = inst != null && inst.pluginId.isNotEmpty;
    final bool isSample = inst?.pluginId == _kSamplePluginId;

    final bool soloed = _soloedInstrumentIds.contains(instrumentId);

    // The channel rows, with their actions in the same order. The flat index
    // the menu reports is this list, then the step fills, then delete.
    final List<ObMenuRowVm> actionRows = <ObMenuRowVm>[
      const ObMenuRowVm(label: 'Open in piano roll', icon: ObKitGlyphKind.note),
      if (hostsPlugin)
        ObMenuRowVm(
          label: isSample ? 'Open sampler' : 'Open plugin window',
          icon: isSample ? ObKitGlyphKind.waveform : ObKitGlyphKind.keyboard,
        ),
      const ObMenuRowVm(label: 'Rename', icon: ObKitGlyphKind.pencil),
      const ObMenuRowVm(label: 'Duplicate', icon: ObKitGlyphKind.plus),
      ObMenuRowVm(
        label: 'Solo',
        checkable: true,
        checked: soloed,
        tone: soloed ? ObMenuRowTone.active : ObMenuRowTone.normal,
      ),
    ];
    final List<void Function()> actions = <void Function()>[
      () => widget.onOpenPianoRoll?.call(instrumentId),
      if (hostsPlugin) () => _openPluginFromMenu(instrumentId),
      () => _beginRename(instrumentId),
      () => _duplicateInstrument(instrumentId),
      () => _toggleSolo(instrumentId),
    ];

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
                vm: ObPopoverMenuVm(
                  sections: <ObMenuSectionVm>[
                    ObMenuSectionVm(rows: actionRows),
                    const ObMenuSectionVm(
                      header: 'Step actions',
                      separated: true,
                      rows: <ObMenuRowVm>[
                        ObMenuRowVm(label: 'Add note every 2 steps', icon: ObKitGlyphKind.plus, shortcut: '2'),
                        ObMenuRowVm(label: 'Add note every 4 steps', icon: ObKitGlyphKind.plus, shortcut: '4'),
                        ObMenuRowVm(label: 'Add note every 8 steps', icon: ObKitGlyphKind.plus, shortcut: '8'),
                      ],
                    ),
                    const ObMenuSectionVm(
                      separated: true,
                      rows: <ObMenuRowVm>[
                        ObMenuRowVm(label: 'Delete', icon: ObKitGlyphKind.trash, tone: ObMenuRowTone.danger),
                      ],
                    ),
                  ],
                ),
                onSelect: (int index) {
                  _hideContextMenu();
                  if (index < actions.length) {
                    actions[index]();
                    return;
                  }
                  switch (index - actions.length) {
                    case 0:
                      _store.addNotesEvery(instrumentId, 2);
                    case 1:
                      _store.addNotesEvery(instrumentId, 4);
                    case 2:
                      _store.addNotesEvery(instrumentId, 8);
                    case 3:
                      _deleteInstrument(instrumentId);
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

  /// Opens the plug-in window for a lane, from the context menu: the lane is
  /// selected first so the engine's hosted-instance surface follows, exactly as
  /// a double-click on the lane does.
  void _openPluginFromMenu(String instrumentId) {
    _store.selectInstrument(instrumentId);
    widget.onOpenPlugin?.call(instrumentId);
  }

  void _beginRename(String instrumentId) {
    setState(() {
      _renameInstrumentId = instrumentId;
      _showRenameDialog = true;
    });
  }

  void _submitRename(String name) {
    if (_renamePattern && _renamePatternId != null) {
      final String trimmed = name.trim();
      if (trimmed.isEmpty) return;
      widget.client.renamePattern(_renamePatternId!, trimmed);
      _store.refresh();
      _closeRenameDialog();
      return;
    }
    final String? id = _renameInstrumentId;
    if (id == null) return;
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      widget.client.renameInstrument(id, trimmed);
    } catch (_) {
      // The command is a stub on a fake client.
    }
    _store.refresh();
    setState(() {
      _showRenameDialog = false;
      _renameInstrumentId = null;
      _renamePattern = false;
      _renamePatternId = null;
    });
  }

  void _closeRenameDialog() {
    setState(() {
      _showRenameDialog = false;
      _renameInstrumentId = null;
      _renamePattern = false;
      _renamePatternId = null;
    });
  }

  void _duplicateInstrument(String instrumentId) {
    try {
      widget.client.duplicateInstrument(instrumentId);
    } catch (_) {
      // Hosting failed or the command is a stub.
      return;
    }
    _store.refresh();
  }

  void _deleteInstrument(String instrumentId) {
    try {
      widget.client.deleteInstrument(instrumentId);
    } catch (_) {
      // The command is a stub on a fake client.
      return;
    }
    _store.refresh();
  }

  void _hideContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final ChannelRackScreenVm vm = _buildVm();
    final String? renameId = _renameInstrumentId;

    return ScopedShortcuts(
      shortcuts: shortcutsForArea(ActionArea.pattern),
      handlers: <String, VoidCallback>{'pattern.create': _onCreatePattern},
      child: Stack(
        children: <Widget>[
          ChannelRackScreen(
            vm: vm,
            onSelectPattern: (String id) => _store.selectPattern(id),
            onPatternSecondaryTapDown: _onPatternSecondaryTapDown,
            onSelectRow: _onSelectRow,
            onRowDoubleTap: _onRowDoubleTap,
            onTogglePower: _onTogglePower,
            onStepTap: _onStepTap,
            onVolChanged: _onVolChanged,
            onPanChanged: _onPanChanged,
            onAddChannel: _onAddChannel,
            onCreatePattern: _onCreatePattern,
            onRowSecondaryTapDown: _onRowSecondaryTapDown,
            onDropInstrument: _onDropInstrument,
            onAddInstrument: _onAddInstrument,
            onReorderRow: _onReorderRow,
            onSteps: (int steps) => _store.setLength(steps),
            onInspectorVol: _onInspectorVol,
            onInspectorPan: _onInspectorPan,
            onInspectorMute: _onInspectorMute,
            onInspectorSolo: _onInspectorSolo,
            onInspectorOpenPlugin: _onInspectorOpenPlugin,
            onInspectorKeyPress: (int note) => _store.auditionNote(note),
            onPointerDownStep: (PointerDownEvent event, int rowIndex, int stepIndex) {
              final List<RackRow> visible = _store.rows;
              if (rowIndex < 0 || rowIndex >= visible.length) return;
              final RackRow row = visible[rowIndex];
              final bool velocityMode =
                  event.buttons == kSecondaryMouseButton || HardwareKeyboard.instance.isAltPressed;
              if (velocityMode) {
                _store.beginVelocityPaint();
                _store.setVelocity(row.instrumentId, stepIndex, 12900);
              } else {
                final bool active = stepIndex < row.steps.length ? !row.steps[stepIndex].active : true;
                _store.beginPaint(row.instrumentId, stepIndex, active: active);
              }
            },
            onPointerMoveStep: (PointerMoveEvent event, int rowIndex, int stepIndex) {
              final List<RackRow> visible = _store.rows;
              if (rowIndex < 0 || rowIndex >= visible.length) return;
              final RackRow row = visible[rowIndex];
              if (event.buttons == kSecondaryMouseButton || HardwareKeyboard.instance.isAltPressed) {
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
          ),
          if (_showRenameDialog)
            RenameChannelDialog(
              initialName:
                  _renamePattern
                      ? (_store.patterns
                              .cast<PatternSummary?>()
                              .firstWhere((PatternSummary? item) => item?.id == _renamePatternId, orElse: () => null)
                              ?.name ??
                          '')
                      : renameId == null
                      ? ''
                      : (_store.instrumentFor(renameId)?.name ?? ''),
              onSubmit: _submitRename,
              onClose: _closeRenameDialog,
              title: _renamePattern ? 'Rename pattern' : 'Rename channel',
              fieldLabel: _renamePattern ? 'Pattern name' : 'Channel name',
            ),
          if (_showDeletePatternDialog)
            DeletePatternDialog(
              patternName:
                  _store.patterns
                      .cast<PatternSummary?>()
                      .firstWhere((PatternSummary? item) => item?.id == _deletePatternId, orElse: () => null)
                      ?.name ??
                  'Pattern',
              usageCount:
                  _store.patterns
                      .cast<PatternSummary?>()
                      .firstWhere((PatternSummary? item) => item?.id == _deletePatternId, orElse: () => null)
                      ?.usageCount ??
                  0,
              onDelete: _confirmDeletePattern,
              onClose: _closeDeletePatternDialog,
            ),
        ],
      ),
    );
  }
}
