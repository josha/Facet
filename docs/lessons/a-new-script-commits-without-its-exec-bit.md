# A new script commits without its exec bit

**Found:** 2026-08-16, during D0 of the navigation-and-menus round, by reading
`git ls-tree HEAD` rather than `ls -l`.

## What happened

D0 added `tools/suite_transcript.sh` — the helper that 234 gate checks invoke as a bare
path — and `tools/suite_cache_selftest.sh`. Both were `chmod +x`'d before committing, both
ran fine, and every gate was green.

The committed blobs were mode **100644**.

```
$ git ls-tree HEAD tools/suite_transcript.sh tools/test.sh
100644 blob efa70e0…  tools/suite_transcript.sh
100755 blob d145cda…  tools/test.sh
```

Reproduced against a clone-shaped export:

```
$ T=$(mktemp -d); git archive HEAD tools/suite_transcript.sh | tar -x -C "$T"
$ (cd "$T" && ./tools/suite_transcript.sh)
permission denied: ./tools/suite_transcript.sh
```

So the working tree was green and a fresh clone could not run a single suite grep in the
manifest.

## Why

`tools/commit_isolated.py` seeds a private index from HEAD and applies a filtered patch.
For a file that **already exists** in HEAD, the mode comes along with the existing index
entry — which is why `tools/test.sh`, already 100755, was unaffected. For a **newly added**
file there is no entry to inherit from, and the blob lands at git's default 100644
regardless of what the file's mode is on disk.

Rascal Rally's copy of the same helper was unaffected because it went in through plain
`git add`, which does carry the bit.

The script also cannot fix this after the fact: it compares content, so a mode-only change
is refused —

```
commit_isolated: tools/suite_transcript.sh has no change against HEAD — refusing
```

## Why the round's own check did not catch it

The D0 gate row asserted `test -x tools/suite_transcript.sh`. That reads the **working
tree**, where the bit was always present. It is a check that cannot fail, in the exact
sense the gate-integrity sweep uses the phrase: it was measuring the thing that was never
broken.

## The rule

**A mode is a fact about the committed blob, not about the file on disk.** Any check that
means "this script is runnable after a clone" must read `git ls-tree`:

```sh
[ "$(git ls-tree HEAD path/to/script.sh | cut -c1-6)" = "100755" ]
```

That is what `navigation-and-menus` / `d0-one-run-per-sweep` asserts now, for all three
helpers across both repos.

## Fixing a mode without touching the shared index

`commit_isolated.py` will not do it, and a bare `git add` would sweep in other agents'
work. Use its own technique directly — a private index, seeded from HEAD, so nothing but
the mode moves:

```sh
OLD=$(git rev-parse HEAD)
IDX=$(mktemp -u)
GIT_INDEX_FILE="$IDX" git read-tree HEAD
GIT_INDEX_FILE="$IDX" git update-index --chmod=+x path/to/script.sh
TREE=$(GIT_INDEX_FILE="$IDX" git write-tree)
NEW=$(git commit-tree "$TREE" -p "$OLD" -F msgfile)
git update-ref refs/heads/main "$NEW" "$OLD"   # compare-and-swap; fails loudly if HEAD moved
rm -f "$IDX"
git update-index --chmod=+x path/to/script.sh  # republish into the shared index
```

Seeding from HEAD is what makes this safe: `update-index --chmod` on an entry that already
exists changes only the mode, so a concurrent agent's uncommitted work in the same file
cannot be swept in.

## The general shape

This is the "green locally, broken on arrival" family. The others in it are all the same
mistake: **verifying the artifact you have instead of the artifact you shipped.** The
suite-floor rows in `gate_manifest.luau` that derive their count from `git archive HEAD`
into a scratch directory exist for exactly this reason, and were right to.
