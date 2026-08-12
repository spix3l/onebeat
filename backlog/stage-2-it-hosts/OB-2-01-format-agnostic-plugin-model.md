# OB-2-01 — Format-agnostic internal plugin model (CLAP semantics)

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature (engine) — architecture-critical |
| **Priority** | Blocker for all hosting work |
| **Dependencies** | OB-1-14 |
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

- [ ] Interfaces merged with the threading contract documented per method.
- [ ] Sampler runs behind `PluginInstance` with zero regression (OB-1-13 golden test still byte-identical).
- [ ] Event-list handling is allocation-free on the audio thread (RTSan-verified via harness).
- [ ] A design-review pass confirms: every CLAP 1.2 core concept (params, note expression, modulation, thread-pool hook point, dynamic ports) has a seat in the model or a documented exclusion.
- [ ] Human review completed (R4).

## Out of scope

- CLAP adapter itself (OB-2-07), VST3/AU adapters (Stage 5), the WASM/public API (Stage 6).
