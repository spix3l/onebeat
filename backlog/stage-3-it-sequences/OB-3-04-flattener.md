# OB-3-04 — The flattener: model → schedule

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (engine) — architecture-critical |
| **Priority** | Blocker |
| **Dependencies** | OB-3-02, OB-1-07 (publish machinery) |
| **References** | ARCHITECTURE.md §7, FR-ENG-09, DM-Q2, DM-Q3, FR-SEQ-07/08 |
| **Estimate** | L |

## Context

The bridge between the reference-heavy editing model and the flat immutable schedule the audio thread reads (OB-1-07's machinery, until now fed by test data). Resolves every `PatternClip → Pattern → (InstrumentId, NoteSequence)` reference off-thread into absolute-time events.

## Scope

1. **Resolution:** for each unmuted clip on each unmuted lane (lane mute = event gate, D-M4; solo logic included): resolve pattern references; apply **clip windowing** — source offset, length, loop mode (DM-Q2): a clip shorter than its pattern truncates, a longer one loops per its loop mode; apply **non-destructive transforms** — transpose now, velocity-scale/nudge/probability structurally supported (DM-Q3); emit note events at absolute sample positions via the `TimeMap` (OB-1-09).
2. **Note-off correctness at boundaries:** notes truncated by clip end/window end emit note-offs at the boundary; overlapping identical notes from stacked clips resolved by a documented rule.
3. **Incremental re-flatten:** change events (OB-3-02) mark dirty regions; the flattener rebuilds affected spans (or, v0.3-acceptably, rebuilds whole but fast — budget: <10 ms for a 1,000-clip project; measure and record; incremental optimization ticketed if exceeded). Publishes via the OB-1-07 swap; **edit-during-playback is glitch-free and takes effect within one block + one flatten cycle.**
4. **Automation groundwork:** AutomationClip curves flatten into the parameter events of OB-2-09 (structural now, exercised fully in Stage 4).
5. **Determinism:** same model ⇒ identical schedule bytes (hashable), enabling golden tests.

## Acceptance criteria

- [ ] Reference semantics proven end-to-end: one pattern placed as two clips; editing the pattern changes both placements' rendered audio (offline-render test) — **this is the v0.3 exit behaviour**.
- [ ] Windowing matrix tested: offset/length/loop combinations against hand-computed expected event lists (event-capture harness from OB-1-13).
- [ ] Transpose transform shifts only the transformed clip.
- [ ] Boundary note-offs verified — no hanging notes in any windowing case.
- [ ] Flatten budget measured on the 1,000-clip synthetic project and recorded.
- [ ] Audio thread untouched by this ticket (diff review: no changes under `rt/` paths beyond event types), anti-pattern §6 #7 re-checked.
- [ ] Human review completed (R4).

## Out of scope

- Probability/velocity-scale UI + runtime semantics (v1.x per DM-Q3 — fields flatten as no-ops until then). Tempo changes (FR-SEQ-11, v1.x).
