// The shell's fixed chrome: the left destination rail and the top-bar readout
// wells, from the design screens (`onebeat-shell.html`).
//
// Split out of shell.dart because the shell was becoming a file where layout,
// shortcut wiring and three bespoke widgets all lived together, and the bespoke
// widgets are the part that gets restyled.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'action_registry.dart';
import 'controls.dart';
import 'engine_controller.dart';
import 'icons.dart';

/// One destination in the left rail.
@immutable
class RailDestination {
  const RailDestination({
    required this.actionId,
    required this.icon,
    required this.label,
    this.view,
    this.onSelected,
  });

  /// The registry entry this tile satisfies, so FR-UX-17 can find it.
  final String actionId;

  /// A painted icon (see icons.dart). Text glyphs were tried first and were
  /// the reason half the rail rendered as tofu: the shipped typefaces do not
  /// carry `▥` or `🎛`.
  final OneBeatIconData icon;
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
                child: OneBeatIcon(
                  destination.icon,
                  size: tokens.size.railGlyphSize,
                  color: foreground,
                ),
              ),
              SizedBox(height: tokens.spacing.xxs),
              Text(
                destination.label.toUpperCase(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: tokens.type.railLabel.copyWith(
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

/// Transport and history: play/stop, undo, redo, return-to-zero, loop.
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
    this.loopEnabled = false,
    this.onToggleLoop,
    this.undoName = '',
    this.redoName = '',
    super.key,
  });

  final bool playing;
  final bool canUndo;
  final bool canRedo;
  final bool loopEnabled;
  final VoidCallback onTogglePlay;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReturnToZero;
  final VoidCallback? onToggleLoop;
  final String undoName;
  final String redoName;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TransportButton(
          key: actionKey('edit.undo'),
          icon: OneBeatIconData.undo,
          semanticLabel: canUndo && undoName.isNotEmpty
              ? 'Undo $undoName'
              : ActionRegistry.byId('edit.undo').tooltip,
          onPressed: canUndo ? onUndo : null,
        ),
        SizedBox(width: tokens.spacing.xs),
        TransportButton(
          key: actionKey('edit.redo'),
          icon: OneBeatIconData.redo,
          semanticLabel: canRedo && redoName.isNotEmpty
              ? 'Redo $redoName'
              : ActionRegistry.byId('edit.redo').tooltip,
          onPressed: canRedo ? onRedo : null,
        ),
        SizedBox(width: tokens.spacing.md),
        // The play control is the one filled thing in the bar, playing or not:
        // in the design it is what your eye finds without looking.
        TransportButton(
          key: actionKey('transport.play'),
          icon: playing ? OneBeatIconData.pause : OneBeatIconData.play,
          semanticLabel: ActionRegistry.byId('transport.play').tooltip,
          filled: true,
          wide: true,
          onPressed: onTogglePlay,
        ),
        SizedBox(width: tokens.spacing.xs),
        TransportButton(
          key: actionKey('transport.returnToZero'),
          icon: OneBeatIconData.stop,
          semanticLabel: ActionRegistry.byId('transport.returnToZero').tooltip,
          onPressed: onReturnToZero,
        ),
        if (onToggleLoop != null) ...<Widget>[
          SizedBox(width: tokens.spacing.xs),
          TransportButton(
            icon: OneBeatIconData.loop,
            semanticLabel: 'Toggle loop playback',
            filled: loopEnabled,
            onPressed: onToggleLoop,
          ),
        ],
      ],
    );
  }
}

/// A square icon well. The transport is the one row in the app where controls
/// carry no text at all, so it does not reuse [OneBeatButton]'s label layout.
class TransportButton extends StatefulWidget {
  const TransportButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.filled = false,
    this.wide = false,
    super.key,
  });

  final OneBeatIconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Accent-filled: the play control, and the loop control while looping.
  final bool filled;
  final bool wide;

  @override
  State<TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<TransportButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final bool enabled = widget.onPressed != null;
    final Color background = widget.filled && enabled
        ? tokens.color.accent
        : _hovered && enabled
        ? tokens.color.surfaceOverlay
        : tokens.color.surfaceRaised;
    final Color foreground = !enabled
        ? tokens.color.textMuted
        : widget.filled
        ? tokens.color.textPrimary
        : tokens.color.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        onShowHoverHighlight: (bool value) => setState(() => _hovered = value),
        onShowFocusHighlight: (bool value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: tokens.motion.instant,
              curve: tokens.motion.standard,
              width: widget.wide
                  ? tokens.size.transportButtonSize * 1.3 // token-lint-ok: ratio
                  : tokens.size.transportButtonSize,
              height: tokens.size.transportButtonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: tokens.radius.controlBorder,
                border: Border.all(
                  color: _focused
                      ? tokens.color.accent
                      : widget.filled
                      ? tokens.color.accent
                      : tokens.color.line,
                  width: _focused
                      ? tokens.size.focusRingWidth
                      : tokens.border.hairline,
                ),
              ),
              child: OneBeatIcon(
                widget.icon,
                size: tokens.size.transportGlyphSize,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The view switcher from the design's top bar. Always shows all options.
class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({
    required this.activeView,
    required this.onSelect,
    super.key,
  });

  final WorkspaceView activeView;
  final ValueChanged<WorkspaceView> onSelect;

  static const List<(WorkspaceView, OneBeatIconData, String)> _destinations =
      <(WorkspaceView, OneBeatIconData, String)>[
    (WorkspaceView.arrangement, OneBeatIconData.playlist, 'Playlist'),
    (WorkspaceView.rack, OneBeatIconData.channels, 'Channels'),
    (WorkspaceView.pianoRoll, OneBeatIconData.piano, 'Piano roll'),
    (WorkspaceView.mixer, OneBeatIconData.mixer, 'Mixer'),
  ];

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (WorkspaceView view, OneBeatIconData icon, String label)
            in _destinations)
          Padding(
            padding: EdgeInsets.only(right: tokens.spacing.xs),
            child: _ViewSwitcherTile(
              icon: icon,
              label: label,
              active: activeView == view,
              onTap: () => onSelect(view),
            ),
          ),
      ],
    );
  }
}

/// One switcher tile: icon over caption, exactly as the design draws it. Kept
/// distinct from the rail tile because it is half the size and its caption is
/// sentence case, not the rail's uppercase.
class _ViewSwitcherTile extends StatefulWidget {
  const _ViewSwitcherTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final OneBeatIconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ViewSwitcherTile> createState() => _ViewSwitcherTileState();
}

class _ViewSwitcherTileState extends State<_ViewSwitcherTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Color foreground = widget.active
        ? tokens.color.textPrimary
        : tokens.color.textMuted;
    return Semantics(
      button: true,
      selected: widget.active,
      label: 'Show the ${widget.label.toLowerCase()} view',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: tokens.motion.instant,
            curve: tokens.motion.standard,
            width: tokens.size.viewSwitcherTileWidth,
            height: tokens.size.readoutHeight + tokens.spacing.sm,
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.xxs),
            decoration: BoxDecoration(
              color: widget.active
                  ? tokens.color.accent
                  : _hovered
                  ? tokens.color.surfaceOverlay
                  : tokens.color.surfaceSunken,
              borderRadius: tokens.radius.controlBorder,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OneBeatIcon(
                  widget.icon,
                  size: tokens.size.iconSize,
                  color: foreground,
                ),
                SizedBox(height: tokens.spacing.xxs),
                Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: tokens.type.railLabel.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
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
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
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
        // A well with no fixed [width] shrink-wraps, and its children are
        // Flexible rather than Expanded so that they may. Leaving this at
        // `max` asks the row to fill an unbounded width, which throws during
        // layout and takes the whole top bar down with it.
        mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          Flexible(child: child),
          if (label.isNotEmpty) ...<Widget>[
            SizedBox(width: tokens.spacing.xs),
            // The caption never wraps and never pushes the digits out of the
            // well: it is the part of the readout you can afford to lose.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: tokens.type.labelDense,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The gap the window's real traffic lights occupy.
///
/// The window uses a full-size content view, so the close/minimise/zoom buttons
/// are drawn by macOS *inside* the app's top bar — the design's own arrangement.
/// The app used to paint three coloured dots of its own here, which meant two
/// sets of them: the real ones in a title strip above, and a decorative set
/// that did nothing when clicked.
class TitleBarInset extends StatelessWidget {
  const TitleBarInset({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: OneBeatTheme.of(context).size.titleBarInset);
}

/// The app's identity block, top-left, matching the design.
class BrandMark extends StatelessWidget {
  const BrandMark({required this.version, super.key});

  final String version;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: tokens.size.controlHeight,
          height: tokens.size.controlHeight,
          decoration: BoxDecoration(
            color: tokens.color.accent,
            borderRadius: BorderRadius.all(tokens.radius.md),
          ),
          alignment: Alignment.center,
          child: Container(
            width: tokens.spacing.sm,
            height: tokens.spacing.sm,
            decoration: BoxDecoration(
              color: tokens.color.surfaceSunken,
              shape: BoxShape.circle,
            ),
          ),
        ),
        SizedBox(width: tokens.spacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('ONEBEAT', style: tokens.type.brand),
            Text(version, style: tokens.type.labelDense),
          ],
        ),
      ],
    );
  }
}

/// Export action button.
class ExportButton extends StatelessWidget {
  const ExportButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Semantics(
      button: true,
      label: 'Export audio',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: tokens.size.controlHeight,
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          decoration: BoxDecoration(
            color: tokens.color.accent,
            borderRadius: tokens.radius.controlBorder,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OneBeatIcon(
                OneBeatIconData.export,
                size: tokens.size.tagHeight,
                color: tokens.color.textPrimary,
              ),
              SizedBox(width: tokens.spacing.xs),
              Text(
                'Export',
                style: tokens.type.labelDense.copyWith(
                  color: tokens.color.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A vertical master peak indicator on the far right of the top bar.
class MasterPeakIndicator extends StatelessWidget {
  const MasterPeakIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      width: tokens.spacing.xs,
      height: tokens.size.controlHeight,
      decoration: BoxDecoration(
        color: tokens.color.surfaceRaised,
        borderRadius: tokens.radius.controlBorder,
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Container(color: tokens.color.meterHigh),
          ),
          Expanded(
            flex: 3,
            child: Container(color: tokens.color.meterMid),
          ),
          Expanded(
            flex: 10,
            child: Container(color: tokens.color.meterLow),
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
          constraints: BoxConstraints(
            minWidth: tokens.size.controlHeight,
            maxWidth: tokens.size.searchWidth,
          ),
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
              OneBeatIcon(
                OneBeatIconData.search,
                size: tokens.size.tagHeight,
                color: tokens.color.textMuted,
              ),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: tokens.type.label,
                ),
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
