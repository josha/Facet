# Step 14 remote-change packet — GitHub repository rename (DRAFT, fills in at close-out)

Prepared by the release-candidate-review stage. This packet PREPARES the remote
rename; it performs no remote mutation. The rename itself is a Step 14
owner-checkpoint action (docs/plans/distribution-readiness.md).

## What the owner is approving

Rename the existing private repository `https://github.com/josha/LuauUI` to
`https://github.com/josha/Facet`. No visibility change, no publish, no history
rewrite, no second repository.

## Pre-mutation verification (state at packet time)

| Check | State | Evidence |
|---|---|---|
| Target `josha/Facet` available | AVAILABLE (404 on 2026-08-17) | artifacts/release-candidate-review/facet-collision-check.md |
| Collision/rights sweep | No blocking conflicts; one dormant same-ecosystem Wally package (`emdomanus/facet`) flagged for owner review | same file |
| Local drift gate (old-name negative controls) | «fill: green run id/commit» | rename/drift-guard-proof.md |
| Local tree canonical Facet | «fill: after-inventory counts» | rename/after-inventory.md |
| Recoverable local mirror exists | «fill: `git clone --mirror` path + verified fetch» | commands.md |
| Admin authority on the repo | OWNER CONFIRMS at checkpoint (agent cannot verify credentials) | — |
| GitHub Pages on this repo | «fill: none expected — verify in Settings» | — |
| Actions hosted by this repo referenced elsewhere | «fill: none expected — calls to an Action hosted by a renamed repo do NOT redirect» | — |

## The exact mutation (owner performs, or authorizes in one guarded step)

1. GitHub → josha/LuauUI → Settings → General → Repository name → `Facet` → Rename.
   (API alternative: `gh api -X PATCH repos/josha/LuauUI -f name=Facet`.)

## Post-mutation verification checklist

1. `gh repo view josha/Facet --json name,visibility,defaultBranchRef,id` — same
   repository ID as recorded pre-mutation; visibility unchanged (private).
2. Redirect: `git ls-remote https://github.com/josha/LuauUI.git` still answers
   (GitHub redirect) — record; do NOT rely on it long-term and never reuse the old
   name later (reuse kills the redirect).
3. Local remote update, both checkouts if any:
   `git -C GameStudio/ui/Facet remote set-url origin https://github.com/josha/Facet.git`
   then `git fetch origin && git status` (no push).
4. Branches/tags/issues/stars/Actions history intact per Settings + `gh api`.
5. Update every current link to the URL: «fill: link inventory — expected only the
   Step-14-prepared docs; the maintained tree reads the old URL only from this packet».
6. Record before/after state in the release receipt.

## Rollback

Renaming back restores the old name (GitHub permits rename-back; doing so removes
the new-name redirect). Rollback = Settings → rename to `LuauUI`, re-run step 3
with the old URL. The local mirror from the pre-mutation table is the disaster copy.

## Explicitly out of scope here

Visibility change, Creator Store listing, Package creation, pushes, releases —
all remain later Step 14 owner actions with their own checkpoints.
