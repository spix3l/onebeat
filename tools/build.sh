#!/usr/bin/env bash
# Build the engine and the app. One command, from a clean clone (NFR-07).
#
#   tools/build.sh              release-ish engine + release app bundle
#   tools/build.sh --debug      debug engine + debug app bundle
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_TYPE=RelWithDebInfo
FLUTTER_MODE=--release
if [[ "${1:-}" == "--debug" ]]; then
  BUILD_TYPE=Debug
  FLUTTER_MODE=--debug
fi

FLUTTER=${FLUTTER:-flutter}

echo "==> Engine ($BUILD_TYPE)"
cmake -S engine -B build -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
cmake --build build -j"$(sysctl -n hw.ncpu)"

echo "==> Engine tests"
ctest --test-dir build --output-on-failure

echo "==> App"
cd app
$FLUTTER pub get
$FLUTTER build macos $FLUTTER_MODE

# Place the engine next to the app binary so the built bundle is self-contained.
# Proper embedding, code-signing and notarization of the dylib is Stage 2 work
# (OB-2-06); until then the copy plus an ad-hoc signature is enough to run.
APP_DIR=$(find build/macos/Build/Products -maxdepth 2 -name 'onebeat.app' | head -1)
if [[ -n "$APP_DIR" ]]; then
  mkdir -p "$APP_DIR/Contents/Frameworks"
  cp "$REPO_ROOT/build/libonebeat_engine.dylib" "$APP_DIR/Contents/Frameworks/"
  codesign --force --sign - "$APP_DIR/Contents/Frameworks/libonebeat_engine.dylib" 2>/dev/null || true
  echo "==> Built $APP_DIR"
fi
