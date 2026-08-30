# Facet — audit commands

Every command run for this audit, in order, so it can be reproduced. All are read-only: nothing
was written to the repository outside `artifacts/distribution-readiness/audit/`, no history was
rewritten, nothing was pushed, and the test suite was not run.

Run everything from the repo root:

```sh
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
git checkout 27c0afd    # the audit baseline = origin/main. 11 unpushed commits landed after it.
SP=/tmp/facet-audit && mkdir -p "$SP"     # scratch, outside the repo
```

## 0. Orientation

```sh
git rev-parse HEAD                                        # 27c0afd
git status --porcelain                                    # 2 modified files, ignored per brief
git for-each-ref --format='%(refname) %(objecttype) %(objectname:short)'
git rev-list --all --count                                # 1097
git rev-list main --count                                 # 1094
git count-objects -vH                                     # 4 packs 233.95 MB + 762 loose 186.00 MB
git log --all --format='A:%an <%ae>' | sort -u            # 2 authors
cat .gitignore
git ls-tree HEAD --name-only                              # confirms: no root LICENSE
```

## 1. Build the object and blob inventory

```sh
git rev-list --all --objects > $SP/allobjs.txt                     # 15,393 objects

git rev-list --all --objects \
  | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(rest)' \
  | grep '^[0-9a-f]* blob' > $SP/blobs.txt                          # 7,699 blobs

# dedupe by SHA, split text vs binary by extension
awk '{sha=$1;size=$3;p="";for(i=4;i<=NF;i++)p=p (i>4?" ":"") $i;
      if(!(sha in seen)){seen[sha]=1; print sha"\t"size"\t"p}}' $SP/blobs.txt > $SP/uniqblobs.tsv

grep -viE '\.(rbxl|rbxm|rbxlx|png|jpg|jpeg|gif|mov|mp4|ttf|otf|woff2?|zip|gz|tar|ico|webp|mp3|ogg|wav|pdf)$' \
  $SP/uniqblobs.tsv > $SP/textblobs.tsv                             # 7,026 text blobs, 397.2 MB
grep  -iE '\.(rbxl|rbxm|rbxlx|png|jpg|jpeg|gif|mov|mp4|ttf|otf|woff2?|zip|gz|tar|ico|webp|mp3|ogg|wav|pdf)$' \
  $SP/uniqblobs.tsv > $SP/binblobs.tsv                              # 673 binary blobs
cut -f1 $SP/textblobs.tsv > $SP/textshas.txt
cut -f1 $SP/binblobs.tsv  > $SP/binshas.txt
```

## 2. Secrets — every text blob on every ref

`git cat-file --batch` streams blob contents; `grep -o` prints only the matched text, so no
surrounding context is captured. Both passes returned the results quoted in `history-audit.md`.

```sh
# Pass A — high-entropy credential shapes. RESULT: zero matches.
git cat-file --batch --buffer < $SP/textshas.txt \
 | LC_ALL=C grep -aoE '\.ROBLOSECURITY|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|hooks\.slack\.com/services|discordapp?\.com/api/webhooks|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|Bearer [A-Za-z0-9._-]{25,}' \
 | sort | uniq -c | sort -rn

# Pass B — soft patterns: assignments, key-file references, env var names.
git cat-file --batch --buffer < $SP/textshas.txt \
 | LC_ALL=C grep -aoiE 'ROBLOSECURITY|x-api-key[^\n]{0,60}|(password|passwd|secret|api[_-]?key|apikey|token)[[:space:]]*[=:][[:space:]]*["'"'"'][A-Za-z0-9_/+-]{12,}["'"'"']|OPENAI_API_KEY|GEMINI_API_KEY|MESHY_API_KEY|TRIPO_API_KEY|ROBLOX_API_KEY|API_KEYS\.txt|\.env\b' \
 | sort | uniq -c | sort -rn
# -> .env 6169 (Luau property access), ROBLOX_API_KEY 20, API_KEYS.txt 19,
#    "x-api-key: <same>" 3, "x-api-key: <key with scope `assets`, read + write>" 3,
#    'x-api-key", key)' 2.  No values.

# Attribute the soft hits to paths, then read the context
for pat in ROBLOX_API_KEY 'API_KEYS.txt' 'x-api-key' 'ROBLOSECURITY'; do
  echo "### $pat"
  git grep -l -F "$pat" $(git rev-list --all --max-count=400) -- | sed 's/^[0-9a-f]*://' | sort -u
done
git show HEAD:tools/upload_icons.py | grep -n -iE 'key|env|secret|token|http|url'
git show HEAD:docs/plans/compact-label.md | grep -n -iE -B2 -A2 'api.key|x-api-key'
```

## 3. Personal and machine data

```sh
# All text blobs, matched text only
git cat-file --batch --buffer < $SP/textshas.txt \
 | LC_ALL=C grep -aoiE '/Users/[A-Za-z0-9_.-]+|Joshs-Mac-mini[A-Za-z0-9.-]*|/private/tmp/claude-[0-9]*|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|/Volumes/[A-Za-z0-9_ .-]+|CloudStorage/Dropbox|Dropbox/Documents|\bUntitledRacingGame\b|/home/[a-z0-9_-]+' \
 | sort | uniq -c | sort -rn

# Attribute to tip paths
for pat in '/Users/josha' 'Joshs-Mac-mini' '/private/tmp/claude-' 'CloudStorage/Dropbox' 'UntitledRacingGame'; do
  echo "### $pat files=$(git grep -l -F "$pat" HEAD -- | wc -l) lines=$(git grep -c -F "$pat" HEAD -- | awk -F: '{s+=$NF} END{print s+0}')"
  git grep -l -F "$pat" HEAD -- | sed 's|^HEAD:||' | awk -F/ '{print $1"/"$2}' | sort | uniq -c | sort -rn
done

# The hostname is history-only: find the commits and read the blob
git log --all --oneline -S'Joshs-Mac-mini' --name-only
git show 51ff4a1^:examples/places/LuauUI-Showcase.rbxl.lock      # hostname + PID + 2 UUIDs

# .pyc blobs embed their compile-time absolute path
git show 664d974^:assets/themes/glossy-touch/source/__pycache__/generate_art.cpython-314.pyc \
 | LC_ALL=C strings -n 4 | grep -aiE '/Users|Dropbox|josha|\.py$'
git log --all --oneline --diff-filter=D --name-only -- '*/__pycache__/*'

# IP addresses
git cat-file --batch --buffer < $SP/textshas.txt \
 | LC_ALL=C grep -aoE '\b(([0-9]{1,3})\.){3}[0-9]{1,3}\b' | sort | uniq -c | sort -rn
git grep -n -F '151.0.0.0' HEAD --                   # -> a Chrome VERSION, not an IP
git grep -n -E '8\.8\.8\.8|1\.1\.1\.1' HEAD --       # -> public DNS cited in a research doc
```

## 4. Private Roblox identifiers

```sh
# Tip
for pat in '110532093445029' '10429557340' '1364639953'; do
  echo "### $pat"; git grep -n -F "$pat" HEAD -- | sed 's|^HEAD:||'
done
git grep -nEi '(place|universe|game)_?id["'"'"']?\s*[=:]\s*"?[0-9]{9,16}' HEAD --   # no matches

# All history, text
git log --all --oneline -S'110532093445029' | wc -l      # 0
git log --all --oneline -S'10429557340'     | wc -l      # 0
```

## 5. Binary blobs — place files, images, video

Text greps cannot see inside `.rbxl`, so all 673 binary blobs were streamed through `strings`, and
then through an exact byte-count pass that attributes hits to paths.

```sh
git cat-file --batch --buffer < $SP/binshas.txt \
 | LC_ALL=C strings -n 6 \
 | LC_ALL=C grep -aoE '/Users/[A-Za-z0-9_.-]+|Joshs-Mac-mini[A-Za-z0-9.-]*|110532093445029|10429557340|1364639953|ROBLOSECURITY|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|RascalRally|UntitledRacingGame|CloudStorage/Dropbox' \
 | sort | uniq -c | sort -rn
# -> RascalRally 7132.  No paths, no hostnames, no place ids, no credentials.

# Per-blob attribution (script: binattrib.py, in this audit's scratch)
#   reads $SP/blobs.txt for sha->path, streams git cat-file --batch over $SP/binblobs.tsv,
#   and counts exact literals per blob.
python3 $SP/binattrib.py
# -> all 530 examples/places/*.rbxl blobs carry 152-605 "RascalRally" and 25-82 "Rascal Rally"

# What those strings actually are
git show HEAD:examples/places/00_settings_demo.rbxl | LC_ALL=C strings -n 8 | grep -a 'RascalRally'
# -> Facet source COMMENTS compiled into the place, e.g. "a `UI.When` flip: RascalRally's Sponsor"
git grep -o -F 'RascalRally' HEAD -- src | wc -l         # 43
git grep -o -F 'RascalRally' HEAD -- examples | wc -l    # 18
```

## 6. Rascal Rally and private-project leakage

```sh
git grep -c -E 'bunny_bolt|furry_flash|razz_raccoon|prickles|bruno_bear|wrenchy_penguin' HEAD --
git log --all --format='%h %s' | grep -iE 'rascal'
git log --all --oneline --diff-filter=D --name-only        # no deleted game-keyword files
for f in artifacts/api-architecture-consistency/game-suite.txt \
         artifacts/example-games-and-standalones/test-optimization/rr-suite-before.txt \
         artifacts/example-games-and-standalones/test-optimization/rr-suite-after.txt \
         artifacts/release-candidate-review/baseline/suite-rr.txt; do
  echo "$(git cat-file -s HEAD:$f) $f"
done
```

## 7. Rights and provenance

```sh
git ls-tree -r --name-only HEAD | grep -iE 'licen[cs]e|copying|notice|provenance|attribution|third.?party'
git show HEAD:vendor/Fusion/LICENSE
git show HEAD:vendor/Fusion/VENDOR.md | grep -inE 'tag|version|v0\.3|upstream|commit'
git log --oneline -- vendor/Fusion/LICENSE                 # exactly 1 commit: never modified

git grep -l -iE 'scowl|Kevin Atkinson' HEAD --
git show HEAD:examples/gallery/examples/words/PROVENANCE.md | grep -n 'Copyright\|^##\|^```'
git show HEAD:examples/gallery/examples/words/PROVENANCE.md | sed -n '85,110p'   # opening notice
git show HEAD:examples/gallery/examples/words/PROVENANCE.md | sed -n '260,285p'  # UKACD clause
git grep -nE '[0-9a-f]{64}' HEAD -- examples/gallery/examples/words/PROVENANCE.md tools/build_word_lists.py

git grep -n -F 'Facet Wordle' HEAD --
git ls-tree -r -l HEAD -- docs/plans/reference-media
git ls-tree -r -l HEAD -- docs/plans/reference-media | grep -E '/(f1|r1|r2|r3)-' \
 | awk '{s+=$4;n++} END{printf "%d files, %d bytes\n", n, s}'    # 11 files, 6,202,133 bytes
```

## 8. Bulk

```sh
git rev-list --all --objects \
 | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(objectsize:disk) %(rest)' \
 > $SP/disk.txt

# Bytes by top-level path, deduped by blob SHA
awk '$2=="blob"{sha=$1;sz=$3;dk=$4;p="";for(i=5;i<=NF;i++)p=p (i>5?" ":"") $i;
     if(!(s[sha]++)){split(p,a,"/");t=a[1];D[t]+=dk;S[t]+=sz;N[t]++}}
     END{for(t in D) printf "%14.2f MB disk %10.1f MB raw %6d blobs  %s\n", D[t]/1048576, S[t]/1048576, N[t], t}' \
 $SP/disk.txt | sort -rn

# Every blob >= 1 MB, grouped by path with a revision count
awk '$3>=1048576 {sha=$1;p="";for(i=4;i<=NF;i++)p=p (i>4?" ":"") $i;
     if(!(s[sha]++)) printf "%d %s %s\n", $3, substr(sha,1,8), p}' $SP/blobs.txt | sort -rn > $SP/big.txt
wc -l < $SP/big.txt        # 523
awk '{p=$3;for(i=4;i<=NF;i++)p=p" "$i; c[p]++; b[p]+=$1}
     END{for(k in c) printf "%12d %4d %s\n", b[k], c[k], k}' $SP/big.txt | sort -rn

# Generated files: tracked at tip, and ever tracked
git ls-tree -r --name-only HEAD | grep -iE '\.(rbxl|rbxm|rbxlx|lock|pyc)$|sourcemap\.json|__pycache__|\.DS_Store'
awk '{p="";for(i=4;i<=NF;i++)p=p (i>4?" ":"") $i; print p}' $SP/blobs.txt \
 | grep -iE '(^|/)(build|node_modules|__pycache__)/|\.DS_Store$|sourcemap\.json$|\.lock$|\.pyc$|suite_cache' \
 | sort | uniq -c | sort -rn
```

### The three pack-size estimates

`git pack-objects --stdout` writes the pack to stdout and never touches the repository.

```sh
# (a) everything, as a fresh clone would receive it -> 217,735,168 bytes = 207.65 MB
git rev-list --all --objects | awk '{print $1}' > $SP/all_sha.txt      # 15,413 lines
git pack-objects --stdout < $SP/all_sha.txt | wc -c

# (b) removed from tip only -> unchanged. Not measured: a `git rm` adds one commit and leaves
#     every place blob reachable from its original commit, so the object set is the same.

# (c) purged from history -> 29,588,785 bytes = 28.22 MB
awk '$2=="blob"{p="";for(i=5;i<=NF;i++)p=p (i>5?" ":"") $i;
     if(p ~ /^examples\/places\/.*\.rbxl$/) print $1}' $SP/disk.txt | sort -u > $SP/exclude_rbxl.txt
wc -l < $SP/exclude_rbxl.txt                                            # 530 blobs
grep -vxFf $SP/exclude_rbxl.txt $SP/all_sha.txt > $SP/sha_no_rbxl.txt   # 14,883 objects
git pack-objects --stdout < $SP/sha_no_rbxl.txt | wc -c
```

## 9. Remote-visible surfaces

```sh
# The local tag: does it point inside main's history?
git merge-base --is-ancestor f1f0454 HEAD && echo ancestor || echo "NOT an ancestor"
git log -1 --format='%h %ad %s' --date=short f1f0454      # "WIP on main: aeffc68 ..." = a stash
git rev-list --objects f1f0454 --not main | wc -l         # 58 objects unique to the tag
git rev-list --objects f1f0454 --not main | awk 'NF>1{$1="";print}' | sed 's/^ //' | sort -u

# Unreachable / reflog-only work (local only; GitHub serves only pushed refs)
git fsck --unreachable --no-progress | awk '{print $2}' | sort | uniq -c
git reflog --all --format='%H' | sort -u > /tmp/rl.txt
git rev-list --all          | sort -u > /tmp/rr.txt
comm -23 /tmp/rl.txt /tmp/rr.txt | wc -l                  # 16

# Internal writing at tip
for d in .superpowers docs/plans docs/research docs/handoff artifacts; do
  echo "$d: $(git ls-tree -r --name-only HEAD -- "$d" | wc -l) files, \
$(git ls-tree -r -l HEAD -- "$d" | awk '{s+=$4} END{printf "%.2f MB", s/1048576}')"
done
git cat-file -s HEAD:ui_todo.md
```

## Notes on method

- **`git log -p` over 1,094 commits was deliberately avoided.** Blob-level scanning covers exactly
  the same content once per unique blob instead of once per commit-touch, so the secrets and
  personal-data passes each read 397.2 MB rather than tens of gigabytes.
- **`git grep <pat> $(git rev-list --all)` was used only for path attribution on a bounded commit
  range**, never for the primary scan — it re-reads trees per commit and does not scale here.
- **Binary blobs were scanned separately.** `.rbxl` is LZ4-chunk-compressed, so a `strings` pass
  finds strings in uncompressed regions but cannot prove a negative about compressed ones. That
  limitation is why `provenance-ledger.md` item 23 is marked `[VERIFY]`.
- **Two scratch Python helpers** (`binattrib.py` for per-blob literal attribution, and an earlier
  `scan2.py` for regex attribution) were written to the session scratch directory outside the
  repository. Neither is needed to reproduce the results above; the shell commands are sufficient.
- **Nothing in the repository was modified.** `git status --porcelain` before and after shows the
  same two owner-modified files plus the new untracked `artifacts/distribution-readiness/`.
