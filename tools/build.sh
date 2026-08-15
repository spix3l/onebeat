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

# Place the engine and scan helper next to the app binary so the built bundle is
# self-contained. Proper signing and notarization is Stage 2 work (OB-2-06);
# until then an ad-hoc signature is enough to run.
#
# *Every* product bundle is refreshed, not just the one this invocation built.
# The loader prefers a dylib inside the bundle over the repository build output
# (engine_library.dart), and `flutter run` produces a Debug bundle without ever
# coming through this script — so a Debug bundle left over from an earlier day
# will happily be loaded in preference to the engine you just compiled. That
# actually happened: a Debug bundle four hours stale shadowed a fresh Release
# build and the app died on a missing symbol.
found_any=0
while IFS= read -r APP_DIR; do
  [[ -z "$APP_DIR" ]] && continue
  found_any=1
  mkdir -p "$APP_DIR/Contents/Frameworks"
  mkdir -p "$APP_DIR/Contents/MacOS"
  mkdir -p "$APP_DIR/Contents/PlugIns"
  HELPER_APP="$APP_DIR/Contents/Helpers/onebeat-plugin-host.app"
  mkdir -p "$HELPER_APP/Contents/MacOS"
  cp "$REPO_ROOT/build/libonebeat_engine.dylib" "$APP_DIR/Contents/Frameworks/"
  cp "$REPO_ROOT/build/onebeat-plugin-host" "$HELPER_APP/Contents/MacOS/"
  cp "$REPO_ROOT/engine/src/host/Info.plist" "$HELPER_APP/Contents/"
  rm -f "$APP_DIR/Contents/MacOS/onebeat-plugin-host"
  rm -rf "$APP_DIR/Contents/PlugIns/OneBeat Piano.clap"
  rm -rf "$APP_DIR/Contents/PlugIns/Lowkey.clap"
  rm -rf "$APP_DIR/Contents/PlugIns/OneBeat Organ.clap"
  rm -rf "$APP_DIR/Contents/PlugIns/OneBeat Drill Synth.clap"
  cp -R "$REPO_ROOT/build/stock-plugins/OneBeat Piano.clap" "$APP_DIR/Contents/PlugIns/"
  cp -R "$REPO_ROOT/build/stock-plugins/Lowkey.clap" "$APP_DIR/Contents/PlugIns/"
  cp -R "$REPO_ROOT/build/stock-plugins/OneBeat Organ.clap" "$APP_DIR/Contents/PlugIns/"
  cp -R "$REPO_ROOT/build/stock-plugins/OneBeat Drill Synth.clap" "$APP_DIR/Contents/PlugIns/"
  codesign --force --sign - "$APP_DIR/Contents/PlugIns/OneBeat Piano.clap" 2>/dev/null || true
  codesign --force --sign - "$APP_DIR/Contents/PlugIns/Lowkey.clap" 2>/dev/null || true
  codesign --force --sign - "$APP_DIR/Contents/PlugIns/OneBeat Organ.clap" 2>/dev/null || true
  codesign --force --sign - "$APP_DIR/Contents/PlugIns/OneBeat Drill Synth.clap" 2>/dev/null || true
  codesign --force --sign - "$APP_DIR/Contents/Frameworks/libonebeat_engine.dylib" 2>/dev/null || true
  codesign --force --sign - "$HELPER_APP" 2>/dev/null || true
  # Replacing nested code invalidates the outer seal. Re-sign the development
  # bundle last, mirroring the inside-out order used by release_macos.sh.
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
  echo "==> Engine and plug-in scan helper refreshed in $APP_DIR"
done < <(find build/macos/Build/Products -maxdepth 2 -name 'onebeat.app' 2>/dev/null)

if [[ $found_any -eq 0 ]]; then
  echo "==> No app bundle found to place the engine in."
fi
