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

  /// The end tick of the note a resize grabbed. The drag is measured against
  /// this rather than against the pointer's start, so the edge tracks the
  /// cursor instead of trailing it.
  int _resizeOriginEnd = 0;

  /// What the pointer is currently over, expressed as a cursor.
  MouseCursor _gridCursor = MouseCursor.defer;

  /// The tick under the pointer, or null when the pointer is off the canvas.
  /// A paste reads it; see [_pasteTick].
  int? _hoverTick;

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
    // Shown from the view switcher, so it owns the keyboard immediately rather
    // than only after the first click on the canvas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusPolicy.take(_focus);
    });
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

  /// Whether the snap is suspended for the gesture in flight.
  ///
  /// Control only. ⌥ used to do this too, but ⌥ is the lasso modifier — see
  /// [_isLasso] — and a key cannot both start a marquee and mean "ignore the
  /// grid" for the drag it just prevented.
  bool get _snapOff => HardwareKeyboard.instance.isControlPressed;

  /// Whether a drag beginning now is a rubber-band selection.
  ///
  /// ⌥ or ⌘, whatever tool is up. Switching to the select tool to lasso a few
  /// notes and switching back is the round trip a modifier exists to remove —
  /// and with the pencil up, ⌥-dragging used to *draw*, which is the opposite
  /// of what a selection modifier should do.
  bool get _isLasso =>
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  int _maybeSnap(int tick) => _snapOff ? tick : _store.snapDown(tick);

  PrViewport _buildViewport(OneBeatTokens tokens) {
    final double rowHeight = tokens.size.pianoRowHeight * _store.verticalZoom;
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
          orElse:
              () => _store.patterns.isNotEmpty ? _store.patterns.first : null,
        );
    final String patternName = currentPattern?.name ?? 'Pattern';

    final ProjectInstrument?
    currentInst = _store.instruments.cast<ProjectInstrument?>().firstWhere(
      (ProjectInstrument? inst) => inst?.id == _store.instrumentId,
      orElse:
          () => _store.instruments.isNotEmpty ? _store.instruments.first : null,
    );
    final String instName = currentInst?.name ?? _store.instrumentId;

    final int instIndex = _store.instruments.indexWhere(
      (ProjectInstrument inst) => inst.id == _store.instrumentId,
    );
    final Color channelColor = _resolveInstrumentColor(
      instIndex >= 0 ? instIndex : 0,
      currentInst?.color,
    );

    final List<String> patternNames =
        _store.patterns.isNotEmpty
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

    // Playhead calculation.
    //
    // Wrapped on the transport's *loop region* — the same [start, end) the
    // engine wraps the audio on, read straight back from the snapshot. Deriving
    // the loop length from the notes under-read once several instruments share
    // a pattern; reading it from the snapshot keeps the drawn playhead on
    // exactly the tick the audio wraps on.
    int? playheadTick;
    final EngineSnapshot snapshot = _controller.snapshot;
    if (snapshot.playing) {
      final double startBeats = snapshot.loopStartBeats;
      final double endBeats = snapshot.loopEndBeats;
      final double loopLengthBeats =
          endBeats > startBeats ? endBeats - startBeats : 0.0;
      final double inLoop = snapshot.positionBeats - startBeats;
      final double looped =
          loopLengthBeats > 0.0 ? inLoop % loopLengthBeats : inLoop;
      playheadTick = ((looped < 0.0 ? 0.0 : looped) * ticksPerQuarter).round();
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
    // A previewed note lights the same way a played one does. "Sounding" is one
    // idea, and the roll should not care whether the transport or your own
    // click is what made the sound.
    final int? previewing = _store.auditionKey;
    if (previewing != null) activeKeys.add(previewing);

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
    FocusPolicy.take(_focus);
    final int tick = view.tickAt(details.localPosition.dx);
    final int key = view.noteAt(details.localPosition.dy);
    final SequenceNote? hit = _store.noteAt(tick, key);

    // A lasso that never moved far enough to become a drag. It still means
    // "select", so it must not fall through to the pencil and draw.
    if (_isLasso) {
      if (hit != null) {
        _store.selectOnly(hit);
      } else {
        _store.clearSelection();
      }
      return;
    }

    if (hit != null) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _store.toggleSelection(hit);
      } else if (_store.tool == PrTool.eraser) {
        _store.deleteNote(hit);
      } else {
        // A note already in the selection keeps the whole selection: this fires
        // on *press*, before the arena has decided whether the gesture is a
        // click or the start of a drag, and narrowing here would leave a block
        // move dragging one note out of the block. A press that rests for the
        // tap deadline before moving — the normal way to grab a phrase — is
        // exactly the path that used to lose it. [_onTapUp] narrows instead,
        // once the gesture is known to have been a click.
        if (!_store.selection.contains(hit)) {
          _store.selectOnly(hit);
        }
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

  /// A click that never became a drag, on a note inside a multi-selection.
  ///
  /// Only here can the roll know the difference between "you are picking this
  /// one note out" and "you are about to move the block" — the press looks
  /// identical either way, and the gesture arena rejects the tap the moment the
  /// pointer travels, so a drag never reaches this.
  void _onTapUp(TapUpDetails details, PrViewport view) {
    if (_isLasso ||
        HardwareKeyboard.instance.isShiftPressed ||
        _store.tool == PrTool.eraser ||
        _store.selection.length < 2) {
      return;
    }
    final SequenceNote? hit = _store.noteAt(
      view.tickAt(details.localPosition.dx),
      view.noteAt(details.localPosition.dy),
    );
    if (hit != null && _store.selection.contains(hit)) {
      _store.selectOnly(hit);
    }
  }

  /// Whether [x] falls in [note]'s right-edge grab zone.
  ///
  /// Capped at a third of the note, because the zone is a fixed number of
  /// pixels and a note is not: zoomed out, a 1/16 is a handful of pixels wide
  /// and a fixed handle would swallow all of it, leaving no way to move the
  /// note at all.
  bool _onResizeEdge(SequenceNote note, double x, PrViewport view) {
    final double endX = view.xOf(note.endTicks);
    final double width = note.lengthTicks / view.ticksPerPx;
    final double handle = OneBeatTheme.of(context).size.pianoResizeHandleWidth;
    final double zone = handle < width / 3 ? handle : width / 3;
    return x >= endX - zone && x <= endX;
  }

  /// What the pointer is over, said in the cursor: the one affordance that
  /// tells you a note can be resized *before* you commit to a drag.
  MouseCursor _cursorAt(Offset local, PrViewport view) {
    if (_store.tool == PrTool.eraser) return MouseCursor.defer;
    final SequenceNote? hit = _store.noteAt(
      view.tickAt(local.dx),
      view.noteAt(local.dy),
    );
    if (hit == null) return MouseCursor.defer;
    return _onResizeEdge(hit, local.dx, view)
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.grab;
  }

  void _onGridHover(Offset local, PrViewport view) {
    // No setState: this feeds the *next* paste, not the current frame.
    _hoverTick = view.tickAt(local.dx);
    final MouseCursor next = _cursorAt(local, view);
    // Only when it changes: a hover fires per pixel, and a setState per pixel
    // would rebuild the roll for a cursor that already looks right.
    if (next == _gridCursor) return;
    setState(() => _gridCursor = next);
  }

  void _onGridExit() => _hoverTick = null;

  /// Where a paste lands: under the pointer if it is over the canvas, otherwise
  /// the next free slot after the last note.
  ///
  /// The pointer is the only thing on screen that says *where you are working*
  /// — a paste that ignored it and went back to where the copy was taken from
  /// made ⌘C ⌘V useless for moving a phrase anywhere.
  int get _pasteTick =>
      _hoverTick == null ? _store.nextFreeTick : _maybeSnap(_hoverTick!);

  // ----- Erasing ------------------------------------------------------------

  /// The last point the erase sweep sampled, in canvas coordinates.
  Offset? _lastErasePoint;

  void _onEraseStart(Offset local, PrViewport view) {
    FocusPolicy.take(_focus);
    // A right-click is a sweep of length zero, so there is one code path rather
    // than a tap handler and a drag handler that have to agree.
    _store.beginErase();
    _lastErasePoint = null;
    _sweepErase(local, view);
  }

  void _onEraseUpdate(Offset local, PrViewport view) {
    if (_store.dragKind != PianoDragKind.erase) return;
    _sweepErase(local, view);
  }

  void _onEraseEnd() {
    if (_store.dragKind != PianoDragKind.erase) return;
    _lastErasePoint = null;
    _store.endDrag();
  }

  /// Erases everything the pointer crossed since the last sample, not only what
  /// is under it now.
  ///
  /// A quick sweep delivers pointer moves tens of pixels apart, and a note
  /// narrower than that gap would survive a stroke drawn straight through it —
  /// which reads as the erase randomly missing.
  void _sweepErase(Offset local, PrViewport view) {
    final Offset? from = _lastErasePoint;
    _lastErasePoint = local;
    if (from == null) {
      _eraseAt(local, view);
      return;
    }
    final double step = view.rowHeight / 2;
    final int samples =
        step <= 0 ? 1 : ((local - from).distance / step).ceil().clamp(1, 64);
    for (int i = 1; i <= samples; i++) {
      _eraseAt(Offset.lerp(from, local, i / samples)!, view);
    }
  }

  void _eraseAt(Offset local, PrViewport view) =>
      _store.eraseAt(view.tickAt(local.dx), view.noteAt(local.dy));

  void _onPanStart(DragStartDetails details, PrViewport view) {
    FocusPolicy.take(_focus);
    final int tick = view.tickAt(details.localPosition.dx);
    final int key = view.noteAt(details.localPosition.dy);
    _dragOriginTick = tick;
    _dragOriginKey = key;

    if (_isLasso) {
      _store.beginMarquee(tick, key);
      return;
    }

    // The eraser tool's drag is the same sweep the right button does, so the
    // two never disagree about what a stroke removes.
    if (_store.tool == PrTool.eraser) {
      _onEraseStart(details.localPosition, view);
      return;
    }

    final SequenceNote? hit = _store.noteAt(tick, key);
    if (hit == null) {
      if (_store.tool == PrTool.pencil) {
        _store.addNoteAt(_maybeSnap(tick), key);
        // The drawn note's own end is what the drag then stretches.
        _resizeOriginEnd = _maybeSnap(tick) + _store.defaultNoteLength;
        _store.beginResize();
      } else {
        _store.beginMarquee(tick, key);
      }
      return;
    }

    if (!_store.selection.contains(hit)) {
      _store.selectOnly(hit);
    }

    if (_onResizeEdge(hit, details.localPosition.dx, view)) {
      _resizeOriginEnd = hit.endTicks;
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
        // Measured from the note's *end*, not from where the drag began. The
        // edge then lands exactly where the pointer is, instead of trailing it
        // by however far into the handle you happened to click.
        final int target = _snapOff ? tick : _store.snap(tick);
        _store.updateResize(target - _resizeOriginEnd);
      case PianoDragKind.marquee:
        _store.updateMarquee(tick, key);
      case PianoDragKind.erase:
        _sweepErase(details.localPosition, view);
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
  /// Where several notes start on the same tick their stems coincide exactly,
  /// and the lane has no axis left to tell them apart. The selection breaks the
  /// tie: with some of the chord selected only those voices move, and with none
  /// of it selected the whole stack moves together — which is what a single
  /// visible stem looks like it should do. Refusing to act on an ambiguous grab
  /// read as the lane being broken for chords.
  void _applyVelocity(
    Offset local,
    double height,
    PrViewport view,
    double gutter,
  ) {
    if (PrLaneKind.fromLabel(_selectedVelocityLane) != PrLaneKind.velocity) {
      return;
    }
    final double fraction = (1.0 - (local.dy / height)).clamp(0.0, 1.0);
    final int velocity = (fraction * 16383).round().clamp(1, 16383);

    final int tick = view.tickAt(local.dx - gutter);
    // A stem is a few pixels wide; the grab radius is expressed in ticks so it
    // stays the same *distance* at every zoom.
    final double stemWidth = OneBeatTheme.of(context).size.prVelocityStemWidth;
    final int tolerance = (stemWidth * 2 * view.ticksPerPx).round();
    final List<SequenceNote> hits = _store.notesNearTick(tick, tolerance);
    if (hits.isEmpty) return;

    if (hits.length == 1) {
      _store.setNoteVelocity(hits.single, velocity);
      return;
    }

    // A chord. The selected voices if any of them are selected, otherwise the
    // whole stack.
    final List<SequenceNote> selected =
        hits.where(_store.selection.contains).toList();
    for (final SequenceNote note in selected.isEmpty ? hits : selected) {
      _store.setNoteVelocity(note, velocity);
    }
  }

  // ----- Trackpad -----------------------------------------------------------

  /// The cumulative scale reported at the previous pan/zoom update. A trackpad
  /// reports total scale since the gesture began, so the frame-to-frame zoom
  /// factor is the ratio between two of them.
  double _lastPinchScale = 1.0;

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _lastPinchScale = 1.0;
  }

  void _onPanZoomUpdate(
    PointerPanZoomUpdateEvent event,
    PrViewport view,
    double gutter,
  ) {
    // Pinch to zoom the time axis, about the pointer.
    if (event.scale != _lastPinchScale && event.scale > 0) {
      final double factor = event.scale / _lastPinchScale;
      _lastPinchScale = event.scale;
      final double canvasX = event.localPosition.dx - gutter;
      _store.zoomHorizontally(
        factor,
        anchorTick: _store.scrollTicks + canvasX / _store.pixelsPerTick,
      );
      return;
    }
    // Two-finger pan. Unlike a scroll signal, a pan delta follows the fingers,
    // so the content moves *with* the gesture rather than against it.
    _store.panBy(
      deltaTicks: -event.panDelta.dx * view.ticksPerPx,
      deltaKeys: (event.panDelta.dy / view.rowHeight).round(),
      visibleRows: _visibleRows,
    );
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
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
        ): const _NudgeKeyIntent(1),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
        ): const _NudgeKeyIntent(-1),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          shift: true,
        ): const _NudgeKeyIntent(12),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          shift: true,
        ): const _NudgeKeyIntent(-12),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
        ): const _NudgeTimeIntent(-1),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
        ): const _NudgeTimeIntent(1),

        // Explicit panning, which works whatever is selected.
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          alt: true,
        ): const _PanIntent(deltaKeys: 1),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          alt: true,
        ): const _PanIntent(deltaKeys: -1),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          alt: true,
        ): const _PanIntent(deltaBeats: -1),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          alt: true,
        ): const _PanIntent(deltaBeats: 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): const _PanIntent(
          pages: 1,
        ),
        const SingleActivator(LogicalKeyboardKey.pageDown): const _PanIntent(
          pages: -1,
        ),
        const SingleActivator(
          LogicalKeyboardKey.pageUp,
          shift: true,
        ): const _PanIntent(horizontalPages: -1),
        const SingleActivator(
          LogicalKeyboardKey.pageDown,
          shift: true,
        ): const _PanIntent(horizontalPages: 1),
        const SingleActivator(LogicalKeyboardKey.home): const _HomeIntent(),

        // Zoom. Both the main-row and the numpad keys, because a laptop and a
        // full keyboard disagree about which one `+` is.
        const SingleActivator(
          LogicalKeyboardKey.equal,
          meta: true,
        ): const _ZoomIntent(1.25),
        const SingleActivator(
          LogicalKeyboardKey.add,
          meta: true,
        ): const _ZoomIntent(1.25),
        const SingleActivator(
          LogicalKeyboardKey.minus,
          meta: true,
        ): const _ZoomIntent(0.8),
        const SingleActivator(
          LogicalKeyboardKey.numpadSubtract,
          meta: true,
        ): const _ZoomIntent(0.8),
        const SingleActivator(
          LogicalKeyboardKey.equal,
          meta: true,
          shift: true,
        ): const _ZoomIntent(1.25, vertical: true),
        const SingleActivator(
          LogicalKeyboardKey.minus,
          meta: true,
          shift: true,
        ): const _ZoomIntent(0.8, vertical: true),

        // Tools, matching the letters in their tooltips.
        const SingleActivator(LogicalKeyboardKey.keyP): const _ToolIntent(
          PrTool.pencil,
        ),
        const SingleActivator(LogicalKeyboardKey.keyE): const _ToolIntent(
          PrTool.select,
        ),
        const SingleActivator(LogicalKeyboardKey.keyD): const _ToolIntent(
          PrTool.eraser,
        ),

        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const CancelIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const _SelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            const _DuplicateIntent(),
        // ⌘B is FL's duplicate: the selection again, one selection-length
        // later. ⌘D is kept as the alias the rest of the app already used.
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            const _DuplicateIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            const _CopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true):
            const _CutIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const _PasteIntent(),
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
            final int step =
                _store.snapTicks > 0 ? _store.snapTicks : ticksPerQuarter ~/ 4;
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
                  intent.deltaKeys + intent.pages * (rows > 1 ? rows - 1 : 1),
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
        _CopyIntent: CallbackAction<_CopyIntent>(
          onInvoke: (_) {
            _store.copySelection();
            return null;
          },
        ),
        _CutIntent: CallbackAction<_CutIntent>(
          onInvoke: (_) {
            _store.cutSelection();
            return null;
          },
        ),
        _PasteIntent: CallbackAction<_PasteIntent>(
          onInvoke: (_) {
            _store.pasteClipboard(atTick: _pasteTick);
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
          onZoomIn:
              () => _store.zoomHorizontally(1.25, anchorTick: _centreTick),
          onZoomOut:
              () => _store.zoomHorizontally(0.8, anchorTick: _centreTick),
          onBack: widget.onBackToPlaylist,
          onKeyPress: (int key) => _store.audition(key),
          onTapDown: (TapDownDetails d) => _onTapDown(d, view),
          onTapUp: (TapUpDetails d) => _onTapUp(d, view),
          onPanStart: (DragStartDetails d) => _onPanStart(d, view),
          onPanUpdate: (DragUpdateDetails d) => _onPanUpdate(d, view),
          onPanEnd: (_) => _store.endDrag(),
          onPanCancel: _store.cancelDrag,
          onEraseStart: (Offset local) => _onEraseStart(local, view),
          onEraseUpdate: (Offset local) => _onEraseUpdate(local, view),
          onEraseEnd: _onEraseEnd,
          onGridHover: (Offset local) => _onGridHover(local, view),
          onGridExit: _onGridExit,
          gridCursor: _gridCursor,
          onPointerSignal:
              (PointerSignalEvent e) => _onPointerSignal(e, view, gutter),
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate:
              (PointerPanZoomUpdateEvent e) =>
                  _onPanZoomUpdate(e, view, gutter),
          onPointerPanZoomEnd: (_) => _lastPinchScale = 1.0,
          onScrollTicks: (double ticks) => _store.panTo(ticks, _store.topKey),
          onScrollTopKey: (int key) => _store.panTo(_store.scrollTicks, key),
          onGridSize: _onGridSize,
          onLaneChanged:
              (String lane) => setState(() => _selectedVelocityLane = lane),
          onVelocityTapDown:
              (TapDownDetails d, double h) =>
                  _onVelocityTapDown(d, h, view, gutter),
          onVelocityDragStart: _store.beginVelocityGesture,
          onVelocityDragUpdate:
              (DragUpdateDetails d, double h) =>
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

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _CutIntent extends Intent {
  const _CutIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _QuantiseIntent extends Intent {
  const _QuantiseIntent();
}
