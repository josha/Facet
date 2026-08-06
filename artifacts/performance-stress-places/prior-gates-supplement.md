# Prior-gates supplement — performance stress places (Step 9)

`tools/prior_gates.sh` re-runs every gate preceding this stage, at the final source, and
writes the roll-up in `prior-gates.txt`. This file accounts for **every check that came
back red**, individually, with the verdict it gives when run on its own.

## The rule this file has to satisfy

`check_perf_gate_evidence.py prior-gates` requires:

1. the roll-up ends in `DONE` (a truncated sweep cannot read as complete);
2. at least 18 gates pass structurally;
3. **every** `FAIL_RECOVERABLE` check under every failed gate has a line below of the
   form `<gate> :: <check> :: standalone PASS`.

Rule 3 replaced an inherited allowlist of four bench check *names*. The allowlist was
weaker in the way that matters: it trusted a name instead of demanding evidence, and it
would have excused a genuinely broken check that happened to be called one of the four.
`FAIL_ENVIRONMENT` checks are the physical/human rows this repository leaves open by
design and are not covered by rule 3.

**This is not a formality — rule 3 caught a real regression.** See "The one that was
real" below.

## Why anything fails at all

The sweep runs ~21 gates back to back, and **twelve of them regenerate their own nested
sweep**, so the work is superlinear in gate count. Each gate runs the full 3 367-case
suite at least once. On this machine the idle load floor sits near 4 (browser, Studio),
`prior_gates.sh` gives up waiting for load to settle after 45 s, and under that
contention the suite and the bench comparisons intermittently fail.

**The load matters, measurably.** Two sweeps at the same source:

| sweep | conditions | gates passing | red `FAIL_RECOVERABLE` checks |
|---|---|---|---|
| 1 | Studio in Play (~40% CPU) + sync server running | 15 | 10, incl. `library-suite-green` ×2 and five suite-grep checks under `native-substrate` |
| 2 | Studio out of Play, sync server stopped | 18 | 3 |
| 3 | same, **at the final source** (after the L-6 scoping fix) | **20** | **1** |

`prior-gates.txt` holds **sweep 3** — the one taken at the judged source. Sweep 3's
single red is `sponsor-fixtures`, and note what is no longer there:
`performance-unregressed` passes now, because the regression it was reporting was fixed
rather than excused.

Sweep 1's extra reds are one event each, not many: the five `native-substrate` checks all
use the Form-A `out="$(./run-tests.sh 2>&1)" && …` shape, so a single failed suite run
reddens all five. `library-suite-green` runs `tools/test.sh` against floors of 114 and
154 — numbers a 3 367-case suite clears by an enormous margin — so the only way it fails
is the suite not completing. Standalone it passed **5 runs out of 5**.

## The one that was real

`code-simplicity-cleanup :: performance-unregressed` was red in the sweep **and red
standalone**. That is the discriminator, and it said regression rather than noise.

Cause: this stage's `solver.measure` memo, unconditional, cost more than it saved on
`textinput-typing-storm` — a small tree with no scroll node and therefore no redundant
measure to eliminate. Interleaved A/B: worse in 6 of 6 pairs.

**Fixed, not excused, and the budget was not touched.** The memo is now scoped to trees
that contain a scroll node; the two builds are indistinguishable on that scene
afterwards, and the beneficiary keeps its full win. Full record in
`optimization-log.md` **L-6**.

## Standalone verdicts

```
large-text-accessibility :: sponsor-fixtures :: standalone PASS
part-2-director :: ws1-adr-and-bench :: standalone PASS
code-simplicity-cleanup :: performance-unregressed :: standalone PASS
```

The first line is sweep 3's only red. The other two were red in sweep 2 and are kept
because they are the same class and a reader comparing the sweeps will ask.

How each was established, at the final source:

- **`ws1-adr-and-bench`** — ran its exact `run` string: the ADR file exists,
  `tools/bench.sh` completed, `artifacts/bench.json` contains `table-resize-drag`. It
  *is* a bench comparison, which is why it moves with load.
- **`performance-unregressed`** — see above. Red for a real reason, fixed at the source,
  and passing afterwards. It remains flaky around the 1.5× threshold in **both** builds
  (measured), which is a pre-existing property of `textinput-typing-storm` and not
  something this stage introduced.
- **`sponsor-fixtures`** — the only non-bench red, and the one worth checking hardest: it
  runs the **Rascal Rally** suite and greps fourteen named cases. Ran its exact `run`
  string standalone → **PASS** on 3 089 cases. The game suite was also run independently
  for the consumer ledger, twice, green both times.

## What is NOT excused here

- a red check with no standalone verdict recorded above;
- a check that also fails standalone and was *not* fixed — that is a regression and
  belongs in the optimization log, which is exactly where `performance-unregressed`
  went;
- a truncated roll-up;
- fewer than 18 structurally passing gates.

Each reddens `prior-gates-unregressed` by construction. The check is structural and reads
the roll-up produced at the judged source, so it cannot decay into the
compare-two-checked-in-text-files shape the gate-integrity sweep removed elsewhere.

## Standing recommendation

The sweep's cost is superlinear because twelve gates each regenerate it. A shared
"prior gates already ran in this process" memo would make it linear. Out of scope here,
recorded rather than quietly tolerated.
