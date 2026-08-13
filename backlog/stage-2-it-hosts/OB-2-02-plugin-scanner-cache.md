# OB-2-02 — Plugin scanner with persistent cache

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature |
| **Priority** | High |
| **Dependencies** | OB-2-01, OB-2-04 (scan runs out-of-process) |
| **References** | FR-PLG-05, NFR-04 |
| **Estimate** | M |
| **Status** | ✅ Done (13 August 2026) |

## Context

Scanning must never block startup (FR-PLG-05), and cold start with 500 cached plugins must stay under 5 s (NFR-04). Scanning executes in the sandbox helper process because plugins can crash during enumeration (see OB-2-03).

## Scope

1. **Locations:** standard CLAP paths (`/Library/Audio/Plug-Ins/CLAP`, `~/Library/Audio/Plug-Ins/CLAP`) + user-added directories; structure supports VST3/AU paths for Stage 5.
2. **Scan process:** background, incremental (mtime/size/bundle-version keyed), executed plugin-by-plugin in the helper process (OB-2-05); results streamed to the app as they arrive.
3. **Cache:** persistent store (SQLite or flat file — decide in-ticket) holding descriptor data: id, name, vendor, version, format, category/features, audio/note port summary, param count, file path, scan timestamp, quarantine status. Versioned schema; corrupt cache → rebuild, never crash.
4. **Startup behaviour:** app boots from cache immediately; rescan of changed/new bundles proceeds in background; UI store updates live.
5. **ABI/UI:** scan progress + plugin list exposed to Dart (ABI extension per ADR-002 policy); minimal debug listing until OB-2-10's UI.

## Acceptance criteria

- [x] First run with N plugins installed: app is interactive immediately; list populates progressively.
- [x] Second run: no rescan of unchanged plugins (verified by scan log); cold start to usable UI <5 s with a synthetic 500-entry cache (NFR-04 measured).
- [x] Adding/removing/updating a plugin bundle is detected on next scan cycle.
- [x] Deleting/corrupting the cache file: clean rebuild, no crash.

## Out of scope

- Quarantine handling (OB-2-03). Browser UX with search/favourites (FR-PLG-13, Stage 7+).

---

## Close-out

### What was built

`engine/src/plugin/scan/` — four pieces with one seam between them:

- **`descriptor.h`** — `PluginDescriptor`, a padding-free trivially-copyable POD.
  The absence of padding is asserted, not hoped for
  (`has_unique_object_representations_v`), because padding bytes are
  uninitialised and would both destabilise the cache checksum and write stack
  contents to disk.
- **`plugin_cache.{h,cpp}`** — the persistent store.
- **`scanner.{h,cpp}`** — discovery, fingerprint diff, background thread,
  streamed results, and the injected `ScanProbe`.
- **`plugin_library.{h,cpp}`** — the façade that owns the startup order.

Plus ABI 1.1 (four functions, two structs), the Dart client and store, a minimal
F10 listing, and `onebeat_devtool scan`.

### Decisions made in-ticket

**The cache is a versioned flat binary file, not SQLite.** The ticket left this
open. The descriptors are already fixed-capacity PODs (OB-2-01 chose that shape
deliberately), the access pattern is *read everything at boot, rewrite
everything after a scan*, and a dependency has to pass the licence audit and be
carried forever. 500 rows is 609 KiB and loads in 2.7 ms. The reasoning and the
trigger for revisiting it — FR-PLG-13's browser wants indexed search over a much
larger library — are recorded at the top of `plugin_cache.h`.

**The probe is injected, and the one that ships does not open plugins.**
Discovering `Diva.clap` and *loading* it are different acts: the second can
crash the process, which is why it belongs to OB-2-05 (safely) and OB-2-07
(meaningfully). So `ScanProbe` is an interface, and the shipping
`BundleNameProbe` reports one row per bundle named after the file with
`DescriptorFlagIntrospected` **unset**. The user's real library appears in the
list on first run with real names; every row says "found, not yet inspected"
rather than carrying invented port and parameter counts.

**Probes declare their capability, and a stronger probe re-examines weaker
rows.** Without this, every row written today would be reused forever once
OB-2-07 lands: the bundle never changed, so the fingerprint always matches, so
the row would never gain the information. `ScanProbe::capabilities()` compared
against `descriptor.flags` makes the upgrade automatic and costs exactly one
scan. There is a test for the one-time-ness.

**The cache lives beside the session logs.** `log_directory` now determines both,
so pointing the engine at a scratch directory keeps everything it writes
together — without which every ABI test would have silently overwritten the
developer's real plugin cache with an empty one.

### The sandbox had to go, and that is a real decision

The app was inheriting Flutter's macOS template, which turns the **App Sandbox
on**. Under it the scan finds exactly zero plugins in a shipped build: there is
no entitlement for `/Library/Audio/Plug-Ins`, and `$HOME` is redirected into a
container that plugin installers know nothing about. This was found the honest
way — the measurement run produced a populated list from the terminal and an
empty one from the `.app`, and the engine's log was in
`~/Library/Containers/dev.onebeat.onebeat/…`.

Both entitlements files now disable the sandbox, with the argument written into
them. This is the same position every shipping macOS DAW takes: Developer ID and
notarization rather than the Mac App Store. What replaces the sandbox as the
containment story is ADR-003's helper process, which is what actually protects
the user's work (G3) — and which a sandboxed app could not spawn as designed
anyway. **`OB-2-06` (Gate G-B) owns signing and notarization and should confirm
this**; a note has been added there.

### Evidence

Measured on this machine against a synthetic 500-bundle library
(`ONEBEAT_PLUGIN_PATH=… onebeat_devtool scan`):

| | |
|---|---|
| Cold scan, 500 bundles | 43 ms, 500 opened, 0 reused |
| Second scan, nothing changed | **500 reused, 0 opened** |
| Cache load, 500 entries | **2.7–3.8 ms** (609 KiB) |
| One bundle updated, one removed, one added | 498 reused, **2 opened**, removed row dropped |
| **App cold start → usable window, 500 cached plugins** | **274–566 ms wall clock** (85–99 ms of it Dart-entry-to-first-usable-frame) — against NFR-04's 5 s |

The startup number is printed on every launch (`onebeat: usable in … ms with …
plug-ins from cache`) rather than measured once into a document that then goes
stale.

`engine/tests/test_plugin_scan.cpp` covers all four criteria plus ten distinct
ways a cache file can be wrong — truncated in the header, truncated
mid-descriptor, empty, wrong magic, unknown schema, a flipped bit, an entry
count that would allocate a terabyte, an entry count larger than the file,
trailing bytes, and random bytes of the right length. Every one produces an
empty cache and a rebuild. A separate test hand-builds a file whose checksum is
*valid* but whose text is unterminated and whose enum is out of range, because
the checksum cannot catch a file someone edited on purpose — that is the one
memory-safety hazard in a POD cache, and it is repaired on load.

### What was found while building it

- **Two `noexcept` markers were lies.** clang-tidy's `bugprone-exception-escape`
  caught `isBundle` and `fingerprintBundle`, both of which allocate strings and
  do filesystem work. A throw from either would have terminated the process.
  They are no longer `noexcept`, and the scanner thread's entry point now
  catches everything and ends the scan as cancelled — an exception on a
  background thread otherwise calls `std::terminate`, and losing the user's
  session to a scan is absurd.
- **The startup stopwatch measured zero.** A top-level `final Stopwatch =
  Stopwatch()..start()` in Dart is *lazy*: it is not constructed until first
  read, which is the moment the elapsed time is asked for. It now starts
  explicitly at the top of `main`, with the trap written down next to it.
- **Event text was being decoded byte-by-byte**, which renders any non-ASCII
  device or plugin name as mojibake. Both paths now decode UTF-8 properly.

### ABI 1.1 — the ADR-002 §8 checklist

1. **Additive?** Yes: four new functions and two new structs, no existing field
   moved, resized or repurposed. Minor bump, 1.0.0 → 1.1.0.
2. **Still compiles as C?** Yes — `ctest -R abi_header_is_c` green.
3. **Offsets recorded?** Yes, `ob_plugin_scan_status` (288 bytes) and
   `ob_plugin_info` (984 bytes) are frozen in `test_abi.cpp`.
4. **Thread and blocking behaviour documented?** Yes, per function in the
   header. `ob_engine_plugin_cache_load` is the only one that may block.
5. **Pointer ownership?** No new pointers cross the boundary. Both structs are
   caller-owned and copied into; the directory list is a caller-owned buffer
   read during the call and not retained.
6. **UI path still allocation-free per frame?** Yes. The list is copied only
   when `list_generation` moves, and `ob_engine_plugin_scan_status` is called
   per frame only while a scan is actually running.
7. **Bindings regenerated?** Yes, `app/lib/src/engine/generated/` is checked in.
8. **Human review?** See below.

The one thing worth arguing with: ADR-002 says a synchronous "ask the engine and
wait" call does not exist and will not be added. `ob_engine_plugin_at` is
synchronous. The rule is about state the *audio thread* owns — the coupling
NFR-06 forbids — and the plugin list is main-thread-owned data read from a file
and a background thread, with no seqlock and no audio thread anywhere near it.
The header says so explicitly so that the next reader does not have to
re-derive it.

## Review sign-off (R4)

Reviewed and signed off by the implementer. On 13 August 2026 the maintainer
delegated the R4 human-review criterion; this records what was actually checked
rather than implying a second reader.

- **No audio-thread code in this ticket.** Nothing under `plugin/scan/` is
  `OB_NONBLOCKING`, nothing is called from `Engine::process`, and the plugin
  library is deliberately owned by the ABI handle rather than by `Engine` so
  that it stays out of the RT surface entirely. Verified by grep and by the
  seam check.
- **FFI boundary** reviewed against ADR-002 §8, item by item, above. The two
  new structs are POD, `memset` before every write, every text field copied
  with a truncating always-terminating helper rather than `strncpy`.
- **Threading:** the scanner's background thread shares exactly two things with
  its owner — a mutex-guarded progress/pending block, and two atomics. The cache
  itself is never shared: it is snapshotted before the thread starts and written
  back after it ends. TSan green.
- **Hostile input:** the cache is parsed defensively (bounded entry count before
  any allocation, exact-size check, checksum, then per-row sanitisation), which
  is the part of this ticket most worth a second pair of eyes and got the most
  tests.
- CI green including the sanitizer matrix; clang-tidy run locally over
  `engine/src/plugin/` before pushing.
