# Journal — "a column disappears at certain widths" (Facet table)

## 0. Orientation (docs first)
- No README at the repo root. `find . -maxdepth 1 -name '*.md'` returns only `ui_todo.md`.
  The real entry point is `docs/guide/README.md`; I found it by listing `docs/`, not by
  being pointed there. **Friction #1: nothing at the root tells a newcomer where to start.**
- `docs/guide/README.md` was excellent for the two things I needed immediately:
  - how to run the suite: `./run-tests.sh` (full, ~42 s) vs `./run-tests.sh --fast`
    (inner loop, refuses to count as green — `tools/test.sh` rejects the FAST-TIER banner).
  - what "finished" means: it points at `docs/plans/agent-execution-contract.md`.
- The execution contract (§3 evidence ladder, §6 implementation loop) is written for
  roadmap *stages*, not for a one-line bug fix. Useful parts: E1 = pure/headless is the
  right level for a deterministic geometry decision; §6.2 "add a failing E1 test first";
  §6 "when Studio uncovers a defect the headless suite missed, add the smallest headless
  regression". The Rascal Rally consumer-lockstep section is not actionable here — this
  checkout is `GameStudio/ui/Facet` alone, no game tree exists to synchronize.

## 1. Finding the owner
`src/controls/` has five `table_*` files; `table_columns.luau` (447 lines) is the pure
half — the *only* place column widths are divided, and `table.luau:1387` is its single
caller. Grepping `overflow` across `src/` gave 30 hits and was useless; grepping
`resiz|drag|divider` inside the five table files landed on it in one step.

The module is unusually well documented — every rule carries the measurement that
produced it. That is what made the diagnosis a five-minute read: the block above
`FIT_EPSILON` argues at length for a tolerance of **1e-6** ("WHY 1e-6 AND NOT
composition.luau's 0.5"), and the constant underneath it read `= 0`. The code
contradicted its own docstring.

## 2. Reproducing before believing (E1, per contract §3)
`scratchpad/exB/repro_column_collapse.luau` (run from the Facet root with `lune run`):
sweeps `available` from 150..700 for two `fill` columns with floors 100/90 and drags
377/304, and counts widths where `layout()` hides a column while `fitOverrides()`'
own widths still fit.

    before fix: 53 of 551 widths collapsed a column whose widths fit
                band 193..511, e.g. available=227 -> 120.87372708757641
                + 106.12627291242364 = 227.00000000000006, hidden = artist
                available=192 -> none, 193 -> artist   (the "one pixel" report)
                available=511 -> artist, 512 -> none
    after fix:  0 of 551

**A trap I walked into:** my first oracle asked `sum <= available` exactly — and found
zero bad widths, because the very float overshoot that *is* the bug also made my oracle
say "does not fit". A repro for a floating-point defect needs a tolerance on the
*oracle*, not just on the code. That cost one wrong run.

## 3. Root cause
`fitOverrides` distributes the clamp as `px - take * (room_i / slack)`, so when the
clamp is active the fitted widths sum to `available - reserved` **by construction**.
`layout`'s collapse loop then re-adds those same numbers with a left fold and asked
`demand <= room + FIT_EPSILON` with `FIT_EPSILON = 0`; IEEE accumulation lands the
re-sum a few ulps above its own target, so "exactly fits" read as "does not fit" and the
lowest-priority column was collapsed whole. Since the overshoot depends on the exact
divisor, only *some* widths are affected — hence "one pixel and it comes back".

`git show HEAD` confirmed it afterwards: the tip commit ("internal build snapshot")
flipped `1e-6 -> 0` and deleted the 50-line regression test that covered it. I had the
diagnosis from the source and the sweep before I looked at history.

## 4. Fix + regression
- `src/controls/table_columns.luau`: `FIT_EPSILON = 1e-6` (one line, back to what the
  module's own documented reasoning specifies).
- `tests/table.spec.luau`: one case, three assertions — the point case I measured
  (227), a sweep of 190..1200 asserting *no* width above the floors' own sum collapses
  anything (this defect is a stripe, so the guard is a stripe), and the null hypothesis
  at 189 (one pixel under the floors' sum) so the tolerance can never degrade into
  "never collapse".
- Mutation check (repo lesson: confirm the test bites): with `FIT_EPSILON` set back to
  0 the new case fails and the other 130 in `table.spec` pass. Restored, all 131 pass.

## 5. Checks run
| Check | Result |
|---|---|
| `./run-tests.sh` (full suite) | **6799 passed**, 0 failed — 3 m 36 s |
| `tools/test.sh 6799` (judged, writes `artifacts/test.json`) | `test: PASS passed=6799`, exit 0 |
| `stylua --check src tests tools bench examples` | clean |
| `python3 tools/check_source_size.py` | PASS (nothing near the 200k cap moved) |
| `tools/doctor.sh` | FAIL on a pristine tree too — see below; PASS after `mkdir build` |
| `python3 tools/check_doc_style.py` | PASS |
| `python3 tools/check_library_purity.py` | PASS |
| `python3 tools/check_brand_drift.py` | `FAIL_ENVIRONMENT` — wants `games/RascalRally/code`, absent here |

## 6. Where the docs did not help
- **The suite timing in the guide is stale.** `docs/guide/README.md` promises ~42 s for
  the full suite and ~8 s for `--fast`; the real full run here is **3 m 36 s**. Not
  wrong in kind, but it changes how you plan an inner loop.
- **`tools/doctor.sh` fails out of the box for a reason that is not a code problem.**
  Its `rojo-build` row runs `rojo build ... -o build/Facet-Gallery.rbxl`, `build/` is
  gitignored, and nothing creates it — the script does `mkdir -p artifacts` but not
  `mkdir -p build`. A fresh clone therefore gets a REQUIRED FAIL whose detail line says
  "rojo build ... failed", which reads like a broken project. I verified against a
  `git stash`ed pristine tree that it fails identically without my change, and that it
  passes with my change once `build/` exists. I left the script alone (out of scope),
  but it is a one-line fix for whoever owns it.
- **The execution contract is stage-shaped, not fix-shaped.** `docs/plans/agent-
  execution-contract.md` is the document the guide points at for "what finished means",
  and its §2 acceptance ledger, §7 evidence bundle, and the Rascal Rally consumer-
  lockstep section all assume a roadmap stage with a game checkout beside it. For a
  one-line arithmetic fix in a pure module there is no row that says "this is the whole
  bar". I used §3 (E1 is the right level for a deterministic geometry decision) and §6
  (failing test first, smallest durable regression) and ignored the rest.
- **No single-spec runner.** `tests/run.luau` is a hand-maintained `require` list and
  the only entry points are all-or-fast-tier. To iterate on one spec I had to write a
  four-line `tests/run_one_tmp.luau` that requires testkit + the one spec. That should
  be a flag on `run-tests.sh`.
- **Gate rows cannot pass in this checkout.** The gate manifest rows for the table
  divider end with `(cd ../../../games/RascalRally/code && tools/suite_transcript.sh)`,
  and `check_brand_drift.py` shells into the same absent tree. Facet-only clones cannot
  run their own phase gates.

## 7. Landed
`5f8bb8462` on `main`, via the repo's own `tools/commit_isolated.py` (private index,
compare-and-swap on HEAD) rather than `git add` — `docs/lessons/staging-by-name-is-
not-isolation.md` is emphatic about why. Working tree clean afterwards; the suite cache
reports `hit` for the committed tree state, i.e. the transcript that says 6799 passed is
the transcript for exactly this tree.

## 8. Three biggest friction points
1. **No root README.** The repo root has `ui_todo.md` and nothing else; every
   orientation fact lives under `docs/guide/`, discoverable only by listing directories.
2. **`tools/doctor.sh` fails on a clean checkout** because `rojo build -o build/...`
   has no `build/` directory to write into, and reports it as a REQUIRED build failure.
   That is a false alarm every newcomer meets before their first edit.
3. **Facet cannot verify itself alone.** The phase gates and `check_brand_drift.py`
   shell into `games/RascalRally/code`, which is not part of this checkout, so the
   repo's own definition of "gate green" is unreachable here. Combined with the
   stage-shaped execution contract, a small bug fix has no documented bar of its own —
   I had to assemble one (suite + stylua + the applicable python checks + doctor).
