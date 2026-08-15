#!/usr/bin/env bash
# Run the same matrix CI runs, on a dev machine (OB-1-02 AC).
#
#   tools/ci_local.sh            everything available on this machine
#   tools/ci_local.sh sanitizers only the sanitizer builds
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
FLUTTER=${FLUTTER:-flutter}
ONLY="${1:-all}"
FAILURES=()

run() {
  local name="$1"
  shift
  echo ""
  echo "=== $name"
  if "$@"; then
    echo "--- $name: OK"
  else
    echo "--- $name: FAILED"
    FAILURES+=("$name")
  fi
}

build_and_test() {
  local dir="$1"
  shift
  cmake -S engine -B "$dir" "$@" >/dev/null
  cmake --build "$dir" -j"$JOBS"
  ctest --test-dir "$dir" --output-on-failure
}

if [[ "$ONLY" == "all" ]]; then
  run "engine debug"   build_and_test build-ci-debug -DCMAKE_BUILD_TYPE=Debug
  run "engine release" build_and_test build-ci-release -DCMAKE_BUILD_TYPE=Release
fi

run "asan+ubsan" build_and_test build-ci-asan -DCMAKE_BUILD_TYPE=Debug -DONEBEAT_ASAN=ON
run "tsan"       build_and_test build-ci-tsan -DCMAKE_BUILD_TYPE=Debug -DONEBEAT_TSAN=ON

# RTSan needs LLVM >= 20. Xcode's clang does not ship it, so this step is only
# run when a suitable toolchain is present — and says so loudly when it is not,
# because silently skipping a merge-blocking check is worse than failing.
LLVM_PREFIX="$(brew --prefix llvm 2>/dev/null || true)"
if [[ -n "$LLVM_PREFIX" && -x "$LLVM_PREFIX/bin/clang++" ]]; then
  run "rtsan" build_and_test build-ci-rtsan \
    -DCMAKE_BUILD_TYPE=Debug -DONEBEAT_RTSAN=ON \
    -DCMAKE_CXX_COMPILER="$LLVM_PREFIX/bin/clang++" \
    -DCMAKE_C_COMPILER="$LLVM_PREFIX/bin/clang"
  if [[ "$ONLY" == "all" ]]; then
    run "clang-tidy" bash -c "
      cmake -S engine -B build-ci-tidy -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_CXX_COMPILER='$LLVM_PREFIX/bin/clang++' \
        -DCMAKE_C_COMPILER='$LLVM_PREFIX/bin/clang' >/dev/null &&
      find engine/src/core engine/src/audio_io engine/src/plugin engine/src/model \
        -name '*.cpp' -print0 |
        xargs -0 '$LLVM_PREFIX/bin/clang-tidy' -p build-ci-tidy --quiet"
  fi
else
  echo ""
  echo "=== rtsan: SKIPPED — install it with 'brew install llvm' (CI always runs it)"
  echo "=== clang-tidy: SKIPPED — same toolchain"
  FAILURES+=("rtsan and clang-tidy (LLVM not installed locally)")
fi

if [[ "$ONLY" == "all" ]]; then
  # Xcode ships clang-format; clang-tidy comes with the LLVM install below.
  # Build directories are pruned: CI checks out clean, but a dev machine has
  # `engine/build*` full of CMake's generated compiler-probe sources, and those
  # are not ours to format. Without this the local run fails on files the real
  # CI never sees.
  run "clang-format" bash -c \
    "find engine \\( -path '*/build*' -prune \\) -o \\( -name '*.cpp' -o -name '*.h' \\) -print0 | xargs -0 \"\$(xcrun -f clang-format)\" --dry-run --Werror"
  run "seam check"    tools/seam_check.sh
  run "licence audit" python3 tools/license_audit.py
  run "token lint"    python3 tools/token_lint.py
  run "flutter analyze" bash -c "cd app && $FLUTTER analyze"
  run "flutter test"    bash -c "cd app && $FLUTTER test"
fi

echo ""
if [[ ${#FAILURES[@]} -eq 0 ]]; then
  echo "All checks passed."
else
  echo "Failed: ${FAILURES[*]}"
  exit 1
fi
