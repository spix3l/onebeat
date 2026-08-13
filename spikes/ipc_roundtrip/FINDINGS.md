# OB-2-04 — two-process audio IPC: measurements

**Ticket:** OB-2-04 · **Date:** 13 August 2026 · **Feeds:** [ADR-003](../../docs/adr/ADR-003-sandbox-ipc.md)

**Machine.** MacBook Air (Mac15,12), Apple M3, 4 performance + 4 efficiency
cores, macOS 26.6.1. Release build, no sanitizers. Both processes' worker
threads carry CoreAudio's `THREAD_TIME_CONSTRAINT_POLICY`. Block size 128
frames at 48 kHz, so the period is **2.667 ms** and the host's wait deadline is
60 % of it, **1.6 ms**.

Everything below is `spikes/ipc_roundtrip`. Reproduce with the commands in
[README.md](README.md).

## Headline

A 128-frame block survives a round trip through a second process in **single-digit
microseconds under load** and **tens of microseconds on an idle machine**, with a
worst case over 675,000 blocks of **669 µs** — a quarter of the 2.667 ms budget,
and reached exactly once. Synchronous in-callback hosting is affordable; OneBeat
does not have to pipeline sandboxed plugins and does not have to spend a block of
latency on FR-ENG-04's compensation.

Three things surprised us, and all three changed the design:

1. **An idle machine is the slower one.** Latency was 4–5× *higher* with nothing
   else running — the opposite of the intuition the ticket was written with.
   (The single largest excursion, though, happened under load: §6.)
2. **You cannot busy-wait on a Darwin time-constraint thread.** The spin backend
   does not merely waste a core; the scheduler demotes the thread and the
   transport collapses within seconds.
3. **POSIX semaphores have no timed wait on macOS**, which disqualifies them
   regardless of how they measure.

## 1. Backend comparison — 30 s per cell, 11,250 blocks

Round-trip microseconds, signal sent → answer visible.

### Idle machine (`--load 0`)

| Backend | p50 | p99 | p99.9 | max | misses |
|---|---|---|---|---|---|
| `spin` | 0.21 | 333.83 | 1405.17 | 1450.71 | **10,551 of 11,250** |
| `wait_on_address` | 37.08 | 76.54 | 91.50 | 143.67 | 0 |
| `posix_sem` | 18.00 | 38.79 | 56.29 | 114.71 | 0 |
| **`mach_sem`** | 18.33 | 36.21 | 44.17 | **52.46** | 0 |

### Under load (`--load 8` — eight CPU burners on eight cores)

| Backend | p50 | p99 | p99.9 | max | misses |
|---|---|---|---|---|---|
| `spin` | 0.12 | 0.46 | 1.33 | 2.46 | **10,875 of 11,250** |
| `wait_on_address` | 6.50 | 11.67 | 13.92 | 22.67 | 0 |
| `posix_sem` | 3.54 | 9.33 | 14.54 | 33.71 | 0 |
| **`mach_sem`** | 3.92 | 8.54 | 10.75 | **13.12** | 0 |

`mach_sem` is not the fastest at the median — `posix_sem` edges it — but it has
the tightest tail in both conditions, and the tail is the only part of the
distribution an audio callback cares about.

These are 30-second runs and they **understate the tail**; §6 finds a 669 µs
excursion that nothing at this timescale predicts. Read the table for the
comparison between backends, not for the worst case.

## 2. The idle machine is the worst case

Every wait-based backend got 4–5× faster when eight CPU burners were added.
That is the opposite of the intuition the ticket was written with, and it is not
noise: it reproduced on every backend and every run.

The explanation is power management. On an idle Apple-silicon machine the cores
are clocked down and in a deep idle state, so waking a sleeping thread means
waiting for a core to come back. Under load the cores are already awake and at
full clock, and the wake is nearly free. Idle-machine numbers also vary far more
between runs (`mach_sem` p50 ranged 7.6–18.3 µs across runs) while loaded
numbers were stable to a fraction of a microsecond.

**Consequence for the ADR:** typical and percentile latency must be budgeted
from the *idle* figures, and any future regression test must measure the idle
case. A benchmark that only runs the machine hot will report numbers that are
both better and less stable than what a user gets when they hit play on a quiet
system.

The absolute worst case is a separate question with a different answer: §6's
single 669 µs excursion occurred under load. Budget the percentiles from idle
and the maximum from the soak.

## 3. Spin-waiting is not an option, for a reason worth writing down

The spin backend has the best latency anyone will ever measure here — **170 ns**
median, the cost of a cache line moving between cores — and it fails completely.
After roughly 1,300 blocks (3.4 s) the helper stops answering and never recovers.

The hypothesis was that a time-constraint thread which never yields blows its
declared computation budget and is demoted by the scheduler. `OB204_NO_RT=1`
tests exactly that by leaving the helper at default priority:

| Helper thread policy | Answered | p50 | max | misses |
|---|---|---|---|---|
| Time-constraint (RT) | 1,280 of 3,750 | 0.58 µs | 1570 µs | 2,470 |
| Default priority | **3,750 of 3,750** | 0.17 µs | 480 µs | 0 |

Confirmed. The RT policy is a *contract* — "I need this much computation every
period" — and a thread that consumes 100 % of every period has broken it. Darwin
responds by throttling, and the throttled helper misses the deadline forever.

So spinning is not a trade of CPU for latency. It is unavailable on the thread
policy a plugin helper must have, and at default priority it both burns a core
per plugin instance and has a worse tail (480 µs) than any waiting backend.

## 4. POSIX semaphores cannot bound the wait

macOS ships no `sem_timedwait`. The audio thread must never block without a
deadline — an unbounded wait turns one hung plugin into a dead audio device — so
the only bounded use of a POSIX semaphore is `sem_trywait` in a polling loop,
which is spinning with extra steps and lands back in §3.

The measurements above use exactly that polling loop, so `posix_sem`'s good p50
is somewhat flattered by burning the host core while it waits. Even so it loses
on the tail. It is excluded on capability, not on speed.

`os_sync_wait_on_address_with_timeout` and `semaphore_timedwait` both provide a
real bounded wait.

## 5. Failure semantics: `SIGKILL` mid-run

20 s run, helper killed at 10 s, `--deadline-frac 0.6`. The host treats two
consecutive missed deadlines as death and stops waiting entirely thereafter.

| Backend | Load | Detection latency | Worst callback after death | **Overruns** |
|---|---|---|---|---|
| `mach_sem` | idle | 4.27 ms | 1.60 ms | **0** |
| `mach_sem` | 8 | 4.27 ms | 1.61 ms | **0** |
| `wait_on_address` | idle | 4.47 ms | 1.81 ms | **0** |

The audio never stopped. The two blocks between the kill and the diagnosis each
spent their 1.6 ms deadline waiting and then output silence — inside the 2.667 ms
period, so **no xrun** — and every block after that cost nothing at all, because
a helper known to be dead is never waited on again.

Two details that matter more than they look:

**Sequence numbers, not flags.** `request` and `response` are counters. A helper
that answers *after* the host gave up would, with a flag, have its stale answer
consumed as if it were fresh — the audible result being one block of the
previous buffer's audio, which is a click. With counters the late answer simply
fails the `response == seq` test and is discarded.

**The deadline is a budget for the whole graph, not per plugin.** 1.6 ms of a
2.667 ms period is affordable once. Two sandboxed plugins timing out in the same
block would overrun. Whatever OneBeat ships must divide one deadline across the
plugins in the block, not give each its own.

## 6. Ten-minute soak

Per the ticket's acceptance criterion: ≥10 min at 128 frames under CPU load.
Because §2 showed idle to be the worse case, the idle condition was soaked too.

Three runs, 600 s each, **225,000 blocks per run**, `--frames 128`.

| Run | p50 | p99 | p99.9 | max | misses | **overruns** |
|---|---|---|---|---|---|---|
| `mach_sem`, load 8 | 4.67 | 9.67 | 12.79 | **668.83** | 0 | **0** |
| `mach_sem`, idle | 14.96 | 36.21 | 47.38 | 98.38 | 0 | **0** |
| `wait_on_address`, load 8 | 11.50 | 19.50 | 26.79 | 48.21 | 0 | **0** |

Zero missed deadlines and zero overruns in 675,000 blocks. That is the result
the ADR needs.

**The 30-second screening understated the tail, and by a lot.** The soak found a
single round trip of **669 µs** — 13× the worst value seen in any 30 s run, and
50× this run's own p99.9. It is one block in 225,000; the second-worst in the
same run is 43 µs. Per-block detail:

| Run | samples > 50 µs | samples > 100 µs | second-worst |
|---|---|---|---|
| `mach_sem`, load 8 | 1 | 1 | 43.17 µs |
| `mach_sem`, idle | 138 | 0 | 93.79 µs |
| `wait_on_address`, load 8 | 0 | 0 | 42.21 µs |

So the two conditions have differently *shaped* tails, not just different
heights. Under load the distribution is tight with one rare excursion; idle it
is uniformly fatter — 138 samples past 50 µs — but never spikes. Neither shape
is visible in a 30-second run, which is the argument for the soak being an
acceptance criterion rather than a formality.

**This complicates the "`mach_sem` has the best tail" claim, and it should.**
Over ten minutes `wait_on_address` never exceeded **48 µs**, while `mach_sem`
produced one 669 µs excursion. `mach_sem` is better at every percentile that has
enough samples to mean anything (2.5× at p50 and p99.9); `wait_on_address` has
the better absolute maximum. One outlier in one run is not enough to attribute
to the primitive rather than to the scheduler, and this prototype cannot tell
those apart.

What it does establish is that **both are inside the budget with two orders of
magnitude of headroom**, and that the choice between them is not the load-bearing
part of the decision. The load-bearing part is that a bounded wait exists at all.

**Worst case for budgeting: 669 µs**, 25 % of the block period and 42 % of the
1.6 ms deadline. That is the number OB-2-05 should size against, not the 52 µs
the short runs suggested.

## 7. Mach port transfer works, and costs one design constraint

A Mach semaphore is a port, and ports survive neither `fork` nor `exec`. The
prototype hands the helper a send right to a host-owned port through
`posix_spawnattr_setspecialport_np(..., TASK_BOOTSTRAP_PORT)`; the helper creates
both semaphores and mails both send rights back in one `mach_msg`. That works
today, first try, with no launchd registration.

It does, however, mean the helper's bootstrap port is *ours* rather than
launchd's, so the helper cannot look up system services. For a plugin host that
is close to a feature — it is one more thing the sandbox does not grant — but it
is a real constraint and OB-2-05 must confirm no plugin-loading path in
`dlopen`/CoreFoundation needs bootstrap. If one does, the alternative is to
establish the connection over XPC and send the semaphore rights across it, which
costs a launchd service definition and nothing in the steady-state audio path.

## 8. What this prototype does not measure

Recorded so the ADR's confidence is not overstated:

- **No real plugin.** The helper multiplies by 0.5. A real plugin adds its own
  DSP time and, more importantly, its own allocation and locking behaviour
  inside the helper's callback.
- **One helper, one block, two channels.** Nothing here measures N helpers
  contending, which is the case §5's shared-deadline point is about.
- **No control channel.** Instantiate/state/editor traffic (XPC vs socket) is
  argued in the ADR from first principles and from OB-2-06's signing
  constraints, not measured here.
- **One machine.** M3, 4+4. An M-series Pro/Max with more performance cores, or
  an Intel Mac, may behave differently — particularly §2, which is a power
  management effect.
- **No thermal soak.** The 10-minute runs are not long enough to reach a
  throttling steady state on a fanless Air.
