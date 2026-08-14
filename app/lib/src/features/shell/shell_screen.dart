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
    this.onSearchTap,
    this.onExport,
    this.onBrowserTap,
    this.onBrowserToggle,
    this.onBrowserSearchTap,
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
  final VoidCallback? onSearchTap;
  final VoidCallback? onExport;
  final ValueChanged<String>? onBrowserTap;
  final ValueChanged<String>? onBrowserToggle;
  final VoidCallback? onBrowserSearchTap;

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
          onSearchTap: onSearchTap,
          onExport: onExport,
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
                  _ShellPanel(
                    child: ObBrowserPanel(
                      vm: vm.browser!,
                      onTap: onBrowserTap,
                      onToggle: onBrowserToggle,
                      onSearchTap: onBrowserSearchTap,
                    ),
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
      child: overlay == null
          ? frame
          : Stack(children: <Widget>[frame, overlay]),
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
      decoration: BoxDecoration(
        color: tokens.color.surfaceDeep,
        borderRadius: tokens.radius.panelBorder,
      ),
      child: child,
    );
  }
}
