# OB-3-10 — Piano roll UI

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (UI) |
| **Priority** | High |
| **Dependencies** | OB-3-08; ADR-001 canvas strategy |
| **References** | FR-SEQ-02, FR-UX-05, R13; design screen `onebeat-piano.html` |
| **Estimate** | L |

## Context

"The densest view and the one users judge a DAW by" (§15.2). Built on the OB-0-01-validated CustomPainter strategy, editing the same `NoteSequence` as the rack (DM-Q4), for the instrument selected in the current pattern.

## Scope

1. **Canvas per design (`onebeat-piano.html`):** pitch rows with keyboard sidebar (octave labels, black/white shading), bar/beat grid, notes coloured by velocity/selection, playhead; **scale highlighting** (selectable root + scale lighting in-scale rows); velocity editing strip at the bottom.
2. **Note editing:** draw (pencil default; length = last-used), select (click/lasso/marquee), move/resize with snap (grid selector incl. triplets; snap-off modifier), delete, duplicate (⌘D), velocity edit per note + multi-select scale in the strip; all via OB-3-08 commands, gesture-coalesced undo; keyboard: arrows nudge, ⇧arrows transpose octave, standard select-all/copy/paste.
3. **Quantise** action on selection (grid + strength dialog/popover).
4. **Navigation:** smooth zoom (H/V) and pan (trackpad + keyboard), zoom-to-selection; viewport persisted per pattern+instrument during the session.
5. **Audition:** note-on when clicking keys or placing/dragging notes (through the engine preview path, OB-3-07).
6. **Toolbar:** every tool and action visible per FR-UX-17; shortcuts shown in tooltips (FR-UX-18 groundwork).
7. **Performance discipline:** layered painters per ADR-001 (static grid cached, notes layer, playhead layer); zero per-frame allocation; the OB-1-11 frame-timing overlay used during review.

## Acceptance criteria

- [ ] All FR-SEQ-02 capabilities present: entry/edit, velocity, length, quantise, scale highlighting.
- [ ] Same-sequence proof: rack edits appear live in the roll and vice versa (DM-Q4, widget test).
- [ ] 2,000-note pattern: sustained 120 Hz during scroll + playback in profile mode (the OB-0-01 measurement repeated in the real app — regression gate for R13).
- [ ] Full walkthrough with no right-click-only actions (FR-UX-17).
- [ ] Matches `onebeat-piano.html`; token lint clean.

## Out of scope

- Per-note expression lanes (v1.x, FR-SEQ-10). Generators (FR-SEQ-13, Stage 6+). MIDI import (v1.x).
