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
import '../../core/pattern_store.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../../core/action_registry.dart';
import '../../core/shortcuts.dart';
import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/popover_menu.dart';
import '../browser/sample_pack.dart';
import '../plugins/channel_editor_binding.dart';
import 'channel_inspector.dart';
import 'channel_rack_screen.dart';
import 'channel_settings_editor.dart';
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
    this.onOpenChannelEditor,
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

  /// Opens the shared FL-style Plugin/Settings editor. The legacy callbacks
  /// remain available for lightweight hosts and presentation tests.
  final void Function(String instrumentId, ChannelEditorTab tab)? onOpenChannelEditor;

  @override
  State<RackBinding> createState() => _RackBindingState();
}

/// The rack clipboard works on *note data*, not on channels: it is how a riff
/// written in the wrong pattern gets moved to the right one. Copy takes the
/// selected channel's notes in the current pattern, cut lifts them out, and
/// paste writes them into whichever pattern is current when it runs.
class _CopyNotesIntent extends Intent {
  const _CopyNotesIntent();
}

class _CutNotesIntent extends Intent {
  const _CutNotesIntent();
}

class _PasteNotesIntent extends Intent {
  const _PasteNotesIntent();
}

class _RackBindingState extends State<RackBinding> with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final RackStore _store;
  late final PatternStore _patternStore;
  bool _ownsController = false;
  bool _ownsStore = false;

  final Map<String, double> _gains = <String, double>{};
  final Map<String, double> _pans = <String, double>{};
  final FocusNode _focus = FocusNode(debugLabel: 'channel-rack-binding');

  OverlayEntry? _contextMenuEntry;

  /// The channel the rename dialog is pointed at, while it is open. Solo is
  /// persisted by the engine and gates non-solo instrument channels during
  /// rendering; the rack mirrors the model state for its menu and inspector.
  bool _showRenameDialog = false;
  bool _renamePattern = false;
  bool _showDeletePatternDialog = false;
  bool _showChannelSettings = false;
  InstrumentSettings? _channelSettings;
  String? _settingsInstrumentId;
  String? _deletePatternId;
  String? _renameInstrumentId;
  String? _renamePatternId;

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
    _patternStore = PatternStore(widget.client)..load();

    _controller.addListener(_onEngineChanged);
    _store.addListener(_onStoreChanged);
    _patternStore.addListener(_onPatternStoreChanged);
  }

  @override
  void dispose() {
    _hideContextMenu();
    _focus.dispose();
    _controller.removeListener(_onEngineChanged);
    _store.removeListener(_onStoreChanged);
    _patternStore.removeListener(_onPatternStoreChanged);
    _patternStore.dispose();
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

  void _onPatternStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onCreatePattern() {
    final int nextNumber = _store.patterns.length + 1;
    _patternStore.create('Pattern $nextNumber');
    _store.refresh();
  }

  void _onSelectPattern(String patternId) {
    FocusPolicy.take(_focus);
    _store.selectPattern(patternId);
    _patternStore.select(patternId);
  }

  void _noteEditStarted() => _patternStore.noteEditStarted();

  void _makeUniqueSharedPattern() {
    final SharedPatternNotice? notice = _patternStore.notice;
    if (notice == null) return;

    if (notice.clipId.isNotEmpty) {
      _patternStore.makeUnique(<String>[notice.clipId]);
      _store.refresh();
      return;
    }

    // The rack edits a pattern globally and normally has no playlist clip
    // context. Cloning and selecting the pattern gives the user an isolated
    // editing target without guessing which of its arrangement instances they
    // meant to detach.
    _patternStore.duplicate(notice.patternId);
    _patternStore.dismissNotice();
    _store.refresh();
  }

  void _selectNextEmptyPattern() {
    final List<PatternSummary> patterns = _store.patterns;
    if (patterns.isEmpty) return;
    final int currentIndex = patterns.indexWhere((PatternSummary pattern) => pattern.isCurrent);
    for (int offset = 1; offset <= patterns.length; offset++) {
      final int index = (currentIndex + offset) % patterns.length;
      if (patterns[index].noteCount == 0) {
        _onSelectPattern(patterns[index].id);
        return;
      }
    }
  }

  String _nextPatternColor(String current) {
    const List<String> palette = <String>['#EF6F91', '#4FAFF5', '#9FC65C', '#F5A623', '#9B8CFF', '#55C2A5'];
    final int index = palette.indexOf(current.toUpperCase());
    return palette[(index + 1) % palette.length];
  }

  String _nextPatternGroup(String current) {
    const List<String> groups = <String>['', 'Drums', 'Music'];
    final int index = groups.indexOf(current);
    return groups[(index + 1) % groups.length];
  }

  String _nextPatternTimeSignature(PatternSummary pattern) {
    const List<String> choices = <String>['4/4', '3/4', '6/8', '7/8'];
    final int index = choices.indexOf(pattern.timeSignature);
    return choices[(index + 1) % choices.length];
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
      _patternStore.remove(patternId);
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

  String _gridLabel(int ticks) {
    switch (ticks) {
      case 480:
        return '1/8';
      case 120:
        return '1/32';
      default:
        return '1/16';
    }
  }

  int _gridTicks(String label) {
    switch (label) {
      case '1/8':
        return 480;
      case '1/32':
        return 120;
      default:
        return 240;
    }
  }

  String _routeLabel(ProjectInstrument? instrument, {required bool inspector}) {
    final String name = instrument?.routeName.trim() ?? '';
    if (name.isEmpty) return inspector ? 'Unrouted' : '→ —';
    return inspector ? name : '→ $name';
  }

  List<MixerTrackInfo> _readMixerTracks() {
    try {
      return widget.client.readMixerTracks();
    } catch (_) {
      // Some lightweight rack clients do not expose the mixer seam.
      return const <MixerTrackInfo>[];
    }
  }

  List<String> _routeOptions(ProjectInstrument? instrument) {
    final List<String> names = <String>[
      for (final MixerTrackInfo track in _readMixerTracks())
        if (!track.isMaster) track.name,
    ];
    final String current = instrument?.routeName.trim() ?? '';
    if (current.isNotEmpty && !names.contains(current)) names.add(current);
    return names;
  }

  void _onInspectorRouteSelected(String routeName) {
    final String? instrumentId = _store.selectedInstrumentId;
    if (instrumentId == null || routeName.isEmpty || routeName == 'Unrouted') return;
    final MixerTrackInfo? track = _readMixerTracks().cast<MixerTrackInfo?>().firstWhere(
      (MixerTrackInfo? value) => value?.name == routeName,
      orElse: () => null,
    );
    if (track == null) return;
    try {
      widget.client.setInstrumentRoute(instrumentId, track.id);
      _store.refresh();
    } catch (_) {
      // The route command is unavailable on presentation-only test clients.
    }
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
        patternTabs.add(
          PatternTabVm(
            id: p.id,
            name: p.name,
            color: p.color,
            selected: p.isCurrent,
            count: p.usageCount,
            group: p.group,
            timeSignature: p.timeSignature,
          ),
        );
      }
    } else if (pattern != null) {
      patternTabs.add(PatternTabVm(id: pattern.id, name: pattern.name, selected: true));
    }

    final List<RackRow> visibleRows = _store.visibleRows;

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
          route: _routeLabel(inst, inspector: false),
          powered: !(inst?.muted ?? false),
          selected: _store.isInstrumentSelected(row.instrumentId),
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

      final List<String> routeOptions = _routeOptions(selectedInst);
      final String inspectorRoute =
          routeOptions.isEmpty && (selectedInst?.routeName.trim().isEmpty ?? true)
              ? _routeLabel(selectedInst, inspector: true)
              : (selectedInst?.routeName.trim().isEmpty ?? true ? 'Select route' : selectedInst!.routeName);

      inspectorVm = ChannelInspectorVm(
        name: selectedInst?.name ?? selectedId,
        subtitle:
            '${selectedInst?.pluginId == _kSamplePluginId ? "Sampler" : (selectedInst?.pluginName.isNotEmpty == true ? selectedInst!.pluginName : "Sampler")} · channel ${(selectedInst?.order ?? (instIndex >= 0 ? instIndex : 0)) + 1}',
        color: inspColor,
        vol: _gains[selectedId] ?? (selectedInst != null ? selectedInst.gain.clamp(0.0, 1.0) : 0.78),
        volText: _volText(selectedId, selectedInst),
        pan: _pans[selectedId] ?? (selectedInst != null ? ((selectedInst.pan.clamp(-1.0, 1.0) + 1.0) / 2.0) : 0.5),
        panText: _panText(selectedId, selectedInst),
        route: inspectorRoute,
        routeOptions: routeOptions,
        muted: selectedInst?.muted ?? false,
        soloed: _store.instrumentFor(selectedId)?.soloed ?? false,
        // The row itself can open a sample's built-in editor, but the
        // inspector's hosted-plugin action is reserved for real plug-ins.
        hostsPlugin:
            selectedInst != null && selectedInst.pluginId.isNotEmpty && selectedInst.pluginId != _kSamplePluginId,
        hostsSampler: selectedInst?.pluginId == _kSamplePluginId,
        gridLabel: _gridLabel(_store.rowFor(selectedId)?.gridTicks ?? 240),
      );
    }

    final SharedPatternNotice? sharedNotice = _patternStore.notice;

    final String? velocityInstrument = _store.selectedVelocityInstrument;
    final int? velocityStep = _store.selectedVelocityStep;
    final RackRow? velocityRow = velocityInstrument == null ? null : _store.rowFor(velocityInstrument);
    final RackStep? selectedStep =
        velocityRow != null && velocityStep != null && velocityStep < velocityRow.steps.length
            ? velocityRow.steps[velocityStep]
            : null;

    final RackToolbarVm toolbarVm = RackToolbarVm(
      channelType: 'Sampler',
      group: _store.showAll ? 'All' : 'Used',
      snap: '1/16',
      steps: stepCount,
      autoLength: pattern?.autoLength ?? false,
      groups: const <String>['All', 'Used'],
      swing: pattern?.swing ?? 0.0,
      velocity: selectedStep?.active == true ? selectedStep!.velocity : null,
      velocityStep: velocityStep,
    );

    return ChannelRackScreenVm(
      patterns: patternTabs,
      toolbar: toolbarVm,
      stepCount: stepCount,
      // The rack's time base, so a piano-roll lane places its notes and its
      // read head on the same columns the step lanes are counting.
      stepTicks: pattern?.baseGridTicks ?? 240,
      rows: rowVms,
      playingStep: playingStep,
      playingTick: playingTick,
      inspector: inspectorVm,
      sharedPatternNotice: sharedNotice == null
          ? null
          : SharedPatternNoticeVm(
              message: sharedNotice.message,
              // A rack edit has no playlist clip selection, so its fallback is
              // to clone the pattern and continue editing the clone. When the
              // store was entered from a clip, the same action repoints that
              // one clip instead.
              canMakeUnique: true,
            ),
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

  void _onShowFilter(String value) => _store.setShowAll(value == 'All');

  void _onSwingChanged(double value) {
    _noteEditStarted();
    _store.setSwing(value);
  }

  void _onVelocityDelta(int delta) {
    _noteEditStarted();
    _store.nudgeVelocity(delta);
  }

  void _setGrid(String instrumentId, String label) => _store.setGrid(instrumentId, _gridTicks(label));

  /// The grid select in the inspector acts on whatever lane is selected — the
  /// inspector has no other subject.
  void _onInspectorGrid(String label) {
    final String? id = _store.selectedInstrumentId;
    if (id == null) return;
    _setGrid(id, label);
  }

  void _removeSequence(String instrumentId) {
    _noteEditStarted();
    _store.removeSequence(instrumentId);
  }

  void _onStepTap(int rowIndex, int stepIndex) {
    final List<RackRow> visible = _store.visibleRows;
    if (rowIndex >= 0 && rowIndex < visible.length) {
      _noteEditStarted();
      _store.toggleStep(visible[rowIndex].instrumentId, stepIndex);
    }
  }

  /// Selection is silent: it points the inspector at a lane and nothing more.
  /// It must not touch the transport — narrowing a running preview to the
  /// clicked channel silenced every other lane and restarted playback from the
  /// top, and hearing one channel on its own is what solo is for.
  void _onSelectRow(int rowIndex) {
    FocusPolicy.take(_focus);
    final List<RackRow> visible = _store.visibleRows;
    if (rowIndex >= 0 && rowIndex < visible.length) {
      final String instrumentId = visible[rowIndex].instrumentId;
      widget.client.selectInstrument(instrumentId);
      _store.selectInstrument(instrumentId, additive: HardwareKeyboard.instance.isShiftPressed);
    }
  }

  void _copyNotes([String? instrumentId]) {
    _store.copyNotes(instrumentId);
  }

  /// Cut is the first half of a move: the notes leave the current pattern and
  /// wait on the clipboard. The channel and its plug-in stay exactly where they
  /// were — only this pattern's note data moves.
  void _cutNotes([String? instrumentId]) {
    if (_store.cutNotes(instrumentId)) _noteEditStarted();
  }

  /// The second half: paste writes the clipboard into whatever pattern is
  /// current now, which is what makes "cut here, select another pattern, paste"
  /// a move between patterns.
  void _pasteNotes([String? instrumentId]) {
    if (_store.pasteNotes(instrumentId)) _noteEditStarted();
  }

  /// A double-click on a lane that hosts a plug-in selects it and hands the
  /// instrument to the shell, which opens the plug-in window. The row only
  /// wires the double-tap for plug-in lanes ([RackRowVm.hostsPlugin]), but the
  /// guard keeps this robust if that ever drifts.
  void _onRowDoubleTap(int rowIndex) {
    final List<RackRow> visible = _store.visibleRows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    final String instrumentId = visible[rowIndex].instrumentId;
    widget.client.selectInstrument(instrumentId);
    _store.selectInstrument(instrumentId);
    final ProjectInstrument? inst = _store.instrumentFor(instrumentId);
    if (widget.onOpenChannelEditor != null) {
      widget.onOpenChannelEditor!(instrumentId, ChannelEditorTab.plugin);
    } else if (inst?.pluginId == _kSamplePluginId) {
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
    final List<RackRow> rows = _store.visibleRows;
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
    final List<RackRow> visible = _store.visibleRows;
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
    final List<RackRow> visible = _store.visibleRows;
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
    final List<RackRow> visible = _store.visibleRows;
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
    if (widget.onOpenChannelEditor != null) {
      widget.onOpenChannelEditor!(id, ChannelEditorTab.plugin);
    } else {
      _openPluginFromMenu(id);
    }
  }

  /// Toggles the engine-backed solo gate for [instrumentId]. Solo is exclusive
  /// in the channel rack: enabling one channel clears any previous solo, while
  /// pressing the already-soloed channel turns solo off and restores the full
  /// rack. The native publish path reapplies the gates immediately.
  void _toggleSolo(String instrumentId) {
    final ProjectInstrument? instrument = _store.instrumentFor(instrumentId);
    if (instrument == null) return;
    final bool next = !instrument.soloed;
    if (next) {
      for (final ProjectInstrument other in _store.instruments) {
        if (other.id != instrumentId && other.soloed) {
          widget.client.setInstrumentSoloed(other.id, soloed: false);
        }
      }
    }
    widget.client.setInstrumentSoloed(instrumentId, soloed: next);
    _store.refresh();
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
    final List<RackRow> visible = _store.visibleRows;
    if (rowIndex < 0 || rowIndex >= visible.length) return;
    final String instrumentId = visible[rowIndex].instrumentId;
    _showContextMenu(instrumentId, details.globalPosition);
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
                          ObMenuRowVm(label: 'Duplicate', icon: ObKitGlyphKind.plus),
                          ObMenuRowVm(label: 'Recolor', icon: ObKitGlyphKind.grid),
                          ObMenuRowVm(label: 'Time signature', icon: ObKitGlyphKind.note),
                          ObMenuRowVm(label: 'Group', icon: ObKitGlyphKind.grid),
                          ObMenuRowVm(label: 'Move earlier', icon: ObKitGlyphKind.chevronRight),
                          ObMenuRowVm(label: 'Move later', icon: ObKitGlyphKind.chevronRight),
                          ObMenuRowVm(label: 'Select next empty', icon: ObKitGlyphKind.chevronRight),
                          ObMenuRowVm(label: 'Delete', icon: ObKitGlyphKind.trash, tone: ObMenuRowTone.danger),
                        ],
                      ),
                    ],
                  ),
                  onSelect: (int index) {
                    _hideContextMenu();
                    switch (index) {
                      case 0:
                        _beginPatternRename(patternId);
                      case 1:
                        _patternStore.duplicate(patternId);
                        _store.refresh();
                      case 2:
                        final PatternSummary? pattern = _store.patterns.cast<PatternSummary?>().firstWhere(
                          (PatternSummary? item) => item?.id == patternId,
                          orElse: () => null,
                        );
                        if (pattern != null) {
                          _patternStore.recolor(patternId, _nextPatternColor(pattern.color));
                          _store.refresh();
                        }
                      case 3:
                        final PatternSummary? pattern = _store.patterns.cast<PatternSummary?>().firstWhere(
                          (PatternSummary? item) => item?.id == patternId,
                          orElse: () => null,
                        );
                        if (pattern != null) {
                          final String next = _nextPatternTimeSignature(pattern);
                          final List<String> nextParts = next.split('/');
                          _patternStore.setTimeSignature(patternId, int.parse(nextParts[0]), int.parse(nextParts[1]));
                          _store.refresh();
                        }
                      case 4:
                        final PatternSummary? pattern = _store.patterns.cast<PatternSummary?>().firstWhere(
                          (PatternSummary? item) => item?.id == patternId,
                          orElse: () => null,
                        );
                        if (pattern != null) {
                          _patternStore.setGroup(patternId, _nextPatternGroup(pattern.group));
                          _store.refresh();
                        }
                      case 5:
                        final PatternSummary? pattern = _store.patterns.cast<PatternSummary?>().firstWhere(
                          (PatternSummary? item) => item?.id == patternId,
                          orElse: () => null,
                        );
                        if (pattern != null) {
                          _patternStore.reorder(patternId, math.max(0, pattern.order - 1));
                          _store.refresh();
                        }
                      case 6:
                        final PatternSummary? pattern = _store.patterns.cast<PatternSummary?>().firstWhere(
                          (PatternSummary? item) => item?.id == patternId,
                          orElse: () => null,
                        );
                        if (pattern != null) {
                          _patternStore.reorder(patternId, pattern.order + 1);
                          _store.refresh();
                        }
                      case 7:
                        _selectNextEmptyPattern();
                      case 8:
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
    _patternStore.select(patternId);
    setState(() {
      _renamePatternId = patternId;
      _renamePattern = true;
      _showRenameDialog = true;
    });
  }

  void _onDropInstrument(int rowIndex, Object data) {
    final List<RackRow> visible = _store.visibleRows;
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

    final bool soloed = _store.instrumentFor(instrumentId)?.soloed ?? false;
    // The lane's own settings, off the lane: the divisor its steps sit on, and
    // the action that empties it. Both are things you decide about a channel
    // once, not controls you reach for while writing a rhythm, so they cost the
    // lane no width and the rack no column.
    final String gridLabel = _gridLabel(_store.rowFor(instrumentId)?.gridTicks ?? 240);
    final bool hasSequence = _store.rowFor(instrumentId)?.hasSequence ?? false;
    final bool multiSelection = _store.selectedInstrumentIds.length > 1;

    // The channel rows, with their actions in the same order. The flat index
    // the menu reports is this list, then the step fills, then delete.
    final List<ObMenuRowVm> actionRows = <ObMenuRowVm>[
      const ObMenuRowVm(label: 'Open in piano roll', icon: ObKitGlyphKind.note),
      if (hostsPlugin)
        ObMenuRowVm(
          label: isSample ? 'Open sampler' : 'Open plugin window',
          icon: isSample ? ObKitGlyphKind.waveform : ObKitGlyphKind.keyboard,
        ),
      const ObMenuRowVm(label: 'Channel settings', icon: ObKitGlyphKind.grid),
      const ObMenuRowVm(label: 'Rename', icon: ObKitGlyphKind.pencil),
      const ObMenuRowVm(label: 'Duplicate', icon: ObKitGlyphKind.plus),
      const ObMenuRowVm(label: 'Recolor', icon: ObKitGlyphKind.grid),
      // Moving a riff to another pattern: cut here, switch pattern, paste. The
      // rows name the pattern they act on so the reference semantics are on
      // screen rather than in the manual.
      if (hasSequence) const ObMenuRowVm(label: 'Copy notes', icon: ObKitGlyphKind.note, shortcut: '⌘C'),
      if (hasSequence)
        const ObMenuRowVm(label: 'Cut notes from this pattern', icon: ObKitGlyphKind.note, shortcut: '⌘X'),
      if (_store.canPaste)
        const ObMenuRowVm(label: 'Paste notes into this pattern', icon: ObKitGlyphKind.note, shortcut: '⌘V'),
      ObMenuRowVm(
        label: 'Solo',
        checkable: true,
        checked: soloed,
        tone: soloed ? ObMenuRowTone.active : ObMenuRowTone.normal,
      ),
      if (multiSelection) const ObMenuRowVm(label: 'Mute selected', icon: ObKitGlyphKind.check),
      if (multiSelection)
        const ObMenuRowVm(label: 'Delete selected', icon: ObKitGlyphKind.trash, tone: ObMenuRowTone.danger),
    ];
    final List<void Function()> actions = <void Function()>[
      () => widget.onOpenPianoRoll?.call(instrumentId),
      if (hostsPlugin) () => _openPluginFromMenu(instrumentId),
      () => _openChannelSettings(instrumentId),
      () => _beginRename(instrumentId),
      () => _duplicateInstrument(instrumentId),
      () => _recolorInstrument(instrumentId),
      if (hasSequence) () => _copyNotes(instrumentId),
      if (hasSequence) () => _cutNotes(instrumentId),
      if (_store.canPaste) () => _pasteNotes(instrumentId),
      () => _toggleSolo(instrumentId),
      if (multiSelection) () => _toggleSelectedMute(),
      if (multiSelection) () => _deleteSelectedInstruments(),
    ];

    // The divisors, then — only for a lane that has something to clear — the
    // clear action. A row that would do nothing is left out rather than shown
    // dead: the menu is built per lane, so it can simply not offer it.
    const List<String> gridLabels = <String>['1/8', '1/16', '1/32'];
    final List<ObMenuRowVm> gridRows = <ObMenuRowVm>[
      for (final String label in gridLabels)
        ObMenuRowVm(
          label: label,
          checkable: true,
          checked: label == gridLabel,
          tone: label == gridLabel ? ObMenuRowTone.active : ObMenuRowTone.normal,
        ),
      if (hasSequence) const ObMenuRowVm(label: 'Clear steps', icon: ObKitGlyphKind.trash),
    ];
    for (final String label in gridLabels) {
      actions.add(() => _setGrid(instrumentId, label));
    }
    if (hasSequence) actions.add(() => _removeSequence(instrumentId));

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
                    ObMenuSectionVm(header: 'Step grid', separated: true, rows: gridRows),
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
    widget.client.selectInstrument(instrumentId);
    _store.selectInstrument(instrumentId);
    if (widget.onOpenChannelEditor != null) {
      widget.onOpenChannelEditor!(instrumentId, ChannelEditorTab.plugin);
    } else if (_store.instrumentFor(instrumentId)?.pluginId == _kSamplePluginId) {
      widget.onOpenSampler?.call(instrumentId);
    } else {
      widget.onOpenPlugin?.call(instrumentId);
    }
  }

  void _onInspectorOpenSampler() {
    final String? id = _store.selectedInstrumentId;
    if (id == null || _store.instrumentFor(id)?.pluginId != _kSamplePluginId) return;
    if (widget.onOpenChannelEditor != null) {
      widget.onOpenChannelEditor!(id, ChannelEditorTab.plugin);
    } else {
      widget.onOpenSampler?.call(id);
    }
  }

  void _openChannelSettings(String instrumentId) {
    if (widget.onOpenChannelEditor != null) {
      widget.onOpenChannelEditor!(instrumentId, ChannelEditorTab.settings);
      return;
    }
    final ProjectInstrument? instrument = _store.instrumentFor(instrumentId);
    if (instrument == null) return;
    InstrumentSettings settings = const InstrumentSettings();
    try {
      settings = widget.client.readInstrumentSettings(instrumentId);
    } catch (_) {
      // Presentation fakes can still open the editor with safe defaults.
    }
    setState(() {
      _settingsInstrumentId = instrumentId;
      _channelSettings = settings;
      _showChannelSettings = true;
    });
  }

  void _applyChannelSettings(InstrumentSettings settings) {
    final String? instrumentId = _settingsInstrumentId;
    if (instrumentId == null) return;
    try {
      widget.client.setInstrumentSettings(instrumentId, settings);
    } catch (_) {
      return;
    }
    _store.refresh();
    setState(() {
      _showChannelSettings = false;
      _settingsInstrumentId = null;
      _channelSettings = null;
    });
  }

  void _closeChannelSettings() {
    setState(() {
      _showChannelSettings = false;
      _settingsInstrumentId = null;
      _channelSettings = null;
    });
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
      _patternStore.rename(_renamePatternId!, trimmed);
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

  void _deleteSelectedInstruments() {
    final List<String> ids = _store.selectedInstrumentIds.toList(growable: false);
    if (ids.isEmpty) return;
    try {
      for (final String id in ids) {
        widget.client.deleteInstrument(id);
      }
    } catch (_) {
      return;
    }
    _store.refresh();
  }

  void _toggleSelectedMute() {
    final List<ProjectInstrument> selected = <ProjectInstrument>[
      for (final String id in _store.selectedInstrumentIds)
        if (_store.instrumentFor(id) != null) _store.instrumentFor(id)!,
    ];
    if (selected.isEmpty) return;
    final bool mute = selected.any((ProjectInstrument instrument) => !instrument.muted);
    for (final ProjectInstrument instrument in selected) {
      try {
        widget.client.setInstrumentMuted(instrument.id, muted: mute);
      } catch (_) {
        return;
      }
    }
    _store.refresh();
  }

  String _nextInstrumentColor(String current) {
    const List<String> palette = <String>[
      '#EF6F91',
      '#4FAFF5',
      '#9FC65C',
      '#F5A623',
      '#9B8CFF',
      '#55C2A5',
    ];
    final int index = palette.indexOf(current.toUpperCase());
    return palette[(index + 1) % palette.length];
  }

  void _recolorInstrument(String instrumentId) {
    final ProjectInstrument? instrument = _store.instrumentFor(instrumentId);
    if (instrument == null) return;
    try {
      widget.client.recolorInstrument(instrumentId, _nextInstrumentColor(instrument.color));
    } catch (_) {
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
      shortcuts: <ShortcutActivator, Intent>{
        ...shortcutsForArea(ActionArea.pattern),
        const SingleActivator(LogicalKeyboardKey.space): const _TogglePatternPreviewIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): const _CopyNotesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): const _CutNotesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): const _PasteNotesIntent(),
      },
      handlers: <String, VoidCallback>{'pattern.create': _onCreatePattern},
      extraActions: <Type, Action<Intent>>{
        _TogglePatternPreviewIntent: CallbackAction<_TogglePatternPreviewIntent>(
          onInvoke: (_) {
            final RackPattern? pattern = _store.pattern;
            if (pattern == null) return null;
            if (_controller.patternPreviewing) {
              _controller.stopPatternPreview();
            } else {
              _controller.playPatternPreview(pattern.id);
            }
            return null;
          },
        ),
        _CopyNotesIntent: CallbackAction<_CopyNotesIntent>(
          onInvoke: (_) {
            _copyNotes();
            return null;
          },
        ),
        _CutNotesIntent: CallbackAction<_CutNotesIntent>(
          onInvoke: (_) {
            _cutNotes();
            return null;
          },
        ),
        _PasteNotesIntent: CallbackAction<_PasteNotesIntent>(
          onInvoke: (_) {
            _pasteNotes();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focus,
        child: Stack(
          children: <Widget>[
            ChannelRackScreen(
              vm: vm,
              onSelectPattern: _onSelectPattern,
              onPatternSecondaryTapDown: _onPatternSecondaryTapDown,
              onSelectRow: _onSelectRow,
              onRowDoubleTap: _onRowDoubleTap,
              onTogglePower: _onTogglePower,
              onStepTap: _onStepTap,
              onVolChanged: _onVolChanged,
              onPanChanged: _onPanChanged,
              onRouteTap: (_) => widget.onOpenMixer?.call(),
              onAddChannel: _onAddChannel,
              onCreatePattern: _onCreatePattern,
              onRowSecondaryTapDown: _onRowSecondaryTapDown,
              onDropInstrument: _onDropInstrument,
              onAddInstrument: _onAddInstrument,
              onReorderRow: _onReorderRow,
              onSteps: (int steps) => _store.setLength(steps),
              onSwing: _onSwingChanged,
              onVelocityDelta: _onVelocityDelta,
              onInspectorVol: _onInspectorVol,
              onInspectorPan: _onInspectorPan,
              onInspectorMute: _onInspectorMute,
              onInspectorSolo: _onInspectorSolo,
              onInspectorOpenPlugin: _onInspectorOpenPlugin,
              onInspectorOpenSampler: _onInspectorOpenSampler,
              onInspectorRouteTap: widget.onOpenMixer,
              onInspectorRouteSelected: _onInspectorRouteSelected,
              onGroup: _onShowFilter,
              onInspectorGrid: _onInspectorGrid,
              onDismissSharedPatternNotice: _patternStore.dismissNotice,
              onMakeUniqueSharedPattern: _makeUniqueSharedPattern,
              onInspectorKeyPress: (int note) => _store.auditionNote(note),
              onPointerDownStep: (PointerDownEvent event, int rowIndex, int stepIndex) {
                final List<RackRow> visible = _store.visibleRows;
                if (rowIndex < 0 || rowIndex >= visible.length) return;
                final RackRow row = visible[rowIndex];
                final bool velocityMode =
                    event.buttons == kSecondaryMouseButton || HardwareKeyboard.instance.isAltPressed;
                if (velocityMode) {
                  _noteEditStarted();
                  _store.beginVelocityPaint();
                  _store.setVelocity(row.instrumentId, stepIndex, 12900);
                } else {
                  _noteEditStarted();
                  final bool active = stepIndex < row.steps.length ? !row.steps[stepIndex].active : true;

                  _store.beginPaint(row.instrumentId, stepIndex, active: active);
                }
              },
              onPointerMoveStep: (PointerMoveEvent event, int rowIndex, int stepIndex) {
                final List<RackRow> visible = _store.visibleRows;
                if (rowIndex < 0 || rowIndex >= visible.length) return;
                final RackRow row = visible[rowIndex];
                if (event.buttons == kSecondaryMouseButton || HardwareKeyboard.instance.isAltPressed) {
                  _noteEditStarted();
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
            if (_showChannelSettings && _channelSettings != null && _settingsInstrumentId != null)
              ChannelSettingsEditor(
                channelName: _store.instrumentFor(_settingsInstrumentId!)?.name ?? 'Channel',
                initial: _channelSettings!,
                onApply: _applyChannelSettings,
                onClose: _closeChannelSettings,
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
      ),
    );
  }
}

class _TogglePatternPreviewIntent extends Intent {
  const _TogglePatternPreviewIntent();
}
