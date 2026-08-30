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

| # | Mutation | Phase | Kind | Why it is in the corpus |
|---|---|---|---|---|
| M1 | a focus case's expectation is broken (`.toBeTruthy()` → `.toBeFalsy()`) | `phase-0-foundation` | parity | the plain failing-test case: a red case must redden every row that cites it |
| M2 | a spec's `require` is deleted from `tests/run.luau` | `api-architecture-consistency` | parity | an unregistered spec is a SILENT ZERO — the suite still exits 0, with a smaller number |
| M3 | the suite is truncated by a main-thread yield | `phase-0-foundation` | parity | the run ends EARLY AND WITH EXIT 0, so the exit code proves nothing |
| M4 | an `it()` a gate row names is renamed | `phase-0-foundation` | parity | the changed-test-ID mutation: a missing id must be a loud FAIL, never a satisfied lookup |
| M5 | a stored result is edited after it was written | `phase-0-foundation` | new-only | the body hash: a hand-edited result must be refused, not served |
| M6 | a result claims a different toolchain (re-hashed, so only that rule can fire) | `phase-0-foundation` | new-only | a result taken under another toolchain is not this tree's evidence |
| M7 | an evidence document a row pins is deleted | `navigation-and-menus` | parity | a row whose evidence is gone must not pass on the strength of its other clauses |
| M8 | a retired product name is planted in a public guide | `release-candidate-review` | parity | a scanner producer that fails must redden every row that asserts its exit 0 |
| M9 | a require of the excised third-party core is planted in `src/` | `distribution-readiness` | parity | the hard no-third-party-core check, exercised as a producer |
| M10 | a stored result is offered after an input changed | `phase-0-foundation` | reuse | identity: the suite's result must NOT be reused after a source edit |
| M11 | a partial suite result is offered (a quarter of the cases, re-hashed) | `phase-0-foundation` | new-only | truncation: fewer specs reported than registered must be refused |
| M12 | a perf-class result is offered to a deterministic row (re-hashed) | `phase-0-foundation` | new-only | evidence classes are never upgraded by a headless cache |
| M13 | a PENDING row is flipped to PASS with nothing behind it | `distribution-readiness` | parity | the cheapest way to fake a gate; only the new path has a graph to fake |


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
