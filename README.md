# OneBeat

Open-source, MIT-licensed digital audio workstation built around FL Studio's
pattern-based production workflow. It hosts third-party plugins (CLAP, VST3, AU),
accepts user soundpacks, and ships with a small suite of built-in instruments and
effects. macOS first; Windows and Linux are a v2 target rather than an exclusion.

**Status: v0.1 — "it makes sound."** A note plays without glitching, a meter
moves smoothly, and the real-time discipline that everything else will be built
on is in place. There is no sequencer yet; that is v0.3.

> This repository stays private until the "OneBeat" trademark search clears (OQ-1).

## Build it

Prerequisites: macOS 14+ on Apple Silicon, Xcode command-line tools,
CMake ≥ 3.28, Flutter 3.44+.

```sh
git clone <repo> onebeat && cd onebeat
tools/build.sh          # engine + tests + app bundle
open app/build/macos/Build/Products/Release/onebeat.app
```

Clone to running app on a fresh machine with no caches: **73 s**, against a
15-minute budget (NFR-07). CI re-measures it on every push, so it cannot drift.
Incrementally, with caches warm, `tools/build.sh --debug` takes about 19 s.

For day-to-day work, `tools/dev.sh` rebuilds the engine and starts the app with
hot reload.

## Hear it without the app

The engine builds and runs standalone — no Flutter needed:

```sh
cmake -S engine -B build && cmake --build build -j8
ctest --test-dir build --output-on-failure

./build/onebeat_devtool devices        # list output devices
./build/onebeat_devtool play 8         # play a pattern for eight seconds
./build/onebeat_devtool formats        # every rate and buffer size, with latency
./build/onebeat_devtool render out.wav # offline render, no hardware required
```

## Using it

| | |
|---|---|
| **Space** | play / stop — always, whatever was clicked last |
| **Enter** | activate the focused control |
| **F8** | frame-timing overlay |
| **F9** | design-token specimen sheet |

## Layout

```
engine/            C++20 core — platform-independent
  src/core/          transport, schedule, sampler, real-time primitives
  src/core/rt/       the real-time toolkit; read docs/rt-rules.md first
  src/audio_io/      abstract device interface
    coreaudio/       the only CoreAudio-aware code in the repository
  src/abi/           the extern "C" surface — the only door to the app
  testing/           offline render driver and fixtures
  tests/             unit / engine / abi / stress suites
  tools/             onebeat_devtool
app/               Flutter macOS application
  lib/src/design/    design tokens — every colour and size in the app
  lib/src/engine/    FFI client (bindings generated from the ABI header)
  lib/src/ui/        widgets; tokens only, enforced by CI
third_party/       vendored dependencies, each with its licence
docs/adr/          architecture decision records
backlog/           tickets and epics
tools/             build, dev and CI scripts
```

## The three things that matter

1. **The audio thread never allocates, locks, or throws.** Enforced at compile
   time by `[[clang::nonblocking]]` and at run time by RealtimeSanitizer in CI.
   See `docs/rt-rules.md` before touching engine code.
2. **The audio thread never walks a reference graph.** Edits mutate the model
   off-thread; a flattening pass produces an immutable, time-ordered schedule
   published by atomic swap. `ARCHITECTURE.md` §7.
3. **The C ABI is a product surface**: commands in, snapshots out, versioned,
   frozen by a layout test. `docs/adr/ADR-002-ffi-contract.md`.

## Contributing

`CONTRIBUTING.md`. Run `tools/ci_local.sh` before opening a PR — it runs the same
matrix CI does, including the sanitizers.

## Licence

MIT (`LICENSE`). Every dependency is MIT, Apache-2.0, BSD, ISC, Zlib or public
domain; fonts are SIL OFL. Copyleft, including LGPL, fails the build
(`tools/license_audit.py`).
