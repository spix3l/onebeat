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

# 5. Every model mutation goes through the command layer (OB-3-03 §1), so that
#    undo cannot be forgotten by a caller in a hurry. `model/` may call its own
#    mutators; nothing else may. The door for everyone else is
#    `model/commands.h` plus `CommandBus::execute`.
mutators='create(Instrument|Pattern|Lane|MixerTrack|Clip)'
mutators+='|delete(Instrument|Pattern|Lane|Clip|MixerTrack)'
mutators+='|update(Instrument|Pattern|Lane|Clip|MixerTrack|Sequence)'
mutators+='|restore(Instrument|Pattern|Lane|Clip|MixerTrack|Sequence)'
mutators+='|adopt|mintId'
offenders=$(grep -rlE "\.(${mutators})\(" engine/src engine/tools engine/testing 2>/dev/null \
  | grep -v '^engine/src/model/' || true)
if [[ -n "$offenders" ]]; then
  fail "model mutated outside the command layer; use model/commands.h + CommandBus:"
  echo "$offenders"
fi

# 6. The Dart loader must reject an older additive ABI before generated
# bindings attempt to resolve a symbol that dylib does not export. Keep its
# expected major/minor paired with the public header mechanically; a missed
# minor bump otherwise becomes an ArgumentError during the first widget build.
engine_major=$(awk '/^#define OB_ABI_VERSION_MAJOR / { print $3 }' engine/src/abi/onebeat_abi.h)
engine_minor=$(awk '/^#define OB_ABI_VERSION_MINOR / { print $3 }' engine/src/abi/onebeat_abi.h)
dart_major=$(awk '/^const int expectedAbiMajor = / { gsub(/;/, "", $5); print $5 }' \
  app/lib/src/engine/engine_library.dart)
dart_minor=$(awk '/^const int expectedAbiMinor = / { gsub(/;/, "", $5); print $5 }' \
  app/lib/src/engine/engine_library.dart)
if [[ "$engine_major.$engine_minor" != "$dart_major.$dart_minor" ]]; then
  fail "engine ABI is $engine_major.$engine_minor but Dart expects $dart_major.$dart_minor."
fi

if [[ $status -eq 0 ]]; then
  echo "Seam check passed."
fi
exit $status
