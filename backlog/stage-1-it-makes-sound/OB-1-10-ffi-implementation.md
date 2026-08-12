# OB-1-10 — FFI implementation: command queue + frame snapshots

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (boundary) |
| **Priority** | Blocker for UI |
| **Dependencies** | OB-1-04 (ADR-002), OB-1-06, OB-1-09 |
| **References** | NFR-06, NFR-10, D4, R5, R6 |
| **Estimate** | M |

## Context

Implements ADR-002: the versioned `extern "C"` surface, the lock-free command path in, the lock-free snapshot path out, and the generated Dart bindings — the only door between the two worlds.

## Scope

1. **C side** (`engine/src/abi/`): implement `onebeat_abi.h` v1 — engine lifecycle, `ob_abi_version`, command submission (transport commands from OB-1-09), snapshot read (transport + master peak/RMS levels + engine CPU load + round-trip latency), event queue drain (device-change, errors), last-error message.
2. **Dart side** (`app/lib/src/engine/`): `ffigen` bindings wrapped in an idiomatic `EngineClient`: typed command methods; a per-frame `SnapshotReader` using external typed data, zero allocation per read (OB-0-04's winning mechanism); version check on startup with a hard, clear failure on mismatch.
3. **Threading enforcement:** debug assertions on calling threads per the ADR-002 contract; the Dart side documents which zone/isolate owns the engine handle.
4. **ABI freeze test:** a C test asserting `sizeof`/`offsetof` of every snapshot/command struct against recorded values — fails on accidental layout drift (R5).
5. Soak test: 10-minute run, UI ticker reading snapshots at 120 Hz while a script hammers commands — TSan/ASan clean, zero Dart steady-state allocation growth.

## Acceptance criteria

- [ ] Dart starts the engine, plays/stops/seeks/sets tempo; state changes visible in snapshots within one frame.
- [ ] Snapshot read is allocation-free in steady state (DevTools verified) and <0.1 ms per read in profile mode.
- [ ] ABI freeze test in CI; version mismatch produces the designed error, not a crash.
- [ ] Soak test passes under TSan and ASan.
- [ ] Human review completed (R4 — FFI boundary, no exceptions).

## Out of scope

- Plugin/model commands (added per-stage under the ADR-002 evolution policy).
