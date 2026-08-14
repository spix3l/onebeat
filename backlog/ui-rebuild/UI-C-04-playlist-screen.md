# UI-C-04 — Playlist screen

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-08 (UI-C-01 for full-frame golden) |
| **Reference** | `ui-files/screens/arrangement.png` — open it before writing code |
| **Target files** | `app/lib/src/features/playlist/playlist_screen.dart`, `playlist_screen_vm.dart`; fixture `app/test/features/playlist/fixture.dart`; tests `app/test/features/playlist/playlist_screen_golden_test.dart` |
| **Estimate** | S |

## Scope

1. **`PlaylistScreenVm`** = `PlaylistHeader` vm + `PlaylistVm` (UI-B-08).
2. **`PlaylistScreen`** — workspace-only: header row → ruler → canvas. Thin composition; most work landed in UI-B-08.
3. Fixture: the 9 mockup clips (positions transcribed in UI-B-08's fixture — reuse it), playhead ~bar 10, header right caption `Untitled.onebeat · 124 BPM · 4/4`.
4. Callbacks bubble: `onClipTap`, `onBackgroundTap`.
5. Goldens: `playlist_full_dark` (in `ShellScreen`, PLAYLIST rail… note: the mockup shows MIXER active in the rail with the sample-list browser — match the mockup exactly) vs `screens/arrangement.png`.

## Acceptance criteria

- [ ] Full-frame golden comparable 1:1 with the mockup, including the sample-list browser variant on the left.
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Clip manipulation, lane management (D-04).
