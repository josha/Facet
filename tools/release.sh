#!/usr/bin/env bash
# The protected manual release. NOTHING here runs automatically: no hook, no
# push trigger, no schedule. A human types this command with a version and a
# commit, and every guard in tools/package.py still has to agree before a single
# byte leaves the machine.
#
#     tools/release.sh <version> <commit> [extra package.sh flags...]
#
# WHAT IT DOES, in order:
#   1. refuses unless <commit> exists and the working tree is clean;
#   2. checks that exact commit out into a throwaway git worktree, so the release
#      is built from the commit and not from whatever the tree happens to hold;
#   3. reruns the release gate there — tools/verify.sh release when that script
#      exists, otherwise tools/test.sh — and RECORDS which one ran;
#   4. runs tools/package.sh publish --confirm with the version, the commit and
#      the asset id read out of package/facet-package.json;
#   5. copies the receipt back into the main tree's package/receipts/;
#   6. prints the Studio verification checklist and the exact stamp command;
#   7. removes the worktree.
#
# ROBLOX_API_KEY must be in the environment. It is never read from a file, never
# printed and never written to a receipt.
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

# ── 3. the release gate, in the worktree, at that commit ────────────────────
if [ -x "$work/tools/verify.sh" ]; then
	gate="tools/verify.sh release"
else
	gate="tools/test.sh"
fi
echo "release: gate = $gate"
(cd "$work" && $gate)
echo "release: gate PASS ($gate)"

# ── 4. build in the worktree, so the drift guard has something to compare ───
# `package.sh publish` refuses when build/Facet.manifest.json does not describe
# this tree, and a fresh worktree has no build at all. Building here is also what
# gives that guard its meaning: the manifest recorded now and the fresh build
# inside publish are two independent builds of the same commit.
(cd "$work" && tools/package.sh build >/dev/null)

# THE WATERMARK for step 6. Receipts are selected by CONTENT — a publishedAt at
# or after this instant — not by having a name the main tree has not seen. A
# receipt is named <version>-<sha7>, so republishing the same version from the
# same commit reuses the name, and "the name is new" would have called a real
# publish a failure.
started_at="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z"))')"

# ── 5. publish, with every package.py guard still in force ──────────────────
(cd "$work" && tools/package.sh publish --confirm \
	--version "$version" \
	--commit "$full_commit" \
	--asset-id "$asset_id" \
	"$@")
echo "release: publish exited 0"

# ── 6. carry the receipt AND the config back into the main tree ─────────────
# `set -e` means we only reach here if publish exited 0; the receipt selection
# below confirms it actually wrote something, and the config carries the state
# publish records outside the receipt — `assetId` on create, `versions[]` on
# publish — which the worktree would otherwise take to the bin with it.
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

# THE CONFIG, whose diff must be only what publish is allowed to change.
# Anything else moving means the worktree and the main tree disagree about the
# package itself, and silently copying that over would launder the disagreement.
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
