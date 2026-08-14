# Variable item extents — the decision, what it cost, and what is left

**Ruled 2026-08-13** (`docs/handoff/2026-08-13-rulings-needed.md` ruling 7, option
A: *build variable item extents*). **Stage 1 built 2026-08-14.**

---

## The measurement that bought it

The widened overflow sweep — 42 surfaces × 8 viewports × 4 text preferences —
found a `row_actions` row declaring `itemExtent = 84` and measuring **88 at the
DEFAULT text preference**, and **249 in the same 84px slot** on a 320×640 phone
at `preferredTextOffset = 14`. The class is "the lying `itemExtent`": 184
findings, 3 distinct defects, invisible to the sweep from the hour its guard
shipped.

`newVirtualList` windows by `index × itemExtent`. That is O(1) and exact **only
because the extent is one declared number** — and the control makes the CONSUMER
predict it, for every live fact the row reads. The perf lab's own `heightFor` is
the case study: it learned the viewport width, then the type scale, then the
theme insets, each one *after* a device pass caught rows painting over each
other, and never learned the accessibility text preference at all. Four inputs,
three added post-mortem.

This project binds itself to the four measured offsets `{0, 4, 10, 14}` and to a
~1.4× localization expansion rule. One number cannot satisfy either.

---

## The two recorded candidate designs, read against that measurement

`docs/reference/swiftui-parity.md` §4.2 records both, with what each gives up.
Neither survives contact unchanged, and the reason is a constraint neither of
them was written against.

### Candidate 1 — "estimate and correct"

> Assume an estimated extent for unmeasured items; replace each estimate with the
> real measurement as the item enters the window; re-derive the running offsets.
> **Cost:** the scroll thumb jumps. Total content extent is a moving estimate, so
> the scrollbar's proportions change under the player's finger, and a long scroll
> back to a place they have been changes where that place is.

### Candidate 2 — "measure up front"

> Measure every item's extent at mount, then window exactly.
> **Cost:** laziness survives for instance creation but not for measurement. A
> 10 000-item list pays a full measure pass at mount — text measurement is the
> expensive part and it is exactly what would run.

### Why candidate 2 is dead, not merely expensive

**Virtualization must stay bounded.** That is not a preference here: the perf lab
breaks its window on purpose and *requires* the scenario to REFUSE
(`tests/perf_lab.spec.luau`, the declared-window-fault negative control). An
implementation that measures every row to lay out the list has not made
virtualization slower — it has deleted the property the construct exists for. A
design whose stated cost is "the list is no longer lazy in the sense that matters
for a first frame" cannot be chosen in a codebase that gates on that laziness.

Candidate 2 is therefore refused on a standing constraint, and
`tests/virtual_list_variable_extents.spec.luau` contains the check that keeps it
refused: **a build counter on a 10 000-item ragged list**, not a timer.

### Why candidate 1 is not what was needed FIRST

Candidate 1 is the only one compatible with boundedness, and it is where this
work ends up — but reading it against the measurement shows it was written
against the wrong problem. Its whole difficulty is *the extents of items you have
not built*. Two things are true of the measured defect:

1. **Every consumer in the sweep already knows its own row shape.** These are not
   arbitrary feeds. `row_actions`, `perf_capture` and `virtual_list_native` build
   the same cell for every row; what they got wrong is a *number*, not a
   *structure*. A consumer that can compute a per-row extent from the same facts
   its cell paints with needs no estimate and no correction at all.
2. **The blocked consumer named in the round-3 plan is `newTable`**, which ships
   `rowHeight(item)` — a per-item extent the consumer DECLARES. `newTable` does
   not virtualize *because* the substrate cannot express that. It needs the
   offset index, not the estimator.

Both candidates need the same thing underneath: **a running-offset index** — a
prefix sum, searched rather than divided. That is the load-bearing half, it is
shared, and it is exact.

---

## The decision

**Ship the running-offset substrate with a DECLARED per-item extent as Stage 1;
keep candidate 1 (measured extents) as Stage 2, on the same index.**

`itemExtent` gains a third legal form:

```luau
itemExtent = function(item, index, use) -> px
```

alongside the number and the `Readable<number>` it already took. The function is
resolved inside a memo and is handed the memo's own `use`, so an extent derived
from `preferredTextOffset`, the theme metrics or the viewport re-derives when
they move — reading a Readable with `:get()` instead is right once and registers
no dependency, which is the silent-staleness this whole feature exists to end.

### Why this and not option B from the ruling

The ruling's cheaper option B was "make the declared extent GROW with the text
preference". It closes the accessibility case and leaves the class open — rows
stay uniform, so one tall row still overflows. The per-item form is strictly more
than B (an extent that reads the text preference AND the row's own content) for
the same consumer-side work, and it is the substrate B would have to be thrown
away for later.

### What was traded

- **Stage 1 does not remove the prediction.** A declared per-item extent is still
  a consumer's guess, and this repo's own history says guesses about row height
  are wrong four times before they are right. What Stage 1 buys is the *expressive
  power to be correct per row* and an offset index that is exact once the numbers
  are; what it does not buy is the number itself. **The slot guard therefore stays,
  and is not weakened** — it just files per-row now, naming that row's own
  declaration instead of one list-wide one. Stage 2 is what makes the prediction
  unnecessary.
- **`window()` diverges by one row, deliberately, mid-slot.** The uniform rule
  takes the visible COUNT from the viewport alone (`ceil(viewport / pitch)`),
  which is independent of where between two slots the scroll sits, so at a
  fractional offset it names one row fewer than the viewport actually touches;
  `overscan` (default 2) has always covered it. The variable rule cannot use a
  count — with ragged extents "how many rows fit in 498px" has no answer — so it
  asks the exact question and is a strict SUPERSET, never a subset. **The uniform
  rule is left exactly as it was**: it is the baseline every shipped list, every
  window assertion in the suite and the perf lab's instance counts were measured
  against, and tightening it is a separate change with its own before/after.
  Recorded here so it is a decision rather than a surprise; pinned by
  `virtual_extents.spec`'s own case.
- **Scroll anchoring is variable-extents-only.** On a uniform list the offset
  table also moves when the ROW COUNT changes, and re-anchoring that would change
  what every shipped list does when a row is inserted above the viewport — a
  behaviour change no measurement has asked for. Generalizing it is a follow-up,
  flagged rather than smuggled.
- **The per-item extent function is evaluated O(N) per data change.** Arithmetic,
  not measurement: no item is built and nothing is measured, which is the line
  that keeps candidate 2 refused and this accepted. The index is cached on its
  inputs so an edit that moves no geometry rebuilds nothing.

---

## What Stage 1 shipped

| piece | where |
|---|---|
| the pure running-offset index (`uniform` and `variable`, one interface) | `src/virtual_extents.luau` |
| the control wired to it: canvas extent, scroll clamp, window membership, per-row offset and box, keep-visible, insertion slot and hairline, reorder slide, hosted tray offset/height | `src/controls/virtual_list.luau` |
| per-row slot declaration, so the lying-extent guard names the right number | same |
| scroll anchoring on the item under the viewport's leading edge | same |
| construction-time refusal of an invalid per-item extent, naming the row's key | same |
| the arithmetic's own spec (17 cases, incl. the uniform-containment invariant and a counted boundedness check) | `tests/virtual_extents.spec.luau` |
| the control's spec (17 cases, incl. a build counter on 10 000 ragged rows and the anchored-scroll case) | `tests/virtual_list_variable_extents.spec.luau` |
| the showcase: 400 posts of four heights, with a toggle that re-creates the measured defect beside the fix | `examples/gallery/scenarios/variable_extents.luau` |
| the consumer proof: Rascal Rally's racer list is still on the uniform arithmetic | `games/RascalRally/code/tests/luauui_closed_key_contract.spec.luau` |
| mutation evidence (20 mutations across three rounds) and the perf numbers | `artifacts/variable-item-extents/` |

---

## Stage 2 — measured extents, and what it needs

The remaining half of the ruling: **remove the prediction entirely**, so a row's
extent is what it MEASURES rather than what its consumer promised.

The design, in the shape this codebase already supports:

1. **`itemExtent = "measured"`, with `estimatedItemExtent` for unmeasured items.**
   The row's main-axis dim becomes `content` rather than a fixed px, so its
   ARRANGED rect *is* its measured extent. No new solver channel is needed.
2. **The measurement arrives through `syncGeometry`.** The contribution bundle
   already carries `(rectOf, rootNode) -> ()` and the presenter calls it after
   every refresh; `slider.luau` and `row_actions.luau` both write signals from it
   today. This is the seam — a per-consumer wiring step would be exactly the
   silent, per-caller failure this repo keeps getting burned by.
3. **A per-key extent cache feeds the same prefix sum.** `virtual_extents.variable`
   already takes an extents array; measured mode fills it with
   `measured[key] or estimate`. Nothing about the windowing changes.
4. **Convergence is one step, and the reason is worth stating.** A row's
   main-axis measure does not depend on its own main-axis slot (the cross axis is
   fixed by the viewport), so measuring cannot change what was measured. The one
   exception is a cell declaring `height = fill`, which must be refused in
   measured mode — a fill would take whatever the slot is and the loop would have
   no fixed point.
5. **The anchoring built in Stage 1 is what makes it non-jumping**, and it is
   already there. The residual cost is the one candidate 1 always had and which no
   mitigation removes: the *total* content extent is an estimate until every item
   has been seen, so the scroll THUMB's proportion moves even though the content
   under the eye does not.

Stage 2 is not started. Nothing in Stage 1 is staged for it and no field is
reserved — the index takes an array of numbers and does not care where they came
from, which is the only seam it needs.

## Follow-ups flagged, not taken

- **Tighten the uniform `window()` rule** to the exact containing-slot question,
  so both paths run one rule. It only ever mounts MORE rows (a strict superset),
  so it is safe in kind — but it moves window assertions across the suite and the
  perf lab's instance counts, and it deserves its own before/after.
- **Generalize scroll anchoring to uniform lists**, so a row inserted above the
  viewport does not shift the content under the player's eye either.
- **`newTable` virtualization**, which round 3 records as blocked behind this
  work *because* `Table` ships `rowHeight(item)`. The substrate it was waiting for
  now exists; wiring it is its own mission.
