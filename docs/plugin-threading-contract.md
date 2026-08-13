# The plugin threading contract

**Ticket:** OB-2-01 · **Applies to:** everything in `engine/src/plugin/` ·
**Companion to:** [`rt-rules.md`](rt-rules.md)

Almost every serious plugin-hosting bug is a thread-contract violation, and
almost none of them fail immediately. A parameter read from the audio thread
that the plugin only meant to be read from the main thread produces a crash
weeks later, on someone else's machine, in a plugin you cannot debug. CLAP
responds by annotating every entry point `[main-thread]` or `[audio-thread]` in
its headers. OneBeat mirrors those annotations, and then goes one step further:
**it asserts them at runtime in debug builds**, so a violation is a trap at the
call site rather than a corruption three seconds later.

## The two roles

| Role | Who | What it may do |
|---|---|---|
| `[audio-thread]` | The thread inside `Engine::process()` — the CoreAudio callback in production, the offline driver's caller in tests | No allocation, no locks, no exceptions, no syscalls, no unbounded loops. Enforced at compile time by `OB_NONBLOCKING` (`[[clang::nonblocking]]` + `-Wfunction-effects`) and at runtime by RTSan in CI. |
| `[main-thread]` | Anything else: the UI thread, the housekeeping thread, the scanner | Everything. Allocation, file I/O and locks are expected here. |

`[main-thread]` is deliberately weaker than "one specific thread". OneBeat's
housekeeping and (from OB-2-02) scanner threads legitimately make main-thread
calls, serialised by the caller. What must never happen is the **audio** thread
making one — and that is exactly what the assertion checks.

## How the roles are claimed

`Engine::process()` calls `plugin::ThreadCheck::enterAudioThread()` on entry and
`leaveAudioThread()` on exit. Two consequences worth knowing:

- The offline driver gets the same discipline as CoreAudio for free, because
  both go through `process()`. FR-ENG-06's "offline shares the real-time path"
  extends to the thread contract, not just the DSP.
- The role is *released* at the end of the block rather than left set, so the
  offline driver's caller — an ordinary thread that goes on to make main-thread
  calls — is not left holding the audio role and tripping the opposite
  assertion.

A test that drives `process()` directly declares itself with
`ThreadCheck::ScopedAudioThread`. That is the only sanctioned way to satisfy an
audio-thread assertion outside the engine, and it exists so tests do not become
a reason to weaken the check.

In release builds (`NDEBUG`) both assertions compile to nothing.

## The contract, method by method

### `PluginInstance` — lifecycle

| Method | Thread | Legal in state | Notes |
|---|---|---|---|
| `configure(setup)` | `[main-thread]` | Created, Configured | **Not** while active. This is DM-Q5's rule: ports and stream format change only while deactivated. |
| `activate()` | `[main-thread]` | Configured | May allocate. After it returns, the port layout is frozen. |
| `deactivate()` | `[main-thread]` | Active | Refused while Processing — the audio thread must `stopProcessing()` first. |
| `startProcessing()` | `[audio-thread]` | Active | Separate from `activate()` precisely because the transport starting must not take a lock. |
| `stopProcessing()` | `[audio-thread]` | Processing | |
| `reset()` | `[audio-thread]` | Active, Processing | Drops sounding state; keeps allocations. |
| `process(block)` | `[audio-thread]` | Processing (and tolerated in Active) | The only method allowed to be expensive. |
| `beginAudioBlock()` | `[audio-thread]` | any | **OneBeat extension.** Once per *callback*, before any `process()` call for it. |

### `PluginInstance` — parameters, ports, state

| Method | Thread | Notes |
|---|---|---|
| `paramCount`, `paramInfo`, `paramValue` | `[main-thread]` | `paramValue` returns the **base** value — never the modulated one. |
| `paramValueToText`, `paramTextToValue` | `[main-thread]` | May allocate; the generic editor calls them. |
| `paramsFlush(in, out)` | `[main-thread, while not processing]` | The only way a parameter change reaches a plugin when the transport is stopped. Skipping it is how "my automation does nothing when stopped" bugs begin. |
| `audioPortCount`/`Info`, `notePortCount`/`Info` | `[main-thread]` | Reading is always legal; the values are only *stable* while active. |
| `saveState`, `loadState` | `[main-thread]` | Allocation and I/O expected. A plugin that saves state from `process()` is broken. |
| `latencyFrames` | `[main-thread]` | |
| `tailFrames`, `activeVoiceCount` | `[audio-thread]` | Cheap reads; the snapshot publisher calls them per block. |
| `onMainThread` | `[main-thread]` | Runs in response to `PluginHost::requestCallback()`. |
| `threadPoolExec` | `[audio-thread]` | Called concurrently for distinct task indices, on host worker threads that are all real-time threads. |

### `PluginHost` — what a plugin may ask of us

| Method | Thread | Notes |
|---|---|---|
| `requestRestart`, `requestProcess`, `requestCallback` | `[thread-safe]` | Callable from anywhere, including inside `process()`. Implementations must be lock-free; OneBeat's are atomic flags. |
| `paramsRescan`, `paramsClear` | `[main-thread]` | `ParamRescanAll` requires deactivation and may invalidate automation, so a plugin that over-reports it destroys user work. |
| `audioPortsRescan`, `notePortsRescan` | `[main-thread]` | |
| `latencyChanged`, `tailChanged` | `[main-thread]` | |
| `requestThreadPoolExec` | `[audio-thread]` | The one host callback marked `OB_NONBLOCKING`. Declining is always legal — OneBeat declines for the whole of Stage 2. |

## Rules that are not obvious from the table

**One callback may be several `process()` calls.** OneBeat splits a block at
loop seams so a wrap is sample-accurate, and each segment gets its own
`process()` with its own `TransportInfo`. A plugin must not assume one call per
callback, and must not assume `frames` equals `max_block_frames`. What *is*
guaranteed: `beginAudioBlock()` runs once per callback, before the first
`process()` of that callback.

**Event times are block-relative.** `PluginEvent::time` counts frames from the
start of the block being processed, never from the schedule origin. The
flattener resolves absolute time; the instrument never sees it.

**Event lists are borrowed and short-lived.** The storage behind
`ProcessBlock::in_events` belongs to the host and is valid only for the duration
of the call. That includes sysex payloads, which are pointers into host memory —
a plugin that needs a dump after the call returns must copy it, from
`onMainThread()`, not from `process()`.

**The audio thread never allocates, and `EventList` will not let it.** Capacity
is fixed at `configure()` time. A push past capacity is dropped and counted, and
the engine logs the drop through the RT log (`event_list_full`). This is
deliberately visible: a silently resizing container on the audio thread is how
an RT invariant dies six months after it was written.

**Modulation never writes back.** `ParamModulation` adjusts a per-block offset;
`ParamValue` is the value the user set and the project saves. `paramValue()`
returns the base, `saveState()` writes the base, and the DSP uses
`base + modulation` clamped to range. Collapsing the two is the specific bug D5
exists to prevent, and it is enforced structurally: they are separate fields.

## Where this is checked

| Layer | What it catches | Where |
|---|---|---|
| `-Wfunction-effects` at compile time | Allocation, locks, exceptions, non-nonblocking calls inside any `OB_NONBLOCKING` function | Every build; `-Werror` |
| Debug thread assertions | Calling a `[main-thread]` method from the audio thread and vice versa | Debug builds |
| RTSan | Anything the compiler could not see through — including inside libc | CI sanitizer matrix |
| TSan | Genuine data races between the roles | CI sanitizer matrix |

The compile-time check is the strongest of the four because it cannot be
skipped, but it only sees what it can inline. Two places in the codebase
suppress it with a written justification — `rt::monotonicNanos()` for the
commpage read and `ThreadCheck::current()` for the thread-local access. Adding a
third needs the same standard of argument.
