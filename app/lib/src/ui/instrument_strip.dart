import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'plugin_library_store.dart';

/// Project-global instrument headers. OB-3-09 adds step cells to the right;
/// these headers already own selection and lifecycle.
class InstrumentStrip extends StatelessWidget {
  const InstrumentStrip({required this.controller, super.key});

  final EngineController controller;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final PluginLibraryStore library = controller.library;
    return Container(
      width: t.size.instrumentStripWidth,
      decoration: BoxDecoration(
        color: t.color.surfacePanel,
        border: Border(right: BorderSide(color: t.color.line)),
      ),
      child: AnimatedBuilder(
        animation: library,
        builder:
            (BuildContext context, Widget? child) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.all(t.spacing.md),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text('INSTRUMENTS', style: t.type.label)),
                      if (library.canUndo)
                        OneBeatButton(
                          label: 'UNDO',
                          semanticLabel: 'Undo instrument edit',
                          onPressed: library.undo,
                        ),
                      if (library.canUndo && library.canRedo)
                        SizedBox(width: t.spacing.xs),
                      if (library.canRedo)
                        OneBeatButton(
                          label: 'REDO',
                          semanticLabel: 'Redo instrument edit',
                          onPressed: library.redo,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child:
                      library.instruments.isEmpty
                          ? Padding(
                            padding: EdgeInsets.all(t.spacing.lg),
                            child: Text(
                              'Add an instrument from the plug-in browser.',
                              style: t.type.body.copyWith(
                                color: t.color.textMuted,
                              ),
                            ),
                          )
                          : ListView.builder(
                            itemCount: library.instruments.length,
                            itemBuilder: (BuildContext context, int index) {
                              final ProjectInstrument instrument =
                                  library.instruments[index];
                              return KeyedSubtree(
                                key: ValueKey<String>(instrument.id),
                                child: _InstrumentRow(
                                  instrument: instrument,
                                  library: library,
                                  order: index,
                                  canMoveUp: index > 0,
                                  canMoveDown:
                                      index + 1 < library.instruments.length,
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
      ),
    );
  }
}

class _InstrumentRow extends StatefulWidget {
  const _InstrumentRow({
    required this.instrument,
    required this.library,
    required this.order,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final ProjectInstrument instrument;
  final PluginLibraryStore library;
  final int order;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  State<_InstrumentRow> createState() => _InstrumentRowState();
}

class _InstrumentRowState extends State<_InstrumentRow> {
  late final TextEditingController _name;
  late final FocusNode _focus;
  bool _confirmDelete = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.instrument.name);
    _focus = FocusNode(debugLabel: 'instrument name');
  }

  @override
  void didUpdateWidget(_InstrumentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _name.text != widget.instrument.name) {
      _name.text = widget.instrument.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commitName() {
    final String value = _name.text.trim();
    if (value.isNotEmpty && value != widget.instrument.name) {
      widget.library.renameInstrument(widget.instrument, value);
    }
  }

  void _cycleColor() {
    final int current = instrumentPalette.indexOf(widget.instrument.color);
    widget.library.recolorInstrument(
      widget.instrument,
      instrumentPalette[(current + 1) % instrumentPalette.length],
    );
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final ProjectInstrument instrument = widget.instrument;
    return GestureDetector(
      onTap: () => widget.library.selectInstrument(instrument),
      child: Container(
        padding: EdgeInsets.all(t.spacing.sm),
        decoration: BoxDecoration(
          color:
              instrument.selected
                  ? t.color.surfaceRaised
                  : t.color.surfacePanel,
          border: Border(
            top: BorderSide(color: t.color.line),
            left: BorderSide(
              color: instrument.selected ? t.color.accent : t.color.line,
              width:
                  instrument.selected ? t.border.emphasis : t.border.hairline,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                GestureDetector(
                  onTap: _cycleColor,
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
                  child: EditableText(
                    controller: _name,
                    focusNode: _focus,
                    style: t.type.body,
                    cursorColor: t.color.accent,
                    backgroundCursorColor: t.color.line,
                    selectionColor: t.color.accentMuted,
                    maxLines: 1,
                    onSubmitted: (_) => _commitName(),
                  ),
                ),
                Text(instrument.order.toString(), style: t.type.numericSmall),
                if (widget.canMoveUp)
                  OneBeatButton(
                    label: '↑',
                    semanticLabel: 'Move ${instrument.name} up',
                    onPressed:
                        () => widget.library.moveInstrument(
                          instrument,
                          widget.order - 1,
                        ),
                  ),
                if (widget.canMoveDown)
                  OneBeatButton(
                    label: '↓',
                    semanticLabel: 'Move ${instrument.name} down',
                    onPressed:
                        () => widget.library.moveInstrument(
                          instrument,
                          widget.order + 1,
                        ),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.xs),
            Text(
              '${instrument.pluginVendor.isEmpty ? 'OneBeat' : instrument.pluginVendor} · ${instrument.pluginName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.type.numericSmall,
            ),
            SizedBox(height: t.spacing.sm),
            if (_confirmDelete)
              _DeleteConfirmation(
                instrument: instrument,
                onCancel: () => setState(() => _confirmDelete = false),
                onConfirm: () => widget.library.deleteInstrument(instrument),
              )
            else
              Wrap(
                spacing: t.spacing.xs,
                runSpacing: t.spacing.xs,
                children: <Widget>[
                  _AuditionButton(library: widget.library),
                  OneBeatButton(
                    label: instrument.muted ? 'UNMUTE' : 'MUTE',
                    semanticLabel:
                        '${instrument.muted ? 'Unmute' : 'Mute'} ${instrument.name}',
                    active: instrument.muted,
                    onPressed:
                        () => widget.library.toggleInstrumentMuted(instrument),
                  ),
                  OneBeatButton(
                    label: 'DUPLICATE',
                    semanticLabel: 'Duplicate ${instrument.name}',
                    onPressed:
                        () => widget.library.duplicateInstrument(instrument),
                  ),
                  OneBeatButton(
                    label: 'DELETE',
                    semanticLabel: 'Delete ${instrument.name}',
                    onPressed: () => setState(() => _confirmDelete = true),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AuditionButton extends StatelessWidget {
  const _AuditionButton({required this.library});
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
        label: 'Audition instrument',
        child: Container(
          height: t.size.controlHeight,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.color.surfaceRaised,
            border: Border.all(color: t.color.line),
            borderRadius: t.radius.controlBorder,
          ),
          child: Text('PREVIEW', style: t.type.label),
        ),
      ),
    );
  }
}

class _DeleteConfirmation extends StatelessWidget {
  const _DeleteConfirmation({
    required this.instrument,
    required this.onCancel,
    required this.onConfirm,
  });

  final ProjectInstrument instrument;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Removes its notes from ${instrument.affectedPatterns} patterns; '
          '${instrument.affectedClips} clips use those patterns.',
          style: t.type.body.copyWith(color: t.color.warning),
        ),
        SizedBox(height: t.spacing.sm),
        Row(
          children: <Widget>[
            OneBeatButton(
              label: 'CANCEL',
              semanticLabel: 'Keep ${instrument.name}',
              onPressed: onCancel,
            ),
            SizedBox(width: t.spacing.sm),
            OneBeatButton(
              label: 'DELETE',
              semanticLabel: 'Confirm delete ${instrument.name}',
              onPressed: onConfirm,
            ),
          ],
        ),
      ],
    );
  }
}
