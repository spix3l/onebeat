# OB-1-02 — CI: builds, sanitizer matrix, licence audit

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Infra |
| **Priority** | Blocker — "sanitizer CI from the first commit" (PRD §10 v0.1) |
| **Dependencies** | OB-1-01 |
| **References** | NFR-08, NFR-09, R4, D2 |
| **Estimate** | M |

## Context

The sanitizer regime is the mandatory price of choosing C++ (D2, R4). NFR-08: a PR failing any sanitizer does not merge. NFR-09: CI must prove no dependency introduces copyleft (LGPL included).

## Scope

GitHub Actions (macOS Apple Silicon runners):

1. **Build & test job:** Debug + Release engine builds, engine unit tests, `flutter analyze` + `flutter test`.
2. **Sanitizer matrix (merge-blocking):**
   - **ASan + UBSan** build running the engine test suite.
   - **TSan** build running the engine test suite (esp. schedule-swap and FFI tests).
   - **RTSan** (LLVM 20+): engine tests that drive the audio callback with RTSan enabled; any malloc/lock/syscall on a `[[clang::nonblocking]]` path fails the job. Pin/document the required Clang; if the Xcode toolchain lacks RTSan, install LLVM via Homebrew in CI and document the local-dev equivalent.
3. **Licence audit job:** script (`tools/license_audit.py`) walks `third_party/` + Dart dependencies (`pubspec.lock`), resolves each package's licence, fails on anything not in the allowlist {MIT, Apache-2.0, BSD-2/3, ISC, Zlib, PD/Unlicense/CC0}. Explicit denylist match (GPL, LGPL, AGPL, MPL) fails with the offending package named.
4. **Seam check:** greps enforcing OB-1-01's platform-code confinement (NFR-11).
5. Branch protection: all jobs required to merge.

## Acceptance criteria

- [ ] A PR with a deliberate heap overflow in a test fails ASan; a deliberate data race fails TSan; a deliberate `malloc` inside a `[[clang::nonblocking]]` function fails RTSan (all three demonstrated once, then reverted).
- [ ] A PR adding a fake GPL-licensed dependency fails the licence audit naming the package (demonstrated, reverted).
- [ ] Full pipeline runtime <20 min.
- [ ] Local reproduction documented: `tools/ci_local.sh` runs the same matrix on a dev machine.

## Out of scope

- Token lint (OB-1-03). Public-API check for built-ins (Stage 6).
