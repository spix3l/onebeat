# OneBeat — Master Development Plan

**Version:** 1.0
**Date:** 13 August 2026
**Companions:** `PRD.md` (v1.0 baseline), `ARCHITECTURE.md` (domain model spec, normative), `backlog/` (tickets and epics)

This document turns the PRD's release plan (§10) into an executable sequence of stages with dependency edges, decision gates, and cross-cutting workstreams. Tickets for Stage 0 through Stage 3 are fully detailed in `backlog/`; Stages 4–9 exist as epics to be broken down when reached.

---

## 1. Guiding principles

1. **Vertical slices, never horizontal layers.** Every stage ends with something that runs and demonstrates its exit criterion. We never build "all the model" or "all the UI" in isolation (R1).
2. **The riskiest unknowns die first.** Stage 0 exists solely to kill or confirm Flutter (D3) before any real code depends on it. If P1 fails, we stop and reconsider — a cheap reversal now, catastrophic at v0.4.
3. **The flattened-schedule architecture is non-negotiable and immovable.** The audio thread never traverses `PatternClip → Pattern → Instrument` (ARCHITECTURE.md §7). It is established in Stage 1 because retrofitting it means rewriting the sequencer.
4. **Sanitizers from the first commit.** RTSan on all `[[clang::nonblocking]]` paths; ASan/UBSan/TSan builds on every PR; a failing sanitizer blocks merge (NFR-08). This is the price of choosing C++ over Rust (D2, R4), payable in full.
5. **Tokens before pixels.** The design token system (§8.1.1) exists before any UI code, and CI rejects literal colours/sizes in widget code (FR-UX-01/02). v0.8 turns "consistent" into "beautiful"; it cannot rescue a UI built without tokens.
6. **The C ABI is a product surface.** Narrow, hand-designed, versioned: commands in, snapshots out. Documented as an ADR before UI work begins (NFR-10, R5).
7. **Built-ins prove the public API.** From v0.6 on, built-in instruments and effects use only the public extension API, CI-enforced (G4, FR-EXT-08, R11).
8. **Human review where agents are dangerous.** Every audio-thread function and every FFI boundary function gets human review without exception (R4). Agents are used freely for UI, project model, file I/O and tests.

---

## 2. Stage map

```
Stage 0 ──► Stage 1 ──► Stage 2 ──► Stage 3 ──► Stage 4 ──► Stage 5
(spikes)    (v0.1)      (v0.2)      (v0.3)      (v0.4)      (v0.5)
   │                                                           │
   └─ GATE: Flutter go/no-go                                   ▼
                                            Stage 6 ──► Stage 7 ──► Stage 8 ──► Stage 9
                                            (v0.6)      (v0.7)      (v0.8)      (v1.0)
```

Stages map 1:1 to the PRD §10 releases. Exit criteria below are quoted from the PRD and are the only definition of "done" for a stage.

| Stage | Release | Name | Exit criterion (PRD §10) | Backlog |
|---|---|---|---|---|
| 0 | — | Risk spikes | P1–P4 answered with throwaway code; ADR-001 records the Flutter decision | `backlog/stage-0-spikes/` — 5 tickets |
| 1 | v0.1 | It makes sound | A note plays without glitching, a meter moves smoothly, RTSan is clean | `backlog/stage-1-it-makes-sound/` — 14 tickets |
| 2 | v0.2 | It hosts (CLAP) | 15 CLAP plugins load, play, and are crash-contained | `backlog/stage-2-it-hosts/` — 11 tickets |
| 3 | v0.3 | It sequences | An 8-bar loop created, saved, reopened; the same pattern placed twice updates in both places | `backlog/stage-3-it-sequences/` — 15 tickets |
| 4 | v0.4 | It mixes and exports | A complete track produced and exported | `backlog/epics/EPIC-4.md` |
| 5 | v0.5 | It hosts everything | ≥90% of the reference set passes | `backlog/epics/EPIC-5.md` |
| 6 | v0.6 | It's extensible | An external developer writes a working extension from the docs alone | `backlog/epics/EPIC-6.md` |
| 7 | v0.7 | It's furnished | Browser, core effects, presets, thumbnails shipped | `backlog/epics/EPIC-7.md` |
| 8 | v0.8 | It's beautiful and learnable | FR-UX-23 passes (4 of 5 novices export a loop in <15 min, unaided) | `backlog/epics/EPIC-8.md` |
| 9 | v1.0 | Usable by someone else | A producer who is not the author releases a track made in OneBeat | `backlog/epics/EPIC-9.md` |

### Hard dependency edges (beyond simple sequence)

- **ADR-002 (C ABI) before any Flutter UI beyond the Stage 0 spikes** — NFR-10 requires it documented before UI work begins.
- **ADR-003 (sandbox IPC) before OB-2-05 (out-of-process host)** — OQ-3.
- **ADR-004 (project file format) before any Stage 3 persistence work** — OQ-2.
- **Signing/notarization validation (OB-2-06) inside Stage 2, not deferred** — R10 says validate with a sandboxed helper now, not at v1.0.
- **The domain model (OB-3-02) precedes every sequencer UI ticket** — the model is normative; UI conforms to it, never the reverse (R15).
- **Compatibility reference set (OQ-4) selected before Stage 5 begins.**
- **Usability test participants (OQ-5) recruited during Stage 7, tested in Stage 8.**

---

## 3. Decision gates

| Gate | When | Question | Fail action |
|---|---|---|---|
| **G-A: Flutter go/no-go** | End of Stage 0 | P1: 120 fps piano roll? P2: tear-off windows? P3: Finder DnD? P4: FFI snapshot cost? | If P1 fails: stop, reconsider D3 entirely (native or alternative toolkit), re-plan Stages 1+. If P2/P3 fail partially: document workaround or descope FR-WSP-02/FR-SND-04 with user consent. |
| **G-B: Notarization** | Mid Stage 2 | Does Apple notarization accept our out-of-process plugin host helper architecture? | Rework sandbox architecture before more hosting code lands on top of it. |
| **G-C: Exit demos** | End of every stage | Stage exit criterion demonstrated end-to-end, recorded | Stage does not close; no next-stage tickets start except unblocked infra. |

---

## 4. Cross-cutting workstreams

These run through every stage rather than belonging to one.

### 4.1 CI (established Stage 1, extended thereafter)

- Debug + Release builds, unit tests.
- **Sanitizer matrix (merge-blocking, NFR-08):** RTSan on `[[clang::nonblocking]]` paths, ASan, UBSan, TSan.
- **Licence audit (NFR-09):** every dependency MIT/Apache-2.0/BSD/ISC/PD; copyleft (incl. LGPL) fails the build.
- **Token lint (FR-UX-02):** no colour/size/spacing literals in widget code.
- **Public-API-only check for built-ins (FR-EXT-08):** added in Stage 6.
- Clone-to-build time tracked against the <15 min budget (NFR-07).

### 4.2 ADRs (Architecture Decision Records, `docs/adr/`)

| ADR | Decision | Required before |
|---|---|---|
| ADR-001 | Flutter confirmed/killed; Stage 0 measurements recorded | Stage 1 |
| ADR-002 | C ABI / FFI contract: command queue in, snapshot out, versioning scheme | First Flutter UI ticket (OB-1-11) |
| ADR-003 | Sandbox IPC mechanism (shared memory + Mach ports vs XPC vs sockets) | OB-2-05 |
| ADR-004 | Project file format: TOML vs JSON vs custom; sidecar layout | Stage 3 persistence |
| ADR-005 | WIT API surface v1 | Stage 6 |

### 4.3 Open questions and where they get answered

| Question | Answered by | Due |
|---|---|---|
| OQ-1 trademark clearance "OneBeat" | Owner task, outside backlog — **before repo goes public** | Before Stage 1 repo is public (repo can stay private meanwhile) |
| OQ-2 project file format | ADR-004 (OB-3-01) | Stage 3 |
| OQ-3 sandbox IPC | ADR-003 (OB-2-04) | Stage 2 |
| OQ-4 compatibility reference set (50 plugins) | EPIC-5 ticket | Before Stage 5 |
| OQ-5 usability test participants | EPIC-8 ticket, recruit during Stage 7 | Stage 8 |
| DM-Q1 lane grouping | Resolved: flat lanes, schema reserves `group_id` (OB-3-02) | Stage 3 |
| DM-Q2 clip windowing | Resolved: supported from v1 (OB-3-04) | Stage 3 |
| DM-Q3 clip transforms | Resolved: schedule/schema from v0.3, transpose UI in v1.0 (OB-3-04) | Stage 3 |
| DM-Q4 one NoteSequence | Resolved: shared representation (OB-3-08) | Stage 3 |
| DM-Q5 multi-out ports | Resolved: dynamic per CLAP | Stage 5 |

### 4.4 Design conformance

- All UI tickets reference the Pencil design screens (27 screens: shell/arrangement, piano roll, workspace drag + tear-off window, first-run, empty states, failure states, plugin windows, script console ×3, extension manager ×3, export flow ×4, routing ×3, preferences ×2).
- Chrome stays chromatically quiet; every screen tested against saturated user clip colours (§15.3).
- Meters keep conventional green–amber–red, never restyled.
- Empty and error states are designed in the same ticket as the feature, not afterwards (FR-UX-12/13) — the design file already covers them; implementation must too.

---

## 5. Ways of working

### 5.1 Ticket lifecycle

`backlog/` is the single source of truth until the repo moves to GitHub issues (then tickets convert 1:1). Ticket states are tracked in `backlog/README.md`'s index: **todo → in progress → review → done**. A ticket is picked up by reading only the ticket file plus the referenced PRD/ARCHITECTURE sections.

### 5.2 Definition of done (every ticket)

- All acceptance criteria demonstrably met (test, recording, or reproducible manual check as the AC specifies).
- CI green, including the full sanitizer matrix (NFR-08).
- **Human review of any audio-thread or FFI-boundary code, no exceptions** (R4).
- New dependencies pass the licence audit (NFR-09).
- UI code uses tokens only (FR-UX-02); no functionality reachable only by right-click or undocumented shortcut (FR-UX-17); destructive actions undoable (FR-UX-21).
- Sequencer-adjacent tickets re-checked against the anti-pattern table (ARCHITECTURE.md §6) in review (R15).

### 5.3 Estimation

T-shirt sizes on tickets: **S** (≤1 day), **M** (2–4 days), **L** (about a week, and a candidate for splitting). Estimates assume one senior engineer with heavy agent assistance on non-RT code.

### 5.4 Risk watch-list per stage

| Stage | Risks actively watched |
|---|---|
| 0 | R6, R12, R13, R14 (all four Flutter unknowns) |
| 1 | R4 (RT discipline), R5 (ABI ossification), R6 |
| 2 | R3 (compat long tail), R10 (notarization) |
| 3 | R15 (domain model drift — anti-pattern table is the review checklist) |
| 4–5 | R3 |
| 6 | R11 (decorative extensibility) |
| 8 | R7 (taste), R8 (flexibility vs learnability) |
| all | R1 (scope collapse), R2 (bus factor) |
