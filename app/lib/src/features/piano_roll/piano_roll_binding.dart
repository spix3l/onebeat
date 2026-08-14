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
import 'velocity_lane.dart';

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

  /// The measured canvas. Paging, anchored zoom and the "how far can I scroll
  /// down" floor all need it, and none of them can be answered from the vm.
  Size _gridSize = Size.zero;

  /// The row height the last build resolved, kept so the gesture and keyboard
  /// handlers can reason in rows without reaching for the theme.
  double _rowHeight = 14;

  int get _visibleRows {
    if (_rowHeight <= 0 || _gridSize.height <= 0) return 0;
    return (_gridSize.height / _rowHeight).floor();
  }

  /// The tick at the centre of the canvas — the anchor a zoom button or a
  /// keyboard zoom holds still, since neither has a pointer to zoom about.
  double get _centreTick =>
      _store.scrollTicks + (_gridSize.width / 2) / _store.pixelsPerTick;

  /// How much music is on screen, in ticks. One horizontal page.
  double get _visibleTicks => _gridSize.width / _store.pixelsPerTick;

  void _pan({double deltaTicks = 0, int deltaKeys = 0}) => _store.panBy(
    deltaTicks: deltaTicks,
    deltaKeys: deltaKeys,
    visibleRows: _visibleRows,
  );

  void _onGridSize(Size size) {
    if (size == _gridSize) return;
    // No setState: this is measurement feeding the *next* gesture, not the
    // current frame, and rebuilding here would loop through LayoutBuilder.
    _gridSize = size;
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
    // Unconditionally: this binding is what starts previews, so it is what owes
    // the note-off, and a store handed in from outside is exactly the case
    // where nothing else would send it.
    _store.stopAudition();
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
    _rowHeight = rowHeight;
    final double ticksPerPx = 1.0 / _store.pixelsPerTick;
    return PrViewport(
      ticksPerPx: ticksPerPx,
      rowHeight: rowHeight,
      firstVisibleTick: _store.scrollTicks.round(),
      topMidiNote: _store.topKey,
      // The canvas draws the grid the edits will land on, so changing Snap
      // changes what you see and not only what happens next.
      subdivisionTicks: _store.snapTicks,
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

    // What is sounding right now, derived rather than reported: a note is
    // audible exactly while the playhead is inside it, and asking the engine
    // for a second copy of that fact would let the two disagree.
    final Set<int> activeKeys = <int>{};
    if (playheadTick != null) {
      for (final SequenceNote note in _store.notes) {
        if (playheadTick >= note.startTicks && playheadTick < note.endTicks) {
          activeKeys.add(note.key);
        }
      }
    }

    final PianoRollVm rollVm = PianoRollVm(
      notes: noteVms,
      ghostNotes: ghostVms,
      viewport: viewport,
      playheadTick: playheadTick,
      selected: selectedIds,
      marqueeRect: marqueeRect,
      activeKeys: activeKeys,
      scaleIntervals: _store.scale.intervals,
      scaleRoot: _store.scaleRoot,
    );

    return PianoRollScreenVm(
      toolbar: toolbarVm,
      roll: rollVm,
      channelColor: channelColor,
      velocityLane: _selectedVelocityLane,
      contentEndTicks: _store.contentEndTicks,
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

    // ⌘-drag is a lasso whatever tool is up. Switching to the select tool to
    // rubber-band a few notes and switching back is the kind of round trip a
    // modifier exists to remove.
    if (HardwareKeyboard.instance.isMetaPressed) {
      _store.beginMarquee(tick, key);
      return;
    }

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

  void _onPointerSignal(
    PointerSignalEvent event,
    PrViewport view,
    double gutter,
  ) {
    if (event is! PointerScrollEvent) return;
    final HardwareKeyboard keys = HardwareKeyboard.instance;

    if (keys.isMetaPressed) {
      // Zoom about the pointer. The Listener spans the key column too, so the
      // canvas x is the local x less that gutter.
      final double canvasX = event.localPosition.dx - gutter;
      final double anchor = _store.scrollTicks + canvasX / _store.pixelsPerTick;
      final double factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
      // ⌘⇧ zooms the pitch axis. Two axes, one modifier pair, and the shift
      // means the same thing it means for scrolling: "the other axis".
      if (keys.isShiftPressed) {
        _store.zoomVertically(
          factor,
          anchorKey: view.noteAt(event.localPosition.dy),
          visibleRows: _visibleRows,
        );
      } else {
        _store.zoomHorizontally(factor, anchorTick: anchor);
      }
      return;
    }

    if (keys.isShiftPressed) {
      _store.panBy(
        deltaTicks: event.scrollDelta.dy * view.ticksPerPx,
        visibleRows: _visibleRows,
      );
      return;
    }

    _store.panBy(
      deltaTicks: event.scrollDelta.dx * view.ticksPerPx,
      deltaKeys: -(event.scrollDelta.dy / view.rowHeight).round(),
      visibleRows: _visibleRows,
    );
  }

  /// Applies a lane gesture at [local] to the stem under the pointer.
  ///
  /// Two rules, both of them FL's: you edit the note you are pointing at, and
  /// if that note is part of a selection you edit the whole selection. The lane
  /// used to do only the second, so grabbing one stem while several notes were
  /// selected flattened all of them — with the pointer on the one stem that
  /// looked like it was behaving.
  void _applyVelocity(Offset local, double height, PrViewport view, double gutter) {
    if (PrLaneKind.fromLabel(_selectedVelocityLane) != PrLaneKind.velocity) {
      return;
    }
    final double fraction = (1.0 - (local.dy / height)).clamp(0.0, 1.0);
    final int velocity = (fraction * 16383).round().clamp(1, 16383);

    final int tick = view.tickAt(local.dx - gutter);
    // A stem is a few pixels wide; the grab radius is expressed in ticks so it
    // stays the same *distance* at every zoom.
    final double stemWidth =
        OneBeatTheme.of(context).size.prVelocityStemWidth;
    final int tolerance = (stemWidth * 2 * view.ticksPerPx).round();
    final SequenceNote? hit = _store.noteNearTick(tick, tolerance);
    if (hit == null) return;

    if (_store.selection.contains(hit) && _store.selection.length > 1) {
      _store.setSelectionVelocity(velocity);
    } else {
      _store.setNoteVelocity(hit, velocity);
    }
  }

  void _onVelocityTapDown(
    TapDownDetails details,
    double height,
    PrViewport view,
    double gutter,
  ) => _applyVelocity(details.localPosition, height, view, gutter);

  void _onVelocityDragUpdate(
    DragUpdateDetails details,
    double height,
    PrViewport view,
    double gutter,
  ) => _applyVelocity(details.localPosition, height, view, gutter);

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
    // The key column the canvas sits to the right of. Pointer events arriving
    // from the ruler/canvas Listener and from the velocity lane are local to a
    // box that includes it, so every x has to cross the same gutter.
    final double gutter = tokens.size.prKeyColumnWidth;

    return ScopedShortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Arrows edit the selection, and pan when there is nothing selected —
        // one key that always does the obvious thing with what is in front of
        // you, rather than a modifier you have to remember on an empty canvas.
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

        // Explicit panning, which works whatever is selected.
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
            const _PanIntent(deltaKeys: 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
            const _PanIntent(deltaKeys: -1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const _PanIntent(deltaBeats: -1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            const _PanIntent(deltaBeats: 1),
        const SingleActivator(LogicalKeyboardKey.pageUp):
            const _PanIntent(pages: 1),
        const SingleActivator(LogicalKeyboardKey.pageDown):
            const _PanIntent(pages: -1),
        const SingleActivator(LogicalKeyboardKey.pageUp, shift: true):
            const _PanIntent(horizontalPages: -1),
        const SingleActivator(LogicalKeyboardKey.pageDown, shift: true):
            const _PanIntent(horizontalPages: 1),
        const SingleActivator(LogicalKeyboardKey.home): const _HomeIntent(),

        // Zoom. Both the main-row and the numpad keys, because a laptop and a
        // full keyboard disagree about which one `+` is.
        const SingleActivator(LogicalKeyboardKey.equal, meta: true):
            const _ZoomIntent(1.25),
        const SingleActivator(LogicalKeyboardKey.add, meta: true):
            const _ZoomIntent(1.25),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true):
            const _ZoomIntent(0.8),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, meta: true):
            const _ZoomIntent(0.8),
        const SingleActivator(LogicalKeyboardKey.equal, meta: true, shift: true):
            const _ZoomIntent(1.25, vertical: true),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true, shift: true):
            const _ZoomIntent(0.8, vertical: true),

        // Tools, matching the letters in their tooltips.
        const SingleActivator(LogicalKeyboardKey.keyP):
            const _ToolIntent(PrTool.pencil),
        const SingleActivator(LogicalKeyboardKey.keyE):
            const _ToolIntent(PrTool.select),
        const SingleActivator(LogicalKeyboardKey.keyD):
            const _ToolIntent(PrTool.eraser),

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
            // Escape cancels an in-flight drag first, then closes the roll.
            if (_store.dragKind != PianoDragKind.none) {
              _store.cancelDrag();
            } else {
              widget.onBackToPlaylist?.call();
            }
            return null;
          },
        ),
        _NudgeKeyIntent: CallbackAction<_NudgeKeyIntent>(
          onInvoke: (_NudgeKeyIntent intent) {
            if (!_store.hasSelection) {
              _pan(deltaKeys: intent.semitones);
              return null;
            }
            _store.transposeSelection(intent.semitones);
            return null;
          },
        ),
        _NudgeTimeIntent: CallbackAction<_NudgeTimeIntent>(
          onInvoke: (_NudgeTimeIntent intent) {
            final int step = _store.snapTicks > 0
                ? _store.snapTicks
                : ticksPerQuarter ~/ 4;
            if (!_store.hasSelection) {
              _pan(deltaTicks: (step * intent.direction).toDouble());
              return null;
            }
            _store.nudgeSelection(step * intent.direction);
            return null;
          },
        ),
        _PanIntent: CallbackAction<_PanIntent>(
          onInvoke: (_PanIntent intent) {
            final int rows = _visibleRows;
            _pan(
              deltaTicks:
                  intent.deltaBeats * ticksPerQuarter.toDouble() +
                  intent.horizontalPages * _visibleTicks,
              // A vertical page is one row short of the viewport, so the row
              // you were reading is still on screen after the jump.
              deltaKeys:
                  intent.deltaKeys +
                  intent.pages * (rows > 1 ? rows - 1 : 1),
            );
            return null;
          },
        ),
        _HomeIntent: CallbackAction<_HomeIntent>(
          onInvoke: (_) {
            _store.panTo(0, _store.topKey);
            return null;
          },
        ),
        _ZoomIntent: CallbackAction<_ZoomIntent>(
          onInvoke: (_ZoomIntent intent) {
            if (intent.vertical) {
              _store.zoomVertically(
                intent.factor,
                anchorKey: _store.topKey - _visibleRows ~/ 2,
                visibleRows: _visibleRows,
              );
            } else {
              _store.zoomHorizontally(intent.factor, anchorTick: _centreTick);
            }
            return null;
          },
        ),
        _ToolIntent: CallbackAction<_ToolIntent>(
          onInvoke: (_ToolIntent intent) {
            _store.setTool(intent.tool);
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
          onZoomIn: () =>
              _store.zoomHorizontally(1.25, anchorTick: _centreTick),
          onZoomOut: () =>
              _store.zoomHorizontally(0.8, anchorTick: _centreTick),
          onBack: widget.onBackToPlaylist,
          onKeyPress: (int key) => _store.audition(key),
          onTapDown: (TapDownDetails d) => _onTapDown(d, view),
          onSecondaryTapDown: (TapDownDetails d) => _onSecondaryTapDown(d, view),
          onPanStart: (DragStartDetails d) => _onPanStart(d, view),
          onPanUpdate: (DragUpdateDetails d) => _onPanUpdate(d, view),
          onPanEnd: (_) => _store.endDrag(),
          onPanCancel: _store.cancelDrag,
          onPointerSignal: (PointerSignalEvent e) =>
              _onPointerSignal(e, view, gutter),
          onScrollTicks: (double ticks) => _store.panTo(ticks, _store.topKey),
          onScrollTopKey: (int key) => _store.panTo(_store.scrollTicks, key),
          onGridSize: _onGridSize,
          onLaneChanged: (String lane) =>
              setState(() => _selectedVelocityLane = lane),
          onVelocityTapDown: (TapDownDetails d, double h) =>
              _onVelocityTapDown(d, h, view, gutter),
          onVelocityDragStart: _store.beginVelocityGesture,
          onVelocityDragUpdate: (DragUpdateDetails d, double h) =>
              _onVelocityDragUpdate(d, h, view, gutter),
          onVelocityDragEnd: _store.endDrag,
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

/// A viewport move. One intent for every flavour of pan so the shortcut table
/// reads as a table rather than as five near-identical intent classes.
class _PanIntent extends Intent {
  const _PanIntent({
    this.deltaBeats = 0,
    this.deltaKeys = 0,
    this.pages = 0,
    this.horizontalPages = 0,
  });

  final int deltaBeats;
  final int deltaKeys;

  /// Vertical pages, positive being up the keyboard.
  final int pages;
  final int horizontalPages;
}

class _HomeIntent extends Intent {
  const _HomeIntent();
}

class _ZoomIntent extends Intent {
  const _ZoomIntent(this.factor, {this.vertical = false});
  final double factor;
  final bool vertical;
}

class _ToolIntent extends Intent {
  const _ToolIntent(this.tool);
  final PrTool tool;
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
