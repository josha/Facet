# Time-based easing — mutation evidence

*A check never seen to fail is decoration.*

## Method

Harness: a Python driver (`mutate_easing.py`, kept in the session scratchpad —
it is the same shape as `artifacts/rulings-1-and-5/mutate.py`). For each mutation
it asserts the anchor appears **exactly once** in the target (otherwise
`SETUP-FAIL`, never a silent multi-site patch), copies the file to the scratchpad,
patches the working copy, runs `lune run tests/run_one motion_tween`, strips ANSI,
collects every line beginning `✗`, then restores from the copy in a `finally` and
**re-verifies the SHA-256** before moving on.

No `git reset`, no `git checkout`, no `git stash` at any point — other agents had
uncommitted work in this tree throughout.

**Baseline: 29 passed, 0 failed.**

## Result: 18 of 18 bite

| # | mutation | file | verdict | a NAMED case that reddened |
|---|---|---|---|---|
| M1 | elastic period reverts to Penner's `0.3` — the twin drifts off the engine | `curves.luau` | **BIT** | matches the frozen engine corpus at every sampled alpha |
| M2 | `back` overshoot constant `1.70158` → `1.5` | `curves.luau` | **BIT** | matches the frozen engine corpus at every sampled alpha |
| M3 | `sine` silently becomes linear | `curves.luau` | **BIT** | matches the frozen engine corpus at every sampled alpha |
| M4 | direction `out` stops mirroring: every out-curve becomes an in-curve | `curves.luau` | **BIT** (3 red) | matches the frozen engine corpus at every sampled alpha |
| M5 | negative-zero normalisation removed | `curves.luau` | **BIT** | every style is anchored at both ends, in all three directions |
| M6 | an out-of-range alpha extrapolates instead of clamping | `curves.luau` | **BIT** | clamps an alpha outside [0,1] rather than extrapolating |
| M7 | the default direction flips from `out` to `in` | `curves.luau` | **BIT** | registers, resolves, defaults direction to out, and freezes the result |
| M8 | an unknown easing style is accepted (and evaluates as linear) | `curves.luau` | **BIT** | refuses an out-of-range duration, an unknown style and an unknown direction |
| M9 | an out-of-range or non-finite duration registers | `curves.luau` | **BIT** | refuses an out-of-range duration, an unknown style and an unknown direction |
| M10 | an inline spec table at a call site stops being refused | `curves.luau` | **BIT** | refuses an inline spec table and names registerCurve instead |
| M11 | the tween takes twice its declared duration | `motion.luau` | **BIT** (10 red) | ARRIVES EXACTLY ON TIME, and not one frame early |
| M12 | the curve is ignored mid-flight; every tween is linear | `motion.luau` | **BIT** (2 red) | a curve is not a straight line — quad/out is ahead of linear at the midpoint |
| M13′ | a re-aim inherits a stale origin, so the value jumps | `motion.luau` | **BIT** | a re-aim mid-flight redirects from where it IS, with no jump |
| M14 | `setVelocity` silently does nothing instead of raising | `motion.luau` | **BIT** | refuses setVelocity: a curve's speed is its shape |
| M15 | `getVelocity` reports the average, not the instantaneous slope | `motion.luau` | **BIT** | reports the curve's INSTANTANEOUS slope, not its average |
| M16 | the closed-opts guard is removed | `motion.luau` | **BIT** | refuses an unknown curve, an inline spec, and a non-finite initial |
| M17 | the installed engine evaluator is ignored; the twin always runs | `motion.luau` | **BIT** (2 red) | routes every evaluation through the installed evaluator |
| M18 | the evaluator is captured at construction, so a later bind cannot upgrade it | `clock.luau` | **BIT** (2 red) | routes every evaluation through the installed evaluator |

## The one that survived, and what it was worth

**M13 (first round) — NO-BITE.** Re-basing the ramp's origin on `target` instead
of `current` at every re-aim. The suite stayed green.

This was **a real hole in the checks, not a non-mutation.** The original case
("a re-aim mid-flight redirects from where it IS, with no jump") asserted two
things: that `setTarget` does not move the value (true under the mutation, because
aiming writes nothing — the signal is only written by the clock's commit phase),
and that the value reaches 0 at the right time (also true under the mutation,
because the destination and the duration are untouched).

The defect lives **entirely in the first painted frame after the interrupt**: with
a stale origin the value jumps from 50 to ~97 on the next step and then eases back
down. An endpoint-only check cannot see it, and this is a defect a player sees
immediately — a card that visibly snaps backwards when you interrupt it.

The case now samples the frame after the aim and asserts the value moved *toward*
the new target *from where it was* (`< mid` and `> mid - 10`). Re-run as **M13′:
BIT**, reddening that named case.

That is the whole argument for mutation testing on this feature: the interruption
behaviour is the part of a tween most likely to be got wrong, and it was the one
part the suite could not see.

## Not mutated, and why

The clock-entry / leak cases (`a scope owns the clock`,
`build/aim/settle/dispose churn returns the graph to baseline`) are not mutated
here. They assert `core:counters()` equality against a baseline and are already
mutation-proven for the spring path in `motion_clock.spec.luau`; the tween reaches
them through the *same* `newValue` shell, so a mutation would be testing borrowed
code. The tween-specific claim — that acquiring a clock entry inherits the scope
requirement — is structural: `newTween` cannot obtain an entry except through
`newValue`, which calls `internals.own` before the verbs are attached.
