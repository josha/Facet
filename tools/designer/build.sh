#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build
rojo build tools/designer/default.project.json -o build/Facet-Design.rbxm
rojo build tools/designer/smoke.project.json -o build/Facet-Design-Playground.rbxl
