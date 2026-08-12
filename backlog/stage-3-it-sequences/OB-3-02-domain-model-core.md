# OB-3-02 — Domain model core: entities and identities

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (engine/model) — architecture-critical |
| **Priority** | Blocker for everything in Stage 3 |
| **Dependencies** | OB-2-11, OB-3-01 (ID scheme) |
| **References** | ARCHITECTURE.md §2–§4 (normative), PRD §7, FR-PRJ-02, R15 |
| **Estimate** | L |

## Context

The heart of the product. ARCHITECTURE.md is **normative**: two orthogonal axes (time: Pattern → PatternClip → ArrangementLane; signal: Instrument → MixerTrack → Master) meeting only at the Instrument. The anti-pattern table (§6) is the review checklist for this and every dependent PR (R15).

## Scope

Implement in `engine/src/model/` (off-audio-thread code; the audio thread only ever sees the flattened schedule):

1. **`Instrument`:** project-global; stable `InstrumentId` (never reused); plugin reference + state ref, name, colour, default note properties, ordered output routing `OutputPort → MixerTrackId` list. (Mixer tracks themselves are stubs until Stage 4: a `MixerTrackId` registry with Master pre-created, so routing fields are real from day one — routing by **stable ID, never index**, D-M1.)
2. **`Pattern`:** stable `PatternId`; **sparse** `map<InstrumentId, NoteSequence>`; name, colour, default length; derived usage count.
3. **`PatternClip`:** references `PatternId` + `ArrangementLaneId`; start, length, source offset, loop mode (DM-Q2), mute flag, transform struct (transpose now; velocity-scale/nudge/probability fields reserved, DM-Q3). **Holds no note data — enforce by construction** (no accessor path to notes via a clip except through the pattern).
4. **`ArrangementLane`:** name, colour, height, **order as a field**, collapse state, event-gate mute, solo; reserved `group_id` (DM-Q1). **No instrument, no effects, no routing** — the type simply has no such fields.
5. **`AudioClip` / `AutomationClip`:** first-class clip types (D-M7): AudioClip references a source file + edit params and routes to a `MixerTrackId` directly; AutomationClip references a parameter target + curve. Stage 3 implements them structurally (schema + model + flattener awareness); full behaviour lands in Stage 4 (automation) and Stage 9 (audio editing).
6. **Model invariants module:** deleting an instrument cascades its sequences out of all patterns (with an impact report object for the UI: "used in N patterns" — §3.1); deleting a pattern reports/deletes its clips; referential integrity checked in debug builds after every command.
7. **Change notification:** model emits fine-grained change events (entity + field granularity) consumed by the flattener (OB-3-04) and the UI stores.

## Acceptance criteria

- [ ] All entities implemented exactly per ARCHITECTURE.md §3–§4; a review pass walks the §6 anti-pattern table item by item and records "not present" for each (R15).
- [ ] IDs are never reused across create/delete cycles (test: 10k create/delete, no collision, tombstone/counter persisted).
- [ ] Instrument delete produces a correct impact report and cascades correctly (test with a pattern matrix).
- [ ] `ArrangementLane ↔ MixerTrack` relationship is impossible to express in the type system (§4: "none. Deliberate. Do not add.").
- [ ] Invariant checker runs in debug/CI after every model mutation in tests.
- [ ] Human review completed with ARCHITECTURE.md open.

## Out of scope

- Mixer track behaviour (chains, gain — Stage 4). Serialization (OB-3-05). Flattening (OB-3-04).
