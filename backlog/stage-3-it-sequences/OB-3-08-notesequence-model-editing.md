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

- [ ] A sequence edited in the piano roll shows correctly in the step grid and vice versa; the off-grid rule behaves as documented (round-trip tests).
- [ ] All edit ops undoable, coalescing per gesture.
- [ ] Quantise with strength verified against hand-computed fixtures.
- [ ] 10k-note sequence: range query + edit latency measured within the UI frame budget.

## Out of scope

- The widgets (OB-3-09/10). Per-note property *behaviour* (v1.x). MIDI import/export (v1.x).
