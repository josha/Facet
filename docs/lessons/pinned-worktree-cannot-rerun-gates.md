# A pinned worktree cannot re-run the gate battery

**Found:** 2026-08-02, roadmap Step 8 (`desktop-keyboard-navigation`), setting up
the stage-start prior-gates baseline.

## What happened

The recipe from Step 7 is "regenerate the baseline from a git worktree pinned to
the stage-start commit, so concurrent implementation edits cannot contaminate
it". Run that way, **all eighteen prior gates failed**, in a tree whose only
difference from the passing one was the checkout path.

Two independent causes, both environmental:

1. **Relative paths out of the library.** Several checks do
   `cd ../../../games/RascalRally/code`. A worktree at
   `/tmp/<anything>` resolves that to a directory that does not exist. A worktree
   only works if it sits at `<root>/GameStudio/ui/Facet` with a real (or
   symlinked) `<root>/games` beside it.
2. **`build/` is gitignored.** `tools/doctor.sh` builds the gallery place to
   `build/Facet-Gallery.rbxl`, and `rojo build` fails when the output directory
   does not exist. `doctor` is a check in most gates, so one missing empty
   directory reddened the whole battery. `mkdir -p build` fixes it.

## The part that does not have a fix

Fixing both still does not make a worktree a usable baseline, because
`.gitignore` excludes `artifacts/**/*.json` and `artifacts/**/*.png` — the
gate.json files, verifier verdicts, capture manifests and perf reports that many
checks *read*. A fresh worktree has none of them, so those checks cannot pass
there no matter what.

That matters more than it looks. The `prior-gates-unregressed` comparison is
`comm -23 <before-PASS> <after-PASS>` — "no gate that passed before may fail
now". With an all-FAIL baseline the before-set is empty, the comparison is
**vacuously green**, and the check proves nothing. It is the same
can't-ever-fail shape the 2026-07-29 gate-integrity sweep removed from seven
gates; producing it from a broken baseline would have put it straight back.

## The rule

**Use the previous stage's in-tree roll-up as the baseline, not a worktree run.**
`artifacts/<previous-stage>/prior-gates.txt` is checked in (it is a `.txt`, so
the artifact ignore rules do not touch it) and was regenerated in-tree at that
stage's final source — which *is* this stage's starting source. Step 8 compared
against `artifacts/api-architecture-consistency/prior-gates.txt` (15 PASS lines)
and regenerated the after-side in-tree at its own final source.

The contamination the worktree was meant to prevent is real, so keep the other
half of the Step 7 recipe: capture the *suite count* and the *public-surface
dump* from a pinned worktree (both are pure source reads and work fine there),
and take the gate roll-up from the previous stage's record.

If a baseline run ever reports every gate failing, do not diagnose the product
from it. Check `doctor` first — it names the environment, and it is what named
this one.
