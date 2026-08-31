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

**A mutation is credited only for a row that was NOT already failing.** The
first version of this runner compared exit codes, and every mutation came back
inconclusive — this tree carries reds that belong to other workstreams (a
product-language guard mid-sweep, an allowlist awaiting the archival step, four
transcript greps whose case was renamed before this stage opened), so every
phase was already non-zero and "it exited 1 afterwards" would have credited a
mutation for a failure it had nothing to do with. Each path is therefore asked
WHICH ROWS FAIL, before and after, and the verdict is the difference. It is the
same rule `tools/check_manifest_integrity.py --selftest` uses on itself, and it
is the only one that means anything on a tree in motion.

The same rule exposed a mutation that was proving nothing: planting a retired
product name reddened neither path, because the guard that would have caught it
was ALREADY failing. It was replaced with a broken link in a public guide, which
two green producers hold.

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

Thirteen mutations, all run. Every number below is from a run in this session;
the transcripts are `/tmp/mut_cheap.txt`, `/tmp/mut_hard.txt` and `/tmp/mut_fix.txt`,
and the machine-readable records are the `--out` JSON files beside them.

| # | What it broke | Old path | New path | Verdict |
|---|---|---|---|---|
| M1 | a focus case's expectation | **+3 failing rows** (`modal-focus-spike` first) | **+201 failing rows** (`api-architecture-consistency::compatible-fixes-proven` first) | **PARITY** — 316 s, through the full suite |
| M2 | a spec's `require`, deleted | **+4** (`compatible-fixes-proven` first) | **+228** | **PARITY** — 326 s, through the full suite |
| M3 | a main-thread yield appended to a spec | +0 | +0 | **DID NOT REPRODUCE** — see below |
| M4 | an `it()` a gate row names, renamed | +0 | **+1** (`navigation-and-menus::d0-one-run-per-sweep`) | **NEW-ONLY** — the old path did not notice |
| M5 | a stored result edited after it was written | — | refused: *body hash mismatch — the stored result was edited after it was written* | **REFUSED** |
| M6 | a result claiming another toolchain (re-hashed) | — | refused: *stored result was produced under a different toolchain* | **REFUSED** |
| M7 | an evidence document a row pins, deleted | **+1** (`d0-one-run-per-sweep`) | **+1** (`navigation-and-menus::d0-one-run-per-sweep`) | **PARITY** — the same row, by name, on both |
| M8 | a dead link planted in a public guide | no row asserts it | `check_links_cli` **PASS → FAIL**, naming the dead link and its line | **REFUSED at the producer** |
| M9 | a require of the excised third-party core, planted in `src/` | no row asserts it | `check_no_fusion` **PASS → FAIL**, 2 violations naming the line in the source AND in the built model | **REFUSED at the producer** |
| M10 | a source edit under a stored result | — | the suite was **not reused**: *no stored result for this identity* | **REFUSED REUSE** |
| M11 | a partial suite result (a quarter of the cases, re-hashed so only the partial rule can fire) | — | the store **refuses to serve it**; restoring the file makes it serve again | **REFUSED** |
| M12 | a `perf`-class result offered to a deterministic row (re-hashed) | — | refused: *stored result is class 'perf' but the row requires 'deterministic'* | **REFUSED** |
| M13 | a PENDING row flipped to PASS with nothing behind it | +0 — the old system has no graph to fake | **+44** | **NEW-ONLY** |

**Three mutations went red on both paths** (M1, M2, M7), two of them through a
complete suite run, which is the "at least three through the full suite path"
the plan asks for. **Six are refusals only the new path can make**, because the
old system had no result store to corrupt — and each of those six is ALSO
asserted in isolation by `lune run tools/lune/verify/selftest`, which makes all
thirty-two of the store's checks happen on purpose in a scratch directory.

### The four that did not come out as expected, stated rather than smoothed over

**M3 did not reproduce the defect it was aiming at.** Appending
`task.wait(0.01)` to a spec did not truncate the run under Lune 0.10.4: the
suite completed, so neither path had anything to notice. The REFUSAL is proven —
`suiteRefusal` rejects a run with no summary, with fewer specs reported than
registered, and with fewer passes than registered spec modules, each asserted by
the selftest, and M11 exercises the same rule end to end on a real stored result.
What is NOT proven is that this particular trigger still produces that shape.

**M4 was caught by the new path and missed by the old one.** Renaming a case a
gate row names added one failing row on the new path and none on the old. That is
the asymmetry the conversion was for — an id lookup cannot silently match a
different sentence — but it is the opposite of parity, so it is recorded as
NEW-ONLY rather than counted as one.

**M8 and M9 have no row to redden.** `check_links_cli` and `check_no_fusion` both
run in the release graph and both go from PASS to FAIL when their defect is
planted, naming it precisely. Neither is asserted by any row yet, because the
rows that will assert them are two of the director's thirty-four PENDING
registration rows. **That is a finding for the director, not a gap in the
conversion**: two release-graph producers are currently unconsumed.

### What the corpus cost

M1 and M2 each spend a full suite run on each path (316 s and 326 s). The rest
are seconds, because the store serves everything the mutation did not touch —
which is itself a measurement of the thing being proved.


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

The six are M5, M6, M8, M9, M11 and M12. M8 and M9 are refusals at the producer
rather than at a row, for the reason given above.
