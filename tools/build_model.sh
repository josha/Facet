#!/usr/bin/env bash
# Facet model builder: emits build/Facet.rbxm — the library alone, as a single
# ModuleScript named Facet with the whole src/ tree beneath it. This is the
# artifact a consumer WITHOUT Rojo drags into ReplicatedStorage
# (docs/guide/08-without-rojo.md), and the artifact the official Roblox Package
# is made of. Rebuild it whenever src/ or VERSION changes.
# Usage: tools/build_model.sh [output] [--publisher]  (from anywhere)
# Output: build/Facet.rbxm, or `output` when one is given — the SAME project
#   mapping either way, plus the `.rbxmx` twin beside it and the semantic
#   manifest `build/Facet.manifest.json`. `tools/check_library_purity.py` passes
#   a temporary `.rbxmx` so it can read the model's scripts as text; a second
#   Rojo mapping living inside that check would prove the check rather than the
#   artifact. THAT RULE IS WHY THIS FILE IS THE ONLY PLACE IN THE REPOSITORY
#   THAT WRITES A ROJO PROJECT FOR THE DISTRIBUTION.
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build

out=""
publisher=0
for arg in "$@"; do
	case "$arg" in
	--publisher) publisher=1 ;;
	*) out="$arg" ;;
	esac
done
out="${out:-build/Facet.rbxm}"

# THE RELEASE METADATA IS GENERATED, NEVER EDITED. `package.py stage` writes
# build/.stage/Distribution/ fresh on every build: an init.meta.json declaring a
# Folder with the Version/SourceCommit/SourceHash/BuildSchema/Repository
# attributes, and LICENSE.txt / THIRD_PARTY_NOTICES.txt (Rojo maps a .txt file to
# a StringValue named after its stem). No build TIME is in there — two builds of
# one commit must produce the same bytes, and the time of a release lives in its
# receipt. build/ is gitignored, so the staging dir is never committed.
python3 tools/package.py stage --quiet

# ONE PROJECT, ONE MAPPING. Rojo merges a named child into the instance produced
# by `$path`, so `Distribution` lands INSIDE the `Facet` ModuleScript that `src`
# builds — the artifact stays a single ModuleScript named Facet.
project=".model_build.project.json"
cat >"$project" <<'JSON'
{
  "name": "Facet",
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "$path": "src",
    "Distribution": { "$path": "build/.stage/Distribution" }
  }
}
JSON
place_project=".model_build.place.project.json"
trap 'rm -f "$project" "$place_project"' EXIT

mkdir -p "$(dirname "$out")"
rojo build "$project" -o "$out"

# THE XML TWIN, always. A binary .rbxm is LZ4-chunked, so nothing can read its
# scripts as text — not the purity check, not the manifest walk, not the packaged
# consumer canary. When the caller already asked for XML this is the same file
# and the second build is skipped.
twin="${out%.*}.rbxmx"
if [ "$twin" != "$out" ]; then
	rojo build "$project" -o "$twin"
fi
python3 tools/package.py manifest --model "$twin" --artifact "$out" --out "${out%.*}.manifest.json"

# THE CANONICAL PUBLISHER PLACE (opt-in). The studio publish route needs one
# place, built from the artifact this script just produced, whose only content is
# the model under ReplicatedStorage — a human opens it, right-clicks Facet, and
# converts or publishes. It CONSUMES build/Facet.rbxm rather than mapping src/
# again, so it is not a second model source: change the model and the place
# changes with it, by construction.
if [ "$publisher" = "1" ]; then
	cat >"$place_project" <<JSON
{
  "name": "FacetPublisher",
  "tree": {
    "\$className": "DataModel",
    "ReplicatedStorage": {
      "\$className": "ReplicatedStorage",
      "Facet": { "\$path": "$out" }
    }
  }
}
JSON
	rojo build "$place_project" -o build/FacetPublisher.rbxl
	echo "built build/FacetPublisher.rbxl (publisher place, from $out)"
fi

version=$(grep -m1 'VERSION = ' src/init.luau | sed -E 's/.*"([^"]+)".*/\1/')
echo "built $out (Facet $version, $(find src -name '*.luau' ! -name '*.spec.luau' | wc -l | tr -d ' ') modules)"
