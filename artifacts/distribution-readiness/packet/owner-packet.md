# Owner release packet — Facet distribution readiness

**Status: ANSWERED 2026-08-31 — the owner confirmed all 11 rows** (1 confirmed
copyright line as written; 2 rename approved and EXECUTED, see
`../rename-record.md`; 3–7 confirmed; 8–9 recommendations adopted: places stay
at the tip, history rewrite candidate **B**; 10 rewrite/contact e-mail =
`facetframework@gmail.com`; 11 acknowledged). Final numbers stamped at close.
Beyond the rename, nothing remote has been touched: no push, no asset creation,
no visibility change. The repository is exactly as private as it was.

This packet is the one batch of decisions the plan reserves for you. Everything
else is done or blocked only on these.

## 1. What you are approving (the checkpoint, in plain words)

| # | Decision | The candidate answer awaiting your yes |
|---|---|---|
| 1 | **Copyright line** for the MIT `LICENSE` | `Copyright (c) 2026 Josh Anon` (your commit display name; never inferred as a legal identity — say the exact line you want) |
| 2 | **Rename** `github.com/josha/LuauUI` → `github.com/josha/Facet` | Yes, via Settings → Repository name (or `gh api -X PATCH repos/josha/LuauUI -f name=Facet`); target verified available; redirect verified after; rollback = rename back (loses the new-name redirect) |
| 3 | **Package creator** | Your Roblox **user** account `1364639953` (the one the icon uploads used) — or a group id instead; ownership is irreversible either way ("Ownership transfers are not supported") |
| 4 | **Package name + description** | Name `Facet`; description in `package/facet-package.json` (one honest paragraph: MIT, source link, what it is) |
| 5 | **Private creation now, free Creator Store listing later** | Create private now; the listing waits for the ordered checklist after the repo is public |
| 6 | **Credential** | `ROBLOX_API_KEY` env var, Assets API read+write, IP-allowlisted; never a cookie, never stored in the repo |
| 7 | **Publish route** | `studio` (default) until the spike proves the API route: Roblox documents `.rbxm` content updates as unsupported over Open Cloud |
| 8 | **The 14 tracked `.rbxl` place files** (~44 MB at tip; ~52 MB of history) | Recommended: keep at tip, purge historical revisions only if you take candidate B (below) |
| 9 | **History rewrite** — pick one | **A** (required minimum): purge the 15 must-purge files; public clone ≈ 81 MB. **B** (recommended): A + place-file history + author-email rewrite + `.rbxl.lock`/`.pyc`/game-parity docs; public clone ≈ 23 MB. **Neither** blocks going public — the plan forbids it while must-purge items exist |
| 10 | **Author e-mail on 1,113 rewritten commits** (candidate B only) | `facetframework@gmail.com` (owner-confirmed) |
| 11 | **Old revisions of the platform-comparison document stay in Git history** | Acknowledged (product research, not sensitive; a later purge would be a separate destructive decision) |

## 2. Why a history rewrite is on the table at all

The full-history audit (`audit/history-audit.md`) found **zero secrets and zero
private place/universe ids** anywhere in 1,100+ commits — but **15 files that
must be purged before the repo can go public**: 11 screenshots/recordings of the
official Roblox mobile app (another company's UI, no licence to redistribute)
and 4 checked-in Rascal Rally test transcripts carrying unreleased character
codenames and economy rules. They are already **off the tip and preserved in the
private archive**; only a rewrite removes them from history.

Both rewrite candidates are **built and verified** on mirror clones
(`audit/history-candidate.md`): every purged path proven absent by blob SHA,
commit counts intact, tree diff exactly the removed paths, a fresh clone of A
runs the test suite. The migration is: archive the pre-rewrite mirror
off-Dropbox → force-push the chosen candidate → re-clone locally → verify on
GitHub → (optionally) ask GitHub Support to drop retained unreachable objects.
Rollback = force-push the mirror back. **The rewrite must be re-run on the final
commit** — the built candidates are the rehearsal that proves the procedure.

## 3. What changed while the repo stayed private (all local, all committed)

- **Fusion excised** (your correction, executed): `vendor/Fusion`, the adapter,
  both comparison documents and the bake-off evidence live only in the private
  archive; `src/core/` ships the custom core alone; `tools/check_no_fusion.py`
  scans sources, the built model, examples, skills and Rascal Rally — proven to
  bite on planted violations.
- **Everything internal archived**: plans, handoffs, research, decision records
  (your ruling), lessons, stage artifacts, probes, the retired gate manifest —
  **772 files, checksummed** (`tools/archive_private.py verify` OK) at
  `GameStudio/ui/Facet-private-archive/`, then removed from the tip.
  Tracked files: 1,788 → **1,181**. No public file cites an internal record.
- **Public docs stand alone**: MIT LICENSE (line pending #1), third-party
  notices, changelog, contributing (with the versioning/deprecation policy
  folded in), security policy, rewritten README, the guide + API + constitution
  + maintainer map + extension playbooks, root `AGENTS.md`, and a thin
  `skills/use-facet/SKILL.md`. One public comparison chapter
  (`docs/guide/14-choosing-a-ui-library.md`) — pinned primary sources, labeled
  facts vs. inference, no popularity or speed claims, Facet's own core stated
  plainly.
- **A standalone consumer** (`examples/consumer/`) proves mount, theme, input,
  adaptation, preferred text and teardown through public API alone.
- **Package channel built, never used**: one extended model builder emits the
  library with `Version`/`SourceCommit`/`SourceHash` metadata and license text
  inside the artifact; byte-deterministic builds; a semantic manifest; a
  packaged-consumer canary that drives a real screen through the **built**
  artifact; `tools/package.sh` with 18 refusal codes proven by 21 mutation
  cases; a protected `tools/release.sh` + manual-dispatch workflow. Create and
  publish refuse everything until #3–#7 are answered.
- **Verification rebuilt**: one coordinator (`tools/verify.sh`), 510 rows / 134
  producers from structured results with identity-keyed reuse and tamper
  detection; each producer runs once per identity; prior-gate replay retired;
  release tier **~9 minutes cold** on this machine against the 20-minute budget
  (final timing stamped at close). Coverage map proves no requirement lost its
  producer; mutation parity recorded, including one defect class only the new
  path catches.
- **Rascal Rally untouched at runtime**: comment-only edits; game suite green
  (3541/0); consumer-impact ledger records "no caller change".

## 4. Repository settings to apply after the rename (owner actions)

Description: "A declarative, testable UI library for Roblox, written in Luau."
Topics: `roblox`, `luau`, `ui`, `ui-framework`, `rojo`. Default branch `main`.
Enable private vulnerability reporting. Branch protection/rulesets become
available on the public repo — require PRs + green CI on `main`. Wiki stays
off; issues on.

## 5. The ordered checklist (nothing here happens without you)

1. Confirm rows 1–11 above (one message is enough).
2. **Rename** the repo; verify same repository id, redirect, `git remote
   set-url`; record before/after.
3. **Spike** (Studio + Open Cloud, throwaway private asset): does an Open
   Cloud-created Model carry a `PackageLink`? Does a `.rbxm` PATCH work? Does a
   Studio publish show in the versions API? Record; set `route` accordingly.
4. **Create** the one private Package (`tools/package.sh create --confirm`),
   record the asset id in `package/facet-package.json`.
5. **Prove** in a clean place: insert by id, `PackageLink`, version/tree/hash
   match, mount/theme/input/teardown; publish a second version to the same id;
   an unmodified opted-in copy updates, a modified copy is reported.
6. Later, at your pace: re-run the chosen history rewrite on the final commit →
   force-push → make the repository public → verify license detection + public
   CI → enable the free Creator Store listing → GitHub Release with the tagged
   source + `.rbxm` if wanted.

## 6. Evidence index (all in this directory or the archive)

`freeze/` (state at open) · `audit/` (history audit, bulk, provenance,
candidates, migration/rollback) · `research/platform-sources.md` (every platform
fact, cited) · `fusion-excision.md` · `swiftui-migration.md` +
`swiftui-archive-receipt.md` · `decision-internalization.md` ·
`verification/` (census, coverage map, parity, timings) · `package-channel.md` ·
`docs-refresh.md` · `rascalrally-consumer-impact.md` · the private archive's
`MANIFEST.json` + `SHA256SUMS`.

*To be stamped at close: final release-tier verdict counts and timings, the
candidate commit id, reproducibility checksums, fresh-clone and fresh-agent
results, red-team disposition, and the repository-size summary.*
