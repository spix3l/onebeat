# OB-1-01 — Repository scaffolding & build system

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Infra |
| **Priority** | Blocker — everything depends on it |
| **Dependencies** | OB-0-05 (Flutter confirmed) |
| **References** | NFR-05, NFR-07, NFR-11, G7, D1, D2, D3 |
| **Estimate** | M |

## Context

The repo must be contributable from day one (G7): clone → running build in <15 min on a clean machine (NFR-07). Layout must confine platform-specific code to defined seams so v2 (Windows/Linux) is a port, not a rewrite (NFR-11).

## Scope

Monorepo layout:

```
engine/                 # C++20 core — platform-independent
  src/core/             # graph, schedule, transport, model (later)
  src/audio_io/         # abstract interface (FR-ENG-08)
  src/audio_io/coreaudio/  # the only CoreAudio-aware code
  src/abi/              # extern "C" surface (ADR-002)
  tests/
app/                    # Flutter application (Dart)
third_party/            # vendored deps (dr_libs, choc, readerwriterqueue, ...)
docs/adr/
backlog/
spikes/                 # Stage 0 archive, not built
tools/                  # CI scripts, lint scripts
```

- **Engine build:** CMake ≥3.28, C++20, Clang (Xcode toolchain), builds `libonebeat_engine.dylib` with the `extern "C"` surface exported and everything else hidden (`-fvisibility=hidden`).
- **App build:** standard Flutter macOS project consuming the dylib; a top-level script (`tools/build.sh`, plus `tools/dev.sh` for engine-rebuild + `flutter run`) drives both.
- Dependency vendoring policy: git submodules or vendored copies in `third_party/`, each with a `LICENSE` file present — feeds the licence audit (OB-1-02).
- `README.md` with build prerequisites and the three commands to a running app; `CONTRIBUTING.md` stub; MIT `LICENSE`.
- `.clang-format`, `.clang-tidy` baseline, Dart `analysis_options.yaml`.
- Repo stays **private** until OQ-1 (trademark) clears — note in README.

## Acceptance criteria

- [ ] On a clean macOS 14+ Apple Silicon machine with Xcode + Flutter installed: clone → documented commands → app window opens, in **under 15 minutes** (timed, recorded in README as the reference run).
- [ ] Engine builds standalone (no Flutter needed) with `cmake --build`; unit test target runs.
- [ ] No CoreAudio/AppKit includes outside `engine/src/audio_io/coreaudio/` and the app's platform folder (grep-able check, later enforced in CI).
- [ ] `flutter analyze` and `clang-tidy` run clean on the scaffold.

## Out of scope

- CI (OB-1-02). Any audio code (OB-1-05+).
