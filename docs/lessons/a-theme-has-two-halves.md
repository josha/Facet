# A theme has two halves, and installing one is invisible

**Found:** 2026-08-05, chasing the 4px residual left by
[the ornate geometry fix](../../artifacts/performance-stress-places/optimization-log.md)
(L-25 → L-26).

**Cost:** every lifted label in the perf lab 4px short under `fantasy_ornate`; one
button's glyph rendered as nothing; and — worse — every "ornate" performance number in
that pass was taken on **flat geometry with ornate paint**, and nobody knew.

## The two halves

```
decoration    adapter.setThemePackage(pkg)        -- the ART
metrics       env:set("themeMetrics", snapshot)   -- what the SOLVER reserves
```

`theme_controller.install` commits both in one transaction for exactly this reason. The
perf lab called the first one directly and skipped the second entirely.

Nothing errored. The screen was visibly, correctly themed — carved borders, gilded
corners, per-state art — because **paint is the half you can see**. The solver went on
measuring every control with Studio Neutral.

## Why it presented as a 4px bug

The paint seam takes the recipe's `contentInsets` out of a box the measure seam sized
with the neutral package's button padding:

```
box  = host - 28    (fantasy-ornate contentInsets, 14 per side)
want = host - 24    (Studio Neutral buttonPadding, 12 per side)
                      -> short by 4px, at every size and every label length
```

Both terms are constants, so the shortfall is a constant. The previous investigation read
"constant, not proportional" as *the wrong inset was reserved* and went looking at the
measure seam — which turned out to be correct and always had been. A content-sized
`Open` button solves to 69px flat and 120px ornate: the inset **is** added on top of the
node's own padding.

**A constant offset tells you two numbers disagree. It does not tell you which one is
in the wrong place.**

## The tell that named it in one read

`TextSize = 18` on a button under `fantasy_ornate` — 18 is Studio Neutral's `control`
size; ornate's is 17. One property, read from the live instance, and the whole story is
there: *this surface's text was measured by a package it is not wearing.*

Every geometry number was consistent with that and with nothing else. It was available
from the first measurement and went unasked for two rounds.

## Rules

1. **Ask which half of a theme is installed before reading anything else off a themed
   screen.** A themed *appearance* is not evidence that the layout knows about the theme.
   Compare one solver-owned value — a type-ramp size, a control height — against the
   package that is supposed to be on.
2. **An install path that can succeed halfway will.** `setPackage` is a legitimate
   adapter call (the verification runner makes it before the controller's transaction),
   which is what made the half-install look like a whole one at the call site. Go through
   the controller, or commit both halves yourself; never one.
3. **A constant discrepancy is a disagreement, not a location.** Prove which side moved
   before deciding where the fix goes — here, one headless solve with and without the
   snapshot settled it in a minute and would have saved a round.
4. **A performance number taken under a theme nobody installed is a wrong number, not a
   noisy one.** The related trap is recorded in L-23: a selector that *records* a theme
   name it never applied. This is the same failure one layer down — it applied half.
5. **The theme is an input to any measured layout constant.** A row height derived from a
   viewport width and a type scale is still wrong under a package whose controls carry a
   carved border. Same class as
   [`the-solver-already-told-you.md`](the-solver-already-told-you.md): a number derived
   from facts is only as complete as the facts you asked for.
