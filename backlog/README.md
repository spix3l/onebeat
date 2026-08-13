# OneBeat Backlog

Companion to `../PLAN.md`. Stages 0–3 are fully detailed tickets; Stages 4–9 are epics broken down when their stage is reached. This index is the single source of ticket status until the project migrates to GitHub issues (1:1 conversion).

**Status legend:** ⬜ todo · 🟨 in progress · 🟦 review · ✅ done

**Stage 1 is closed.** OB-1-01 … OB-1-14 are done, all three v0.1 exit criteria
are demonstrated, the full CI matrix including RTSan is green, and the closeout
is merged. See [`docs/stage-1-closeout.md`](../docs/stage-1-closeout.md) for the
measurements, the deviations, and the seven items of debt carried forward with
their landing stages.

**Stage 0 is not closed, and gate G-A has never been run.** It was not executed
as separate spikes: P4 was answered by the shipped FFI and P1 only at 60 Hz,
while **P2 (tear-off windows) and P3 (Finder drag-and-drop) were never
attempted** and ADR-001 is unwritten. Stage 1 proceeded as though the Flutter
go/no-go had been decided; in truth it was decided implicitly, by the app
working.

**P2 has since been run** (13 August 2026) and it was worth running early: the
answer changed `OB-2-08`. Flutter's multi-window support works well but is not
shippable on stable, so the generic parameter editor renders in the main window
instead of floating. ADR-001 is written and gate G-A is closed. P3 genuinely
does wait for Stage 7.

## Conventions

- **IDs:** `OB-<stage>-<nn>`, stable forever; epics are `EPIC-<n>`.
- A ticket is pickable when all its **Dependencies** are ✅.
- Definition of done is in `PLAN.md §5.2` (ACs met, CI + sanitizers green, human review on audio-thread/FFI code, tokens-only UI, undo coverage).
- Estimates: **S** ≤1 day · **M** 2–4 days · **L** ~1 week (split candidate).

## Ticket template

```markdown
# OB-X-NN — Title

| | |
|---|---|
| **Stage** | N — name |
| **Type** | Spike / Feature / Infra / Design / ADR / Verification |
| **Priority** | Blocker / High / Medium |
| **Dependencies** | ticket IDs |
| **References** | PRD FR-…, ARCHITECTURE.md §…, design screens |
| **Estimate** | S / M / L |

## Context      — why this exists, in one or two paragraphs
## Scope        — functional + technical, numbered
## Acceptance criteria — testable checklist
## Out of scope — explicit deferrals with their landing stage
```

## Stage 0 — Risk spikes (kill/confirm Flutter) — `stage-0-spikes/`

| Status | ID | Title | Est |
|---|---|---|---|
| 🟨 | [OB-0-01](stage-0-spikes/OB-0-01-spike-custompainter-piano-roll-120hz.md) | Spike P1: CustomPainter piano roll at 120 Hz | M |
| ✅ | [OB-0-02](stage-0-spikes/OB-0-02-spike-panel-tearoff-multiwindow.md) | Spike P2: panel tear-off into a second native window | M |
| ⬜ | [OB-0-03](stage-0-spikes/OB-0-03-spike-finder-drag-and-drop.md) | Spike P3: Finder drag-and-drop file paths | S |
| ✅ | [OB-0-04](stage-0-spikes/OB-0-04-spike-ffi-snapshot-roundtrip.md) | Spike P4: FFI round-trip cost for per-frame snapshots | M |
| ✅ | [OB-0-05](stage-0-spikes/OB-0-05-decision-gate-adr-001.md) | Decision gate: ADR-001, Flutter go/no-go | S |

Gate **G-A is closed**: [ADR-001](../docs/adr/ADR-001-ui-toolkit.md) confirms
Flutter, with FR-WSP-02 accepted as *conditional*. Statuses reflect what the
**real** implementation answered, not spike code:

- **P4 ✅** — the shipped seqlock snapshot read over one C call per frame, measured
  across 3797 frames with no attributable per-frame cost (closeout §4).
- **P2 ✅** — answered by [`spikes/p2_multiwindow/`](../spikes/p2_multiwindow/FINDINGS.md).
  Tear-off, live render and re-dock all work, on **one engine and one isolate**,
  with no state serialization needed. But the API is `@internal` and
  master-channel-only, so **OneBeat cannot ship it on stable today** — which is
  why `OB-2-08`'s generic parameter editor now has an in-main-window fallback.
- **P1 🟨** — zero dropped frames sustained and the painter's CPU cost bounded in
  CI at 0.06 % of a 120 Hz frame, but on a 60 Hz panel and with a meter rather
  than the 2,000-note piano roll the spike asks for. Needs ProMotion hardware
  (D1a) *and* Stage 3's piano roll (D1b). **The only spike that can still
  invalidate the Flutter decision.**
- **P3 ⬜** — not attempted; needed before Stage 7.

## Stage 1 — v0.1 "It makes sound" — `stage-1-it-makes-sound/`

| Status | ID | Title | Est |
|---|---|---|---|
| ✅ | [OB-1-01](stage-1-it-makes-sound/OB-1-01-repo-scaffolding-build-system.md) | Repository scaffolding & build system | M |
| ✅ | [OB-1-02](stage-1-it-makes-sound/OB-1-02-ci-sanitizers-license-audit.md) | CI: builds, sanitizer matrix, licence audit | M |
| ✅ | [OB-1-03](stage-1-it-makes-sound/OB-1-03-design-tokens-typography.md) | Design token system, typography, token lint | M |
| ✅ | [OB-1-04](stage-1-it-makes-sound/OB-1-04-adr-002-c-abi-ffi-contract.md) | ADR-002: the C ABI / FFI contract | M |
| ✅ | [OB-1-05](stage-1-it-makes-sound/OB-1-05-audio-io-abstraction-coreaudio.md) | Audio I/O abstraction + CoreAudio backend | L |
| ✅ | [OB-1-06](stage-1-it-makes-sound/OB-1-06-rt-callback-skeleton-rtsan.md) | RT callback skeleton with `[[clang::nonblocking]]` + RTSan | M |
| ✅ | [OB-1-07](stage-1-it-makes-sound/OB-1-07-flattened-schedule-atomic-swap.md) | Flattened schedule: immutable publish via atomic swap | L |
| ✅ | [OB-1-08](stage-1-it-makes-sound/OB-1-08-minimal-sampler.md) | Minimal built-in sampler | M |
| ✅ | [OB-1-09](stage-1-it-makes-sound/OB-1-09-transport.md) | Transport: play, stop, tempo, position | M |
| ✅ | [OB-1-10](stage-1-it-makes-sound/OB-1-10-ffi-implementation.md) | FFI implementation: command queue + frame snapshots | M |
| ✅ | [OB-1-11](stage-1-it-makes-sound/OB-1-11-app-shell-live-meter-120hz.md) | App shell with transport bar and live meter at 120 Hz | M |
| ✅ | [OB-1-12](stage-1-it-makes-sound/OB-1-12-logging-diagnostics.md) | Logging & diagnostics infrastructure | S |
| ✅ | [OB-1-13](stage-1-it-makes-sound/OB-1-13-engine-test-harness.md) | Engine test harness & offline-render fixtures | M |
| ✅ | [OB-1-14](stage-1-it-makes-sound/OB-1-14-v0-1-exit-verification.md) | v0.1 exit verification | S |

## Stage 2 — v0.2 "It hosts" (CLAP) — `stage-2-it-hosts/`

| Status | ID | Title | Est |
|---|---|---|---|
| 🟦 | [OB-2-01](stage-2-it-hosts/OB-2-01-format-agnostic-plugin-model.md) | Format-agnostic internal plugin model (CLAP semantics) | L |
| ⬜ | [OB-2-02](stage-2-it-hosts/OB-2-02-plugin-scanner-cache.md) | Plugin scanner with persistent cache | M |
| ⬜ | [OB-2-03](stage-2-it-hosts/OB-2-03-scan-crash-quarantine.md) | Scan crash quarantine & reporting | S |
| 🟦 | [OB-2-04](stage-2-it-hosts/OB-2-04-adr-003-sandbox-ipc.md) | ADR-003: sandbox IPC mechanism | M |
| ⬜ | [OB-2-05](stage-2-it-hosts/OB-2-05-out-of-process-host-helper.md) | Out-of-process sandboxed host helper | L |
| ⬜ | [OB-2-06](stage-2-it-hosts/OB-2-06-signing-notarization-validation.md) | Code-signing & notarization validation (Gate G-B) | M |
| ⬜ | [OB-2-07](stage-2-it-hosts/OB-2-07-clap-hosting.md) | CLAP hosting: instantiate, process, state | L |
| ⬜ | [OB-2-08](stage-2-it-hosts/OB-2-08-floating-editor-windows.md) | Floating native plugin editor windows | L |
| ⬜ | [OB-2-09](stage-2-it-hosts/OB-2-09-parameter-model-basic-automation.md) | Host parameter model & basic automation | M |
| ⬜ | [OB-2-10](stage-2-it-hosts/OB-2-10-plugin-list-ui-missing-placeholder.md) | Plugin list UI & missing-plugin placeholder | M |
| ⬜ | [OB-2-11](stage-2-it-hosts/OB-2-11-v0-2-exit-verification.md) | v0.2 exit verification | S |

## Stage 3 — v0.3 "It sequences" — `stage-3-it-sequences/`

| Status | ID | Title | Est |
|---|---|---|---|
| ⬜ | [OB-3-01](stage-3-it-sequences/OB-3-01-adr-004-project-file-format.md) | ADR-004: project file format | M |
| ⬜ | [OB-3-02](stage-3-it-sequences/OB-3-02-domain-model-core.md) | Domain model core: entities and identities | L |
| ⬜ | [OB-3-03](stage-3-it-sequences/OB-3-03-undo-redo-command-system.md) | Undo/redo command system | M |
| ⬜ | [OB-3-04](stage-3-it-sequences/OB-3-04-flattener.md) | The flattener: model → schedule | L |
| ⬜ | [OB-3-05](stage-3-it-sequences/OB-3-05-project-save-load.md) | Project save/load | M |
| ⬜ | [OB-3-06](stage-3-it-sequences/OB-3-06-autosave-crash-recovery.md) | Auto-save & crash recovery | M |
| ⬜ | [OB-3-07](stage-3-it-sequences/OB-3-07-instrument-lifecycle.md) | Instrument lifecycle & management | M |
| ⬜ | [OB-3-08](stage-3-it-sequences/OB-3-08-notesequence-model-editing.md) | NoteSequence: one representation, edit operations | M |
| ⬜ | [OB-3-09](stage-3-it-sequences/OB-3-09-channel-rack-ui.md) | Channel rack UI (step sequencer) | L |
| ⬜ | [OB-3-10](stage-3-it-sequences/OB-3-10-piano-roll-ui.md) | Piano roll UI | L |
| ⬜ | [OB-3-11](stage-3-it-sequences/OB-3-11-pattern-management.md) | Pattern management: selector, usage, Make unique | M |
| ⬜ | [OB-3-12](stage-3-it-sequences/OB-3-12-arrangement-view.md) | Arrangement view: lanes, clips, playhead | L |
| ⬜ | [OB-3-13](stage-3-it-sequences/OB-3-13-clip-windowing-transforms.md) | Clip windowing, looping & transpose transform | M |
| ⬜ | [OB-3-14](stage-3-it-sequences/OB-3-14-ui-test-infrastructure.md) | UI test & interaction-walkthrough infrastructure | M |
| ⬜ | [OB-3-15](stage-3-it-sequences/OB-3-15-v0-3-exit-verification.md) | v0.3 exit verification | S |

## Epics — `epics/` (break down at stage start)

| ID | Release | Title |
|---|---|---|
| [EPIC-4](epics/EPIC-4-it-mixes-and-exports.md) | v0.4 | It mixes and exports |
| [EPIC-5](epics/EPIC-5-it-hosts-everything.md) | v0.5 | It hosts everything (VST3 + AU) |
| [EPIC-6](epics/EPIC-6-its-extensible.md) | v0.6 | It's extensible (WASM + WIT API) |
| [EPIC-7](epics/EPIC-7-its-furnished.md) | v0.7 | It's furnished (browser, effects, presets) |
| [EPIC-8](epics/EPIC-8-beautiful-and-learnable.md) | v0.8 | It's beautiful and learnable (workspace, onboarding) |
| [EPIC-9](epics/EPIC-9-usable-by-someone-else.md) | v1.0 | Usable by someone else |

## Suggested execution order (first two stages)

Stage 0: OB-0-01 → -04 in parallel where practical; OB-0-05 last (gate G-A).
Stage 1: OB-1-01 → OB-1-02/03/04 (parallel) → OB-1-05 → OB-1-06 → OB-1-07 → OB-1-08/09/12/13 (parallel) → OB-1-10 → OB-1-11 → OB-1-14. **Done.**
Stage 2: ~~OB-0-02~~ (done) → OB-2-01 (in review) → **OB-2-04 (ADR-003, in review)** → OB-2-02/03 → OB-2-05 → OB-2-06 (gate G-B, validate early) → OB-2-07 → OB-2-08/09/10 → OB-2-11.

**The order above was wrong until 13 August 2026** and is corrected here:
OB-2-02 was listed before OB-2-04, but the scanner runs plugin-by-plugin in the
helper process, so OB-2-02's own Dependencies line names OB-2-04. Building the
scanner first would have meant designing its process model twice.

**OB-2-04 is 🟦 review, not ✅.** Three of its four acceptance criteria are met
with measurements from `spikes/ipc_roundtrip`; the fourth is **human review
(R4)**, required because this is RT-adjacent. `docs/adr/ADR-003-sandbox-ipc.md`
is what needs reading, and the finding worth arguing with is that sandboxed
plugins are called **synchronously** — no pipelining, no added latency, no PDC
contribution.

**OB-2-01 is 🟦 review, not ✅.** Four of its five acceptance criteria are met
and verified; the fifth is **human review (R4)**, which is required for
audio-thread and FFI code and is not the implementer's to sign. The model,
`docs/plugin-threading-contract.md` and `docs/clap-coverage.md` are what needs
reading. Note also that RTSan ran only in CI, not locally — see the ticket's
close-out.
