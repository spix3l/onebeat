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
4. **App integration:** New/Open/Save/Save As with unsaved-changes tracking (dirty flag from the command bus) and native dialogs; recent-projects list; `.onebeat` bundle association.
5. **Round-trip guarantee:** load → save byte-identical (the canonical-writer test); save → load → deep model equality.

## Acceptance criteria

- [ ] Round-trip tests pass: byte-identity and model equality, including a project with unknown future fields injected.
- [ ] Kill -9 during save: previous save intact (atomicity test).
- [ ] A project with a missing pattern reference loads with the designed report; nothing crashes.
- [ ] Git diff of "move one clip" and "add three notes" on a real saved project is small and readable (attached to PR, compared against ADR-004's sample).
- [ ] Plugin state round-trips through sidecars (hash-verified per instance).

## Out of scope

- Auto-save (OB-3-06). Consolidation, stem/asset collection (later stages).
