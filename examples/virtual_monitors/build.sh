#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
python3 ../../tools/sync_compose.py --check
mkdir -p ../places
rojo build default.project.json -o ../places/Facet-VirtualMonitors.rbxl
python3 - <<'PY'
import json
from pathlib import Path
project = json.loads(Path("default.project.json").read_text())
project["name"] = "Facet Flap"
project["tree"]["Workspace"].setdefault("$attributes", {})["FacetFlap"] = True
Path(".flap_build.project.json").write_text(json.dumps(project, indent=2) + "\n")
PY
trap 'rm -f .flap_build.project.json' EXIT
rojo build .flap_build.project.json -o ../places/Facet-Flap.rbxl

lune run check_builds.luau
