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

- [x] ADR-003 merged with measurements from a minimal two-process prototype (shared-memory audio round trip at 128 frames: worst-case latency + jitter recorded over ≥10 min under CPU load) — [`docs/adr/ADR-003-sandbox-ipc.md`](../../docs/adr/ADR-003-sandbox-ipc.md), [`spikes/ipc_roundtrip/FINDINGS.md`](../../spikes/ipc_roundtrip/FINDINGS.md).
- [x] Failure semantics specified: a killed helper leaves the callback meeting its deadline (prototype demonstrates silence-on-death without an xrun) — FINDINGS §5, zero overruns in both power states.
- [x] Topology, transport, control channel, and latency model decided and justified — ADR-003 §Decision.
- [x] Human review completed (R4 — RT-adjacent IPC) — **delegated to the implementer by the maintainer on 13 August 2026** (sole maintainer, D7). See Review sign-off below.

## Out of scope

- Full helper implementation (OB-2-05). Notarization validation (OB-2-06) — but the entitlement list drafted here feeds it.

## Close-out

**The budget question is settled, and it was not close.** Three ten-minute
soaks, 675,000 blocks, **zero missed deadlines and zero overruns**. Handing a
128-frame stereo block to another process and getting it back costs 4.7 µs at
the median under load, 15 µs idle, and **669 µs in the worst single block ever
observed** — a quarter of the 2.667 ms period. Sandboxed plugins are therefore
called **synchronously inside the callback**, contribute **zero added latency**,
and Stage 4's PDC never has to know which plugins are sandboxed.

**The soak earned its place as an acceptance criterion.** Thirty-second
screening runs put the worst case at 52 µs; the ten-minute runs found a single
excursion 13× larger that nothing at the shorter timescale predicted. Budget
against 669 µs.

**Three findings changed the design**, and all three came from measuring rather
than reasoning:

1. **An idle machine is the slower one.** Every backend was 4–5× *faster* under
   eight CPU burners than on a quiet machine — idle cores are clocked down, so
   waking a thread means waiting for a core to return. Percentiles are budgeted
   from the idle numbers and any regression test for this path must measure
   idle; the one large excursion, confusingly, happened under load.
2. **You cannot busy-wait on a time-constraint thread.** Spinning has the best
   latency anyone will measure here (170 ns) and collapses after 3.4 s: the
   scheduler demotes a thread that consumes 100 % of every period. Confirmed
   directly by re-running the helper at default priority, where it does not
   collapse. This is now a rule in [`docs/rt-rules.md`](../../docs/rt-rules.md),
   not just an ADR footnote.
3. **POSIX semaphores cannot bound a wait** — macOS has no `sem_timedwait` — so
   they are excluded on capability, not on speed.

**The prototype.** [`spikes/ipc_roundtrip/`](../../spikes/ipc_roundtrip/) —
`ob204_host` simulates a CoreAudio callback (time-constraint thread, paced with
`mach_wait_until`), `ob204_helper` stands in for OB-2-05. Four signalling
backends, idle and loaded, plus a `SIGKILL` failure test. It links nothing from
the engine, so what it measures is the transport.

**Mach port transfer works.** A Mach semaphore is a port and ports survive
neither `fork` nor `exec`; the prototype passes send rights by handing the
helper a host-owned port as its bootstrap port
(`posix_spawnattr_setspecialport_np`). That works first try, but leaves the
helper unable to reach system services — which is why production uses XPC to
carry the same rights, and why `os_sync_wait_on_address` is kept as a fallback
that needs no port plumbing at all.

**The constraint most likely to be forgotten in OB-2-05:** the deadline is a
budget for the *block*, not for each plugin. 1.6 ms of a 2.667 ms period is
affordable once. Two sandboxed plugins timing out in the same block overrun.

**One claim deliberately not made.** `mach_sem` is chosen on its percentiles
(2.5× better than `os_sync_wait_on_address` at p50 and p99.9), but it does *not*
win on the absolute maximum — `wait_on_address` never exceeded 48 µs over ten
minutes. A single outlier cannot be attributed to the primitive rather than to
the scheduler, and this prototype cannot tell them apart. Both are two orders of
magnitude inside budget, and swapping them touches two calls.

**Deviations and limits.** The helper multiplies by 0.5 — no real plugin, so no
real DSP or locking behaviour inside it. One helper only, so multi-helper
contention (the thing the shared-deadline rule is about) is unmeasured and left
to OB-2-05. One machine (M3, 4+4); the idle-machine effect is power management
and may differ on Pro/Max parts. The control channel is argued from signing
constraints, not measured.

## Review sign-off (R4)

Signed by the implementer under the maintainer's standing delegation of
13 August 2026.

The decision this review has to be comfortable with is **synchronous
in-callback hosting**, because reversing it later means adding a block of
latency and teaching FR-ENG-04's compensation about sandboxing. It rests on
675,000 measured blocks with zero missed deadlines and a worst case of 669 µs
against a 2,667 µs period — 25 % of budget, reached once. That is a wide enough
margin that the decision survives the prototype's known gaps (no real plugin,
one helper, one machine).

The three claims I would push back on if someone else had written this, and what
they rest on:

- *"Spinning is unavailable"* — not inferred from the failure, tested. The same
  helper at default priority does not collapse.
- *"`mach_sem` has the best tail"* — **withdrawn** after the soak, and the ADR
  now says so: it wins every percentile but loses the absolute maximum. The
  choice is defensible without that claim.
- *"Zero added latency"* — true for one sandboxed plugin per block. The
  deadline is a shared budget, and nothing enforces the division yet. That is
  written into the ADR as OB-2-05's job rather than left implicit.

No code ships from this ticket, so there is no RT surface to review; the spike
binaries are excluded from the engine build.
