#!/usr/bin/env bash





















set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
repo="$PWD"

if [ "$#" -lt 2 ]; then
	echo "usage: tools/release.sh <version> <commit> [extra package.sh flags...]" >&2
	exit 2
fi
version="$1"
commit="$2"
shift 2

if ! git cat-file -t "$commit" >/dev/null 2>&1; then
	echo "release: '$commit' is not an object in this repository" >&2
	exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
	echo "release: the working tree is dirty; a release is built from a commit, not from a desk" >&2
	git status --porcelain >&2
	exit 1
fi
if [ -z "${ROBLOX_API_KEY:-}" ]; then
	echo "release: ROBLOX_API_KEY is not set in the environment (it is never read from a file)" >&2
	exit 1
fi

asset_id="$(python3 -c "import json,sys; print(json.load(open('package/facet-package.json')).get('assetId') or '')")"
if [ -z "$asset_id" ]; then
	echo "release: package/facet-package.json records no assetId — run tools/package.sh create first" >&2
	exit 1
fi

full_commit="$(git rev-parse "$commit")"
work="$(mktemp -d "${TMPDIR:-/tmp}/facet-release-XXXXXX")"
cleanup() {
	cd "$repo"
	git worktree remove --force "$work" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT

echo "release: Facet $version at $full_commit"
echo "release: worktree $work"
git worktree add --detach "$work" "$full_commit" >/dev/null


if [ -x "$work/tools/verify.sh" ]; then
	gate="tools/verify.sh release"
else
	gate="tools/test.sh"
fi
echo "release: gate = $gate"
(cd "$work" && $gate)
echo "release: gate PASS ($gate)"






(cd "$work" && tools/package.sh build >/dev/null)






started_at="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z"))')"


(cd "$work" && tools/package.sh publish --confirm \
	--version "$version" \
	--commit "$full_commit" \
	--asset-id "$asset_id" \
	"$@")
echo "release: publish exited 0"






mkdir -p "$repo/package/receipts"
latest=""
copied=0
for receipt in "$work"/package/receipts/*.json; do
	[ -e "$receipt" ] || continue
	fresh="$(python3 - "$receipt" "$started_at" <<'EOF'
import json, sys
receipt = json.load(open(sys.argv[1]))
print("yes" if str(receipt.get("publishedAt") or "") >= sys.argv[2] else "no")
EOF
	)"
	[ "$fresh" = "yes" ] || continue
	name="$(basename "$receipt")"
	if [ -e "$repo/package/receipts/$name" ] && ! cmp -s "$receipt" "$repo/package/receipts/$name"; then
		echo "release: $name already exists in the main tree with different content — refusing to overwrite" >&2
		echo "release: the worktree's copy is at $receipt" >&2
		exit 1
	fi
	cp "$receipt" "$repo/package/receipts/$name"
	echo "release: receipt package/receipts/$name"
	copied=1
	latest="$repo/package/receipts/$name"
done
if [ "$copied" = "0" ]; then
	echo "release: publish exited 0 but wrote no receipt dated at or after $started_at" >&2
	exit 1
fi




config_verdict="$(python3 - "$repo/package/facet-package.json" "$work/package/facet-package.json" <<'EOF'
import json, sys
mine, theirs = (json.load(open(path)) for path in sys.argv[1:3])
mutable = ("assetId", "versions")
same = {key: value for key, value in mine.items() if key not in mutable}
other = {key: value for key, value in theirs.items() if key not in mutable}
if same != other:
    moved = sorted(set(same) | set(other))
    moved = [key for key in moved if same.get(key) != other.get(key)]
    print("differs:" + ",".join(moved))
else:
    print("ok:" + json.dumps({key: theirs.get(key) for key in mutable}))
EOF
)"
case "$config_verdict" in
ok:*)
	cp "$work/package/facet-package.json" "$repo/package/facet-package.json"
	echo "release: package/facet-package.json updated (${config_verdict#ok:})"
	;;
*)
	echo "release: the worktree's package/facet-package.json disagrees with the main tree outside assetId and" >&2
	echo "release: versions (${config_verdict#differs:}); refusing to copy it back. Reconcile by hand." >&2
	exit 1
	;;
esac

cat <<CHECKLIST

STUDIO VERIFICATION — owed before this release counts as verified
  1. Open a clean Studio place.
  2. Insert the package by id ($asset_id) from Toolbox > Inventory > My Packages.
  3. Move it to ReplicatedStorage and confirm the root is one ModuleScript named Facet
     with a PackageLink beside it.
  4. Read Facet.Distribution's Version / SourceCommit / SourceHash attributes and
     compare them with this release: $version / $full_commit.
  5. require() it and exercise mount, theme, input, a reactive update and teardown.
  6. Confirm PackageLink.VersionNumber advanced and Status reads Up To Date.
  7. In a second place holding an AutoUpdate copy, confirm it picks the new version up
     on place-open; in a third holding a locally MODIFIED copy, confirm it is reported
     as modified and skipped rather than overwritten.

Then record it:

  tools/package.sh stamp --receipt $(python3 -c "import os,sys; print(os.path.relpath('$latest', '$repo'))") \\
      --studio-verified --by "<who>" --notes "<what you saw>"

CHECKLIST
echo "release: done. Nothing was pushed; commit the receipt yourself."
