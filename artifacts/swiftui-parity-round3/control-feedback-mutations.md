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

## The showcase fixture

Eight mutations against `examples/gallery/scenarios/sensory_feedback.luau`, run
over `control_feedback` + `gallery_demo_picker` + `examples_gallery` +
`overflow_sweep`. Six bit immediately; two did not, and both are covered now.

| # | Mutation | Case that reddened |
|---|---|---|
| F1 | the sensation column claims the wrong effect | the sensation column is the SHIPPED map, not a story about it |
| F2 | Mute stops declaring `none` | pressing the five leaves writes four lines and Mute writes none |
| F3 | the cascade panel declares a different verb | the CASCADE panel: three controls, one declaration, one verb |
| F4 | the leaf chip row stops wrapping | no diagnostic, in any package…; scenario 'sensory_feedback': the solver reports NOTHING… |
| F5 | the cascade row stops wrapping | (both of the above) |
| F6 | the page stops scrolling (a VStack instead) | (both of the above) |
| F7 | the subscriber's `reason` filter deleted | *(nothing, at first)* → **a NON-activation event on the same surface writes no line** |
| F8 | the subscriber's path filter deleted | *(nothing, at first)* → **a press on ANOTHER surface of the same presenter writes no line** |

**F7 and F8 are the same lesson twice.** Both filters are defensive against the
rest of the showcase — a toast retiring elsewhere, the demo picker's own chip
strip — and the headless drive presented exactly one surface and emitted only
activations, so neither filter was ever exercised. The fix in both cases was to
build the world the filter exists for: emit a non-activation event through the
presenter's own registration point, and present a second surface on the same
presenter and press it.

## The Rascal Rally contract rows

Six mutations, each applied to the LuauUI source the game requires directly, the
game suite run, and the source restored. Baseline: **3170 passed**, 3 failed
(all in a concurrent agent's live solver/text work, identical names before and
after every mutation).

| # | Mutation | Case that reddened |
|---|---|---|
| R1 | the adapter defaults to ENABLED | carries the haptics adapter, and it is DEFAULT OFF; a default-off adapter ignores the new attribute entirely |
| R2 | the presenter stops stamping `reason = "activation"` | this game's activate now says WHY it fired, and the live bus consumer does not care |
| R3 | the renderer pushes the verb only when non-nil | this game's own buttons carry no verb, and the seam is still exercised |
| R4 | the mixed-form refusal deleted | ...and refuses the two shapes that would be ambiguous |
| R5 | the duplicate-`activation` refusal deleted | ...and refuses the two shapes that would be ambiguous |
| R6 | the closed-taxonomy refusal deleted | the framework carries the control form, with the same closed vocabulary plus `none` |

**R1 found a seventh check that proved nothing** on its first pass. "A default-off
adapter ignores the new attribute entirely" did NOT redden when the default was
flipped to enabled, because Lune has no `Enum`: the adapter failed to resolve an
effect type and built nothing *even while enabled*, so the assertion held for the
wrong reason. The row now injects the `enums` seam, and R1 reddens both
default-off rows.
