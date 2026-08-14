// Workspace fixtures (UI-C-12) — transcribed from `screens/workspace-window.png`
// and `screens/workspace-drag.png`.
//
// The drag positions are read off the drag mockup at the export's 2× scale
// (measure px, divide by 2) and are relative to the content area — the region
// right of the rail and below the transport bar, which is where the drag layer
// is stacked.
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/mixer/mixer_strip.dart';
import 'package:onebeat/src/features/shell/status_bar.dart';
import 'package:onebeat/src/features/workspace/workspace_vm.dart';

const WorkspaceLayoutsVm demoLayouts = WorkspaceLayoutsVm(
  layouts: <LayoutVm>[
    LayoutVm(name: 'Beatmaking', current: true),
    LayoutVm(name: 'Arranging'),
    LayoutVm(name: 'Mixing'),
  ],
);

/// The six fader strips inside the detached Mixer window. Drums Bus is
/// selected — which is what the window's own subtitle says it is.
final List<MixerStripVm> demoDetachedStrips = <MixerStripVm>[
  MixerStripVm(
    name: 'Kick 808',
    color: channelColors[0],
    route: '→ Drums',
    fader: 0.42,
  ),
  MixerStripVm(
    name: 'Snare',
    color: channelColors[5],
    route: '→ Drums',
    fader: 0.62,
  ),
  MixerStripVm(
    name: 'Sub Bass',
    color: channelColors[2],
    route: '→ Bass',
    fader: 0.48,
  ),
  MixerStripVm(
    name: 'Soft Keys',
    color: channelColors[4],
    route: '→ Music',
    fader: 0.36,
  ),
  MixerStripVm(
    name: 'Drums Bus',
    color: channelColors[4],
    route: '→ Master',
    fader: 0.55,
    routeActive: true,
    selected: true,
  ),
  MixerStripVm(
    name: 'MASTER',
    color: channelColors[7],
    route: '0.0 dB',
    fader: 0.58,
    routeActive: true,
    isMaster: true,
  ),
];

const ObStatusBarVm demoWorkspaceWindowStatus = ObStatusBarVm(
  tone: StatusTone.ok,
  primary: 'Mixer detached to its own window',
  details: <String>['Layout Beatmaking · saved'],
  rightHint: 'Reset to default is one click away, always',
);

/// The mid-drag state: the Channel Rack in flight over the playlist, four edge
/// targets and the centre tab card.
const WorkspaceDragVm demoWorkspaceDrag = WorkspaceDragVm(
  floatingNote: 'dragging · Channel Rack',
  ghost: DragGhostVm(
    title: 'Channel Rack',
    left: 487,
    top: 192,
    width: 371,
    height: 228,
  ),
  targets: <DockTargetVm>[
    // Clear of the first clip: the left-edge chip belongs outside the content
    // it would dock beside, not on top of it.
    DockTargetVm(label: 'Dock left', edge: DockEdge.left, left: 248, top: 48),
    DockTargetVm(label: 'Dock top', edge: DockEdge.top, left: 839, top: 48),
    DockTargetVm(label: 'Dock right', edge: DockEdge.right, left: 1434, top: 48),
    DockTargetVm(
      label: 'Dock bottom',
      edge: DockEdge.bottom,
      left: 827,
      top: 799,
    ),
  ],
  asTab: DockAsTabVm(
    title: 'Dock as tab',
    path: 'CHANNEL RACK → PLAYLIST',
    left: 628,
    top: 454,
  ),
);

const ObStatusBarVm demoWorkspaceDragStatus = ObStatusBarVm(
  tone: StatusTone.ok,
  primary: 'Dragging Channel Rack over Playlist',
  details: <String>[
    'Edge zones split · centre tabs · drop outside the window to tear off',
  ],
  rightHint: 'Panel handles appear on hover · ⌥ drag to tear off',
);
