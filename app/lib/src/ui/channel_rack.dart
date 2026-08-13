import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'plugin_library_store.dart';
import 'rack_store.dart';

class ChannelRack extends StatefulWidget {
  const ChannelRack({
    required this.controller,
    required this.onBrowsePlugins,
    super.key,
  });

  final EngineController controller;
  final VoidCallback onBrowsePlugins;

  @override
  State<ChannelRack> createState() => _ChannelRackState();
}

class _ChannelRackState extends State<ChannelRack> {
  late final Listenable _changes;
  bool _showAdd = false;
  String? _confirmDelete;

  EngineController get controller => widget.controller;
  RackStore get rack => controller.rack;
  PluginLibraryStore get library => controller.library;

  @override
  void initState() {
    super.initState();
    _changes = Listenable.merge(<Listenable>[rack, library]);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return ColoredBox(
      color: t.color.surfaceDeep,
      child: AnimatedBuilder(
        animation: _changes,
        builder: (BuildContext context, Widget? child) {
          final RackPattern? pattern = rack.pattern;
          if (pattern == null) return const SizedBox.shrink();
          final List<RackRow> visibleRows =
              rack.rows.where(rack.isVisible).toList();
          final Map<String, ProjectInstrument> instruments =
              <String, ProjectInstrument>{
                for (final ProjectInstrument instrument in library.instruments)
                  instrument.id: instrument,
              };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _toolbar(t, pattern, instruments),
              Expanded(
                child:
                    library.instruments.isEmpty
                        ? _empty(t)
                        : _rackBody(t, pattern, visibleRows, instruments),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _toolbar(
    OneBeatTokens t,
    RackPattern pattern,
    Map<String, ProjectInstrument> instruments,
  ) {
    ProjectInstrument? selected;
    for (final ProjectInstrument instrument in instruments.values) {
      if (instrument.selected) selected = instrument;
    }
    final RackRow? velocityRow =
        rack.selectedVelocityInstrument == null
            ? null
            : rack.rowFor(rack.selectedVelocityInstrument!);
    final int? velocityStep = rack.selectedVelocityStep;
    final RackStep? velocity =
        velocityRow != null &&
                velocityStep != null &&
                velocityStep < velocityRow.steps.length
            ? velocityRow.steps[velocityStep]
            : null;

    return Container(
      height: t.size.rackToolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.surfacePanel,
        border: Border(bottom: BorderSide(color: t.color.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            Text('CHANNEL RACK', style: t.type.title),
            SizedBox(width: t.spacing.md),
            Text(pattern.name, style: t.type.body),
            SizedBox(width: t.spacing.lg),
            Text('STEPS', style: t.type.label),
            SizedBox(width: t.spacing.xs),
            for (final int length in <int>[16, 32, 64]) ...<Widget>[
              OneBeatButton(
                label: '$length',
                semanticLabel: 'Set pattern length to $length steps',
                active: pattern.baseStepCount == length,
                onPressed: () => rack.setLength(length),
              ),
              SizedBox(width: t.spacing.xs),
            ],
            SizedBox(width: t.spacing.sm),
            Text(
              'SWING ${(pattern.swing * 100).round()}%',
              style: t.type.numericSmall,
            ),
            SizedBox(width: t.spacing.xs),
            OneBeatButton(
              label: '−',
              semanticLabel: 'Decrease pattern swing',
              onPressed: () => rack.setSwing(pattern.swing - 0.05),
            ),
            SizedBox(width: t.spacing.xs),
            OneBeatButton(
              label: '+',
              semanticLabel: 'Increase pattern swing',
              onPressed: () => rack.setSwing(pattern.swing + 0.05),
            ),
            SizedBox(width: t.spacing.md),
            OneBeatButton(
              label: rack.showAll ? 'ALL ON' : 'SHOW ALL',
              semanticLabel: 'Show all project instruments in this pattern',
              active: rack.showAll,
              onPressed: () => rack.setShowAll(value: !rack.showAll),
            ),
            SizedBox(width: t.spacing.xl),
            if (velocity != null && velocityStep != null) ...<Widget>[
              Text(
                'VELOCITY ${velocityStep + 1} · ${(velocity.velocity / 16383 * 100).round()}%',
                style: t.type.numericSmall,
              ),
              SizedBox(width: t.spacing.xs),
              OneBeatButton(
                label: '−',
                semanticLabel: 'Decrease selected step velocity',
                onPressed: () => rack.nudgeVelocity(-1024),
              ),
              SizedBox(width: t.spacing.xs),
              OneBeatButton(
                label: '+',
                semanticLabel: 'Increase selected step velocity',
                onPressed: () => rack.nudgeVelocity(1024),
              ),
              SizedBox(width: t.spacing.md),
            ],
            if (selected != null) ...<Widget>[
              OneBeatButton(
                label: '↑',
                semanticLabel: 'Move ${selected.name} up',
                onPressed:
                    selected.order > 0
                        ? () {
                          library.moveInstrument(selected!, selected.order - 1);
                          rack.refresh();
                        }
                        : null,
              ),
              SizedBox(width: t.spacing.xs),
              OneBeatButton(
                label: '↓',
                semanticLabel: 'Move ${selected.name} down',
                onPressed:
                    selected.order + 1 < instruments.length
                        ? () {
                          library.moveInstrument(selected!, selected.order + 1);
                          rack.refresh();
                        }
                        : null,
              ),
              SizedBox(width: t.spacing.xs),
              OneBeatButton(
                label: 'DUP',
                semanticLabel: 'Duplicate ${selected.name}',
                onPressed: () {
                  library.duplicateInstrument(selected!);
                  rack.refresh();
                },
              ),
              SizedBox(width: t.spacing.xs),
              OneBeatButton(
                label: _confirmDelete == selected.id ? 'DELETE?' : 'DELETE',
                semanticLabel:
                    _confirmDelete == selected.id
                        ? 'Confirm delete ${selected.name}; removes ${selected.affectedNotes} notes from ${selected.affectedPatterns} patterns'
                        : 'Delete instrument ${selected.name}',
                active: _confirmDelete == selected.id,
                onPressed: () {
                  if (_confirmDelete == selected!.id) {
                    library.deleteInstrument(selected);
                    rack.refresh();
                    setState(() => _confirmDelete = null);
                  } else {
                    setState(() => _confirmDelete = selected!.id);
                  }
                },
              ),
              SizedBox(width: t.spacing.md),
            ],
            OneBeatButton(
              label: 'UNDO',
              semanticLabel:
                  rack.canUndo
                      ? 'Undo ${rack.undoName}, command Z'
                      : 'Nothing to undo',
              onPressed: rack.canUndo ? controller.undoProject : null,
            ),
            SizedBox(width: t.spacing.xs),
            OneBeatButton(
              label: 'REDO',
              semanticLabel:
                  rack.canRedo
                      ? 'Redo ${rack.redoName}, shift command Z'
                      : 'Nothing to redo',
              onPressed: rack.canRedo ? controller.redoProject : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(OneBeatTokens t) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('No instruments in this project', style: t.type.title),
        SizedBox(height: t.spacing.sm),
        Text(
          'Add the stock piano or another plug-in to start this pattern.',
          style: t.type.body.copyWith(color: t.color.textMuted),
        ),
        SizedBox(height: t.spacing.lg),
        OneBeatButton(
          label: '+ ADD INSTRUMENT',
          semanticLabel: 'Open the plug-in browser to add an instrument',
          onPressed: widget.onBrowsePlugins,
        ),
      ],
    ),
  );

  Widget _rackBody(
    OneBeatTokens t,
    RackPattern pattern,
    List<RackRow> rows,
    Map<String, ProjectInstrument> instruments,
  ) {
    final double canvasWidth = math.max(
      pattern.baseStepCount * t.size.rackStepWidth,
      t.size.proseWidth,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: math.max(
                t.size.rackRowHeight,
                rows.length * t.size.rackRowHeight,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: t.size.rackHeaderWidth,
                    child: Column(
                      children: <Widget>[
                        for (final RackRow row in rows)
                          SizedBox(
                            height: t.size.rackRowHeight,
                            child:
                                instruments[row.instrumentId] == null
                                    ? const SizedBox.shrink()
                                    : _RackHeader(
                                      instrument:
                                          instruments[row.instrumentId]!,
                                      row: row,
                                      library: library,
                                      rack: rack,
                                    ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: canvasWidth,
                        height: rows.length * t.size.rackRowHeight,
                        child: Listener(
                          onPointerDown:
                              (PointerDownEvent event) =>
                                  _pointerDown(event, rows, canvasWidth, t),
                          onPointerMove:
                              (PointerMoveEvent event) =>
                                  _pointerMove(event, rows, canvasWidth, t),
                          onPointerUp: (_) => _pointerUp(),
                          onPointerCancel: (_) => _pointerCancel(),
                          child: RepaintBoundary(
                            child: RackStepGrid(
                              rows: rows,
                              pattern: pattern,
                              positionBeats: controller.snapshot.positionBeats,
                              playing: controller.snapshot.playing,
                              repaint: controller,
                              positionBeatsProvider:
                                  () => controller.snapshot.positionBeats,
                              playingProvider:
                                  () => controller.snapshot.playing,
                              selectedInstrument:
                                  rack.selectedVelocityInstrument,
                              selectedStep: rack.selectedVelocityStep,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _addRow(t, rows, instruments),
      ],
    );
  }

  Widget _addRow(
    OneBeatTokens t,
    List<RackRow> visibleRows,
    Map<String, ProjectInstrument> instruments,
  ) {
    final Set<String> visible =
        visibleRows.map((RackRow row) => row.instrumentId).toSet();
    final List<ProjectInstrument> available =
        instruments.values
            .where((ProjectInstrument value) => !visible.contains(value.id))
            .toList();
    return Container(
      padding: EdgeInsets.all(t.spacing.sm),
      decoration: BoxDecoration(
        color: t.color.surfacePanel,
        border: Border(top: BorderSide(color: t.color.line)),
      ),
      child: Wrap(
        spacing: t.spacing.xs,
        runSpacing: t.spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          OneBeatButton(
            label: '+ ADD INSTRUMENT',
            semanticLabel: 'Add an instrument row to this pattern',
            active: _showAdd,
            onPressed: () => setState(() => _showAdd = !_showAdd),
          ),
          if (_showAdd)
            for (final ProjectInstrument instrument in available)
              OneBeatButton(
                label: instrument.name.toUpperCase(),
                semanticLabel: 'Show ${instrument.name} in this pattern',
                onPressed: () {
                  rack.includeInstrument(instrument.id);
                  setState(() => _showAdd = false);
                },
              ),
          if (_showAdd)
            OneBeatButton(
              label: 'NEW PLUGIN…',
              semanticLabel: 'Open the plug-in browser for a new instrument',
              onPressed: widget.onBrowsePlugins,
            ),
          if (rowsHaveOffGrid(visibleRows))
            Text(
              '• OFF-GRID NOTES STAY IN THE PIANO ROLL',
              style: t.type.label.copyWith(color: t.color.warning),
            ),
        ],
      ),
    );
  }

  bool rowsHaveOffGrid(List<RackRow> rows) =>
      rows.any((RackRow row) => row.offGridCount > 0);

  ({RackRow row, int step, double rowY})? _hit(
    Offset position,
    List<RackRow> rows,
    double width,
    OneBeatTokens t,
  ) {
    final int rowIndex = (position.dy / t.size.rackRowHeight).floor();
    if (rowIndex < 0 || rowIndex >= rows.length) return null;
    final RackRow row = rows[rowIndex];
    final double stepWidth = width / row.steps.length;
    final int step = (position.dx / stepWidth).floor();
    if (step < 0 || step >= row.steps.length) return null;
    return (row: row, step: step, rowY: position.dy % t.size.rackRowHeight);
  }

  void _pointerDown(
    PointerDownEvent event,
    List<RackRow> rows,
    double width,
    OneBeatTokens t,
  ) {
    final hit = _hit(event.localPosition, rows, width, t);
    if (hit == null) return;
    final bool velocity =
        event.buttons == kSecondaryMouseButton ||
        HardwareKeyboard.instance.isAltPressed;
    if (velocity) {
      rack.beginVelocityPaint();
      _setVelocityFromPointer(hit, t);
      return;
    }
    rack.beginPaint(
      hit.row.instrumentId,
      hit.step,
      active: !hit.row.steps[hit.step].active,
    );
  }

  void _pointerMove(
    PointerMoveEvent event,
    List<RackRow> rows,
    double width,
    OneBeatTokens t,
  ) {
    final hit = _hit(event.localPosition, rows, width, t);
    if (hit == null) return;
    if (event.buttons == kSecondaryMouseButton ||
        HardwareKeyboard.instance.isAltPressed) {
      _setVelocityFromPointer(hit, t);
    } else {
      rack.paintStep(hit.row.instrumentId, hit.step);
    }
  }

  void _setVelocityFromPointer(
    ({RackRow row, int step, double rowY}) hit,
    OneBeatTokens t,
  ) {
    final double unit = 1 - (hit.rowY / t.size.rackRowHeight).clamp(0.0, 1.0);
    rack.setVelocity(
      hit.row.instrumentId,
      hit.step,
      math.max(1, (unit * 16383).round()),
    );
  }

  void _pointerUp() {
    rack.commitPaint();
    rack.commitVelocityPaint();
  }

  void _pointerCancel() {
    rack.abortPaint();
    rack.abortVelocityPaint();
  }
}

class _RackHeader extends StatelessWidget {
  const _RackHeader({
    required this.instrument,
    required this.row,
    required this.library,
    required this.rack,
  });

  final ProjectInstrument instrument;
  final RackRow row;
  final PluginLibraryStore library;
  final RackStore rack;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return GestureDetector(
      onTap: () => library.selectInstrument(instrument),
      child: Container(
        height: t.size.rackRowHeight,
        padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
        decoration: BoxDecoration(
          color:
              instrument.selected
                  ? t.color.surfaceRaised
                  : t.color.surfacePanel,
          border: Border(
            bottom: BorderSide(color: t.color.line),
            left: BorderSide(
              color: instrument.selected ? t.color.accent : t.color.line,
              width:
                  instrument.selected ? t.border.emphasis : t.border.hairline,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: () {
                final int current = instrumentPalette.indexOf(instrument.color);
                library.recolorInstrument(
                  instrument,
                  instrumentPalette[(current + 1) % instrumentPalette.length],
                );
              },
              child: Semantics(
                button: true,
                label: 'Change ${instrument.name} colour',
                child: Container(
                  width: t.size.iconSize,
                  height: t.size.iconSize,
                  decoration: BoxDecoration(
                    color: projectColor(instrument.color, t.color.accent),
                    borderRadius: t.radius.controlBorder,
                  ),
                ),
              ),
            ),
            SizedBox(width: t.spacing.sm),
            Expanded(
              child: _InstrumentNameField(
                instrument: instrument,
                library: library,
              ),
            ),
            if (row.offGridCount > 0)
              Text(
                '${row.offGridCount} OFF',
                style: t.type.numericSmall.copyWith(color: t.color.warning),
              ),
            SizedBox(width: t.spacing.xs),
            _PreviewButton(library: library),
            SizedBox(width: t.spacing.xs),
            OneBeatButton(
              label: instrument.muted ? 'M' : 'M',
              semanticLabel:
                  '${instrument.muted ? 'Unmute' : 'Mute'} ${instrument.name}',
              active: instrument.muted,
              onPressed: () => library.toggleInstrumentMuted(instrument),
            ),
            SizedBox(width: t.spacing.xs),
            OneBeatButton(
              label: _gridLabel(row.gridTicks),
              semanticLabel: 'Change ${instrument.name} step resolution',
              onPressed:
                  () => rack.setGrid(instrument.id, _nextGrid(row.gridTicks)),
            ),
            SizedBox(width: t.spacing.xs),
            OneBeatButton(
              label: '− PAT',
              semanticLabel:
                  'Remove ${instrument.name} sequence from this pattern, keep instrument',
              onPressed:
                  row.hasSequence
                      ? () => rack.removeSequence(instrument.id)
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _gridLabel(int ticks) => switch (ticks) {
    120 => '1/32',
    480 => '1/8',
    _ => '1/16',
  };

  static int _nextGrid(int ticks) => switch (ticks) {
    240 => 120,
    120 => 480,
    _ => 240,
  };
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.library});
  final PluginLibraryStore library;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return Listener(
      onPointerDown: (_) => library.auditionNoteOn(60),
      onPointerUp: (_) => library.auditionNoteOff(60),
      onPointerCancel: (_) => library.auditionNoteOff(60),
      child: Semantics(
        button: true,
        label: 'Preview instrument',
        child: Container(
          height: t.size.controlHeight,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.color.surfaceRaised,
            border: Border.all(color: t.color.line),
            borderRadius: t.radius.controlBorder,
          ),
          child: Text('▶', style: t.type.label),
        ),
      ),
    );
  }
}

class _InstrumentNameField extends StatefulWidget {
  const _InstrumentNameField({required this.instrument, required this.library});

  final ProjectInstrument instrument;
  final PluginLibraryStore library;

  @override
  State<_InstrumentNameField> createState() => _InstrumentNameFieldState();
}

class _InstrumentNameFieldState extends State<_InstrumentNameField> {
  late final TextEditingController _name = TextEditingController(
    text: widget.instrument.name,
  );
  late final FocusNode _focus = FocusNode(debugLabel: 'rack instrument name');

  @override
  void didUpdateWidget(_InstrumentNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _name.text != widget.instrument.name) {
      _name.text = widget.instrument.name;
    }
  }

  void _commit() {
    final String value = _name.text.trim();
    if (value.isNotEmpty && value != widget.instrument.name) {
      widget.library.renameInstrument(widget.instrument, value);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return EditableText(
      controller: _name,
      focusNode: _focus,
      style: t.type.body,
      cursorColor: t.color.accent,
      backgroundCursorColor: t.color.line,
      selectionColor: t.color.accentMuted,
      maxLines: 1,
      onSubmitted: (_) => _commit(),
    );
  }
}

class RackStepGrid extends StatelessWidget {
  const RackStepGrid({
    required this.rows,
    required this.pattern,
    required this.positionBeats,
    required this.playing,
    this.selectedInstrument,
    this.selectedStep,
    this.repaint,
    this.positionBeatsProvider,
    this.playingProvider,
    super.key,
  });

  final List<RackRow> rows;
  final RackPattern pattern;
  final double positionBeats;
  final bool playing;
  final String? selectedInstrument;
  final int? selectedStep;
  final Listenable? repaint;
  final ValueGetter<double>? positionBeatsProvider;
  final ValueGetter<bool>? playingProvider;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RackPainter(
      rows: rows,
      pattern: pattern,
      positionBeats: positionBeats,
      playing: playing,
      selectedInstrument: selectedInstrument,
      selectedStep: selectedStep,
      tokens: OneBeatTheme.of(context),
      repaint: repaint,
      positionBeatsProvider: positionBeatsProvider,
      playingProvider: playingProvider,
    ),
  );
}

class _RackPainter extends CustomPainter {
  _RackPainter({
    required this.rows,
    required this.pattern,
    required this.positionBeats,
    required this.playing,
    required this.selectedInstrument,
    required this.selectedStep,
    required this.tokens,
    super.repaint,
    this.positionBeatsProvider,
    this.playingProvider,
  }) : _line = Paint()..color = tokens.color.line,
       _inactive = Paint()..color = tokens.color.surfacePanel,
       _beat = Paint()..color = tokens.color.surfaceRaised,
       _active = Paint()..color = tokens.color.accent,
       _velocity = Paint()..color = tokens.color.textPrimary,
       _cursor = Paint()..color = tokens.color.accent,
       _selected =
           (Paint()
             ..color = tokens.color.textPrimary
             ..style = PaintingStyle.stroke
             ..strokeWidth = tokens.border.emphasis);

  final List<RackRow> rows;
  final RackPattern pattern;
  final double positionBeats;
  final bool playing;
  final String? selectedInstrument;
  final int? selectedStep;
  final OneBeatTokens tokens;
  final ValueGetter<double>? positionBeatsProvider;
  final ValueGetter<bool>? playingProvider;
  final Paint _line;
  final Paint _inactive;
  final Paint _beat;
  final Paint _active;
  final Paint _velocity;
  final Paint _selected;
  final Paint _cursor;

  @override
  void paint(Canvas canvas, Size size) {
    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final RackRow row = rows[rowIndex];
      final double cellWidth = size.width / row.steps.length;
      final double top = rowIndex * tokens.size.rackRowHeight;
      for (int step = 0; step < row.steps.length; step++) {
        final Rect outer = Rect.fromLTWH(
          step * cellWidth,
          top,
          cellWidth,
          tokens.size.rackRowHeight,
        );
        canvas.drawRect(outer, _line);
        final Rect cell = outer.deflate(tokens.size.rackStepInset);
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell, tokens.radius.sm),
          row.steps[step].active
              ? _active
              : (step % 4 == 0 ? _beat : _inactive),
        );
        if (row.steps[step].active) {
          final double unit = row.steps[step].velocity / 16383;
          canvas.drawRect(
            Rect.fromLTWH(
              cell.left,
              cell.bottom - tokens.size.rackVelocityHeight,
              cell.width * unit,
              tokens.size.rackVelocityHeight,
            ),
            _velocity,
          );
        }
        if (selectedInstrument == row.instrumentId && selectedStep == step) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(cell, tokens.radius.sm),
            _selected,
          );
        }
      }
    }

    final bool livePlaying = playingProvider?.call() ?? playing;
    if (livePlaying && pattern.lengthTicks > 0) {
      final double ticks =
          (positionBeatsProvider?.call() ?? positionBeats) * 960;
      final double loopTicks = ticks % pattern.lengthTicks;
      final double x = size.width * loopTicks / pattern.lengthTicks;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, tokens.size.rackCursorWidth, size.height),
        _cursor,
      );
    }
  }

  @override
  bool shouldRepaint(_RackPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.positionBeats != positionBeats ||
      oldDelegate.playing != playing ||
      oldDelegate.selectedInstrument != selectedInstrument ||
      oldDelegate.selectedStep != selectedStep;
}
