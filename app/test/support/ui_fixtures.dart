// The shared demo-project fixture (UI-A-02 §2).
//
// Every screen golden renders the same story — the same transport, channels,
// patterns, playlist and mixer — so the goldens read like the mockups rather
// than like whatever each ticket happened to invent. Values are verbatim from
// `ui-files/screens/`, and colour indices are 1-based channel colour indices
// into `ColorTokens.channelColors` (so `colourIndex: 1` is c1).
//
// These are plain records and lists on purpose: each C ticket defines its own
// view-model and builds it from these constants, so no ticket can drift onto a
// different demo project.

/// A channel strip: display name, instrument type and channel colour index.
typedef ChannelFixture = ({
  String name,
  String type,
  int colourIndex,
  bool powered,
});

/// The eight channel strips, verbatim from the mockup. `Shaker` is powered off.
const List<ChannelFixture> demoChannels = <ChannelFixture>[
  (name: 'Kick 808', type: 'Sampler', colourIndex: 1, powered: true),
  (name: 'Snare', type: 'Sampler', colourIndex: 6, powered: true),
  (name: 'Hats', type: 'Synth', colourIndex: 2, powered: true),
  (name: 'Sub Bass', type: 'Reese CLAP', colourIndex: 3, powered: true),
  (name: 'Soft Keys', type: 'EP', colourIndex: 5, powered: true),
  (name: 'Pluck Lead', type: 'Synth', colourIndex: 4, powered: true),
  (name: 'Shaker', type: 'Sampler', colourIndex: 7, powered: false),
  (name: 'Open Hat', type: 'Sampler', colourIndex: 8, powered: true),
];

/// Transport readouts, verbatim from the mockup top bar.
const String demoBpm = '124.00';
const String demoSig = '4/4';
const String demoPosition = '02:01:218';
const String demoClock = '14:02';
const String demoWindowTitle = 'ONEBEAT / v0.3 SEQUENCES';

/// The pattern in the browser. `Main Groove 4×` holds the Soft Keys piano roll
/// and a three-times Bass Motif.
const String demoPatternName = 'Main Groove';
const String demoPatternLength = '4×';
const String demoPatternContents = 'Soft Keys piano roll · Bass Motif 3×';

/// A browser folder: display name and item count, when the mockup shows one.
typedef BrowserFolderFixture = ({String name, int? count});

/// Browser folders, verbatim from the mockup.
const List<BrowserFolderFixture> demoBrowserFolders = <BrowserFolderFixture>[
  (name: 'Packs', count: 12),
  (name: 'Current Project', count: null),
  (name: 'Drums', count: 340),
  (name: 'Synths', count: null),
];

/// A playlist clip: display name, duration label and channel colour index.
typedef ClipFixture = ({String name, String duration, int colourIndex});

/// Playlist clips, verbatim from the mockup. Colour indices follow
/// `ui-files/screens/arrangement.png`: kick coral (c1), sub bass teal (c4),
/// lead riff lime (c3), vocal chop pink (c6), riser amber (c2).
const List<ClipFixture> demoPlaylistClips = <ClipFixture>[
  (name: 'Intro Kick', duration: '0:08', colourIndex: 1),
  (name: 'Kick Var B', duration: '0:06', colourIndex: 1),
  (name: 'Sub Bass', duration: '0:12', colourIndex: 4),
  (name: 'Lead Riff', duration: '0:06', colourIndex: 3),
  (name: 'Lead Riff B', duration: '0:08', colourIndex: 3),
  (name: 'Lead Riff C', duration: '0:05', colourIndex: 3),
  (name: 'Vocal Chop', duration: '0:09', colourIndex: 6),
  (name: 'Riser', duration: '0:04', colourIndex: 2),
  (name: 'Reverse Crash', duration: '0:05', colourIndex: 5),
];

/// A mixer track: display name, bus it routes into (null for the master), and
/// the selected/sidechain flags the mockup shows on the Drums Bus.
typedef MixerTrackFixture = ({
  String name,
  String? route,
  bool selected,
  bool sidechain,
});

/// Mixer tracks, verbatim from the mockup. The MASTER track routes nowhere.
const List<MixerTrackFixture> demoMixerTracks = <MixerTrackFixture>[
  (name: 'Kick 808', route: 'Drums', selected: false, sidechain: false),
  (name: 'Snare', route: 'Drums', selected: false, sidechain: false),
  (name: 'Hats', route: 'Drums', selected: false, sidechain: false),
  (name: 'Clap', route: 'Drums', selected: false, sidechain: false),
  (name: 'Drums Bus', route: 'Master', selected: true, sidechain: true),
  (name: 'Sub Bass', route: 'Bass', selected: false, sidechain: false),
  (name: 'Soft Keys', route: 'Music', selected: false, sidechain: false),
  (name: 'MASTER', route: null, selected: false, sidechain: false),
];

/// The master level readout, verbatim from the mockup.
const String demoMasterLevel = '0.0 dB';
