# OB-1-06 — Real-time callback skeleton with `[[clang::nonblocking]]` + RTSan

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (engine) |
| **Priority** | Blocker |
| **Dependencies** | OB-1-02 (RTSan in CI), OB-1-05 |
| **References** | FR-ENG-03, FR-ENG-07, NFR-08, R4, D2 |
| **Estimate** | M |

## Context

Every audio-thread entry point must be allocation-, lock- and exception-free, marked `[[clang::nonblocking]]`, and verified by RTSan in CI (FR-ENG-03). This ticket establishes the pattern every later engine feature follows.

## Scope

1. **Processing context:** a `ProcessContext` (sample rate, block size, transport position, output buffers) passed down a minimal processing chain: callback → engine process → (later) graph.
2. **Attribute discipline:** the render entry (`Engine::process`) and everything it calls marked `[[clang::nonblocking]]`; compile-time Function Effect Analysis warnings promoted to errors for the engine target.
3. **RT-safe primitives library** (`engine/src/core/rt/`): pre-allocated buffer pool sized at (re)configuration time; SPSC command queue drain; atomic schedule-pointer read (consumed by OB-1-07); a `NonRealtimeMutable<T>`-style helper encapsulating the publish/retire pattern.
4. **RT violation policy:** debug/CI builds run RTSan; a documented "how to write engine code" page (`docs/rt-rules.md`) with the rules: no `new`, no locks, no logging via allocating paths, no `std::function`, exceptions compiled out of hot paths, bounded loops only.
5. Internal processing at 32-bit float (FR-ENG-07 minimum); block-based, sample-accurate event offsets within a block supported structurally (events carry intra-block frame offsets).

## Acceptance criteria

- [ ] `Engine::process` and callees carry `[[clang::nonblocking]]`; Function Effect Analysis clean.
- [ ] RTSan test drives ≥10 s of callbacks (null backend) with zero violations, in CI.
- [ ] A deliberately violating test (temporary) proves RTSan catches malloc, mutex, and syscall on the path — then removed.
- [ ] `docs/rt-rules.md` merged; referenced by `CONTRIBUTING.md` and the DoD.
- [ ] Human review completed (R4).

## Out of scope

- Actual instruments (OB-1-08), schedule content (OB-1-07), multicore (FR-ENG-05, v1.x).
