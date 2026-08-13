#!/usr/bin/env bash
# Platform-code confinement (NFR-11, OB-1-01 AC, OB-1-02 §4).
#
# v2's Windows and Linux backends must be new files, not a rewrite. That only
# stays true if platform headers never leak out of their backend directory, so
# the rule is checked mechanically on every PR rather than remembered.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0

fail() {
  echo "SEAM VIOLATION: $1"
  status=1
}

# 1. Apple frameworks may only be included from the CoreAudio backend.
offenders=$(grep -rlE '#[[:space:]]*include[[:space:]]*<(CoreAudio|AudioToolbox|AudioUnit|CoreFoundation|Foundation|AppKit|Cocoa)/' \
  engine/src engine/tests engine/testing engine/tools 2>/dev/null \
  | grep -v '^engine/src/audio_io/coreaudio/' || true)
if [[ -n "$offenders" ]]; then
  fail "Apple framework headers outside engine/src/audio_io/coreaudio/:"
  echo "$offenders"
fi

# 2. The public ABI header must stay free of C++ and of platform types.
if grep -nE '\b(class|namespace|template|std::)' engine/src/abi/onebeat_abi.h >/dev/null; then
  fail "engine/src/abi/onebeat_abi.h contains C++ constructs; it must compile as C."
fi

# 3. Engine code must not reach into the app, and the app must not reach into
#    engine internals — the only door between them is the ABI header.
if grep -rn 'engine/src/core' app/lib 2>/dev/null | grep -v '^app/lib/src/engine/generated/' >/dev/null; then
  fail "app/lib references engine internals; go through the ABI (onebeat_abi.h)."
fi

# 4. Every [[clang::nonblocking]] surface goes through the OB_NONBLOCKING macro,
#    so the real-time surface can be enumerated with one grep.
raw=$(grep -rn '\[\[clang::nonblocking\]\]' engine/src engine/testing 2>/dev/null \
  | grep -v 'core/rt/rt.h' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true)
if [[ -n "$raw" ]]; then
  fail "use OB_NONBLOCKING rather than the bare attribute:"
  echo "$raw"
fi

if [[ $status -eq 0 ]]; then
  echo "Seam check passed."
fi
exit $status
