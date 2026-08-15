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
import 'playlist_store.dart';

class PlaylistBinding extends StatefulWidget {
  const PlaylistBinding({
    required this.client,
    this.controller,
    this.store,
    this.onOpenPattern,
    this.externalAudioDrop,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;
  final PlaylistStore? store;
  final void Function(String patternId, String clipId)? onOpenPattern;
  final AudioFileDrop? externalAudioDrop;

  @override
  State<PlaylistBinding> createState() => _PlaylistBindingState();
}

class _PlaylistBindingState extends State<PlaylistBinding>
    with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final PlaylistStore _store;
  final FocusNode _focus = FocusNode(debugLabel: 'playlist-binding');
  final GlobalKey _canvasKey = GlobalKey();
  bool _ownsController = false;
  bool _ownsStore = false;
  String _draggingClipId = '';
  int _dragStartLane = 0;
  Offset _dragPixels = Offset.zero;
  final Map<String, List<double>> _waveforms = <String, List<double>>{};
  final Set<String> _waveformLoads = <String>{};

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
      _store = PlaylistStore(widget.client)..refresh();
      _ownsStore = true;
    }

    _controller.addListener(_onEngineChanged);
    _store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeExternalAudioDrop(widget.externalAudioDrop);
    });
  }

  @override
  void didUpdateWidget(covariant PlaylistBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _requestWaveform(String path) {
    if (path.isEmpty ||
        _waveforms.containsKey(path) ||
        !_waveformLoads.add(path)) {
      return;
    }
    loadAudioWaveform(path).then((List<double> waveform) {
      _waveformLoads.remove(path);
      if (!mounted) return;
      setState(() => _waveforms[path] = waveform);
    });
  }

  Color _resolveColor(int index, String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty) {
      final int parsed =
          int.tryParse(colorStr.replaceFirst('#', ''), radix: 16) ?? 0;
      if (parsed != 0) {
        return Color(0xFF000000 | parsed);
      }
    }
    return channelColors[index % channelColors.length];
  }

  String _formatDuration(int lengthTicks) {
    final double beats = lengthTicks / ticksPerQuarter;
    final int seconds = (beats * (60.0 / 120.0)).round();
    final int minutes = seconds ~/ 60;
    final int remainingSec = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSec.toString().padLeft(2, '0')}';
  }

  PlaylistScreenVm _buildVm(OneBeatTokens tokens) {
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
          );
        })(),
    ];

    int? playhead16ths;
    final EngineSnapshot snapshot = _controller.snapshot;
    if (snapshot.playing) {
      playhead16ths = (snapshot.positionBeats * 4).round();
    }

    final double pxPerBar = tokens.size.playlistPxPerBar * _store.horizontalZoom;

    final PlaylistVm canvasVm = PlaylistVm(
      clips: clipVms,
      pxPerBar: pxPerBar,
      laneCountOverride: _store.lanes.length,
      playheadBar16ths: playhead16ths,
      headerTitle: 'Playlist',
      headerRight:
          'Untitled.onebeat · ${snapshot.tempoBpm.toStringAsFixed(0)} BPM · 4/4',
    );

    ClipInspectorVm inspectorVm = const ClipInspectorVm(selectedCount: 0);
    if (_store.selectedClipIds.length > 1) {
      inspectorVm = ClipInspectorVm(
        selectedCount: _store.selectedClipIds.length,
      );
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
              : (clip.isShared
                  ? 'Pattern used in ${clip.usageCount} clips'
                  : 'Pattern used once'),
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

    return PlaylistScreenVm(
      canvas: canvasVm,
      inspector: inspectorVm,
    );
  }

  void _onClipTap(int hashId) {
    FocusPolicy.takeUnlessTyping(_focus);
    for (final ArrangementClip clip in _store.clips) {
      if (clip.id.hashCode == hashId) {
        if (HardwareKeyboard.instance.isShiftPressed) {
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
    final RenderBox? box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset local = box.globalToLocal(Offset(drop.x, drop.y));
    final double bar = local.dx /
        (OneBeatTokens.dark().size.playlistPxPerBar * _store.horizontalZoom);
    final int lane =
        (local.dy / OneBeatTokens.dark().size.playlistLaneHeight).floor();
    _ensureLane(lane);
    for (final String path in drop.paths) {
      final String extension = path.split('.').last.toLowerCase();
      if (!SamplePackScanner.supportedExtensions.contains(extension)) continue;
      _onSampleDrop(
        SampleAsset(id: 'sample:$path', name: path.split('/').last, path: path),
        bar,
        lane,
      );
    }
  }

  void _onClipPanStart(int hashId, DragStartDetails details) {
    final ArrangementClip? clip = _store.clips.cast<ArrangementClip?>().firstWhere(
          (ArrangementClip? item) => item?.id.hashCode == hashId,
          orElse: () => null,
        );
    if (clip == null) return;
    FocusPolicy.takeUnlessTyping(_focus);
    if (!_store.selectedClipIds.contains(clip.id)) {
      _store.selectClip(clip.id);
    }
    _draggingClipId = clip.id;
    _dragStartLane = _store.lanes.indexWhere(
      (ArrangementLane lane) => lane.id == clip.laneId,
    ).clamp(0, _store.lanes.length - 1);
    _dragPixels = Offset.zero;
    _store.beginClipDrag(ClipDragKind.move);
  }

  void _onClipPanUpdate(int hashId, DragUpdateDetails details) {
    if (_draggingClipId.isEmpty) return;
    _dragPixels += details.delta;
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final double pxPerBar = tokens.size.playlistPxPerBar * _store.horizontalZoom;
    final int deltaTicks = _store.snapDelta(
      (_dragPixels.dx / pxPerBar * ticksPerBar).round(),
    );
    if (_store.lanes.isEmpty) return;
    final int laneIndex = (_dragStartLane +
            (_dragPixels.dy / tokens.size.playlistLaneHeight).round())
        .clamp(0, _store.lanes.length - 1);
    _store.updateClipMove(deltaTicks, laneId: _store.lanes[laneIndex].id);
  }

  void _onClipPanEnd(int hashId, DragEndDetails details) {
    if (_draggingClipId.isEmpty) return;
    _store.endClipDrag();
    _draggingClipId = '';
    _dragStartLane = 0;
    _dragPixels = Offset.zero;
  }

  void _onClipPanCancel(int hashId) {
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
              clip?.isAudio == true &&
              clip?.laneId == targetLane.id &&
              clip?.startTicks == startTicks,
          orElse: () => null,
        );
    if (added != null) _store.selectClip(added.id);
  }

  void _onBackgroundTap(double bar, int lane) {
    FocusPolicy.takeUnlessTyping(_focus);
    if (_store.selectedClipIds.isNotEmpty &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _store.clearClipSelection();
      return;
    }

    _ensureLane(lane);
    if (_store.lanes.isEmpty) return;

    final int targetLaneIndex = lane.clamp(0, _store.lanes.length - 1);
    final ArrangementLane targetLane = _store.lanes[targetLaneIndex];
    final int startTicks = (bar * ticksPerBar).round();
    _store.placeCurrentPattern(targetLane.id, startTicks);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PlaylistScreenVm vm = _buildVm(tokens);

    return ScopedShortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
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
          onClipPanStart: _onClipPanStart,
          onClipPanUpdate: _onClipPanUpdate,
          onClipPanEnd: _onClipPanEnd,
          onClipPanCancel: _onClipPanCancel,
          onBackgroundTap: _onBackgroundTap,
          onDrop: _onSampleDrop,
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
