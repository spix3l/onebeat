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

- [x] All FR-SEQ-02 capabilities present: entry/edit, velocity, length, quantise, scale highlighting.
- [x] Same-sequence proof: rack edits appear live in the roll and vice versa (DM-Q4, widget test).
- [ ] 2,000-note pattern: sustained 120 Hz during scroll + playback in profile mode, on a 120 Hz display, with the frame-time histogram attached. **This is now the only place P1 gets answered** — `OB-0-01` was closed by decision on 13 August 2026 without building the spike, so this criterion inherited it, and failing it is the D3 reversal ADR-001 §Amendment describes rather than a UI defect. Needs debt D1a (ProMotion hardware) resolved first; if it is not, say so here rather than measuring at 60 Hz and calling it done.
- [x] Full walkthrough with no right-click-only actions (FR-UX-17) — now a
      test rather than a walkthrough, see below.
- [x] Matches `onebeat-piano.html` in layout and structure; token lint clean.
      The base palette deliberately still differs — see the closeout.

**In review (14 August 2026).** The roll is built on ABI 1.7's value-addressed
note surface: draw/select/lasso/move/resize/delete/duplicate, velocity strip,
quantise with strength, triplet grids, snap-off modifier, scale highlighting with
a selectable root, smooth zoom and pan, zoom-to-selection, per-(pattern,
instrument) viewport memory, audition on the keyboard and on placement, and a
toolbar carrying every action.

Three layered painters per ADR-001 with every `Paint` built in the constructor.
A 2,000-note fixture paints in **0.22–0.25 ms** against the 8.33 ms 120 Hz frame
(`app/test/stage3_paint_cost_test.dart`). FR-UX-17 is enforced by
`action_reachability_test.dart` rather than walked. A dark golden covers the
surface, and the first one caught a real bug — the grid never filled its
background, so out-of-scale natural rows rendered transparent.

The 120 Hz criterion above stays unticked: this MacBook Air reports a 60 Hz
panel, and OB-3-10's own text forbids measuring at 60 Hz and calling it done.
Debt D1a is unchanged. Detail in [`docs/stage-3-editors.md`](../../docs/stage-3-editors.md).


## Out of scope

- Per-note expression lanes (v1.x, FR-SEQ-10). Generators (FR-SEQ-13, Stage 6+). MIDI import (v1.x).
