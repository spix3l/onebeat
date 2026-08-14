// PlaylistBinding — wires playlist presentation to the engine and store (UI-D-04).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../core/shortcuts.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
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
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;
  final PlaylistStore? store;
  final void Function(String patternId, String clipId)? onOpenPattern;

  @override
  State<PlaylistBinding> createState() => _PlaylistBindingState();
}

class _PlaylistBindingState extends State<PlaylistBinding>
    with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final PlaylistStore _store;
  final FocusNode _focus = FocusNode(debugLabel: 'playlist-binding');
  bool _ownsController = false;
  bool _ownsStore = false;

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
          return ClipVm(
            id: clip.id.hashCode,
            name: clip.name.isNotEmpty ? clip.name : 'Clip ${i + 1}',
            duration: _formatDuration(clip.lengthTicks),
            color: _resolveColor(laneIndex, clip.color),
            startBar: clip.startTicks / ticksPerBar,
            lengthBars: clip.lengthTicks / ticksPerBar,
            lane: laneIndex,
            selected: _store.selectedClipIds.contains(clip.id),
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
          usageText: clip.isShared
              ? 'Pattern used in ${clip.usageCount} clips'
              : 'Pattern used once',
          isShared: clip.isShared,
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

  void _onBackgroundTap(double bar, int lane) {
    FocusPolicy.takeUnlessTyping(_focus);
    if (_store.selectedClipIds.isNotEmpty &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _store.clearClipSelection();
      return;
    }

    if (_store.lanes.isEmpty) {
      _store.addLane('Track 1');
    }

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
          onClipTap: _onClipTap,
          onBackgroundTap: _onBackgroundTap,
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
