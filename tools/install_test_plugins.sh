#!/usr/bin/env bash
# Build and install free-audio/clap-plugins into the user CLAP folder, so that
# there is a real third-party instrument to test hosting against.
#
# The headless preset is deliberate: the GUI variant needs Qt, takes far longer
# to build, and nothing we test here is about the plugin's own editor. What we
# want is a plugin that is not ours — "CLAP Synth" has a note input, an audio
# output and 25 parameters, which exercises the scanner, the instrument
# lifecycle and the parameter path end to end.
#
# Ninja is not required: the upstream presets use it, but the headless build has
# no generator-specific steps, so plain Makefiles work and one less tool has to
# be installed.
set -euo pipefail

readonly REPO="https://github.com/free-audio/clap-plugins.git"
readonly WORK="${OB_PLUGIN_WORK_DIR:-${TMPDIR:-/tmp}/onebeat-test-plugins}"
readonly DESTINATION="${OB_CLAP_DIR:-$HOME/Library/Audio/Plug-Ins/CLAP}"
readonly SOURCE="$WORK/clap-plugins"

if [[ ! -d "$SOURCE/.git" ]]; then
  echo "==> Cloning clap-plugins into $SOURCE"
  mkdir -p "$WORK"
  git clone --depth 1 --recurse-submodules --shallow-submodules "$REPO" "$SOURCE"
else
  echo "==> Reusing the existing clone at $SOURCE"
fi

echo "==> Configuring (headless, Release)"
cmake -S "$SOURCE" -B "$SOURCE/builds/mk" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release -DCLAP_PLUGINS_HEADLESS=ON >/dev/null

echo "==> Building"
cmake --build "$SOURCE/builds/mk" -j "$(sysctl -n hw.ncpu)" >/dev/null

readonly BUNDLE="$SOURCE/builds/mk/plugins/clap-plugins.clap"
if [[ ! -d "$BUNDLE" ]]; then
  echo "The build finished but $BUNDLE is missing." >&2
  exit 1
fi

echo "==> Installing into $DESTINATION"
mkdir -p "$DESTINATION"
rm -rf "${DESTINATION:?}/clap-plugins.clap"
cp -R "$BUNDLE" "$DESTINATION/"

echo "==> Done. Rescan from the plugin browser to pick the new bundle up."
echo "    'CLAP Synth' is the instrument worth testing with (note in, 25 params)."
