# Mutation evidence — variable item extents (2026-08-14)

Every check below was seen to FAIL before it was trusted. One edit at a time,
the source restored in a `finally`, the named cases that reddened recorded. A
check never seen to fail is decoration.

Harness: `tests/run_one.luau` (one spec, for this loop) driven by a script that
applies the edit, runs, and restores.

## Round 1 — the pure index (`src/virtual_extents.luau`, spec `virtual_extents`)

17 cases. Every mutation reddened at least one NAMED case; the source was green
again after each restore.

| mutation | cases that reddened |
|---|---|
| M1 prefix sum forgets the gap | offsetOf sums every preceding extent plus one gap each · window covers exactly the slots the viewport touches · degenerate inputs answer rather than throw · every question agrees when every extent is equal · variable boundaries land on the item edge |
| M2 content keeps the trailing gutter | offsetOf sums every preceding extent · degenerate inputs answer rather than throw · every question agrees when every extent is equal |
| M3 window ignores the viewport's trailing edge | window covers exactly the slots the viewport touches · every question agrees · mid-slot, the variable rule windows one MORE row · windowing a 10,000-item list reads a logarithmic number of extents |
| M4 slotAt snaps to the leading edge, not the midpoint | every question agrees · slotAt counts the whole slots whose midpoint the offset has passed |
| M5 the search walks the list instead of halving it | windowing a 10,000-item list reads a logarithmic number of extents |
| M6 uniform window drops overscan | window reproduces floor/ceil + overscan, the pre-feature formula · every question agrees |
| M7 variable boundary forgets to split the gutter | every question agrees · variable boundaries land on the item edge, gutter split |

M5 is the one that matters most: it is the "correct answer that destroys the
point" mutation — a linear scan gives every right number and reddens only the
boundedness case.

## Round 2 — the control (`src/controls/virtual_list.luau`, spec `virtual_list_variable_extents`)

15 cases.

| mutation | cases that reddened |
|---|---|
| C1 the window ignores the index and divides by one pitch | a viewport inside ONE tall row windows that row alone |
| C2 every row's box is the FIRST row's extent | each row's box is its OWN extent · the gutter is dead space between ragged slots |
| C3 every row sits at the canvas origin | each row's box is its OWN extent · the gutter is dead space · the insertion slot snaps on ragged midpoints · a per-item function returning one constant is IDENTICAL to the uniform list |
| C4 the scroll anchor never re-applies | the item at the top of the viewport stays at the top |
| C5 the slot declaration is list-wide again | the declared slot is PER ROW: the guard names that row's own number |
| C6 an invalid per-item extent is accepted | refuses a per-item extent that is not a positive number, naming the row |
| C7 validation happens only inside the memo (the quarantined channel) | refuses a per-item extent that is not a positive number, naming the row |
| C8 the canvas spans count x the first extent | the PAINTED canvas spans the running total, not count x one extent |
| C9 the insertion slot is off by a row | the insertion slot snaps on ragged midpoints |
| C10 keep-visible measures the FIRST row's extent | keep-visible measures the row's OWN extent, not an average |

**C8 originally reddened NOTHING.** The canvas `Dim` — the number the renderer
maps to the engine's `CanvasSize`, and therefore the only one the player's
finger can feel — was not asserted anywhere: the "content extent" case measured
the framework's scroll CLAMP, which reads the index through a different memo. A
canvas spanning `count × oneExtent` would have let the engine scroll to a place
the framework refuses to window, and every test would have stayed green. The
case `the PAINTED canvas spans the running total` was added for it, on the
SOLVED box rather than the memo, and C8 then reddened it.

C7 is the channel check: with the construction-time validation removed the
mistake still fails, but as "attempt to iterate over a nil value" three frames
away — the core quarantines a throwing memo body. The case asserts the row's
KEY is in the message, so only the construction channel satisfies it.

## Round 3 — the Rascal Rally consumer (`games/RascalRally/code/tests/luauui_closed_key_contract.spec.luau`)

The rider: LuauUI and Rascal Rally move together, so "the uniform path is
unchanged" is a claim that is worth exactly one test on an existing consumer.
The game's racer list is a `newVirtualList` on the deprecated spelling with a
LIVE extent (theme metrics × orientation).

| mutation | cases that reddened |
|---|---|
| R1 the dump always claims the VARIABLE arithmetic | newVirtualList: this game's racer list is still on the UNIFORM arithmetic |
| R2 the UNIFORM content extent regains its trailing gutter | newVirtualList accepts `rowGap`, and the gutter stays OUT of the row · no declared axis is still VERTICAL · this game's racer list is still on the UNIFORM arithmetic |
| R3 a live uniform extent stops tracking its Readable in the INDEX | newVirtualList: this game's racer list is still on the UNIFORM arithmetic |

**The first attempt at this round reddened NOTHING, and the test was wrong, not
the mutations.** R3 freezes `itemExtentIn` on its first read — the list would
stop re-windowing after a rotation, which is precisely what this consumer would
feel — and the case stayed green because it asserted only `dump().rowHeight`,
which reads the spec's Readable DIRECTLY and never goes through the offset
index. The case now asserts the CONTENT EXTENT at the portrait metric too, and
R3 reddens it.

(R1/R2's first spellings were bad mutations rather than a bad test: R1 forced
"uniform", which is what this consumer already is, and R2 mutated the VARIABLE
content formula on a list that uses the uniform one. Recorded because "the
mutation did not bite" has two causes and only one of them is the test's
fault.)

Standing pre-existing reds in both suites during this work, identified by name
and belonging to the concurrent solver/shrink change, not to this one:
`...and the shrink pass reaches the MEASURE pass` and `a ticker entry's target
NAME may truncate` (Rascal Rally); the `stack_distribution` / `layout_vocabulary`
shrink cases plus `haptics` / `control_feedback` / `render_target_contract`
(LuauUI).

## Final verification (2026-08-14)

Every spec this work touched or could plausibly have broken, run individually:

| spec | result |
|---|---|
| `virtual_extents` | 17 passed |
| `virtual_list_variable_extents` | 17 passed |
| `virtualization` | 8 passed |
| `virtual_list_row_gap` | 9 passed |
| `virtual_list_axis` | 35 passed |
| `virtual_list_slot_guard` | 12 passed |
| `virtual_list_focus_policy` | 18 passed |
| `virtual_list_input` | 23 passed |
| `virtual_list_row_actions` | 73 passed |
| `collection_list` | 40 passed |
| `examples_gallery` | 133 passed |

Whole suites, with FIVE other agents committing into the same tree during the
work — the reds are identified by NAME and every one of them lives in a file
another agent has open (`row_actions.luau`, `solver.luau`, `renderer.luau`,
`mount.luau`, `src/core/*`, the perf lab, `composition`):

* **LuauUI:** 5046 passed / 7 failed — `a viewport change DROPS the overlay's
  stale reservation`, `the full resize pass leaves the workload MOUNTED`, `the
  round trip costs NO extra solve` (the concurrent measure/publish work), `the
  live repository passes every registration rule` + its two `extension_checker`
  siblings (`composition.ZONES` undocumented), `the forwarded tap is scoped to
  THIS row` (ruling 6), `an unknown group field`.
* **Rascal Rally:** 3165 passed / 3 failed — `...and the shrink pass reaches the
  MEASURE pass`, `the surface still RESPONDS to each geometry fact`, `a ticker
  entry's target NAME may truncate` (all the concurrent solver/shrink change).

Baselines at the start of this work were 4856 (LuauUI) and 3160 (Rascal Rally),
both green; the tree gained ~190 and ~5 cases from concurrent agents while this
ran, which is why neither total is comparable to its baseline by subtraction.

---

# Stage 2 — measured extents (2026-08-15)

Sixteen mutations, run in an isolated `git worktree` at HEAD carrying only this
mission's files, so a mutation could never touch the shared working tree four
other agents are live in. Runner `_m` = the measured spec + the variable spec +
the slot guard + `collection_list` (90 cases green). Runner `_mg` = the overflow
sweep + `examples_gallery` + `gallery_demo_picker` (217 green).

**TWO MUTATIONS SURVIVED THE FIRST ROUND, AND BOTH FOUND HOLES RATHER THAN
CONFIRMING TESTS.** They are M-11 and M-13 below; both are listed with the round
they were caught in and the check that was written for them.

| # | mutation | result |
|---|---|---|
| M-01 | `estimatedItemExtent` assert → `true` (never required) | 1 failed ✔ |
| M-02 | the "refused on every other form" assert → `true` | 1 failed ✔ |
| M-03 | the `"measured"` sentinel compares against `"MEASURED"` | 16 failed ✔ |
| M-04 | `extentsFor` ignores the cache: `out[i] = estimate` always | 10 failed ✔ |
| M-05 | `measureWindow` walks the whole DATA instead of the window | 12 failed ✔ |
| M-06 | scroll anchoring re-gated to the declared path only | 1 failed ✔ |
| M-07 | the epoch is bumped whether or not anything changed | 1 failed ✔ |
| M-08 | the measurement cache is never pruned with the data | 1 failed ✔ |
| M-09 | the `fill`-main-axis refusal is bypassed | 1 failed ✔ |
| M-10 | `measureWindow` reads a wrong `Content` path | 10 failed ✔ |
| M-11 | `filedBy` removed from the lying-extent finding | **round 1: SURVIVED** → round 2: 1 failed ✔ |
| M-12 | the axis is ignored: always read `rect.h` | 1 failed ✔ |
| M-13 | no rounding at all: `px = raw` | **round 1: SURVIVED** → round 2: 1 failed ✔ |
| M-14 | rounding kept, the `math.max(1, …)` zero floor removed | 1 failed ✔ |
| M-15 | `measured_extents` removed from the overflow sweep's surfaces | 2 failed ✔ |
| M-16 | `measured_extents` removed from `scenarios/init.luau` ORDER | 3 failed ✔ |
| M-17 | the picker entry removed from `demo_picker.DEMOS` | 2 failed ✔ |

## M-11 — the hole that mattered

Stripping `filedBy` from the lying-`itemExtent` finding changed nothing, because
by then measured mode had stopped declaring a `virtualSlot` at all and the only
witness was reaching the *generic* zstack finding instead. So the solver fix this
mission made had **no test on the path it was made for** — the DECLARED one.

That fix is real and was found by measurement, not by reading: with incremental
layout on (the default), a `newVirtualList` whose per-item extent re-derived
**correctly** went on reporting the OLD number forever, because the finding is
filed by the row ZStack and names its content child, and the replay gate asks
whether the node that FILED it was skipped. The row was walked and filed nothing;
the child landed on the rect it already had and was skipped; the stale finding was
copied forward every solve. With `incrementalLayout = false` it cleared on the next
solve — which is how it was attributed.

A stale finding is the worst possible failure of this channel: `overflow_sweep`
fails the suite on it, so it reports a defect that is already fixed. The witness
now lives on the declared path, where the defect lives:
`tests/virtual_list_slot_guard.spec.luau`, "A FIXED ROW STOPS BEING REPORTED".

## M-13 — the check with no witness

The measurement is rounded to whole px and floored at 1, and neither half had a
test. Both are load-bearing: whole px because sub-pixel measure noise would
otherwise write, invalidate the index and re-solve every frame forever; the floor
because the running-offset index searches a strictly-increasing prefix sum and a
run of zero-extent rows makes several slots share one offset. `tests/
virtual_list_measured_extents.spec.luau`, "a fractional measure is rounded to whole
px, and a zero one is floored to 1", now covers both — M-13 and M-14 are the two
halves, mutated separately.
