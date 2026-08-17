# A `fill` of nothing is nothing

**2026-08-16, device review of the `level-picker` demo:** *"three of the five
demo rows are blank."*

`newLevelPicker` shipped headlessly green a few hours earlier with 17 mutations,
17 of which bite. On a real phone its DEFAULT segment — `bar`, the shape the
whole control was requested for — painted nothing at all. The `glyph` row drew
its ◆◆◇◇◇ and the `image` row drew its icons; every `bar` row was empty space
beside a stepper that rendered perfectly.

## The measurement, at the boundary that had it

```
/…/Balanced/Pair/BalancedBars         ZStack  190x44
/…/Balanced/Pair/BalancedBars/Levels  Grid    190x44
/…/Balanced/Pair/BalancedBars/Levels/Level1   Box   12x0   tint accent@1
…                                             Box   12x0
/…/Balanced/Pair/BalancedBars/Strip   Grip    190x44
```

The strip reserved its 44px. The grid was arranged 44px tall. Every mark came out
**12 wide and 0 high** — the lane's width and no height — and a rectangle with no
area paints nothing whatever colour it is carrying.

## The engine-free fact

A `UI.Grid` derived its line's **flow** extent (the row height, on a row-major
grid) from its cells' CONTENT and from nothing else, and a `fill` cell then took
that line. A line whose every cell fills has no content anywhere in it, so the
line was zero and every cell in it was zero. The grid's OWN extent — the number
its parent had already imposed on it — never reached the line.

The same declaration under a stack, measured side by side:

| container, 400x60, three `fill`/`fill` Boxes | each child |
|---|---|
| `UI.HStack` | `198x60` |
| `UI.Grid` (`columns = 3`, `itemSizing = "uniform"`) | **`130x0`** |

Every other container in this library resolves a `fill` against ITS OWN resolved
extent — which is what `resolveAxis` means by *"fill resolves at arrange"*. The
grid was the one that resolved it against its content. CSS states the rule this
was missing for the identical shape: `align-content: stretch`, the default,
stretches auto-sized rows to fill a container whose block size is DEFINITE.

The fix is arrange-only and hands out only what is genuinely spare (`innerFlow -
flowTotal`), to the lines that contain a flow-axis `fill` cell, split evenly. The
grid's REPORT is untouched, so no hug parent grew and not one baseline in the
library moved: the whole suite went from 5995 to 6000 passing with the five new
cases and nothing else.

## What the verification missed, and why

**Seventeen mutations, and every one of them asked about a DECLARATION.** Which
segment, which tint, which half, which count, which threshold, which schema. The
one geometric case the control shipped with asserted this:

```lua
expect(first.w > 0).toBe(true)
expect(math.abs(last.w - first.w) <= 1).toBe(true)
```

— ten bars, all the same width, none of them zero. It never multiplied the two
sides of the rect together. **A rect with a width is not a rect you can see**, and
no mutation of a *property* can reach a defect in the *other axis* of a rect that
property never touched: the mutation ledger was complete over the space it was
written in, and the defect was outside that space.

This is the sibling of `docs/lessons/a-default-valued-write-never-claims.md`,
which is worth reading beside it because the two failures are the same failure at
two different layers:

| | that one | this one |
|---|---|---|
| the probe read | the tint on the node | the width of the mark |
| the probe was | correct | correct |
| what was empty | the fill (the write claimed nothing) | the rect (the height was 0) |
| the screen showed | nothing | nothing |

and the family entry above both of them is
`docs/lessons/measure-the-requirement-not-the-render.md` — *painted at a size
nobody measured*.

## The instrument

`GetStyled` is the only thing that can see the FIRST of those, and it is not
reachable headlessly (a fake adapter models the write, not the engine's refusal
of it). The SECOND is completely reachable, and it was simply never asked for:
**the area of the solved rect.**

`tests/level_picker.spec.luau`'s `blankFills(adapter)` is the general form and it
is deliberately not "every zero-area node" — a spacer, an elided row and a
collapsed group are all legitimately zero, and a check that fails on those is a
check somebody waives. It reports a node whose ONLY possible paint is its own
fill:

> a leaf `UI.Box` carrying a `tint` — no text, no image, no child to be seen
> through — whose rect has no area.

That predicate does not know what a level picker is, which is what makes it worth
keeping: the next control that paints a run of tinted plates is covered by it on
the day it ships. It runs over the whole shipped gallery surface at every swept
viewport.

**The rule:** a node that paints only a fill must be asserted at an AREA, never at
an extent. Any check of the form `w > 0` on a node with no content is a check that
passes on an invisible rectangle.

See also: `docs/lessons/a-default-valued-write-never-claims.md`,
`docs/lessons/measure-the-requirement-not-the-render.md`,
`docs/lessons/the-solver-already-told-you.md` (the solver said nothing here —
a zero-height cell is inside its box, so nothing overflowed and nothing was
diagnosed; the always-on sweep was green on this surface at 9 viewports × 4 text
preferences the whole time).
