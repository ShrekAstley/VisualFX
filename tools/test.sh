#!/bin/sh
# Runs the VisualFX test suite and the plugin smoke test with the Luau CLI
# (https://github.com/luau-lang/luau/releases). LUAU may point at the binary.
# Usage: sh tools/test.sh [spec-name-filter]
set -e
cd "$(dirname "$0")/.."
mkdir -p build
python3 tools/bundle.py test.project.json build/test_bundle.luau
python3 tools/bundle.py plugin.project.json build/plugin_bundle.luau
"${LUAU:-luau}" tools/run_tests.luau -a "$@"
if [ -z "$1" ]; then
	"${LUAU:-luau}" tools/run_plugin_smoke.luau
fi
