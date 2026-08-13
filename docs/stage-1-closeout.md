# Stage 1 closeout — v0.1 "it makes sound"

**Date:** 13 August 2026
**Ticket:** OB-1-14
**Exit criterion (PRD §10):** *a note plays without glitching, a meter moves
smoothly, RTSan is clean.*

## Verdict

Two of the three exit criteria are demonstrated. The third — RTSan clean — is
**wired but not yet executed**, because RealtimeSanitizer requires an LLVM ≥ 20
toolchain that is not installed on the development machine. See "Open items"
below. **Stage 1 does not close until that run is green** (PLAN.md gate G-C).

## 1. A note plays without glitching

Verified two ways.

**In the app** (Profile build, default output device, 48 kHz / 128 frames):
playback of the built-in 16-step pattern for 60 s continuously, with the sampler
triggering throughout.

| Measurement | Result |
|---|---|
| xruns (callback overruns) | **0** |
| engine CPU load | < 1 % |
| active voices | 1–2 sustained |
| round-trip latency | **5.73 ms** (budget: < 10 ms, NFR-01) |

**Across every supported format** (`onebeat_devtool formats`) — all 24
combinations of 44.1/48/88.2/96 kHz and 64/128/256/512/1024/2048 frames opened,
played audibly, and reported zero xruns:

```
  44100 Hz /   64 frames  granted   44100 Hz /   64  latency   4.65 ms  peak 0.54  xruns 0
  48000 Hz /  128 frames  granted   48000 Hz /  128  latency   5.73 ms  peak 0.63  xruns 0
  96000 Hz / 2048 frames  granted   96000 Hz / 2048  latency  24.40 ms  peak 0.78  xruns 0
  … (full sweep in the ticket; every row xruns 0)
```

Click-freedom is additionally covered by tests rather than by ear: the sampler's
note-off and voice-steal paths are asserted to produce no sample-to-sample jump
above threshold (`engine/tests/test_sampler.cpp`).

## 2. A meter moves smoothly

Profile build, 60 s of continuous playback with the meter live and the
frame-timing overlay recording:

| Measurement | Result |
|---|---|
| frames rendered | **3797** |
| **dropped frames** | **0** |
| average build time | 2.20 ms |
| average raster time | 1.35 ms |
| worst frame | 23.36 ms (the first frame after toggling the overlay on) |
| frame budget | 16.67 ms |

**Caveat, and it matters:** the development machine's display runs at **60 Hz**,
so this is a zero-dropped-frame result at 60 Hz, not at the 120 Hz the ticket
asks for. The budget is read from the display at run time, so the same
measurement on a ProMotion panel will report an 8.33 ms budget — it has not been
run there yet. Carried forward as an open item.

The meter's ballistics are driven by the snapshot's wall-clock timestamp rather
than by a frame counter, and there is a test proving the decay rate is identical
at 120 Hz and at 12 Hz (`app/test/meter_state_test.dart`).

## 3. RTSan is clean

**Not yet run.** Apple's Clang does not ship RealtimeSanitizer:

```
clang++: error: unsupported option '-fsanitize=realtime' for target 'arm64-apple-darwin25.6.0'
```

What is in place:

- Every audio-thread function is marked `OB_NONBLOCKING` (`[[clang::nonblocking]]`)
  and the **compile-time** half of the check is already enforced and green:
  `-Wfunction-effects -Werror` is on for every engine build, and it caught real
  violations during development (an unannotated queue, a lock-guarded timebase
  cache, a `push_back` on the capture instrument).
- `-DONEBEAT_RTSAN=ON` is implemented and fails configuration with instructions
  if the toolchain lacks RTSan.
- The CI `sanitizers` matrix installs Homebrew LLVM and runs the RTSan job as a
  merge-blocking check.
- `tools/ci_local.sh` reports RTSan as a **failure**, not a skip, when the
  toolchain is missing.

To close it: `brew install llvm && tools/ci_local.sh sanitizers`.

The same toolchain gap means **clang-tidy has not been run either** (Xcode ships
clang-format but not clang-tidy), so OB-1-01's "clang-tidy runs clean" criterion
is also outstanding. `clang-format --dry-run --Werror` is clean across the whole
engine.

## Other sanitizers, run and green

| Build | Result |
|---|---|
| ASan + UBSan (Debug) | all suites pass |
| TSan (Debug) | all suites pass, including 1000+ schedule publishes during continuous playback |
| Debug / RelWithDebInfo | all suites pass |

## 4. Stage 0 constraints

Stage 0 was not executed as a separate set of spikes — the four questions were
answered by the real implementation instead, which is a deviation from the plan
worth recording:

| Spike | Question | Answer from the real code |
|---|---|---|
| P1 | CustomPainter at 120 Hz | Not yet answered at 120 Hz. Zero dropped frames at 60 Hz with a CustomPainter meter and a CustomPainter clock; needs a ProMotion display to close. |
| P2 | Panel tear-off into a second window | **Not answered.** No multi-window work exists yet; the first ticket that needs it is Stage 8's workspace. Risk carried. |
| P3 | Finder drag-and-drop | **Not answered.** First needed by the browser (Stage 7). Risk carried. |
| P4 | FFI snapshot cost | Answered: a seqlock read through one C call per frame, into a struct allocated once. 3797 frames with a 2.20 ms average build time including the snapshot read; no measurable per-frame cost. |

ADR-001 has not been written. The Flutter decision is *de facto* confirmed by
the working app, but P2 and P3 remain genuinely open, and pretending otherwise
would be dishonest. Carried forward.

## 5. Clone to build

`tools/build.sh --debug` from a deleted `build/` and `app/build/`, warm Xcode and
pub caches: **19 s**. The cold path (fresh runner, no caches) is measured by the
`clone-to-build` CI job against the 900 s budget on every push.

## Accepted debt, carried into the backlog

Each of these should become a ticket before Stage 2 feature work starts.

| # | Item | Why it was deferred | Lands in |
|---|---|---|---|
| D1 | RTSan has never been executed, and neither has clang-tidy (both need Homebrew LLVM; Xcode ships neither RTSan nor clang-tidy) | Toolchain not installed on the development machine; the CI jobs are written but the repository has had no CI runs yet | Immediately — RTSan blocks the gate |
| D2 | 120 Hz measurement outstanding | No ProMotion display available | Whenever the measurement can be made on suitable hardware |
| D3 | ADR-001 (Flutter go/no-go) unwritten; spikes P2 and P3 unanswered | Stage 1 was built directly; the risks they cover do not bite until Stages 7–8 | Before Stage 7 |
| D4 | The engine dylib is copied into the bundle by a build script, not embedded by Xcode, and is ad-hoc signed | Proper embedding, signing and notarization is Stage 2 (OB-2-06) | OB-2-06 |
| D5 | No `flutter_test` widget tests for the shell — only token, contrast and ballistics unit tests, plus the headless FFI smoke test | Widget/interaction test infrastructure is scheduled for OB-3-14 | OB-3-14 |
| D6 | Sample loading is WAV-only, and only via the fallback path in the UI (no file picker) | Browser and multi-format decode are Stage 7 | Stage 7 |
| D7 | `ob_engine_set_step_pattern` is a content stand-in on the ABI | Real model edits arrive with the domain model | OB-3-02 / OB-3-04 |
| D8 | The demo pads in the empty state are not a designed instrument UI | The channel rack replaces them | OB-3-09 |

## Sign-off

- [ ] RTSan run green (D1)
- [ ] Project owner signs off Stage 1 as closed

Until both boxes are ticked, Stage 2 feature work does not start; unblocked
infrastructure work may (PLAN.md gate G-C).
