#!/bin/sh
# Regenerates Documentation/schema/*.json from the live registries.
# LUAU may point at the Luau CLI binary (https://github.com/luau-lang/luau/releases).
set -e
cd "$(dirname "$0")/.."
mkdir -p build Documentation/schema
python3 tools/bundle.py test.project.json build/test_bundle.luau
for kind in config full commands presets; do
	case "$kind" in
		config) out=config.schema.json ;;
		full) out=visualfx.schema.json ;;
		commands) out=commands.json ;;
		presets) out=presets.json ;;
	esac
	"${LUAU:-luau}" tools/gen_schema.luau -a "$kind" > "Documentation/schema/$out"
done
echo "schemas written to Documentation/schema/"
python3 tools/gen_markdown.py
