# OB-3-03 — Undo/redo command system

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (model) |
| **Priority** | Blocker — every mutation from now on goes through it |
| **Dependencies** | OB-3-02 |
| **References** | FR-PRJ-08, FR-UX-21 |
| **Estimate** | M |

## Context

Unlimited undo/redo across all operations (FR-PRJ-08); undo covers every destructive action so exploration is safe (FR-UX-21). Retrofit is miserable — so the command system is the *only* mutation path from the first sequencer feature.

## Scope

1. **Command pattern:** every model mutation is a `Command` (apply/revert) executed via a single `CommandBus`; direct model mutation outside commands is compile-visible (mutating APIs private to the command layer).
2. **History:** unbounded stack (memory-bounded by command granularity, not snapshots); **coalescing** for continuous gestures (drag = one entry, knob twiddle = one entry) via explicit transaction begin/commit from the UI; named entries for UI display ("Delete 3 notes").
3. **Cross-cutting captures:** commands that cascade (instrument delete removing sequences from N patterns) capture the full inverse; plugin-state-affecting commands snapshot state chunks as needed.
4. **ABI/UI:** undo/redo commands + history-top names in the snapshot/event channel; ⌘Z/⇧⌘Z wired app-wide.
5. **Consistency with flattening:** every committed command triggers incremental re-flatten (OB-3-04) — one code path, no special cases.
6. Fuzz test: random command sequences interleaved with undo/redo; model equality (deep compare + invariant check) against a replayed reference after every step.

## Acceptance criteria

- [x] Every Stage 3 mutation (notes, patterns, clips, lanes, instruments, transport-agnostic settings) is undoable/redoable; a checklist in the PR enumerates them.
- [x] Drag/paint gestures coalesce to single history entries.
- [x] Instrument delete + undo restores sequences in all affected patterns byte-identically.
- [x] Fuzz test (≥100k ops) passes under ASan.
- [x] Undo of an edit audibly reverts during playback within one flatten cycle.

**Done (13 August 2026).** Scope 1–3 and 6 live in
`engine/src/model/command.h`, `commands.h/.cpp` and the 100,000-operation fuzz;
`tools/seam_check.sh` §5 keeps the command layer the only mutation path. ABI
1.6 exposes undo/redo availability and history-top names, the shell binds
⌘Z/⇧⌘Z app-wide, and the rack also keeps visible named controls. Every model
command, transaction commit, undo and redo flushes the `FlattenScheduler` and
publishes the resulting immutable schedule. The ABI test drains prior events,
undoes a live rack sequence edit, and requires the schedule-published event
before the call returns: one flatten cycle, not a later UI poll.

The scope's suggestion to put history names in the frame snapshot was replaced
with allocation-free ABI getters. Names are not frame-rate state, so copying
them through the seqlock snapshot every audio callback would make the real-time
contract worse for no benefit.

## Out of scope

- Persistent (cross-session) undo history. Selective/branched undo.
