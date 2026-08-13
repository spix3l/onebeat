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
- [ ] Undo of an edit audibly reverts during playback within one flatten cycle.

**Status (13 August 2026): model layer landed, stage-level wiring pending.**
Scope 1–3 and 6 are implemented in `engine/src/model/command.h`,
`commands.h/.cpp` and `engine/tests/test_model_commands.cpp`; the seam rule
in `tools/seam_check.sh` §5 is what makes the command layer the only mutation
path. Scope 4 (ABI + ⌘Z wiring) waits for the first model-backed UI
(`OB-3-09`), and scope 5 with AC 5 wait for the flattener (`OB-3-04`) — there
is nothing to re-flatten or hear yet. The fuzz run is 100,000 operations,
86,666 applied, and takes 52 s under ASan.

## Out of scope

- Persistent (cross-session) undo history. Selective/branched undo.
