# OB-3-01 — ADR-004: project file format

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Design / ADR |
| **Priority** | Blocker for all Stage 3 persistence |
| **Dependencies** | OB-2-11 |
| **References** | OQ-2, FR-PRJ-01/02/03, ARCHITECTURE.md §8 |
| **Estimate** | M |

## Context

FR-PRJ-01: human-readable, diffable, text-based project format with a binary sidecar for plugin state. OQ-2 (TOML vs JSON vs custom) is due now. ARCHITECTURE.md §8 fixes the shape (top-level maps keyed by ID, lane order as a field, clips reference lanes) and the design rules (stable never-reused IDs, sidecar by reference).

## Scope

Write `docs/adr/ADR-004-project-format.md` deciding:

1. **Syntax:** evaluate against criteria — diff quality for the note-heavy parts (a pattern edit should diff as a few lines), hand-editability, comment support, parser availability under MIT-compatible licences, streaming/size behaviour for a 10k-note project. Candidates: TOML (comments, but nested arrays of notes get awkward), JSON (ubiquitous, no comments, good diffs with stable key ordering + one-note-per-line formatting), JSON5/custom. **Recommendation to validate: JSON with a canonical formatter** (sorted keys, fixed number formatting, one note per line) — diffability comes from canonical formatting more than from syntax.
2. **Layout:** single file vs directory bundle. Recommendation: a `.onebeat` **directory bundle**: `project.json` (text, diffable), `state/<instance-id>.bin` sidecars (plugin chunks), `assets/` (consolidation target for FR-PRJ-05 later). Record trade-offs (bundle vs flat for git users).
3. **Schema:** entities per ARCHITECTURE.md §8 (`instruments`, `patterns`, `lanes`, `clips`, `mixer_tracks`); ID scheme (ULID-style monotonic, never reused — deletion tombstones or a persisted counter, decide); note encoding (compact per-note record: start, length, key, velocity, later per-note props); `group_id` reserved on lanes (DM-Q1); versioning field + **forward-compatible loading rules** (unknown fields preserved on round-trip, unknown entity types warned and retained).
4. **Canonical writer rules:** ordering, formatting, float precision — specified so two saves of the same model are byte-identical.
5. **Schema documentation:** generated or hand-written schema doc (`docs/project-format.md`) — FR-PRJ-03 requires it documented and versioned.

## Acceptance criteria

- [ ] ADR-004 merged: syntax, layout, ID scheme, versioning and forward-compat rules decided with rationale.
- [ ] A realistic sample project (3 patterns × 4 instruments, 16 clips) written by hand in the format; a simulated "move one clip + edit one pattern" produces a git diff a human can read (attached to the ADR).
- [ ] Round-trip rule specified: load → save is byte-identical; unknown-field preservation specified.
- [ ] `docs/project-format.md` v1 drafted.

## Out of scope

- Implementation (OB-3-05). Consolidation (FR-PRJ-05, later).
