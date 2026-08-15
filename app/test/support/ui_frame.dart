// The window frame a screen golden is recorded inside (Phase C).
//
// UI-C-01 builds the real shell; until it lands, every Phase C golden needs
// the same four pieces of chrome around its content — menu bar, transport bar,
// left rail, status bar — or a reviewer cannot put the golden next to a 1600×1000
// mockup and see the same design. This assembles them from the UI-B-02/B-03
// components so that the screens under test stay what they are meant to be:
// content areas driven by a vm.
//
// When UI-C-01 lands, this is what its `ShellScreen` replaces.
import 'package:flutter/widgets.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/shell/menu_bar.dart';
import 'package:onebeat/src/features/shell/rail_glyphs.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';
import 'package:onebeat/src/features/shell/status_bar.dart';
import 'package:onebeat/src/features/shell/transport_bar.dart';

/// The menu titles every mockup draws, with `Tools` marked active where a
/// screen shows its menu open.
ObMenuBarVm demoMenuBar({int? activeIndex}) => ObMenuBarVm(
  menus: const <String>[
    'File',
    'Edit',
    'Pattern',
    'View',
    'Tools ▾',
    'Mixer',
    'Window',
    'Help',
  ],
  activeIndex: activeIndex,
  clock: '14:02',
);

/// The transport bar as the mockups set it: stopped, 124 BPM, 4/4.
const ObTransportBarVm demoTransportBar = ObTransportBarVm(
  title: 'ONEBEAT',
  subtitle: 'v0.3 SEQUENCES',
  playing: false,
  looping: false,
  bpmText: '124.00',
  sigText: '4/4',
  positionText: '02:01:218',
  meterLeft: 0.55,
  meterRight: 0.48,
  searchHint: 'Search actions',
);

/// The reduced rail the extension screens draw: PLAYLIST, SCRIPT, EXTNS.
const ObSideRailVm demoExtensionsRail = ObSideRailVm(
  items: <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.script, label: 'Script'),
    RailItemVm(icon: ObRailGlyphKind.extension, label: 'Extns'),
  ],
  activeIndex: 2,
  separatorBefore: null,
);

/// The full rail: the workspace screens keep every project destination.
const ObSideRailVm demoWorkspaceRail = ObSideRailVm(
  items: <RailItemVm>[
    RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
    RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
    RailItemVm(icon: ObRailGlyphKind.note, label: 'Piano'),
    RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
  ],
  activeIndex: 3,
  separatorBefore: null,
);

/// Wraps [content] in the app's chrome at the mockups' 1600×1000.
///
/// [overlay] is stacked over the content *and* the chrome — an open popover
/// spills out of the panel that anchored it, which is exactly what
/// `screens/ext-manager.png` and `screens/workspace-window.png` show.
class UiFrame extends StatelessWidget {
  const UiFrame({
    required this.content,
    required this.status,
    this.menuBar,
    this.rail = demoWorkspaceRail,
    this.transport = demoTransportBar,
    this.overlay,
    super.key,
  });

  final Widget content;
  final ObStatusBarVm status;
  final ObMenuBarVm? menuBar;
  final ObSideRailVm rail;
  final ObTransportBarVm transport;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final Widget? overlay = this.overlay;

    final Widget frame = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ObMenuBar(vm: menuBar ?? demoMenuBar()),
        ObTransportBar(vm: transport),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ObSideRail(vm: rail),
              Expanded(child: content),
            ],
          ),
        ),
        ObStatusBar(vm: status),
      ],
    );

    return ColoredBox(
      color: tokens.color.surfaceSunken,
      child:
          overlay == null
              ? frame
              : Stack(children: <Widget>[frame, overlay]),
    );
  }
}
