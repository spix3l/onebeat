// Stage 2 plug-in browser and generic editor, matched to the Pen reference
// frames onebeat-fail-plugin.html and onebeat-plugin-params.html.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../engine/engine_client.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'plugin_library_store.dart';

class PluginListDebugPanel extends StatefulWidget {
  const PluginListDebugPanel({required this.controller, super.key});
  final EngineController controller;
  @override
  State<PluginListDebugPanel> createState() => _PluginListPanelState();
}

class _PluginListPanelState extends State<PluginListDebugPanel> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'plugin search');
  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final PluginLibraryStore library = widget.controller.library;
    return AnimatedBuilder(
      animation: library,
      builder: (BuildContext context, Widget? child) {
        if (library.showParameters && library.instance != null) {
          return _ParameterEditor(
            library: library,
            instance: library.instance!,
          );
        }
        final String query = _search.text.toLowerCase();
        final List<PluginListing> available =
            library.availablePlugins
                .where(
                  (PluginListing item) =>
                      query.isEmpty ||
                      item.name.toLowerCase().contains(query) ||
                      item.vendor.toLowerCase().contains(query),
                )
                .toList();
        return Container(
          color: tokens.color.surfaceDeep,
          alignment: Alignment.topCenter,
          padding: EdgeInsets.all(tokens.spacing.xl),
          child: SizedBox(
            width: tokens.size.pluginBrowserWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('PLUGIN MANAGER', style: tokens.type.title),
                    const Spacer(),
                    if (library.quarantinedPlugins.isNotEmpty)
                      Text(
                        '${library.quarantinedPlugins.length} PROBLEMS',
                        style: tokens.type.label.copyWith(
                          color: tokens.color.danger,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: tokens.spacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        height: tokens.size.searchHeight,
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.spacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.color.surfacePanel,
                          border: Border.all(color: tokens.color.line),
                          borderRadius: tokens.radius.controlBorder,
                        ),
                        child: EditableText(
                          controller: _search,
                          focusNode: _searchFocus,
                          style: tokens.type.body,
                          cursorColor: tokens.color.accent,
                          backgroundCursorColor: tokens.color.textMuted,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    SizedBox(width: tokens.spacing.sm),
                    OneBeatButton(
                      label: library.status.isScanning ? 'STOP SCAN' : 'SCAN',
                      semanticLabel: 'Scan for CLAP plugins',
                      active: library.status.isScanning,
                      onPressed:
                          library.status.isScanning
                              ? library.cancelScan
                              : () {
                                library.startScan();
                              },
                    ),
                  ],
                ),
                SizedBox(height: tokens.spacing.sm),
                Text(library.summary, style: tokens.type.numericSmall),
                if (library.instance != null) ...<Widget>[
                  SizedBox(height: tokens.spacing.lg),
                  Text('LOADED INSTANCE', style: tokens.type.label),
                  SizedBox(height: tokens.spacing.sm),
                  _InstanceRow(library: library, instance: library.instance!),
                ],
                if (library.quarantinedPlugins.isNotEmpty) ...<Widget>[
                  SizedBox(height: tokens.spacing.xl),
                  Text('PROBLEMS', style: tokens.type.label),
                  SizedBox(height: tokens.spacing.sm),
                  for (final PluginListing item in library.quarantinedPlugins)
                    _ProblemRow(listing: item, library: library),
                ],
                SizedBox(height: tokens.spacing.xl),
                Text('AVAILABLE', style: tokens.type.label),
                SizedBox(height: tokens.spacing.sm),
                Expanded(
                  child:
                      available.isEmpty
                          ? _EmptyLibrary(scanning: library.status.isScanning)
                          : ListView(
                            children: <Widget>[
                              for (final PluginListing item in available)
                                _AvailableRow(
                                  listing: item,
                                  onAdd: () => library.add(item),
                                ),
                            ],
                          ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AvailableRow extends StatelessWidget {
  const _AvailableRow({required this.listing, required this.onAdd});
  final PluginListing listing;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return Container(
      height: t.size.pluginRowHeight,
      margin: EdgeInsets.only(bottom: t.spacing.xs),
      padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.surfacePanel,
        border: Border.all(color: t.color.line),
        borderRadius: t.radius.controlBorder,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(listing.name, style: t.type.body),
                Text(
                  '${listing.vendor.isEmpty ? 'Unknown vendor' : listing.vendor} · CLAP · '
                  '${listing.paramCount} parameters',
                  style: t.type.numericSmall,
                ),
              ],
            ),
          ),
          OneBeatButton(
            label: 'ADD',
            semanticLabel: 'Add ${listing.name}',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _InstanceRow extends StatelessWidget {
  const _InstanceRow({required this.library, required this.instance});
  final PluginLibraryStore library;
  final HostedInstance instance;
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final Color border =
        instance.needsRestart
            ? t.color.danger
            : instance.missing
            ? t.color.warning
            : t.color.accentMuted;
    return Container(
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.surfacePanel,
        border: Border.all(color: border),
        borderRadius: t.radius.controlBorder,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(instance.name, style: t.type.title),
                    if (instance.missing) ...<Widget>[
                      SizedBox(width: t.spacing.sm),
                      Text(
                        'MISSING',
                        style: t.type.label.copyWith(color: t.color.warning),
                      ),
                    ] else if (instance.needsRestart) ...<Widget>[
                      SizedBox(width: t.spacing.sm),
                      Text(
                        'STOPPED',
                        style: t.type.label.copyWith(color: t.color.danger),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: t.spacing.xs),
                Text(
                  instance.needsRestart
                      ? 'Plugin stopped responding or crashed\nAudio is silenced — restart restores the last saved state'
                      : instance.missing
                      ? 'Plugin not found on this machine\nSaved state is kept — reinstall or locate it to restore sound'
                      : '${instance.vendor} · CLAP · ${instance.paramCount} parameters',
                  style: t.type.body.copyWith(color: t.color.textMuted),
                ),
              ],
            ),
          ),
          if (instance.needsRestart)
            OneBeatButton(
              label: 'RESTART',
              semanticLabel: 'Restart ${instance.name}',
              onPressed: library.restartInstance,
            )
          else if (instance.missing)
            OneBeatButton(
              label: 'LOCATE',
              semanticLabel: 'Locate ${instance.name}',
              onPressed: () {},
            )
          else
            OneBeatButton(
              label: instance.hasEditor ? 'OPEN EDITOR' : 'PARAMETERS',
              semanticLabel: 'Open ${instance.name} editor',
              onPressed:
                  instance.hasEditor
                      ? library.openEditor
                      : library.openParameters,
            ),
          SizedBox(width: t.spacing.sm),
          OneBeatButton(
            label: 'REMOVE',
            semanticLabel: 'Remove ${instance.name}',
            onPressed: library.removeInstance,
          ),
        ],
      ),
    );
  }
}

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.listing, required this.library});
  final PluginListing listing;
  final PluginLibraryStore library;
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: t.spacing.sm),
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.surfacePanel,
        border: Border.all(color: t.color.danger),
        borderRadius: t.radius.controlBorder,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(listing.name, style: t.type.title),
                SizedBox(height: t.spacing.xs),
                Text(
                  _pluginProblemDetail(listing),
                  style: t.type.body.copyWith(color: t.color.textMuted),
                ),
              ],
            ),
          ),
          OneBeatButton(
            label: 'RESCAN ONCE',
            semanticLabel: 'Rescan ${listing.name}',
            onPressed: () => library.retry(listing),
          ),
          SizedBox(width: t.spacing.sm),
          OneBeatButton(
            label: 'REMOVE',
            semanticLabel: 'Hide ${listing.name}',
            onPressed: () => library.keepQuarantined(listing),
          ),
        ],
      ),
    );
  }
}

class _ParameterEditor extends StatefulWidget {
  const _ParameterEditor({required this.library, required this.instance});
  final PluginLibraryStore library;
  final HostedInstance instance;
  @override
  State<_ParameterEditor> createState() => _ParameterEditorState();
}

class _ParameterEditorState extends State<_ParameterEditor> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'parameter search');
  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final String query = _search.text.toLowerCase();
    final List<HostedParameter> shown =
        widget.library.parameters
            .where(
              (HostedParameter p) =>
                  query.isEmpty ||
                  p.name.toLowerCase().contains(query) ||
                  p.module.toLowerCase().contains(query),
            )
            .toList();
    return Container(
      color: t.color.surfaceDeep,
      alignment: Alignment.center,
      child: Container(
        width: t.size.pluginEditorWidth,
        height: t.size.pluginEditorHeight,
        decoration: BoxDecoration(
          color: t.color.surfacePanel,
          border: Border.all(color: t.color.line),
          borderRadius: t.radius.panelBorder,
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(t.spacing.lg),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(widget.instance.name, style: t.type.title),
                        Text('GENERIC VIEW', style: t.type.label),
                      ],
                    ),
                  ),
                  OneBeatButton(
                    label: 'CLOSE',
                    semanticLabel: 'Close generic editor',
                    onPressed: widget.library.closeParameters,
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.spacing.lg,
                vertical: t.spacing.sm,
              ),
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: t.color.line),
                ),
              ),
              child: Container(
                height: t.size.searchHeight,
                padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
                decoration: BoxDecoration(
                  color: t.color.surfaceDeep,
                  border: Border.all(color: t.color.line),
                  borderRadius: t.radius.controlBorder,
                ),
                child: EditableText(
                  controller: _search,
                  focusNode: _focus,
                  style: t.type.body,
                  cursorColor: t.color.accent,
                  backgroundCursorColor: t.color.textMuted,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (final HostedParameter parameter in shown)
                    _ParameterRow(
                      parameter: parameter,
                      library: widget.library,
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(t.spacing.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.color.line)),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    '↵ type value   ↑↓ select   esc close',
                    style: t.type.numericSmall,
                  ),
                  const Spacer(),
                  Text(
                    '${shown.length} shown of ${widget.library.parameters.length}',
                    style: t.type.numericSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParameterRow extends StatelessWidget {
  const _ParameterRow({required this.parameter, required this.library});
  final HostedParameter parameter;
  final PluginLibraryStore library;
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    final double range = parameter.maximum - parameter.minimum;
    final double fraction =
        range == 0
            ? 0
            : ((parameter.value - parameter.minimum) / range).clamp(0, 1);
    return Container(
      height: t.size.parameterRowHeight,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.color.line)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: t.size.parameterLabelWidth,
            child: Text(
              parameter.name,
              style: t.type.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  onHorizontalDragStart:
                      (_) => library.beginParameterGesture(parameter.id),
                  onHorizontalDragUpdate: (DragUpdateDetails details) {
                    final double next =
                        parameter.minimum +
                        ((details.localPosition.dx / constraints.maxWidth)
                                .clamp(0, 1) *
                            range);
                    library.setParameter(parameter, next);
                  },
                  onHorizontalDragEnd:
                      (_) => library.endParameterGesture(parameter.id),
                  child: SizedBox(
                    height: t.size.sliderHeight,
                    child: Align(
                      alignment: Alignment.center,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.color.surfaceDeep,
                                borderRadius: t.radius.controlBorder,
                              ),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: fraction,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.color.accent,
                                borderRadius: t.radius.controlBorder,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(width: t.spacing.md),
          SizedBox(
            width: t.size.parameterValueWidth,
            child: Text(
              parameter.display,
              textAlign: TextAlign.right,
              style: t.type.numericSmall,
            ),
          ),
          SizedBox(width: t.spacing.sm),
          Text('A', style: t.type.label.copyWith(color: t.color.accent)),
        ],
      ),
    );
  }
}

String pluginQuarantineMessage(PluginListing listing) {
  final String event =
      listing.outcome == ScanOutcome.timedOut
          ? 'stopped responding'
          : 'crashed';
  final String phase = switch (listing.failurePhase) {
    ScanPhase.spawn => 'before OneBeat could open it',
    ScanPhase.load => 'while OneBeat was opening it',
    ScanPhase.enumerate => 'while OneBeat was reading its plug-in list',
    ScanPhase.instantiate =>
      'while OneBeat was checking its audio and parameter setup',
    ScanPhase.done => 'after its scan completed',
    ScanPhase.none => 'during its scan',
  };
  return '“${listing.name}” $event $phase. It remains disabled so the rest of your '
      'plug-ins can load. Retry after updating or removing it, or keep it quarantined.';
}

String _pluginProblemDetail(PluginListing listing) {
  final String failure =
      listing.outcome == ScanOutcome.timedOut
          ? 'stopped responding'
          : 'crashed';
  return 'CLAP · $failure during scan · will not be rescanned automatically';
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.scanning});
  final bool scanning;
  @override
  Widget build(BuildContext context) {
    final OneBeatTokens t = OneBeatTheme.of(context);
    return Center(
      child: Text(
        scanning
            ? 'Looking for plug-ins…'
            : 'No plugins found — add a folder or scan again.',
        style: t.type.body.copyWith(color: t.color.textMuted),
      ),
    );
  }
}
