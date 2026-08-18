# ADR-0030 — The second axis of a focus group: `columns`, not a second group kind

**Date:** 2026-08-15
**Status:** Accepted
**Commissioned by:** the game director, 2026-08-15, after two grid missions flagged the same gap and
both declined to close it inside a feature task. The second one's words are the brief: *"there was
one intercept, now there are two differing only in a direction pair, which is exactly the shape a
general mechanism is owed"* — and it declined because closing it *"changes a module every control
shares and would require re-proving every existing group."*
**Companions:** ADR-0022 Decision 5 (focus-skip: navigation-only eligibility, the active-interaction
exemption), ADR-0016 (the three axes — reachability vs paradigm), the traversal-document-order stage
(`docs/plans/…`, `tools/check_traversal_evidence.py`), `src/focus/focus_graph.luau`,
`src/present/focus_map.luau` (`emitGridGroups`, `linkGridBoundaries`),
`src/controls/virtual_grid.luau`.

## Context — a rectangle described as a ring, twice

`focus_graph`'s `NavigationGroup` has one axis, and an axis there is the string `"vertical"` or
`"horizontal"`. A grid's focus ring has two. So both lazy grids did the same thing: declare a 1-D
group along one axis and **intercept** the perpendicular key.

```
    newVirtualGrid { axis = "y" }      declares "horizontal", intercepts Up/Down   = ±columns
    newVirtualGrid { axis = "x" }      declares "vertical",   intercepts Left/Right = ±columns
```

The rule the two grids settled on is correct and survives this ADR unchanged: **the group's axis is
the LANE axis, always perpendicular to the scroll**, because the band's document order walks a
line's lanes before it moves to the next line, so ±1 in that order is always the neighbouring cell
across a line. It is worth restating that **a virtual LIST transposes the opposite way** — its line
holds one item, so its document order *is* its scroll axis. Copying the list's answer into a grid is
the defect shape ADR-0016 named: *reachable and wrong in shape*. Every cell stays reachable while
the perpendicular key walks one cell instead of one line, so every test passes and the ring visibly
crawls sideways under a player pressing Down.

Two costs made the intercepts worth replacing rather than living with.

- **The move was not routed.** `navigateIntercept` returning `true` suppresses `graph.navigateDirection`
  *and* `handle.focusMoved` (`presenter.luau:2790`, `:2811`), and `focusMoved` is where the shared
  keep-visible lives (`controller.scrollToVisible`). So each grid had to carry a private
  keep-visible — scroll first, then `focusOn` — for one axis and not the other. That asymmetry was
  itself a measured finding: neutering the presenter's keep-visible reddened the Left/Right case and
  nothing else, because Up/Down never reached it.
- **Two implementations of one sentence.** The two grids are one control parameterised by
  `isX`, so the intercept was one function with a `FORWARD`/`BACKWARD` pair — but the *next* 2-D
  control would have written a third, and the eager `UI.Grid` had already written a fourth in a
  different shape (below).

## Decision 1 — an AXIS PAIR on the existing group, never a new group KIND

`NavigationGroup` gains exactly one field:

```lua
columns: number?,  -- an integer >= 1: this order is LINES of `columns` LANES, row-major
```

`axis` keeps its meaning and becomes the **lane** direction; the direction perpendicular to it moves
±`columns`. Nothing else about a group changes, and **every path is gated on `columns` being a usable
integer**, so a group that does not declare one navigates through byte-identical code to the graph
that never heard of a second axis.

A new group *kind* (`axis = "grid"`) was rejected on contact. `AXIS_DELTA[group.axis][direction]` is
read in three places, and a third axis value makes all three answer `nil` — the group would have to
be special-cased everywhere the existing two are shared, which is the opposite of what a general
mechanism is for. More importantly a kind would have had to say what its document order is, and an
axis pair does not have to say: see Decision 2.

## Decision 2 — document order does not fall out of this, because it was never taken away

The single most valuable property of the shape above: **`columns` adds no ordering opinion at all.**
The group's `order` is what it always was — one array, in document order — and `columns` only says
where the lines break in it. Therefore:

- **Tab still walks document order.** `allIds` concatenates group orders; a 2-D group contributes one
  order, unchanged, and `traversalRank` sorts the same members it always did. The
  `traversal-document-order` stage and its live Studio recording are untouched by construction, not
  by inspection.
- **A grid's Tab order walks lanes then lines**, because that is what its order is.
- **The lane axis is unchanged**, including at a line's end: Right off the end of line 1 lands on the
  first cell of line 2, because that is ±1 in document order. This ADR deliberately does not
  re-litigate that into "the arrows stop at the line edge" — it is shipped behaviour, it is what
  row-major means, and it is not the gap that was flagged.

## Decision 3 — perpendicular ENTRY is the near LINE, at the ordinal LANE

`enterGroup` already had two rules, and a 2-D group is the one shape that needs both at once:

- entry **along** an axis lands at the **near end** ("pressing right into a horizontal row means the
  first card, every time");
- entry **across** an axis is **ordinal nearest**, which is what preserves the column — and which is
  ordinal rather than geometric for a measured reason: ordering a row group by pure left-to-right
  geometry once put a **Delete button under the ring** when a pad walked into an editing table.

For a rectangle those compose: **entering downward means the FIRST line, entering upward means the
LAST, and within that line the incoming ordinal is the lane.** Entry along the lane axis is
untouched.

This fixes a defect the 1-D reading had all along. `enterGroup` puts every perpendicular entry at
index 1 of the group it enters, and index 1 of a grid is its **top-left cell** — so a pad pressing Up
from beneath a grid jumped over the entire grid to land on its first cell. The near-end rule the
graph applies *along* an axis was exactly the rule missing *across* one.

## Decision 4 — a ragged last line clamps FORWARD and needs nothing backward

Only the **last** line of a rectangle may be short, so the two directions are not symmetric and
should not be made to look it.

- **Forward**, stepping off the end of the order asks a real question: *is there a line below at
  all?* If there is, this lane simply does not reach it, and the move **clamps to the last cell that
  exists**. If the ring is already in the last line, nothing is below and the move **exits the
  group**. Clamping is not wrapping.
- **Backward** needs no case: every line above a given one is full by construction.

The pre-mechanism intercept answered this by declining (`target > #items` → `return false`), which
meant that on a 10-cell, 4-lane grid **lanes 3 and 4 could not reach the last row at all** without
stepping sideways first. That was a live reachability gap, not a preference.

The clamp is tested on **every** step of the skip walk, not only the first. That is not a
generalisation for its own sake: skipping ineligible cells down a lane can arrive at the ragged line
from above the line before it, and the differential oracle found exactly that walk (seed
`2977402678`) on the first draft.

## Decision 5 — `wrap` still governs the DECLARED axis only

A 2-D group gets no second, unstated wrap policy. The rule was already written for 1-D — *"a group's
own `wrap` governs the DIRECTIONAL arrows along that group's axis and nothing else"* — and it is
applied verbatim: the lane axis wraps if the group says so, and the bottom of a column is an
**exit**, which is what lets a grid hand focus to whatever sits under it.

When a 2-D group does exit perpendicular, **the ordinal it hands on is its LANE, not its flat
index**. Cell 7 of a four-lane grid is lane 3, and handing `7` to a neighbour reading `entry =
"nearest"` would land the ring seven controls along the row below.

## Decision 6 — the rectangle invariant, and the three places that can break it

**The order of a 2-D group is a complete row-major rectangle, and only the last line may be short.**
Every answer above is derived from that sentence, so the sentence needs an enforcement story rather
than a hope. Grepping every caller that rewrites an order found **four** of them, three of which can
leave the shape behind, and all four answer the same way: *a claim about the shape is re-stated with
the shape, or it is dropped.* Failing to the 1-D reading is failing to something merely **old**;
keeping a stale `columns` is failing to something **confidently wrong**, which is worse by a wide
margin. Only `remove` was in the original draft — the other two were found by grepping the callers of
what the change touched rather than by patching the path the mission named.

| Site | What it does | Answer |
|---|---|---|
| `focus_graph.remove` | splices one entry out | drops `columns` |
| `focus_map.filterGroupsHidden` | splices out entries under a hidden root (a losing `ViewThatFits` candidate, an exit transition) — the same hole, one layer up, on every group's way to the graph | drops `columns` |
| `focus_graph.setGroupOrder` | replaces one group's order without restating the group | takes `columns` **as an argument**, exactly as `replaceGroups` takes `rank` and for the identical reason; omitting it clears the field |
| `focus_graph.replaceGroups` | replaces whole groups | re-declares it, no special case needed |

And the contract for consumers: **make a cell unreachable with a focus-skip predicate, never with a
hole.** This is precisely why focus-skip is navigation-only — an ineligible entry stays in the order,
so the lanes stay aligned.

## Decision 7 — the dump reports the lane count

`handle.focusOrder()` gained `columns` on each navigation group, because it is the one fact about a
2-D group that **cannot be inferred from the data already there**: a four-lane grid and a
sixteen-button row are the same sixteen paths. That dump exists because a defect was once found by a
person pressing Tab sixteen times and by none of the instruments; a dump that could not tell those
two apart would have reproduced the same blindness for the arrows.

## Decision 8 — `navigate(±1)` on a 2-D group means down/up

`navigate(delta)` is the unsigned ring verb. It maps ±1 onto the group's axis *because a 1-D group
has only one navigable axis and the verb carries no direction* — a guess, made necessary by a
missing fact. The presenter drives it from the **vertical** arrow (`presenter.luau:2836`, the path a
scope takes when its groups arrived after the push — DB-4's flat-to-grouped upgrade), so on a
LazyVGrid's `horizontal` group that guess sent a DOWN press rightward, and only the intercept was
hiding it. A 2-D group answers all four directions, so the guess is retired for it and the verb
keeps its own reading: down/up. On a LazyHGrid "down" is the lane axis and the same verb steps one
cell, which is correct there too.

## The alternative that was closest — per-line groups linked by exits

The focus graph **already** navigates a 2-D shape, and has since 2026-08-06: `focus_map.emitGridGroups`
decomposes an eager `UI.Grid` into one `horizontal` group **per row**, `entry = "nearest"`,
`containment = true`, linked by `up`/`down` exits, with `linkGridBoundaries` patching the first and
last rows so the grid is not a closed box. A virtual grid could emit the same shape and both
intercepts would delete with **zero** change to `focus_graph` — and therefore nothing to re-prove,
which is a serious argument and was taken seriously.

It loses on four counts, none of which is line count:

1. **It expresses one thing as N things, rebuilt on every scroll.** A mounted window is a dozen to
   thirty lines; the group array would be replaced wholesale on every structural refresh, and the
   `handle.focusOrder()` dump — a diagnostic this framework built *because a person had to press Tab
   sixteen times to see the order* — would become thirty groups of four.
2. **The correctness moves into an exit web the control must rebuild.** `linkGridBoundaries` already
   carries an architecture-review note (M-2) about why array adjacency is only trustworthy for groups
   one derivation emitted in one walk. Every future 2-D control would re-derive that web.
3. **It forces `entry = "nearest"` on every line group**, which changes entry from *outside* the grid:
   a tab bar above it lands the ring on lane N rather than lane 1.
4. **The graph still would not know it is a grid**, so `focusMap()` cannot report it and the next 2-D
   consumer starts from nothing.

The honest measurement, stated because it does not flatter the decision: **this mechanism does not
pay for itself in lines.** Counting executable lines only (block comments excluded), before → after:

```
    src/focus/focus_graph.luau      660 -> 726   (+66)
    src/controls/virtual_grid.luau  633 -> 591   (-42)   the intercept, its FORWARD/BACKWARD pair,
                                                         its private keep-visible, its focusGraph
                                                         reference and its bindFocusGraph seam,
                                                         minus one line back: columns = lanesNow()
    src/present/focus_map.luau      550 -> 551   (+1)
    src/present/presenter.luau     2103 -> 2108  (+5)
    ------------------------------------------------------------------
    net                                          +30
```

And the brief's framing deserves a correction rather than a quiet pass: the two grids are **one
control** parameterised by `isX`, so what was deleted is one 43-line function serving two direction
pairs, not two functions. On a pure line count the intercept was cheaper.

**Read that line count and do not conclude this was a bad trade.** The decision was made on
correctness, and the justification is not the tidiness — it is two reachability defects that were
live in a shipped control and that the intercept could not have found, because an intercept is a
special case and a special case never has to state its rule:

- **Up from beneath a grid landed on the top-left cell.** `enterGroup` put every perpendicular entry
  at index 1, so a pad walking up into a grid jumped over the entire grid to reach its first cell
  (Decision 3).
- **Lanes 3 and 4 of a ragged grid could not reach the last row at all.** The intercept declined a
  target past the end of the collection, so on a 10-cell four-lane grid the bottom row was
  unreachable from half the columns without stepping sideways first (Decision 4).

Both are the class this project calls *passes every test and feels broken to a player*. Neither was
in the brief; both fell out of having to write the rule down in a form that answers every direction
rather than the one the control happened to catch.

The rest is what a general mechanism buys anyway. One mechanism instead of a per-control convention.
A **routed** focus move, so the shared keep-visible — and the armed-aim sync, and every other
consumer of a routed move — applies to both axes instead of one, and the control's private
scroll-then-focus goes away rather than moving. A structural guarantee the intercept could not make:
the graph can only aim at what is in the order, so aiming at an unmounted cell stopped being possible
rather than being checked for. The second axis visible in the dump. And a contract the next 2-D
control declares in one field instead of re-deriving.

**What this ADR deliberately does not do:** convert `emitGridGroups` to `columns`. The eager grid's
decomposition works, is proved, and re-proving it is a mission of its own. It is a candidate
follow-up, not a smuggled refactor.

## Verification

- **The acceptance test is the deletion.** `src/controls/virtual_grid.luau` contributes no
  `navigateIntercept` and no `bindFocusGraph` at all, and `tests/virtual_grid_input.spec.luau` and
  `tests/virtual_hgrid.spec.luau` — which pin "Down moves a whole LINE, not one cell", its transpose,
  and both keep-visible cases — pass with their navigation cases **unmodified**. The live client was
  checked for the same thing rather than the working tree: the running datamodel's `virtual_grid`
  carries no `navigateIntercept` declaration and no bundle entry.
- **`tests/focus_grid_axis.spec.luau`**: 26 cases, including the NULL HYPOTHESIS (a group with no
  `columns` walks byte-identically to one that never heard of the field), the refusal set, all three
  splice sites, and a **differential oracle** — a `(line, lane)` coordinate model written from the
  decisions above, run against the graph over 300 seeded grids and walks, with a negative control
  asserting the corpus still rejects the list's one-cell answer. The oracle earned its place twice.
  It found on the first run that the ragged clamp fired only on the opening step (seed
  `2977402678`), which no hand-picked case had covered; and when that same defect was re-injected as
  mutation M4, the oracle was still the **only** thing in the whole suite that reddened. The case
  named "the ragged clamp still fires when the walk REACHED the last line by skipping" was written
  from that seed afterwards — the corpus finds, a sentence explains.
- **Clean-room control** (a second agent was live in this tree, so the headline number is measured
  against HEAD in a separate worktree): HEAD unmodified = **5395 passed / 0 failed**; HEAD + only this
  change = **5421 passed / 0 failed**, which is +26 and the new cases exactly. The shared working tree
  with both agents' work runs 5440 / 0.
- **Mutation battery**: 18 mutations over the four files this touches, recorded in
  `artifacts/two-dimensional-focus/mutation-battery.md`. Seventeen reddened, each naming its own
  case; the gate mutation (M13 — read every 1-D group as a rectangle of one lane) reddened 17 cases
  across `navigation_groups`, `focus` and the entry rules, which is what makes "gated on `columns`"
  a checked claim rather than a described one. It produced two findings of its own:
  - **M3** — dropping the clamp's guard made the perpendicular walk **non-terminating** rather than
    reddening a case, so the loop is now bounded by the line count structurally instead of by its
    exit conditions.
  - **M8 is a NULL RESULT and is recorded as one.** Removing the clamp on `enterGroup`'s target
    index reddened *nothing* — because it was the same clamp twice: `nearestEligible` already clamps
    its own start into the order. The redundant clamp was **deleted**, not covered with a test that
    would only have re-proved `nearestEligible`. The ragged-entry behaviour it appeared to protect is
    still held by M6 and M7, both of which redden it.
- **Live**: `artifacts/two-dimensional-focus/live-studio.md` — both grids driven on a real Studio
  place through the real `InputAction`s, read off the painted focus ring, with a staleness check on
  the datamodel's source and a positive control in the transcript.
- **Consumer rider**: `games/RascalRally/code/tests/facet_focus_grid_axis_contract.spec.luau` — this
  game mounts no lazy grid and no focusable grid cell, so the rider is the tripwire that asserts it
  against a real shipped screen, plus a positive control proving that game's own focus dump would
  report a lane count if one existed.
