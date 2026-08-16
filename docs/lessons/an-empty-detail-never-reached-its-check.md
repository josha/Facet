# A gate row with an empty `detail` did not fail its check — it failed to reach it

**2026-08-15.** The round-3 gate came back with `popup-catcher-paint` and
`solve-count-coalescing` red, neither of which had ever been red. Both looked
like fresh regressions from the work that had landed that week. **Neither was a
regression.** Re-run on an idle machine, the suite was 5530 passed / 0 failed and
every grep both rows make hit.

## The signature

Look at what the gate recorded:

```json
{ "name": "popup-catcher-paint", "state": "FAIL_RECOVERABLE", "detail": "" }
```

`detail` is empty. That is not a failure with nothing to say — **it is the shape
of a row that never got to its own question.** Both rows are one `&&` chain:

```bash
out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "✓.*swiping LEFT TO RIGHT …" && …
```

The first link is the whole suite. Under the load a 27-gate sweep generates
(measured at 3.48–8.78 during this run), the suite exited non-zero — a timing
casualty, not a real failure — and `&&` short-circuited. The greps that carry the
row's actual claim never ran. The row is reported against the check it is named
for, but it never executed that check.

Compare a genuine red from the same run, `checker-battery`, which had **two**
independent real causes and was found by running the chain link by link:

- `stylua --check` — six files committed unformatted
- `check_flat_baseline` — 200 problems, a stored dump gone stale

Same `FAIL_RECOVERABLE`, same empty-ish presentation in the roll-up, completely
different meaning.

## The rule

> An empty `detail` is a diagnosis, not an absence of one. Read it as **"this row
> did not reach its check"** and go find which link died — never as "this claim
> is now false."

Concretely, before treating any red row as a regression:

1. **Re-run the row's command standalone, on a quiet machine.** A row that shells
   the suite is measuring the machine as much as the tree.
2. **If it is an `&&` chain, run it link by link.** The chain reports the row's
   name whichever link fails, and the first link is usually the most expensive
   and the least related to the claim.
3. **Only then compare against the recorded state.** Two of the three suspicious
   rows in this run were noise; the third was real and had a second cause nobody
   would have found from the roll-up.

## Why this keeps happening

The expensive link is first because it produces the `out` the greps filter. That
ordering makes every one of these rows a **compound assertion**: "the suite
passes AND this specific behaviour holds." Only the second half is the row's
subject, but the first half is the one that fails under contention, and it fails
in a way that erases the evidence for the second.

The related trap, from `tools/prior_gates.sh`, is the same family: a check whose
own note says *"NOT YET RUN, AND SAID PLAINLY"* is more honest than one that
reports a red it never measured. A row that cannot distinguish "false" from "not
reached" is not yet a check — it is a check plus a timing bet.
