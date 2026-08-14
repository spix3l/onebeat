# UI-B-08 — Playlist pieces: ruler, clip cards, playhead

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02 |
| **Reference** | workspace of `ui-files/screens/arrangement.png` |
| **Target files** | `app/lib/src/features/playlist/` — `timeline_ruler.dart`, `clip_card.dart`, `playlist_canvas.dart`; tests `app/test/features/playlist/playlist_pieces_golden_test.dart` |
| **Estimate** | M |

## Context

The arrangement mockup shows a free-form playlist: a bar ruler (1,5,9,…33), coloured clip cards on lanes, an accent playhead. The old `arrangement.dart` is store-bound; build fresh in `features/playlist/`.

## Scope

1. **Vm**: `PlaylistVm{List<ClipVm> clips, double pxPerBar, int? playheadBar16ths, String headerTitle /* 'PLAYLIST' */, String headerRight /* 'Untitled.onebeat · 124 BPM · 4/4' */}`; `ClipVm{int id, String name, String duration /* '0:08' */, Color color, double startBar, double lengthBars, int lane, bool selected}`.
2. **`PlaylistRuler`** — top row: bar numbers every 4 bars in dim mono, hairline baseline, faint vertical gridlines continuing down the canvas.
3. **`ObClipCard`** — rounded rect filled with the clip colour, darker text: name (semibold 14) + mono duration below; slight radius (~10); selected = brighter outline. Colours in the mockup come from `channelColors` (`Intro Kick` coral, `Sub Bass` teal, `Lead Riff` lime, `Vocal Chop` pink, `Riser` amber, …).
4. **`PlaylistCanvas`** — positions cards from `(startBar, lane)` on the gridline background, draws the accent playhead line over everything, exposes `onClipTap(id)`, `onBackgroundTap(bar, lane)`.
5. **`PlaylistHeader`** — `PLAYLIST` micro-caps left, dim right caption.
6. Golden `playlist_body_dark` (1600×860) reproducing the mockup's 9 clips at their positions (transcribe approximate bars/lanes from the PNG; keep fixed in the fixture) with playhead ~bar 10.

## Acceptance criteria

- [ ] Golden reads like the mockup: same clips, colours, ruler numerals 1..33, playhead.
- [ ] Card text stays legible (auto-darkened text colour role on bright fills — token, not literal).
- [ ] Tap callbacks proven with a widget test.
- [ ] analyze + token lint + tests clean.

## Out of scope

Clip drag/resize/duplicate (D-04), lane headers, zoom, selection marquee.
