# A Button eats the swipe underneath it

**Measured live in Studio, 2026-08-13** (Facet-Showcase, Play mode, real engine).

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

## RESOLVED 2026-08-14 — ruling 6, option A, and the second measurement

The director ruled **A: the Grip goes on top and forwards presses it does not
claim** (`docs/handoff/2026-08-13-rulings-needed.md` #6). Shipped in `aa1e271`.

The rule was re-measured in a fresh Studio session on the day of the fix, with
BOTH arrangements and the control, one instrument throughout — because the first
experiment only ever showed the broken half, and "the other order works" was
still an assumption:

| arrangement | click point | what fired |
|---|---|---|
| BEFORE — button on top (`ZIndex` 2) | over the button | `BUTTON InputBegan (Touch)`, `BUTTON Activated`. **Grip: nothing** |
| CONTROL — bare grip, nothing on top | the uncovered strip | `GRIP InputBegan (Touch)` |
| **AFTER — grip on top (`ZIndex` 2)** | over the button | **`GRIP InputBegan (Touch)`. Button: nothing** |

The third row is the fix's engine half: the Grip on top DOES receive the press
the button used to eat, and the button receives nothing — which is exactly why
the framework has to forward, and why forwarding is not optional polish.

**A third trap, met on the day.** The first six injected clicks in that session
fired nothing at all, at either arrangement. The probe GUI was mounted at
`DisplayOrder = 5000` and the showcase's own surfaces sit at 10100–10300, so a
full-screen catcher above it swallowed every press. "Nothing fired" looked
exactly like the answer being hunted for. A `UserInputService.InputBegan` probe —
which fires regardless of GUI sinking — is what separated "the engine sank it
where I expected" from "the input never got here". **Log at the input-service
level as well as the instance level, or a null result has two explanations.**

**And the place was STALE while all of this ran.** Rojo live-sync adds new
modules to a running Studio session but does not update existing ones once they
pass the 200,000-char `Script.Source` write cap
(`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`);
`row_actions.luau` is over it. The running session held a 219,701-char
`row_actions` with none of the day's markers in it. That is why the live check
above is a clean-room experiment on the RULE and NOT a run of the shipped code
path: **a live test against a module over the cap is testing the build in the
place file, not your edits.** Check a marker before believing a live result.

## What the original experiment did NOT settle

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
