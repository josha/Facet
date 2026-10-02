#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tools/sync_compose.py --check
mkdir -p build
rojo build examples/facet_home/default.project.json -o build/Facet-Home.rbxl
