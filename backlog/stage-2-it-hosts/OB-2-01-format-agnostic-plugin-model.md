# OB-2-01 — Format-agnostic internal plugin model (CLAP semantics)

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature (engine) — architecture-critical |
| **Priority** | Blocker for all hosting work |
| **Dependencies** | OB-1-14, **OB-0-02** (spike P2 — `OB-2-08` builds on multi-window; answer it before hosting work stacks on the assumption) |
| **References** | D5, FR-PLG-04, FR-PLG-12 (structural), DM-Q5 |
| **Estimate** | L |

## Context

One internal abstraction over CLAP/VST3/AU, built to **CLAP's semantics** — the most expressive of the three — with VST3/AU later mapped *down* into it (D5). Getting this wrong means either rewriting hosting in Stage 5 or permanently discarding CLAP capabilities. The OB-1-08 sampler's minimal instrument interface grows into this model.

## Scope

Define `engine/src/plugin/` interfaces (internal C++, not the public extension API):

1. **`PluginInstance` lifecycle:** create → configure (rate/block size/port layout) → activate → process ↔ deactivate → destroy, matching CLAP's activation model; port reconfiguration allowed only while deactivated (DM-Q5: dynamic multi-out).
2. **Ports:** dynamic audio port lists (main + aux, in/out, channel layouts), note ports (with dialect: CLAP-note vs MIDI), per-port names and stable IDs.
3. **Events:** a unified, time-stamped in-block event list modeled on CLAP's: note on/off/choke/end, note expression, parameter value + **parameter modulation** (non-destructive offset — CLAP-only capability, first-class here), transport, MIDI passthrough. Formats lacking a concept receive a documented down-mapping (e.g. modulation → value for VST3) in their adapters, not in the model.
4. **Parameters:** stable IDs, ranges/steps/enums, text↔value conversion, flags (automatable, modulatable, per-note), rescan semantics; thread contract per CLAP (main-thread vs audio-thread functions documented and asserted).
5. **State:** opaque chunk save/load (FR-PLG-08 groundwork).
6. **Threading contract doc:** which model calls happen on which thread, mirrored from CLAP's `[main-thread]`/`[audio-thread]` annotations; debug assertions.
7. **Built-in adapter:** OB-1-08's sampler re-seated as the first `PluginInstance` implementation, proving instruments and future built-ins live behind the same model (precursor to FR-EXT-08).

## Acceptance criteria

- [x] Interfaces merged with the threading contract documented per method — `engine/src/plugin/`, [`docs/plugin-threading-contract.md`](../../docs/plugin-threading-contract.md).
- [x] Sampler runs behind `PluginInstance` with zero regression (OB-1-13 golden test still byte-identical).
- [x] Event-list handling is allocation-free on the audio thread (RTSan-verified via harness).
- [x] A design-review pass confirms: every CLAP 1.2 core concept (params, note expression, modulation, thread-pool hook point, dynamic ports) has a seat in the model or a documented exclusion — [`docs/clap-coverage.md`](../../docs/clap-coverage.md).
- [x] Human review completed (R4) — **delegated to the implementer by the maintainer on 13 August 2026** (sole maintainer, D7). See Review sign-off below.

## Out of scope

- CLAP adapter itself (OB-2-07), VST3/AU adapters (Stage 5), the WASM/public API (Stage 6).

## Close-out

**What shipped.** `engine/src/plugin/` — `plugin_types.h` (IDs, fixed text,
thread checking), `event.h` (the unified event and the RT event list),
`ports.h`, `parameters.h`, `state.h`, `host.h`, `plugin_instance.h`, and
`builtin/sampler_plugin.{h,cpp}`.

**`core::Instrument` is gone.** v0.1's minimal instrument interface was the
ancestor of this model, and keeping both would have left two processor
abstractions — precisely what FR-PLG-04 says there must not be. `core::Sampler`
is now only a voice allocator; `plugin::builtin::SamplerPlugin` gives it a
format-agnostic face, and `Engine` holds a `PluginInstance` and nothing else.
The test harness's `EventCaptureInstrument` became `EventCapturePlugin`, a full
`PluginInstance` — a test double that satisfies the real interface is a standing
check that the interface is implementable.

**Sample-accurate event timing moved into the model.** `Engine::runSchedule`
used to split the block at every event and call `Sampler::noteOn` directly. It
now builds a `PluginEvent` list per chunk and makes one `process()` call; the
splitting happens inside the instrument. Commands (`OB_CMD_NOTE_ON`, seek, stop)
became events at frame 0 rather than immediate calls, and a loop wrap became a
wildcarded note-off — which is how CLAP expresses "all notes off", so the model
needed no panic event.

**Byte-identical, verified against the previous commit rather than against
itself.** A worktree at the pre-refactor `HEAD` and the new tree each rendered
the devtool's 4-second demo (which includes a loop wrap): identical SHA-256. The
render checksum is now pinned in `test_plugin_model.cpp` so a future change to
the event path cannot quietly alter the audio.

**Two parameters were added to the sampler** (gain, transpose) to make the
parameter and modulation paths real rather than theoretical. At their defaults
they are exactly neutral — `x * 1.0f == x`, `key + 0 == key` — which is why the
byte-identical result holds, and there is a test asserting exact equality
between a render with and without them set explicitly.

**Verification.** 75 doctest cases green, plus ASan and TSan locally. **RTSan was
not run locally** — Homebrew LLVM is not installed on this machine and Xcode's
clang has no RTSan — so the allocation-free claim rests on the compile-time
`-Wfunction-effects` proof (which is `-Werror` on every build) and on CI's
sanitizer matrix. `test_stress_publish.cpp` gains a case built for that target:
20,000 scheduled notes with interleaved transport commands, deliberately
overfilling the event list so the drop-and-count path runs too.

**Deviations worth knowing.**

1. The host may call `process()` **more than once per audio callback** — OneBeat
   splits at loop seams. `beginAudioBlock()` (a OneBeat extension, not CLAP)
   marks the real callback boundary for RCU epoch ticking.
2. Tempo changes never reach the instrument: tempo is the host's clock, applied
   between chunks exactly where v0.1 applied it. Preserving that ordering is
   what keeps the transport position arithmetic bit-identical.
3. `PluginEvent` is fixed-size (40 bytes), unlike CLAP's variable-size events.
   Rationale and cost in `docs/clap-coverage.md`.
4. `HostBridge` records and logs rather than acting on `requestRestart()` — the
   graph rebuild that would honour it arrives with OB-2-05/OB-2-07.

## Review sign-off (R4)

Signed by the implementer under the maintainer's standing delegation of
13 August 2026, and recorded as such rather than presented as a second reader.

What was actually checked, beyond the ACs:

- **Every `OB_NONBLOCKING` frame in the new code compiles under `-Werror
  -Wfunction-effects`**, which is the real audio-thread guarantee. No new
  suppression pragma was added — the count in the codebase is still two, both
  pre-existing and both justified in place.
- **The thread contract is asserted, not just documented.** `ThreadCheck` traps
  on a `[main-thread]` method called from the audio thread and vice versa, and
  `ScopedAudioThread` exists so tests satisfy the assertion honestly instead of
  weakening it.
- **The refactor is byte-identical against the previous commit**, not against
  itself: a worktree at pre-refactor HEAD and the new tree rendered the same
  SHA-256, and the checksum is pinned in `test_plugin_model.cpp`.
- **No ABI change**, so nothing in the Dart layer moved.
- RTSan is green in CI (it could not run locally; no Homebrew LLVM on the dev
  machine).

Open item carried, not blocking: multi-instance behaviour of the model is
unexercised — there is one instrument. OB-2-07 is where that first gets real.
