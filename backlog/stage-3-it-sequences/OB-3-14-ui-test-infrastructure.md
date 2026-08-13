# OB-3-14 — UI test & interaction-walkthrough infrastructure

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Infra (tests) |
| **Priority** | Medium — but pays for itself immediately across OB-3-09/10/12 |
| **Dependencies** | OB-3-09/10/12 (co-developed; land early parts with the first widget) |
| **References** | NFR-08 discipline applied to UI; FR-UX-17/21 as testable properties |
| **Estimate** | M |

## Context

Stage 3 multiplies UI surface. Without widget/integration tests and scripted walkthroughs, FR-UX-17 (no right-click-only), FR-UX-21 (undo everywhere) and the 120 Hz budget regress silently.

## Scope

1. **Widget test layer:** harness with a fake `EngineClient` (scripted snapshots/accepted commands) so all editors run in `flutter test` without the engine; golden-image tests for the token-critical surfaces (meter, clip, step row, note) with per-theme goldens.
2. **Integration driver:** `flutter_test`-driven end-to-end scripts against the real engine (null audio backend): "program pattern → arrange → play → assert event capture" — the same scripts double as stage-exit demos.
3. **Property checks as tests:** (a) every registered UI action asserted reachable from a visible control (action registry introspection → FR-UX-17 becomes a test, not a walkthrough); (b) command-bus audit: any mutation reaching the model outside a `Command` fails the test run (FR-UX-21 backstop).
4. **Perf regression lane:** scripted profile-mode runs of piano roll / arrangement scroll+playback capturing frame stats; thresholds fail CI on regression (guards R13 permanently).
5. Action registry itself (if not already forced into existence by (3)): central declaration of user actions {id, label, shortcut, menu placement} — also the future seed of FR-UX-22 (remappable shortcuts) and the command palette.

## Acceptance criteria

- [x] All Stage 3 editors have widget tests + at least one golden each; CI runs them.
- [x] The FR-UX-17 reachability test runs in CI and its deliberate-violation
      case is kept permanently rather than performed once. The command-bus
      audit is the existing `tools/seam_check.sh`, in CI since Stage 3 opened.
- [x] Perf lane fails on regression and has already caught a real one (the
      2.6 ms arrangement painter). **Trend data on main is not yet written to
      a file** — see the closeout.
- [x] The v0.3 exit script (OB-3-15) runs green via the integration driver.

**Complete (14 August 2026), with one half-item named.** Landed: a scripted
`FakeStage3Client` covering all three Stage 3 seams; a `Stage3Harness` that wires
fakes to the real stores and real widgets; per-theme goldens for the roll and the
arrangement; paint-cost guards at OB-3-10's and OB-3-12's own stress figures; a
real-engine integration driver (`stage3_exit_test.dart`, tagged `integration`,
skipped in an unbuilt checkout); and the action registry.

The registry is the piece that pays for itself. FR-UX-17 is now a test: every
declared action must have a visible control carrying `actionKey(id)`, asserted
per editor, with a permanent negative case so the guard cannot stop guarding. It
found a genuine gap on its first run.

The command-bus audit (§3b) was already mechanised by `tools/seam_check.sh`,
which fails the build if `Project`'s mutating API is touched outside
`model/commands.cpp` — so it is not duplicated here.

**Still open:** §4's *trend* data. The perf lane fails on regression today but
does not append figures to a file on `main`, so there is no history to look at.
Small, and worth doing before the surface grows again.


## Out of scope

- Full E2E on real audio hardware (manual, stage exits). Accessibility audits (Stage 8).

**In progress (13 August 2026).** OB-3-09 landed the first reusable slice: a
`RackClient` seam with a scripted fake, store interaction tests proving
one-transaction paint gestures, a per-theme rack golden, and a dense 8 × 64
custom-painter budget test. The shared action registry, real-engine integration
driver and profile trend lane remain to be completed as OB-3-10/12 arrive, as
this ticket's co-development plan intended.
