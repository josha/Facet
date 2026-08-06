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

**1. Nothing read the diagnostics.** This is the whole lesson. LuauUI's solver reports
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
> where you think it is. LuauUI will tell you — if you ask it.
