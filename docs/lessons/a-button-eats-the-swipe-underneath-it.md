# A Button eats the swipe underneath it

**Measured live in Studio, 2026-08-13** (LuauUI-Showcase, Play mode, real engine).

`src/controls/row_actions.luau:3322` justified putting the drag hit surface
*behind* the row's content with this claim:

> Roblox delivers InputBegan/Changed/Ended to every Active GuiObject under the
> point independently of paint order, so this background Grip still captures a
> drag while a button INSIDE `content` still receives its own tap, unaffected.

**The first half is false.** The engine delivers `InputBegan` to the topmost
interactive object only; a `GuiButton` sinks it, and the Active Frame behind
receives nothing.

## The experiment

An Active `Frame` (the "Grip") at `[100..500]x[300..420]`, and a `TextButton`
painted on top of it at `[200..400]x[320..400]` — the exact
background-Grip-under-content shape `row_actions` builds.

| click point | what fired |
|---|---|
| `(150, 360)` — grip only, nothing on top | `GRIP InputBegan (Touch)` |
| `(300, 360)` — **over the button** | `BUTTON InputBegan (Touch)`, `BUTTON Activated`. **The grip: nothing.** |

The first row is the control that makes the second row mean something: without
it, "the grip got nothing" is equally explained by "this injection never produces
`InputBegan` at all".

## Consequence

**A row whose `content` contains a Button cannot be swiped where that button
covers it.** The gesture simply never reaches the hit surface. Rows whose content
is inert (text, images) are unaffected, which is why this has not been noticed —
every swipe demo built so far uses inert content.

`table.luau`'s `rowBlueprint` puts its row "Hit" `Button` behind its "Cells" in
the same array-order relationship and is cited by the same comment, so the same
question applies to any Table row with an interactive cell.

## Two traps this experiment nearly fell into

1. **Injected input arrives as `UserInputType.Touch`, not `MouseButton1`.** The
   first two readings filtered on `MouseButton1` and showed "nothing fired"
   everywhere — an answer that looked like strong evidence for the conclusion I
   was expecting. Filtering on the wrong input type manufactures a false
   positive that agrees with you.
2. **A negative result needs a positive control in the same session.** "The grip
   received nothing" is only evidence once "the grip receives something when
   nothing covers it" has been shown with the identical instrument.

## What this does NOT settle

The repair is a **design decision**, not an obvious patch — the hit surface has
to be reachable without stealing taps from real controls, and the platform-native
answers (put the Grip on top and forward taps; let the button offer the gesture
upward; hit-test in the framework rather than relying on engine delivery) trade
off differently. Recorded in `docs/handoff/2026-08-13-rulings-needed.md`.

**Do not write a headless test for this and call it covered.** The fake target
models handler wiring, not the engine's input-sinking behaviour, so a headless
"the grip receives the gesture" test passes today and would keep passing while
the real device stayed dead. This is a live-engine claim and needs a live-engine
check.
