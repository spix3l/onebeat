# OB-1-12 — Logging & diagnostics infrastructure

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Infra (engine + app) |
| **Priority** | Medium |
| **Dependencies** | OB-1-01, OB-1-06 |
| **References** | NFR-08, R4; groundwork for FR-UX-12 (errors that state what happened and what to do) |
| **Estimate** | S |

## Context

Debugging an RT engine without RT-safe logging leads to heisenbugs (logging changes timing) or sanitizer violations (logging allocates). Establish the diagnostics spine before the engine grows.

## Scope

1. **RT-safe log path:** fixed-size lock-free ring buffer of POD log records (id, level, timestamp, up to N numeric args — **no strings formatted on the RT thread**); drained and formatted by a background thread. Usable inside `[[clang::nonblocking]]` code.
2. **Non-RT logging:** conventional leveled logger (engine + Dart sides) writing to a rotating session log file in the app support directory.
3. **Dropout/xrun counter:** callback overrun detection (render time vs budget) counted and exposed in the snapshot — feeds the perf overlay (OB-1-11) and later NFR-02 soak tests.
4. **Crash groundwork:** install a crash handler that flushes logs and writes a marker file (full crash-recovery UX is Stage 3's auto-save ticket; here we just don't lose the logs).
5. Error taxonomy stub shared across ABI (status codes) and UI copy — one table, so FR-UX-12's "specific, actionable" errors have a single source.

## Acceptance criteria

- [ ] RT log call from inside the audio callback: RTSan clean, records appear formatted in the session log.
- [ ] Ring overflow drops records with a counted "dropped N" marker rather than blocking.
- [ ] Xrun counter visible in the snapshot and the debug overlay; provoked xrun (artificial load) increments it.
- [ ] Session log location documented; logs survive a `kill -9` (marker file test).

## Out of scope

- User-facing error dialogs (per-feature). Telemetry/analytics (none planned).
