# Mutation evidence — the per-control sensory hook

Every check in `tests/control_feedback.spec.luau` was proved to BITE: the
mutation below was applied to the shipped source, the spec was run, the named
case reddened, and the source was restored. A check never seen to fail is
decoration (`docs/lessons/` — the gate-integrity sweep), and this round found
**two** that were not biting on the first attempt. Both are recorded here rather
than quietly fixed, because the way they failed is the useful part.

Runner: `lune run tests/run_cf_tmp` (a scratch runner over this one spec;
deleted after the round). Baseline: **34 passed, 0 failed**.

## The two checks that did not bite, and why

**M4 — `activation` type check.** Deleting the "must be a string" guard changed
nothing. `activation = true` still fell through to the *unknown-verb* refusal
(`TYPE_SET[true]` is nil), which also contains the word "activation" — the only
thing the assertion looked for. So the case was satisfied by a different error.
The assertion now names the message an author can act on ("must be a string",
and the type they passed), and the mutation reddens it.

**M13 — the renderer's unconditional push.** Restricting the seam to a non-nil
verb changed nothing, because the recycling case was not recycling: the renderer
CREATES before it PARKS, so the pool has nothing to hand out until the *second*
structural change, and both of the test's buttons were fresh instances. It was a
test of two creates wearing the name of a recycling test. Rewritten over a keyed
`ForEach` with two successive item swaps, and `stats().recycled > 0` is now
asserted so it cannot silently degrade back.

## The round

| # | Mutation | Where | Case that reddened |
|---|---|---|---|
| M1 | closed-taxonomy refusal for `activation` deleted | `present/feedback.luau` | refuses a verb outside the closed twelve, listing the whole vocabulary |
| M2 | mixed-form refusal deleted | `present/feedback.luau` | refuses MIXING the two forms in one spec |
| M3 | empty-spec refusal deleted | `present/feedback.luau` | refuses a spec that declares NEITHER form |
| M4 | `activation` type check deleted | `present/feedback.luau` | refuses a non-string activation, NAMING the type *(see above)* |
| M5 | duplicate-`activation` refusal deleted | `blueprint.luau` | refuses a SECOND activation on the same node |
| M6 | cascade drops the inherited value | `mount.luau` | INHERITS…; a NEARER declaration overrides…; crosses a When; crosses a ForEach; does NOT spend the seam… (5) |
| M7 | cascade prefers the FARTHER declaration | `mount.luau` | a NEARER declaration overrides a farther one |
| M8 | field stamped on undeclared nodes too | `mount.luau` | an undeclared tree carries the field NOWHERE (+2) |
| M9 | control form also handed to `core:observe` | `mount.luau` | buys NO observer… (+8, the nil trigger faults the mount) |
| M10 | presenter ignores the declared verb | `present/presenter.luau` | a declared control emits ITS verb (+2) |
| M11 | presenter drops the `none` guard | `present/presenter.luau` | `none` emits NOTHING |
| M12 | presenter stops stamping `reason = "activation"` | `present/presenter.luau` | an undeclared control still emits `activate` (+1) |
| M13 | renderer pushes only a non-nil verb | `render/renderer.luau` | a recycled instance never inherits the PREVIOUS control's verb *(see above)* |
| M14 | renderer pushes for EVERY class | `render/renderer.luau` | does NOT spend the seam on nodes that cannot be activated |
| M15 | `pressEffectFor` ignores the verb | `client/haptics.luau` | a DECLARED button gets the effect its verb maps to (+2) |
| M16 | `pressEffectFor` treats `none` as a press | `client/haptics.luau` | `none` leaves the button with NO effect reference |
| M17 | `decorate` SKIPS instead of clearing | `client/haptics.luau` | `none` leaves the button with NO effect reference |
| M18 | press effects not pooled | `client/haptics.luau` | effects are POOLED per verb: ten commit buttons share one effect |
| M19 | bus stops ignoring `reason = "activation"` | `client/haptics.luau` | STILL PLAYS NOTHING for an activation |
| M20 | adapter defaults to ENABLED | `client/haptics.luau` | DEFAULT OFF: a disabled adapter decorates nothing |
| M21 | attribute name drifts by one character | `client/screen_target.luau` | the two ends of the attribute channel spell it the SAME |

M16 and M17 both redden the same case, deliberately: it is one claim ("a `none`
control ends up with no reference") with two independent ways to break it — the
resolver saying the wrong thing, and the decorator failing to act on the right
thing. The assertion starts the button **already decorated** so that the second
mutation cannot pass by doing nothing.
