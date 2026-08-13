# OB-3-08 — NoteSequence: one representation, edit operations

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (model) |
| **Priority** | Blocker for rack + piano roll |
| **Dependencies** | OB-3-02, OB-3-03 |
| **References** | DM-Q4, FR-SEQ-03, FR-SEQ-01/02 (model halves) |
| **Estimate** | M |

## Context

DM-Q4 resolved: **one** `NoteSequence` shared by step sequencer and piano roll — a step is a quantised note. Two representations would need permanent reconciliation. This ticket builds that single model plus the edit operations both editors call.

## Scope

1. **Note record:** start (ticks, PPQ decided and documented — e.g. 960), length, key, velocity; reserved per-note fields (pan, pitch offset, mod — FR-SEQ-10, v1.x) in the schema.
2. **Sequence container:** ordered, overlap-permitted; efficient range queries for painting (sorted structure adequate for ~10k notes; measured).
3. **Edit operations (all as OB-3-03 commands):** add/remove; move/resize with grid snapping; velocity set/scale; quantise (grid + strength); transpose selection; duplicate selection; select by range/lasso predicate.
4. **Step-view mapping (the DM-Q4 proof):** "step at (row, index)" ⇔ "note at quantised position with default length/velocity"; toggling a step adds/removes exactly such a note; **notes not on the step grid remain untouched and visible as "off-grid" indicators in the rack** (rule documented and tested — this is where clones usually fork representations).
5. **Default note properties** from the instrument (velocity etc., §3.1) applied on entry.

## Acceptance criteria

- [x] A sequence edited in the piano roll shows correctly in the step grid and vice versa; the off-grid rule behaves as documented (round-trip tests).
- [x] All edit ops undoable, coalescing per gesture.
- [x] Quantise with strength verified against hand-computed fixtures.
- [x] 10k-note sequence: range query + edit latency measured within the UI frame budget.

## Close-out evidence

Completed 13 August 2026 on branch `ob-3-08-notesequence-editing`.

- `model/note_edit.h` is the shared editor API: range/lasso selection; snapped
  move/resize; velocity set/scale; strength quantise; transpose; duplicate; and
  instrument-default note entry. Every mutation returns an OB-3-03 command.
- `inspectStep` and `toggleStep` implement DM-Q4 directly over `NoteSequence`.
  The round-trip test proves an off-grid piano-roll note remains present and is
  reported separately through two rack toggles.
- Replacement commands coalesce `A → B → C` into one undo entry. Batch edits
  validate atomically and use indexed removal rather than repeated vector
  erasure.
- `test_note_edit.cpp` covers every operation and hand-computed 50% quantise
  fixtures. Its 10,000-note test measured a 0.09 ms range query and 1.11 ms full
  edit in Debug against the 16.667 ms UI-frame budget; the continuing benchmark
  contract is documented in `docs/note-sequence-editing.md`.
- The complete local CI matrix is green: Debug, Release, ASan/UBSan, TSan,
  RTSan, clang-tidy, clang-format, seam/license/token checks, Flutter analyze,
  and Flutter tests.

## Out of scope

- The widgets (OB-3-09/10). Per-note property *behaviour* (v1.x). MIDI import/export (v1.x).
