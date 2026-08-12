# OB-2-02 — Plugin scanner with persistent cache

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature |
| **Priority** | High |
| **Dependencies** | OB-2-01, OB-2-04 (scan runs out-of-process) |
| **References** | FR-PLG-05, NFR-04 |
| **Estimate** | M |

## Context

Scanning must never block startup (FR-PLG-05), and cold start with 500 cached plugins must stay under 5 s (NFR-04). Scanning executes in the sandbox helper process because plugins can crash during enumeration (see OB-2-03).

## Scope

1. **Locations:** standard CLAP paths (`/Library/Audio/Plug-Ins/CLAP`, `~/Library/Audio/Plug-Ins/CLAP`) + user-added directories; structure supports VST3/AU paths for Stage 5.
2. **Scan process:** background, incremental (mtime/size/bundle-version keyed), executed plugin-by-plugin in the helper process (OB-2-05); results streamed to the app as they arrive.
3. **Cache:** persistent store (SQLite or flat file — decide in-ticket) holding descriptor data: id, name, vendor, version, format, category/features, audio/note port summary, param count, file path, scan timestamp, quarantine status. Versioned schema; corrupt cache → rebuild, never crash.
4. **Startup behaviour:** app boots from cache immediately; rescan of changed/new bundles proceeds in background; UI store updates live.
5. **ABI/UI:** scan progress + plugin list exposed to Dart (ABI extension per ADR-002 policy); minimal debug listing until OB-2-10's UI.

## Acceptance criteria

- [ ] First run with N plugins installed: app is interactive immediately; list populates progressively.
- [ ] Second run: no rescan of unchanged plugins (verified by scan log); cold start to usable UI <5 s with a synthetic 500-entry cache (NFR-04 measured).
- [ ] Adding/removing/updating a plugin bundle is detected on next scan cycle.
- [ ] Deleting/corrupting the cache file: clean rebuild, no crash.

## Out of scope

- Quarantine handling (OB-2-03). Browser UX with search/favourites (FR-PLG-13, Stage 7+).
