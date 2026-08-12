# OB-1-11 — Flutter app shell with transport bar and live meter at 120 Hz

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (UI) |
| **Priority** | Blocker — carries the v0.1 exit proof |
| **Dependencies** | OB-1-03 (tokens), OB-1-10 (FFI) |
| **References** | PRD §10 v0.1 ("FFI contract proven with a live meter at 120 Hz"), FR-UX-05, FR-UX-07, R6, R13; design screens `onebeat-shell.html` (chrome only) |
| **Estimate** | M |

## Context

v0.1's exit includes "a meter moves smoothly" — the end-to-end proof that engine → snapshot → FFI → CustomPainter holds 120 Hz with real machinery, not spike code. The shell here is a skeleton of the designed layout: real top bar, empty center.

## Scope

1. **App shell:** single window matching the designed chrome (top bar with transport controls + BPM + time display, status bar), all styling via tokens (OB-1-03), Martian Mono for BPM/timecode. Center area is an intentionally-designed placeholder (not a TODO — an empty state per FR-UX-13, inviting "press Play").
2. **Transport controls:** play/stop buttons and tempo field wired through `EngineClient`; keyboard: spacebar = play/stop (with focus handling done properly from the start, FR-UX-24); a test button/key triggering sampler notes so sound is demonstrable.
3. **Live meter:** master peak/RMS stereo meter as a `CustomPainter` fed by the per-frame snapshot; conventional green–amber–red segments (semantic tokens); peak-hold with decay; ballistics computed from snapshot timestamps, not frame count (frame drops must not change decay rates).
4. **Playhead/time display:** bars.beats.ticks + minutes:seconds from the snapshot, Martian Mono, no jitter (values derived from the same snapshot the meter used).
5. **Performance instrumentation:** frame-timing overlay toggle (debug builds) reporting build/raster times and dropped-frame count — kept for all future UI work.

## Acceptance criteria

- [ ] Pressing play: sampler note plays, meter responds, time display advances — full loop demonstrated.
- [ ] **60 s of playback with the meter live on a 120 Hz display: zero dropped frames in profile mode** (recorded histogram attached to the PR). This is the v0.1 exit-proof measurement.
- [ ] No per-frame allocation in the meter paint path (DevTools verified).
- [ ] All colours/spacing/type via tokens; token lint passes; meter uses semantic meter colours.
- [ ] Spacebar toggles transport regardless of which control was last clicked.

## Out of scope

- Arrangement canvas, browser, channel rack (Stage 3). Menus and preferences. Meter in the mixer (Stage 4).
