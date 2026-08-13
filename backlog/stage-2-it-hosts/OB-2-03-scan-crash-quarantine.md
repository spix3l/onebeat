# OB-2-03 — Scan crash quarantine & reporting

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature |
| **Priority** | High |
| **Dependencies** | OB-2-02, OB-2-05 |
| **References** | FR-PLG-06, G3; design screen `onebeat-fail-plugin.html` |
| **Estimate** | S |

## Context

Plugins crash during scan; the scan must survive, mark the offender, and tell the user plainly (FR-PLG-06). The failure state is already designed (`onebeat-fail-plugin.html`).

## Scope

1. **Detection:** helper-process death during a scan of plugin X → X is recorded as quarantined with the failure phase (load/enumerate/instantiate) and signal; scan continues with the next plugin. A watchdog timeout (hang ≠ crash) also quarantines.
2. **Persistence:** quarantine status + reason in the scan cache; quarantined plugins skipped on future scans unless the user retries or the bundle version changes (auto-retry once on version change).
3. **UI:** per the designed failure screen — plugin name, what happened in plain language, actions: *Retry scan*, *Keep quarantined*; a quarantined section in the plugin list; error copy follows FR-UX-12 (what happened + what to do next, no apologies).
4. **Reporting:** helper writes a crash-context file (plugin path, phase, stack if available) into the session log directory (OB-1-12).

## Acceptance criteria

- [x] A deliberately-crashing test plugin (built in-repo: crashes on entry) is quarantined; the scan completes for remaining plugins; the app never dies.
- [x] A hanging test plugin trips the watchdog and is quarantined.
- [x] Quarantine persists across restarts; *Retry* re-scans exactly that plugin; version bump triggers one auto-retry.
- [x] UI implements the designed failure state; copy reviewed against FR-UX-12.

## Out of scope

- Crashes during *processing* (OB-2-05's runtime containment).

## Close-out evidence

| Criterion | Evidence |
|---|---|
| Crash containment and scan continuation | `test_plugin_quarantine.cpp`: the real crash-on-load `.clap` dies in its helper, is stored with phase and signal/exit status, the healthy bundle is still returned, and the test process survives. |
| Hang containment | The real constructor-hang fixture hits a 1.5 s test watchdog and is quarantined as `TimedOut`; the shipping default remains 15 s. |
| Persistence and retries | Tests reload the binary cache without reopening the quarantined bundle, retry exactly one path while preserving other rows, and change `Info.plist` to prove one automatic retry on a new fingerprint. |
| Reporting | The crash-context test checks plugin path, phase, signal/exit status and stack context; the helper-missing test verifies the fallback is logged rather than silent. |
| UI and copy | `plugin_quarantine_copy_test.dart` pins plugin name, crash vs timeout, phase wording, consequence and next actions, and rejects apologies/exclamation marks. Token lint is clean. |
| Build product | `tools/build.sh` embeds and ad-hoc signs `onebeat-plugin-host` in every product bundle's `Contents/MacOS/`, where helper discovery looks for it. |
| Full CI | [GitHub Actions run 31713136840](https://github.com/spix3l/onebeat/actions/runs/31713136840) passed Debug, Release, ASan/UBSan, TSan, RTSan, clang-format, clang-tidy, seams, token lint, licence audit, regenerated-bindings check, Flutter tests, headless FFI smoke test and macOS app build. |

The referenced `onebeat-fail-plugin.html` is not present in this repository, so
pixel matching it was not possible and is not claimed. This ticket implements
the specified information hierarchy and interactions in the existing F10 debug
library; OB-2-10 owns the final plugin-browser presentation.

*Keep quarantined* is deliberately a UI-only dismissal for the current app
session. It neither creates engine state nor removes the persistent quarantine.

## Decisions

- One helper process is spawned per bundle. A plugin cannot corrupt the parent
  scanner or the next bundle's scan state.
- Framed descriptor records use file descriptor 3. Stdout is not a protocol
  because loaded third-party code can write to it.
- The watchdog is 15 seconds in shipping code. Timeout is distinct from crash
  so the user and crash report describe what actually happened.
- Cache schema 2 replaces schema 1 rather than migrating it. The cache is a
  reproducible index, so rebuilding is safer and simpler than transforming raw
  POD rows whose layout changed.
- The helper exits with `_exit(0)` after a clean scan so plugin-owned `atexit`
  handlers cannot turn successful enumeration into a parent-process failure.

## ABI 1.2 — ADR-002 §8 checklist

1. **Additive?** Yes. `ob_engine_plugin_retry` is new and the three 32-bit
   failure fields are appended after every ABI 1.1 field. Minor bump 1.1 → 1.2.
2. **Still compiles as C?** Yes; `abi_header_is_c` passes.
3. **Offsets recorded?** Yes. Existing offsets remain fixed and
   `ob_plugin_info` is now 1000 bytes, with new offsets 984, 988 and 992.
4. **Thread and blocking behaviour documented?** Yes. Retry is main/UI-thread,
   copies its path, launches background work and never waits for the probe.
5. **Pointer ownership?** The caller owns `utf8_path`; the function copies it
   during the call and retains no pointer.
6. **UI path allocation-free per frame?** Yes. Retry is a user action. Normal
   list reads still happen only when `list_generation` changes.
7. **Bindings regenerated?** Yes, with ffigen 19.1.0; generated Dart is checked in.
8. **Human review?** Self-signed under the standing delegation; see below.

## Review sign-off (R4)

Reviewed and signed off by the implementer under the maintainer's standing
delegation dated 13 August 2026. This is a self-review, not a claim that a
second person read the change.

- **No audio-thread code changed.** Helper supervision, filesystem work, cache
  updates and retry all stay outside `Engine::process`; seam check passes.
- **FFI boundary:** every ABI 1.1 field retains its offset; new fields are
  appended and zeroed before population; enum values match the cached engine
  values; Dart clamps untrusted integer values before enum lookup.
- **Pointer lifetime and exceptions:** retry rejects null/empty paths, copies
  the path before returning, catches allocation/standard exceptions, and lets
  no exception cross C. The Dart UTF-8 allocation is freed in `finally`.
- **Subprocess lifecycle:** phase is announced before risky plugin code; pipe
  file actions close before `dup2`; reads and `waitpid(WNOHANG)` share a bounded
  deadline; timeout kills and reaps the child.
- **Hostile plugins:** protocol framing is bounded and validated; stdout cannot
  corrupt it; fatal signals produce best-effort context then re-raise; plugin
  exit handlers never run in the helper.
- **CI:** the complete sanitizer, lint, audit and app matrix is green in GitHub
  Actions run 31713136840.
