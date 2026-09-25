#!/usr/bin/env bash





























set -euo pipefail
cd "$(dirname "$0")/.."



export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"


build_one() {
	local source="$1" name="$2" out="$3"
	if [ ! -f "$source" ]; then
		echo "build_themes: no such theme module: $source" >&2
		return 1
	fi
	local project=".theme_build.$$.project.json"




	printf '{\n  "name": "%s",\n  "tree": { "$path": "%s" }\n}\n' "$name" "$source" >"$project"
	# shellcheck disable=SC2064
	trap "rm -f '$project'" RETURN
	mkdir -p "$(dirname "$out")"
	rojo build "$project" -o "$out"
}

if [ "${1:-}" = "--one" ]; then
	if [ $# -ne 4 ]; then
		echo "usage: tools/build_themes.sh --one <source.luau> <Name> <output.rbxm>" >&2
		exit 2
	fi
	build_one "$2" "$3" "$4"
	echo "built $4"
	exit 0
fi

if [ $# -ne 0 ]; then
	echo "tools/build_themes.sh: unexpected argument '$1' (expected no arguments, or --one)" >&2
	exit 2
fi

mkdir -p build/themes
count=0



while IFS=$'\t' read -r module artifact; do
	[ -n "$module" ] || continue
	if [ -d "examples/themes/$module" ]; then
		echo "build_themes: examples/themes/$module/ exists — this package now owns runtime data beside its" >&2
		echo "  module, and this script only maps the module. Extend build_one before shipping it." >&2
		exit 1
	fi
	build_one "examples/themes/$module.luau" "$artifact" "build/themes/$artifact.rbxm"
	count=$((count + 1))
done < <(lune run tools/lune/theme_artifacts -- list)

if [ "$count" -eq 0 ]; then
	echo "build_themes: the enumerator listed no shippable packages — that is a bug, not an empty product" >&2
	exit 1
fi




lune run tools/lune/theme_artifacts -- manifest build/themes
echo "built $count theme artifacts into build/themes/"
