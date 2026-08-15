#!/usr/bin/env bash
# Build, Developer-ID sign, notarize, staple, and verify a OneBeat macOS zip.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${OB_SIGNING_IDENTITY:?Set OB_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${OB_NOTARY_PROFILE:?Set OB_NOTARY_PROFILE to a notarytool keychain profile}"

"$REPO_ROOT/tools/build.sh"
APP="$REPO_ROOT/app/build/macos/Build/Products/Release/onebeat.app"
HELPER="$APP/Contents/Helpers/onebeat-plugin-host.app"
ENGINE="$APP/Contents/Frameworks/libonebeat_engine.dylib"
STOCK_PIANO="$APP/Contents/PlugIns/OneBeat Piano.clap"
STOCK_LOWKEY="$APP/Contents/PlugIns/Lowkey.clap"
STOCK_ORGAN="$APP/Contents/PlugIns/OneBeat Organ.clap"
STOCK_DRILL_SYNTH="$APP/Contents/PlugIns/OneBeat Drill Synth.clap"
ENTITLEMENTS="$REPO_ROOT/app/macos/Runner/PluginHost.entitlements"
OUTPUT="$REPO_ROOT/app/build/macos/OneBeat-macOS.zip"

# Sign inside-out. Only the helper can load third-party signatures.
codesign --force --timestamp --options runtime --sign "$OB_SIGNING_IDENTITY" "$STOCK_PIANO"
codesign --force --timestamp --options runtime --sign "$OB_SIGNING_IDENTITY" "$STOCK_LOWKEY"
codesign --force --timestamp --options runtime --sign "$OB_SIGNING_IDENTITY" "$STOCK_ORGAN"
codesign --force --timestamp --options runtime --sign "$OB_SIGNING_IDENTITY" "$STOCK_DRILL_SYNTH"
codesign --force --timestamp --options runtime --sign "$OB_SIGNING_IDENTITY" "$ENGINE"
codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" \
  --sign "$OB_SIGNING_IDENTITY" "$HELPER"
codesign --force --deep --timestamp --options runtime \
  --entitlements "$REPO_ROOT/app/macos/Runner/Release.entitlements" \
  --sign "$OB_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$OUTPUT"
xcrun notarytool submit "$OUTPUT" --keychain-profile "$OB_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized artifact: $OUTPUT"
