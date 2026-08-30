# The solver already told you — read `controller.diagnostics()`

**Found:** 2026-08-05, on a real phone, by a human looking at a screenshot.
**Cost:** a shipped fixture whose rows painted over each other on every phone in
portrait, past a green 3 368-case suite, a green perf gate, six live Studio sessions,
a five-view device matrix and four fresh-context reviews.

## The symptom

The performance lab's row on a 359×718 device: the avatar, the name and the Ready
toggle piled on top of one another, the name clipped to a single letter, the stepper
and Open button poking out below into the next row.

## What made it survive everything

`controller.diagnostics()` had the answer the whole time, in the exact words of the
defect:

```
DIAGNOSTICS: 18
  x9  content overflows this hstack by 132px on the main axis; it will paint outside its box
  x2  this child overflows its zstack by 132x106px and nothing clips a zstack, so it paints over
  x4  this child overflows its zstack by 132x77px  …
  x3  this child overflows its zstack by 132x91px  …
```

**Nothing in the fixture ever called it.** Every other control was in place — the
suite, the gate, the matrix — and not one of them asked the solver what it thought of
the geometry it had just produced.

## Four mistakes, in the order they mattered

**1. Nothing read the diagnostics.** This is the whole lesson. Facet's solver reports
overlap, main-axis overflow, collapsed content boxes, clipped essential text and
sub-floor hit targets. A fixture that does not read them is not verified, however many
other checks are green.

**2. A count is not a layout assertion.** The lab asserted
`mountedRows <= windowBound` — bounded virtualization — and the device-matrix rows
asserted the same thing at 360×691. Both passed. Neither says anything about whether
the pixels are on top of each other.

**3. Magic constants that do not adapt.** `rowHeight = 56` and
`viewportHeight = 420`, both hard-coded. The row needed ~475px of width and was taller
than 56px below ~640px; the list was taller than a landscape phone's entire 390px
screen. A constant that does not adapt is a constant that is wrong on some real device
— the same family as
[`a-fixed-box-cannot-hold-a-themes-frame.md`](a-fixed-box-cannot-hold-a-themes-frame.md),
with the viewport in the theme's place.

**4. Every capture was taken at the developer's viewport.** 907×1067, where the row
happens to fit. Findings by viewport, measured afterwards:

| viewport | findings |
|---|---|
| 359×718 phone portrait | **18** |
| 844×390 phone landscape | 1 |
| 907×1067 — every capture taken | **0** |
| 1280×720 desktop | 0 |

## What to do instead

**Read the diagnostics in the fixture, and fail on them.** One call, and the class
becomes impossible:

```lua
local findings = handle.controller.diagnostics()
assert(#findings == 0, `layout finding: {findings[1].node}: {findings[1].issue}`)
```

Put it where the fixture mounts and after anything that changes geometry. Then break it
on purpose once and watch it fire — an audit nobody has seen fail is decoration.

**Sweep the narrowest supported viewport, not your own.** 320×640 through 1920×1080.
The dev viewport is the one place a layout bug hides.

**In a fixed-height windowed list, the arrangement and the height are ONE decision.**
`newVirtualList` windows on a fixed pitch. If the row restacks on narrow widths, the
`rowHeight` Readable must follow the *same* signal — two decisions is the split brain
that paints a 152px row into a 56px slot.

**Measure the breakpoint in the real slot.** A row measured with a free height only
reveals *horizontal* overflow. Measured inside its actual fixed slot, the one-line form
here was still 77px too tall at 480px, 48px at 540px and 1px at 600px — clean only from
~640px. The first measurement missed all of that.

**A viewport threshold is legitimate for a list row; `ViewThatFits` is for containers.**
`adaptive.conditions(...).isCompact` flips at 600px, which is right for a screen and was
wrong for this row. `docs` point container-relative questions at `UI.ViewThatFits` —
but a row inside a fixed-height list cannot use it, because the winning candidate's
height must be known to the list *before* the row is built. So measure the row's own
requirement and threshold on it, and say in a comment that the number is measured.

---

# Round 2 — everything the first fix still got wrong

The fix above was verified headlessly and shipped. The same human then rotated the
device and found it broken again, twice more. Each round was the SAME mistake in a new
place, so the list below is the useful part of this document, not an appendix.

## 5. A value read once is a value that is wrong on the second screen

`compact = isCompact:get()` inside a `ForEach` cell. `ForEach` never rebuilds a row
whose key is unchanged, so one-line rows survived into a portrait slot. Twelve findings.

Then the *same shape* twice more in the control overlay, which is built once:

```lua
maxHeight     = overlayMaxHeight(),   -- snapshot of whichever orientation booted first
actionColumns = (function() … viewportRect … end)(),
```

Mount in landscape, rotate to portrait, and the panel still carried landscape's five
columns — the buttons clipped exactly as before the "fix".

**Rule:** if a number comes from the viewport, it is a `Readable` or it is stated to the
solver declaratively. A plain number captured at build time is a bug with a delay on it.

## 6. Prefer stating the intent to computing the answer

Every one of those snapshots had a declarative form that needed no viewport read at all:

| computed by the caller | stated to the solver |
|---|---|
| `columns = floor((w - 16) / 124)` | `minColumnWidth = "intrinsic"` |
| `height = { px = clamp(h * 0.34, 96, 260) }` | `height = { type = "percent", fraction = 0.34, min = 96, max = 260 }` |
| `rowHeight = 56` | `rows.heightFor(compact, typographyScale)` |

The declarative form re-resolves on every solve, including the one after a rotation.
There is nothing to keep in sync because there is no second copy of the decision.

## 7. Two surfaces are two solves — no diagnostic sees the collision

The overlay and the workload are separate `present()` calls, so they are separate
ScreenGuis with separate controllers. Each was individually correct. Together, the
control panel painted straight over the list — and `diagnostics()` on either surface
reported **zero**, because neither can see the other.

Two things fix it, and both are needed:

- the overlay publishes its **measured** height into `coreSafeInsets.bottom`
  (`onGeometry`, never a literal), so the solver lays the workload out in what is left —
  and it carries the other three edges through, because writing a whole table with three
  zeroes in it means "delete the notch and the home indicator";
- the audit runs over **both** surfaces, not just the workload.

**Rule:** a per-surface diagnostic is not a per-screen diagnostic. Audit every surface
you present, and make overlapping surfaces reserve space rather than trusting z-order.

## 8. An opaque surface is not decoration

The panel had no plate, so the list read straight through its own labels. On a phone
screenshot the counter text was woven into the rows. `surface = "raised"` — one prop.

## 9. The arithmetic that mirrors the renderer will drift from the renderer

The list height was `viewport.h − chrome`, and `chrome` was wrong twice:

- a flat `64` ignored the CoreGui topbar → 33px over on a 706×339 landscape phone;
- adding `coreSafeInsets` still missed the **ten-foot overscan margins**, which
  `renderer.solveAndApply` composes *on top of* that fact while the display class is
  `Large` → 104px over at 1920×1080.

No constant covers a margin the arithmetic cannot see. The fix was to read *every* fact
the renderer reads — `coreSafeInsets`, plus `effectiveOverscanInsets` when
`distanceProfile == "ten-foot"` — rather than approximate their sum.

**Rule:** if you must reproduce a framework's arithmetic, reproduce its *inputs*, not
its result. And when a constant has to stay approximate, make it approximate in the safe
direction and say which direction that is (over-reserving chrome shortens a list, which
can never overflow; under-reserving paints over the header).

## 10. The type scale is part of the geometry

A `Large` display class multiplies typography by **1.5**. A row height measured at scale
1.0 is wrong there in exactly the way a row height measured at one viewport width is
wrong on a phone — every row overflowed its 56px slot by 3px. Split the constant into
the part that scales (text) and the part that does not (padding, the avatar).

## 11. Fix the report before fixing the bug

The audit printed only the first finding and no rect. "Overflows by 104px" names a
symptom; the box it overflowed is what identifies the wrong constant. Adding the top four
findings *with their solved rects* turned a guessing loop into one measurement.

## 12. A device-matrix row that counts is not a device-matrix row that looks

The withdrawn matrix reported `mountedRows: 11, windowBound: 13` at **every** row, from
a 360×691 phone to a 1920×1080 television. A window that does not move with the viewport
is a window computed from a constant — the defect's own signature was sitting in the
results table the whole time, in a column nobody read as a claim.

**Rule:** when every row of a matrix reports an identical number, that is a finding, not
a pass.

## The one-line version

> A green suite means your decisions are right. It does not mean anything is on screen
> where you think it is. Facet will tell you — if you ask it.

---

## 13. It said it TWICE, in the same words, and nothing failed (2026-08-06)

The device report was "the edit button overlaps the heading at largest text". Seven fixes
were attempted and reverted — two of them deleted the button entirely — because each was a
guess at the solver's behaviour rather than a question put to it.

The answer was one call away the whole time:

```
/S/T/Main/Header/Head-name/Title :: this child overflows its zstack by 0x6px and nothing
clips a zstack, so it paints over whatever sits beside it (give the box room — a `minMax`
FLOOR rather than a fixed CAP — or set overflow = "intentionalOverlap")
```

The diagnostic **named the defect, named the fix, and named the exact node**. `UI.Table`'s
header cell was `{ type = "fixed", px = "controls.table.headerHeight" }` — a 28px cap
holding a title that measures 34px at the Largest preference. Changing the one word `fixed`
to a `minMax` floor closed it, and the mutation back reproduces all of it.

Two habits let a fully-formed answer sit unread for seven attempts:

1. **The LT-8 control sweep mounted the Table without `reorderable`**, so the auto Edit
   toolbar — the neighbour the header collided with — did not exist in a single swept row.
   *A sweep only covers the configurations its fixture actually builds. An optional
   sub-control that ships by default belongs in the fixture.*
2. **Nothing in the suite failed on `controller.diagnostics()`.** §1 of this file already
   says to call it. Calling it is not enough — a fixture must **fail** on it, or the list
   is a log nobody reads.

And the director got there first, from a phone, with no instrumentation: *"if height is the
issue why can't we make the whole table have more height as text size increases"*. That is
the fix, stated plainly, one message before the measurement found it.

**Rule:** before the second attempt at a layout defect — not the eighth — print
`controller.diagnostics()` for the failing configuration and read it as a sentence. And any
fixture that can produce a finding must assert the list is EMPTY, so the next one fails
loudly instead of printing into the dark.

---

## 14. It said it a THIRD time, and the answer was to make it un-ignorable (2026-08-12)

Three device reports from a phone, all one family: a mail table entirely below the
fold in landscape with nothing to scroll it (`IMG_3689`), a Match-3 button row
sliced by the right screen edge (`IMG_3690`), an all-controls fixture running past
its box (`IMG_3691`). §1 of this file says to read `controller.diagnostics()`. §13
says a fixture must *fail* on them. Both were written, and the suite still could
not see any of the three, because reading them was still something a person had to
decide to do — per fixture, per stage, per mission.

The fix is not another instruction. It is `tests/overflow_sweep.spec.luau`: every
showcase surface (25 gallery scenarios, 7 tutorial examples, 5 reference proofs)
mounted at the five recorded device-matrix viewports plus the narrowest supported
one in **both** orientations plus the desktop size the director actually drives,
failing on any main-axis overflow. It runs on `./run-tests.sh` and nobody has to
remember it.

**It found eleven more on its first run.** Not three defects — fourteen surfaces.
`probe`, `scroll_host`, `path_ring`, `drag_session`, `virtual_list_native`,
`native_style`, `authoring`, `sponsor_list`, `composition`, `keyboard_navigation`,
`06_tile_game` and the `p4_foyer` reference proof were all overflowing at a
viewport the device matrix has been *driven at* for months. That is the measure of
what "a diagnostic nobody reads" was costing.

Four things this round adds to the list above.

**A sweep is only as honest as its ENVIRONMENT.** The first version laid every
surface out against the bare viewport. In the showcase every one of them is reached
through the demo picker, which reserves a 62px chip strip by writing
`coreSafeInsets.top` — so the bare-viewport sweep was measuring a screen 62px taller
than any player has ever seen, and that 62px was the whole margin several of these
lived in. The sweep reads the number from `demo_picker.barReservation` rather than
holding its own copy.

**A sweep only covers the CONFIGURATIONS its fixture builds** (§13.1, again). The
row-actions fixture is one screen with three surfaces behind a mode signal, and the
default mount builds one of them. The other two held a `viewportHeight = 336 -- 4
rows visible` that painted 245px past its pane on every landscape phone. The sweep
now drives declared variants; that defect appeared the minute it did.

**Two attempts at a viewport-derived constant were both wrong, and the third was
not a constant.** `viewportHeight - chrome` was off by 64px on a portrait phone
because the mode bar re-columns to two rows there — the chrome is the *solver's*
decision, not a number the fixture can hold (§9, in a new place). The window is fed
from the pane's own solved rect through `onGeometry` now, exactly as the picker
strip publishes its own measured height. It cannot chase its tail because the pane
takes `fill`, so its height never depends on the list inside it.

**The chrome gives way, not the content.** Every fix in this round is the same
sentence: a screen whose subject is a list spends a short viewport on the list.
`adaptive.conditions(...).isShort` is the framework's own signal for it and it is a
Readable, so it survives a rotation (§5). A `title`-sized heading, a mode bar and a
toolbar are what a 200px-tall landscape phone cannot afford.

### ...and the corollary that made it worth doing

The sweep's failure message carries the offending node's solved box, not just the
overflow (§11). Eleven of the twelve extra surfaces were diagnosed and fixed from
that one line, without a capture.

## 15. The overflow message now has TWO forms, and they call for different repairs (2026-08-12)

Parity round 2 §2.4 gave the solver a shrink pass, so "content overflows this
`<stack>` by `<N>`px on the main axis" is no longer the whole story. Read the tail
of the line:

| What you see | What it means | The repair |
|---|---|---|
| `…(wrap it in a ScrollView, or give it room)` | the historic message, unchanged. **Nothing in this stack was allowed to shrink** — no child declared a `shrinkWeight`, which is the default | give it room, scroll it, or let a child give way (`shrinkWeight = 1`) |
| `… — every shrinkable child is already at its floor (layoutPriority order tried: 0, 2)` | the shrink pass ran, worked through those priority tiers lowest-first, and took every pixel it could. The row still does not fit | the floors are the constraint: a `minMax.min`, a label's longest word. Widen the box, shorten the content, or raise a floor's owner into a higher tier |

The distinction is the whole point of appending it: *"nothing was allowed to
shrink"* and *"everything is already at its floor"* look identical in a rect dump
and want opposite edits.

There is a second new line on the same channel, and it is an authoring conflict
rather than a fit problem: `distribute = "spaceBetween" has nothing to distribute
on this hstack: a `fill` child already takes the whole leftover`. `fill` resolves
first and consumes the remainder, so `distribute` is spreading nothing. Drop the
fill dimension or leave `distribute` at `"start"`.

## 16. A THIRD kind of line now rides the channel: "this prop did nothing" (2026-08-13)

Every message above is about a box that does not fit. Parity round 2 §2.1 added a
different question to the same channel — *was anything you asked for actually
read?* — and the line looks like this:

```
`alignH` is a placement prop this parent never reads: a vstack's arrange places
its children by stacking them down a line, so `alignH` here is accepted and then
ignored — nothing moves. Use `lineAlign` (start|center|end|stretch), which a stack
does read off each child
```

`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign` and `gridSpan` are
shared BOX props — legal on **every** node — but not one of them is a fact the node
has of its own. Each is an instruction addressed to a particular kind of **parent**,
and every arrange branch reads only the ones it knows. Anywhere else the framework
accepted the prop and then ignored it, which constitution §4 forbids.

**Why this belongs in this file and not in a refusal.** A child cannot catch it —
it does not know its parent at its own construction — so the *parent* does
(`solver.auditPlacement`, called from `renderer.toLayoutNode`, reported by
`arrange`). And a construction-time refusal, which is the house shape and was
built, turned out to redden five live Rascal Rally screens; the diagnostic carries
the same information without changing a shipped build. That is the trade this
channel exists to make.

**What it cost to leave unread, measured on the day it landed:** twelve live call
sites across the framework, the game and the examples. The loudest was
`row_actions`' floating menu asking to sit at its trigger's screen coordinates and
being placed at the origin — silently, with `diagnostics()` empty, through a green
suite. Four more were an alignment an author asked for and never got. Every one is
written up in
`docs/plans/unfulfilled-placement-intents.md` (archived privately).

**The rule, same as §13's:** a fixture must FAIL on it, or the list is a log nobody
reads. Three suites already assert an *empty* `diagnostics()` for their screens
(Glade twice, the Rascal Rally results screen once) — those three assertions are
what made this tier land as a real gate rather than a log, and they passed
unedited once the twelve call sites were cleared.
