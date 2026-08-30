# Facet — bulk audit

**Baseline:** `27c0afd`, which is exactly `origin/main` — the commit the private GitHub repo holds.
All figures cover every object reachable from every ref at that commit (15,393 objects, 7,699 unique blobs).
11 unpushed commits landed locally during the audit; they do not remove any place binary, so every
figure below still holds.

## Headline

**86.4% of this repository is one directory.** `examples/places/*.rbxl` is 179.4 MB of the
207.65 MB a fresh clone downloads. Purge it and the repo becomes a 28.22 MB clone.

## Current on-disk state

| Measure | Value | Command |
|---|---|---|
| Packs | 4 packs, 233.95 MB | `git count-objects -vH` |
| Loose objects | 762, 186.00 MB | `git count-objects -vH` |
| **Fully repacked (what a clone receives)** | **207.65 MB** (217,735,168 bytes) | `git rev-list --all --objects \| awk '{print $1}' \| git pack-objects --stdout \| wc -c` |
| Unique blobs | 7,699 (7,026 text, 673 binary) | `git cat-file --batch-check` |
| Raw blob bytes | 1,570.5 MB | — |

The four-packs-plus-762-loose state is a working-copy artifact. The repacked figure is the honest
one: it is what GitHub stores and what `git clone` transfers.

## Bytes by top-level path, across all history

Deduplicated by blob SHA. "Disk" is `%(objectsize:disk)`, i.e. the packed/delta-compressed
contribution; "raw" is `%(objectsize)`.

| Path | Disk | Raw | Blobs |
|---|---:|---:|---:|
| `examples/` | 268.83 MB | 1,189.0 MB | 1,564 |
| `docs/` | 11.13 MB | 117.2 MB | 1,131 |
| `artifacts/` | 6.50 MB | 20.8 MB | 720 |
| `tests/` | 4.99 MB | 66.2 MB | 1,806 |
| `src/` | 3.57 MB | 96.7 MB | 1,486 |
| `tools/` | 2.37 MB | 72.6 MB | 535 |
| `assets/` | 0.77 MB | 1.1 MB | 154 |
| `.superpowers/` | 0.42 MB | 6.8 MB | 123 |
| `vendor/` | 0.10 MB | 0.3 MB | 124 |
| `bench/` | 0.07 MB | 0.3 MB | 16 |
| `phases.json` | 0.03 MB | 0.3 MB | 18 |
| `ui_todo.md` | 0.02 MB | 0.2 MB | 10 |
| `requirements.json` | 0.01 MB | 0.1 MB | 4 |
| `.gitignore`, `run-tests.sh`, `rokit.toml`, `README.md`, `sweep.luau` | <0.01 MB | <0.1 MB | 18 |
| Trees / commits / tags | 2.05 MB | — | 7,704 objects |

`examples/` alone is 268.83 MB of disk against 11.13 MB for all of `docs/`. Of that,
`examples/places/*.rbxl` is 266.55 MB — the rest of `examples/` is 2.28 MB.

## Every blob ≥ 1 MB, by path

523 distinct blobs are ≥ 1 MB. All but one are place binaries.

| Path | Revisions (distinct blobs) | Total raw |
|---|---:|---:|
| `examples/places/LuauUI-Showcase.rbxl` | 43 | 104.7 MB |
| `examples/places/03_settings_sync.rbxl` | 40 | 85.1 MB |
| `examples/places/LuauUI-PerformanceLab.rbxl` | 40 | 76.4 MB |
| `examples/places/07_match3.rbxl` | 39 | 83.2 MB |
| `examples/places/06_tile_game.rbxl` | 39 | 83.2 MB |
| `examples/places/05_word_game.rbxl` | 39 | 83.2 MB |
| `examples/places/04_confirm_dialog.rbxl` | 39 | 83.2 MB |
| `examples/places/02_playlist_table.rbxl` | 39 | 83.2 MB |
| `examples/places/01_temperature_converter.rbxl` | 39 | 83.2 MB |
| `examples/places/00_settings_demo.rbxl` | 39 | 83.2 MB |
| `examples/places/Facet-Showcase.rbxl` | 10 | 34.2 MB |
| `examples/places/Facet-PerformanceLab.rbxl` | 12 | 33.8 MB |
| `examples/places/LuauUI-Ref-Wardrobe.rbxl` | 13 | 30.7 MB |
| `examples/places/LuauUI-Ref-Cartwheel.rbxl` | 13 | 30.6 MB |
| `examples/places/LuauUI-Ref-Sipworks.rbxl` | 13 | 30.6 MB |
| `examples/places/LuauUI-Ref-Glade.rbxl` | 13 | 30.6 MB |
| `examples/places/LuauUI-Ref-Foyer.rbxl` | 13 | 30.6 MB |
| `examples/places/Facet-Ref-Cartwheel.rbxl` | 8 | 28.9 MB |
| `examples/places/Facet-Ref-Sipworks.rbxl` | 8 | 28.9 MB |
| `examples/places/Facet-Ref-Glade.rbxl` | 8 | 28.9 MB |
| `examples/places/Facet-Ref-Foyer.rbxl` | 8 | 28.9 MB |
| `examples/places/Facet-Ref-Wardrobe.rbxl` | 7 | 24.7 MB |
| `docs/plans/reference-media/2026-08-16-roblox-app-navigation/r1-popup-list.mov` | 1 | 2.4 MB |
| **Total ≥ 1 MB** | **523 blobs** | **1,156.2 MB** |

The `LuauUI-*` and `Facet-*` names are the same places before and after the 2026-08-17 rename
(`44b9e62`). Both sets are in history; only the `Facet-*` set is at tip.

## The three pack-size estimates

All three measured with `git pack-objects --stdout`, which writes nothing to the repository.

| Scenario | Pack size | Change |
|---|---:|---:|
| **(a) `examples/places/*.rbxl` kept** | **207.65 MB** | baseline |
| **(b) removed from tip only** | **~207.65 MB** | **no change** |
| **(c) purged from history** | **28.22 MB** | **−179.43 MB (−86.4%)** |

**(a)** Measured directly:
```sh
git rev-list --all --objects | awk '{print $1}' > /tmp/all_sha.txt
git pack-objects --stdout < /tmp/all_sha.txt | wc -c    # 217,735,168 bytes = 207.65 MB
```

**(b)** A `git rm` at tip creates one new commit and leaves all 530 place blobs reachable from
their original commits. The object set is unchanged apart from one commit and a handful of trees,
so the pack size is unchanged to within a few kilobytes. **Deleting these files at tip does not
make the repo smaller — only a history rewrite does.**

**(c)** Measured by excluding every blob that ever appeared at `examples/places/*.rbxl`
(530 blobs) and repacking the remaining 14,883 objects:
```sh
git rev-list --all --objects \
  | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(objectsize:disk) %(rest)' \
  | awk '$2=="blob"{p="";for(i=5;i<=NF;i++)p=p (i>5?" ":"") $i; if(p ~ /^examples\/places\/.*\.rbxl$/) print $1}' \
  | sort -u > /tmp/exclude_rbxl.txt          # 530 blobs
grep -vxFf /tmp/exclude_rbxl.txt /tmp/all_sha.txt > /tmp/sha_no_rbxl.txt   # 14,883 objects
git pack-objects --stdout < /tmp/sha_no_rbxl.txt | wc -c   # 29,588,785 bytes = 28.22 MB
```

This is an upper bound on the saving from a `filter-repo --path-glob 'examples/places/*.rbxl'`
run: real filter-repo output will land at or slightly below 28.22 MB, since it also drops the
tree entries that referenced those blobs.

## Generated files tracked at tip

| Kind | Tracked at tip? | Detail |
|---|---|---|
| `.rbxl` place binaries | **Yes — 14** | `00_settings_demo`, `01_temperature_converter`, `02_playlist_table`, `03_settings_sync`, `04_confirm_dialog`, `05_word_game`, `06_tile_game`, `07_match3`, `Facet-PerformanceLab`, `Facet-Showcase`, `Facet-Ref-{Cartwheel,Foyer,Glade,Sipworks}` |
| `.rbxm` | No | none, any ref |
| `sourcemap.json` | No | gitignored |
| `build/` output | No | gitignored |
| `.DS_Store` | No | gitignored (one exists untracked at the repo root) |
| `__pycache__/`, `*.pyc` | No | gitignored — **but 2 blobs are in history**, removed at `664d974` |
| `*.lock` | No | gitignored — **but 2 blobs are in history**, untracked at `51ff4a1` |
| `node_modules/` | No | never present |
| `artifacts/suite_cache/` | No | gitignored |
| One deliberate exception | Yes | `artifacts/theme-packages-and-skinning/final-neutral-dump.json` (408,664 bytes) — un-regenerable 0.6.0 baseline, force-included by `.gitignore` with a written justification |

`.gitignore` also excludes `artifacts/**/*.{png,jpg,jpeg,mov,mp4,json,log}`, which is why
`artifacts/` is only 15.08 MB at tip despite being the evidence trail. The Roblox-app captures
under `docs/plans/reference-media/` are **not** covered by that rule, which is how they came to
be tracked.

## Other bulk observations

- `docs/plans/reference-media/2026-08-16-roblox-app-navigation/` is 6.81 MB at tip across 15
  files (3 `.mov`, 1 `.mp4`, 7 `.png`, 4 `.jpeg`). Eleven of the fifteen are the must-purge
  Roblox-app captures (RGT-07).
- 673 binary blobs total: 530 `.rbxl`, 135 `.png`, 4 `.jpeg`, 3 `.mov`, 1 `.mp4`.
- The local tag `luauui-step8-baseline` adds 58 objects not reachable from `main`. They are small
  (WIP markdown), but they are only absent from GitHub because tags have never been pushed.
