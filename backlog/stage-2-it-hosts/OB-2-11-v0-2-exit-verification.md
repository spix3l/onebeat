# OB-2-11 — v0.2 exit verification

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Verification |
| **Priority** | Gate (PLAN.md G-C) |
| **Dependencies** | All OB-2-* tickets |
| **References** | PRD §10 v0.2 exit criteria |
| **Estimate** | S |

## Context

Exit criterion: **"15 CLAP plugins load, play, and are crash-contained."** Also confirms gate G-B (notarization) closed.

## Scope

1. **Assemble a 15-plugin CLAP test set** (free/obtainable; mix of instruments and effects; include known heavyweights like Surge XT and Vital-class synths, and at least one GUI-less plugin). Record versions. This list seeds the Stage 5 reference set (OQ-4).
2. Per plugin, run and record a checklist: scan → instantiate sandboxed → play scheduled notes / process audio → open editor → change params → save/reload state → force-kill helper → confirm containment + restart with state.
3. Full-session test: 10 of the 15 loaded simultaneously, playback at 128 frames for 30 min — zero xruns, zero app crashes.
4. Notarized build (OB-2-06) used for at least one full pass — not a dev build.
5. `docs/stage-2-closeout.md`: results matrix, deviations, debt tickets filed.

## Acceptance criteria

- [ ] ≥15 plugins pass the full checklist on the notarized build; failures analysed (our bug → fixed or ticketed; plugin bug → documented).
- [ ] Crash containment demonstrated on every plugin in the set (scripted helper kill).
- [ ] Closeout doc merged; owner signs off Stage 2.
