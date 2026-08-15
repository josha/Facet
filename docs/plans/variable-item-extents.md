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

**Stage 2 built 2026-08-15.** The design above survived contact almost intact;
what changed, and what it cost, is below.

### What Stage 2 shipped

| piece | where |
|---|---|
| `itemExtent = "measured"` + `estimatedItemExtent`, both refused in the wrong company | `src/controls/virtual_list.luau` |
| the per-key measurement cache, its epoch, and the pruning that ties it to the data | same |
| the `Content` wrapper — one control-owned node per MEASURED row, `content` on the scroll axis and `fill` across it | same |
| the measurement seam on `bundle.syncGeometry`, equality-guarded and composed with hosted row actions | same |
| the `fill`-main-axis refusal, naming the row | same |
| `filedBy` on the lying-extent and zstack-overflow findings — a replay-gate fix, found by a surviving mutation | `src/layout/solver.luau` |
| the control's spec (25 cases: geometry, laziness by build counter, the anchored scroll, the fill refusal, the closed lying-extent class, the differential against uniform) | `tests/virtual_list_measured_extents.spec.luau` |
| the stale-finding witness on the DECLARED path | `tests/virtual_list_slot_guard.spec.luau` |
| the showcase: 400 posts, no height arithmetic anywhere, bodies that wrap with no `lineLimit` | `examples/gallery/scenarios/measured_extents.luau` (ORDER, `demo_picker.DEMOS`, the overflow sweep) |
| the perf lab's fifth arm (D, measured, against arm C's identical picture) | `examples/performance/lab/perf_lab.luau` |
| the consumer proof: Rascal Rally's racer list is still uniform AND mounts no wrapper | `games/RascalRally/code/tests/luauui_closed_key_contract.spec.luau` |

### The one design change, and why

The plan said "the row's main-axis dim becomes `content`, so its ARRANGED rect
*is* its measured extent". **Built the other way round**: the ROW keeps a fixed
box (the index's number) and the CELL rides a `content`-sized wrapper whose rect
is the measurement. Two reasons, both measured on this solver rather than
reasoned:

1. A content-sized ROW takes the max of its children, and one of its children is
   the control's own hit Button — which measures 24px with an empty label. Every
   measured row would have carried a silent 24px floor sourced from the button's
   theme metrics, which is precisely the hidden-number class this feature exists
   to end.
2. With the row fixed at the index's number, the canvas offsets and the painted
   rects can never disagree. Only the *content* is ever momentarily out of step,
   and only for the convergence step.

The wrapper costs one node per **measured** row. Uniform and declared-variable
rows are byte-identical to what they were.

### What the `fill` refusal actually is

The plan predicted "a fill would take whatever the slot is and the loop would
have no fixed point". Measured: a `fill` child inside a content-sized wrapper
measures **0**, so the row silently collapses rather than looping. The refusal
stands — the reason on the error message is the measured one.

### What Stage 2 traded

- **It is not the default, and that is a perf decision.** Against a declared list
  painting the identical rows, arm D costs about **+30% per scroll frame** in
  steady state and about **+100%** while a region is converging (tier 1, headless;
  A/A control spread 1.6%). A row a consumer really can predict should still be
  declared. `artifacts/variable-item-extents/perf.md`.
- **The total canvas is an estimate until every row has been seen**, exactly as
  candidate 1 always said. The content under the eye is exact (the anchor holds
  it); the scroll thumb's proportion is not. `dump().measuredRows` makes it a
  number instead of a mystery.
- **No `virtualSlot` is declared in measured mode**, so the lying-extent guard
  files nothing there — there is no prediction to check. The generic
  zstack-overflow finding still covers the convergence step and clears after it.
- **A bound `fill` dim is not caught.** The refusal reads the literal dim at row
  build; a Readable resolving to `fill` still collapses, just without the sentence.

### Follow-ups flagged, not taken

- **`measureWindow` walks the whole window every solve.** Once a region is
  converged that walk finds nothing and is pure cost — it is most of the +30%
  steady-state number. Gating it on a per-row dirty signal is a real optimization
  and is its own change with its own before/after.
- **The `LuauUI.text` line-box helper did NOT land with Stage 2** — see below.

## What the showcase proved about Stage 1, the hard way (2026-08-14)

The overflow sweep reached `variable_extents` for the first time — the sweep's own
registry check and this fixture landed the same day — and filed **418 findings on
it, 372 of them the lying-extent guard.** On the fixture written to demonstrate the
feature, by the mission that built it.

The cause is worth recording because it is the strongest argument for Stage 2 that
exists. `rowExtent` multiplied `(size + the fixture's own chip offset)` by a
literal `1.25` and stopped. It was right on Studio Neutral at the default text
preference and wrong everywhere else: 8px short at `preferredTextOffset` 4, 54px
at 14, and 15px short *at the default preference* on a ten-foot display, whose
Large class multiplies the type ladder by 1.5.

**So "Stage 1 buys the expressive power to be correct per row" is true, and the
power is harder to use than it looks.** The correct declaration is the solver's own
arithmetic, reproduced by hand:

```
px = ceil(lines * (authoredSize * max(typographyScale, typographyPaintScale)
                   + preferredTextOffset) * theRole'sLineHeight)
```

Three env facts, one theme number, and one seam (`typographyPaintScale`) that
exists only because a sub-1 accessibility preference makes the paint seam the
larger of the two. The fixture is now the reference for that spelling, and the
sweep is what keeps it honest — but **no public helper turns those facts into a
line box**, and every itemExtent consumer in the repo currently gets it wrong the
same way: `row_actions`, `perf_capture` and `virtual_list_native` each carry a
lying-extent waiver in `tests/overflow_sweep.spec.luau` for exactly this.

Flagged rather than smuggled: a `LuauUI.text` helper for "the height of N lines of
this size, against these live facts" would close all three waivers and remove the
whole class from Stage-1 authoring. It is an API addition and belongs to whoever
takes Stage 2 — the two are the same problem, once from each side.

**RULED 2026-08-15, WITH STAGE 2, AND THE ANSWER IS NOT YET.** The helper is still
the right thing and it is still not built. The reasoning, so the next agent does
not have to redo it:

* **Stage 2 is the stronger answer for the class the helper was proposed for.** The
  helper makes a prediction *easier to get right*; measured mode removes the
  prediction. `row_actions` is the waiver that lies at the DEFAULT preference (84
  declared, 88 measured), and its cell is exactly the shape — wrapped text at a live
  size — that should stop declaring. Adding a public API so three consumers can keep
  predicting, on the same day the framework learned not to, is addition where
  deletion was available.
* **But it is not a complete answer.** `perf_capture` declares a uniform extent *on
  purpose* — it is the baseline the perf harness measures the uniform arithmetic
  against — so moving it to measured mode would change what it measures. That one
  genuinely wants a correct declaration, and today the only correct copy of the
  arithmetic in the repo is private to `examples/gallery/scenarios/variable_extents.luau`.
  A survey run for this mission found **seven** near-duplicates of the line-box
  formula and exactly one of them right; the public `LuauUI.composition.floorPx` is
  wrong in three ways (no `ceil`, no scale, no text offset).
* **It is a bigger change than it looks.** The correct spelling needs the env facts
  read through `use` — `max(typographyScale, typographyPaintScale)` is the part every
  consumer gets wrong — so it is two members (a facts reader and the line box), plus
  a surface-ledger row, an `api.md` entry, a registered spec and a regenerated
  public-surface artifact. Landing it badly is worse than not landing it.

**The recommended shape, for whoever takes it:** `text.facts({ env, use })` →
`{ scale, offset, metrics }` and `text.lineBox({ facts, size, lines, role? })` → px,
with `ceil` applied ONCE to the whole product (several existing copies ceil per line
and drift by up to `lines-1` px). Adopt it in `variable_extents.luau` first — deleting
that fixture's private copy is the proof the shape is right — then close the
`perf_capture` and `virtual_list_native` waivers with it, and close `row_actions` by
moving it to `itemExtent = "measured"` instead.

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
