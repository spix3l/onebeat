// Playlist fixtures (UI-B-08) — the nine clips of `screens/arrangement.png`.
//
// Bars and lengths were read off the PNG at the export's 2× scale: four ruler
// bars span 153 logical px, so a bar is 38.3, and the lanes are on a 50px
// pitch. The positions are rounded to the nearest quarter bar — the mockup's
// clips do not sit on bar lines, and rounding them onto one would be a
// different arrangement.
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/playlist/clip_card.dart';
import 'package:onebeat/src/features/playlist/playlist_canvas.dart';

final List<ClipVm> demoClips = <ClipVm>[
  ClipVm(
    id: 1,
    name: 'Intro Kick',
    duration: '0:08',
    color: channelColors[0],
    startBar: 0.5,
    lengthBars: 4.5,
    lane: 0,
  ),
  ClipVm(
    id: 2,
    name: 'Kick Var B',
    duration: '0:06',
    color: channelColors[0],
    startBar: 6,
    lengthBars: 4,
    lane: 0,
  ),
  ClipVm(
    id: 3,
    name: 'Sub Bass',
    duration: '0:12',
    color: channelColors[3],
    startBar: 5.5,
    lengthBars: 7,
    lane: 1,
  ),
  ClipVm(
    id: 4,
    name: 'Lead Riff',
    duration: '0:06',
    color: channelColors[2],
    startBar: 1.5,
    lengthBars: 3.5,
    lane: 2,
  ),
  ClipVm(
    id: 5,
    name: 'Lead Riff B',
    duration: '0:08',
    color: channelColors[4],
    startBar: 6,
    lengthBars: 4.5,
    lane: 2,
  ),
  ClipVm(
    id: 6,
    name: 'Lead Riff C',
    duration: '0:05',
    color: channelColors[2],
    startBar: 11.25,
    lengthBars: 3,
    lane: 2,
  ),
  ClipVm(
    id: 7,
    name: 'Vocal Chop',
    duration: '0:09',
    color: channelColors[5],
    startBar: 10.25,
    lengthBars: 5.25,
    lane: 3,
  ),
  ClipVm(
    id: 8,
    name: 'Riser',
    duration: '0:04',
    color: channelColors[1],
    startBar: 4,
    lengthBars: 2.25,
    lane: 4,
  ),
  ClipVm(
    id: 9,
    name: 'Reverse Crash',
    duration: '0:05',
    color: channelColors[6],
    startBar: 13.5,
    lengthBars: 3.5,
    lane: 4,
  ),
];

/// The playhead sits just short of bar 10 in the mockup.
const int demoPlayheadBar16ths = 142;

final PlaylistVm demoPlaylist = PlaylistVm(
  clips: demoClips,
  pxPerBar: 38.3,
  playheadBar16ths: demoPlayheadBar16ths,
  headerRight: '124 BPM · 4/4',
);
