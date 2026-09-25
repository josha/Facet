#!/usr/bin/env bash













set -euo pipefail
cd "$(dirname "$0")/.."





export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"







python3 tools/sync_compose.py --check || exit $?
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
twin=""
base=""
ext=""























case "$out" in
*.rbxmx) base="${out%.rbxmx}" ext="rbxmx" ;;
*.rbxm) base="${out%.rbxm}" ext="rbxm" ;;
*)
	echo "build_model: output '$out' must end in .rbxm or .rbxmx (rojo decides the format from the name)" >&2
	exit 2
	;;
esac

token="$$-${RANDOM}-${RANDOM}"
stage_dir="build/.stage.$token"
project=".model_build.$token.project.json"
place_project=".model_build.place.$token.project.json"
trap 'rm -rf "$stage_dir" "$project" "$place_project" "$base.tmp.$token.$ext" "$base.tmp.$token.rbxmx" "build/FacetPublisher.tmp.$token.rbxl"' EXIT








python3 tools/package.py stage --out "$stage_dir" --quiet






cat >"$project" <<JSON
{
  "name": "Facet",
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "\$path": "src",
    "Distribution": { "\$path": "$stage_dir/Distribution" }
  }
}
JSON

mkdir -p "$(dirname "$out")"
rojo build "$project" -o "$base.tmp.$token.$ext"
mv -f "$base.tmp.$token.$ext" "$out"





twin="$base.rbxmx"
if [ "$twin" != "$out" ]; then
	rojo build "$project" -o "$base.tmp.$token.rbxmx"
	mv -f "$base.tmp.$token.rbxmx" "$twin"
fi
python3 tools/package.py manifest --model "$twin" --artifact "$out" --out "$base.manifest.json"







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
	rojo build "$place_project" -o "build/FacetPublisher.tmp.$token.rbxl"
	mv -f "build/FacetPublisher.tmp.$token.rbxl" build/FacetPublisher.rbxl
	echo "built build/FacetPublisher.rbxl (publisher place, from $out)"
fi

version=$(grep -m1 'VERSION = ' src/init.luau | sed -E 's/.*"([^"]+)".*/\1/')
echo "built $out (Facet $version, $(find src -name '*.luau' ! -name '*.spec.luau' | wc -l | tr -d ' ') modules)"
