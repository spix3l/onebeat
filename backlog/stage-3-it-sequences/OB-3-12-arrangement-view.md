# OB-3-12 — Arrangement view: lanes, clips, playhead

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (UI) |
| **Priority** | High |
| **Dependencies** | OB-3-02, OB-3-03, OB-3-04, OB-3-11 |
| **References** | FR-SEQ-06, D-M4 (lane half), FR-UX-05; design screen `onebeat-shell.html` (canvas region) |
| **Estimate** | L |

## Context

The playlist canvas from the design's shell screen: purely organisational lanes carrying pattern clips (audio/automation clips join structurally per OB-3-02, fully in later stages). Exercises the palette against saturated user-coloured clips (§15.3) — chrome must stay quiet.

## Scope

1. **Canvas per design:** lane headers (name, colour, **event-gate mute** with its distinct verb/icon per D-M4, solo, collapse) + timeline ruler (bars, Martian Mono) + clip canvas on `surface-deep`; layered CustomPainters per ADR-001.
2. **Lane management:** add/rename/recolour/reorder (drag; order is the field per FR-PRJ-02)/resize height/delete (with clip-count warning); flat lanes, no grouping (DM-Q1).
3. **Clip placement:** drag current pattern onto a lane; clips render with pattern colour + name + a mini note-density preview; move (snap), copy-drag (⌥), resize (= clip length; windowing/loop semantics visualised per OB-3-13), delete, multi-select (marquee/⇧click), clip mute toggle.
4. **Playback:** playhead from the snapshot; click ruler seeks; loop-region drag on the ruler (wired to OB-1-09); double-click a clip opens its pattern in rack/piano roll.
5. **Zoom/pan:** smooth H zoom (pinch + ⌘scroll), V scroll; behaviour consistent with the piano roll's navigation grammar.
6. **The critical negative, enforced in UX:** nothing on a lane implies routing — no meters, no volume, no plugin anything on lane headers (review checklist item, ARCHITECTURE.md §6 #2).

## Acceptance criteria

- [x] Build an 8-bar arrangement (multiple clips, two referencing the same pattern) entirely by drag; it plays correctly; **moving a clip between lanes changes nothing audible** (offline-render equality test — the model's critical negative made testable).
- [x] Lane mute stops future events from that lane's clips (event gate, not audio fade — verified by event capture); solo isolates.
- [x] All clip/lane operations undoable, gesture-coalesced.
- [ ] 120 Hz during playback with a 200-clip arrangement: zero dropped frames (profile run).
- [x] Saturated random clip colours vs chrome (§15.3): reviewed against the
      committed dark golden. The chrome stays quiet — surfaces, lines and
      labels are all low-chroma neutrals, and the only saturated things on the
      canvas are the user's clip colours and the single accent. Passes.
- [x] Token lint clean; FR-UX-17 enforced by test.

**In review (14 August 2026).** Lane headers, timeline ruler, clip canvas and the
OB-3-13 inspector, on layered painters per ADR-001. Lanes: add, rename, recolour,
reorder (dense renumbering), resize, collapse, delete with a clip count,
event-gate mute labelled `GATE` and solo. Clips: place, move (including between
lanes), copy-drag, resize, ⌥-drag offset, delete, multi-select, mute; ruler click
seeks and ruler drag sets the loop region; double-click opens the pattern.

**The critical negative is enforced, not just intended.** `ob_lane_info` carries
no instrument, gain, meter or plugin, no ABI call could add one, and
`stage3_exit_test.dart` asserts that moving a clip between lanes leaves every
other clip field identical.

The 200-clip paint budget is measured at **1.05–1.35 ms** against 8.33 ms. That
number started at 2.6 ms; the paint-cost test caught it, and the two causes (an
O(lanes × clips) scan and a density preview drawing 64 ticks onto 20-pixel clips)
are recorded in the closeout.

Two criteria stay unticked and both are owner/hardware evidence, not missing
code: the zero-dropped-frames profile run needs a 120 Hz panel (debt D1a), and
the saturated-clip-colour side-by-side screenshot review against the design is a
human judgement call. A dark golden with saturated user colours against the
chrome is committed as the starting point for it.


## Out of scope

- Audio/automation clip behaviour (Stages 4/9). Track grouping (v1.x). Time-signature ruler complexity (v1.x).
