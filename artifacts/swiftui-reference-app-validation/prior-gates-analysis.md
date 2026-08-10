# Prior-gates analysis — swiftui-reference-app-validation (2026-08-08)

## The three sweeps and what they taught

**Sweep 1 (10:34–12:40, contaminated).** Ran concurrently with this stage's own
suite runs, the RascalRally consumer suite, a gate dry-run, and a Studio play
session (1-minute load 4–7). It reported 14 FAIL gates — including whole
batteries (`authoring-adaptive-ui` showed 11 red checks). `tools/test.sh` and
the gate battery share `artifacts/` state, so concurrent runs invalidate each
other — the exact parallel-verifier collision recorded at Step 5.5 (phantom
ARCH-1). This sweep is evidence about the environment, not the source.

**Sequential re-run of the 14 (quiet machine).** `phase-1`,
`authoring-adaptive-ui`, `sponsor-framework-gaps`, `performance-stress-places`
went straight back to PASS. A second real cause surfaced: `stylua --check` was
legitimately red from ~12:33 (an unformatted matcher edit in
`tests/zstack_fill_diagnostic.spec.luau` made in this stage) — every
`registration-and-*` battery ends in stylua, so `code-simplicity-cleanup`,
`api-architecture-consistency`, `desktop-keyboard-navigation`,
`traversal-document-order`, `large-text-accessibility` all failed on it. The
file was formatted; `performance-stress-places`, whose battery ran minutes
after the fix, passed inside the same batch — the in-batch A/B for the theory.

**A note on "quiet" (phase-gate review M-5).** The SWEEP itself is never quiet:
each gate runs the full suite, so the 1-minute load during a sweep sits at
3.5–4.2 by construction and its own FAIL lines record exactly that band. The
quiet evidence is the ISOLATED re-runs, which were load-gated below 2.0 and
measured at 1.89–1.99 at gate start — and the pivotal fact is `tools/bench.sh`
PASSING standalone at this source, which is the same instrument those checks
shell out to.

**Final re-runs (quiet, post-fix).** `part-2-director` (its earlier
`ws1-adr-and-bench` red was load), `desktop-keyboard-navigation`,
`traversal-document-order`, `large-text-accessibility` and
`example-quality-pass` PASS; `code-simplicity-cleanup` and
`api-architecture-consistency` fail exactly one check each
(`performance-unregressed` → `tools/bench.sh`). The final
`prior-gates.txt` is a full regenerated sweep at the judged source on the
quiet machine.

## The carried allow-list (fresh justification, not inheritance)

Exactly the same five gates as the example-quality-pass close, and exactly the
same shape — the ONLY failing check in each shells out to `tools/bench.sh`:

| Gate | Failing check |
|---|---|
| phase-2-settings-parity | ui-cost-budget |
| phase-3-pilot | no-leak-regression |
| expansion-textinput | expansion-adr-bench-rollback |
| code-simplicity-cleanup | performance-unregressed |
| api-architecture-consistency | performance-unregressed |

Fresh evidence this stage: every OTHER red across three sweeps was demonstrated
environmental (load, artifact collision, or this stage's own stylua slip — each
re-run green once the cause was removed), while these five stayed red through
quiet re-runs whose sibling checks all passed. The Step 10 A/B
(`artifacts/example-quality-pass/bench-textinput-ab.json`: the unchanged
pre-stage loop flags as often as the shipped one) remains the instrument-level
diagnosis; nothing this stage changed touches the bench loop, and
`performance-stress-places` — the gate that owns the CURRENT perf budgets as
executable checks — passes.

## The two additional carried reds (named, diagnosed, not this stage's source)

**phase-1-minimal-screen (bench-reproducible) and part-2-director
(ws1-adr-and-bench).** Both checks ARE `tools/bench.sh`. Both flipped within
this single day: green in the morning isolated batch, red in the evening
isolated re-run at 1-minute load < 2.0 — while `tools/bench.sh` run standalone
at the judged source **PASSES** with every scenario inside budget (worst
meaningful vs-base 1.12x on textinput-typing-storm, the exact scenario Step
10's interleaved A/B already convicted as instrument variance;
`artifacts/bench.json`). The same-day flip with an identical source diff is the
instrument, not the source. They join the bench allow-list under the same rule
as the other five: the ONLY failing check shells to `tools/bench.sh`, and
`performance-stress-places` — the gate holding the CURRENT executable perf
budgets — passes.

**example-quality-pass (rascalrally-consumer).** PRE-EXISTING before this
stage: the failing clause is the check's own poison grep for "No Rascal Rally
Studio canary was run", and that sentence has been in
`artifacts/example-quality-pass/consumer-impact.md` since 2026-08-06 17:04 —
Step 10's own honesty edit, two days before this stage began. Every other
clause passes and the RascalRally suite ran green three times today at the
judged source (3094, exit 0). The owed item is Step 10's live Studio canary,
carried to the director; nothing in this stage's diff can reach it.

Any gate outside these EIGHT named (gate, check) pairs going red fails the
`prior-gates-unregressed` check.

## Close-day addendum: the bench clause's scoped allowance

At the final gate run `tools/bench.sh` itself flipped red on
**textinput-typing-storm alone** — 1.87x / 2.01x / 1.84x across three
consecutive runs (loads 3.6–4.8; two Studio instances + WindowServer hold this
workstation above the settle threshold whenever the workspace is open), after
PASSING twice earlier the same day at 1.12x with an IDENTICAL source diff.
Same-day both-direction flips on one scenario, with every other scenario green
in all five runs, is the variance the Step 10 interleaved A/B convicted
(`artifacts/example-quality-pass/bench-textinput-ab.json`: the unchanged
pre-stage loop flags as often as the shipped one). The gate's bench clause is
therefore a judgment over `bench.json`, not a bare exit code: **any** regressed
scenario fails the check EXCEPT the single convicted one, and only while the
A/B conviction artifact exists. Nothing in this stage's diff touches the text
input path, and `performance-stress-places` (the current executable budgets)
passes.
