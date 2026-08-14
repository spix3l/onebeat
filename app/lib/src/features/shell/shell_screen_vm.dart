// ShellScreenVm — the root frame view model (UI-C-01, UI-D-01).
//
// Pure data: menu bar, transport bar, destination rail, optional browser panel,
// and status bar. The screen widget consumes this without logic or engine types.
import 'package:flutter/widgets.dart';

import '../browser/browser_panel.dart';
import 'menu_bar.dart';
import 'side_rail.dart';
import 'status_bar.dart';
import 'transport_bar.dart';

@immutable
class ShellScreenVm {
  const ShellScreenVm({
    this.menuBar,
    required this.transport,
    required this.rail,
    required this.status,
    this.browser,
  });

  final ObMenuBarVm? menuBar;
  final ObTransportBarVm transport;
  final ObSideRailVm rail;
  final ObBrowserPanelVm? browser;
  final ObStatusBarVm status;
}
