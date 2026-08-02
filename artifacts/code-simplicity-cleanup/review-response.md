# Step 5.5 — fresh-context review response

**Date:** 2026-07-28 · **Gate:** `code-simplicity-cleanup`

The `fresh-context-reviews` check was the stage's last open acceptance control. Three
reviewers ran fresh-context on the raw baseline, ledgers, changed-file list and
evidence, none of them given `SUMMARY.md`.

| Reviewer | Verdict | Report |
|---|---|---|
| phase-gate | **ACCEPT** — 0 BLOCKER, 3 MAJOR, 8 MINOR | `verifier-phase-gate.json` |
| architecture | **ACCEPT WITH FINDINGS** — 0 BLOCKER, 1 MAJOR, 5 MINOR | `verifier-architecture.json` |
| reactive-runtime | **ACCEPT WITH FINDINGS** — 0 BLOCKER, 1 MAJOR, 6 MINOR | `verifier-reactive-runtime.json` |

No BLOCKER was found by any reviewer, and no reviewer could establish a behaviour
change smuggled into the cleanup. **All four MAJOR findings are fixed** (one was a
phantom; three were real). Every fix is mutation-proved.

The reactive-runtime review was run **alone**, after the other two, precisely because
of ARCH-1 below. It also adjudicated the two findings the architecture reviewer
referred to it:

- **ARCH-2 — UPHELD, and stronger than filed.** Fixed as RT-1 below.
- **ARCH-3 — REJECTED.** `scrollHostOf` is `table.clear`ed and rebuilt by `livePaths`
  inside the same `structuralSync` that unmounts handles, and the removal sweep
  independently nils `lastRects[path]` and `lastScrollRegions[path]`.
  `scrollToVisible` fails two independent gates for an unmounted path. No lost
  liveness check, no leak, no stale scroll. No action.

---

## ARCH-1 (MAJOR) — withdrawn, phantom

The architecture reviewer reported that two source files were edited mid-session and
that `src/core/scope_impl.luau` was caught in a state that **removes the
double-disposal detector**.

**This was an artifact of running two reviewers concurrently, not a defect.** The
phase-gate reviewer mutation-tests by construction — it reverts a fix, confirms
exactly the named test reddens, and restores. The architecture reviewer read
`scope_impl.luau` and `clock.luau` while that was in flight.

Disproved directly: the detector is present at `src/core/scope_impl.luau:62`
(`note(\`LuauUI: double disposal of scope '{...}' detected\`)` inside the
`if self.disposed then` guard); suite 2571 passed exit 0; `stylua --check` exit 0.

**Process rule taken from this:** never run verifiers concurrently when any of them
may mutation-test. Serialize, or give the mutating one an isolated worktree. The
reactive-runtime review was run alone for exactly this reason.

---

## The three MAJOR findings — all fixed

### PG-1 — the RR-1-R2 pin did not pin

**Finding.** `tests/runtime_quarantine.spec.luau` is named *"transactions counts
frames that really committed, never the aborted ones"* and the carry-over ledger
claims RR-1-R2 is *"pinned both directions"*. The unhealthy branch asserted only
`stats.transactions <= stats.steps` — satisfied by **any** counting scheme,
including the wrong one. Only the healthy branch was exact. `carry-over-pins`
asserts this test by name, so the gate was reporting a pin that pinned nothing.

**Fix.** The unhealthy branch now asserts the exact measured value the probe already
prints: `expect(stats.transactions).toBe(0)` — all 30 steps abort in `pre`, so a
correct clock opens zero transactions. The healthy-equality and `steps > 0`
assertions are unchanged.

**Proof (mutation).** Moved `transactions += 1` out of the pcall'ed commit phase
(`src/motion/clock.luau:195`) to immediately after `steps += 1` — the exact drift the
corrected doc comment exists to prevent.

- Before the fix: suite **2571 passed, exit 0** — the mutation was invisible.
- After the fix: **1 failed, 2570 passed**, and the one red test is
  `transactions counts frames that really committed, never the aborted ones`.
- Restored; `src/motion/clock.luau` sha256 `6dbf086a3a40ee8a…`, `stylua --check` exit 0.

### PG-2 — `prior-gates-unregressed` re-ran no gate

**Finding.** The run string compared `baseline/prior-gates-before.txt` against
`prior-gates.txt` — **two stored text files**. Nothing executed against the current
tree. Any regression introduced after those files were written left the check green,
and re-running the gate could not detect it. This is the identical can't-ever-fail
shape ledger **C-08 had just removed** from `theme-packages-and-skinning`'s old `cmp`
of two stored dumps, reintroduced in the same stage, carrying that stage's own
headline claim. Carry-over PG-9 had already noted the manifest was never swept for
shallow checks.

**Fix.** New `tools/prior_gates.sh <out> [stage]` re-runs every gate preceding the
stage and writes the roll-up. The gate list is derived from `phases.json`, not
hard-coded, so a newly registered gate is covered the day it lands rather than the
day someone remembers to edit a list. The check now regenerates its `after` operand
through that script before the existing directional `comm -23`.

The comparison stays **directional** on purpose: no gate that passed at the baseline
may fail now, but an identical list is not demanded — `theme-packages-and-skinning`
legitimately went FAIL → PASS in this stage (C-08/C-09), and `authoring-adaptive-ui`
fails identically before and after on its own standing PENDING physical row.

**Proof (two parts).**

1. *The regeneration is real.* Ran against the clean tree: 16 gates re-run, ~11 min,
   output identical to the stored hand-made file on every `^PASS ` line (the only
   diff is one cosmetic `gate: PENDING -> …` line the hand-made file carried).
2. *A regression is now caught.* On a cheap 2-gate slice (`phase-2-settings-parity`),
   broke `defaultEq` in `src/core/custom.luau` to always report "changed".
   `phase-0-foundation` and `phase-1-minimal-screen` both flipped PASS → FAIL, `comm`
   reported both as lost, and the check's `test -z "$lost"` failed — **correct**.
   Restored; `src/core/custom.luau` sha256 `dbdac4cfd26dafa6…`, zero mutation markers.

*Cost:* the check now takes ~11 minutes, plus inter-gate settle (below). Accepted —
this is the terminal gate of a stage, run rarely, and the alternative was a check that
could not fail.

**What making it real immediately exposed — a pre-existing flaky-gate fragility.**
The first honest runs of this check went red on `phase-3-pilot`, whose
`no-leak-regression` runs `tools/soak.sh` **and** `tools/bench.sh`. It failed
**in-batch 2/2 and passed standalone 2/2** with nothing in the tree changing. Cause:
`mounted-slice-update-storm` normally sits at **1.40×** its frozen baseline p95 against
a `REGRESSION_FACTOR` of **1.5×** — roughly 7% headroom — so eleven minutes of
back-to-back gates is enough to push it over. (Separately, an earlier run of this gate
made while Roblox Studio was open at ~17% CPU pushed the same scene to **1.54×**;
stopping Studio and re-running **once** returned 1.402× and a clean bench. A single
clean re-run, not a run-until-green loop.)

`tools/prior_gates.sh` now waits for the 1-minute load average to fall below a
threshold before each gate (`PRIOR_GATES_SETTLE_LOAD`, `PRIOR_GATES_SETTLE_MAX`), and
with that the full batch is green — `phase-3-pilot` PASS in-batch, nothing lost against
the baseline.

**This is a mitigation, not a fix, and it should not be filed as closed.** A check that
goes red from its own scheduling is the flaky-gate version of exactly the defect class
this stage spent its budget removing: it does not tell you about the tree. The real fix
is headroom — re-baselining the tight scenes or giving them a per-scene factor — which
changes frozen perf baselines and is a deliberate decision, not a cleanup side effect.
Recorded in `perf-after.md` and left for that decision.

Operational consequence, now that PG-3 makes this gate regenerate the bench itself:
**do not run the `code-simplicity-cleanup` gate with Studio open.**

### PG-3 — `performance-unregressed` read a bench it did not run

**Finding.** The run string read `artifacts/bench.json` without invoking
`tools/bench.sh`. The manifest note openly conceded the after-numbers were produced
by the **expansion-textinput gate's** own bench check during the prior-gate rerun —
so this gate's performance evidence was a side effect of a different gate's run, and
nothing in this gate's run string re-established it. It could not distinguish
final-source evidence from a stale artifact and would have passed forever. Two other
gates in the same manifest already do it correctly.

**Fix.** Prefixed `tools/bench.sh >/dev/null &&`, matching
`expansion-adr-bench-rollback`. `bench.json` is now regenerated at the source being
judged. Check ordering is safe: `prior-gates-unregressed` runs first and clobbers
`bench.json`/`test.json` via the nested gate runs, and `performance-unregressed`
regenerates afterwards.

### RT-3 — the conformance check this stage ADDED pinned nothing

**Finding.** The new cross-core check
`scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose` says it pins that
"a child disposed EARLY is ordinary ownership rather than a double-dispose report".
It could not fail for that reason. An early-disposed child **deregisters itself** from
`parent.owned`, so the parent's reverse walk never encounters it and the
`if not resource.disposed` guard in `scope_impl.luau` is never consulted on that path.
Mutation-proven by the reviewer: deleting the guard entirely left the full suite green
at 2571, the new conformance check on all three cores included.

This is the same class as PG-1, and worse for being the check the stage *added* while
the carry-over ledger cites it as the RR-7-R1 disposition. The runtime behaviour was
correct; the evidence for it was not.

**Fix.** The check now builds the guard's actual live case: the child is created
FIRST, then a cleanup closure that disposes it is owned after. The reverse walk
therefore reaches the closure first and finds the child already disposed **while it is
still in `owned`** — the only path where the guard does any work. The comment now
names what it really pins.

**Proof (mutation).** Replaced the guarded branch with a bare `resource:dispose()`:

- Before the fix: suite **2571 passed, exit 0** — invisible.
- After the fix: **1 failed, 2570 passed**, red on
  `scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose`, and FAIL on
  **all three cores** (`custom`, `fusion`, `imperative`) with
  *"the walk reported an already-disposed child as a double disposal"*.
- Restored; `src/core/scope_impl.luau` sha256 `82334975cd669e4f…`.

### RT-1 / ARCH-2 — the header rule was false in both directions

**Finding.** `src/core/scope_impl.luau` said the double-disposal report *"fires only
for a scope with TWO owners"*. Measured, both halves are wrong: it **does** fire for a
scope with zero owners (exactly what the `double-dispose-detected` conformance check
asserts), and it does **not** fire for a scope literally owned by two parents. Code,
the inline comment, and both conformance checks were correct and consistent — only the
header was wrong.

This is more than a typo because the stage deliberately made this header the single
home of the wording ("THE WORDING LIVES HERE"), so a future agent reconciling code to
header would have deleted a detector two conformance checks depend on.

**Fix.** Reworded to the rule the code implements: it fires when code calls
`dispose()` directly on an already-disposed handle, including a scope with no owners;
the parent's reverse walk skips an already-disposed child silently. The old wording is
recorded inline with why it was wrong.

### RT-2 — the clock's corrected invariant over-claimed

**Finding.** The stage rewrote the `Stats` contract to `transactions <= steps`,
*"equality exactly when `lastError()` is nil"*. The forward direction holds; the
biconditional does not. `onSettle` subscribers run in the POST phase and are pcall'ed
inside `fireSettle`, which routes to `noteError` rather than aborting the frame — so a
throwing settle handler sets `lastError` while every frame still commits. Measured:
steps 48, transactions 48, error set.

**Fix.** Corrected to *"equality exactly when no frame aborted BEFORE the commit
phase"*, which is what the code implements and what the RR-1-R2 pin measures, with the
falsifying case recorded inline. The RR-1-R2 test comment repeated the over-claim and
is corrected too.

*Carried, not taken:* RT-2 also suggests optionally adding a throwing-`onSettle` case
to pin equality-with-error in both directions. Not added — it would be a new test the
stage does not otherwise need, and the false statement (the actual defect) is gone.

---

## MINOR findings — dispositioned

Carried, not fixed in this stage. Full text in the reviewer JSONs.

- **PG-4** `CHANGED-FILES.md` omits `docs/plans/luauui-consolidated-roadmap.md` — corrected below.
- **PG-5** "every scene same-or-faster" is p50-only; 2 scenes were slower on p95 in the
  reviewer's re-run, both inside the bench's own 1.5× rule. The claim should say p50.
- **PG-6** the compact-phone-portrait Studio row is prose-only with no stored artifact,
  yet is cited as evidence for the `topbarInset` correction. Folded into the open
  `studio-evidence` row.
- **PG-7** three gate checks in other stages are token greps — the PG-9 sweep this
  stage declined is still owed.
- **PG-8** the presenter `filterHidden`/`isPathPrefix` "same expression" claim is
  unverifiable without pre-cleanup source (segment-aligned vs bare prefix differ).
- **PG-9** `TYPE_CHECKS` is now unfrozen; the old freeze is unverifiable.
- **PG-10** `studio-evidence` is marked non-release-blocking for what is a recoverable
  harness refusal.
- **PG-11** the RR-7-R1 conformance check is single-directional.
- **ARCH-2 / RT-1** — **FIXED above**, upheld and stronger than filed.
- **ARCH-3** — **REJECTED above** by the reactive-runtime reviewer. No defect.
- **RT-2** — **FIXED above.**
- **RT-4** RR-5-R1's retirement rationale is registration-order-dependent; the mirror
  alias is silent.
- **RT-5** `enabledNow`'s Readable branch can be mutated to `return true` with the
  suite still green — the branch is unpinned.
- **RT-6** `enabledIn`'s subscription behaviour is pinned only via Slider, not across
  the five controls that now delegate.
- **RT-7** (pre-existing, not this stage) renderer `lastCompact` is never cleared on
  removal.
- **ARCH-4** `controls/contract.luau` mixes registry and runtime policy; no gate models
  the resulting require direction (`check_boundary` covers only client/server and the
  engine-free zone).
- **ARCH-5** `gridColumnCount` widens the arrange path with a `math.huge` guard arrange
  never had; traced inert, but unpinned.
- **ARCH-6** the ledger's reason for retaining the dead `host` authority member
  overstates its evidence — the export freeze is the real reason.

**The standing structural point, worth carrying forward:** the repo's recurring
failure mode is *a check that passes without proving anything*, and this stage —
whose whole purpose was to remove that class — shipped two new instances of it in its
own manifest and one test pin that pinned nothing. PG-7's sweep of the remaining
manifest is the obvious next move.

---

## Files changed by this response

| File | What changed |
|---|---|
| `tests/runtime_quarantine.spec.luau` | RR-1-R2 unhealthy branch asserts the exact value (PG-1); comment no longer repeats the over-claim (RT-2) |
| `tests/conformance/suite.luau` | the RR-7-R1 check now builds the guard's live case, so it pins the guard on all three cores (RT-3) |
| `src/core/scope_impl.luau` | header rule corrected — comment only, no code change (RT-1 / ARCH-2) |
| `src/motion/clock.luau` | `Stats` invariant corrected — comment only, no code change (RT-2) |
| `tools/prior_gates.sh` | **new** — re-runs every prior gate, list derived from `phases.json` (PG-2) |
| `tools/lune/gate_manifest.luau` | `prior-gates-unregressed` regenerates via that script (PG-2); `performance-unregressed` runs `tools/bench.sh` first (PG-3); both notes rewritten to record why |
| `artifacts/code-simplicity-cleanup/review-response.md` | **new** — this file |
| `artifacts/code-simplicity-cleanup/CHANGED-FILES.md` | records the above, plus the PG-4 omission |

No `src/` **behaviour** changed in this response — the two `src/` edits are comment
corrections. Every mutation used as proof was backed up, restored, and confirmed by
sha256 plus a clean suite and `stylua --check`. Final state: **2571 passed, exit 0**
(unchanged count — the RT-3 fix rewrote an existing check rather than adding one, so
the `library-suite-green` floor is untouched); `stylua --check` exit 0.
