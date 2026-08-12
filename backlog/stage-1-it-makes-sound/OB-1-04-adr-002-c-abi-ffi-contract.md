# OB-1-04 — ADR-002: the C ABI / FFI contract

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Design / ADR |
| **Priority** | Blocker for OB-1-10/11 — NFR-10 requires this ADR before UI work |
| **Dependencies** | OB-0-04 (P4 findings), OB-1-01 |
| **References** | NFR-10, NFR-06, D4, R5, R6 |
| **Estimate** | M |

## Context

The Dart↔C++ boundary is a product surface (D4). Early mistakes ossify (R5). NFR-10 fixes the shape: **commands in, snapshots out**; narrow, hand-designed, versioned; Dart never polls, allocates on, or blocks the audio thread; audio-thread state reaches Dart only via lock-free snapshots sampled at frame rate.

## Scope

Write `docs/adr/ADR-002-ffi-contract.md` plus the initial header `engine/src/abi/onebeat_abi.h`, deciding:

1. **Versioning:** `ob_abi_version()` returning semver; Dart refuses mismatched major. Header is the single source of truth; `ffigen` generates bindings from it (no hand-written bindings).
2. **Lifecycle:** `ob_engine_create/destroy`, error model (status codes + `ob_last_error_message` pattern — no exceptions across the boundary, ever).
3. **Command channel (UI → engine):** serialized command structs pushed onto a lock-free SPSC queue (`readerwriterqueue`) drained by the engine off the audio thread where possible, or at callback top for RT-relevant commands. Commands are fire-and-forget with generation counters; no synchronous calls that block the UI on the audio thread (NFR-06).
4. **Snapshot channel (engine → UI):** the mechanism won in OB-0-04 (seqlock or double buffer), fixed layout struct (version-tagged) containing transport state, playhead, master/track peak levels, CPU load. Dart reads once per frame via typed-data view, zero allocation.
5. **Event/notification channel** for non-frame-rate events (errors, device changes): lock-free MPSC queue drained by a Dart ticker or `NativePort` — decide and record.
6. **Threading contract:** which thread each ABI function may be called from, documented per function; assertions in debug builds.
7. **String/blob passing rules** (UTF-8, ownership, who frees).
8. **Evolution policy:** additive-only within a major; deprecation pattern; the ABI check test (OB-1-13) that fails on layout drift.

## Acceptance criteria

- [ ] ADR-002 merged, covering all eight points with rationale.
- [ ] `onebeat_abi.h` compiles standalone as C (`-x c`), documented per function (thread, blocking behaviour, ownership).
- [ ] `ffigen` generates Dart bindings from the header in the build.
- [ ] A review checklist for future ABI changes is included (R5 mitigation) and referenced by `CONTRIBUTING.md`.
- [ ] Human review completed (R4 — FFI boundary).

## Out of scope

- The implementation (OB-1-10). Plugin-related commands (Stage 2 extends the ABI per the evolution policy).
