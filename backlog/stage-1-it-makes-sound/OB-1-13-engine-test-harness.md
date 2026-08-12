# OB-1-13 — Engine test harness & offline-render fixtures

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Infra (tests) |
| **Priority** | High |
| **Dependencies** | OB-1-05 (null backend), OB-1-07 |
| **References** | FR-ENG-06, NFR-08 |
| **Estimate** | M |

## Context

FR-ENG-06 requires offline render to share the real-time processing code. Building the test harness on an offline driver of the *same* process path both enables deterministic CI tests and guarantees the shared-code property from day one — the Stage 4 export feature becomes a consumer of this harness rather than new machinery.

## Scope

1. **Offline driver:** renders N blocks through the identical `Engine::process` path (null clock, faster than real time), capturing output to buffers/WAV.
2. **Fixture toolkit:** builders for schedules (note lists → schedule), golden-file comparison with tolerance, spectral/level assertions (peak, RMS, click detection via max sample delta), event-capture instrument (records received events instead of rendering — used by sequencer tests in Stage 3).
3. **Test taxonomy:** unit (pure DSP/model), engine (offline renders), stress (TSan/RTSan targets from OB-1-07/10) — wired as separate CTest labels so CI can matrix them across sanitizers (OB-1-02).
4. **Determinism rule:** engine tests must be bit-exact reproducible; any nondeterminism (denormals, uninitialized memory) is a bug the harness should surface (FTZ/DAZ set explicitly, ASan catches the rest).

## Acceptance criteria

- [ ] Offline driver renders the OB-1-08 golden test byte-identically across 10 repeated runs.
- [ ] The driver calls the same `Engine::process` entry as the CoreAudio backend (enforced by construction: one entry point; code-reviewed).
- [ ] Event-capture instrument exists and is demonstrated in one test.
- [ ] CTest labels integrated into the CI sanitizer matrix.

## Out of scope

- User-facing export (Stage 4 consumes this). Flutter widget/integration tests (added with Stage 3 UI).
