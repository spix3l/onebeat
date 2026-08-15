// PlaylistBinding — wires playlist presentation to the engine and store (UI-D-04).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../core/shortcuts.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import '../browser/sample_pack.dart';
import '../browser/sample_pack_platform.dart';
import 'audio_waveform.dart';
import 'clip_card.dart';
import 'playlist_canvas.dart';
import 'playlist_screen.dart';
import 'playlist_screen_vm.dart';
import 'playlist_selection.dart';
import 'playlist_store.dart';

class PlaylistBinding extends StatefulWidget {
  const PlaylistBinding({
    required this.client,
    this.controller,
    this.store,
    this.onOpenPattern,
    this.externalAudioDrop,
    this.lastClickedItem,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;
  final PlaylistStore? store;
  final void Function(String patternId, String clipId)? onOpenPattern;
  final AudioFileDrop? externalAudioDrop;
  final PlaylistInsertItem? lastClickedItem;

  @override
  State<PlaylistBinding> createState() => _PlaylistBindingState();
}

class _PlaylistBindingState extends State<PlaylistBinding> with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final PlaylistStore _store;
  final FocusNode _focus = FocusNode(debugLabel: 'playlist-binding');
  final GlobalKey _canvasKey = GlobalKey();
  bool _ownsController = false;
  bool _ownsStore = false;
  String _draggingClipId = '';
  String _resizingClipId = '';
  int _resizeOriginLength = 0;
  int _dragStartLane = 0;
  Offset _dragPixels = Offset.zero;
  final Map<String, List<double>> _waveforms = <String, List<double>>{};
  final Set<String> _waveformLoads = <String>{};
  String _historySignature = '';
  bool _previewCacheReady = false;
  String _previewPatternId = '';
  String _previewInstrumentName = '';
  List<ClipPreviewNoteVm> _previewNotes = const <ClipPreviewNoteVm>[];

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
      _store = PlaylistStore(widget.client)..refresh();
      _ownsStore = true;
    }

    _controller.addListener(_onEngineChanged);
    _store.addListener(_onStoreChanged);
    if (widget.lastClickedItem != null) {
      _store.setLastClickedItem(widget.lastClickedItem!);
    }
    _historySignature = _projectHistorySignature();
    // Shown from the view switcher, so it owns the keyboard immediately rather
    // than only after the first click on the canvas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusPolicy.take(_focus);
      _consumeExternalAudioDrop(widget.externalAudioDrop);
    });
  }

  @override
  void didUpdateWidget(covariant PlaylistBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastClickedItem != null && !identical(widget.lastClickedItem, oldWidget.lastClickedItem)) {
      final PlaylistInsertItem item = widget.lastClickedItem!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(widget.lastClickedItem, item)) {
          _store.setLastClickedItem(item);
        }
      });
    }
    if (!identical(widget.externalAudioDrop, oldWidget.externalAudioDrop)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _consumeExternalAudioDrop(widget.externalAudioDrop);
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onEngineChanged);
    _store.removeListener(_onStoreChanged);
    if (_ownsStore) {
      _store.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  String _projectHistorySignature() {
    try {
      return '${widget.client.canUndoProject}:${widget.client.undoProjectName}: '
          '${widget.client.canRedoProject}:${widget.client.redoProjectName}';
    } catch (_) {
      // Lightweight fake clients used by presentation tests do not implement
      // project history. Their store is already the source of truth.
      return '';
    }
  }

  void _onEngineChanged() {
    final String history = _projectHistorySignature();
    // Undo and redo are dispatched by the shell's controller, outside this
    // store. Refresh only when the history head changes, rather than re-reading
    // every clip on every transport frame.
    if (history.isNotEmpty && _historySignature.isNotEmpty && history != _historySignature) {
      _store.refresh();
    }
    _historySignature = history;
    if (mounted) setState(() {});
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _requestWaveform(String path) {
    if (path.isEmpty || _waveforms.containsKey(path) || !_waveformLoads.add(path)) {
      return;
    }
    loadAudioWaveform(path).then((List<double> waveform) {
      _waveformLoads.remove(path);
      if (!mounted) return;
      setState(() => _waveforms[path] = waveform);
    });
  }

  /// The colour every entity carries until something recolours it
  /// (`entities.h`). Stored, so it arrives here indistinguishable from a
  /// deliberate choice — and a project of twelve lanes then paints twelve
  /// identical blue headers, which tells the user nothing about which lane is
  /// which. Treated as "no colour chosen" so untouched lanes and clips fall
  /// through to the cycling identity palette instead.
  static const String _unassignedColor = '#6C8CFF';

  Color _resolveColor(int index, String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty && colorStr.toUpperCase() != _unassignedColor) {
      final int parsed = int.tryParse(colorStr.replaceFirst('#', ''), radix: 16) ?? 0;
      if (parsed != 0) {
        return Color(0xFF000000 | parsed);
      }
    }
    return channelColors[index % channelColors.length];
  }

  void _refreshPatternPreview() {
    final PatternSummary? current = _store.patterns.cast<PatternSummary?>().firstWhere(
      (PatternSummary? pattern) => pattern?.isCurrent ?? false,
      orElse: () => _store.patterns.isEmpty ? null : _store.patterns.first,
    );
    final String patternId = current?.id ?? '';
    if (_previewCacheReady && patternId == _previewPatternId) return;

    _previewCacheReady = true;
    _previewPatternId = patternId;
    _previewInstrumentName = '';
    _previewNotes = const <ClipPreviewNoteVm>[];
    if (current == null) return;

    try {
      final List<ProjectInstrument> instruments = widget.client.readInstruments();
      final ProjectInstrument? selected = instruments.cast<ProjectInstrument?>().firstWhere(
        (ProjectInstrument? instrument) => instrument?.selected ?? false,
        orElse: () => instruments.isEmpty ? null : instruments.first,
      );
      final List<ClipPreviewNoteVm> notes = <ClipPreviewNoteVm>[];
      final List<String> names = <String>[];
      for (final ProjectInstrument instrument
          in selected == null ? const <ProjectInstrument>[] : <ProjectInstrument>[selected]) {
        final List<SequenceNote> sequence = widget.client.readNotes(instrument.id);
        if (sequence.isEmpty) continue;
        if (instrument.name.isNotEmpty) names.add(instrument.name);
        for (final SequenceNote note in sequence) {
          if (notes.length >= 96) break;
          final double patternLength = current.lengthTicks <= 0
              ? ticksPerBar.toDouble()
              : current.lengthTicks.toDouble();
          notes.add(
            ClipPreviewNoteVm(
              x: note.startTicks / patternLength,
              width: (note.lengthTicks / patternLength).clamp(0.01, 1.0),
              y: note.key / 127.0,
            ),
          );
        }
      }
      _previewInstrumentName = names.join(' + ');
      _previewNotes = notes;
    } catch (_) {
      // Lightweight clients may not expose project instruments or notes.
    }
  }

  List<ClipPreviewNoteVm> _previewForClip(ArrangementClip clip) {
    if (clip.patternId == _previewPatternId && _previewNotes.isNotEmpty) {
      return _previewNotes;
    }
    // A non-current pattern still gets a useful density silhouette from the
    // derived note count in ob_clip_info, without changing the current pattern
    // merely to inspect another clip.
    if (clip.noteCount <= 0) return const <ClipPreviewNoteVm>[];
    final int count = clip.noteCount.clamp(1, 24);
    return <ClipPreviewNoteVm>[
      for (int index = 0; index < count; index++)
        ClipPreviewNoteVm(
          x: count == 1 ? 0.08 : index / (count - 1) * 0.88,
          width: 0.025, // token-lint-ok: normalized clip-preview ratio
          y: ((index * 17) % 100) / 100.0,
        ),
    ];
  }

  String _formatDuration(int lengthTicks) {
    final double beats = lengthTicks / ticksPerQuarter;
    final int seconds = (beats * (60.0 / 120.0)).round();
    final int minutes = seconds ~/ 60;
    final int remainingSec = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSec.toString().padLeft(2, '0')}';
  }

  PlaylistScreenVm _buildVm(OneBeatTokens tokens) {
    _refreshPatternPreview();
    final Map<String, int> laneOrderMap = <String, int>{};
    for (int i = 0; i < _store.lanes.length; i++) {
      laneOrderMap[_store.lanes[i].id] = i;
    }

    final List<ClipVm> clipVms = <ClipVm>[
      for (int i = 0; i < _store.clips.length; i++)
        (() {
          final ArrangementClip clip = _store.clips[i];
          final int laneIndex = laneOrderMap[clip.laneId] ?? 0;
          if (clip.isAudio) _requestWaveform(clip.audioPath);
          return ClipVm(
            id: clip.id.hashCode,
            name: clip.name.isNotEmpty ? clip.name : 'Clip ${i + 1}',
            duration: _formatDuration(clip.lengthTicks),
            color: _resolveColor(laneIndex, clip.color),
            startBar: clip.startTicks / ticksPerBar,
            lengthBars: clip.lengthTicks / ticksPerBar,
            lane: laneIndex,
            selected: _store.selectedClipIds.contains(clip.id),
            isAudio: clip.isAudio,
            waveform: _waveforms[clip.audioPath] ?? const <double>[],
            instrumentName: clip.isAudio ? '' : _previewInstrumentName,
            previewNotes: clip.isAudio ? const <ClipPreviewNoteVm>[] : _previewForClip(clip),
          );
        })(),
    ];

    final List<PlaylistLaneVm> laneVms = <PlaylistLaneVm>[
      for (final ArrangementLane lane in _store.lanes)
        PlaylistLaneVm(
          id: lane.id,
          name: lane.name,
          color: _resolveColor(laneOrderMap[lane.id] ?? 0, lane.color),
          muted: lane.muted,
          soloed: lane.soloed,
          collapsed: lane.collapsed,
          clipCount: lane.clipCount,
        ),
    ];

    int? playhead16ths;
    final EngineSnapshot snapshot = _controller.snapshot;
    if (snapshot.playing) {
      playhead16ths = (snapshot.positionBeats * 4).round();
    }

    final double pxPerBar = tokens.size.playlistPxPerBar * _store.horizontalZoom;
    final PlaylistMarquee? marquee = _store.marquee;
    final Rect? marqueeRect = marquee == null
        ? null
        : Rect.fromLTRB(
            (marquee.lowTick - _store.scrollTicks) / ticksPerBar * pxPerBar,
            (marquee.lowLane - _store.scrollLanes) * tokens.size.playlistLaneHeight,
            (marquee.highTick - _store.scrollTicks) / ticksPerBar * pxPerBar,
            (marquee.highLane + 1 - _store.scrollLanes) * tokens.size.playlistLaneHeight,
          );

    final PlaylistVm canvasVm = PlaylistVm(
      clips: clipVms,
      lanes: laneVms,
      pxPerBar: pxPerBar,
      laneCountOverride: _store.lanes.length,
      playheadBar16ths: playhead16ths,
      scrollTicks: _store.scrollTicks,
      scrollLanes: _store.scrollLanes,
      snapTicks: _store.snap.ticks,
      marqueeRect: marqueeRect,
      headerTitle: 'Playlist',
      headerRight: '${snapshot.tempoBpm.toStringAsFixed(0)} BPM · 4/4',
    );

    ClipInspectorVm inspectorVm = const ClipInspectorVm(selectedCount: 0);
    if (_store.selectedClipIds.length > 1) {
      inspectorVm = ClipInspectorVm(selectedCount: _store.selectedClipIds.length);
    } else if (_store.selectedClipIds.length == 1) {
      final ArrangementClip? clip = _store.selectedClip;
      if (clip != null) {
        final int laneIndex = laneOrderMap[clip.laneId] ?? 0;
        inspectorVm = ClipInspectorVm(
          selectedCount: 1,
          clipId: clip.id,
          name: clip.name,
          color: _resolveColor(laneIndex, clip.color),
          usageText: clip.isAudio
              ? 'Audio file · full source duration'
              : (clip.isShared ? 'Pattern used in ${clip.usageCount} clips' : 'Pattern used once'),
          isShared: !clip.isAudio && clip.isShared,
          isAudio: clip.isAudio,
          startBar: (clip.startTicks / ticksPerBar).round(),
          lengthBars: (clip.lengthTicks / ticksPerBar).ceil().clamp(1, 1000),
          offsetBeats: (clip.windowStartTicks / ticksPerQuarter).round(),
          loop: clip.loop,
          muted: clip.muted,
          transpose: clip.transpose,
        );
      }
    }

    return PlaylistScreenVm(canvas: canvasVm, inspector: inspectorVm);
  }

  bool get _isLasso => HardwareKeyboard.instance.isAltPressed || HardwareKeyboard.instance.isMetaPressed;

  Offset _canvasLocalFromGlobal(Offset global) {
    final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  int _tickAtCanvas(Offset local) =>
      ((local.dx / (OneBeatTokens.dark().size.playlistPxPerBar * _store.horizontalZoom) +
                  _store.scrollTicks / ticksPerBar) *
              ticksPerBar)
          .round();

  int _laneAtCanvas(Offset local) =>
      (local.dy / OneBeatTokens.dark().size.playlistLaneHeight + _store.scrollLanes).floor();

  void _beginMarquee(Offset local) {
    if (!_isLasso) return;
    FocusPolicy.take(_focus);
    _store.beginMarquee(_tickAtCanvas(local), _laneAtCanvas(local));
  }

  void _updateMarquee(Offset local) {
    if (_store.dragKind != ClipDragKind.marquee) return;
    _store.updateMarquee(_tickAtCanvas(local), _laneAtCanvas(local));
  }

  void _endMarquee() {
    if (_store.dragKind == ClipDragKind.marquee) _store.endMarquee();
  }

  void _cancelMarquee() {
    if (_store.dragKind == ClipDragKind.marquee) _store.cancelMarquee();
  }

  void _onClipDoubleTap(int hashId) {
    for (final ArrangementClip clip in _store.clips) {
      if (clip.id.hashCode == hashId && !clip.isAudio && clip.patternId.isNotEmpty) {
        FocusPolicy.take(_focus);
        widget.onOpenPattern?.call(clip.patternId, clip.id);
        return;
      }
    }
  }

  void _onClipTap(int hashId) {
    FocusPolicy.take(_focus);
    for (final ArrangementClip clip in _store.clips) {
      if (clip.id.hashCode == hashId) {
        if (_isLasso) {
          _store.selectClip(clip.id);
        } else if (HardwareKeyboard.instance.isShiftPressed) {
          _store.selectClip(clip.id, additive: true);
        } else {
          _store.selectClip(clip.id);
        }
        return;
      }
    }
  }

  void _consumeExternalAudioDrop(AudioFileDrop? drop) {
    if (!mounted || drop == null) return;
    final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset local = box.globalToLocal(Offset(drop.x, drop.y));
    final double bar =
        local.dx / (OneBeatTokens.dark().size.playlistPxPerBar * _store.horizontalZoom) +
        _store.scrollTicks / ticksPerBar;
    final int lane = (local.dy / OneBeatTokens.dark().size.playlistLaneHeight + _store.scrollLanes).floor();
    _ensureLane(lane);
    for (final String path in drop.paths) {
      final String extension = path.split('.').last.toLowerCase();
      if (!SamplePackScanner.supportedExtensions.contains(extension)) continue;
      _onSampleDrop(SampleAsset(id: 'sample:$path', name: path.split('/').last, path: path), bar, lane);
    }
  }

  void _onClipResizeStart(int hashId, DragStartDetails details) {
    ArrangementClip? clip;
    for (final ArrangementClip candidate in _store.clips) {
      if (candidate.id.hashCode == hashId) {
        clip = candidate;
        break;
      }
    }
    if (clip == null) return;
    FocusPolicy.take(_focus);
    if (!_store.selectedClipIds.contains(clip.id)) {
      _store.selectClip(clip.id);
    }
    _resizingClipId = clip.id;
    _resizeOriginLength = clip.lengthTicks;
    _dragPixels = Offset.zero;
    _store.beginClipDrag(ClipDragKind.resizeEnd, name: 'Resize clip');
  }

  void _onClipResizeUpdate(int hashId, DragUpdateDetails details) {
    if (_resizingClipId.isEmpty) return;
    _dragPixels += details.delta;
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final double pxPerBar = tokens.size.playlistPxPerBar * _store.horizontalZoom;
    final int deltaTicks = _store.snapDelta((_dragPixels.dx / pxPerBar * ticksPerBar).round());
    _store.updateClipResize(_resizingClipId, _resizeOriginLength + deltaTicks);
  }

  void _onClipResizeEnd(int hashId, DragEndDetails details) {
    if (_resizingClipId.isEmpty) return;
    _store.endClipDrag();
    _resizingClipId = '';
    _resizeOriginLength = 0;
    _dragPixels = Offset.zero;
  }

  void _onClipResizeCancel(int hashId) {
    if (_resizingClipId.isEmpty) return;
    _store.cancelClipDrag();
    _resizingClipId = '';
    _resizeOriginLength = 0;
    _dragPixels = Offset.zero;
  }

  void _onClipPanStart(int hashId, DragStartDetails details) {
    if (_isLasso) {
      _beginMarquee(_canvasLocalFromGlobal(details.globalPosition));
      return;
    }
    final ArrangementClip? clip = _store.clips.cast<ArrangementClip?>().firstWhere(
      (ArrangementClip? item) => item?.id.hashCode == hashId,
      orElse: () => null,
    );
    if (clip == null) return;
    FocusPolicy.take(_focus);
    if (!_store.selectedClipIds.contains(clip.id)) {
      _store.selectClip(clip.id);
    }
    _draggingClipId = clip.id;
    _dragStartLane = _store.lanes
        .indexWhere((ArrangementLane lane) => lane.id == clip.laneId)
        .clamp(0, _store.lanes.length - 1);
    _dragPixels = Offset.zero;
    _store.beginClipDrag(ClipDragKind.move);
  }

  void _onPlaylistScroll(Offset delta) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool horizontal = HardwareKeyboard.instance.isShiftPressed && delta.dx == 0;
    _store.panBy(
      deltaTicks: (horizontal ? delta.dy : delta.dx) / _store.pixelsPerTick,
      deltaLanes: horizontal ? 0 : delta.dy / tokens.size.playlistLaneHeight,
    );
  }

  void _onPlaylistPanZoom(Offset delta) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    _store.panBy(deltaTicks: -delta.dx / _store.pixelsPerTick, deltaLanes: -delta.dy / tokens.size.playlistLaneHeight);
  }

  void _onSnapChanged(String label) {
    for (final GridChoice choice in GridChoice.all) {
      if (choice.label == label) {
        _store.setSnap(choice);
        return;
      }
    }
  }

  void _onPlaylistSeek(double bar) {
    widget.client.seekBeats(bar * 4.0);
  }

  void _onClipPanUpdate(int hashId, DragUpdateDetails details) {
    if (_store.dragKind == ClipDragKind.marquee) {
      _updateMarquee(_canvasLocalFromGlobal(details.globalPosition));
      return;
    }
    if (_draggingClipId.isEmpty) return;
    _dragPixels += details.delta;
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final double pxPerBar = tokens.size.playlistPxPerBar * _store.horizontalZoom;
    final int deltaTicks = _store.snapDelta((_dragPixels.dx / pxPerBar * ticksPerBar).round());
    if (_store.lanes.isEmpty) return;
    final int laneIndex = (_dragStartLane + (_dragPixels.dy / tokens.size.playlistLaneHeight).round()).clamp(
      0,
      1 << 20,
    );
    _ensureLane(laneIndex);
    _store.updateClipMove(deltaTicks, laneId: _store.lanes[laneIndex].id);
  }

  void _onClipPanEnd(int hashId, DragEndDetails details) {
    if (_store.dragKind == ClipDragKind.marquee) {
      _endMarquee();
      return;
    }
    if (_draggingClipId.isEmpty) return;
    _store.endClipDrag();
    _draggingClipId = '';
    _dragStartLane = 0;
    _dragPixels = Offset.zero;
  }

  void _onClipPanCancel(int hashId) {
    if (_store.dragKind == ClipDragKind.marquee) {
      _cancelMarquee();
      return;
    }
    if (_draggingClipId.isEmpty) return;
    _store.cancelClipDrag();
    _draggingClipId = '';
    _dragStartLane = 0;
    _dragPixels = Offset.zero;
  }

  void _ensureLane(int laneIndex) {
    if (laneIndex < 0) return;
    while (_store.lanes.length <= laneIndex) {
      _store.addLane('Track ${_store.lanes.length + 1}');
    }
  }

  void _onPlaylistDrop(Object data, double bar, int lane) {
    if (data is PlaylistInsertItem) {
      _ensureLane(lane);
      if (_store.lanes.isEmpty) return;
      final int targetLane = lane.clamp(0, _store.lanes.length - 1);
      _store.placeItem(data, _store.lanes[targetLane].id, (bar * ticksPerBar).round());
      return;
    }
    _onSampleDrop(data, bar, lane);
  }

  void _onSampleDrop(Object data, double bar, int lane) {
    if (data is! SampleAsset) return;
    _ensureLane(lane);
    if (_store.lanes.isEmpty) return;

    final int targetLaneIndex = lane.clamp(0, _store.lanes.length - 1);
    final ArrangementLane targetLane = _store.lanes[targetLaneIndex];
    final int startTicks = _store.snapTick((bar * ticksPerBar).round());
    try {
      widget.client.addAudioClip(targetLane.id, data.path, startTicks);
    } catch (_) {
      // A malformed or unreadable file is rejected by the native loader.
      return;
    }
    _store.refresh();
    final ArrangementClip? added = _store.clips.cast<ArrangementClip?>().firstWhere(
      (ArrangementClip? clip) =>
          clip?.isAudio == true && clip?.laneId == targetLane.id && clip?.startTicks == startTicks,
      orElse: () => null,
    );
    if (added != null) _store.selectClip(added.id);
  }

  void _onBackgroundTap(double bar, int lane) {
    FocusPolicy.take(_focus);
    if (_isLasso) {
      _store.clearClipSelection();
      return;
    }
    // Empty space is an insertion target, not merely a deselection target.
    // The browser/current-pattern selection is the last playlist item, so the
    // next click places another instance exactly where the user asked.
    _ensureLane(lane);
    if (_store.lanes.isEmpty) return;

    final int targetLaneIndex = lane.clamp(0, _store.lanes.length - 1);
    final ArrangementLane targetLane = _store.lanes[targetLaneIndex];
    final int startTicks = (bar * ticksPerBar).round();
    _store.placeLastClickedItem(targetLane.id, startTicks);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PlaylistScreenVm vm = _buildVm(tokens);

    return ScopedShortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
        // ⌘B is FL's duplicate, and the key the piano roll already answers to;
        // ⌘D is kept as the alias the rest of the app uses.
        SingleActivator(LogicalKeyboardKey.keyB, meta: true): _DuplicateIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, meta: true): _DuplicateIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, meta: true): _SelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.escape): CancelIntent(),
      },
      handlers: const <String, VoidCallback>{},
      extraActions: <Type, Action<Intent>>{
        CancelIntent: CallbackAction<CancelIntent>(
          onInvoke: (_) {
            if (_store.dragKind != ClipDragKind.none) {
              _store.cancelClipDrag();
            } else {
              _store.clearClipSelection();
            }
            return null;
          },
        ),
        _DeleteIntent: CallbackAction<_DeleteIntent>(
          onInvoke: (_) {
            _store.deleteSelection();
            return null;
          },
        ),
        _DuplicateIntent: CallbackAction<_DuplicateIntent>(
          onInvoke: (_) {
            _store.duplicateSelection();
            return null;
          },
        ),
        _SelectAllIntent: CallbackAction<_SelectAllIntent>(
          onInvoke: (_) {
            _store.selectClips(_store.clips.map((ArrangementClip c) => c.id));
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focus,
        child: PlaylistScreen(
          vm: vm,
          canvasKey: _canvasKey,
          onClipTap: _onClipTap,
          onClipDoubleTap: _onClipDoubleTap,
          onClipPanStart: _onClipPanStart,
          onClipPanUpdate: _onClipPanUpdate,
          onClipPanEnd: _onClipPanEnd,
          onClipPanCancel: _onClipPanCancel,
          onClipResizeStart: _onClipResizeStart,
          onClipResizeUpdate: _onClipResizeUpdate,
          onClipResizeEnd: _onClipResizeEnd,
          onClipResizeCancel: _onClipResizeCancel,
          onBackgroundPanStart: (DragStartDetails details) {
            _beginMarquee(details.localPosition);
          },
          onBackgroundPanUpdate: (DragUpdateDetails details) {
            _updateMarquee(details.localPosition);
          },
          onBackgroundPanEnd: (_) => _endMarquee(),
          onBackgroundPanCancel: _cancelMarquee,
          onBackgroundTap: _onBackgroundTap,
          onDrop: _onPlaylistDrop,
          onScroll: _onPlaylistScroll,
          onPanZoom: _onPlaylistPanZoom,
          onSeekBar: _onPlaylistSeek,
          onSnapChanged: _onSnapChanged,
          onStartChanged: (int bar) {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) {
              _store.setClipStart(clip.id, bar * ticksPerBar);
            }
          },
          onLengthChanged: (int bars) {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) {
              _store.resizeClip(clip.id, bars * ticksPerBar);
            }
          },
          onOffsetChanged: (int beats) {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) {
              _store.setClipWindowStart(clip.id, beats * ticksPerQuarter);
            }
          },
          onLoopToggle: (bool loop) {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) {
              _store.setClipLoop(clip.id, loop: loop);
            }
          },
          onMuteToggle: () {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) {
              _store.toggleClipMute(clip);
            }
          },
          onTransposeChanged: (int semitones) {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) {
              _store.setClipTranspose(clip.id, semitones);
            }
          },
          onMakeUnique: () {
            _store.makeClipsUnique(_store.selectedClipIds.toList());
          },
          onSplitByChannel: () {
            final ArrangementClip? clip = _store.selectedClip;
            if (clip != null) _store.splitClipByChannel(clip.id);
          },
          onLaneMute: (String laneId) {
            final ArrangementLane? lane = _store.lanes.cast<ArrangementLane?>().firstWhere(
              (ArrangementLane? value) => value?.id == laneId,
              orElse: () => null,
            );
            if (lane != null) _store.toggleLaneMute(lane);
          },
          onLaneSolo: (String laneId) {
            final ArrangementLane? lane = _store.lanes.cast<ArrangementLane?>().firstWhere(
              (ArrangementLane? value) => value?.id == laneId,
              orElse: () => null,
            );
            if (lane != null) _store.toggleLaneSolo(lane);
          },
          onLaneCollapse: (String laneId) {
            final ArrangementLane? lane = _store.lanes.cast<ArrangementLane?>().firstWhere(
              (ArrangementLane? value) => value?.id == laneId,
              orElse: () => null,
            );
            if (lane != null) _store.toggleLaneCollapsed(lane);
          },
        ),
      ),
    );
  }
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _DuplicateIntent extends Intent {
  const _DuplicateIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}
