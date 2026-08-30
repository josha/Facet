# Mutation parity — the old path and the new one go red together

Workstream T, D9. The new verification path may not retire the old one until a
corpus of deliberate defects has been SEEN to fail on both.

## How it was run

`python3 tools/lune/verify/mutation_parity.py --prepare` builds a frozen copy of
the working tree at `/tmp/facet-mutation-parity/GameStudio/ui/Facet`, laid out
with that path prefix and a `games` symlink beside it so
`../../../games/RascalRally/code` still resolves, then warms the result store
with one full run. `--run` then, for each mutation: takes a BASELINE on both
paths, applies the defect, runs both paths, restores, and records the four exit
codes.

  OLD path — `lune run tools/lune/gate_legacy <phase>` (the pre-conversion gate,
             running that phase's rows out of `tools/lune/gate_manifest.luau` as
             shell, writing `artifacts/<phase>/gate-legacy.json` so a parity run
             cannot overwrite the live verdict with the old system's opinion)
  NEW path — `tools/verify.sh full --gate <phase>`

A copy rather than this tree, because every mutation here is a real defect — a
broken expectation, a deleted `require`, a planted forbidden word — and
`tools/commit_isolated.py` filters by HUNK, so a sibling agent committing the
file a mutation is sitting in would commit the mutation with it. The window is
the length of a suite run.

**A mutation is credited only when the baseline was green.** A defect that
"reddens" a phase that was already red proves nothing, and the runner records
both numbers so a reader can see which is which.

## The corpus

<!--CORPUS-->

## Results

<!--RESULTS-->

## What only the new path can see, and why that is not a gap

Five of the thirteen are defects the old system had no concept of, because it had
no result store to corrupt: an edited result, a result claiming a different
toolchain, a result whose environment class was changed to one the row may not
accept, a partial suite result, and a stored result offered after its inputs
moved. The old path's equivalent — its transcript cache — is guarded separately
by `tools/suite_cache_selftest.sh`, which is a producer in the graph and runs on
every full and release tier. Each of these five is ALSO asserted in isolation by
`lune run tools/lune/verify/selftest`, which makes all thirty-one refusals happen
on purpose in a scratch directory.

<!--NEWONLY-->
