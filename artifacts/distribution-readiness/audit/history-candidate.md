# Facet — clean-history candidates

**Built 2026-08-30.** Two candidates exist, both verified, neither pushed anywhere. The working
repository was not modified. **This run is a rehearsal:** the repository is being committed to by
other agents right now, so the rewrite must be re-run on the final pre-publication commit before
anything is pushed. The builder script exists precisely so that re-run is one command.

Tooling: **`git filter-repo` 2.47.0**, installed into the root virtualenv
(`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/.venv`) with
`pip install git-filter-repo`. `git filter-branch` was not used. Git 2.50.1 (Apple Git-155).

Everything lives outside the repository, under
`GameStudio/ui/Facet-private-archive/history-rewrite/`:

| Path | What |
|---|---|
| `build_candidate.sh` | the re-runnable builder + verifier |
| `scan_history.py` | full-history string scanner (every blob + every commit's metadata) |
| `candidate-A-must-purge/source.git` | frozen `--mirror` of the repository before the rewrite — the disaster copy |
| `candidate-A-must-purge/candidate` | candidate A |
| `candidate-A-must-purge/report.md` | candidate A's machine-generated verification report |
| `candidate-B-full/…` | the same three things for candidate B |

That directory is **1.2 GB** and it is inside the Dropbox tree, which is now syncing it. Nothing in
it is needed once a candidate has been chosen except the frozen mirror, which step 1 of the
migration moves off Dropbox anyway. Deleting `candidate-*/candidate` and re-running the builder is
always cheaper than keeping them.

```
build_candidate.sh <source-repo-path> <out-name> [--bulk] [--email <addr>] [--extras]
```

Both candidates were built from the same source commit
**`cf33f8e16fcd324d014260bd9ea3492894f0a494`** — the local `main` tip at 11:31 on 2026-08-30.
Candidate A was built from the live repository; candidate B was built from candidate A's frozen
mirror, so that the two share an identical baseline even though `main` kept moving underneath
(eighteen further commits landed from other agents while this ran).

---

## The two candidates

### candidate A — `candidate-A-must-purge`

Removes **only the 15 must-purge files** (audit findings RGT-07 and PRJ-01): the eleven screen
captures of the official Roblox mobile app under
`docs/plans/reference-media/2026-08-16-roblox-app-navigation/`, and the four checked-in Rascal
Rally test transcripts. Nothing else changes: same 1,113 commits in the same order with the same
messages, dates and authorship, and all 530 historical `.rbxl` place blobs retained.

- Tip `aeda8eaaf66ded5228e3617acd4f4b02d6c9d99d`.
- `git filter-repo --invert-paths --prune-empty never` with 15 `--path` arguments.
- **Every SHA changes**, as any rewrite does — A shares exactly **1** commit SHA with the original
  (`6a4b59c`, the root commit, which predates the first purged file). B shares **0**, because the
  mailmap touches even the root commit.

### candidate B — `candidate-B-full`

Everything A removes, **plus** every optional rewrite the audit surfaced:

| Also removed in B | Audit finding | Commits that touched it before |
|---|---|---:|
| `examples/places/*.rbxl` across all history (530 blobs), with the tip's 14 place files re-added in one final commit | BLK-01 / PRJ-05 | 79 |
| `examples/places/LuauUI-Showcase.rbxl.lock` (hostname, PID, two session UUIDs) | PER-02 | 4 |
| `assets/themes/{glossy-touch,fantasy-parchment}/source/__pycache__/generate_art.cpython-314.pyc` | PER-04 | 2 each |
| `docs/reference/sponsor-view-parity.md` | PRJ-02 | 7 |
| author **and** committer `Josh Anon <josha@Joshs-Mac-mini.local>` → `Josh Anon <josha@users.noreply.github.com>` on every commit, via `--mailmap` | PER-03 | all |

**`josha@users.noreply.github.com` is a placeholder.** It is the address GitHub itself hands out
for commit privacy, but the owner may want the numbered form
(`<id>+josha@users.noreply.github.com`, which GitHub links to the account) or a real address.
Changing it means re-running the builder with a different `--email`; nothing else changes.

- Tip `16beb08cf5e3eda7d468c58d8e71d5a39be9bd90` — the re-add commit
  *"Restore the place builds at the tip after the history rewrite"*, dated to the rewritten tip's
  own committer date so the build is deterministic.
- `git filter-repo --invert-paths --prune-empty never` with 19 `--path` arguments,
  `--path-glob 'examples/places/*.rbxl'` and `--mailmap`.

`--prune-empty never` is deliberate: it keeps a 1:1 commit mapping, so "commits before == commits
after" is a check the rewrite can be held to. The cost is 31 now-empty commits in B (the
place-rebuild commits). If the owner would rather they disappeared, re-run with `--prune-empty auto`
in `build_candidate.sh`; B's commit count then drops by 31 and that verification row changes
accordingly.

---

## Sizes

Measured with `git count-objects -vH` after `git gc --prune=now --aggressive`, and with a real
`git clone` into a temp directory followed by `du -sh`.

| | pack | `.git` on disk | full clone on disk |
|---|---:|---:|---:|
| Original, as a clone receives it today | 202.52 MiB | 209 M | — |
| Original, after `gc --prune=now --aggressive` | **81.10 MiB** | 97 M | — |
| **Candidate A** | **75.18 MiB** | 81 M | 171 M |
| **Candidate B** | **22.66 MiB** | 23 M | 113 M |

**A surprise worth the owner's attention: most of the "180 MB" is a packing artifact, not the
place files.** The audit's headline — 179.4 MB of a 207.65 MB clone is `examples/places/*.rbxl`,
purge it and the repo becomes 28.22 MB — was measured with `git pack-objects` at default settings,
which is what the repository's four-packs-plus-762-loose working state gives you. A single
`gc --prune=now --aggressive` on the *unmodified* repository takes it from 202.52 MiB to
**81.10 MiB** on its own, with nothing removed. Against that honest baseline:

- purging the 15 must-purge files saves **5.9 MiB** (81.10 → 75.18);
- purging 516 historical place revisions on top saves a further **52.5 MiB** (75.18 → 22.66).

So the place binaries cost about **52 MiB**, not 179 MB, once git is allowed to delta-compress
them properly. Candidate B is still a 3.3× smaller pack than candidate A, and B beats even the
audit's optimistic 28.22 MB estimate — but the "180 MB" framing overstates the case for purging
them by roughly 3×. (INFERENCE: GitHub repacks server-side, so what a clone from GitHub actually
transfers will be closer to the aggressive figures than to the local four-pack state; the exact
numbers depend on GitHub's packing, which cannot be measured from here.)

---

## Verification

Every row is filled from tool output captured in each candidate's `report.md`, `build.log` and
`verify/` directory.

| # | Check | Candidate A | Candidate B |
|---|---|---|---|
| a | For each purged path, `git log --all --oneline -- <path>` | 0 commits, all 15 | 0 commits, all 19 |
| a | For each purged path, a blob under it in `git rev-list --all --objects` | 0, all 15 | 0, all 19 |
| a | `examples/places/*.rbxl` | n/a (retained) | 530 blobs before → **14 objects**, in **1** commit (the re-add) |
| a+ | Stronger check: take the purged blobs' **SHAs** from the mirror and ask each candidate for them by SHA (`git cat-file -e`), which no path filter can fake. 27 blobs tested | all 15 must-purge blobs **absent**; the other 12 (6 revisions of `sponsor-view-parity.md`, 2 `.pyc`, 2 `.rbxl.lock`, 2 `goal-prompt-sponsor-view-parity.md`) present, as intended — A purges none of them | **25 of 27 absent** — the 15 must-purge plus all 10 extras blobs. The 2 still present are `docs/plans/goal-prompt-sponsor-view-parity.md`, which is on no purge list |
| a+ | Place blobs by SHA in B | n/a | **14 of 530** present — exactly the re-added tip files |
| b | Commits on `main` before → after | 1,113 → **1,113** | 1,113 → **1,114** (+1 re-add) |
| b | Commits left with an empty tree diff | **0** | 31 — and every one of their subjects is a place rebuild ("Rebuild the ten place files at this tree", "build(places): rebuild all fifteen …"), so nothing but place binaries was lost from them |
| c | `git diff --stat <original tip> <candidate tip>` | **15 files changed, 17,183 deletions(-)**, zero insertions | **16 files changed, 17,666 deletions(-)**, zero insertions |
| c | Are the differences exactly the removed paths? | yes — the 15 must-purge files and nothing else | yes — the 15 plus `docs/reference/sponsor-view-parity.md`; the 14 place files are byte-identical, so they do not appear |
| d | Pack after `gc --prune=now --aggressive` | 75.18 MiB, 1 pack, 0 loose | 22.66 MiB, 1 pack, 0 loose |
| d | Fresh `git clone` + `du -sh` | 171 M total, 81 M `.git` | 113 M total, 23 M `.git` |
| e | `Joshs-Mac-mini` — blobs / commit metadata records | **2 blobs** (both revisions of `examples/places/LuauUI-Showcase.rbxl.lock`) / **1,113** | **0 / 0** |
| e | `Joshs-Mac-mini` via `git log --all -p \| grep -c` | 1,117 lines | **0** |
| e | `/Users/josha` — blobs / paths | 42 blobs / 24 paths | 40 blobs / 22 paths |
| e | `/Users/josha` via `git log --all -p \| grep -c` | 1,068 lines | 1,068 lines |
| f | `./run-tests.sh --fast` in a fresh clone | **4 failed, 7,159 passed**, exit 1 | 4 failed, 7,159 passed, exit 1 |
| f | Control: same command in a fresh clone of the **unmodified** mirror at the same commit | **4 failed, 7,159 passed**, exit 1 — identical | identical |
| f | `lune run tools/lune/check_links_cli` | PASS (163 documents, 635 relative links, 149 heading anchors) | PASS, same counts |
| g | Refs in the candidate | `refs/heads/main` only | `refs/heads/main` only |
| g | Tags | **0** (the mirror has 1) | **0** |
| g | Distinct author+committer identities across all commits | 2,226 records, all `Josh Anon <josha@Joshs-Mac-mini.local>` | 2,228 records, all `Josh Anon <josha@users.noreply.github.com>` |

### Notes on the rows that are not a simple pass

**(e) `/Users/josha` is still in both candidates, by design.** That is audit finding PER-01, which
is classed `remove-from-tip-keep-history`, not `must-purge` — it is a tip scrub, and neither
candidate is a tip scrub. It survives in 40 blobs across 22 paths in B (42 / 24 in A; the two the
extras remove are the `.pyc` files). The paths are captured agent logs and plans:
`artifacts/**` (15 paths), `docs/plans/**` (4), `docs/research/**` (2), `assets/icons/provenance.md`.
The audit's "~1,076 blob matches" for PER-01 is a *line* count, not a blob count — this run
measures 1,068 matching lines in `git log --all -p` and 42 matching blobs, and those two numbers
agree with each other.

**(e) `Joshs-Mac-mini` is fully gone from B and fully present in A.** In the original it lives in
exactly two places: two revisions of one `.rbxl.lock` blob, and the author/committer address on
all 1,113 commits. B removes both; A removes neither. There is no third hiding place — the `.pyc`
blobs embed the compile-time *path*, not the hostname.

**(f) the four failures are pre-existing, not caused by the rewrite.** A fresh clone of the
untouched mirror at the same commit `cf33f8e` fails the same four specs with the same
`4 failed, 7159 passed`. All four are documentation-gate specs reporting that
`docs/extending/new-theme.md` no longer mentions `acceptance-ledger.md`; none names a purged path.
For contrast, the stage's own freeze recorded `7875 passed / 0 failed` at `27c0afd`, so **`main`
has gone red today under the other agents' in-flight work** — that is a live issue for whoever
owns those commits, and it is not this task's to fix. The fast tier also reports itself over
budget (55 s = 129% of the 42.7 s full suite), which is likewise pre-existing.

**(a) one "before" figure looks like a zero and is not.**
`artifacts/example-games-and-standalones/test-optimization/rr-suite-before.txt` and
`rr-suite-after.txt` are **the same blob** (`3ffaa891…`), so `git rev-list --all --objects` lists
that object once, under the "after" path, and the "before" path shows 0 objects in the mirror
column. `git log --all -- <path>` shows 1 commit for each. Both paths are purged, so nothing
leaks; but any future path-based purge check has to allow for blob sharing, because a shared blob
legitimately survives under a path that was not purged.

**(g) the stash tag cannot reach either candidate.** The audit's RMT-01 records that the local tag
`luauui-step8-baseline` points at `f1f0454`, a `git stash` commit that is not an ancestor of
`main` and drags 58 WIP objects with it. The frozen mirrors carry it (they are mirrors); the
candidates are cloned `--single-branch --branch main --no-tags`, so neither has any tag at all —
confirmed by `git tag | wc -l` = 0 in both, and by `for-each-ref` showing only `refs/heads/main`.

### Two follow-ups this run turned up

1. **Purging `docs/reference/sponsor-view-parity.md` (B) leaves 20+ references to it at the tip**,
   including a live markdown link at `docs/plans/facet-consolidated-roadmap.md:119`
   (`[../reference/sponsor-view-parity.md](../reference/sponsor-view-parity.md)`), and the sibling
   `docs/plans/goal-prompt-sponsor-view-parity.md`, which is the goal prompt for the same study
   and is *not* on any purge list. `check_links_cli` still passes only because `docs/plans/` is on
   its `ARCHIVED_PREFIXES` list — material already earmarked not to go public. If the plans
   directory ships, that link dangles.
2. **The audit's must-purge selection is right.** The other three `artifacts/**/game-suite.txt`
   files at the tip (919, 125 and 50 bytes) are one-line pass summaries with zero hits for the
   internal system names, so they are correctly left out of the purge — they fall under PRJ-04's
   tip-scrub instead.

---

## Proof that the working repository was not modified

Nothing in this run wrote to `GameStudio/ui/Facet` except the two files this stage is allowed to
add — this one and `history-candidate-commands.md`. Every rewrite happened on mirror clones under
`Facet-private-archive/history-rewrite/`. No commit, no checkout, no `git gc`, no ref change, no
config change, and no push, anywhere.

| | At session start | At session end |
|---|---|---|
| `HEAD` | `f092312da06ba54472f984816ad3fd794e99528c` | `fff916276048c02a43bcdf832bb0d44a605e2f8b` |
| `origin/main` | `27c0afd21da16540d2b0c46327eaea8a8ddb8904` | `27c0afd21da16540d2b0c46327eaea8a8ddb8904` — **unchanged** |
| `refs/tags/luauui-step8-baseline` | `f1f045418ff00925edbd99c4324935e8535510bd` | same — **unchanged** |
| stashes | 0 | 0 |

**`HEAD` moved, and `git status --porcelain` returns a different set of paths, because other
agents committed 18 times to `main` while this ran** — including `cf33f8e`, the commit both
candidates are built from. `git log --oneline f092312..HEAD` shows their work
("Point the public documents at the package reference…", "Continuous integration runs the same
commands a contributor runs", and so on); `git log --name-only f092312..HEAD | grep -i
'history-candidate\|history-rewrite'` returns nothing, so none of those commits is this task's.
The only entries this task added to `git status` are the two untracked report files above.

Two things it is worth being explicit about, because they were already red before this task
started and are *not* caused by it:

- `./run-tests.sh --fast` on committed `main` is at **4 failed, 7,159 passed** (four documentation
  gates about `docs/extending/new-theme.md` and `acceptance-ledger.md`). The stage freeze recorded
  `7875 passed / 0 failed` at `27c0afd`, so this went red today under the in-flight work.
- `python3 tools/check_brand_drift.py` exits 1 with **191 old-brand matches, all of them inside
  `tools/lune/verify/graph.json`**, an uncommitted file belonging to another agent. Zero matches
  are in either file this task wrote.

---

## Owner migration and rollback procedure

Read this whole section before running any of it. Steps 2 onward are destructive and irreversible
except by step 5.

Preconditions, from this stage's own `freeze.md` (recorded 2026-08-30, so FACT as of today):
`github.com/josha/LuauUI` is **private**, viewer permission **ADMIN**, default branch `main`,
**`main` is the only remote ref, 0 tags, 0 releases, 0 Actions runs or workflows, 0 issues, wiki
disabled, no Pages, no webhooks, 0 Actions secrets, collaborators: `josha` only**, and the target
name `josha/Facet` was **available (404)**. Re-check fork count and open pull requests
(`gh api repos/josha/LuauUI --jq '.forks_count'` and `gh pr list --repo josha/LuauUI --state all`)
immediately before step 2 — the freeze did not enumerate them.

### 0. Re-run the rewrite on the FINAL commit

**This is not optional.** The candidates above were built from `cf33f8e`, and `main` has moved
since. Every local commit that is not in the candidate is orphaned by the rewrite: its SHA ceases
to exist upstream, and any agent or worktree still holding it will have to rebase or re-apply by
hand. So: stop all agents, land every commit that is going to be in the release, confirm the suite
is green, and only then build the candidate you are actually going to push.

```sh
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet-private-archive/history-rewrite

./build_candidate.sh \
  /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet \
  candidate-final \
  --bulk --extras --email 'josha@users.noreply.github.com'      # drop flags to choose A's shape

cat candidate-final/report.md      # confirm every check before going further
```

The script deletes and rebuilds `candidate-final/` from scratch each time, so it is safe to re-run
as often as you like.

### 1. Archive the pre-rewrite mirror off Dropbox

`candidate-final/source.git` is the only complete copy of the pre-rewrite history once the remote
is overwritten, and it currently lives inside the Dropbox tree next to the repository it is
supposed to protect. Move it to different physical media.

```sh
STAMP=$(date +%Y%m%d-%H%M)
DEST="/Volumes/<external-disk>/facet-prerewrite-$STAMP"       # any non-Dropbox volume
mkdir -p "$DEST"

cp -R candidate-final/source.git "$DEST/source.git"
git -C "$DEST/source.git" fsck --full                          # must report no errors
git -C "$DEST/source.git" for-each-ref  > "$DEST/refs.txt"
git -C "$DEST/source.git" rev-list --all --count > "$DEST/commit-count.txt"

tar -czf "$DEST.tar.gz" -C "$(dirname "$DEST")" "$(basename "$DEST")"
shasum -a 256 "$DEST.tar.gz" | tee "$DEST.tar.gz.sha256"
```

Keep `$DEST.tar.gz`, `$DEST.tar.gz.sha256` and `refs.txt` together. Do not delete them until the
public repository has been live and correct for as long as you are willing to bet on.

### 2. Rename the GitHub repository, then force-push the candidate

Two routes. **Route A is the one to prefer here**, because it is the only one that actually
removes the purged blobs from GitHub's storage without a support ticket.

**Route A — delete and recreate (recommended).** Legitimate here precisely because the freeze
found nothing to preserve: no issues, no pull requests, no releases, no Actions history, no
collaborators but the owner. It costs you the old-name redirect and any stars or watchers.

```sh
gh repo view josha/LuauUI --json name,visibility,forkCount,stargazerCount,issues,pullRequests
gh auth refresh -s delete_repo                 # `gh repo delete` needs this scope
gh repo delete josha/LuauUI                    # interactive confirmation
gh repo create josha/Facet --private
cd candidate-final/candidate
git remote add origin https://github.com/josha/Facet.git
git push --force --all  origin
git push --force --tags origin                 # the candidate has 0 tags; this proves it
```

**Route B — rename in place and force-push.** Keeps the repository object, the redirect from
`josha/LuauUI`, and anything attached to it. Leaves the purged blobs in GitHub's storage until
support purges them (see the caveats below).

```sh
gh repo rename Facet --repo josha/LuauUI
gh repo view josha/Facet --json name,visibility,defaultBranchRef

cd candidate-final/candidate
git remote add origin https://github.com/josha/Facet.git
git push --force --all  origin
git push --force --tags origin
```

Do **not** change visibility in this step. Leave the repository private until step 4 has passed.

Never run `git push --tags` from the *mirror* — that publishes `luauui-step8-baseline` and the 58
stash objects hanging off it.

### 3. Update the local repository

Save anything uncommitted first; the rewrite makes the old SHAs unreachable.

```sh
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
git status --porcelain                                   # expect empty after step 0
git diff  > /tmp/facet-uncommitted.patch                 # if it is not empty
git diff --cached >> /tmp/facet-uncommitted.patch

git remote set-url origin https://github.com/josha/Facet.git
git fetch --all --prune
git reset --hard origin/main
git reflog expire --expire=now --all
git gc --prune=now
git tag -d luauui-step8-baseline                         # the stash tag; do this or never push tags
```

The cleaner alternative, and the one to use if anything above complains, is to re-clone:

```sh
cd .../GameStudio/ui
mv Facet Facet-old-prerewrite
git clone https://github.com/josha/Facet.git Facet
# re-run both Rojo projects' tests and a Studio canary before deleting Facet-old-prerewrite
```

**What happens to other agents' unpushed work:** anything committed locally after the commit the
candidate was built from is *not* in the candidate, and after `reset --hard` it is reachable only
through the reflog of the old clone — which step 3 then expires. That is exactly why step 0 says
to build the candidate on the final commit with every agent stopped. **The 2026-08-30 run
documented above is a rehearsal, not the artifact to push:** ten commits landed while it ran.

### 4. Verify on GitHub

```sh
gh api repos/josha/Facet --jq '{name,visibility,default_branch,size,forks_count,open_issues_count}'
gh api --paginate repos/josha/Facet/commits --jq '.[].sha' | wc -l    # must equal the candidate's count
git ls-remote https://github.com/josha/Facet.git                      # must be refs/heads/main + HEAD only

rm -rf /tmp/facet-verify
git clone https://github.com/josha/Facet.git /tmp/facet-verify
cd /tmp/facet-verify

du -sh .git
git rev-list --count HEAD
git log --all --format='%ae %ce' | sort -u                            # only the intended address

# every purged path must produce nothing, twice over
for p in docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg \
         docs/plans/reference-media/2026-08-16-roblox-app-navigation/r1-popup-list.mov \
         docs/plans/reference-media/2026-08-16-roblox-app-navigation/r2-top-tab-bar.mov \
         docs/plans/reference-media/2026-08-16-roblox-app-navigation/r3-segmented-control.mov \
         artifacts/api-architecture-consistency/game-suite.txt \
         artifacts/example-games-and-standalones/test-optimization/rr-suite-before.txt \
         artifacts/example-games-and-standalones/test-optimization/rr-suite-after.txt \
         artifacts/release-candidate-review/baseline/suite-rr.txt; do
  printf '%s  log=%s\n' "$p" "$(git log --all --oneline -- "$p" | wc -l | tr -d ' ')"
done
git rev-list --all --objects | grep -E 'roblox-app-navigation/(f1-|r1-|r2-|r3-)' ; echo "exit $?  (1 = clean)"
git rev-list --all --objects | grep -E 'game-suite\.txt|rr-suite-|suite-rr\.txt'  ; echo "exit $?  (1 = clean)"

./run-tests.sh          # the full suite, from a clone a stranger could have made
```

Only after all of that: change visibility, in the GitHub UI or with
`gh repo edit josha/Facet --visibility public --accept-visibility-change-consequences`.

### 5. Rollback

The mirror restores the exact pre-rewrite state, including every original SHA.

```sh
cd "$DEST/source.git"                                  # the archived mirror from step 1
git push --force https://github.com/josha/Facet.git 'refs/heads/main:refs/heads/main'
gh repo rename LuauUI --repo josha/Facet               # if you took route B and want the old name back
```

Push `refs/heads/main` explicitly, **not** `--all` and **not** `--tags`: `--mirror`/`--tags` from
this archive would publish `luauui-step8-baseline` and its 58 stash objects, which is a different
leak. If you took route A, the old repository object is gone — recreate it
(`gh repo create josha/LuauUI --private`) and push into that instead; issues, stars and the
redirect do not come back.

Locally, `git reset --hard <old sha>` still works in any clone that has not been gc'd, and the
archived mirror can be re-cloned at any time.

### GitHub-side caveats — what is FACT and what is INFERENCE

**FACT**, from
<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository>
(fetched 2026-08-30): after a rewrite and force-push, the old data remains accessible
"in any clones or forks of your repository", "directly via their SHA-1 hashes in cached views on
GitHub", and "through any pull requests that reference them". To have GitHub actually remove it
you must contact GitHub Support with "the owner and repository name", "the number of affected pull
requests" and "the First Changed Commit(s)"; support will then "dereference or delete any affected
PRs on GitHub", "run a garbage collection on the server to expunge the sensitive data from
storage", and "remove cached views". Forks are not covered: "If the commit that introduced the
sensitive data exists in any forks, it will continue to be accessible there. You will need to
coordinate with the owners of the forks." And where the data is a credential, GitHub says to
revoke or rotate it first.

**FACT**, from this stage's own audit: there is **no credential of any kind anywhere in this
history** (SEC-01 through SEC-05, zero matches over 7,026 text blobs and 673 binary blobs), so
there is nothing to rotate. The must-purge material is third-party trade dress and private-game
prose, neither of which becomes safe by rotation.

**INFERENCE** (reasoned, not measured here): because the repository has always been private, has a
single collaborator, and the freeze found no other refs, the population that could hold a clone or
fork containing the purged blobs is very likely just this machine. That is why route A —
delete and recreate — is worth its cost: it makes the "GitHub keeps unreachable objects until
support purges them" problem structurally impossible, with no ticket and no waiting, and there is
nothing attached to the repository that deleting it would destroy. If route B is taken instead,
open a support ticket in the same sitting as the force-push and treat the purged blobs as still
retrievable-by-SHA until support confirms otherwise.

**INFERENCE**: `gh repo rename` leaves a redirect from the old URL, and the repository's numeric id
(`1320732857`, `R_kgDOTrjIuQ`) is unchanged by a rename. Neither was tested in this session.

**FACT, checked locally:** the `gh` command forms above exist in the installed `gh 2.89.0` —
`gh repo rename <new-name> --repo OWNER/REPO`, `gh repo delete <repo>` (which "requires
authorization with the `delete_repo` scope"), and `gh repo edit --visibility` (which states "When
the `--visibility` flag is used, `--accept-visibility-change-consequences` flag is required").
Checked with `--help`; no command was run against GitHub.

**Not verified here at all:** nothing in this session contacted GitHub. No push, no rename, no
visibility change, no `gh` call against the remote. Every remote fact above comes from
`artifacts/distribution-readiness/freeze.md` or from the GitHub documentation page cited.
