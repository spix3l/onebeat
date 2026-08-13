# Domain-model anti-pattern review

Required by `OB-3-02` AC 1 and by R15: ARCHITECTURE.md §6 lists the seven
mistakes DAW clones make, and every change to `engine/src/model/` is reviewed
against this table item by item. This document records the walk for the initial
implementation and is the checklist to repeat, not a one-time exercise.

Reviewed: `engine/src/model/` at OB-3-02 — `ids.h`, `entities.h`,
`note_sequence.h`, `changes.h`, `project.h/.cpp`, `invariants.h/.cpp`.
Date: 13 August 2026. Reviewer: implementation review with ARCHITECTURE.md open
(R4 delegated).

| # | Mistake | Verdict | Where it is prevented |
|---|---|---|---|
| 1 | Pattern belongs to a lane | **not present** | `Pattern` has no lane field. Lanes are reached only from `Clip::lane`, and a pattern does not know its clips. A pattern holds `map<InstrumentId, NoteSequence>` — a horizontal slice — so one pattern spans four instruments in the same record (`entities.h`, `Pattern`) |
| 2 | Lane is a signal path | **not present** | `ArrangementLane` has no instrument, no effects, no routing, no gain. Not empty-for-now: there is no field, and `TypedId<ArrangementLane>` is not convertible to or from `MixerTrackId`, so the relationship ARCHITECTURE.md §4 forbids cannot be spelled. Enforced by `static_assert` in `ids.h` and by the test "Lane order is a field, so reordering touches no clip" |
| 3 | Clip copies pattern data | **not present** | `PatternSource` holds a `PatternId` and nothing else. `Clip` exposes no mutable path to notes; notes are reachable only via `Project::patterns()`. Test: "Editing a pattern is seen by every clip that references it" |
| 4 | Instrument ↔ mixer track hardwired 1:1 | **not present** | `Instrument::routing` is a vector of `OutputRoute{port, MixerTrackId}` and several instruments may name the same track. D-M2's auto-created track is a *default*, not a binding. Test: "Many instruments share one mixer track" (8 → 1) |
| 5 | Instruments scoped per pattern | **not present** | Instruments live in `Project::instruments_`; a pattern references them by ID. The consequence is implemented rather than hidden: `deleteInstrument` removes the instrument's notes from every pattern at once and `instrumentImpact` reports the count first (ARCHITECTURE.md §3.1). Test: "Deleting an instrument reports and removes its notes from every pattern" |
| 6 | Note data stored inside clips in the project file | **not present** | ADR-004 §5 and `docs/project-format.md` §5.4: a clip serialises to five fields and a source reference. Notes live once, in the pattern. The evidence is the worked diff — moving a clip is one changed line |
| 7 | Audio thread traverses the reference graph | **not present** | Nothing in `model/` is reachable from the audio thread. The model is off-thread by construction — `std::map`, `std::string`, allocation everywhere — and the audio thread reads only the flattened schedule published by `core/rt/publisher.h`. The flattener (OB-3-04) is the one component that reads the model and writes the schedule |

## Two things this review flags rather than passes

1. **`Project::adopt()` bypasses the invariant checker.** It exists for the
   load path (OB-3-05), which must build a possibly-broken model from a file
   and *report* rather than abort. That makes it the one hole in "every
   mutation is validated", and it is deliberate. The rule for reviewers: only
   the loader and tests may call it, and every caller runs
   `checkReferentialIntegrity` immediately afterwards.
2. **Deleting a lane releases the lanes it grouped rather than deleting them**
   (`deleteLane`). DM-Q1 is still open, so the model takes the behaviour that
   cannot lose work. Revisit when folder lanes are decided.

## Deviation from the ticket

`OB-3-02` AC 2 asks for "no collision, tombstone/counter persisted".
[ADR-004](adr/ADR-004-project-format.md) §4 — written after the ticket — chose
ULIDs precisely so that never-reuse needs neither a tombstone list nor a
persisted counter: uniqueness is a property of the identifier. The test the AC
asks for is implemented as written (10,000 create/delete cycles, no collision);
the persisted-bookkeeping half is not implemented because there is nothing to
persist.
