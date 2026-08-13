# Contributing to OneBeat

## Before you start

Read `PLAN.md` §5 (ways of working) and pick a ticket from `backlog/`. A ticket
is pickable when its dependencies are ✅. Everything you need to do it should be
in the ticket file plus the PRD/ARCHITECTURE sections it references — if it is
not, that is a bug in the ticket; say so.

## Setting up

```sh
tools/build.sh              # builds everything, runs the engine tests
brew install llvm           # RealtimeSanitizer (Xcode's clang has no RTSan)
tools/ci_local.sh           # the full CI matrix, locally
```

## Definition of done

From `PLAN.md` §5.2, on every ticket:

- [ ] Every acceptance criterion demonstrably met — a test, a recording, or the
      reproducible manual check the AC specifies.
- [ ] CI green, including the full sanitizer matrix (ASan, UBSan, TSan, RTSan).
- [ ] **Human review of any audio-thread or FFI-boundary code. No exceptions.**
- [ ] New dependencies pass the licence audit.
- [ ] UI code uses tokens only; no functionality reachable only by right-click or
      an undocumented shortcut; destructive actions undoable.
- [ ] Sequencer-adjacent work re-checked against the anti-pattern table
      (`ARCHITECTURE.md` §6).

## Rules that are not negotiable

### Audio-thread code

Read `docs/rt-rules.md` first. No allocation, no locks, no exceptions, no
unbounded loops, no logging that formats text. The compiler checks it
(`-Wfunction-effects -Werror`), RTSan checks it, and a human checks it.

### The ABI

Changing `engine/src/abi/onebeat_abi.h` means answering the eight-point
checklist in `docs/adr/ADR-002-ffi-contract.md` §8 in your PR description.
Layout changes are a major-version event, not an edit.

Bindings are generated, never hand-written:

```sh
cd app && dart run ffigen --config ffigen.yaml
```

CI fails if the checked-in bindings differ from a fresh generation.

### The UI

Every colour, size, spacing, radius and duration comes from
`app/lib/src/design/tokens.dart`. `tools/token_lint.py` fails the build on
literals. If a number genuinely is not a visual dimension, annotate the line
with `// token-lint-ok: why`.

Empty states and error states are designed in the same ticket as the feature,
not afterwards (FR-UX-12/13).

### Platform code

CoreAudio, AppKit and friends may only be included from
`engine/src/audio_io/coreaudio/` and the app's platform folder.
`tools/seam_check.sh` enforces it, because v2's Windows and Linux backends have
to be a port rather than a rewrite (NFR-11).

## Style

- C++: `.clang-format` (Google-derived, 100 columns) and `.clang-tidy`. Both run
  in CI, which installs Homebrew LLVM for them (`.github/actions/setup-llvm`).

  Locally, Xcode ships `clang-format` but **not** `clang-tidy`, so the tidy job
  is the one you cannot reproduce with the tools you already have. Without
  installing 1.5 GB of Homebrew LLVM:

  ```sh
  xcrun clang-format -i $(find engine \( -name '*.cpp' -o -name '*.h' \))

  python3 -m venv /tmp/tidy && /tmp/tidy/bin/pip install -q clang-tidy
  cmake -S engine -B build-tidy -DCMAKE_BUILD_TYPE=Debug
  SDK=$(xcrun --show-sdk-path)
  find engine/src/core engine/src/audio_io engine/src/plugin -name '*.cpp' -print0 \
    | xargs -0 /tmp/tidy/bin/clang-tidy -p build-tidy --quiet \
        --extra-arg="-isysroot$SDK" --extra-arg="-isystem$SDK/usr/include/c++/v1"
  ```

  The two `--extra-arg`s are not optional. The compile database comes from Apple
  clang and the tool is upstream clang, so without them it uses its own resource
  directory, fails to find `<atomic>`, and then reports a page of nonsense
  findings caused by headers that never parsed.
- Dart: `flutter analyze` with `app/analysis_options.yaml`.
- Comments explain *why*. The code already says what it does; a comment that
  repeats it is noise, and a comment that explains a non-obvious constraint is
  the most valuable line in the file.

## Commits and PRs

- One ticket per PR where possible; reference the ticket ID in the title
  (`OB-1-07: flattened schedule publish/retire`).
- Update the ticket's status in `backlog/README.md` in the same PR.
- Attach the evidence the AC asks for — a measurement, a recording, a histogram.
