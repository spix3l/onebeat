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

- [x] Reference semantics proven end-to-end: one pattern placed as two clips; editing the pattern changes both placements' rendered audio (offline-render test) — **this is the v0.3 exit behaviour**.
- [x] Windowing matrix tested: offset/length/loop combinations against hand-computed expected event lists (event-capture harness from OB-1-13).
- [x] Transpose transform shifts only the transformed clip.
- [x] Boundary note-offs verified — no hanging notes in any windowing case.
- [x] Flatten budget measured on the 1,000-clip synthetic project and recorded.
- [x] Audio thread untouched by this ticket (diff review: no changes under `rt/` paths beyond event types), anti-pattern §6 #7 re-checked.
- [x] Human review completed (R4).

**Notes on the criteria (13 August 2026).**

- **Budget:** met at ordinary density — 1,000 clips / 48,128 events flatten in
  **3.5 ms** in Release. An extreme-density variant (192,512 events) takes
  10.4 ms and is recorded as the known ceiling. Both rows, the profile and the
  trigger conditions for opening an incremental-re-flatten ticket are in
  [`docs/flattener-budget.md`](../../docs/flattener-budget.md). No such ticket is
  opened yet, because the budget holds where it matters.
- **Audio thread untouched:** nothing under `core/rt/` changed and
  `ScheduleEvent` is unchanged. The one edit outside `model/` is a `reserve()`
  on `ScheduleBuilder`, which is the off-thread builder, not RT code.
  Anti-pattern §6 #7 re-checked: `model/` is unreachable from the audio thread.
- **Incremental re-flatten:** `FlattenScheduler` subscribes to the change bus
  and re-flattens the whole project when anything changed. Publishing it into a
  running engine during playback is ABI work and lands with `OB-3-09`; the
  edit-during-playback criterion of `OB-3-03` AC 5 waits for that.
- Automation clips flatten their points into `ParamValue` events; curve shapes
  and interpolation are Stage 4.

## Out of scope

- Probability/velocity-scale UI + runtime semantics (v1.x per DM-Q3 — fields flatten as no-ops until then). Tempo changes (FR-SEQ-11, v1.x).
