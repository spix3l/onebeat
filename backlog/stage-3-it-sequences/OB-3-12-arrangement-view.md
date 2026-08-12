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

- [ ] Build an 8-bar arrangement (multiple clips, two referencing the same pattern) entirely by drag; it plays correctly; **moving a clip between lanes changes nothing audible** (offline-render equality test — the model's critical negative made testable).
- [ ] Lane mute stops future events from that lane's clips (event gate, not audio fade — verified by event capture); solo isolates.
- [ ] All clip/lane operations undoable, gesture-coalesced.
- [ ] 120 Hz during playback with a 200-clip arrangement: zero dropped frames (profile run).
- [ ] Saturated random clip colours vs chrome: side-by-side screenshot review against the design (§15.3 check) attached.
- [ ] Token lint clean; FR-UX-17 walkthrough recorded.

## Out of scope

- Audio/automation clip behaviour (Stages 4/9). Track grouping (v1.x). Time-signature ruler complexity (v1.x).
