// The shell's fixed chrome: the left destination rail and the top-bar readout
// wells, from the design screens (`onebeat-shell.html`).
//
// Split out of shell.dart because the shell was becoming a file where layout,
// shortcut wiring and three bespoke widgets all lived together, and the bespoke
// widgets are the part that gets restyled.
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'action_registry.dart';
import 'controls.dart';
import 'engine_controller.dart';

/// One destination in the left rail.
@immutable
class RailDestination {
  const RailDestination({
    required this.actionId,
    required this.glyph,
    required this.label,
    this.view,
    this.onSelected,
  });

  /// The registry entry this tile satisfies, so FR-UX-17 can find it.
  final String actionId;

  /// A text glyph rather than an icon font: the app ships two typefaces and no
  /// icon set, and inventing a third dependency for six tiles is not worth it.
  final String glyph;
  final String label;

  /// The workspace this tile switches to, when it is a view.
  final WorkspaceView? view;

  /// For tiles that are not views (Packs, FX) — null means "not yet built",
  /// and the tile renders disabled rather than lying about being clickable.
  final VoidCallback? onSelected;
}

/// The left rail: the app's top-level destinations, always visible so the shape
/// of the product is legible before anything has been built (FR-UX-13).
class DestinationRail extends StatelessWidget {
  const DestinationRail({
    required this.destinations,
    required this.activeView,
    required this.onSelectView,
    super.key,
  });

  final List<RailDestination> destinations;
  final WorkspaceView activeView;
  final ValueChanged<WorkspaceView> onSelectView;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: tokens.size.railWidth,
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
      decoration: BoxDecoration(
        color: tokens.color.surfaceRaised,
        border: Border(
          right: BorderSide(
            color: tokens.color.line,
            width: tokens.border.hairline,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          for (final RailDestination destination in destinations)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.sm),
              child: _RailTile(
                destination: destination,
                active:
                    destination.view != null && destination.view == activeView,
                onTap: destination.view != null
                    ? () => onSelectView(destination.view!)
                    : destination.onSelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _RailTile extends StatefulWidget {
  const _RailTile({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final RailDestination destination;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_RailTile> createState() => _RailTileState();
}

class _RailTileState extends State<_RailTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = widget.onTap != null;
    final RailDestination destination = widget.destination;
    final Color background = widget.active
        ? tokens.color.accent
        : _hovered && enabled
        ? tokens.color.surfaceOverlay
        : tokens.color.surfaceRaised;
    final Color foreground = !enabled
        ? tokens.color.textMuted
        : widget.active
        ? tokens.color.surfaceDeep
        : tokens.color.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.active,
      label: destination.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          key: actionKey(destination.actionId),
          onTap: widget.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: tokens.motion.instant,
                curve: tokens.motion.standard,
                width: tokens.size.railTileSize,
                height: tokens.size.railTileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: tokens.radius.controlBorder,
                ),
                child: Text(
                  destination.glyph,
                  style: tokens.type.title.copyWith(
                    color: foreground,
                    fontSize: tokens.size.railGlyphSize,
                  ),
                ),
              ),
              SizedBox(height: tokens.spacing.xxs),
              Text(
                destination.label.toUpperCase(),
                style: tokens.type.label.copyWith(
                  color: widget.active
                      ? tokens.color.textPrimary
                      : tokens.color.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transport and history: play/stop, undo, redo, return-to-zero.
///
/// Takes plain values and callbacks rather than an `EngineController`, so the
/// reachability test can render the *real* controls instead of a copy that
/// might drift from them.
class TransportCluster extends StatelessWidget {
  const TransportCluster({
    required this.playing,
    required this.canUndo,
    required this.canRedo,
    required this.onTogglePlay,
    required this.onUndo,
    required this.onRedo,
    required this.onReturnToZero,
    this.undoName = '',
    this.redoName = '',
    super.key,
  });

  final bool playing;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onTogglePlay;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReturnToZero;
  final String undoName;
  final String redoName;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OneBeatButton(
          key: actionKey('transport.play'),
          label: playing ? 'STOP' : 'PLAY',
          semanticLabel: ActionRegistry.byId('transport.play').tooltip,
          active: playing,
          onPressed: onTogglePlay,
        ),
        SizedBox(width: tokens.spacing.sm),
        // Undo and redo need visible controls, not just ⌘Z: a keyboard-only
        // action is as unreachable as a right-click-only one to someone who
        // does not already know it exists (FR-UX-17).
        OneBeatButton(
          key: actionKey('edit.undo'),
          label: '↶',
          semanticLabel: canUndo && undoName.isNotEmpty
              ? 'Undo $undoName'
              : ActionRegistry.byId('edit.undo').tooltip,
          onPressed: canUndo ? onUndo : null,
        ),
        SizedBox(width: tokens.spacing.xs),
        OneBeatButton(
          key: actionKey('edit.redo'),
          label: '↷',
          semanticLabel: canRedo && redoName.isNotEmpty
              ? 'Redo $redoName'
              : ActionRegistry.byId('edit.redo').tooltip,
          onPressed: canRedo ? onRedo : null,
        ),
        SizedBox(width: tokens.spacing.sm),
        OneBeatButton(
          key: actionKey('transport.returnToZero'),
          label: 'RTZ',
          semanticLabel: ActionRegistry.byId('transport.returnToZero').tooltip,
          onPressed: onReturnToZero,
        ),
      ],
    );
  }
}

/// The view switcher from the design's top bar. Always shows all three, so the
/// app's shape is legible before anything has been built.
class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({
    required this.activeView,
    required this.onSelect,
    super.key,
  });

  final WorkspaceView activeView;
  final ValueChanged<WorkspaceView> onSelect;

  static const Map<WorkspaceView, String> labels = <WorkspaceView, String>{
    WorkspaceView.arrangement: 'PLAYLIST',
    WorkspaceView.rack: 'CHANNELS',
    WorkspaceView.pianoRoll: 'PIANO ROLL',
  };

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final MapEntry<WorkspaceView, String> entry in labels.entries)
          Padding(
            padding: EdgeInsets.only(right: tokens.spacing.xs),
            child: OneBeatButton(
              label: entry.value,
              semanticLabel: 'Show the ${entry.value.toLowerCase()} view',
              active: activeView == entry.key,
              onPressed: () => onSelect(entry.key),
            ),
          ),
      ],
    );
  }
}

/// A labelled readout well: the BPM field, the time signature, the clock.
///
/// The design draws these as recessed wells rather than as controls, because
/// they are values you read far more often than values you set. The label sits
/// *after* the value, small and muted, which is what keeps the digits the thing
/// your eye lands on.
class ReadoutWell extends StatelessWidget {
  const ReadoutWell({
    required this.child,
    required this.label,
    this.width,
    super.key,
  });

  final Widget child;
  final String label;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: width,
      height: tokens.size.readoutHeight,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.controlBorder,
        border: Border.all(
          color: tokens.color.line,
          width: tokens.border.hairline,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Flexible(child: child),
          if (label.isNotEmpty) ...<Widget>[
            SizedBox(width: tokens.spacing.sm),
            Text(label, style: tokens.type.label),
          ],
        ],
      ),
    );
  }
}

/// The app's identity block, top-left, above the rail in the design.
class BrandMark extends StatelessWidget {
  const BrandMark({required this.version, super.key});

  final String version;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return SizedBox(
      width: tokens.size.brandWidth,
      child: Row(
        children: <Widget>[
          Container(
            width: tokens.size.railGlyphSize,
            height: tokens.size.railGlyphSize,
            decoration: BoxDecoration(
              color: tokens.color.accent,
              borderRadius: BorderRadius.all(tokens.radius.sm),
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('ONEBEAT', style: tokens.type.brand),
              Text(version, style: tokens.type.label),
            ],
          ),
        ],
      ),
    );
  }
}

/// The ⌘K affordance. Opens the shortcut sheet, which is the command palette's
/// first form: every registered action, with the key that runs it.
class SearchAffordance extends StatelessWidget {
  const SearchAffordance({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final UiAction action = ActionRegistry.byId('view.search');
    return Semantics(
      button: true,
      label: action.tooltip,
      child: GestureDetector(
        key: actionKey(action.id),
        onTap: onTap,
        child: Container(
          width: tokens.size.searchWidth,
          height: tokens.size.readoutHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          decoration: BoxDecoration(
            color: tokens.color.surfaceDeep,
            borderRadius: tokens.radius.controlBorder,
            border: Border.all(
              color: tokens.color.line,
              width: tokens.border.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(action.label, style: tokens.type.label),
              ),
              Text(action.shortcut, style: tokens.type.numericSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shortcut sheet: every bound action, grouped by area.
///
/// This is FR-UX-18's "shortcuts are discoverable" made concrete, and it is
/// generated from the registry — so it can never list a shortcut that is not
/// bound, or miss one that is.
class ShortcutSheet extends StatelessWidget {
  const ShortcutSheet({required this.onDismiss, super.key});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return GestureDetector(
      onTap: onDismiss,
      child: ColoredBox(
        color: tokens.color.canvasScrim,
        child: Center(
          child: Container(
            width: tokens.size.pluginEditorWidth,
            constraints: BoxConstraints(
              maxHeight: tokens.size.pluginEditorHeight,
            ),
            padding: EdgeInsets.all(tokens.spacing.xl),
            decoration: BoxDecoration(
              color: tokens.color.surfacePanel,
              borderRadius: tokens.radius.panelBorder,
              border: Border.all(
                color: tokens.color.line,
                width: tokens.border.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('KEYBOARD SHORTCUTS', style: tokens.type.label),
                    ),
                    OneBeatButton(label: 'Close', onPressed: onDismiss),
                  ],
                ),
                SizedBox(height: tokens.spacing.md),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final ActionArea area in ActionArea.values)
                          ..._areaSection(tokens, area),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _areaSection(OneBeatTokens tokens, ActionArea area) {
    final List<UiAction> bound = ActionRegistry.forArea(
      area,
    ).where((UiAction action) => action.activator != null).toList();
    if (bound.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: EdgeInsets.only(
          top: tokens.spacing.md,
          bottom: tokens.spacing.xs,
        ),
        child: Text(area.label.toUpperCase(), style: tokens.type.label),
      ),
      for (final UiAction action in bound)
        Padding(
          padding: EdgeInsets.symmetric(vertical: tokens.spacing.xxs),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(action.label, style: tokens.type.body)),
              Text(action.shortcut, style: tokens.type.numeric),
            ],
          ),
        ),
    ];
  }
}
