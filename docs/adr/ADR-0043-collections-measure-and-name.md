# ADR-0043 — A collection may measure the box it was given, and may name its gutter

**Date:** 2026-08-22
**Status:** Accepted
**Number:** 0043. 0040 is the unreleased-breaking-changes register; **this
decision adds no row there** and §"Not a breaking change" below says why.
**Companions:** [ADR-0037](ADR-0037-controls-namespace.md) (the namespace these
controls are reached through), [ADR-0019](ADR-0019-theme-packages.md) §2 (the
metric vocabulary a named gutter resolves against),
`docs/handoff/SOURCE_CAP_LEDGER.md` (the extraction that had to precede the
feature), `tests/collection_self_measure.spec.luau` and
`tests/collection_gap_tokens.spec.luau` (the two guards),
`games/RascalRally/code/tests/facet_collection_extent_contract.spec.luau` (the
consumer's own evidence).

## Context — one sentence, twice

The purity audit's §4 and §5 read as two findings and are one: **the framework
held a number and made the consumer re-derive it.**

**§4.** `newVirtualList.viewportExtent` was asserted REQUIRED with no
self-measuring form, and the cross axis was documented as the consumer's job —
"wrap the list in a box of the height you want". So every consumer that did not
already know its own extent wrote the arithmetic by hand, and the repository has
four of them, each wrong at least once before it settled:

* the gallery's `row_actions` fixture kept a pane PATH, an `onGeometry` handler,
  a window signal seeded with a literal `336`, and a snapshot read of its own
  pane's `"s"` gap. The 336 was measured on a desktop and painted **227-245 px
  past its own pane** on a landscape phone; the gap was a literal `8` until
  ten-foot scaled `space.s` to 12 and the window came out **4 px too tall on
  every console pass**;
* the gallery's `card_rail` fixture subtracted `coreSafeInsets`, a Screen padding
  and a scrollbar guess for the width, and summed **five terms** for the height —
  the plate's padding, two live line boxes, the theme's chrome INSET off the
  `panel` slot, the chrome OUTSET Fantasy Ornate declares, and a slack constant.
  Each of the last three was discovered by a device round after the previous sum
  came out short: 12 px under Compact Pointer at the DEFAULT text preference,
  16 px under Fantasy Ornate at every preference, 8 px for the bar;
* `sponsor_drop` clamped `math.floor(h * 0.5)` between 160 and 420 — four numbers
  about a layout it does not own;
* and `newTable` did **not**, because it has measured its own body since the
  variable-extents mission. Its comment states the rule the audit re-derived:
  asking the consumer for it "would be one more thing to predict wrongly, which
  is the whole family of defect the variable-extents mission was about".

**§5.** `newTable.rowGap` has taken a theme metric name since 2026-08-06,
because the gap is used in ARITHMETIC and a name that reached `cum += height +
rowGap` used to throw. `VirtualList.rowGap` and `VirtualGrid.rowGap` refused a
string; **`VirtualGrid.gap` refused even a `Readable`**. So a consumer wanting a
theme-tracking gutter on a virtualized collection had exactly one legal route:
hand-write a memo that reads the live snapshot and hands back pixels. That memo
existed, in the gallery's `row_actions` fixture, and it is the precedent this
whole round was commissioned from — **the framework required the boilerplate the
precedent was written about.**

## Decision

### 1. `viewportExtent = "auto"` (`newVirtualList` and `newVirtualGrid`)

The host takes `fill` along its own axis and windows against what the solver gave
it, read off the presenter's per-refresh geometry pass. `newTable`'s technique,
promoted verbatim rather than reinvented, with its three load-bearing parts
intact:

* **`fill` is what makes it converge.** The host's size is decided by what
  CONTAINS it and never by what is inside it, so measuring cannot change what was
  measured. An equality guard at the write keeps that a fact rather than a hope —
  a signal written to its own value every refresh would re-solve the tree forever.
* **The seed is the SCREEN, and the direction is the point.** A box is never
  bigger than the surface containing it, so the screen is a sound UPPER bound and
  windowing against an upper bound mounts a strict SUPERSET of what the viewport
  touches. The first frame over-fills rather than mounting three rows and
  popping. Read once, not subscribed: it is a seed, not a second source of truth.
* **One requirement, stated rather than implied:** an ancestor that hands the
  collection a definite extent along that axis. `scenarios/sponsor_list.luau`
  keeps its clamp for exactly that reason and says so at the site.

**THE TWO WAYS TO BREAK THAT REQUIREMENT FAIL DIFFERENTLY, AND THE FIRST DRAFT OF
THIS DECISION GOT THE SECOND ONE WRONG** (fix round 1, review finding A). A `fill`
inside a box that **hugs** measures 0 and mounts nothing, which is obvious. A
`fill` inside an ancestor that is **unbounded** on that axis — which is exactly
what another scroller's own scroll axis is — measures the collection's **whole
canvas**: `solver.luau`'s `fill` branch answers with the node's *content*
contribution, a scroll node offers its children `math.huge` on the axis it
scrolls, and a scroll node's content measure sums them. Measured headlessly: 400
rows of 40px inside a y-scrolling page reported a **16,000px viewport and mounted
all 400 rows**. Virtualization silently off, stable, and invisible to any
assertion about correctness — the rows are all present and all correctly placed.
It is a performance cliff wearing a correct-looking layout, and it is a worse
failure than the one the first draft documented.

**The collection detects it, on the seed's own argument turned around.** The seed
is sound because *a box is never bigger than the surface that contains it*; so a
measured extent that **exceeds the screen** is not a viewport, it is a canvas. The
finding lands in `dump().diagnostics` (`newLevelPicker`'s precedent for a
control-side diagnostic) naming both numbers and the fix, once per state change
rather than once per refresh. The house idiom it follows is `solver.luau`'s
"percent size on an unbounded axis (inside scroll axis?)".

**It reports and does NOT clamp**, and that is the load-bearing half. Clamping the
window to the screen while the solver still paints the host at canvas height would
leave the bottom of the painted box empty of rows — a *visible* defect traded for
an invisible one. The honest answer is the number the solver gave, plus a
diagnostic naming the shape. A solver-side fix (refusing to offer `math.huge` to a
scroll host's own `fill` child, or answering a bounded contribution) was not
attempted: `src/layout/solver.luau` has an extraction owed to another round and
this is not the change to open it with.

**`itemExtent = "cards"` does not take the screen seed** (fix round 1, review
finding B). The superset argument is about *windowing*, where an over-estimate
mounts more rows than the box touches and is bounded and invisible. The card
paradigm makes the same number decide **the arrangement** — `card_rail`'s own
header says in capitals that it must be asked about the rail's own extent and not
the screen's. Measured before the fix: a 300px rail on an 800px screen resolved a
**three-up arrangement of 261px cards** on its first painted frame and a **one-up
270px carousel** on its second; not a size that popped, a different answer to the
paradigm question. A card rail therefore seeds **0**, which windows to nothing:
one frame painting nothing, then the right arrangement. Every other list keeps the
seed and the over-fill it buys.

### 2. `crossExtent = "hug" | "measured"` (`newVirtualList` only)

Absent, the cross axis FILLS — what every list has always done, unchanged.
`"hug"` sizes it to the CONTENT (host, canvas and rows all take `content`
across), which is the card rail's own defect answered: `fill` is a promise the
box will be big enough, and that box was not. `"measured"` keeps filling and
REPORTS the number.

**It is a list field and not a grid one**, and the reason is arithmetic rather
than effort: a grid's lane width is derived FROM its cross extent
(`floor((innerW - gap × (lanes - 1)) / lanes)`), so a hugging grid would be
asking its lanes how wide they are in order to know how wide its lanes are.
`newVirtualGrid`'s closed spec refuses the key by name.

Both self-measuring forms publish their number as a `Readable<number>` on the
returned table. **A collection that declared its own numbers publishes neither**,
so nothing that did not ask pays for the field existing.

### 3. A gutter may be a theme metric name (`controls/gap_metric.luau`)

`VirtualList.rowGap`, `VirtualGrid.rowGap` and `VirtualGrid.gap` take a number, a
theme metric name (`"xs"`..`"xl"` or a dotted path), or a `Readable` of either.
One module holds the vocabulary, the refusal and the live read, shared by both
collections **so they cannot drift into two answers about what a gutter may be**
— the reason `controls/scroll_snap.luau` exists one file over.

**One deliberate divergence from `newTable`, and it is the stricter direction.**
An unresolvable name is REFUSED at construction, by name, rather than falling
back to `0`. `rowGap = "6"` is a number somebody quoted, and constitution §4's
rule for a spec field is that an unknown value is an authoring mistake and never
a silent no-op — which bites hardest on a field whose wrong answer is invisible,
because a gutter of zero looks exactly like a gutter nobody asked for. Every
spelling `newTable` accepts *and means* still works; the only thing refused is
the spelling that meant nothing there either. The LIVE read cannot refuse and
does not pretend to: a package swapped at runtime may drop a key, and a theme
swap must not be able to tear down a mounted surface.

**`env = nil` is two answers, and only one of them may degrade** (fix round 1,
review finding H). `surfaceEnv.find` returns nil both for "nothing published" — a
headless mount, a legal caller — and for **ambiguous**, meaning more than one live
environment on the core. Collapsing them meant a themed gutter silently resolved
against neutral, and `"auto"` seeded from a screen the control could not name, on
a core where the framework had been asked to guess which surface the control
belonged to. The controls distinguish them now and call `surfaceEnv.resolve` — the
one spelling of that refusal — but **only when the build actually needs the
environment**, so a plain numeric collection on an ambiguous core is still built
without complaint.

**Owed:** `newTable.rowGap` should adopt `gap_metric` and inherit the same
refusal. It did not this round only because `table.luau` belonged to a
concurrent writer.

## Not a breaking change — no ADR-0040 row

Every clause above widens or adds:

* `viewportExtent` gains a word; every number and `Readable` behaves identically.
* `crossExtent` is new, and absent it reproduces the previous behaviour exactly
  (the cross axis fills). `"hug"` beside an authored `width` on a vertical list is
  refused rather than silently discarding the width — a refusal on a combination
  that could not exist before the field did.
* the three gutters gain two accepted forms; a number behaves identically and a
  negative one is still refused.
* the self-measured `Readable`s are published only when asked for, so no
  returned table gained a field a caller could collide with.
* `newVirtualGrid.dump().gap` now reports the RESOLVED gutter rather than the raw
  spec value — byte-identical for every call that was legal before, because the
  field only accepted a number.

The one shipped-behaviour change in the round is a bug fix with its own red:
`row_actions`' `api.editGutterPx` is now published in WRAP mode as well as
hosted, which is what let `newTable`'s heading band reserve the same edit gutter
its wrapped rows spend. Nothing behaves differently for the field being legible.

## Consequences

* **Four fixtures stop predicting geometry**, and two of them LEAVE the
  theme-drift lint's *coupled* set — the lint's own criterion for "this file
  predicts its own box from raw constants" no longer matches `card_rail.luau` or
  `virtual_hgrid.luau`.
* **The extraction had to come first.** `virtual_list.luau` was 805 characters
  from the trigger its `SOURCE_CAP_LEDGER` row had set, and that row makes the
  extraction a PRECONDITION of the next change of any size rather than a
  companion to it. `controls/virtual_list_hosted.luau` (192,187 → 145,913) landed
  as its own behaviour-neutral commit with the verdict set diffed line for line.
* **A consumer can now be given the number it used to guess**, which is the
  measure of whether this was worth doing: `viewportExtent = "auto"` deleted a
  signal, a handler and a snapshot read from one fixture (its pane PATH survives,
  as a path — two scripted steps aim the focus ring with it), and ~55 lines plus
  one constant (`RAIL_SLACK`) from another. `PADDING` survives there as the
  padding the Screen is given, which is what it was always for.

## Alternatives considered

* **Publish the measured number and leave the sizing alone** — i.e. only the
  `"measured"` half. Rejected for the rail: it reports the box that was already
  too small. Kept as the second `crossExtent` form, for the caller who needs the
  number rather than a different size.
* **Resolve a gutter name in each control.** Rejected: two refusal messages and,
  worse, two answers to "does this name resolve at all". The `scroll_snap`
  precedent is explicit that the two collections share a vocabulary or drift.
* **Match `newTable`'s fallback-to-zero exactly.** Rejected above; the audit's
  own words were "exactly matching Table's contract", and this is that contract
  minus the one spelling that never meant anything.
* **`crossExtent` on the grid too.** Rejected as circular; see §2.
