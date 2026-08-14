// PianoRollBinding — wires the piano roll presentation to the core engine (UI-D-03).
//
// Owns the mapping from the engine snapshot and PianoRollStore to PianoRollScreenVm.
// Listens to the EngineController for real-time playhead updates,
// and routes gestures and user interactions to PianoRollStore commands.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../core/shortcuts.dart';
import '../../design/tokens.dart';
import '../../engine/engine_client.dart';
import 'note_grid.dart';
import 'piano_roll_screen.dart';
import 'piano_roll_screen_vm.dart';
import 'piano_roll_store.dart';
import 'pr_toolbar.dart';

class PianoRollBinding extends StatefulWidget {
  const PianoRollBinding({
    required this.client,
    this.controller,
    this.store,
    this.onBackToPlaylist,
    super.key,
  });

  final EngineClient client;
  final core.EngineController? controller;
  final PianoRollStore? store;
  final VoidCallback? onBackToPlaylist;

  @override
  State<PianoRollBinding> createState() => _PianoRollBindingState();
}

class _PianoRollBindingState extends State<PianoRollBinding>
    with SingleTickerProviderStateMixin {
  late final core.EngineController _controller;
  late final PianoRollStore _store;
  final FocusNode _focus = FocusNode(debugLabel: 'piano-roll-binding');
  bool _ownsController = false;
  bool _ownsStore = false;

  String _selectedVelocityLane = 'VEL';
  int _dragOriginTick = 0;
  int _dragOriginKey = 0;

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
      _store = PianoRollStore(widget.client)..refresh();
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
    if (mounted) {
      setState(() {});
    }
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Color _resolveInstrumentColor(int index, String? colorStr) {
    if (colorStr != null && colorStr.isNotEmpty) {
      final int parsed =
          int.tryParse(colorStr.replaceFirst('#', ''), radix: 16) ?? 0;
      if (parsed != 0) {
        return Color(0xFF000000 | parsed);
      }
    }
    return channelColors[index % channelColors.length];
  }

  bool get _snapOff =>
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isControlPressed;

  int _maybeSnap(int tick) => _snapOff ? tick : _store.snapDown(tick);

  PrViewport _buildViewport(OneBeatTokens tokens) {
    final double rowHeight =
        tokens.size.pianoRowHeight * _store.verticalZoom;
    final double ticksPerPx = 1.0 / _store.pixelsPerTick;
    return PrViewport(
      ticksPerPx: ticksPerPx,
      rowHeight: rowHeight,
      firstVisibleTick: _store.scrollTicks.round(),
      topMidiNote: _store.topKey,
    );
  }

  PianoRollScreenVm _buildVm(OneBeatTokens tokens) {
    final bool hasInstrument = _store.instrumentId.isNotEmpty;
    final PrViewport viewport = _buildViewport(tokens);

    // Toolbar VM
    final PatternSummary? currentPattern = _store.patterns
        .cast<PatternSummary?>()
        .firstWhere(
          (PatternSummary? p) => p?.id == _store.patternId,
          orElse: () => _store.patterns.isNotEmpty ? _store.patterns.first : null,
        );
    final String patternName = currentPattern?.name ?? 'Pattern';

    final ProjectInstrument? currentInst = _store.instruments
        .cast<ProjectInstrument?>()
        .firstWhere(
          (ProjectInstrument? inst) => inst?.id == _store.instrumentId,
          orElse: () =>
              _store.instruments.isNotEmpty ? _store.instruments.first : null,
        );
    final String instName = currentInst?.name ?? _store.instrumentId;

    final int instIndex = _store.instruments.indexWhere(
      (ProjectInstrument inst) => inst.id == _store.instrumentId,
    );
    final Color channelColor = _resolveInstrumentColor(
      instIndex >= 0 ? instIndex : 0,
      currentInst?.color,
    );

    final List<String> patternNames = _store.patterns.isNotEmpty
        ? _store.patterns.map((PatternSummary p) => p.name).toList()
        : <String>[patternName];

    final PrToolbarVm toolbarVm = PrToolbarVm(
      crumbs: <String>['Piano roll', patternName, instName],
      pattern: patternName,
      patterns: patternNames,
      scale: _store.scale.name,
      scales: MusicalScale.all.map((MusicalScale s) => s.name).toList(),
      snap: _store.grid.label,
      snaps: GridChoice.all.map((GridChoice g) => g.label).toList(),
      tool: _store.tool,
      backLabel: 'Back to playlist',
    );

    // Notes VM mapping
    final List<PrNoteVm> noteVms = <PrNoteVm>[
      for (final SequenceNote note in _store.notes)
        PrNoteVm(
          id: Object.hash(note.startTicks, note.key),
          startTick: note.startTicks,
          lengthTicks: note.lengthTicks,
          midiNote: note.key,
          velocity: (note.velocity / 16383.0).clamp(0.0, 1.0),
        ),
    ];

    final List<PrNoteVm> ghostVms = <PrNoteVm>[
      for (final SequenceNote ghost in _store.ghostNotes)
        PrNoteVm(
          id: Object.hash(ghost.startTicks, ghost.key),
          startTick: ghost.startTicks,
          lengthTicks: ghost.lengthTicks,
          midiNote: ghost.key,
          velocity: (ghost.velocity / 16383.0).clamp(0.0, 1.0),
        ),
    ];

    final Set<int> selectedIds = <int>{
      for (final SequenceNote sel in _store.selection)
        Object.hash(sel.startTicks, sel.key),
    };

    // Playhead calculation
    int? playheadTick;
    final EngineSnapshot snapshot = _controller.snapshot;
    if (snapshot.playing) {
      final int patternLength = currentPattern?.lengthTicks ?? ticksPerBar;
      final double rawTick = snapshot.positionBeats * ticksPerQuarter;
      playheadTick = patternLength > 0
          ? (rawTick % patternLength).round()
          : rawTick.round();
    }

    // Marquee rect in canvas space
    Rect? marqueeRect;
    final MarqueeSelection? marquee = _store.marquee;
    if (marquee != null) {
      marqueeRect = Rect.fromLTRB(
        viewport.xOf(marquee.lowTick),
        viewport.yOf(marquee.highKey),
        viewport.xOf(marquee.highTick),
        viewport.yOf(marquee.lowKey - 1),
      );
    }

    final PianoRollVm rollVm = PianoRollVm(
      notes: noteVms,
      ghostNotes: ghostVms,
      viewport: viewport,
      playheadTick: playheadTick,
      selected: selectedIds,
      marqueeRect: marqueeRect,
    );

    return PianoRollScreenVm(
      toolbar: toolbarVm,
      roll: rollVm,
      channelColor: channelColor,
      velocityLane: _selectedVelocityLane,
      hasInstrument: hasInstrument,
      canUndo: _store.canUndo,
      canRedo: _store.canRedo,
    );
  }

  // ----- Gestures -----------------------------------------------------------

  void _onTapDown(TapDownDetails details, PrViewport view) {
    FocusPolicy.takeUnlessTyping(_focus);
    final int tick = view.tickAt(details.localPosition.dx);
    final int key = view.noteAt(details.localPosition.dy);
    final SequenceNote? hit = _store.noteAt(tick, key);

    if (hit != null) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _store.toggleSelection(hit);
      } else if (_store.tool == PrTool.eraser) {
        _store.deleteNote(hit);
      } else {
        _store.selectOnly(hit);
        _store.audition(key);
      }
      return;
    }

    if (_store.tool == PrTool.pencil) {
      _store.addNoteAt(_maybeSnap(tick), key);
      _store.audition(key);
    } else {
      _store.clearSelection();
    }
  }

  void _onSecondaryTapDown(TapDownDetails details, PrViewport view) {
    final int tick = view.tickAt(details.localPosition.dx);
    final int key = view.noteAt(details.localPosition.dy);
    final SequenceNote? hit = _store.noteAt(tick, key);
    if (hit != null) {
      _store.deleteNote(hit);
    }
  }

  void _onPanStart(DragStartDetails details, PrViewport view) {
    FocusPolicy.takeUnlessTyping(_focus);
    final int tick = view.tickAt(details.localPosition.dx);
    final int key = view.noteAt(details.localPosition.dy);
    _dragOriginTick = tick;
    _dragOriginKey = key;

    final SequenceNote? hit = _store.noteAt(tick, key);
    if (hit == null) {
      if (_store.tool == PrTool.pencil) {
        _store.addNoteAt(_maybeSnap(tick), key);
        _store.beginResize();
      } else {
        _store.beginMarquee(tick, key);
      }
      return;
    }

    if (_store.tool == PrTool.eraser) {
      _store.deleteNote(hit);
      return;
    }

    if (!_store.selection.contains(hit)) {
      _store.selectOnly(hit);
    }

    final double noteEndX = view.xOf(hit.startTicks + hit.lengthTicks);
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    if ((noteEndX - details.localPosition.dx).abs() <=
        tokens.size.pianoResizeHandleWidth) {
      _store.beginResize();
    } else {
      _store.beginMove();
    }
  }

  void _onPanUpdate(DragUpdateDetails details, PrViewport view) {
    final int tick = view.tickAt(details.localPosition.dx);
    final int key = view.noteAt(details.localPosition.dy);

    switch (_store.dragKind) {
      case PianoDragKind.move:
        int deltaTicks = tick - _dragOriginTick;
        if (!_snapOff && _store.snapTicks > 0) {
          deltaTicks =
              (deltaTicks / _store.snapTicks).round() * _store.snapTicks;
        }
        _store.updateMove(deltaTicks, key - _dragOriginKey);
      case PianoDragKind.resize:
        int delta = tick - _dragOriginTick;
        if (!_snapOff && _store.snapTicks > 0) {
          delta = (delta / _store.snapTicks).round() * _store.snapTicks;
        }
        _store.updateResize(delta);
      case PianoDragKind.marquee:
        _store.updateMarquee(tick, key);
      case PianoDragKind.none:
      case PianoDragKind.draw:
      case PianoDragKind.velocity:
        break;
    }
  }

  void _onPointerSignal(PointerSignalEvent event, PrViewport view) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isMetaPressed) {
      _store.zoomHorizontally(event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
      return;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _store.panTo(
        _store.scrollTicks + event.scrollDelta.dy * view.ticksPerPx,
        _store.topKey,
      );
      return;
    }
    _store.panTo(
      _store.scrollTicks + event.scrollDelta.dx * view.ticksPerPx,
      _store.topKey - (event.scrollDelta.dy / view.rowHeight).round(),
    );
  }

  void _onVelocityTapDown(TapDownDetails details, double height) {
    final double fraction = (1.0 - (details.localPosition.dy / height)).clamp(0.0, 1.0);
    final int velocity = (fraction * 16383).round().clamp(1, 16383);
    if (_store.hasSelection) {
      _store.setSelectionVelocity(velocity);
    }
  }

  void _onVelocityDragUpdate(DragUpdateDetails details, double height) {
    final double fraction = (1.0 - (details.localPosition.dy / height)).clamp(0.0, 1.0);
    final int velocity = (fraction * 16383).round().clamp(1, 16383);
    if (_store.hasSelection) {
      _store.setSelectionVelocity(velocity);
    }
  }

  // ----- Toolbar Handlers ---------------------------------------------------

  void _onSelectPatternByName(String name) {
    for (final PatternSummary p in _store.patterns) {
      if (p.name == name) {
        _store.selectPattern(p.id);
        return;
      }
    }
  }

  void _onSelectScaleByName(String name) {
    for (final MusicalScale s in MusicalScale.all) {
      if (s.name == name) {
        _store.setScale(s, _store.scaleRoot);
        return;
      }
    }
  }

  void _onSelectSnapByLabel(String label) {
    for (final GridChoice g in GridChoice.all) {
      if (g.label == label) {
        _store.setGrid(g);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PianoRollScreenVm vm = _buildVm(tokens);
    final PrViewport view = vm.roll.viewport;

    return ScopedShortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _NudgeKeyIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _NudgeKeyIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            const _NudgeKeyIntent(12),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            const _NudgeKeyIntent(-12),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _NudgeTimeIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _NudgeTimeIntent(1),
        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const CancelIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const _SelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            const _DuplicateIntent(),
        const SingleActivator(LogicalKeyboardKey.keyQ): const _QuantiseIntent(),
      },
      handlers: const <String, VoidCallback>{},
      extraActions: <Type, Action<Intent>>{
        CancelIntent: CallbackAction<CancelIntent>(
          onInvoke: (_) {
            if (_store.dragKind != PianoDragKind.none) {
              _store.cancelDrag();
            } else {
              _store.clearSelection();
            }
            return null;
          },
        ),
        _NudgeKeyIntent: CallbackAction<_NudgeKeyIntent>(
          onInvoke: (_NudgeKeyIntent intent) {
            _store.transposeSelection(intent.semitones);
            return null;
          },
        ),
        _NudgeTimeIntent: CallbackAction<_NudgeTimeIntent>(
          onInvoke: (_NudgeTimeIntent intent) {
            final int step = _store.snapTicks > 0
                ? _store.snapTicks
                : ticksPerQuarter ~/ 4;
            _store.nudgeSelection(step * intent.direction);
            return null;
          },
        ),
        _DeleteIntent: CallbackAction<_DeleteIntent>(
          onInvoke: (_) {
            _store.deleteSelection();
            return null;
          },
        ),
        _SelectAllIntent: CallbackAction<_SelectAllIntent>(
          onInvoke: (_) {
            _store.selectAll();
            return null;
          },
        ),
        _DuplicateIntent: CallbackAction<_DuplicateIntent>(
          onInvoke: (_) {
            _store.duplicateSelection();
            return null;
          },
        ),
        _QuantiseIntent: CallbackAction<_QuantiseIntent>(
          onInvoke: (_) {
            _store.quantiseSelection();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focus,
        child: PianoRollScreen(
          vm: vm,
          onPattern: _onSelectPatternByName,
          onTool: (PrTool tool) => _store.setTool(tool),
          onScale: _onSelectScaleByName,
          onSnap: _onSelectSnapByLabel,
          onZoomIn: () => _store.zoomHorizontally(1.25),
          onZoomOut: () => _store.zoomHorizontally(0.8),
          onBack: widget.onBackToPlaylist,
          onKeyPress: (int key) => _store.audition(key),
          onTapDown: (TapDownDetails d) => _onTapDown(d, view),
          onSecondaryTapDown: (TapDownDetails d) => _onSecondaryTapDown(d, view),
          onPanStart: (DragStartDetails d) => _onPanStart(d, view),
          onPanUpdate: (DragUpdateDetails d) => _onPanUpdate(d, view),
          onPanEnd: (_) => _store.endDrag(),
          onPanCancel: _store.cancelDrag,
          onPointerSignal: (PointerSignalEvent e) => _onPointerSignal(e, view),
          onLaneChanged: (String lane) =>
              setState(() => _selectedVelocityLane = lane),
          onVelocityTapDown: _onVelocityTapDown,
          onVelocityDragUpdate: _onVelocityDragUpdate,
        ),
      ),
    );
  }
}

class _NudgeKeyIntent extends Intent {
  const _NudgeKeyIntent(this.semitones);
  final int semitones;
}

class _NudgeTimeIntent extends Intent {
  const _NudgeTimeIntent(this.direction);
  final int direction;
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _DuplicateIntent extends Intent {
  const _DuplicateIntent();
}

class _QuantiseIntent extends Intent {
  const _QuantiseIntent();
}
