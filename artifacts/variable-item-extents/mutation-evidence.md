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
