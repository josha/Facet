# Facet — full-history distribution audit

**Repo:** `GameStudio/ui/Facet` · **HEAD:** `27c0afd` · **Audit date:** 2026-08-30
**Remote:** `github.com/josha/LuauUI.git` (private, to be renamed `josha/Facet` and made public)

## Refs and objects covered

Every scan below ran over **all reachable objects from every ref**, not just the tip:

| What | Value | How |
|---|---|---|
| Refs covered | `refs/heads/main`, `refs/remotes/origin/main`, `refs/remotes/origin/HEAD`, `refs/tags/luauui-step8-baseline` | `git for-each-ref` |
| Objects enumerated | 15,393 | `git rev-list --all --objects` |
| Unique blobs | 7,699 (7,026 text + 673 binary) | `git cat-file --batch-check` |
| Raw blob bytes scanned | 1,570.5 MB (397.2 MB text + 1,173.3 MB binary) | — |
| Commits on `main` | 1,094 | `git rev-list main --count` |
| Commits across all refs | 1,097 (1,094 + 3 `git stash` commits under the local tag) | `git rev-list --all --count` |
| Commit authors | 2: `Josh Anon <josha@Joshs-Mac-mini.local>` and `git stash <git@stash>` | `git log --all --format='%an <%ae>'` |

**Not covered, deliberately:** 72 unreachable commits / 118 unreachable blobs / 16 reflog-only commits.
These are local-only. `origin/main == main == 27c0afd` and GitHub exposes only pushed refs, so
they cannot be reached by anyone cloning the public repo. See RMT-02.

**Working-tree diff ignored** as instructed: `docs/plans/distribution-readiness.md` and
`docs/plans/facet-consolidated-roadmap.md` are modified-uncommitted; only committed content was audited.

> ## Audit baseline, and drift during the audit
>
> **This audit was run against `27c0afd`, which is exactly `origin/main` — the commit the
> private GitHub repo actually holds.** That is the right baseline for the question "what gets
> exposed when this goes public," because nothing else has been pushed.
>
> While the audit was running, the owner committed **11 further commits** locally
> (`27c0afd..17ae422`), none of them pushed. Two of them change conclusions here, and both are
> re-verified below:
>
> | Change at the newer local HEAD | Effect on this audit |
> |---|---|
> | A root `LICENSE` (MIT, `Copyright (c) 2026 Josh Anon`) and a 15,410-byte `THIRD_PARTY_NOTICES.md` were added | **RGT-10 is resolved** at `17ae422`. The new notices file covers Facet's own art, SCOWL (full verbatim block, UKACD clause included), and the toolchain. It has no Fusion section, consistent with `vendor/Fusion/` being deleted in the working tree |
> | `vendor/Fusion/`, `docs/reference/react-lua-comparison.md` and `docs/reference/fusion-comparison.md` are deleted in the working tree | Confirms RGT-01's "drop it" branch is the one being taken |
>
> **The 15 must-purge files are still present at `17ae422`** — re-checked file by file. Nothing in
> the new commits addresses them, and because they are in history, no future commit can.

---

## 1. Secrets and credentials

No credential value of any kind exists anywhere in reachable history. The scan streamed all
7,026 text blobs and all 673 binary blobs through the pattern set below.

| ID | Path / pattern | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| SEC-01 | `ghp_`/`gho_`/`ghu_`/`ghs_`/`github_pat_`/`AIza…`/`sk-…`/`AKIA…`/`xox[baprs]-`/`Bearer <25+>`/`-----BEGIN … PRIVATE KEY`/`hooks.slack.com/services`/`discord*.com/api/webhooks` | **0 matches**, all text blobs, all refs | `safe-public-history` | Nothing matched any high-entropy credential shape | None |
| SEC-02 | `.ROBLOSECURITY` | **0 matches**, text *and* binary blobs | `safe-public-history` | No session cookie ever committed | None |
| SEC-03 | `tools/upload_icons.py` | tip + history (`6a4b59c`→HEAD) | `safe-public-history` | Reads `ROBLOX_API_KEY` from the environment, falling back to `GameStudio/tools/API_KEYS.txt` — a path **two levels above the repo root**, never tracked here. No key value in the file | Optional: make it env-only, since `REPO.parent.parent/tools/API_KEYS.txt` cannot resolve in a public clone and discloses the studio layout |
| SEC-04 | `docs/plans/compact-label.md`, `docs/plans/row-actions-hosted-mode-plan.md` | tip + history | `safe-public-history` | `x-api-key: <key with scope …>` and `x-api-key: <same>` are documentation **placeholders**, not values. Files are internal plans — see RMT-03 | None for secrecy |
| SEC-05 | `.env`, `API_KEYS.txt`, `*.pem`, `*.key` as tracked files | **never tracked**, any ref | `safe-public-history` | No credential file ever entered the index. (6,169 `.env` hits are the Luau property access `.env`, not dotenv files) | None |

## 2. Personal and machine data

| ID | Path / pattern | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| PER-01 | `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/…` | **tip** (20 files, 1,051 lines) + history (~1,076 blob matches). First `6a4b59c`, last HEAD | `remove-from-tip-keep-history` | Absolute home paths in captured logs and plans. Discloses the OS username (already public as the GitHub owner), the Dropbox layout, and the private game's directory name. Concentrated in `artifacts/`, `docs/plans/`, `docs/research/` | Scrub or relativise at tip; history retention is low-risk since `josha` is the public account name |
| PER-02 | `examples/places/LuauUI-Showcase.rbxl.lock` | **history only** — added `a42ef97`, untracked `51ff4a1`. 2 blobs | `owner-decision` | Studio lock file containing hostname `Joshs-Mac-mini.local`, a PID, and two machine/session UUIDs (`DA11…`, `8C30…`) | Already gone from tip. Cheapest purge in the repo (2 blobs) if the hostname is to go |
| PER-03 | Commit author + committer email `josha@Joshs-Mac-mini.local` | **all 1,094 commits on `main`** | `owner-decision` | The address embeds the machine hostname. **Removing it means rewriting every one of the 1,094 commits** — every commit SHA changes, and the rewritten history must be force-pushed before the repo is made public | Decide before publishing: rewrite now (remote is still private, so no exposure) or accept the hostname |
| PER-04 | `assets/themes/{glossy-touch,fantasy-parchment}/source/__pycache__/generate_art.cpython-314.pyc` | **history only** — added `6a4b59c`, removed `664d974`. 2 blobs | `owner-decision` | Python bytecode embeds the absolute compile-time source path, including `/Users/josha/…/UntitledRacingGame/GameStudio/ui/LuauUI/…` | Already gone from tip; purge alongside PER-02 if scrubbing paths from history |
| PER-05 | `/private/tmp/claude-501…` agent scratchpad paths | **tip** (2 files: `artifacts/rulings-1-and-5/…`, `.superpowers/sdd/…`) + history | `remove-from-tip-keep-history` | Machine-local temp paths from agent sessions; internal noise, not sensitive | Scrub at tip |
| PER-06 | `biljir@pobox.com`, `ross@bryson.demon.co.uk`, `Brian.Kelk@cl.cam.ac.uk`, `grady@northcoast.com`, `grady@netcom.com`, `thegrendel@theriver.com` | tip, inside `examples/gallery/examples/words/PROVENANCE.md` | `safe-public-history` | Third-party contributor addresses **inside the SCOWL copyright notice**, which the licence requires be reproduced verbatim. Removing them would breach the licence | Keep verbatim |
| PER-07 | `no-reply@roblox.com` (9) | tip + history | `safe-public-history` | Roblox boilerplate quoted in docs | None |
| PER-08 | `127.0.0.1` (56), `8.8.8.8` (18), `1.1.1.1` (18), `151.0.0.0` (38) | tip + history | `safe-public-history` | Localhost in tooling; public DNS resolvers cited in `docs/reference/react-lua-comparison.md`. `151.0.0.0` is a **Chrome version string**, not an IP — a regex false positive | None |

## 3. Private Roblox identifiers

| ID | Path / pattern | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| RBX-01 | Private place/universe ids `110532093445029`, `10429557340` | **0 matches** — text blobs *and* raw bytes of all 530 `.rbxl` blobs; `git log --all -S` returns 0 commits for each | `safe-public-history` | Neither private id was ever committed, at tip or in history, in source or inside a place binary | None. This is the strongest negative result in the audit |
| RBX-02 | Creator user id `1364639953` — `tools/upload_icons.py:53`, `docs/plans/compact-label.md:248`, `artifacts/row-actions/rr-compat.md:268` | tip + history | `safe-public-history` | A Roblox **public profile id**, visible on any asset the account has published. Not a secret | None (it is already the public creator of the uploaded icon assets) |
| RBX-03 | `rbxassetid://…` content ids in `src/`, `examples/`, `assets/` | tip + history | `safe-public-history` | Every id traces to the project's own Open Cloud uploads recorded in `assets/icons/upload-manifest.json` and `assets/themes/*/upload-manifest.json`. Remaining ids (`1`, `0`, `999999999999999`) are test sentinels | None |
| RBX-04 | `(place|universe|game)_?id = <9–16 digits>` | **0 matches at tip** | `safe-public-history` | No hardcoded place/universe id assignment anywhere | None |

## 4. Rascal Rally and other private projects

The private kart racer leaked as **prose and captured output**, never as source. Zero
`games/RascalRally` diff hunks exist in history; zero files matching game keywords were ever deleted.

| ID | Path | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| PRJ-01 | `artifacts/api-architecture-consistency/game-suite.txt` (293 KB), `artifacts/example-games-and-standalones/test-optimization/rr-suite-before.txt` (352 KB), `…/rr-suite-after.txt` (352 KB), `artifacts/release-candidate-review/baseline/suite-rr.txt` (331 KB) | **tip** + history. First `cf57c25`/`73c9b75`/`3411e07`/`230f864`, each a single-commit add | **`must-purge-before-public`** | Verbatim stdout of the **private game's own test suite**, checked in as evidence. Each file carries 7 hits for six unreleased character/driver codenames, plus internal system names (`KartBodyFeel`, `FarAILod`, `GearDockModel`) and plain-English economy/balance rules | Purge from history. They are captured evidence, not functional inputs — deletable outright or regenerable |
| PRJ-02 | `docs/reference/sponsor-view-parity.md` | tip + history. First `6a4b59c`, last `1482571` | `owner-decision` | ~480-line engineering description of the private game's real Sponsor screen: module names, exact usage counts, real constants, mechanic detail. No code copied | Decide whether an internal parity study ships publicly at all |
| PRJ-03 | `.superpowers/sdd/**` (34 files, 0.98 MB at tip), `artifacts/parallel-sponsor/**`, `artifacts/sponsor-framework-gaps/**` | tip + history (116 commits touch `.superpowers/`) | `remove-from-tip-keep-history` | Internal agent briefs and review verdicts that describe the private game's architecture at length; 144 files cite `games/RascalRally` paths | Drop from the public tip |
| PRJ-04 | ~24 `src/**` files with comments naming `games/RascalRally/code/src/client/FacetSponsor/…` (43 `RascalRally` + 11 `Rascal Rally` occurrences in `src/` at tip; 18 more in `examples/`) | tip + history | `remove-from-tip-keep-history` | Shipped source comments name private internal files and disclose that Facet's default spring-motion constants were promoted from the game's motion spec | Reword the comments to be game-agnostic |
| PRJ-05 | `examples/places/*.rbxl` — all 530 blobs, 14 at tip | tip + history | `remove-from-tip-keep-history` | The places embed the compiled Luau source **including its comments**, so every place binary carries 152–605 `RascalRally` and 25–82 `Rascal Rally` strings. No place ids, paths, or hostnames in the binaries | Fixed downstream of PRJ-04 plus a rebuild; purging the name from history requires purging these binaries too |
| PRJ-06 | Commit subjects `d00ce21` ("…Rascal Rally rows"), `fff48b2` ("RascalRally compatibility evidence") | history | `owner-decision` | Commit messages are fully visible on a public repo. Rewording requires a history rewrite | Fold into the PER-03 rewrite decision if one happens |
| PRJ-07 | Literal game source, place ids, game art/branding | **0 matches** | `safe-public-history` | No `a/games/RascalRally` or `b/games/RascalRally` diff header anywhere; no game assets; no deleted game-keyword files | None |

## 5. Rights and provenance

Full detail in `provenance-ledger.md`; required text in `THIRD_PARTY_NOTICES.draft.md`.

| ID | Path | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| RGT-01 | `vendor/Fusion/` (69 files) | tip + history, `6a4b59c`→HEAD | `safe-public-history` | MIT, `Copyright (c) 2024 Daniel P H Fox`, upstream tag `v0.3-beta`. `LICENSE` has exactly one commit and was never modified. Local patches are mechanical (`require` form) | Keep `LICENSE` beside the code and add the notice; or drop `vendor/` per the existing plan |
| RGT-02 | `assets/icons/` | tip | `safe-public-history` | Original, script-generated (`generate_icons.py`, Pillow). Provenance explicitly rejects SF Symbols and AI generation | None |
| RGT-03 | `assets/themes/{compact-pointer,fantasy-ornate,fantasy-parchment,glossy-touch,ornate-gauge,pixel-quest}/` | tip | `safe-public-history` | All six procedurally generated by in-repo `generate_art.py` from recorded seeds; no external imagery | None |
| RGT-04 | `examples/gallery/examples/words/**` (SCOWL-derived) | tip | `safe-public-history` | Derived from SCOWL 2020.12.07 (SHA-256 pinned in both `PROVENANCE.md:14` and `tools/build_word_lists.py:72`). **The required notice is already present verbatim**, `PROVENANCE.md` lines 92–341. The archive itself is gitignored | Mirror the notice into a root `THIRD_PARTY_NOTICES.md`; never truncate the UKACD clause |
| RGT-05 | Fonts | tip | `safe-public-history` | No font file in the repo; fonts referenced as `rbxasset://fonts/families/*.json`, i.e. the Roblox client's own catalog | None |
| RGT-06 | `examples/gallery/examples/05_word_game.luau:721` — displayed string `"Facet Wordle"` | tip + history | `remove-from-tip-keep-history` | "Wordle" is a live NYT trademark, and this uses it as a **product name for Facet's own screen**, not as comparison. Also pinned in `tools/lune/check_flat_baseline.luau` (3 lines) | Rename the on-screen string and re-pin the baseline |
| RGT-07 | `docs/plans/reference-media/2026-08-16-roblox-app-navigation/` — `f1-avatar-editor.jpeg`, `r1-a-closed-trigger.png`, `r1-b-menu-open-sheet.png`, `r1-c-content-changed.png`, `r1-popup-list.mov`, `r2-a-tab-for-you.png`, `r2-b-tab-charts-loading.png`, `r2-top-tab-bar.mov`, `r3-a-segment-middle.png`, `r3-b-segment-left-content-swapped.png`, `r3-segmented-control.mov` (11 files, 5.91 MB) | **tip** + history. Added `e5973f9` (single commit) | **`must-purge-before-public`** | Screen captures of the **official Roblox mobile app** — third-party UI and trade dress, captured as UX reference. No licence permits redistributing them. Not a notice problem; there is no notice that fixes it | Purge from history. The four `hud-*` files in the same directory are Facet's own captures and are fine |
| RGT-08 | `docs/reference/swiftui-parity.md` and the SW-### citation apparatus | tip | `safe-public-history` | Short, attributed, linked, dated quotations of Apple docs/HIG for comparative purposes; no code fences, no bulk copying | None required (the existing plan removes the file anyway) |
| RGT-09 | `artifacts/swiftui-reference-app-validation/` | tip | `safe-public-history` | Clean-room behavioral notes; `sources.md` states the IP boundary and no Apple sample archive or `.swift` sample was ever committed | None |
| RGT-10 | **No root `LICENSE` file** | absent at `27c0afd`; **added at `17ae422`** | `owner-decision` | At the audited baseline the repo shipped no licence text, so a public clone would have granted no rights. **Resolved after the audit began**: `LICENSE` (MIT, `Copyright (c) 2026 Josh Anon`) and a 15,410-byte `THIRD_PARTY_NOTICES.md` now exist locally, unpushed | None outstanding, provided those two commits are pushed before the repo is made public |
| RGT-11 | `examples/places/*.rbxl` — third-party embedded assets | tip | `owner-decision` | Built by `rojo build` from audited source, so references *should* be a subset of RGT-02/03. `.rbxl` is LZ4-chunked, so a `strings` pass cannot prove it. `[VERIFY]` | Confirm by diffing a fresh `rojo build` against each tracked binary |

## 6. Bulk

Full tables and the three pack estimates in `bulk.md`.

| ID | Path | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| BLK-01 | `examples/places/*.rbxl` — 530 blobs across history, 14 at tip | tip + history | `owner-decision` | **179.4 MB of the 207.65 MB a clone downloads (86.4%)**. 1,161.7 MB raw. Up to 43 revisions of a single place file | Decide: keep, drop from tip, or purge. Purging takes the repo to 28.22 MB |
| BLK-02 | Generated files tracked at tip | tip | `safe-public-history` | Only the 14 `.rbxl` places. **No** `.DS_Store`, `sourcemap.json`, `build/`, `__pycache__/`, `*.lock`, `*.pyc`, or `node_modules` at tip — `.gitignore` covers all of them | None |
| BLK-03 | Noise tracked *historically* only | history | see PER-02, PER-04 | 2 `.rbxl.lock` blobs and 2 `.pyc` blobs; both classes already untracked | Covered above |

## 7. Remote-visible surfaces beyond code

| ID | Item | Where | Class | Reason | Action |
|---|---|---|---|---|---|
| RMT-01 | Local tag `luauui-step8-baseline` → `f1f0454` | local only; **0 remote tags** | `owner-decision` | The tag points at a `git stash` commit ("WIP on main: aeffc68 …") that is **not an ancestor of `main`**, and carries 58 objects `main` does not have (WIP copies of `docs/reference/*`, `docs/plans/*`, `artifacts/*`). Making a repo public does **not** push tags; only an explicit `git push --tags` / `--follow-tags` would expose it | Delete the local tag, or never push tags. If it is pushed, its 58 WIP objects join the public history |
| RMT-02 | 72 unreachable commits, 118 unreachable blobs, 16 reflog-only commits | local only | `safe-public-history` | `origin/main == main == 27c0afd`; GitHub serves only pushed refs, and the reflog is never pushed | None |
| RMT-03 | Internal writing at tip: `artifacts/` (437 files, 15.08 MB), `docs/plans/` (70 files, 8.01 MB), `.superpowers/` (34 files, 0.98 MB), `docs/research/` (16 files), `docs/handoff/` (12 files), `ui_todo.md` (22 KB) | tip + history | `remove-from-tip-keep-history` | Agent prompts, review captures, director rulings, owed-work handoffs and personal decision notes. Not secret, but it is internal working material that reads as such and carries PER-01 and PRJ-03 | Choose a public allowlist for the tip |

---

## Summary

### Findings per class

| Class | Findings | Note |
|---|---|---|
| `safe-public-history` | 22 | Includes the two strongest negatives: zero credentials and zero private place/universe ids |
| `remove-from-tip-keep-history` | 7 | Internal writing, absolute paths, game-name comments, the trademark string |
| `owner-decision` | 10 | Author email, hostname blobs, the local tag, the 180 MB of places, the parity doc. Includes RGT-10, which the owner resolved mid-audit |
| `must-purge-before-public` | 2 findings / **15 files** | RGT-07 (11 files) and PRJ-01 (4 files) |
| **Total** | **41** | |

Counts are generated from `findings.json` and match it exactly. "Findings" counts entries, not
files: the two `must-purge-before-public` findings cover 15 tracked files between them.

### MUST-PURGE ITEMS: 15

Eleven files under `docs/plans/reference-media/2026-08-16-roblox-app-navigation/` — captures of the
official Roblox mobile app, with no licence to redistribute (RGT-07):

1. `f1-avatar-editor.jpeg`
2. `r1-a-closed-trigger.png`
3. `r1-b-menu-open-sheet.png`
4. `r1-c-content-changed.png`
5. `r1-popup-list.mov`
6. `r2-a-tab-for-you.png`
7. `r2-b-tab-charts-loading.png`
8. `r2-top-tab-bar.mov`
9. `r3-a-segment-middle.png`
10. `r3-b-segment-left-content-swapped.png`
11. `r3-segmented-control.mov`

Four files carrying the private game's unreleased character codenames and balance rules (PRJ-01):

12. `artifacts/api-architecture-consistency/game-suite.txt`
13. `artifacts/example-games-and-standalones/test-optimization/rr-suite-before.txt`
14. `artifacts/example-games-and-standalones/test-optimization/rr-suite-after.txt`
15. `artifacts/release-candidate-review/baseline/suite-rr.txt`

All 15 are tracked at `27c0afd` and would ship today. Because the remote is still private and
`origin/main == main`, a history rewrite now carries no exposure risk.

### The two decisions that dominate everything else

1. **Rewrite history or not.** The author email `josha@Joshs-Mac-mini.local` is on all 1,094
   commits; removing it rewrites every SHA. The 15 must-purge files, the two hostname/`.pyc` blob
   pairs, and the 180 MB of place binaries can all be purged in the *same* rewrite. If history is
   rewritten at all, do it once and do it for everything.
2. **Ship the 180 MB of places or not.** They are 86.4% of the clone and they are the only
   reason the repo is not a 28 MB download.

### No secret value appears anywhere in this audit's output

Nothing matched a credential pattern, so no redaction was needed. Every `x-api-key` occurrence in
the repo is a literal documentation placeholder (`<key with scope …>`, `<same>`) or a Python
variable, quoted here as-is because it contains no secret.
