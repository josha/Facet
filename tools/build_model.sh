#!/usr/bin/env bash
# Facet model builder: emits build/Facet.rbxm — the library alone, as a single
# ModuleScript named Facet with the whole src/ tree beneath it. This is the
# artifact a consumer WITHOUT Rojo drags into ReplicatedStorage
# (docs/guide/08-without-rojo.md). Rebuild it whenever src/ or VERSION changes.
# Usage: tools/build_model.sh [output]  (from anywhere)
# Output: build/Facet.rbxm, or `output` when one is given — the SAME project
#   mapping either way. `tools/check_library_purity.py` passes a temporary
#   `.rbxmx` so it can read the model's scripts as text; a second Rojo mapping
#   living inside that check would prove the check rather than the artifact.
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build

project=".model_build.project.json"
cat >"$project" <<'JSON'
{
  "name": "Facet",
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": { "$path": "src" }
}
JSON
trap 'rm -f "$project"' EXIT

out="${1:-build/Facet.rbxm}"
mkdir -p "$(dirname "$out")"
rojo build "$project" -o "$out"
version=$(grep -m1 'VERSION = ' src/init.luau | sed -E 's/.*"([^"]+)".*/\1/')
echo "built $out (Facet $version, $(find src -name '*.luau' | wc -l | tr -d ' ') modules)"
