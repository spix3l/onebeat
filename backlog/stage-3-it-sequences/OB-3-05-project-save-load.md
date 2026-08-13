# OB-3-05 — Project save/load

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature |
| **Priority** | Blocker |
| **Dependencies** | OB-3-01 (ADR-004), OB-3-02 |
| **References** | FR-PRJ-01/02/03, ARCHITECTURE.md §8 |
| **Estimate** | M |

## Context

Implements ADR-004: the text project file + binary sidecars, with canonical formatting for diffability and forward-compatible loading.

## Scope

1. **Writer:** model → canonical `project.json` (per ADR-004's formatter rules: stable ordering, fixed float formatting, one note per line); plugin state chunks → `state/<instance-id>.bin`; atomic save (write-temp-then-rename of the whole bundle) so a crash mid-save never corrupts the previous save.
2. **Loader:** parse + validate; referential integrity check with **specific** recoverable errors (FR-UX-12: "Clip 34 references missing pattern P9 — removed" collected into a load report, not a refusal); unknown fields/entities preserved and round-tripped (forward compat, FR-PRJ-03); schema version gate with a migration hook (identity migration for v1).
3. **Missing-asset handling at load:** missing plugin → OB-2-10 placeholder; missing audio file → offline AudioClip stub retaining the path (full UX in Stage 9).
4. **App integration:** New/Open/Save/Save As with unsaved-changes tracking (dirty flag from the command bus) and native dialogs; recent-projects list; `.obt` bundle association.
5. **Round-trip guarantee:** load → save byte-identical (the canonical-writer test); save → load → deep model equality.

## Acceptance criteria

- [x] Round-trip tests pass: byte-identity and model equality, including a project with unknown future fields injected.
- [x] Kill -9 during save: previous save intact (atomicity test).
- [x] A project with a missing pattern reference loads with the designed report; nothing crashes.
- [x] Git diff of "move one clip" and "add three notes" on a real saved project is small and readable (attached to PR, compared against ADR-004's sample).
- [x] Plugin state round-trips through sidecars (hash-verified per instance).

## Out of scope

- Auto-save (OB-3-06). Consolidation, stem/asset collection (later stages).

## Status — 🟨 partial (13 August 2026)

Scope §1, §2 and §5 are done and green: `engine/src/model/json.{h,cpp}` (the
canonical writer and a parser that keeps integers integral and the locale out of
the file) and `engine/src/model/project_io.{h,cpp}` (writer, forgiving loader,
`Residue` preservation, SHA-256 sidecars, atomic bundle swap). Every acceptance
criterion above is covered by `engine/tests/test_project_io.cpp`.

**Not done, and waiting on `OB-3-09`'s model-backed app:**

- **Scope §4 in full** — New/Open/Save/Save As, the dirty flag from the command
  bus, native dialogs, the recent-projects list and the `.obt` bundle
  association. None of it can exist before the app can hold a project, which is
  the ABI wiring `OB-3-09` brings. This is the same dependency that keeps
  `OB-3-03` open.
- **The host half of scope §3** — the format carries everything OB-2-10's
  missing-plugin placeholder needs (`plugin.id`, `name`, `vendor`, `path_hint`)
  and the loader reports a sidecar that is missing or fails its checksum, but
  nothing yet resolves a loaded instrument against the scan cache to *produce*
  the placeholder. Audio clips already keep their path and stay silent.

Two things were found by implementing this and fixed here rather than deferred:
the worked example's IDs were not legal ULIDs (24 characters, and `O` is not in
Crockford base32), and the format under-specified five fields the model holds
(`note_defaults`, per-instrument routing ports, lane display state, clip `muted`
and the reserved transforms). Both `docs/project-format.md` and the example are
now what the writer actually produces, and a test proves it on every run.
