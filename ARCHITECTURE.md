# OneBeat — Domain Model Specification: Patterns, Instruments and Mixer Tracks

**Version:** 1.0
**Date:** 12 August 2026
**Status:** Proposed — for decision before v0.3
**Companion to:** OneBeat PRD v0.3 (§7.4, §7.6, FR-PRJ-01)

---

## 1. Why this document exists

FL Studio's data model is its most copied and least understood feature. Clones reproduce the *appearance* — a step sequencer, a pattern list, a playlist — while quietly rebuilding the underlying relationships along conventional DAW lines. The result looks like FL and does not behave like it, and the divergence is only discovered once the sequencer is built and expensive to change.

This document fixes the entity relationships before v0.3 rather than during it.

---

## 2. The core principle: two orthogonal axes

OneBeat has **two independent organisational systems** that meet at exactly one point.

| | Time axis | Signal axis |
|---|---|---|
| **Question it answers** | What plays when? | What does it sound like? |
| **Entities** | Pattern, PatternClip, ArrangementLane | Instrument, MixerTrack, Master |
| **User activity** | Composing, arranging | Sound design, mixing |

**The single join:** an `Instrument` receives note events from `Pattern`s and emits audio into `MixerTrack`s. Those two facts are independent of one another.

**The critical negative:** `ArrangementLane` and `MixerTrack` have **no relationship whatsoever**. A lane is not a bus, not a channel, not a signal path. Moving a clip between lanes changes nothing audible.

Every failure mode described in §6 is a version of welding these two axes together.

---

## 3. Entities

### 3.1 Instrument
*(FL Studio: "Channel")*

A plugin instance — built-in or third-party — that turns note events into audio.

- **Scope:** project-global. Not owned by any pattern, lane or mixer track.
- **Identity:** stable `InstrumentId`, never reused after deletion.
- **Holds:** plugin reference, plugin state, name, colour, default note properties (velocity, pan, pitch offset), output routing.
- **Output routing:** an ordered list of `OutputPort → MixerTrackId` mappings. Single-output instruments have one entry; multi-output instruments (drum plugins, multi-timbral samplers) have several.

> **Consequence to surface in UI:** deleting an instrument removes its note data from *every* pattern simultaneously. This is correct behaviour and deeply surprising. The delete confirmation must state how many patterns are affected.

### 3.2 Pattern

A named container of note data, keyed by instrument.

- **Scope:** project-global, referenced by clips.
- **Identity:** stable `PatternId`.
- **Holds:** `map<InstrumentId, NoteSequence>` — **sparse**. A pattern stores sequences only for instruments it actually uses.
- **Also holds:** name, colour, default length, usage count (derived).

A pattern is a **horizontal slice across instruments**, not a container belonging to one. Pattern "Verse Drums" may hold sequences for kick, snare, hat and clap at once.

### 3.3 PatternClip

A placement of a pattern on the timeline.

- **Holds:** `PatternId` (reference), `ArrangementLaneId`, start position, length, source offset, loop behaviour, mute flag, and optional non-destructive transforms.
- **Holds no note data of its own.** Ever.

**Reference semantics are absolute.** Editing a pattern changes every clip that references it. This is FL's behaviour and it is the right default — it is predictable and it is what pattern-based composition is *for*.

**Escape hatch:** a `Make unique` action clones the pattern and repoints this clip to the clone. Explicit, discoverable, undoable.

**Non-destructive clip transforms** (proposed, *Should* priority): transpose, velocity scale, time nudge, probability. These vary a clip's output without cloning the pattern. This is a modern improvement on FL, which forces a clone for any variation.

### 3.4 ArrangementLane
*(FL Studio: "Playlist track")*

A purely organisational horizontal lane in the arrangement.

- **Holds:** name, colour, height, order index, collapse state, event-gate mute, solo.
- **Holds no instrument. No effects. No routing. No audio.**

Two clips on different lanes sound identical. Lanes exist so humans can group work visually — drums on lanes 1–4, bass on 5, vocals on 6–8 — and for nothing else.

### 3.5 MixerTrack
*(FL Studio: "Insert")*

A signal path.

- **Holds:** effect chain (ordered plugin instances), gain, pan, audio-gate mute, solo, sends, output routing to another `MixerTrack` or Master.
- **Receives from:** any number of instrument output ports, and any number of sends.

Many-to-one is a first-class case: eight drum instruments routed into one "Drums" track is a normal workflow, not a workaround.

### 3.6 AudioClip and AutomationClip

Both are placed on `ArrangementLane`s alongside pattern clips.

- **AudioClip** references a source file plus edit parameters (trim, fade, gain, reverse, stretch). It routes to a `MixerTrack` directly — it does not need an instrument.
- **AutomationClip** references a target parameter (`InstrumentId` + parameter, or `MixerTrackId` + parameter, or a plugin parameter) and holds a curve.

> **Divergence from FL:** FL models these as channel types living in the Channel Rack. OneBeat models them as first-class clip types. FL's approach is a historical artefact that confuses users — an "audio clip channel" is a strange object. Separating them costs nothing and removes a conceptual wart.

---

## 4. Relationship summary

| From | To | Cardinality | Notes |
|---|---|---|---|
| Pattern | Instrument | many-to-many | Sparse matrix of note sequences |
| PatternClip | Pattern | many-to-one | **Reference**, never a copy |
| PatternClip | ArrangementLane | many-to-one | Organisational only |
| Instrument | MixerTrack | many-to-one (per port) | Multiple instruments may share a track |
| Instrument | MixerTrack | one-to-many (multi-out) | One port per destination |
| MixerTrack | MixerTrack | many-to-one | Bussing and sends |
| AudioClip | MixerTrack | many-to-one | Direct, no instrument |
| AutomationClip | any parameter | one-to-one | Instrument, mixer or plugin |
| **ArrangementLane** | **MixerTrack** | **none** | **Deliberate. Do not add.** |

---

## 5. Deviations from FL Studio

Each of these is a deliberate departure, justified against PRD goal G6 (learnability) or FR-PRJ-01 (diffable projects).

### D-M1 — Route by stable ID, not integer index
FL assigns instruments to mixer inserts by number ("FX 12"). This is fragile (renumbering breaks assignments), opaque (the number means nothing), and produces poor diffs in a text project format. OneBeat routes by `MixerTrackId` with a user-visible name.

### D-M2 — Auto-create a mixer track per instrument (default on)
FL defaults every new channel to the Master insert, so a beginner cannot EQ their kick without first learning the FX assignment system. This is one of FL's most-cited beginner obstacles and it directly contradicts G6.

OneBeat creates a dedicated mixer track when an instrument is created, named after it. Reassignment and sharing remain fully available — the default simply stops stranding new users. A preference disables it for users who prefer to build routing by hand.

### D-M3 — References by default, `Make unique` on demand
FL has no unlinked pattern instances; Ableton has both linked and unlinked clips and users routinely lose track of which they are editing. OneBeat takes FL's predictable default and adds one explicit command, plus non-destructive clip transforms (§3.3) so that most variation needs no clone at all.

### D-M4 — Two mutes, two names
FL uses "mute" for both playlist-track mute and mixer mute, which do different things. OneBeat distinguishes them:

- **Lane mute — an event gate.** Clips on the lane do not fire. Nothing is scheduled. Upstream.
- **Mixer mute — an audio gate.** The signal is silenced. Downstream, and it silences everything routed there regardless of which lane it came from.

Different verbs in the UI, different icons, and the distinction stated in contextual help (FR-UX-18).

### D-M5 — Pattern-scoped instrument visibility
FL's Channel Rack always shows every channel in the project, which becomes overwhelming past about twenty instruments. OneBeat shows, by default, only the instruments a pattern actually uses, with an explicit **Add instrument to pattern** action and a toggle to show all.

This is a presentation change, not a model change — the underlying sparse matrix is unaltered. It preserves "a pattern is a slice" while reducing visual noise.

### D-M6 — Surface reference impact before editing
Editing a pattern used in forty places, unaware of the other thirty-nine, is a real and common FL frustration. OneBeat:

- shows a usage count on every pattern in the selector,
- highlights all instances in the arrangement when a pattern is selected,
- and warns on destructive edits to patterns used in more than one place.

### D-M7 — Audio and automation clips are not instruments
See §3.6.

---

## 6. Anti-patterns — what clones get wrong

| # | Mistake | Consequence |
|---|---|---|
| 1 | Pattern belongs to a lane | A pattern can hold only one instrument. The pattern-as-slice model is gone; you have rebuilt Ableton with worse ergonomics. |
| 2 | Lane is a signal path | Feels natural to anyone from a linear DAW, and silently destroys the orthogonality. Multi-instrument patterns become impossible to place. |
| 3 | Clip copies pattern data | Editing one placement doesn't update the others. Pattern-based composition loses its entire point. |
| 4 | Instrument ↔ mixer track hardwired 1:1 | Drum busses become impossible; the mixer bloats to one track per sound. |
| 5 | Instruments scoped per pattern | Users expect per-pattern instruments; the model is global. Getting this wrong forces either duplication or a rewrite. |
| 6 | Note data stored inside clips in the project file | Enormous diffs on every arrangement change. Breaks FR-PRJ-01. |
| 7 | Audio thread traverses the reference graph | See §7. |

---

## 7. Real-time architecture consequence

**The audio thread must never traverse `PatternClip → Pattern → Instrument`.**

This model is reference-heavy by design, which is right for editing and wrong for the audio callback. Pointer-chasing through a mutable object graph on the audio thread means cache misses, and — far worse — it means the graph must be locked against concurrent edits.

**Required design:**

1. Edits mutate the project model on the UI/worker thread.
2. A **flattening pass**, off-thread, resolves all references into an immutable, flat, time-ordered **schedule**: absolute-time events already resolved to `InstrumentId` and parameter targets.
3. The schedule is published to the audio thread by atomic pointer swap.
4. The audio thread reads only the schedule. It never sees a Pattern, a PatternClip or a Lane.
5. Retired schedules are freed on a non-real-time thread.

This must be established in v0.1 alongside the FFI contract (PRD NFR-10), because retrofitting it after the sequencer exists means rewriting the sequencer.

---

## 8. Project file implications (FR-PRJ-01)

For a diffable text format, store:

```
instruments:  id → { plugin, state_ref, name, colour, routing[] }
patterns:     id → { name, colour, length, sequences: instrument_id → [notes] }
lanes:        id → { name, colour, height, order }
clips:        id → { pattern_id | audio_ref | automation_target, lane_id, start, length, transforms }
mixer_tracks: id → { name, chain[], gain, pan, sends[], output_id }
```

Design rules:

- **IDs are stable and never reused.** Reusing a deleted ID silently reattaches orphaned references.
- **Lane order is a field on the lane, not implied by array position.** Reordering lanes then rewrites one integer per lane rather than every clip.
- **Clips reference lanes; lanes do not list clips.** Moving a clip touches one record.
- **Plugin binary state lives in a sidecar**, referenced by ID, so the text file stays diffable.

Decided in [ADR-004](docs/adr/ADR-004-project-format.md) (OQ-2) and specified in
[`docs/project-format.md`](docs/project-format.md): JSON in a `.obt` directory
bundle, integer ticks at 960 PPQ, ULID identities, and a canonical writer whose
load → save round-trip is byte-identical. `group_id` is reserved on lanes so
DM-Q1 stays a value change rather than a schema change.

---

## 9. Open decisions

| # | Question | Needed by |
|---|---|---|
| DM-Q1 | Do lanes support nesting or grouping (folder lanes)? Useful at scale; adds tree complexity to a deliberately flat entity | v0.3 |
| DM-Q2 | Can a single pattern clip be *shorter* than its pattern (windowed playback), or only looped/truncated? FL allows both; the interaction with clip transforms needs pinning down | v0.3 |
| DM-Q3 | Are the non-destructive clip transforms in §3.3 v1 scope, or deferred? They are a genuine improvement on FL but they widen the schedule-flattening logic | v0.3 |
| DM-Q4 | Does the step sequencer write into the same `NoteSequence` as the piano roll, or a separate representation? Recommendation: **the same** — a step is a quantised note. Two representations would need permanent reconciliation | v0.3 |
| DM-Q5 | Multi-out instrument ports: fixed at instantiation, or dynamic (CLAP allows port reconfiguration while deactivated)? | v0.5 |

---

## 10. Recommendation

Adopt §2 through §4 as specified, with the deviations in §5. The orthogonality is FL's genuine insight and should be preserved exactly; the deviations are all presentation and ergonomics, none of which touch the underlying relationships.

The one item that cannot be deferred is §7. Everything else in this document can be revised during v0.3. The flattened-schedule architecture cannot.