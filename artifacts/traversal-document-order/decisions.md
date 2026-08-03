# Decision packets — `traversal-document-order`

Evidence-backed decisions taken during this stage that a later reader would
otherwise have to re-derive.

---

## TDN-1 — every focusable Grip traverses in document position; no exceptions

**Question.** Should a Grip's traversal position depend on why it is focusable?

> **The premise this decision was first framed on was wrong, and the correction is
> recorded rather than quietly dropped.** It was put to the director as "Grips are
> not only the Slider track — `table.luau` and `virtual_list.luau` make
> **column-resize handles** focusable, so a 6-column table gains six Tab stops ahead
> of its rows." That is **false at this source**. Re-reading the call sites:
> `table.luau:1200` and `virtual_list.luau:1303` are `UI.Button`s (a column's sort
> header and a row's hit target), not Grips; and Table's actual resize Grip
> (`table.luau:1075`) has carried **`focusable = false`** since the stage that made
> it pointer-only — its comment says so: *"POINTER ONLY NOW. The grip used to be
> focusable so a gamepad could Adjust-resize from it, which meant two focus stops
> per column."*
>
> The **only** focusable Grips that ship are `newSlider`'s track and `newRating`'s
> strip — both **value controls**, both a single focus stop for the whole control.
>
> The decision below is unchanged, and is now strictly better supported: option 2's
> distinction has no shipped case to serve, and option 1's stated cost (resize
> handles crowding a Tab chain) **does not exist**. Nothing in the implementation
> depended on the wrong premise — the rule is "every focusable Grip", which is
> correct either way — but a later reader sizing a change against "tables put
> handles in the Tab order" would be reasoning from a fiction.

**Options weighed.**

1. All Grips move. One rule, no special cases.
2. Value-control Grips move, resize-affordance Grips keep the deferral. A Grip's
   traversal position would depend on *why* it is focusable — a second rule to
   explain, to document, and to test, and a classification the blueprint layer does
   not carry. (With the premise corrected, this option has **no shipped case at
   all**: every focusable Grip is already a value control.)
3. All Grips move by default, and a control opts its own out via the same public
   `traversalPriority` an author gets.

**Decision (director, 2026-08-03): option 1.** One rule, no exceptions.

**Reasoning.** Option 2 reintroduces exactly the category of hidden, purpose-derived
special case that produced this defect: the original deferral was also a reasonable
rule applied to the wrong verb, and it survived a gate and three fresh-context
reviews because nothing stated it in one place. Option 3 is option 1 plus an opt-out
that no measurement has shown is needed. If some future Grip-bearing control does
want to sit late in a Tab chain, option 3 is a one-line follow-up **using shipped
public API** and needs no framework change — which is the point of shipping
`traversalPriority` in the same stage.

---

## TDN-2 — the rank is a sort key, not a second order

**Constraint.** Constitution §9: *"One focus map, read two ways. Directional Navigate
and linear Traverse walk the same scope order. A second order, derived from Instances
or maintained alongside, is the defect — the two would disagree the first time a node
was hidden."*

**Decision.** The presenter supplies `FocusScope.traversalRank : { [path]: number }`.
`graph.traverse` takes its **members** from `allIds(scope)` — unchanged — and sorts
that list by rank. Membership, eligibility, hidden-filtering, wrap, trap, and the
enter-at-the-end-you-came-from rule are all untouched.

**Why this satisfies the rule rather than evading it.** The named failure mode is a
*membership* disagreement. A rank map cannot produce one, because it is never read as
a source of members: a path in the rank map that is not in `allIds` is invisible, and
a path in `allIds` that is not in the rank map still traverses (it sorts stably where
it already was). The alternative considered — carrying a document index on each
`OrderEntry` — would have forced every bare-string entry into table form across the
whole focus surface, which is a larger blast radius for the same answer.

**Falsifiable consequence.** A scope with no rank map (`traversalRank == nil`)
traverses byte-identically to pre-stage behavior. That is what makes TD-7 — a
consumer-supplied `navigationGroups` keeping its declared order verbatim — a real
assertion rather than a restatement.

---

## TDN-3 — `traversalPriority` is construction-only

`focusable` beside it is reactive, so the inconsistency is deliberate and worth
stating. No shipped control needs to move a control's Tab position at runtime, and
constitution §5 puts a prop that answers *what the node is* on the construction-only
side. Per §4 a reactive value bound to it is an **immediate refusal naming the
rebuild idiom**, not a silently ignored binding.

Adding reactivity later is a compatible widening (ADR-0011); removing it would not
be. The narrow default therefore ships first.

---

## TDN-4 — this stage builds on an uncommitted Step 8

**Observed.** At stage start `git status` reported 33 modified and 6 untracked files:
the entire `desktop-keyboard-navigation` stage is in the working tree, uncommitted,
on top of `aeffc68`.

**Consequence.** A stage diff cannot be taken against `HEAD` — it would report Step 8
and this stage as one change, and the fresh-context verifier would be handed the wrong
blast radius.

**Action taken.** `git stash create` produced dangling commit `f1f0454`, tagged
`luauui-step8-baseline`, capturing all **tracked** files at Step 8 completion without
touching the working tree or the index. Stage diffs are taken against that tag.

**Limit, stated rather than papered over.** `git stash create` does not snapshot
untracked files, so the six new Step 8 files — including
`tests/keyboard_navigation.spec.luau` and `artifacts/desktop-keyboard-navigation/` —
have no baseline in the tag and appear as additions in any diff against it. Where this
stage edits one of those files (it edits the test spec), the relevant before-state is
recorded in `step8-debt.md` instead.

**Not decided here.** Whether to commit Step 8 is the user's call and was not taken
autonomously.

---

## TDN-5 — two Step 8 gate checks were stale at stage start, and both were green-by-accident

Running `tools/gate.sh desktop-keyboard-navigation` at the **unmodified** pre-change
source returned `FAIL_RECOVERABLE`, not the `exit 0` the stage was recorded as
achieving. Two checks:

**(a) `adjust-claim-is-subtree-scoped` greps a renamed test.** The check greps
`"a sibling button.s arrows reach the game instead of firing a dead Adjust"`. The test
in `tests/keyboard_navigation.spec.luau:616` is named
`"a sibling button's arrows fire no dead Adjust"`. The test exists and passes; the
grep does not match it. Renamed after the gate last ran.

**(b) `rascalrally-consumer` runs a game test that asserts a pre-Step-8 world.**
`games/RascalRally/code/tests/luauui_closed_key_contract.spec.luau:134` proves its own
mutation by asserting that a surface presented **without** `gameplayGuard` *does*
claim `Space` for Activate. Step 8 made the Space binding conditional on
`keyboardNavigation`, which **defaults to false** at the presenter (the director's
2026-08-03 fix for Space stealing the avatar's jump). The game rig
(`presenterWorld()`) constructs `newPresenter` with no opts, so no Space binding can
exist and the mutation-proof half cannot pass.

**Both are Step 8 consumer/gate debt, not defects introduced by this stage**, and both
are recorded here because the stage is recorded as having passed with them present.
Fixes and evidence in `step8-debt.md`; ledger row TD-16.
