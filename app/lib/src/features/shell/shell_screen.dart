// ShellScreen — the application frame (UI-C-01, UI-D-01).
//
// Composes the top chrome (menu bar, transport bar), left side rail, optional
// docked browser panel, central workspace area, and bottom status bar.
// Pure presentational widget: data in, callbacks out.
import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../browser/browser_panel.dart';
import 'shell_screen_vm.dart';
import 'side_rail.dart';
import 'status_bar.dart';
import 'transport_bar.dart';

class ShellScreen extends StatelessWidget {
  const ShellScreen({
    required this.vm,
    required this.workspace,
    this.overlay,
    this.onRailSelect,
    this.onMenuTap,
    this.onUndo,
    this.onRedo,
    this.onTogglePlay,
    this.onStop,
    this.onToggleLoop,
    this.onToggleMetronome,
    this.onSearchTap,
    this.onExport,
    this.onTempoSubmitted,
    this.onBrowserTap,
    this.onBrowserDoubleTap,
    this.onBrowserToggle,
    this.onBrowserSearchTap,
    this.onBrowserSearchChanged,
    this.onBrowserScrollChanged,
    this.onBrowserResize,
    this.onBrowserAddFolder,
    super.key,
  });

  final ShellScreenVm vm;
  final Widget workspace;
  final Widget? overlay;

  final ValueChanged<int>? onRailSelect;
  final ValueChanged<int>? onMenuTap;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onStop;
  final VoidCallback? onToggleLoop;
  final VoidCallback? onToggleMetronome;
  final VoidCallback? onSearchTap;
  final VoidCallback? onExport;
  final ValueChanged<String>? onTempoSubmitted;
  final ValueChanged<String>? onBrowserTap;
  final ValueChanged<String>? onBrowserDoubleTap;
  final ValueChanged<String>? onBrowserToggle;
  final VoidCallback? onBrowserSearchTap;
  final ValueChanged<String>? onBrowserSearchChanged;
  final ValueChanged<double>? onBrowserScrollChanged;
  final ValueChanged<double>? onBrowserResize;
  final VoidCallback? onBrowserAddFolder;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Widget? overlay = this.overlay;

    final Widget frame = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: tokens.spacing.xl),
        ObTransportBar(
          vm: vm.transport,
          onUndo: onUndo,
          onRedo: onRedo,
          onTogglePlay: onTogglePlay,
          onStop: onStop,
          onToggleLoop: onToggleLoop,
          onToggleMetronome: onToggleMetronome,
          onSearchTap: onSearchTap,
          onExport: onExport,
          onTempoSubmitted: onTempoSubmitted,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ObSideRail(vm: vm.rail, onSelect: onRailSelect),
                if (vm.browser != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.sm),
                  _ResizableBrowserPanel(
                    vm: vm.browser!,
                    onTap: onBrowserTap,
                    onDoubleTap: onBrowserDoubleTap,
                    onToggle: onBrowserToggle,
                    onSearchTap: onBrowserSearchTap,
                    onSearchChanged: onBrowserSearchChanged,
                    onScrollChanged: onBrowserScrollChanged,
                    width: vm.browserWidth,
                    onResize: onBrowserResize,
                    // Sample packs live in the shared instrument browser,
                    // so the import action belongs here rather than on a
                    // dedicated Packs destination.
                    onAddFolder: onBrowserAddFolder,
                  ),
                ],
                SizedBox(width: tokens.spacing.sm),
                Expanded(child: _ShellPanel(child: workspace)),
              ],
            ),
          ),
        ),
        ObStatusBar(vm: vm.status),
      ],
    );

    return ColoredBox(
      color: tokens.color.surfaceSunken,
      child: overlay == null ? frame : Stack(children: <Widget>[frame, overlay]),
    );
  }
}

/// The browser is a docked surface, but unlike the workspace it has a user
/// controlled width. The shell owns that state and passes it in, rather than
/// treating resizing as browser content.
class _ResizableBrowserPanel extends StatefulWidget {
  const _ResizableBrowserPanel({
    required this.vm,
    required this.width,
    this.onTap,
    this.onDoubleTap,
    this.onToggle,
    this.onSearchTap,
    this.onSearchChanged,
    this.onScrollChanged,
    this.onResize,
    this.onAddFolder,
  });

  final ObBrowserPanelVm vm;
  final double width;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onDoubleTap;
  final ValueChanged<String>? onToggle;
  final VoidCallback? onSearchTap;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<double>? onScrollChanged;
  final ValueChanged<double>? onResize;
  final VoidCallback? onAddFolder;

  @override
  State<_ResizableBrowserPanel> createState() => _ResizableBrowserPanelState();
}

class _ResizableBrowserPanelState extends State<_ResizableBrowserPanel> {
  static const double _minWidth = 180;
  static const double _maxWidth = 420;
  late double _width;

  @override
  void initState() {
    super.initState();
    _width = widget.width;
  }

  @override
  void didUpdateWidget(covariant _ResizableBrowserPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.width != oldWidget.width && widget.width != _width) {
      _width = widget.width;
    }
  }

  void _resize(DragUpdateDetails details) {
    final double next = (_width + details.delta.dx).clamp(_minWidth, _maxWidth).toDouble();
    setState(() => _width = next);
    widget.onResize?.call(details.delta.dx);
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: _width,
          child: _ShellPanel(
            child: ObBrowserPanel(
              vm: widget.vm,
              width: _width,
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              onToggle: widget.onToggle,
              onSearchTap: widget.onSearchTap,
              onSearchChanged: widget.onSearchChanged,
              onScrollChanged: widget.onScrollChanged,
              onAddFolder: widget.onAddFolder,
            ),
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: const Key('browser-resize-handle'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: _resize,
            child: SizedBox(
              width: tokens.spacing.xs,
              child: Center(
                child: Container(
                  width: tokens.border.hairline,
                  height: double.infinity,
                  color: tokens.color.lineStrong,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The shell's docked surfaces share one inset frame. Keeping the clipping and
/// outline here preserves the reusable panel components while making their
/// relationship to the workspace visible as a single composition.
class _ShellPanel extends StatelessWidget {
  const _ShellPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: tokens.color.surfaceDeep, borderRadius: tokens.radius.panelBorder),
      child: child,
    );
  }
}
