#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.rokit/bin:$PATH"
OUT=(build/Facet-Lab.rbxl build/Foundation-Light.rbxm build/Foundation-Dark.rbxm)
python3 tools/check_boundary.py "${OUT[@]}"
lune run tools/coverage.luau check
lune run tools/check_themes.luau

FACET_REV=$(git -C ../.. rev-parse --short=8 HEAD)$(git -C ../.. diff --quiet HEAD -- src examples tests || echo "+dirty")
LAB_HASH=$({ find src themes default.project.json -type f -print0; find ../../src ../themes ../gallery ../../tools/studio/live -type f -print0; } \
  | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-10)
STAMP="lab $LAB_HASH / facet $FACET_REV"

python3 - "$STAMP" <<'PY'
import json, sys
project = json.load(open("default.project.json"))
project["tree"]["Workspace"]["$attributes"] = {"Facet_Build": sys.argv[1], "FacetLab": True}
json.dump(project, open(".stamped.project.json", "w"), indent=2)
PY
trap 'rm -f .stamped.project.json' EXIT
mkdir -p build
rojo build .stamped.project.json -o "${OUT[0]}"
rojo build theme-light.project.json -o "${OUT[1]}"
rojo build theme-dark.project.json -o "${OUT[2]}"
echo "built: ${OUT[*]}"
echo "stamp: $STAMP"
