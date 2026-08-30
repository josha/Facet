# Clean-history candidate — every command run

Session date **2026-08-30**. Every command below was run with

```sh
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
```

Shorthands used in this file:

| Name | Path |
|---|---|
| `REPO` | `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet` |
| `HR` | `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet-private-archive/history-rewrite` |
| `VENV` | `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/.venv` |
| `SCRATCH` | the session scratchpad under `/private/tmp/claude-501/…` |

**Nothing below writes to `REPO`** except the two report files this stage is allowed to add
(`artifacts/distribution-readiness/audit/history-candidate.md` and this file). Every `git`
invocation against `REPO` is read-only (`status`, `rev-parse`, `log`, `show`, `ls-tree`,
`rev-list`, `for-each-ref`, `check-ignore`, `remote -v`).

---

## 1. Read the inputs

```sh
git -C REPO rev-parse HEAD
git -C REPO rev-parse --abbrev-ref HEAD
git -C REPO status --porcelain > SCRATCH/status-before.txt
git -C REPO rev-parse HEAD      > SCRATCH/head-before.txt

cat REPO/artifacts/distribution-readiness/audit/history-audit.md
cat REPO/artifacts/distribution-readiness/audit/bulk.md
python3 -c "import json; d=json.load(open('findings.json')); ..."   # must-purge + owner-decision rows
sed -n '/Repository-wide privacy and provenance audit/,/^## /p' REPO/docs/plans/distribution-readiness.md
sed -n '1,80p' REPO/artifacts/distribution-readiness/freeze.md
```

## 2. Establish the exact historical paths

```sh
git -C REPO rev-list --all --objects > SCRATCH/all-objects.txt
awk '{$1="";print substr($0,2)}' SCRATCH/all-objects.txt | grep -i 'rbxl.lock'          | sort -u
awk '{$1="";print substr($0,2)}' SCRATCH/all-objects.txt | grep -i 'pycache\|\.pyc$'    | sort -u
awk '{$1="";print substr($0,2)}' SCRATCH/all-objects.txt | grep -i 'sponsor-view-parity' | sort -u
awk '{$1="";print substr($0,2)}' SCRATCH/all-objects.txt | grep 'roblox-app-navigation'  | sort -u
awk '{$1="";print substr($0,2)}' SCRATCH/all-objects.txt \
  | grep -E 'game-suite\.txt|rr-suite-before\.txt|rr-suite-after\.txt|suite-rr\.txt' | sort -u

git -C REPO ls-tree -r main | grep -E 'game-suite\.txt|rr-suite-(before|after)\.txt|suite-rr\.txt'
git -C REPO rev-list main --count
git -C REPO rev-list --all --count
git -C REPO for-each-ref --format='%(refname) %(objectname:short)'
git -C REPO rev-list --merges main --count        # 0
git -C REPO rev-list --max-parents=0 main --count # 1
git -C REPO show --stat --oneline -s e5973f9
git -C REPO show --format= --name-only e5973f9
git -C REPO check-ignore -v examples/places/Facet-Showcase.rbxl   # exit 1 = not ignored
grep -n 'rbxl\|places' REPO/.gitignore
git -C REPO remote -v

# do the other three artifacts/**/game-suite.txt files carry the same private content?
for f in artifacts/authoring-adaptive-ui/game-suite.txt \
         artifacts/native-stylesheets/game-suite.txt \
         artifacts/native-substrate/game-suite.txt \
         artifacts/api-architecture-consistency/game-suite.txt; do
  git -C REPO show main:"$f" | wc -c
  git -C REPO show main:"$f" | grep -cE 'KartBodyFeel|FarAILod|GearDockModel'
done
```

## 3. Install `git filter-repo`

```sh
which git-filter-repo            # not found
git filter-repo --version        # 'filter-repo' is not a git command
VENV/bin/pip install git-filter-repo
VENV/bin/pip show git-filter-repo    # Version: 2.47.0
VENV/bin/git-filter-repo --help | grep -E 'prune-empty|mailmap|path-glob|invert-paths|--force|--refs'
```

`git filter-branch` was never used.

## 4. Author the tooling

Two new files, both under `HR/` (outside the repository):

- `HR/build_candidate.sh` — the re-runnable builder and verifier.
- `HR/scan_history.py` — streams every unique blob of a repository through one
  `git cat-file --batch` and reports, per pattern, the matching blob count, the paths those
  blobs are known by, and a separate count over commit metadata.

```sh
chmod +x HR/build_candidate.sh HR/scan_history.py
bash -n HR/build_candidate.sh
```

## 5. Build the candidates

```sh
# candidate A — the 15 must-purge files only, straight from the live repository
HR/build_candidate.sh REPO candidate-A-must-purge

# candidate B — must-purge + bulk + extras + email, from A's frozen mirror so that both
# candidates provably share the same baseline commit while other agents keep committing
HR/build_candidate.sh HR/candidate-A-must-purge/source.git candidate-B-full \
    --bulk --extras --email 'josha@users.noreply.github.com'
```

The script itself runs, in order:

```sh
git clone --mirror --no-hardlinks "$SRC" "$OUT/source.git"
git clone --no-local --no-tags --single-branch --branch main "$OUT/source.git" "$OUT/candidate"
git -C "$OUT/candidate" archive main examples/places | tar -x -C "$OUT/places-tip"   # --bulk only
cd "$OUT/candidate" && VENV/bin/git-filter-repo <args>                               # see below
cp -R "$OUT/places-tip/examples/places" "$OUT/candidate/examples/places"             # --bulk only
git -C "$OUT/candidate" add -A examples/places                                       # --bulk only
git -C "$OUT/candidate" commit -m "Restore the place builds at the tip after the history rewrite"
git -C "$OUT/candidate" reflog expire --expire=now --all
git -C "$OUT/candidate" gc --prune=now --aggressive
```

### The exact `git filter-repo` command lines

Candidate A:

```sh
git filter-repo --invert-paths --prune-empty never \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r1-a-closed-trigger.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r1-b-menu-open-sheet.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r1-c-content-changed.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r1-popup-list.mov \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r2-a-tab-for-you.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r2-b-tab-charts-loading.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r2-top-tab-bar.mov \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r3-a-segment-middle.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r3-b-segment-left-content-swapped.png \
  --path docs/plans/reference-media/2026-08-16-roblox-app-navigation/r3-segmented-control.mov \
  --path artifacts/api-architecture-consistency/game-suite.txt \
  --path artifacts/example-games-and-standalones/test-optimization/rr-suite-before.txt \
  --path artifacts/example-games-and-standalones/test-optimization/rr-suite-after.txt \
  --path artifacts/release-candidate-review/baseline/suite-rr.txt
```

Candidate B — the same 15 `--path` arguments, plus:

```sh
  --path examples/places/LuauUI-Showcase.rbxl.lock \
  --path assets/themes/glossy-touch/source/__pycache__/generate_art.cpython-314.pyc \
  --path assets/themes/fantasy-parchment/source/__pycache__/generate_art.cpython-314.pyc \
  --path docs/reference/sponsor-view-parity.md \
  --path-glob 'examples/places/*.rbxl' \
  --mailmap <OUT>/mailmap.txt
```

`mailmap.txt` is one line:

```
Josh Anon <josha@users.noreply.github.com> <josha@Joshs-Mac-mini.local>
```

### Two failures on the way, and the fixes

```sh
# 1. filter-repo aborted: "Refusing to destructively overwrite repo history since this does not
#    look like a fresh clone. (expected freshly packed repo) ... you need to pass --no-local"
#    Fix: the working clone now uses --no-local instead of --no-hardlinks.  --force was NOT used,
#    so filter-repo's own safety check stays armed.
#
# 2. scan_history.py raised ValueError: embedded null byte, because a literal NUL cannot be
#    passed through argv.  Fix: git's own escape, --format=...%n%x00
```

## 6. Verification (run by the script, per candidate)

```sh
git -C "$CAND" rev-list --all --objects > verify/cand-objects.txt
git -C "$MIRROR" rev-list --all --objects > verify/mirror-objects.txt

# (a) per purged path
git -C "$CAND" log --all --oneline -- "$p" | wc -l          # must be 0
awk -v P="$p" '{ $1=""; sub(/^ /,""); if ($0==P) c++ } END{print c+0}' verify/cand-objects.txt

# (b) commit counts
git -C "$MIRROR" rev-list --count refs/heads/main
git -C "$CAND"   rev-list --count main
git -C "$CAND" log --format='%x01%H' --name-only main | awk '...'   # commits with an empty diff

# (c) tree diff against the ORIGINAL tip, in a third scratch repository so that neither the
#     mirror nor the candidate is written to
git init -q "$CMP"
git -C "$CMP" fetch -q --no-tags --depth=1 "file://$MIRROR" refs/heads/main:refs/heads/orig
git -C "$CMP" fetch -q --no-tags --depth=1 "file://$CAND"   refs/heads/main:refs/heads/cand
git -C "$CMP" diff --stat        orig cand
git -C "$CMP" diff --name-status orig cand

# (d) sizes
git -C "$MIRROR" count-objects -vH
git -C "$CAND"   count-objects -vH
git clone -q "$CAND" "$FRESH" && du -sh "$FRESH" "$FRESH/.git"

# (e) hostname / home-path scan
VENV/bin/python3 HR/scan_history.py "$CAND" "Joshs-Mac-mini" "/Users/josha"
git -C "$CAND" log --all -p | grep -c "Joshs-Mac-mini"
git -C "$CAND" log --all -p | grep -c "/Users/josha"

# (f) is it a working repository?
cd "$FRESH" && ./run-tests.sh --fast

# (g) refs
git -C "$CAND"  for-each-ref --format='%(refname) %(objectname)'
git -C "$FRESH" for-each-ref --format='%(refname) %(objectname)'
git -C "$CAND"  tag | wc -l
git -C "$MIRROR" tag | wc -l
```

## 7. Extra verification run by hand

```sh
# baseline scan of the untouched mirror, so (e) has a before as well as an after
VENV/bin/python3 HR/scan_history.py HR/candidate-A-must-purge/source.git "Joshs-Mac-mini" "/Users/josha"

# how many commits touched each purged path BEFORE the rewrite
for p in <the 19 paths>; do git -C HR/candidate-A-must-purge/source.git log --all --oneline -- "$p" | wc -l; done
git -C HR/candidate-A-must-purge/source.git log --all --oneline -- 'examples/places/*.rbxl' | wc -l

# size baselines for the UNMODIFIED repository at the same commit
git clone --no-local -q HR/candidate-A-must-purge/source.git /private/tmp/facet-orig-baseline
du -sh /private/tmp/facet-orig-baseline/.git
git -C /private/tmp/facet-orig-baseline count-objects -vH
git -C HR/candidate-A-must-purge/source.git rev-list --all --objects | awk '{print $1}' \
  | git -C HR/candidate-A-must-purge/source.git pack-objects --stdout | wc -c
git -C /private/tmp/facet-orig-baseline reflog expire --expire=now --all
time git -C /private/tmp/facet-orig-baseline gc --prune=now --aggressive
du -sh /private/tmp/facet-orig-baseline/.git
git -C /private/tmp/facet-orig-baseline count-objects -vH

# THE CONTROL for the four test failures: same commit, no rewrite
cd /private/tmp/facet-orig-baseline && git rev-parse HEAD && ./run-tests.sh --fast

# identities and re-added places
git -C HR/candidate-A-must-purge/candidate log --all --format='%an <%ae>%n%cn <%ce>' | sort | uniq -c
git -C HR/candidate-B-full/candidate      log --all --format='%an <%ae>%n%cn <%ce>' | sort | uniq -c
git -C HR/candidate-B-full/candidate ls-tree --name-only main examples/places/ | wc -l
git -C HR/candidate-B-full/candidate log -3 --format='%H%n  A: %an <%ae> %aI%n  C: %cn <%ce> %cI%n  S: %s'
git -C HR/candidate-B-full/candidate log --format='%H %an <%ae> %s' --max-parents=0
git -C HR/candidate-B-full/candidate for-each-ref

# does anything still point at the file B removes?
git -C HR/candidate-B-full/candidate grep -n 'sponsor-view-parity' main -- .
cd HR/candidate-A-must-purge/candidate && lune run tools/lune/check_links_cli
cd HR/candidate-B-full/candidate      && lune run tools/lune/check_links_cli
```

## 8. Proof that the working repository was not touched

```sh
git -C REPO status --porcelain > SCRATCH/status-after.txt
git -C REPO rev-parse HEAD     > SCRATCH/head-after.txt
diff SCRATCH/status-before.txt SCRATCH/status-after.txt
git -C REPO log --oneline f092312..044d07b
git -C REPO rev-list --count f092312..044d07b
git -C REPO log --name-only --format='--- %h %s' f092312..044d07b | grep -i 'history-candidate\|history-rewrite'
git -C REPO for-each-ref --format='%(refname) %(objectname:short)'
```

## 9. External reference fetched

```
https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
```

## 10. SHA-level purge proof (stronger than the path check)

```sh
M=HR/candidate-A-must-purge/source.git
git -C "$M" rev-list --all --objects \
  | awk '{p=$0; sub(/^[0-9a-f]+ /,"",p);
          if (p ~ /roblox-app-navigation\/(f1-|r1-|r2-|r3-)/ \
           || p ~ /(game-suite\.txt|rr-suite-after\.txt|suite-rr\.txt)$/ \
           || p ~ /rbxl\.lock$/ || p ~ /\.pyc$/ || p ~ /sponsor-view-parity\.md$/) print $1, p}' \
  | grep -v 'authoring-adaptive\|native-stylesheets\|native-substrate' > /tmp/purged-shas.txt   # 27 blobs

while read -r sha p; do
  git -C HR/candidate-A-must-purge/candidate cat-file -e "$sha" 2>/dev/null || echo "absent in A"
  git -C HR/candidate-B-full/candidate       cat-file -e "$sha" 2>/dev/null || echo "absent in B"
done < /tmp/purged-shas.txt

git -C "$M" rev-list --all --objects | awk '$2 ~ /^examples\/places\/.*\.rbxl$/ {print $1}' | sort -u \
  > /tmp/place-shas.txt                                                                      # 530 blobs
while read -r sha; do git -C HR/candidate-B-full/candidate cat-file -e "$sha" 2>/dev/null && echo present; done \
  < /tmp/place-shas.txt | wc -l                                                              # 14
```

## 11. `gh` command forms checked locally (no network)

```sh
gh repo edit   --help | grep -iA2 visibility
gh repo rename --help
gh repo delete --help
```

## 12. Did adding these two files redden anything?

```sh
cd REPO && python3 tools/check_brand_drift.py     # exit 1, 191 matches — ALL in tools/lune/verify/graph.json
                                                  # (another agent's uncommitted file); 0 in either new file
```
