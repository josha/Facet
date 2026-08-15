#!/usr/bin/env bash
# LuauUI model builder: emits build/LuauUI.rbxm — the library alone, as a single
# ModuleScript named LuauUI with the whole src/ tree beneath it. This is the
# artifact a consumer WITHOUT Rojo drags into ReplicatedStorage
# (docs/guide/08-without-rojo.md). Rebuild it whenever src/ or VERSION changes.
# Usage: tools/build_model.sh          (from anywhere)
# Output: build/LuauUI.rbxm
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
  "name": "LuauUI",
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": { "$path": "src" }
}
JSON
trap 'rm -f "$project"' EXIT

rojo build "$project" -o build/LuauUI.rbxm
version=$(grep -m1 'VERSION = ' src/init.luau | sed -E 's/.*"([^"]+)".*/\1/')
echo "built build/LuauUI.rbxm (LuauUI $version, $(find src -name '*.luau' | wc -l | tr -d ' ') modules)"
