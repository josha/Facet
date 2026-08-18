# A far margin must buy something — aligning in a box you did not grant

**Found:** 2026-08-14, Roblox Studio, showcase `table_columns` (retired 2026-08-16
into the playlist tutorial) under Pixel Quest
and Glossy Touch. Director: *"in columns you can resize in the showcase, the
triangle table header sort indicator appears outside when themed."*

## The measurement, before the story

Live, `Facet_TableColumns`, one header cell (`Head-name`), its plate (`Column`),
and its sort glyph (`SortMark`), in absolute pixels:

| package | cell | mark | reserve declared | reserve **spent** |
|---|---|---|---|---|
| studio-neutral | `[12..227]` | `[220..227]` | 14 | **0** |
| pixel-quest | `[28..234]` | `[227..234]` | 16 | **0** |
| glossy-touch | `[39..238]` | `[230..238]` | 14 | **0** |

Nine configurations — the default plus all eight shipped packages, resizable and
not, at 200 px and at 600 px — and the spend is `0` in every one of them. The
mark's far edge lands **exactly** on the column boundary, every time.

Pixel Quest's `chrome.control` carves `contentInsets = 16`, so `[218..234]` is
the plate's border. The glyph was painted entirely inside that border: on the
carved wooden frame, outside the box. Glossy Touch carves 14 and did the same.
The flat packages put the same glyph on the same boundary and nobody could see
it, because a boundary nothing paints is invisible.

**"Default theme is fine, two themes are wrong" was never about those two
themes.** Every package was wrong. Five of the eight paint something at that
edge, so five of them show it.

## The cause: one argument

`src/layout/solver.luau`, the `zstack` arm of `arrange`:

```lua
local availW = math.max(0, innerW - ml - mr)   -- the box the child is GIVEN
local w, h = measure(ctx, child, availW, availH)
...
local x = innerX + ml + alignOffset(align, innerW, w)   -- ...aligned in innerW
```

The 2026-07-31 round taught this loop that *a margin is room the child does not
get* — and taught it only to `measure` and to the `fill` branch. A hugging child
had the margins subtracted from its offer and was then aligned in the box it had
been **denied**. For `start` the two agree (`x = ml` either way), which is why it
survived for a year. For the other two they do not:

- `end`: `x = ml + innerW - w`, so the far edge is on the stack's inner edge and
  `margin.right` buys **nothing**. A `margin.left` is worse than useless — it
  shoves the child clean *through* that edge by its own width (measured: 220 in a
  200 px box).
- `center`: centred in the full box and then displaced by `ml`, so an asymmetric
  margin moves the child by half the wrong amount.

The fix is one word twice: align in `availW`/`availH`.

## Why nothing caught it

**The declaration and the comment agreed with each other, and neither agreed with
the pixels.** `controls.table.sortMarkMargin` ships in every theme package with a
docstring — *"keeps the ▲/▼ clear"* — and `table.luau` spends it, correctly, in
the vocabulary the framework publishes. A reader checking whether the reserve
exists finds it declared, themed, and spent. Only a *rect* says it bought nothing.

Worse, the control had already **written the defect down as a fact of life**:

> `-- ...a ZStack child's FAR margin is not spent by end-alignment`

That sentence is true, and it is a bug report, and it sat in a comment being read
as a design constraint. A workaround was built on top of it for the title. Nobody
asked why.

## The two rules

**1. A reserve is a number you can subtract from a rect.** If a layout declares a
clearance, some test must read the two edges and subtract. "The property is set",
"the metric resolves", "the margin is passed" are all upstream of the only
question, and all three were green here. Same family as
[decoration-paints-to-the-edges](decoration-paints-to-the-edges.md) (a policy
string no consumer branched on) and
[a-compensation-is-only-true-when-it-was-computed](a-compensation-is-only-true-when-it-was-computed.md).

**2. A corpus uniform along an axis cannot test that axis.** Every Table spec in
the suite mounted the default snapshot. The whole class *"correct flat, wrong once
a package paints something"* was outside what the suite could express, so the
instrument that found this was a director looking at a screen. The repair is not
a test for this bug; it is
`tests/table_themed_header.spec.luau`, which runs the header band across all nine
rows and asserts the spend, the plate's carved border, and the title/mark
clearance. (The same trap, the same week, on line heights: every shipped theme
gave every text role the same one, and two mutations survived until a deliberately
ragged fixture existed.)

## The blast radius, and what a shared fix costs

The whole suite moved **three** assertions, which is the argument for fixing the
solver rather than the caller:

- the header sort mark (the report);
- a Table header **title** that reserved one term where it needed two —
  `sortMarkMargin` is the mark's clearance from the boundary, not the glyph's own
  column, so a title inset by it alone ends where the mark *ends* and runs its
  whole width. It also only paid the reserve when the column was trailing-aligned,
  which merely described which title had been long enough for somebody to notice;
- the drag-ghost chip deck, via
  [one-word-two-subsystems](one-word-two-subsystems.md): each chip's
  `alignV = "center"` meant *"center my label"* and its parent read it as
  *"center me"*, so the honest margin halved a deliberate 2 px diagonal stagger to
  1 px. The word moved to the Label, where it means one thing.

And one **characterization test pinned the defect** — `a NON-fill child keeps the
alignment it always had` asserted the centred-then-displaced number, justified by
"the table control's ghost chip stack is exactly this shape". It is not that
shape. A pin whose stated consumer is imaginary is not a baseline; re-aim it, and
make the consumer claim a real assertion in the same change.

## Related

- [a-fixed-box-cannot-hold-a-themes-frame.md](a-fixed-box-cannot-hold-a-themes-frame.md)
- [one-word-two-subsystems.md](one-word-two-subsystems.md)
- [the-solver-already-told-you.md](the-solver-already-told-you.md)
