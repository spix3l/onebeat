#!/usr/bin/env bash
# Rebuild the engine and run the app with hot reload.
#
# The app finds the freshly built dylib through OB_ENGINE_DYLIB, so an engine
# change is one Ctrl-C and one `tools/dev.sh` away — no packaging step.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FLUTTER=${FLUTTER:-flutter}

cmake -S engine -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j"$(sysctl -n hw.ncpu)"

export OB_ENGINE_DYLIB="$REPO_ROOT/build/libonebeat_engine.dylib"
cd app
$FLUTTER run -d macos --dart-define=OB_DEV=1 "$@"
