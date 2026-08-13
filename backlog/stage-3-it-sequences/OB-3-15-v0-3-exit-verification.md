# OB-3-15 — v0.3 exit verification

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Verification |
| **Priority** | Gate (PLAN.md G-C) |
| **Dependencies** | All OB-3-* tickets |
| **References** | PRD §10 v0.3 exit criteria; R15 |
| **Estimate** | S |

## Context

Exit criterion: **"an 8-bar loop created, saved, reopened; the same pattern placed twice updates in both places."**

## Scope — executed and recorded

1. **Manual demo (screen-captured):** from empty project: create 2 instruments (sampler + a CLAP synth) → program a drum pattern in the rack → melody in the piano roll → arrange 8 bars with the drum pattern placed twice → play with loop → edit the drum pattern → **hear/see both placements change** → save → quit → reopen → identical playback (verified against a pre-quit offline render hash).
2. **Automated equivalent** via the OB-3-14 integration driver, kept green permanently.
3. **Domain-model audit (R15):** final walkthrough of ARCHITECTURE.md §6's seven anti-patterns against the shipped code, item by item, recorded in the closeout.
4. **Perf audit:** piano roll and arrangement 120 Hz numbers re-measured on release build; NFR-04 cold-start re-checked.
5. **Data-safety audit:** OB-3-06 fault-injection suite re-run on the release build.
6. `docs/stage-3-closeout.md` with all evidence, debt tickets filed.

## Acceptance criteria

- [x] Both exit behaviours demonstrated by the automated script.
      **The screen capture remains owner evidence.**
- [x] Anti-pattern audit: all seven recorded as absent, with pointers to the enforcing code/tests.
- [ ] Closeout merged; owner signs off; Stage 4 (EPIC-4) breakdown scheduled.
