# How to write engine code

Everything reachable from the audio callback obeys these rules. They are not
style preferences: breaking one produces a click, a dropout, or a deadlock in
someone's recording session, and the failure will not reproduce on your machine.

This is the price of choosing C++ over Rust (D2, R4). We pay it in full.

## The one-line version

**If it can allocate, lock, throw, block, or take an unbounded amount of time,
it does not belong on the audio thread.**

## The mechanism

Every function reachable from the callback is marked `OB_NONBLOCKING`
(`engine/src/core/rt/rt.h`), which expands to `[[clang::nonblocking]]`:

```cpp
void Engine::process(const ProcessContext& context) noexcept OB_NONBLOCKING;
```

Two checks enforce it.

1. **At compile time** — Clang's function effect analysis, with
   `-Wfunction-effects -Werror`. It proves the body performs no allocation, no
   lock, no exception, and no call to a function that is not itself nonblocking.
   A violation is a build failure, not a warning.
2. **At run time** — RealtimeSanitizer, on the engine test suite in CI. It
   catches what the compiler cannot see through: a `malloc` inside a system
   library, a lock inside a third-party call, a syscall behind an inline
   wrapper.

RTSan needs LLVM ≥ 20. Xcode's Clang does not ship it:

```sh
brew install llvm
cmake -S engine -B build-rtsan -DONEBEAT_RTSAN=ON \
      -DCMAKE_CXX_COMPILER=$(brew --prefix llvm)/bin/clang++ \
      -DCMAKE_C_COMPILER=$(brew --prefix llvm)/bin/clang
cmake --build build-rtsan && ctest --test-dir build-rtsan
```

`tools/ci_local.sh` runs the same matrix CI does, and tells you loudly if RTSan
is missing rather than skipping it quietly.

## The rules

### Never on the audio thread

| Forbidden | Instead |
|---|---|
| `new`, `delete`, `malloc`, `std::vector::push_back`, `std::string` | pre-allocate at `prepare()` time; fixed-size arrays with a count |
| `std::mutex`, `std::lock_guard`, any lock | publish immutable data with `rt::NonRealtimeMutable<T>` |
| `throw`, anything that can throw | status codes; `noexcept` on every RT function |
| file I/O, `printf`, logging that formats text | `rt::RtLog` — POD records, formatted off-thread |
| `std::function`, virtual calls to non-nonblocking targets | direct calls, or interfaces whose methods are `OB_NONBLOCKING` |
| unbounded loops, `while (queue.pop())` without a cap | bound every loop; drain at most N per block |
| `sleep`, `yield`, condition variables | never wait on the audio thread |
| `dynamic_cast`, RTTI | design it out |

### …and you cannot busy-wait instead

The obvious escape from "never block" is to spin. It does not work on this
platform, and the reason is worth knowing before you reach for it.

The audio thread runs under `THREAD_TIME_CONSTRAINT_POLICY`, which is a
*contract*: it declares how much computation the thread needs per period. A
thread that spins consumes 100 % of every period, breaks that contract, and gets
demoted by the scheduler. Measured in `spikes/ipc_roundtrip` (OB-2-04): a
spinning helper thread answered for 3.4 seconds and then stopped answering
permanently. The same thread at default priority ran indefinitely.

So spinning is not a trade of CPU for latency on an RT thread. It is a way to
lose the thread.

**The one sanctioned wait** is the bounded wait on a sandboxed plugin helper,
decided in [ADR-003](adr/ADR-003-sandbox-ipc.md): a `semaphore_timedwait` with a
deadline of a fraction of the block period, where missing the deadline produces
silence rather than a late block. It is bounded, it is measured, and the failure
path is demonstrated. Anything else that wants to wait needs the same standard
of argument.

### Always on the audio thread

- **One atomic load per block** for anything published from another thread, at
  the top of the block, through `NonRealtimeMutable::acquire()`.
- **One epoch tick per block** — `beginBlock()` on every publisher you read.
  Reclamation correctness depends on it (the proof is in
  `engine/src/core/rt/publisher.h`).
- **Sample-accurate event offsets.** Split the block at event boundaries rather
  than rounding events to block starts.
- **Flush-to-zero.** `rt::enableFlushToZero()` on the first callback. Denormals
  turn a decaying reverb tail into a 100× CPU spike and break bit-exactness.

### Off the audio thread

Anything that allocates, decodes, opens a file, or talks to the system:

- build the thing completely, off-thread, as an immutable object;
- `publish()` it;
- let the reclamation pass free the old one when the audio thread provably
  cannot reach it.

That pattern — build, publish, retire — is the whole architecture in three
words. The flattened schedule (`core/schedule.h`) and the sampler's sample data
are both instances of it, and so is everything Stage 3 adds.

### Never traverse a reference graph

The audio thread reads the flattened schedule and nothing else. It does not walk
`PatternClip → Pattern → Instrument`. This is ARCHITECTURE.md §7 and
anti-pattern #7, and it is the single decision that cannot be retrofitted.

## Reviewing engine code

Human review is mandatory for every audio-thread and FFI-boundary change (R4,
PLAN.md §5.2). No exceptions, no "it's a small change".

- [ ] Every new function on the RT path is `noexcept OB_NONBLOCKING`.
- [ ] No allocation, lock, or unbounded loop — including inside anything it calls.
- [ ] Publishers get exactly one `beginBlock()` per block.
- [ ] The audio thread reads no shared mutable state except through an atomic.
- [ ] Buffers are pre-sized; nothing indexes past `num_frames`.
- [ ] The change is covered by an offline-render test (deterministic, bit-exact).
- [ ] Sanitizer matrix green: ASan, UBSan, TSan, RTSan.

## When you must suppress a check

Occasionally the compiler cannot see through a system header — for example
`mach_absolute_time()`, which is a commpage read with no syscall behind it.
Suppress narrowly, at the call, with a comment explaining why it is safe, and
rely on RTSan to verify at run time:

```cpp
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"
  const uint64_t ticks = mach_absolute_time();
#pragma clang diagnostic pop
```

There is currently exactly one of these in the engine. Adding a second one is a
conversation, not a commit.
