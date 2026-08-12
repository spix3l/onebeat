# OB-2-04 — ADR-003: sandbox IPC mechanism for out-of-process hosting

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Design / ADR |
| **Priority** | Blocker for OB-2-05 |
| **Dependencies** | OB-2-01 |
| **References** | OQ-3, FR-PLG-07, G3, R10, NFR-01 |
| **Estimate** | M |

## Context

Out-of-process hosting (FR-PLG-07) needs an IPC design that carries audio between processes inside the RT budget — the hardest constraint in the hosting architecture. OQ-3 is due this stage. The decision interacts with notarization (R10) and must precede helper implementation.

## Scope

Write `docs/adr/ADR-003-sandbox-ipc.md` deciding, with a measuring prototype:

1. **Process topology:** one helper per plugin vs per-vendor grouping vs one helper for all. v0.2 recommendation to evaluate: **one helper process per plugin instance** (maximum isolation, more memory) with grouping as a future optimization; record the trade-off.
2. **Audio/event transport:** shared-memory ring buffers (audio + event lists) with a real-time signaling primitive. Evaluate Mach semaphores vs `os_sync_wait_on_address` (futex-like) vs POSIX semaphores for RT-safe cross-process wake; measure round-trip latency and jitter at 128-frame blocks under load.
3. **Control channel:** non-RT command/response (instantiate, state, editor control): XPC vs Unix socket + simple framing. XPC interacts best with signing/entitlements — verify with OB-2-06.
4. **Failure semantics:** helper death detection latency; audio thread behaviour when a helper misses a deadline (output silence for that plugin, never block); reconnect/restart protocol preserving plugin state from the last good save.
5. **Budget:** measured worst-case added latency; decide whether sandboxed plugins run with one block of latency (pipelined, PDC-compensated in Stage 4) or synchronously within the callback — record the choice and its PDC consequence (FR-ENG-04).
6. **Security posture:** helper entitlements, App Sandbox stance, library-validation implications for loading arbitrary third-party plugin binaries (feeds OB-2-06).

## Acceptance criteria

- [ ] ADR-003 merged with measurements from a minimal two-process prototype (shared-memory audio round trip at 128 frames: worst-case latency + jitter recorded over ≥10 min under CPU load).
- [ ] Failure semantics specified: a killed helper leaves the callback meeting its deadline (prototype demonstrates silence-on-death without an xrun).
- [ ] Topology, transport, control channel, and latency model decided and justified.
- [ ] Human review completed (R4 — RT-adjacent IPC).

## Out of scope

- Full helper implementation (OB-2-05). Notarization validation (OB-2-06) — but the entitlement list drafted here feeds it.
