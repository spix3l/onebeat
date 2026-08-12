# OB-1-07 — Flattened schedule: immutable publish via atomic swap

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (engine) — architecture-critical |
| **Priority** | Blocker — "established in v0.1, because retrofitting it means rewriting the sequencer" |
| **Dependencies** | OB-1-06 |
| **References** | FR-ENG-09, ARCHITECTURE.md §7, PRD §7, anti-pattern #7 |
| **Estimate** | L |

## Context

The single non-deferrable architectural decision (ARCHITECTURE.md §10): edits mutate the model off-thread; a flattening pass resolves references into an immutable, time-ordered schedule; the schedule is published by atomic pointer swap; the audio thread reads only the schedule; retired schedules are freed on a non-RT thread. In Stage 1 the "model" is trivial (a hardcoded/test note list), but the **machinery must be real and final**.

## Scope

1. **Schedule data structure** (`engine/src/core/schedule.h`): immutable after construction; flat, time-ordered arrays of events with absolute sample positions, resolved to `InstrumentId` and parameter targets; designed for cache-friendly linear scanning per block. Event types in v0.1: note-on, note-off, tempo marker. Structured so Stage 3 adds types (automation points, clip windows) without changing the publish machinery.
2. **Publisher:** builder runs on a worker thread; publish = single `std::atomic<Schedule*>` swap (or epoch/ABA-safe equivalent — decide and document); audio thread loads the pointer once per block.
3. **Retire path:** superseded schedules queue to a non-RT reclamation thread; freed only after the audio thread can no longer observe them (grace period or epoch counter — document the proof).
4. **Playback cursor:** block-level scan of the schedule keyed by transport position, emitting events with intra-block offsets to instruments; loop-region wrap handled.
5. **Tests:** TSan-verified swap-under-playback stress test (publisher hammering swaps while null-backend playback runs); RTSan clean; a determinism test (same schedule + same transport ⇒ identical event stream).

## Acceptance criteria

- [ ] Audio thread contains no reference-graph traversal and no locks; reads the schedule via one atomic load per block (code-review checked against ARCHITECTURE.md §6 #7).
- [ ] Stress test: 1,000+ publishes during continuous playback — TSan clean, no glitches (measured as no missed/duplicated events in the null backend capture).
- [ ] Retired schedules are provably freed (leak check under ASan across the stress test) and never freed early.
- [ ] Determinism test passes.
- [ ] Human review completed (R4) with the §7 checklist attached to the PR.

## Out of scope

- The real flattener from the domain model (OB-3-04). Automation events (Stage 3/4).
