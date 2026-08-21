#!/usr/bin/env bash
# Facet THEME builder: emits build/themes/<Name>.rbxm — one artifact per
# shippable reference theme package, so a consumer can take a SKIN without
# taking the gallery, the fixtures or the rest of examples/.
#
# It is the sibling of tools/build_model.sh and shares its conventions on
# purpose (same rokit PATH pin, same throwaway-project-then-`rojo build` shape,
# same `build/` output): there is ONE Rojo mapping style in this repository and
# adding a second is how two artifacts drift apart.
#
#   tools/build_themes.sh
#       build every shippable package (the list comes from
#       tools/lune/theme_packages.luau — this script knows no theme names) plus
#       build/themes/manifest.json describing what was built.
#
#   tools/build_themes.sh --one <source.luau> <Name> <output.rbxm>
#       build ONE module through the same mapping. This is the seam
#       tools/check_theme_artifacts.py --selftest drives with a deliberately
#       broken source: a guard that cannot be shown failing proves nothing, and
#       re-implementing the mapping inside the check would prove the check.
#
# WHAT IS IN AN ARTIFACT. Today, exactly one ModuleScript: a theme package is
# INSPECTABLE DATA (src/themes/package.luau) and its art is uploaded content the
# package references by id, so there is no runtime data beside the module. If a
# package ever grows a sibling `examples/themes/<name>/` directory, this script
# REFUSES rather than silently shipping an artifact missing half the package —
# add the mapping here when that day comes.
#
# Usage: tools/build_themes.sh          (from anywhere)
# Output: build/themes/*.rbxm + build/themes/manifest.json
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH — tools/build_model.sh records the
# measurement behind this line (a stale /usr/local/bin/rojo fails the build on a
# property its reflection database does not know).
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# build_one <source.luau> <Name> <output.rbxm> — THE ONLY ROJO MAPPING HERE.
build_one() {
	local source="$1" name="$2" out="$3"
	if [ ! -f "$source" ]; then
		echo "build_themes: no such theme module: $source" >&2
		return 1
	fi
	local project=".theme_build.$$.project.json"
	# `$path` at a single .luau file becomes ONE ModuleScript named by the tree
	# root, which is the project's `name`. That name is what a consumer sees in
	# the Explorer and types in `require(...)`, so it is PascalCase and derived
	# from the module name by tools/lune/theme_packages.artifactName.
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
# THE LIST IS DERIVED, NEVER TYPED HERE. `theme_artifacts list` prints one
# `<module>\t<ArtifactName>` line per shippable package; the enumerator's own
# suite proves the shippable set is the directory minus the named exclusions.
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

# ...and the manifest LAST, because it records each artifact's size on disk and
# it compiles every package through `themes.define` on the way: a package that
# no longer compiles fails the build instead of shipping.
lune run tools/lune/theme_artifacts -- manifest build/themes
echo "built $count theme artifacts into build/themes/"
