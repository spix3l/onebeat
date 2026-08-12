# OB-1-14 — v0.1 exit verification

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Verification |
| **Priority** | Gate (PLAN.md G-C) |
| **Dependencies** | All OB-1-* tickets |
| **References** | PRD §10 v0.1 exit criteria |
| **Estimate** | S |

## Context

Stage close-out against the PRD's exit criterion: **"a note plays without glitching, a meter moves smoothly, RTSan is clean."** No Stage 2 feature work starts until this passes (PLAN.md gate G-C).

## Scope — the checklist, executed and recorded

1. **A note plays without glitching:** trigger sampler notes during playback at 48 kHz/128 frames for 5 minutes; xrun counter (OB-1-12) stays at zero; audible output clean.
2. **A meter moves smoothly:** OB-1-11's 60 s / 120 Hz zero-dropped-frames measurement re-run on the release build.
3. **RTSan is clean:** full CI matrix green on main; RTSan soak (OB-1-06) passes.
4. **Regression of Stage 0 constraints:** ADR-001's binding constraints still hold in the real code (canvas strategy, snapshot mechanism).
5. Clone-to-build re-timed on a clean machine (<15 min, NFR-07).
6. Record a short screen capture of the demo; note deviations/debt in a `docs/stage-1-closeout.md` (carried-forward items become backlog entries).

## Acceptance criteria

- [ ] All three exit criteria demonstrated and recorded.
- [ ] Closeout doc merged listing measurements, capture link, and any accepted debt with owners (as new tickets).
- [ ] Project owner signs off Stage 1 as closed.
