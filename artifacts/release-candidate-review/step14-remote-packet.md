# Step 14 remote-change packet — GitHub repository rename (DRAFT, fills in at close-out)

Prepared by the release-candidate-review stage. This packet PREPARES the remote
rename; it performs no remote mutation. The rename itself is a Step 14
owner-checkpoint action (docs/plans/distribution-readiness.md).

## What the owner is approving

Rename the existing private repository `https://github.com/josha/LuauUI` to
`https://github.com/josha/Facet`. No visibility change, no publish, no history
rewrite, no second repository.

## Repository identity (read-only API, 2026-08-17)

Repository ID `1320732857` (node `R_kgDOTrjIuQ`), private, default branch `main`,
no Pages, no Actions workflows, wiki disabled. Post-rename step 1 must show this
same ID under the new name.

## Pre-mutation verification (state at packet time)

| Check | State | Evidence |
|---|---|---|
| Target `josha/Facet` available | AVAILABLE (404 on 2026-08-17) | artifacts/release-candidate-review/facet-collision-check.md |
| Collision/rights sweep | No blocking conflicts; one dormant same-ecosystem Wally package (`emdomanus/facet`) flagged for owner review | same file |
| Local drift gate (old-name negative controls) | GREEN 2026-08-17: full scan PASS + selftest PASS (planted content, planted path, out-of-scope allowlist pattern each caught) | rename/drift-guard-proof.md |
| Local tree canonical Facet | current-source old-name matches 205, every one reasoned + allowlisted; generated-output 0 | rename/after-inventory.md |
| Recoverable local mirror exists | CREATE AT CHECKPOINT (repo .git is 428MB; avoid a standing Dropbox duplicate): `git clone --mirror https://github.com/josha/LuauUI.git /tmp/Facet-premutation-mirror.git && git -C /tmp/Facet-premutation-mirror.git fetch --all` then archive it off-Dropbox before renaming | this packet |
| Admin authority on the repo | `gh auth status` shows account `josha` (keyring) on this machine; owner confirms at checkpoint | — |
| GitHub Pages on this repo | NONE — `has_pages: false` (read-only API, 2026-08-17) | — |
| Actions hosted by this repo referenced elsewhere | NONE — 0 workflows (`/actions/workflows` total_count 0); nothing external can reference an Action here | — |

## The exact mutation (owner performs, or authorizes in one guarded step)

1. GitHub → josha/LuauUI → Settings → General → Repository name → `Facet` → Rename.
   (API alternative: `gh api -X PATCH repos/josha/LuauUI -f name=Facet`.)

## Post-mutation verification checklist

1. `gh repo view josha/Facet --json name,visibility,defaultBranchRef,id` — same
   repository ID as recorded pre-mutation; visibility unchanged (private).
2. Redirect: `git ls-remote` against the pre-rename URL still answers
   (GitHub redirect) — record; do NOT rely on it long-term and never reuse the old
   name later (reuse kills the redirect).
3. Local remote update, both checkouts if any:
   `git -C GameStudio/ui/Facet remote set-url origin https://github.com/josha/Facet.git`
   then `git fetch origin && git status` (no push).
4. Branches/tags/issues/stars/Actions history intact per Settings + `gh api`.
5. Update every current link to the URL: the drift guard proves the maintained trees
   carry the pre-rename URL nowhere outside this packet, so the only links to touch
   are `git remote set-url` (step 3) and this packet's own tables.
6. Record before/after state in the release receipt.

## Rollback

Renaming back restores the old name (GitHub permits rename-back; doing so removes
the new-name redirect). Rollback = Settings → rename to `LuauUI`, re-run step 3
with the old URL. The local mirror from the pre-mutation table is the disaster copy.

## Explicitly out of scope here

Visibility change, Creator Store listing, Package creation, pushes, releases —
all remain later Step 14 owner actions with their own checkpoints.
