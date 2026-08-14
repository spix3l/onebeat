// Browser fixtures (UI-B-04) — the two trees the mockups draw, verbatim.
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/browser/browser_panel.dart';

/// The tree from `screens/channel-rack.png`.
///
/// `Current Project` is open and its patterns follow it at the folder's own
/// indent — that is how the mockup draws it, and it is why `Main Groove` is a
/// sibling of the folder here rather than a child. Only a pattern's own
/// contents step in a level.
final List<BrowserNodeVm> demoBrowserTree = <BrowserNodeVm>[
  const BrowserFolderVm(id: 'packs', name: 'Packs', count: 12),
  const BrowserFolderVm(
    id: 'project',
    name: 'Current Project',
    expanded: true,
  ),
  BrowserPatternVm(
    id: 'main-groove',
    name: 'Main Groove',
    color: channelColors[0],
    badge: '4×',
    children: <BrowserNodeVm>[
      BrowserPatternVm(
        id: 'soft-keys',
        name: 'Soft Keys',
        color: channelColors[4],
        badge: 'piano roll',
      ),
      BrowserPatternVm(
        id: 'bass-motif',
        name: 'Bass Motif',
        color: channelColors[2],
        badge: '3×',
      ),
    ],
  ),
  const BrowserFolderVm(id: 'drums', name: 'Drums', count: 340),
  const BrowserFolderVm(id: 'synths', name: 'Synths'),
];

/// The flat sample list from `screens/arrangement.png`, with the dot colours
/// it draws (channel colours c1…c8, in the order the mockup uses them).
final List<BrowserNodeVm> demoBrowserSamples = <BrowserNodeVm>[
  BrowserSampleVm(id: 'kick', name: 'Kick 808', color: channelColors[0]),
  BrowserSampleVm(id: 'sub', name: 'Sub Bass', color: channelColors[3]),
  BrowserSampleVm(id: 'vox', name: 'Vocal Take 3', color: channelColors[5]),
  BrowserSampleVm(id: 'sweep', name: 'Filter Sweep', color: channelColors[4]),
  BrowserSampleVm(id: 'crash', name: 'Reverse Crash', color: channelColors[1]),
  BrowserSampleVm(id: 'slide', name: '808 Slide', color: channelColors[6]),
  BrowserSampleVm(id: 'riser', name: 'Riser FX', color: channelColors[2]),
  BrowserSampleVm(id: 'hats', name: 'Hat Loop Tight', color: channelColors[7]),
];
