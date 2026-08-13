# ADR-003 — Sandbox IPC for out-of-process plugin hosting

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 13 August 2026 |
| **Ticket** | OB-2-04 (blocker for OB-2-05) |
| **References** | OQ-3, FR-PLG-07, FR-ENG-04, G3, R10, NFR-01, NFR-11 |
| **Evidence** | [`spikes/ipc_roundtrip/FINDINGS.md`](../../spikes/ipc_roundtrip/FINDINGS.md) |
| **Supersedes** | — |

## Context

FR-PLG-07 says a plugin crash must never terminate OneBeat, and G3 says it must
never destroy user work. The only way to keep that promise against arbitrary
third-party binaries is to run them in another process. The cost is that every
block of audio now crosses a process boundary inside a 2.667 ms budget, and OQ-3
— open since the PRD — is the question of whether that is affordable and how.

This decision has to be made before OB-2-05 writes the helper, because
everything about the helper's shape follows from it: whether audio is
synchronous or pipelined, what the helper's entitlements are, and what happens
in the callback when the helper dies.

It was answered with a two-process measuring prototype rather than by argument.
`spikes/ipc_roundtrip` runs a simulated CoreAudio callback against a real second
process across four signalling primitives, under load and idle, including a
`SIGKILL` failure test. The numbers below are all from it.

## Decision

**Sandboxed plugins are called synchronously inside the audio callback**, over
shared memory, signalled by a pair of Mach semaphores, under a deadline that is
a budget for the whole block. A helper that misses the deadline twice is treated
as dead and its output is silence until it is restarted from the main thread.

| Question | Decision |
|---|---|
| Topology | One helper process **per plugin bundle**, one RT worker thread per instance inside it |
| Audio + event transport | Shared memory (`shm_open` + `mmap`), one segment per instance |
| Signalling | **Mach semaphore pair** per instance, `semaphore_signal` / `semaphore_timedwait` |
| Control channel | **XPC**, which also carries the shm handle and the semaphore send rights |
| Latency model | **Synchronous, zero added latency.** No PDC contribution (FR-ENG-04) |
| Deadline | 60 % of the block period, divided across the sandboxed plugins in the block |
| Failure | Two consecutive missed deadlines → dead; silence; restart from last saved state |

## Why

### The budget is not close

Round-trip cost of handing a 128-frame stereo block to another process and
getting it back. Ten minutes per row, **225,000 blocks each** (FINDINGS §6):

| Run | p50 | p99 | p99.9 | max | misses | **overruns** |
|---|---|---|---|---|---|---|
| `mach_sem`, under load | 4.67 µs | 9.67 µs | 12.79 µs | 668.83 µs | 0 | **0** |
| `mach_sem`, idle | 14.96 µs | 36.21 µs | 47.38 µs | 98.38 µs | 0 | **0** |
| `wait_on_address`, under load | 11.50 µs | 19.50 µs | 26.79 µs | 48.21 µs | 0 | **0** |

Zero missed deadlines and zero overruns in 675,000 blocks. **The worst single
round trip was 669 µs — 25 % of the 2.667 ms period** — reached once, with the
second-worst in that run at 43 µs.

There is no case here for pipelining. Pipelining would buy back a quarter of a
block in the worst case and single-digit percent typically, and would cost a
whole block of latency that FR-ENG-04 must then compensate through the entire
graph, plus the permanent confusion of a plugin whose latency depends on whether
it happens to be sandboxed.

**Budget against 669 µs, not against the median.** Thirty-second screening runs
suggested a 52 µs worst case and were wrong by 13×; only the soak found the
excursion. Anything OB-2-05 sizes should use the soak number.

**Sandboxed plugins therefore contribute nothing to plugin delay compensation.**
That is the single most consequential line in this ADR: it means Stage 4's PDC
never has to know which plugins are sandboxed.

### Mach semaphores, and the two disqualifications

`mach_sem` wins at every percentile with enough samples to mean anything —
2.5× over `wait_on_address` at both p50 and p99.9, in both power states.

It does **not** win on the absolute maximum: over ten minutes `wait_on_address`
never exceeded 48 µs while `mach_sem` produced the single 669 µs excursion. One
outlier in one run cannot be attributed to the primitive rather than to the
scheduler, and this prototype cannot tell those apart. Both sit two orders of
magnitude inside the budget, so the choice between them is not the load-bearing
part of this decision — the load-bearing part is that a bounded wait exists at
all. `mach_sem` is chosen on its percentiles; if the excursion proves to be a
property of Mach semaphores rather than of the scheduler, switching is a
localised change (see below).

The other two candidates lost on capability before they lost on speed:

- **Spinning is unavailable.** It has the best possible latency (170 ns) and it
  collapses after ~3.4 s. A Darwin time-constraint thread declares a computation
  budget per period; a thread that spins consumes 100 % of every period, breaks
  that contract, and is demoted. FINDINGS §3 confirms the mechanism directly by
  re-running the helper at default priority, where it does not collapse. This is
  worth knowing beyond this ADR: **no OneBeat RT thread may busy-wait.**
- **POSIX semaphores cannot bound a wait.** macOS has no `sem_timedwait`, so the
  only bounded use is `sem_trywait` in a poll loop — spinning, with the problem
  above. An unbounded wait on the audio thread is how one hung plugin becomes a
  dead audio device.

`os_sync_wait_on_address` is a genuine second choice, and closer than expected:
it has a real timed wait, needs no port transfer at all — only the shared memory
both processes already have — and had the better ten-minute maximum. It costs
roughly 2.5× at the percentiles. It is the fallback if the port plumbing below
conflicts with sandboxing, and the swap touches only the two wait/signal calls.

### An idle machine is the slower one

Every waiting backend was **4–5× faster with eight CPU burners running** than on
a quiet machine (FINDINGS §2). Idle cores are clocked down and deeply idle, so
waking a thread means waiting for a core to come back; under load they are
already awake.

Two consequences, both binding:

1. **Percentiles are budgeted from the idle numbers**, not the loaded ones. The
   absolute maximum is budgeted from the soak, where the one excursion happened
   to occur under load.
2. **Any regression test for this path must measure the idle machine.** A
   benchmark that warms the machine up first will report numbers that are both
   better and far more stable than what a user gets pressing play on a quiet
   system, and will not catch a regression until it is enormous.

### Topology: per bundle, not per instance

The ticket proposed evaluating one helper per plugin *instance* for maximum
isolation. We are choosing **one helper per plugin bundle** — every instance of
Diva shares one helper; Diva and Serum never do.

The isolation that matters is between OneBeat and third-party code, and between
one vendor's code and another's. Two instances of the same plugin dying together
is not a materially worse outcome than one dying alone: the defect is in that
plugin either way, and G3's promise is about *user work*, which is preserved by
state recovery rather than by process count.

Against that, per-instance has costs that are not hypothetical. Each instance
already needs its own RT worker thread and its own wake per block; per-instance
processes would add a full process image and address space per instance on a
machine with four performance cores. A forty-instance project is a realistic
project.

**Revisit if** crash telemetry shows instances of the same plugin taking each
other down in ways that lose work, or if a specific plugin proves unable to host
multiple instances in one process. Per-instance isolation stays available as a
per-plugin override — the mechanism is identical, only the grouping key changes.

### Control channel: XPC

Instantiate, state save/load, editor control and parameter metadata are all
non-RT and all need to survive signing. XPC is chosen over a raw Unix socket for
three reasons, in order of weight:

1. **It is the transfer mechanism for everything else.** The prototype passed
   Mach semaphore send rights by handing the helper a host-owned port as its
   bootstrap port (FINDINGS §7) — which works, first try, but leaves the helper
   without a real bootstrap port and therefore unable to reach any system
   service. An XPC connection carries the same rights, and file descriptors for
   the shared memory, without taking anything away.
2. Notarisation and entitlements are built around it (R10, OB-2-06).
3. launchd owns the helper's lifecycle, including restart, which is code we
   would otherwise write and get wrong.

Nothing on the control channel is in the audio path, so its latency is not
budgeted.

### Failure semantics

Demonstrated, not asserted (FINDINGS §5): the helper is `SIGKILL`ed mid-run and
the callback keeps its deadline.

| | idle | under load |
|---|---|---|
| Detection latency | 4.27 ms | 4.27 ms |
| Worst callback after death | 1.60 ms | 1.61 ms |
| **Overruns (xruns)** | **0** | **0** |

The rules that produce that result:

- **The wait is always bounded.** 60 % of the period, so a dead helper costs the
  callback its deadline and not its period.
- **The deadline is divided across the sandboxed plugins in the block.** 1.6 ms
  is affordable once per block, not once per plugin. This is the constraint most
  likely to be forgotten in OB-2-05 and it is the one that causes xruns.
- **Two consecutive misses is death.** After that the helper is never waited on
  again and its blocks cost nothing, so a crashed plugin degrades to silence
  rather than to a permanently late callback.
- **Sequence numbers, not flags.** A helper that answers after the host gave up
  must have its answer discarded. With a flag, the stale answer is consumed as
  if fresh and the user hears a block of the previous buffer — a click. With
  counters it fails the sequence test and is dropped.
- **Restart is a main-thread act.** The audio thread marks the helper dead and
  moves on; the host process notices, respawns, and reloads the plugin's last
  saved state. It never blocks the callback to do so.
- **A miss is not automatically a crash.** A helper that is merely late gets the
  same treatment for that block — silence — which is correct: late audio is
  worse than no audio.

### Security posture

Feeds OB-2-06, which validates it against real notarisation.

- The helper is a **separate signed binary** inside the app bundle, with the
  hardened runtime.
- The helper needs **`com.apple.security.cs.disable-library-validation`**. It
  exists to `dlopen` third-party binaries that Apple did not sign and we did
  not sign, which library validation exists to prevent. This is the single
  entitlement R10 is about, and gate **G-B** is the check that notarisation
  accepts it.
- **The main app keeps library validation on.** Isolating the entitlement in the
  helper is most of the point of having a helper: the process that can load
  arbitrary code is not the process holding the user's project.
- The app is sandboxed today (`com.apple.security.app-sandbox` in
  `Release.entitlements`). The helper inherits the sandbox and needs read access
  to the plugin directories; whether that is expressible without a
  user-selected-file entitlement is an open question for OB-2-06.
- The helper gets **no network entitlement**. Plugins that phone home for
  licensing will notice. That is a deliberate default to revisit with evidence,
  not an oversight.

## Consequences

**Good.**

- Synchronous hosting means sandboxing is invisible to the rest of the engine.
  The plugin model from OB-2-01 does not change, and PDC does not learn a new
  case.
- OB-2-01's fixed-size 40-byte `PluginEvent` pays off here: an event list is a
  contiguous trivially-copyable array, so it crosses into shared memory as a
  `memcpy` with no serialisation layer.
- The failure path is demonstrated rather than designed, and it degrades to
  silence, which is the correct failure for audio.

**Bad, or at least owed.**

- One process per plugin bundle is real memory. A project with fifteen distinct
  plugins is fifteen helper processes.
- `disable-library-validation` weakens the helper's own integrity guarantees.
  That is the trade FR-PLG-07 asks for, but it is a trade.
- The deadline budget is a shared resource with no natural enforcement point.
  OB-2-05 must implement the division explicitly.
- Everything here is measured on one M3 with 4+4 cores. The idle-machine effect
  in particular is power management behaviour and may differ on Pro/Max parts.

**Deferred.**

- Editor windows in the helper (OB-2-08) and their event plumbing.
- Scan-time isolation (OB-2-02/03) uses the same helper binary but not the audio
  transport; scanning has no deadline.
- Multi-helper contention, which §5's shared-deadline rule is about, is not
  measured. OB-2-05 should measure it with real plugins before Stage 4's graph
  work depends on it.

## What would change this decision

- Notarisation rejecting `disable-library-validation` (gate G-B) — the whole
  topology would need rework, which is why OB-2-06 sits inside Stage 2.
- A round-trip tail approaching a meaningful fraction of the period, which would
  force the pipelined model and a PDC contribution. The soak's 669 µs is 25 % of
  a 128-frame period; at 64 frames it would be 50 %, so **block sizes below 128
  frames with sandboxed plugins need re-measuring before they are offered.**
- Evidence that the 669 µs excursion is a property of Mach semaphores rather
  than of the scheduler, which would move us to `os_sync_wait_on_address`.
- Evidence that the bootstrap/XPC port plumbing conflicts with the App Sandbox,
  in which case `os_sync_wait_on_address` replaces Mach semaphores with no other
  change: it needs only the shared memory both processes already have.
