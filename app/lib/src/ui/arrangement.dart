// The arrangement view (OB-3-12, design screen `onebeat-shell.html` canvas
// region), with the clip inspector from OB-3-13 down its right edge.
//
// Layered painters per ADR-001: lane backgrounds and the bar grid in one layer,
// clips in another, playhead in a third. Paints are built once per painter.
//
// **The critical negative, enforced here in the UI** (ARCHITECTURE.md §6 #2):
// a lane header carries a name, a colour, an event-gate mute, a solo and a
// collapse — and nothing else. No meter, no fader, no plugin slot, no
// instrument. If a future change adds one, it is the anti-pattern this whole
// model was shaped to make impossible, not a feature.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'action_registry.dart';
import 'arrangement_store.dart';
import 'clip_inspector.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'pattern_store.dart';
import 'piano_roll_store.dart' show GridChoice, ticksPerBar, ticksPerQuarter;

/// The arrangement as the app uses it: transport and playhead come from the
/// live engine, everything else from [ArrangementSurface].
class ArrangementView extends StatelessWidget {
  const ArrangementView({
    required this.controller,
    required this.store,
    required this.patterns,
    required this.onOpenPattern,
    super.key,
  });

  final EngineController controller;
  final ArrangementStore store;
  final PatternStore patterns;
  final void Function(String patternId, String clipId) onOpenPattern;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (BuildContext context, Widget? child) => ArrangementSurface(
      store: store,
      patterns: patterns,
      positionTicks: controller.snapshot.positionBeats * ticksPerQuarter,
      loopEnabled: controller.snapshot.loopEnabled,
      loopStartTicks: controller.snapshot.loopStartBeats * ticksPerQuarter,
      loopEndTicks: controller.snapshot.loopEndBeats * ticksPerQuarter,
      onSeekTicks: (int ticks) =>
          controller.client.seekBeats(ticks / ticksPerQuarter),
      onSetLoop: (int startTicks, int endTicks) => controller.client.setLoop(
        startTicks / ticksPerQuarter,
        endTicks / ticksPerQuarter,
        enabled: true,
      ),
      onOpenPattern: onOpenPattern,
    ),
  );
}

/// The arrangement itself. Depends on stores, a playhead position and two
/// transport callbacks — never on the engine, so `flutter test` can drive the
/// real widget with a scripted seam (OB-3-14 §1).
class ArrangementSurface extends StatefulWidget {
  const ArrangementSurface({
    required this.store,
    required this.patterns,
    required this.positionTicks,
    required this.onOpenPattern,
    this.loopEnabled = false,
    this.loopStartTicks = 0,
    this.loopEndTicks = 0,
    this.onSeekTicks,
    this.onSetLoop,
    super.key,
  });

  final ArrangementStore store;
  final PatternStore patterns;
  final double positionTicks;
  final bool loopEnabled;
  final double loopStartTicks;
  final double loopEndTicks;

  /// Clicking the ruler seeks; dragging it sets the loop region (§4).
  final ValueChanged<int>? onSeekTicks;
  final void Function(int startTicks, int endTicks)? onSetLoop;

  /// Double-clicking a clip opens its pattern in the note editors (§4). The
  /// clip id travels with it so the D-M6 notice can offer "Make unique for this
  /// clip" when the edit turns out to touch a shared pattern.
  final void Function(String patternId, String clipId) onOpenPattern;

  @override
  State<ArrangementSurface> createState() => _ArrangementViewState();
}

class _ArrangementViewState extends State<ArrangementSurface> {
  final FocusNode _focus = FocusNode(debugLabel: 'arrangement');
  final ScrollController _laneScroll = ScrollController();

  int _dragOriginTick = 0;
  String _dragClipId = '';
  int _dragOriginLength = 0;
  int _dragOriginWindow = 0;

  @override
  void dispose() {
    _focus.dispose();
    _laneScroll.dispose();
    super.dispose();
  }

  ArrangementStore get _store => widget.store;

  int _tickAt(double x) =>
      (_store.scrollTicks + x / _store.pixelsPerTick).round().clamp(0, 1 << 30);

  double _xOfTick(num tick) =>
      (tick - _store.scrollTicks) * _store.pixelsPerTick;

  double _laneHeight(ArrangementLane lane, OneBeatTokens tokens) =>
      lane.collapsed ? tokens.size.laneCollapsedHeight : lane.height.toDouble();

  /// The lane under a vertical offset in the clip canvas, or null past the end.
  ArrangementLane? _laneAt(double y, OneBeatTokens tokens) {
    double cursor = 0;
    for (final ArrangementLane lane in _store.lanes) {
      final double height = _laneHeight(lane, tokens);
      if (y >= cursor && y < cursor + height) return lane;
      cursor += height;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_store, widget.patterns]),
      builder: (BuildContext context, Widget? child) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyD, meta: true):
              _DuplicateClipIntent(),
          SingleActivator(LogicalKeyboardKey.keyB, meta: true):
              _PlaceClipIntent(),
          SingleActivator(LogicalKeyboardKey.delete): _DeleteClipIntent(),
          SingleActivator(LogicalKeyboardKey.backspace): _DeleteClipIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _CancelDragIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DuplicateClipIntent: CallbackAction<_DuplicateClipIntent>(
              onInvoke: (_) {
                _store.duplicateSelection();
                return null;
              },
            ),
            _PlaceClipIntent: CallbackAction<_PlaceClipIntent>(
              onInvoke: (_) {
                _placeCurrentPattern();
                return null;
              },
            ),
            _DeleteClipIntent: CallbackAction<_DeleteClipIntent>(
              onInvoke: (_) {
                _store.deleteSelection();
                return null;
              },
            ),
            _CancelDragIntent: CallbackAction<_CancelDragIntent>(
              onInvoke: (_) {
                _store.cancelClipDrag();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _focus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ArrangementToolbar(
                  store: _store,
                  patterns: widget.patterns,
                  onPlace: _placeCurrentPattern,
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _buildLanesAndCanvas(tokens)),
                      ClipInspector(store: _store, patterns: widget.patterns),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _placeCurrentPattern() {
    final String laneId = _store.selectedLaneId.isNotEmpty
        ? _store.selectedLaneId
        : (_store.lanes.isEmpty ? '' : _store.lanes.first.id);
    if (laneId.isEmpty) return;
    // Lands at the end of what is already on the lane, which is what "add
    // another bar of this" means when the user has not aimed anywhere.
    int start = 0;
    for (final ArrangementClip clip in _store.clipsOnLane(laneId)) {
      if (clip.endTicks > start) start = clip.endTicks;
    }
    _store.placeCurrentPattern(laneId, start);
  }

  Widget _buildLanesAndCanvas(OneBeatTokens tokens) {
    final double totalHeight = _store.lanes.fold<double>(
      0,
      (double sum, ArrangementLane lane) => sum + _laneHeight(lane, tokens),
    );

    // The view owns its background: the lanes only cover their own height, and
    // below the last one there is still canvas rather than a hole.
    return ColoredBox(
      color: tokens.color.surfaceDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: tokens.size.arrangementRulerHeight,
            child: Row(
              children: <Widget>[
                // The ruler's gutter sits above the lane headers and takes their
                // surface, so the two read as one column.
                Container(
                  width: tokens.size.laneHeaderWidth,
                  color: tokens.color.surfacePanel,
                ),
                Expanded(child: _buildRuler(tokens)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _laneScroll,
              child: SizedBox(
                height: math.max(totalHeight, 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: tokens.size.laneHeaderWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final ArrangementLane lane in _store.lanes)
                            SizedBox(
                              height: _laneHeight(lane, tokens),
                              child: _LaneHeader(
                                lane: lane,
                                store: _store,
                                selected: _store.selectedLaneId == lane.id,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: _buildClipCanvas(tokens, totalHeight)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The ruler: bar numbers, click to seek, drag to set the loop region (§4).
  Widget _buildRuler(OneBeatTokens tokens) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (TapDownDetails details) => widget.onSeekTicks?.call(
        _store.snapTick(_tickAt(details.localPosition.dx)),
      ),
      onHorizontalDragStart: (DragStartDetails details) {
        _dragOriginTick = _store.snapTick(_tickAt(details.localPosition.dx));
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        final int end = _store.snapTick(_tickAt(details.localPosition.dx));
        final int low = math.min(_dragOriginTick, end);
        final int high = math.max(_dragOriginTick, end);
        if (high <= low) return;
        widget.onSetLoop?.call(low, high);
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RulerPainter(
            tokens: tokens,
            store: _store,
            positionTicks: widget.positionTicks,
            loopEnabled: widget.loopEnabled,
            loopStartTicks: widget.loopStartTicks,
            loopEndTicks: widget.loopEndTicks,
          ),
        ),
      ),
    );
  }

  Widget _buildClipCanvas(OneBeatTokens tokens, double totalHeight) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onCanvasTapDown,
        onDoubleTapDown: _onCanvasDoubleTap,
        onPanStart: _onCanvasPanStart,
        onPanUpdate: _onCanvasPanUpdate,
        onPanEnd: (_) => _store.endClipDrag(),
        onPanCancel: _store.cancelClipDrag,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RepaintBoundary(
                child: CustomPaint(
                  painter: _LaneGridPainter(
                    tokens: tokens,
                    store: _store,
                    laneHeightOf: (ArrangementLane lane) =>
                        _laneHeight(lane, tokens),
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _ClipsPainter(
                    tokens: tokens,
                    store: _store,
                    laneHeightOf: (ArrangementLane lane) =>
                        _laneHeight(lane, tokens),
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _ArrangementPlayheadPainter(
                    tokens: tokens,
                    store: _store,
                    positionTicks: widget.positionTicks,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- gestures -----------------------------------------------------------

  ArrangementClip? _clipAt(Offset position, OneBeatTokens tokens) {
    final ArrangementLane? lane = _laneAt(position.dy, tokens);
    if (lane == null) return null;
    final int tick = _tickAt(position.dx);
    for (final ArrangementClip clip in _store.clipsOnLane(lane.id)) {
      if (tick >= clip.startTicks && tick < clip.endTicks) return clip;
    }
    return null;
  }

  void _onCanvasTapDown(TapDownDetails details) {
    _focus.requestFocus();
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ArrangementLane? lane = _laneAt(details.localPosition.dy, tokens);
    if (lane != null) _store.selectLane(lane.id);

    final ArrangementClip? clip = _clipAt(details.localPosition, tokens);
    if (clip == null) {
      _store.clearClipSelection();
      return;
    }
    _store.selectClip(
      clip.id,
      additive: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  void _onCanvasDoubleTap(TapDownDetails details) {
    final ArrangementClip? clip = _clipAt(
      details.localPosition,
      OneBeatTheme.of(context),
    );
    if (clip == null || !clip.isPattern) return;
    widget.onOpenPattern(clip.patternId, clip.id);
  }

  void _onCanvasPanStart(DragStartDetails details) {
    _focus.requestFocus();
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final ArrangementClip? clip = _clipAt(details.localPosition, tokens);
    if (clip == null) return;

    if (!_store.isSelected(clip)) _store.selectClip(clip.id);
    _dragOriginTick = _tickAt(details.localPosition.dx);
    _dragClipId = clip.id;
    _dragOriginLength = clip.lengthTicks;
    _dragOriginWindow = clip.windowStartTicks;

    // ⌥ inside a clip shifts the window into the pattern (OB-3-13 §2); the
    // right edge resizes; anywhere else moves.
    if (HardwareKeyboard.instance.isAltPressed) {
      _store.beginClipDrag(ClipDragKind.offset, name: 'Set clip offset');
      return;
    }
    final double endX = _xOfTick(clip.endTicks);
    if ((endX - details.localPosition.dx).abs() <=
        tokens.size.pianoResizeHandleWidth) {
      _store.beginClipDrag(ClipDragKind.resizeEnd, name: 'Resize clip');
    } else {
      _store.beginClipDrag(ClipDragKind.move);
    }
  }

  void _onCanvasPanUpdate(DragUpdateDetails details) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final int tick = _tickAt(details.localPosition.dx);
    final int rawDelta = tick - _dragOriginTick;

    switch (_store.dragKind) {
      case ClipDragKind.move:
        int delta = rawDelta;
        if (_store.snap.ticks > 0) {
          delta = (delta / _store.snap.ticks).round() * _store.snap.ticks;
        }
        final ArrangementLane? lane = _laneAt(details.localPosition.dy, tokens);
        _store.updateClipMove(delta, laneId: lane?.id ?? '');
      case ClipDragKind.resizeEnd:
        int length = _dragOriginLength + rawDelta;
        if (_store.snap.ticks > 0) {
          length = (length / _store.snap.ticks).round() * _store.snap.ticks;
        }
        _store.updateClipResize(_dragClipId, math.max(1, length));
      case ClipDragKind.offset:
        _store.updateClipOffset(
          _dragClipId,
          math.max(0, _dragOriginWindow - rawDelta),
        );
      case ClipDragKind.none:
      case ClipDragKind.marquee:
        break;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isMetaPressed) {
      _store.zoomHorizontally(event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
      return;
    }
    _store.panTo(
      _store.scrollTicks + event.scrollDelta.dx / _store.pixelsPerTick,
    );
  }
}

class _DuplicateClipIntent extends Intent {
  const _DuplicateClipIntent();
}

class _PlaceClipIntent extends Intent {
  const _PlaceClipIntent();
}

class _DeleteClipIntent extends Intent {
  const _DeleteClipIntent();
}

class _CancelDragIntent extends Intent {
  const _CancelDragIntent();
}

class _ArrangementToolbar extends StatelessWidget {
  const _ArrangementToolbar({
    required this.store,
    required this.patterns,
    required this.onPlace,
  });

  final ArrangementStore store;
  final PatternStore patterns;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool hasSelection = store.selectedClipIds.isNotEmpty;
    return Container(
      height: tokens.size.pianoToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(
          bottom: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            Text('Arrangement', style: tokens.type.title),
            SizedBox(width: tokens.spacing.lg),
            OneBeatButton(
              key: actionKey('arrangement.addLane'),
              label: ActionRegistry.byId('arrangement.addLane').label,
              onPressed: () => store.addLane('Lane ${store.lanes.length + 1}'),
            ),
            SizedBox(width: tokens.spacing.xs),
            OneBeatButton(
              key: actionKey('arrangement.placeClip'),
              label: ActionRegistry.byId('arrangement.placeClip').label,
              semanticLabel: ActionRegistry.byId(
                'arrangement.placeClip',
              ).tooltip,
              onPressed: patterns.current == null ? null : onPlace,
            ),
            SizedBox(width: tokens.spacing.xs),
            OneBeatButton(
              key: actionKey('arrangement.duplicateClip'),
              label: ActionRegistry.byId('arrangement.duplicateClip').label,
              onPressed: hasSelection ? store.duplicateSelection : null,
            ),
            SizedBox(width: tokens.spacing.xs),
            OneBeatButton(
              key: actionKey('arrangement.deleteClip'),
              label: ActionRegistry.byId('arrangement.deleteClip').label,
              onPressed: hasSelection ? store.deleteSelection : null,
            ),
            SizedBox(width: tokens.spacing.lg),
            OneBeatSelect<GridChoice>(
              key: actionKey('arrangement.snap'),
              prefix: 'SNAP',
              value: store.snap,
              options: ArrangementStore.snapChoices,
              labelOf: (GridChoice choice) => choice.label,
              onChanged: store.setSnap,
            ),
          ],
        ),
      ),
    );
  }
}

/// One lane header. Name, colour, event-gate mute, solo, collapse, delete.
///
/// Read the list again: there is nothing here that carries signal, and that is
/// the design, not an omission (D-M4, ARCHITECTURE.md §6 #2).
class _LaneHeader extends StatelessWidget {
  const _LaneHeader({
    required this.lane,
    required this.store,
    required this.selected,
  });

  final ArrangementLane lane;
  final ArrangementStore store;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Color color = projectColor(lane.color, tokens.color.accent);
    return GestureDetector(
      onTap: () => store.selectLane(lane.id),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? tokens.color.surfaceRaised
              : tokens.color.surfacePanel,
          border: Border(
            bottom: BorderSide(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
            left: BorderSide(color: color, width: tokens.border.emphasis),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    lane.name,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.body,
                  ),
                ),
                Text('${lane.clipCount}', style: tokens.type.numericSmall),
              ],
            ),
            if (!lane.collapsed) ...<Widget>[
              SizedBox(height: tokens.spacing.xs),
              Row(
                children: <Widget>[
                  OneBeatToggle(
                    key: actionKey('arrangement.laneMute'),
                    label: 'GATE',
                    compact: true,
                    value: lane.muted,
                    tooltip: ActionRegistry.byId('arrangement.laneMute').label,
                    activeColor: tokens.color.warning,
                    onChanged: (_) => store.toggleLaneMute(lane),
                  ),
                  SizedBox(width: tokens.spacing.xs),
                  OneBeatToggle(
                    key: actionKey('arrangement.laneSolo'),
                    label: 'SOLO',
                    compact: true,
                    value: lane.soloed,
                    tooltip: ActionRegistry.byId('arrangement.laneSolo').label,
                    onChanged: (_) => store.toggleLaneSolo(lane),
                  ),
                  SizedBox(width: tokens.spacing.xs),
                  OneBeatToggle(
                    key: actionKey('arrangement.laneCollapse'),
                    label: '▾',
                    compact: true,
                    value: lane.collapsed,
                    tooltip: ActionRegistry.byId(
                      'arrangement.laneCollapse',
                    ).label,
                    onChanged: (_) => store.toggleLaneCollapsed(lane),
                  ),
                  SizedBox(width: tokens.spacing.xs),
                  OneBeatToggle(
                    key: actionKey('arrangement.laneDelete'),
                    label: '✕',
                    compact: true,
                    value: false,
                    tooltip:
                        '${ActionRegistry.byId('arrangement.laneDelete').label} '
                        '(${lane.clipCount} clips)',
                    onChanged: (_) => store.removeLane(lane.id),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

typedef _LaneHeightOf = double Function(ArrangementLane);

class _LaneGridPainter extends CustomPainter {
  _LaneGridPainter({
    required this.tokens,
    required this.store,
    required this.laneHeightOf,
  }) : _laneFill = Paint()..color = tokens.color.surfaceDeep,
       _laneAlt = Paint()..color = tokens.color.rowShade,
       _beatLine = Paint()
         ..color = tokens.color.gridLine
         ..strokeWidth = tokens.border.hairline,
       _barLine = Paint()
         ..color = tokens.color.gridLineStrong
         ..strokeWidth = tokens.border.hairline;

  final OneBeatTokens tokens;
  final ArrangementStore store;
  final _LaneHeightOf laneHeightOf;

  final Paint _laneFill;
  final Paint _laneAlt;
  final Paint _beatLine;
  final Paint _barLine;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _laneFill);

    double y = 0;
    for (int index = 0; index < store.lanes.length; index++) {
      final double height = laneHeightOf(store.lanes[index]);
      if (index.isOdd) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, height), _laneAlt);
      }
      y += height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _beatLine);
    }

    // Bar lines across the whole canvas. Stepping from the first visible bar
    // bounds the loop by the viewport rather than by the arrangement length.
    final int step = store.snap.ticks > 0 ? store.snap.ticks : ticksPerBar;
    final int first = (store.scrollTicks ~/ step) * step;
    final double last = store.scrollTicks + size.width / store.pixelsPerTick;
    for (int tick = first; tick <= last; tick += step) {
      final double x = (tick - store.scrollTicks) * store.pixelsPerTick;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        tick % ticksPerBar == 0 ? _barLine : _beatLine,
      );
    }
  }

  @override
  bool shouldRepaint(_LaneGridPainter old) => true;
}

class _ClipsPainter extends CustomPainter {
  _ClipsPainter({
    required this.tokens,
    required this.store,
    required this.laneHeightOf,
  }) : _fill = Paint(),
       _muted = Paint()..color = tokens.color.canvasScrim,
       _density = Paint(),
       _loopLine = Paint()
         ..color = tokens.color.surfaceDeep
         ..strokeWidth = tokens.border.hairline,
       _outline = Paint()
         ..style = PaintingStyle.stroke
         ..strokeWidth = tokens.border.emphasis;

  final OneBeatTokens tokens;
  final ArrangementStore store;
  final _LaneHeightOf laneHeightOf;

  final Paint _fill;
  final Paint _muted;
  final Paint _density;
  final Paint _loopLine;
  final Paint _outline;

  @override
  void paint(Canvas canvas, Size size) {
    final Radius radius = Radius.circular(tokens.size.clipRadius);
    double y = 0;

    // Bucket by lane once. Asking the store per lane is O(lanes x clips) and,
    // at the 200-clip figure OB-3-12 sets, that scan was the single most
    // expensive thing on the paint path.
    final Map<String, List<ArrangementClip>> byLane =
        <String, List<ArrangementClip>>{};
    for (final ArrangementClip clip in store.clips) {
      (byLane[clip.laneId] ??= <ArrangementClip>[]).add(clip);
    }

    for (final ArrangementLane lane in store.lanes) {
      final double height = laneHeightOf(lane);
      for (final ArrangementClip clip
          in byLane[lane.id] ?? const <ArrangementClip>[]) {
        if (!clip.isPattern) continue;
        final double x =
            (clip.startTicks - store.scrollTicks) * store.pixelsPerTick;
        final double width = clip.lengthTicks * store.pixelsPerTick;
        if (x + width < 0 || x > size.width) continue;

        final Rect rect = Rect.fromLTWH(
          x,
          y + tokens.size.pianoNoteInset,
          math.max(2, width),
          height - tokens.size.pianoNoteInset * 2,
        );
        final RRect rounded = RRect.fromRectAndRadius(rect, radius);

        // The clip wears the *pattern's* colour, because that is what it is a
        // placement of. Saturated user colour against quiet chrome (§15.3).
        _fill.color = projectColor(clip.color, tokens.color.accent);
        canvas.drawRRect(rounded, _fill);

        _paintDensity(canvas, rect, clip);
        _paintLoopBoundaries(canvas, rect, clip);

        if (clip.muted) canvas.drawRRect(rounded, _muted);

        // Selection is a bright outline; instance highlighting (D-M6) is the
        // same outline in a quieter weight, so "these are the same pattern"
        // and "this is selected" read as related facts.
        if (store.isSelected(clip)) {
          _outline.color = tokens.color.noteSelected;
          canvas.drawRRect(rounded, _outline);
        } else if (store.isHighlighted(clip)) {
          _outline.color = tokens.color.clipSelectedOutline;
          canvas.drawRRect(rounded, _outline);
        }

        _paintLabel(canvas, rect, clip);
      }
      y += height;
    }
  }

  /// A mini note-density preview (§3): one faint tick per note, positioned as
  /// it falls inside the pattern. Enough to tell two clips apart at a glance
  /// without pretending to be a readable score.
  void _paintDensity(Canvas canvas, Rect rect, ArrangementClip clip) {
    if (clip.noteCount == 0 || clip.patternLengthTicks <= 0) return;
    _density.color = tokens.color.surfaceDeep;
    final double bandTop = rect.top + rect.height * 0.55;
    final double bandHeight = rect.height * 0.35;
    if (bandHeight <= 1) return;
    // Deterministic spread rather than the real note positions: reading every
    // note of every clip on every paint is exactly the per-frame work ADR-001
    // forbids, and the preview only has to convey "busy" versus "sparse".
    //
    // Capped by the clip's width as well as its note count. A 20-pixel clip
    // cannot show 64 distinct ticks — they land on top of each other — so
    // drawing them is pure cost, and at 200 clips it was most of the frame.
    final int ticks = math.min(
      math.min(clip.noteCount, 64),
      (rect.width / 2).floor(),
    );
    if (ticks <= 0) return;
    for (int index = 0; index < ticks; index++) {
      final double fraction = (index + 0.5) / ticks;
      final double x = rect.left + rect.width * fraction;
      if (x < rect.left || x > rect.right) continue;
      canvas.drawRect(
        Rect.fromLTWH(x, bandTop, tokens.border.hairline, bandHeight),
        _density,
      );
    }
  }

  /// Where the pattern restarts inside a looping clip (OB-3-13 §1).
  void _paintLoopBoundaries(Canvas canvas, Rect rect, ArrangementClip clip) {
    if (!clip.loop || clip.patternLengthTicks <= 0) return;
    final double period = clip.patternLengthTicks * store.pixelsPerTick;
    if (period < 4) return;
    for (double x = rect.left + period; x < rect.right; x += period) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), _loopLine);
    }
  }

  void _paintLabel(Canvas canvas, Rect rect, ArrangementClip clip) {
    if (rect.width < tokens.size.controlMinWidth) return;
    final String transpose = clip.transpose == 0
        ? ''
        : '  ${clip.transpose > 0 ? '+' : ''}${clip.transpose}';
    final String loop = clip.loop ? '' : '  ⤓';
    final TextPainter label = TextPainter(
      text: TextSpan(
        text: '${clip.name}$transpose$loop',
        style: tokens.type.labelDense.copyWith(color: tokens.color.surfaceDeep),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - tokens.spacing.sm);
    label.paint(
      canvas,
      Offset(rect.left + tokens.spacing.xs, rect.top + tokens.spacing.xxs),
    );
  }

  @override
  bool shouldRepaint(_ClipsPainter old) => true;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.tokens,
    required this.store,
    required this.positionTicks,
    required this.loopEnabled,
    required this.loopStartTicks,
    required this.loopEndTicks,
  }) : _background = Paint()..color = tokens.color.surfacePanel,
       _tick = Paint()
         ..color = tokens.color.gridLineStrong
         ..strokeWidth = tokens.border.hairline,
       _loop = Paint()..color = tokens.color.marqueeFill,
       _playhead = Paint()
         ..color = tokens.color.playhead
         ..strokeWidth = tokens.size.playheadWidth;

  final OneBeatTokens tokens;
  final ArrangementStore store;
  final double positionTicks;
  final bool loopEnabled;
  final double loopStartTicks;
  final double loopEndTicks;

  final Paint _background;
  final Paint _tick;
  final Paint _loop;
  final Paint _playhead;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _background);

    if (loopEnabled) {
      final double left =
          (loopStartTicks - store.scrollTicks) * store.pixelsPerTick;
      final double right =
          (loopEndTicks - store.scrollTicks) * store.pixelsPerTick;
      if (right > left) {
        canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), _loop);
      }
    }

    final int firstBar = (store.scrollTicks ~/ ticksPerBar).toInt();
    final double lastTick =
        store.scrollTicks + size.width / store.pixelsPerTick;
    for (int bar = firstBar; ; bar++) {
      final int tick = bar * ticksPerBar;
      if (tick > lastTick) break;
      final double x = (tick - store.scrollTicks) * store.pixelsPerTick;
      canvas.drawLine(
        Offset(x, size.height * 0.5),
        Offset(x, size.height),
        _tick,
      );
      final TextPainter label = TextPainter(
        text: TextSpan(text: '${bar + 1}', style: tokens.type.numericSmall),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + tokens.spacing.xxs, tokens.spacing.xxs));
    }

    final double head =
        (positionTicks - store.scrollTicks) * store.pixelsPerTick;
    if (head >= 0 && head <= size.width) {
      canvas.drawLine(Offset(head, 0), Offset(head, size.height), _playhead);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => true;
}

class _ArrangementPlayheadPainter extends CustomPainter {
  _ArrangementPlayheadPainter({
    required this.tokens,
    required this.store,
    required this.positionTicks,
  }) : _line = Paint()
         ..color = tokens.color.playhead
         ..strokeWidth = tokens.size.playheadWidth;

  final OneBeatTokens tokens;
  final ArrangementStore store;
  final double positionTicks;

  final Paint _line;

  @override
  void paint(Canvas canvas, Size size) {
    final double x = (positionTicks - store.scrollTicks) * store.pixelsPerTick;
    if (x < 0 || x > size.width) return;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), _line);
  }

  @override
  bool shouldRepaint(_ArrangementPlayheadPainter old) =>
      old.positionTicks != positionTicks ||
      old.store.scrollTicks != store.scrollTicks ||
      old.store.pixelsPerTick != store.pixelsPerTick;
}
