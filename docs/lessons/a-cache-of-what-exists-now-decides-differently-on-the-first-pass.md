# A cache of "what exists now" decides differently on the first pass

**Found 2026-08-17, closing NM-H4a — nine rounds after it was first reported.**

`syncZOrder` walks the tree assigning ZIndex, and reserves an extra slot below any
node that carries a hit expander (the adapter paints those at `hostZ - 1`, so
without a reservation the number belongs to whatever node was walked immediately
before). It decided by asking `lastHitRects` — **the set of expanders that exist
right now**.

On a first structural sync that set is empty. The rects have not been pushed yet.
So nothing is reserved, and every expander lands on the previous button's number.
Measured on a live tree, on a freshly mounted screen:

```
z=26  /HudScreen/Hud/Rounds/RoundStrip/R1   36x36 @59,62
z=26  LuauUIHitExpander                     44x44 @97,58    <- R2's
z=27  /HudScreen/Hud/Rounds/RoundStrip/R2   36x36 @101,62
```

Then any later structural sync — a rotation gives you one — finds the rects
present, reserves, and the whole band moves underneath everything. Driven against a
fresh mount: **73 of 86 nodes diverged, on `zIndex` alone.**

## The rule

**A derivation that runs on every pass must key on facts that are true on the
FIRST pass.** A hit floor is a property of the class; the expander is a consequence
of it. Reading the consequence made a band that should be a pure function of the
tree into a function of history — and history includes "how many times has this
surface re-synced", which is exactly what a device session accumulates and a
headless replay does not.

Ask of any cache read during a derivation: *what does this answer before anything
has run?* If the answer differs from what it answers later, the derivation has two
outputs for one tree.

## Why nine rounds

Every instrument in the repository, and five more added during the investigation,
asked a MODEL-side question: does the framework agree with itself, does the engine
agree with the framework's rects, is the node visible, is it faded, is it clipped.
`zIndex` is the one property that is **correct in the model** and **decides the
outcome in the engine**. The model agreed with itself at every step, which is
precisely what was being measured.

The answer came from driving the real adapter and diffing the WHOLE ENGINE TREE
against a fresh mount at the same viewport. That is a cheap thing to do — one Play
session and a table compare — and it should be the second thing tried on any defect
that reproduces on hardware and nowhere else, not the tenth.

See also
[`a-seam-that-is-not-told-its-owner-will-guess-one.md`](a-seam-that-is-not-told-its-owner-will-guess-one.md)
and [`the-solver-already-told-you.md`](the-solver-already-told-you.md).

## The measurement that nearly sent it wrong again

`/HudScreen/Hud` reads `BackgroundTransparency = 0.00` on the instance while
`GetStyled("BackgroundTransparency")` returns `1`. **When a StyleSheet owns a
property, the instance property is not the paint verdict.** Reading it would have
"found" an opaque full-screen frame covering the HUD, which is not there — a
confident wrong answer of exactly the kind this defect had already produced twice.
