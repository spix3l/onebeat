// The piano roll (OB-3-10, FR-SEQ-02, design screen `onebeat-piano.html`).
//
// Layered painters per ADR-001: the grid, the notes and the playhead are three
// `CustomPaint`s stacked, each with its own repaint boundary, so a moving
// playhead does not repaint 2,000 notes and a note edit does not repaint the
// grid. Every `Paint` is built once in the painter's constructor — nothing on
// the paint path allocates (R13).
//
// Editing goes through `PianoRollStore`, which goes through the native command
// layer, so there is no path from a gesture to the model that skips undo.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'action_registry.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'pattern_store.dart';
import 'piano_roll_store.dart';
import 'shortcuts.dart';

/// The piano roll as the app uses it: takes the playhead from the live engine
/// snapshot and delegates everything else to [PianoRollSurface].
class PianoRoll extends StatelessWidget {
  const PianoRoll({
    required this.controller,
    required this.store,
    required this.patterns,
    super.key,
  });

  final EngineController controller;
  final PianoRollStore store;
  final PatternStore patterns;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (BuildContext context, Widget? child) => PianoRollSurface(
      store: store,
      patterns: patterns,
      positionTicks: controller.snapshot.positionBeats * ticksPerQuarter,
    ),
  );
}

/// The roll itself. Depends on stores and a playhead position, never on the
/// engine — which is what lets `flutter test` drive the real widget with a
/// scripted seam and a stationary playhead (OB-3-14 §1).
class PianoRollSurface extends StatefulWidget {
  const PianoRollSurface({
    required this.store,
    required this.patterns,
    required this.positionTicks,
    super.key,
  });

  final PianoRollStore store;
  final PatternStore patterns;
  final double positionTicks;

  @override
  State<PianoRollSurface> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRollSurface> {
  final FocusNode _focus = FocusNode(debugLabel: 'piano-roll');
  Size _canvasSize = Size.zero;

  // Where the current drag started, in model space. Deltas are computed against
  // this rather than accumulated per-event, so a fast drag cannot drift.
  int _dragOriginTick = 0;
  int _dragOriginKey = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  PianoRollStore get _store => widget.store;

  double get _rowHeight =>
      OneBeatTheme.of(context).size.pianoRowHeight * _store.verticalZoom;

  int _keyAt(double y) => (_store.topKey - (y / _rowHeight).floor()).clamp(0, 127);

  int _tickAt(double x) =>
      (_store.scrollTicks + x / _store.pixelsPerTick).round().clamp(0, 1 << 30);

  double _xOfTick(num tick) =>
      (tick - _store.scrollTicks) * _store.pixelsPerTick;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_store, widget.patterns]),
      builder: (BuildContext context, Widget? child) {
        if (_store.instrumentId.isEmpty) {
          return _EmptyRoll(tokens: tokens);
        }
        return ScopedShortcuts(
          shortcuts: _shortcuts,
          handlers: _handlers,
          extraActions: _navigationActions,
          child: Focus(
            // No autofocus. The shell holds the only one in the app; this takes
            // focus on pointer-down inside the canvas, so switching to the roll
            // does not silently steal the keyboard from a rename field.
            focusNode: _focus,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PianoToolbar(
                  store: _store,
                  patterns: widget.patterns,
                  onZoomToSelection: _zoomToSelection,
                ),
                Expanded(child: _buildCanvas(tokens)),
                _VelocityStrip(store: _store),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCanvas(OneBeatTokens tokens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: tokens.size.pianoKeyboardWidth,
          child: _Keyboard(store: _store, onAudition: _store.audition),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              _canvasSize = constraints.biggest;
              return _buildGridArea(tokens, constraints.biggest);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGridArea(OneBeatTokens tokens, Size size) {
    final PatternSummary? pattern = widget.patterns.current;
    final int patternLength = pattern?.lengthTicks ?? ticksPerBar;

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onSecondaryTapDown: _onSecondaryTapDown,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (_) => _store.endDrag(),
        onPanCancel: _store.cancelDrag,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Static-ish: repaints only on zoom, scroll or scale change.
              RepaintBoundary(
                child: CustomPaint(
                  painter: _GridPainter(
                    tokens: tokens,
                    store: _store,
                    patternLengthTicks: patternLength,
                    rowHeight: _rowHeight,
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _NotesPainter(
                    tokens: tokens,
                    store: _store,
                    rowHeight: _rowHeight,
                  ),
                ),
              ),
              // Its own layer: the playhead moves every frame and must not drag
              // the note layer's repaint along with it.
              RepaintBoundary(
                child: CustomPaint(
                  painter: _PlayheadPainter(
                    tokens: tokens,
                    store: _store,
                    positionTicks: widget.positionTicks,
                    patternLengthTicks: patternLength,
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

  bool get _snapOff =>
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isControlPressed;

  int _maybeSnap(int tick) => _snapOff ? tick : _store.snapDown(tick);

  void _onTapDown(TapDownDetails details) {
    FocusPolicy.takeUnlessTyping(_focus);
    final int tick = _tickAt(details.localPosition.dx);
    final int key = _keyAt(details.localPosition.dy);
    final SequenceNote? hit = _store.noteAt(tick, key);

    if (hit != null) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _store.toggleSelection(hit);
      } else {
        _store.selectOnly(hit);
        _store.audition(key);
      }
      return;
    }
    if (_store.tool == PianoTool.draw) {
      _store.addNoteAt(_maybeSnap(tick), key);
      _store.audition(key);
    } else {
      _store.clearSelection();
    }
  }

  /// Right-click deletes — but only as an accelerator. Every action it offers
  /// is also on the toolbar, which is what FR-UX-17 actually requires: not the
  /// absence of right-click, the absence of right-click-*only*.
  void _onSecondaryTapDown(TapDownDetails details) {
    final SequenceNote? hit = _store.noteAt(
      _tickAt(details.localPosition.dx),
      _keyAt(details.localPosition.dy),
    );
    if (hit != null) _store.deleteNote(hit);
  }

  void _onPanStart(DragStartDetails details) {
    FocusPolicy.takeUnlessTyping(_focus);
    final int tick = _tickAt(details.localPosition.dx);
    final int key = _keyAt(details.localPosition.dy);
    _dragOriginTick = tick;
    _dragOriginKey = key;

    final SequenceNote? hit = _store.noteAt(tick, key);
    if (hit == null) {
      if (_store.tool == PianoTool.draw) {
        _store.addNoteAt(_maybeSnap(tick), key);
        _store.beginResize();
      } else {
        _store.beginMarquee(tick, key);
      }
      return;
    }

    if (!_store.selection.contains(hit)) _store.selectOnly(hit);

    // The last few pixels of a note are its resize handle; anywhere else moves.
    final double noteEndX = _xOfTick(hit.endTicks);
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    if ((noteEndX - details.localPosition.dx).abs() <=
        tokens.size.pianoResizeHandleWidth) {
      _store.beginResize();
    } else {
      _store.beginMove();
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final int tick = _tickAt(details.localPosition.dx);
    final int key = _keyAt(details.localPosition.dy);

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

  /// Trackpad and mouse navigation (§4). ⌘ zooms, ⇧ swaps the scroll axis, and
  /// plain scrolling pans — the grammar the arrangement uses too.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isMetaPressed) {
      _store.zoomHorizontally(event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
      return;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _store.panTo(
        _store.scrollTicks + event.scrollDelta.dy / _store.pixelsPerTick,
        _store.topKey,
      );
      return;
    }
    _store.panTo(
      _store.scrollTicks + event.scrollDelta.dx / _store.pixelsPerTick,
      _store.topKey - (event.scrollDelta.dy / _rowHeight).round(),
    );
  }

  // ----- keyboard -----------------------------------------------------------

  /// Registry-derived: the binding and the tooltip come from one declaration,
  /// so a shortcut cannot promise something it does not do.
  Map<ShortcutActivator, Intent> get _shortcuts => <ShortcutActivator, Intent>{
    ...shortcutsForArea(ActionArea.pianoRoll),
    // Navigation is not a registry action — it has no button, because a
    // toolbar button for "nudge left" would be noise. These stay local.
    const SingleActivator(LogicalKeyboardKey.arrowUp): const _NudgeKeyIntent(1),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const _NudgeKeyIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const _NudgeTimeIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const _NudgeTimeIntent(1),
    const SingleActivator(LogicalKeyboardKey.delete): const RunActionIntent(
      'piano.delete',
    ),
    const SingleActivator(LogicalKeyboardKey.escape): const CancelIntent(),
  };

  /// One entry per registry id the roll owns. The reachability test guarantees
  /// each of these also has a visible control.
  Map<String, VoidCallback> get _handlers => <String, VoidCallback>{
    'piano.tool.draw': () => _store.setTool(PianoTool.draw),
    'piano.tool.select': () => _store.setTool(PianoTool.select),
    'piano.quantise': _store.quantiseSelection,
    'piano.duplicate': _store.duplicateSelection,
    'piano.delete': _store.deleteSelection,
    'piano.selectAll': _store.selectAll,
    'piano.transposeUp': () => _store.transposeSelection(12),
    'piano.transposeDown': () => _store.transposeSelection(-12),
    'piano.zoomToSelection': _zoomToSelection,
  };

  void _zoomToSelection() =>
      _store.zoomToSelection(viewportWidth: _canvasSize.width);

  Map<Type, Action<Intent>> get _navigationActions => <Type, Action<Intent>>{
    CancelIntent: CallbackAction<CancelIntent>(
      onInvoke: (_) {
        // Escape unwinds one layer at a time: an in-flight drag first, then
        // the selection. Never both at once, so it is always clear what it did.
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
  };
}

class _NudgeKeyIntent extends Intent {
  const _NudgeKeyIntent(this.semitones);
  final int semitones;
}

class _NudgeTimeIntent extends Intent {
  const _NudgeTimeIntent(this.direction);
  final int direction;
}

/// The toolbar. Everything the roll can do is here as a visible control, which
/// is what makes FR-UX-17 a test rather than a walkthrough — each control
/// carries `actionKey(...)` from the registry.
class _PianoToolbar extends StatelessWidget {
  const _PianoToolbar({
    required this.store,
    required this.patterns,
    required this.onZoomToSelection,
  });

  final PianoRollStore store;
  final PatternStore patterns;
  final VoidCallback onZoomToSelection;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool hasSelection = store.hasSelection;
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
            Text(
              patterns.current?.name ?? 'Piano roll',
              style: tokens.type.title,
            ),
            SizedBox(width: tokens.spacing.lg),
            _ToolbarAction(
              id: 'piano.tool.draw',
              active: store.tool == PianoTool.draw,
              onPressed: () => store.setTool(PianoTool.draw),
            ),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(
              id: 'piano.tool.select',
              active: store.tool == PianoTool.select,
              onPressed: () => store.setTool(PianoTool.select),
            ),
            SizedBox(width: tokens.spacing.lg),
            OneBeatSelect<GridChoice>(
              key: actionKey('piano.grid'),
              prefix: 'GRID',
              value: store.grid,
              options: GridChoice.all,
              labelOf: (GridChoice choice) => choice.label,
              onChanged: store.setGrid,
            ),
            SizedBox(width: tokens.spacing.sm),
            OneBeatSelect<MusicalScale>(
              key: actionKey('piano.scale'),
              prefix: 'SCALE',
              value: store.scale,
              options: MusicalScale.all,
              labelOf: (MusicalScale scale) => scale.name,
              onChanged: (MusicalScale scale) =>
                  store.setScale(scale, store.scaleRoot),
            ),
            SizedBox(width: tokens.spacing.xs),
            OneBeatSelect<int>(
              value: store.scaleRoot,
              options: List<int>.generate(12, (int index) => index),
              labelOf: (int root) => pitchClassNames[root],
              onChanged: (int root) => store.setScale(store.scale, root),
            ),
            SizedBox(width: tokens.spacing.lg),
            _ToolbarAction(
              id: 'piano.quantise',
              onPressed: hasSelection ? store.quantiseSelection : null,
            ),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(
              id: 'piano.duplicate',
              onPressed: hasSelection ? store.duplicateSelection : null,
            ),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(
              id: 'piano.delete',
              onPressed: hasSelection ? store.deleteSelection : null,
            ),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(id: 'piano.selectAll', onPressed: store.selectAll),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(
              id: 'piano.transposeUp',
              onPressed: hasSelection
                  ? () => store.transposeSelection(12)
                  : null,
            ),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(
              id: 'piano.transposeDown',
              onPressed: hasSelection
                  ? () => store.transposeSelection(-12)
                  : null,
            ),
            SizedBox(width: tokens.spacing.xs),
            _ToolbarAction(
              id: 'piano.zoomToSelection',
              onPressed: hasSelection ? onZoomToSelection : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A toolbar button wired to a registry entry: the label, the tooltip and the
/// FR-UX-17 key all come from the one declaration.
class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.id,
    required this.onPressed,
    this.active = false,
  });

  final String id;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final UiAction action = ActionRegistry.byId(id);
    return OneBeatButton(
      key: actionKey(id),
      label: action.label,
      semanticLabel: action.tooltip,
      active: active,
      onPressed: onPressed,
    );
  }
}

class _EmptyRoll extends StatelessWidget {
  const _EmptyRoll({required this.tokens});

  final OneBeatTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
    color: tokens.color.surfaceDeep,
    alignment: Alignment.center,
    child: SizedBox(
      width: tokens.size.proseWidth,
      child: Text(
        'Select an instrument in the channel rack to edit its notes here.',
        textAlign: TextAlign.center,
        style: tokens.type.body.copyWith(color: tokens.color.textMuted),
      ),
    ),
  );
}

/// The drawn keyboard. Clicking a key auditions it through the engine's preview
/// path, which is how a user finds the note they want before placing it.
class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.store, required this.onAudition});

  final PianoRollStore store;
  final ValueChanged<int> onAudition;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double rowHeight = tokens.size.pianoRowHeight * store.verticalZoom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (TapDownDetails details) {
        final int key =
            (store.topKey - (details.localPosition.dy / rowHeight).floor())
                .clamp(0, 127);
        onAudition(key);
      },
      child: CustomPaint(
        painter: _KeyboardPainter(
          tokens: tokens,
          store: store,
          rowHeight: rowHeight,
        ),
      ),
    );
  }
}

/// The velocity strip (§2). Editing here applies to the selection, so a
/// multi-note velocity change is one gesture and one undo entry.
class _VelocityStrip extends StatelessWidget {
  const _VelocityStrip({required this.store});

  final PianoRollStore store;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      key: actionKey('piano.velocity'),
      height: tokens.size.pianoVelocityStripHeight,
      decoration: BoxDecoration(
        color: tokens.color.surfacePanel,
        border: Border(
          top: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: tokens.size.pianoKeyboardWidth,
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('VELOCITY', style: tokens.type.label),
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    store.hasSelection
                        ? '${store.selection.length} sel.'
                        : 'none',
                    style: tokens.type.numericSmall,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails details) =>
                  _setFromHeight(context, details.localPosition.dy),
              onVerticalDragUpdate: (DragUpdateDetails details) =>
                  _setFromHeight(context, details.localPosition.dy),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _VelocityPainter(tokens: tokens, store: store),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setFromHeight(BuildContext context, double y) {
    if (!store.hasSelection) return;
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final double height = tokens.size.pianoVelocityStripHeight;
    final double fraction = (1 - (y / height)).clamp(0.0, 1.0);
    store.setSelectionVelocity((fraction * 16383).round().clamp(1, 16383));
  }
}

// ---------------------------------------------------------------------------
// Painters. Every Paint is a field, built once: `paint()` allocates nothing.
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.tokens,
    required this.store,
    required this.patternLengthTicks,
    required this.rowHeight,
  }) : _background = Paint()..color = tokens.color.rollCanvas,
       _rowShade = Paint()..color = tokens.color.rowShade,
       _rowInScale = Paint()..color = tokens.color.rowShadeInScale,
       _beatLine = Paint()
         ..color = tokens.color.gridLine
         ..strokeWidth = tokens.border.hairline,
       _barLine = Paint()
         ..color = tokens.color.gridLineStrong
         ..strokeWidth = tokens.border.hairline,
       _beyond = Paint()..color = tokens.color.canvasScrim;

  final OneBeatTokens tokens;
  final PianoRollStore store;
  final int patternLengthTicks;
  final double rowHeight;

  final Paint _background;
  final Paint _rowShade;
  final Paint _rowInScale;
  final Paint _beatLine;
  final Paint _barLine;
  final Paint _beyond;

  @override
  void paint(Canvas canvas, Size size) {
    // Fill first. Row shading is applied *on top* of the canvas colour and only
    // to some rows, so without this the rows that take no shade would be
    // transparent rather than the deep surface.
    canvas.drawRect(Offset.zero & size, _background);

    final int topKey = store.topKey;
    final int rows = (size.height / rowHeight).ceil() + 1;

    // Pitch rows: accidentals darker, in-scale rows lifted (§1).
    for (int row = 0; row < rows; row++) {
      final int key = topKey - row;
      if (key < 0) break;
      final double y = row * rowHeight;
      final bool inScale = store.scale.contains(key, store.scaleRoot);
      if (isAccidental(key)) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, rowHeight), _rowShade);
      } else if (inScale && store.scale.intervals.length < 12) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, rowHeight),
          _rowInScale,
        );
      }
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _beatLine);
    }

    // Vertical grid. Stepping in ticks from the first visible line keeps the
    // loop bounded by what is on screen, not by the pattern's length.
    final int step = store.snapTicks > 0 ? store.snapTicks : ticksPerQuarter;
    final int firstTick = (store.scrollTicks ~/ step) * step;
    final double lastTick = store.scrollTicks + size.width / store.pixelsPerTick;
    for (int tick = firstTick; tick <= lastTick; tick += step) {
      final double x = (tick - store.scrollTicks) * store.pixelsPerTick;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        tick % ticksPerBar == 0 ? _barLine : _beatLine,
      );
    }

    // Everything past the pattern's end is dimmed rather than hidden: the user
    // can see where the pattern stops without the canvas simply ending.
    final double endX =
        (patternLengthTicks - store.scrollTicks) * store.pixelsPerTick;
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(
          math.max(0, endX),
          0,
          size.width - math.max(0, endX),
          size.height,
        ),
        _beyond,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.rowHeight != rowHeight ||
      old.store.topKey != store.topKey ||
      old.store.scrollTicks != store.scrollTicks ||
      old.store.pixelsPerTick != store.pixelsPerTick ||
      old.store.snapTicks != store.snapTicks ||
      old.store.scale != store.scale ||
      old.store.scaleRoot != store.scaleRoot ||
      old.patternLengthTicks != patternLengthTicks;
}

class _NotesPainter extends CustomPainter {
  _NotesPainter({
    required this.tokens,
    required this.store,
    required this.rowHeight,
  }) : _ghost = Paint()..color = tokens.color.noteGhost,
       _selected = Paint()..color = tokens.color.noteSelected,
       _marqueeFill = Paint()..color = tokens.color.marqueeFill,
       _marqueeStroke = Paint()
         ..color = tokens.color.accent
         ..style = PaintingStyle.stroke
         ..strokeWidth = tokens.border.hairline,
       // One reusable Paint whose colour is set per note. Velocity shading is
       // the only per-note variation, so a fresh Paint per note would be pure
       // allocation on the paint path.
       _note = Paint();

  final OneBeatTokens tokens;
  final PianoRollStore store;
  final double rowHeight;

  final Paint _ghost;
  final Paint _selected;
  final Paint _marqueeFill;
  final Paint _marqueeStroke;
  final Paint _note;

  Rect _rectOf(SequenceNote note, Size size) {
    final double x = (note.startTicks - store.scrollTicks) * store.pixelsPerTick;
    final double width = math.max(
      2,
      note.lengthTicks * store.pixelsPerTick - tokens.size.pianoNoteInset,
    );
    final double y = (store.topKey - note.key) * rowHeight;
    return Rect.fromLTWH(
      x,
      y + tokens.size.pianoNoteInset,
      width,
      rowHeight - tokens.size.pianoNoteInset * 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Radius radius = Radius.circular(tokens.size.pianoNoteRadius);

    for (final SequenceNote note in store.ghostNotes) {
      final Rect rect = _rectOf(note, size);
      if (rect.right < 0 || rect.left > size.width) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), _ghost);
    }

    for (final SequenceNote note in store.notes) {
      final Rect rect = _rectOf(note, size);
      if (rect.right < 0 || rect.left > size.width) continue;
      if (rect.bottom < 0 || rect.top > size.height) continue;

      if (store.selection.contains(note)) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), _selected);
        continue;
      }
      // Velocity reads as opacity: a quiet note is a faint note, which is the
      // convention every DAW shares and needs no legend.
      final double unit = (note.velocity / 16383).clamp(0.0, 1.0);
      _note.color = tokens.color.noteAtVelocity(unit);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), _note);
    }

    final MarqueeSelection? marquee = store.marquee;
    if (marquee != null) {
      final Rect rect = Rect.fromLTRB(
        (marquee.lowTick - store.scrollTicks) * store.pixelsPerTick,
        (store.topKey - marquee.highKey) * rowHeight,
        (marquee.highTick - store.scrollTicks) * store.pixelsPerTick,
        (store.topKey - marquee.lowKey + 1) * rowHeight,
      );
      canvas
        ..drawRect(rect, _marqueeFill)
        ..drawRect(rect, _marqueeStroke);
    }
  }

  @override
  bool shouldRepaint(_NotesPainter old) => true;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.tokens,
    required this.store,
    required this.positionTicks,
    required this.patternLengthTicks,
  }) : _line = Paint()
         ..color = tokens.color.playhead
         ..strokeWidth = tokens.size.playheadWidth;

  final OneBeatTokens tokens;
  final PianoRollStore store;
  final double positionTicks;
  final int patternLengthTicks;

  final Paint _line;

  @override
  void paint(Canvas canvas, Size size) {
    // The transport runs the arrangement; the roll shows where inside the
    // pattern that lands, which is what makes the cursor meaningful while a
    // looped clip plays.
    final double wrapped = patternLengthTicks > 0
        ? positionTicks % patternLengthTicks
        : positionTicks;
    final double x = (wrapped - store.scrollTicks) * store.pixelsPerTick;
    if (x < 0 || x > size.width) return;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), _line);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.positionTicks != positionTicks ||
      old.store.scrollTicks != store.scrollTicks ||
      old.store.pixelsPerTick != store.pixelsPerTick;
}

class _KeyboardPainter extends CustomPainter {
  _KeyboardPainter({
    required this.tokens,
    required this.store,
    required this.rowHeight,
  }) : _white = Paint()..color = tokens.color.textPrimary,
       _black = Paint()..color = tokens.color.surfaceDeep,
       _edge = Paint()
         ..color = tokens.color.line
         ..strokeWidth = tokens.border.hairline,
       _background = Paint()..color = tokens.color.surfacePanel;

  final OneBeatTokens tokens;
  final PianoRollStore store;
  final double rowHeight;

  final Paint _white;
  final Paint _black;
  final Paint _edge;
  final Paint _background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _background);
    final int rows = (size.height / rowHeight).ceil() + 1;

    for (int row = 0; row < rows; row++) {
      final int key = store.topKey - row;
      if (key < 0) break;
      final double y = row * rowHeight;
      final Rect rect = Rect.fromLTWH(0, y, size.width, rowHeight);
      canvas
        ..drawRect(rect, isAccidental(key) ? _black : _white)
        ..drawLine(Offset(0, y), Offset(size.width, y), _edge);

      // Octave labels only: a label on all 128 rows is noise, and C is the
      // landmark players actually navigate by.
      if (key % 12 == 0) {
        final TextPainter label = TextPainter(
          text: TextSpan(
            text: keyName(key),
            style: tokens.type.numericSmall.copyWith(
              color: tokens.color.surfaceDeep,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(
            size.width - label.width - tokens.spacing.xs,
            y + (rowHeight - label.height) / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) =>
      old.rowHeight != rowHeight || old.store.topKey != store.topKey;
}

class _VelocityPainter extends CustomPainter {
  _VelocityPainter({required this.tokens, required this.store})
    : _stem = Paint()..color = tokens.color.noteFill,
      _stemSelected = Paint()..color = tokens.color.noteSelected,
      _baseline = Paint()
        ..color = tokens.color.line
        ..strokeWidth = tokens.border.hairline;

  final OneBeatTokens tokens;
  final PianoRollStore store;

  final Paint _stem;
  final Paint _stemSelected;
  final Paint _baseline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      _baseline,
    );
    final double width = math.max(2, 3 * store.horizontalZoom);
    for (final SequenceNote note in store.notes) {
      final double x =
          (note.startTicks - store.scrollTicks) * store.pixelsPerTick;
      if (x < 0 || x > size.width) continue;
      final double unit = (note.velocity / 16383).clamp(0.0, 1.0);
      final double height = unit * size.height;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - height, width, height),
        store.selection.contains(note) ? _stemSelected : _stem,
      );
    }
  }

  @override
  bool shouldRepaint(_VelocityPainter old) => true;
}
