# DIR5 — the screen-anchored HUD expand feature, four rulings and one addendum

**Status: DONE.** One commit, `27af00f`. Facet suite **6905 → 6915**, RR **3460 →
3463**, both green. Seven mutations bite. One CONTESTED seam (item 3, and it is
named below with the exact line). One defect found en route that was not on the
brief and is fixed. The `Facet_PaintProbe` question is answered: not a leak.

---

## Per-item outcomes

### 1. The expand arrow disappears for passive content — DONE

`expandTarget.role` is a closed set of two again, decided at construction from what
the forms contain (`src/blueprint.luau`, `blueprint.Region`):

* **cover** — no form below the richest carries a focus stop or a semantic action.
  The whole collapsed form is the target: one focusable, tap/A anywhere on it, the
  hit-expander floor over the whole of it, **no painted mark at all** (the Button
  carries one empty `Zone` Box, because a Button with no children draws its own
  accessible label).
* **chevron** — some form below the richest does carry one. Its meanings are left
  alone and the affordance is a mark beside it. Mixed ladders take the chevron.

**How the retired cover's defect is avoided, which is the load-bearing part.** The
cover shipped once (`9a32399`) and a device round killed it for rendering three
stepped-down zones as EMPTY PILLS — the framework had put its own instance ON TOP of
the author's. Its retirement note named the condition for restoring it ("placing the
affordance BELOW the form") and called that **extraction-gated**, because the solver
finds the affordance as the LAST child by identity. **That reading is wrong, and the
correction is the whole fix:** the last-child lookup is a TREE fact; paint order is a
different axis. `zIndex = -1` moves the second and leaves the first alone —
`renderer.orderedChildren` sorts siblings by `(zIndex or 0, tree order)` and a node's
whole subtree travels with it, and `syncZOrder` bands the hit expander one z below its
host, so the expander goes down too. **No extraction-locked file was touched.** The
solver already spends both roles (`cover` reserves nothing and takes the region's box;
`chevron` is reserved out of the form's measure) — that code was live and unreachable.

**Why the gesture still arrives at a node that is underneath**: a cover is only
synthesized where nothing above it is interactive, and a Facet node that is not
interactive is not an `Active` GuiObject — it is the GuiButton that sinks
(`docs/lessons/roblox-input-goes-to-the-topmost-only.md`). `UI.Foreign` — the one
class whose content cannot be inspected for that — is in `UNSEEN_CONTENT` and
therefore never gets a cover; that case is pinned and still green.

**Gamepad and keyboard both proven**: EXPAND 10 ("gamepad A opens the plate and B
returns focus to the stop that opened it") and EXPAND 12 (Return opens, Return on the
focused close control closes; Space where the surface owns it) run against the cover
now and pass unchanged — the affordance is an ordinary Button, so nothing about the
focus stop, the activation verbs or the dismissal routes moved.

**The fixture carries both roles, and that is now pinned.** MEASURED on the hud demo
at 360x691: `Clock=cover Health=cover Rail=cover Tasks=cover Actions=chevron`. The
passive pills (2:14, 84, Tasks 1/3) are arrowless and whole-tappable; `Actions` — a
cluster of round Buttons — keeps its arrow. New case in
`tests/hud_composition.spec.luau`, asserted as the whole set so a fixture edit that
made every zone passive would redden.

**A measured side benefit**: the Clock zone is 80px wide where it was 100 — a cover
reserves nothing, so the value beside it gets the 20px the chevron column was taking.
(That is also what exposed the defect in "found en route" below.)

**R18 is re-verdicted, split by DIRECTION** (`tests/region_expand.spec.luau`,
EXPAND 15). The painted rule was "the framework's rect touches nothing"; it is now
"an overlap is FORBIDDEN at or above an author node, ALLOWED strictly below one",
and the sweep reads the z the adapter was told rather than assuming it. The hit-floor
rule needed a second split and this one is a real finding: **a cover's 44px floor
overhangs the row below** (measured 12px into the next region's Button on the ring
fixture). Inside the affordance's own region an interactive overlap stays absolutely
forbidden — that is the one-gesture-two-meanings collision R18 was ruled on. Across
regions it is the ordinary hit-expander overhang, which this framework already has a
measured shipped ruling on (`src/render/hit_lift.luau` lifts the host past every
sinking sibling its floor reaches into, because a floor that advertises a band it
cannot deliver is the defect). So the case asserts the LIFT HAPPENED rather than
re-litigating which ruling wins; an overhang with no lift is an advertised dead band
and reddens. Both arms are counted non-zero, so neither is a branch nothing enters.

### 2. The opaque popup background — DONE, with the instrument the third report earned

`src/region_expand.luau` `anchoredOpts` presents `scrim = "scrim"` where it presented
`scrim = "none"`.

**The mechanism, stated so the fourth report cannot be the same one.** `scrim = "none"`
mounts the catcher as `surface = "plain"` (`catchers.mountScrim` → `catcherScreen`).
`plain` is the SUPPRESSED surface: `sheet_model.classifyTags` gives it **no
`facet-surface-*` tag at all**, so nothing in the sheet's vocabulary can address that
node and its transparency is whatever the **class-default rule** happens to leave — a
number the plate neither states nor owns, on the one node in the framework that covers
the entire screen. `scrim` is the opposite: the role carries the theme's own
`scrimOpacity` through `sheet_model.SCRIM_RULE`, which is also the single entry in
`PREFERENCE_RULE_PROPS` — so ADR-0035's `PreferredTransparency` composition applies by
construction, uncapped (`backdropTransparency(base, 0) == 0`; pref = 0 is a player
asking for an opaque backdrop and gets one). It is also the right product answer: a
disclosure plate is a modal that covers content, and the dim is how a player is told
the screen behind it is not live. The Menu keeps `none` — a menu is a small list at a
button, not a plate over the screen.

**`popup_catcher_paint.spec.luau` is rebuilt so it reddens on the state the director
measured.** Its two shipped cases assert the DECLARATION (`decorationSlot=nil
surface=plain`), and a declaration is not a paint — which is exactly why they were
green over three reports on the twin path their own header names. The new section
**resolves the paint**: it classifies the catcher the way `classifyTags` does, walks
the BUILT sheet in cascade order, and reports the value **and the rule that supplied
it**. Four cases:

* the oracle can tell a role from a class default (`plain -> 1 by 'Button default'`
  vs `scrim -> SCRIM_RULE`), so the cases built on it read a real distinction;
* a region's expand plate mounts a full-viewport barrier that wears the scrim role
  — **REDDENS at the state the director measured**, verified by reverting the one
  line: `expected plain to be scrim`;
* the PreferredTransparency composition, uncapped, against the declared one-entry
  rule list;
* **the synthesized scrim ROOT is linked to the same theme sheet as the screen it
  covers.** This is the other way the same pixel goes opaque and the role change
  cannot reach it: in native mode the adapter writes no `BackgroundTransparency` at
  all (an explicit write would permanently defeat every surface rule), so a catcher
  root the sheet never reached paints the ENGINE default, which is 0 — opaque under
  every role including this one. The scrim mounts on its own root, after the screen
  it covers, which is exactly the shape that inherits nothing. Driven through
  `fake_target`'s `trackThemeRoots` seam. It passes today; it is a fence.

`tests/transient_over_live.spec.luau`'s expand-plate case is extended as asked. Its
predicate is a NEGATIVE (the plate added no PAINTING role) and a `plain` catcher
passes it while painting whatever the class default leaves — so the positive is added
beside it: the barrier is the scrim role.

### 3. The plate thinner than its own content — FIXED unlocked; the residue is CONTESTED

**Reproduced headlessly at the director's numbers.** Their device: panel 135x98 at
x=151, content 159..294 against a right edge of 286. My headless repro at 360x691:
panel **208x98 at x=130, ClockStack children spanning 138..346** against a right edge
of 338 — the whole content width, starting one inset in, ending 8px past the panel.
Same defect, different text metrics.

**Cause**: `plate.w` measures FORM 1, and it was written straight onto a `VStack` that
also declares `padding`. A padded box's declared width is its OUTER width, so the
content box was `plate.w` minus two insets and the form, measured against `plate.w`,
overflowed it by exactly that — at every viewport, not just the director's.

**Fix (unlocked)**: the plate HUGS its content. The panel is the content plus the
padding, the close disc's reserve and the straddle, and hugging is how a box says
"whatever those come to" — nothing re-derives an inset, and a package with fatter
padding moves the panel rather than cutting the content. The one declared width left
is the `fill` correction (a form declaring `width = fill` gets `plate.max`). After:
panel 268x64 at x=84, plate 84..336, content 92..300 — inside, with the disc clear.

**CONTESTED, with the exact seam.** The composition measures form 1 against
`viewport - gutters` and calls the answer a plate, but the panel it will actually be
wrapped in is wider than that answer by its own chrome. A form whose natural width
lands within the chrome of the cap therefore produces a panel wider than the gutter
allowance. The number that would close it — the plate chrome — can only reach
`src/layout/composition.luau` (unlocked) through `resolveCtx`, and `resolveCtx` is
built in **`src/layout/solver.luau` around line 1113**, beside
`expandGutter = (ctx.metrics.space :: any).m` — extraction-locked. The honest shape is
one more field there (`expandPlateChrome`) subtracted in `composition.luau`'s plate
measure, or `plate.w`/`plate.max` redefined as the OUTER box. **What the unlocked-side
fix honestly covers**: the overflow is removed at every width below that band, which
is every case in every fixture and every case the director measured. What it does not
cover is the last `chrome` px of the range, where the panel now exceeds the gutter
allowance instead of the content exceeding the panel.

**The second half of item 3 is diagnosed and is NOT a defect.** `ScoreHomeT` ("12")
and `ScoreAwayT` ("9") solving width 0 while `TimerText` ("2:14") solves correctly
beside them is the **hidden form-1 subtree**, not a numeric-text measurement bug.
Swept across eleven viewports (320x640 … 1280x720): wherever `ClockStack` is
STANDING both texts solve real widths (36 and 18 at 390x844; 54 and 27 at ten-foot),
and the zeros appear only where `activeForm = 2` — where the framework marks **every
node of that subtree hidden** (`visibleOf = false` at all 11 nodes, which the probe
confirms and `hud_composition.spec` already pins). A hidden subtree is arranged
against a 0x0 box and produces meaningless rects; `TimerText` reads 60 there for the
same reason, it is just a longer string. The director's live reading of "VISIBLE" is
almost certainly a Roblox inspector reporting a descendant's own `Visible` property
under a parent that is hidden. **If the director can still see those glyphs painting
on a device, that is an engine-side paint latch and not this** — it would need the
whole-live-tree diff, not a model instrument, and I have not manufactured a model
check that could not see it either way.

### 4. The close becomes an integrated floating corner control — DONE

`ExpandPanel` is a ZStack of two children: `ExpandPlate` (the raised plate carrying
the author's form 1) and `ExpandClose`, a circular icon Button aligned to the panel's
top-right. MEASURED after: panel 268x64 at x=84, plate 84..336 y 174..222, disc 36x36
at (316,158) — **16px outside the plate's right edge and 16px above its top**, i.e.
centred on the corner, half in and half out.

Kept exactly as asked: the `close` glyph through `icon` (so a package paints art over
it and a control never names an asset), `label = "Close"` for the screen reader, the
focus ring, and the 44px effective target (the disc paints at the theme's
`controlSizes.compact.height` and the renderer's hit floor supplies the band —
asserted at 44 near and at 66 at ten-foot). Keyboard and pad closability are the same
cases as before, unchanged and green.

**The two geometry decisions, both structural rather than tuned:**

* **The straddle is a MARGIN on the plate, never an offset on the disc.** That is what
  keeps the disc inside the PANEL's box — and the anchored placement's safe-area clamp
  knows only the surface's box, so a disc placed by an offset would paint outside every
  rect the placement can see and could be pushed off-screen at the edge. With the
  margin, clamping the panel clamps the disc.
* **R18 by construction.** The plate's RIGHT padding is the disc's own metric, so the
  content box's right edge is `panel - straddle - disc` and the disc's left edge is
  `panel - disc`: the difference is the straddle, which is never negative. That holds
  for any theme ladder and any content, and the spec sweeps every author node on the
  plate for an intersection with the disc and asserts the empty set. Removing that
  reserve reddens it.

### 5. Shoulder hints gate on PRIMARY input — DONE, at the root, and the brief's premise is corrected

**The gate was already on primary.** `showcase_chrome`'s `gamepadActive` reads
`env:get("effectiveInput") == "Gamepad"`, and `effectiveInput` is
`interactionClasses.primary` translated into the platform's vocabulary
(`environment.luau:587`). Re-gating on `interactionClasses.primary == "gamepad"` would
have been byte-for-byte the same predicate and would have moved nothing — manufactured
churn over a live defect. **I did not make that edit**, and the file is untouched.

**The fact underneath is what is wrong.** `interactionClasses` takes
`preferred == "Gamepad"` as the whole answer, and `preferredInput` is
`UserInputService.PreferredInput` verbatim — which the director measured as **Gamepad
on a desktop with three pads connected while they drove with a mouse**. That
preference is STICKY: one drifting thumbstick, or Studio's virtual pads, sets it for
the session and nothing brings it back. (Confirmed live in the connected Studio at
Edit: `PreferredInput=KeyboardAndMouse | LastInputType=MouseMovement |
GamepadEnabled=true | pads=1` — the two facts agree when the pad is quiet and diverge
exactly as reported when one is not.)

**Fix, in `src/client/roblox_env.luau`'s `pushInput`**: when the preference reads
Gamepad **and** the device has a mouse **and** `GetLastInputType()` is a pointer or
keyboard type, publish `KeyboardAndMouse`. It is the mirror of the rule already
written one layer up for the phone case ("a preference the player has not expressed
yet cannot outvote what the device physically is"), applied on the side the engine's
guess is sticky on. It lives in the platform adapter because it is about an engine
fact's known behaviour, which is that module's whole job — the same place
`capabilities.gamepad` already corrects `GamepadEnabled` with `sawGamepadInput`.

Every clause is load-bearing and each has a case: no mouse → the preference stands (a
console is a pad player whatever the last input was); the first pad press hands
primacy straight back, and a mouse move takes it away again (the `LastInputTypeChanged`
connection now pushes on a family change, not only on the first pad press, and only on
a family change so a mouse move is one comparison rather than a transaction);
`GetLastInputType` absent → taken at its word; and the **capability is untouched** —
`classes.gamepad` still reports the pad as live, because it is. Only PRIMARY moved,
which is what ADR-0015 Decision 2 says primary is for.

**Other `Facet.inputHint` consumers**: there is exactly one (`showcase_chrome:385`),
plus one hand-rolled twin in `examples/gallery/client/init.client.luau:1017` reading
the same `effectiveInput`. Both are fixed by the root correction. RR calls
`Facet.inputHint` **zero** times and reads `effectiveInput` at exactly one line
(`FacetSponsor/init.luau:672`, gamepad-only seeded focus on table engage), so it gets
the same correction with no game-side edit.

**Blast radius, stated plainly**: this moves `interactionClasses.primary` — and with it
`effectiveInput`, ten-foot/density decisions and every pad affordance — in exactly the
sessions where the engine reports Gamepad, a mouse exists, and the last input actually
seen was a pointer or keyboard one. Headless and RR are unaffected (nothing sets the
new engine read). The negative control is pinned: an ordinary pointer desktop with no
pad is byte-identical.

---

## Found en route (not on the brief), fixed

`tests/hud_chrome_rotation.spec.luau` went red three ways under item 1's narrower
clock zone: **the settled screen and a fresh mount of the same screen disagreed by
62px** (`80.0x30.0@298.7,120.0` settled vs `@298.7,58.0` fresh, at 678x339).

The hud fixture's `reachEpoch` — documented as "every composition INPUT that can move
a zone's width" — did not include the platform **insets**. The adapter publishes the
six platform facts ONE AT A TIME (`viewportRect` first), so the epoch turned over
while the screen still wore the previous orientation's insets; the reach sample taken
in that half-published state (the clock at its RICHEST form, 208 wide, reaching well
into the chip row) latched `reaches = true`, and the latch is monotone within its
epoch by design. The zone then reserved against chrome its settled form does not
touch. It was invisible while the clock was 20px wider, because both states
overlapped the chip row.

Fix: `platformChrome`'s `insets` and `band` join the epoch token — one read, all four
platform facts, since that is the single authority the HUD's box comes from. After:
both paths land on 58. Removing it again reddens all three cases.

---

## `Facet_PaintProbe` (order 20100) — NOT a leak

It is the hud fixture's own probe surface. `examples/gallery/scenarios/hud.luau:2257`
declares `UI.Screen{ id = "PaintProbe" }`; it is presented at `:2384` and dismissed
through the fixture's own teardown at `:2374-2377` (`presenter.dismiss(probeHandle)`).
`tests/hud_paint_probe.spec.luau` drives it by that exact path. Nothing else in the
repository declares that id (one grep, one hit in `examples/`, the rest in that spec).
No owner to report, and no unrelated demo touched.

---

## ADR-0040 row text (item 1 — public default behaviour; controller appends)

| B-16 | `UI.Region{ expand }`'s synthesized affordance on a form that carries no control of its own | a **chevron** beside the form → a **cover** over the whole form (`expandTarget.role`, a closed set of two again) | the affordance a collapsing region synthesizes changes SHAPE and TARGET on the commonest case: a passive compact form draws **no mark at all** and the whole of it becomes the tap/A target at the standard hit floor, where it used to draw a caret in a column the form's own measure reserved. Shipped geometry moves — the form gets the mark's column back (the HUD demo's clock zone 100 → 80 at 360x691), so a value that was being cut may now fit and a screen tuned against the reserved width re-lays out. Director ruling, DIR5 2026-08-21: *"the controls should just be tappable by default to open more without the arrow. we'll only need the arrow if the thing is already a control the user can tap."* The cover was retired by the 2026-08-21 device round for painting over the author's content; it returns declared `zIndex = -1`, so it and the hit expander banded below it paint UNDER every form — the retirement note's own condition ("placing the affordance BELOW the form"), met without an extraction, because the solver's last-child lookup is a TREE fact and paint order is a different axis. `UI.Foreign` and the lazy regions still force the chevron. Rascal Rally declines the default on every multi-form region (`ResultsScreen.luau`'s `region()` helper) and is unaffected, pinned game-side | `tests/region_expand.spec.luau` EXPAND 5/7/15/17/18; `tests/hud_composition.spec.luau` (the demo carries both roles); RR `tests/facet_composition_collision_contract.spec.luau` (the opt-out fence + a positive control) |

---

## Commits

* **`27af00f`** — *"the passive pill IS the affordance, and the framework finally puts
  itself underneath"*. Facet only. Twelve paths through
  `tools/commit_isolated.py`; `tests/ten_foot_metrics.spec.luau` is committed by the
  `ExpandPlate` **marker** (one hunk — a stale panel path) because the concurrent
  radii/strokes round owns seven other hunks in that file, and the dry run confirmed
  those seven are dropped.
* Rascal Rally has **no git repository** (`games/RascalRally/.git` does not exist), so
  its one changed file — `code/tests/facet_composition_collision_contract.spec.luau`
  — is left in the working tree.

## Suite tails

| | baseline (content-pinned) | after |
|---|---|---|
| Facet | **6905 passed, 0 failed** — `git archive` of `23081c3`, run in a private copy | **6915 passed, 0 failed** — same copy, this round's files only |
| Rascal Rally | **3460** | **3463 passed, 0 failed** — private `GameStudio/ui/Facet` + `games/RascalRally` pair |

Baselines are pinned **by content**, not by timing: every measurement ran in
`git archive HEAD` copies with only this round's files overlaid. The concurrent round
moved HEAD twice mid-flight (`f95afbf` → `23081c3`), and its in-flight
`tests/ten_foot_metrics.spec.luau` edits contaminated one intermediate run (8 reds,
all in that file, all theirs) — the isolated copy is rebuilt from HEAD for that file
and re-patched with my hunk alone, which is what the numbers above are measured on.

**Confirmed after the commit**: a fresh `git archive` of the committed HEAD (`27af00f`,
which carries the concurrent round's landed work too) runs **6915 passed, 0 failed** —
the same number the isolated copy measured, so the delta is this round's and nothing
in it depends on an unlanded edit.

`stylua --check` clean on all eleven files. `check_source_size` PASS (`blueprint.luau`
is nowhere near the band; the six band files are untouched). `check_doc_style`,
`check_comment_codes`, `check_brand_drift` all PASS.

## Mutations (each applied to the isolated copy, run, reverted)

| # | mutation | red |
|---|---|---|
| M1 | a passive form keeps the chevron (`role = "chevron"` forced) | **6** |
| M2 | the cover's `zIndex = -1` dropped, so it paints above the form | **4** |
| M3 | the plate sized to `plate.w` again instead of hugging | **1** |
| M4 | the plate stops reserving the close disc (right padding → `space.s`) | **1** |
| M5 | the sticky-Gamepad correction removed | **2** |
| M6 | the reach epoch forgets the platform insets again | **3** |
| M7 | the expand catcher back to the suppressed surface (`scrim = "none"`) | **3** |

M7 is the red-first proof for item 2 specifically: it is the state the director
measured, and the rebuilt `popup_catcher_paint` case reddens on it
(`expected plain to be scrim`) where the shipped declaration checks stayed green.

## RR lockstep

RR is a **non-consumer** of region expand. Evidence, whole game folder, no extension
filter:

| pattern | hits | |
|---|---|---|
| `expandTarget` | **0** | |
| `region_expand` | **0** | |
| `expandOpen` | **0** | |
| `presenter\.expand` | **0** | |
| `inputHint` | **0** | never calls it |
| `UI\.Region` | 7 (3 in `code/src`) | all one screen |
| `expand =` | 5 (3 in `code/src`) | the OPT-OUT |

The only production `UI.Region` call site is
`code/src/client/FacetSponsor/ResultsScreen.luau:2839`, wrapped by a local `region()`
helper whose whole purpose is to decline the default
(`:2836` — `if spec.expand == nil and spec.recover ~= "none" and #(spec.children or {}) > 1 then spec.expand = "none" end`),
a consumer-lockstep decision documented at `:2806-2827` when the feature landed.

**No production edit was manufactured.** What was added is the compatibility evidence
the root constitution asks for — a fence, because the opt-out is a line of GAME code
that someone who does not know what it is holding back can delete. New block in
`code/tests/facet_composition_collision_contract.spec.luau`, three cases: no region on
the shipped results screen is `expandable` at any of the five matrix viewports; the
framework synthesized no `expandTarget` node anywhere in the mounted tree (with a
not-vacuous guard that the walk got a tree); and a **positive control** — the same
pinned Facet, driven to a two-form passive ladder, really does synthesize a
`role = "cover"`, so the two zeros are distinguishable from "the affordance no longer
exists". Without that control the fence would pass against a Facet that had lost the
feature entirely.

---

## Concerns

1. **CONTESTED — the plate chrome cannot reach the composition (item 3).** Named
   above with the line: `src/layout/solver.luau` ~1113, beside `expandGutter`. Until
   that field crosses, a form whose natural width lands within the plate's chrome of
   `viewport - gutters` produces a panel wider than the gutter allowance. Nothing in
   any fixture is in that band today; a fixture with a very wide form 1 would be.
2. **Item 2's fix is what the director prescribed, and the engine half is unverified
   by me.** I did not reproduce `GetStyled = 0` live — the director did, and a Play
   session would have disturbed the concurrent round's Studio. The role change is
   correct on the mechanism I *can* see model-side (a suppressed surface owns no
   transparency); the second live possibility — a scrim root the StyleLink never
   reached — is fenced by the new `rootThemeSheets` case but is green today, which
   means it is a fence and not a fix. **If the popup is still opaque on the next
   device round, that root-link case is where I would look next, and it should be
   re-checked with `GetStyled` on `/__scrim__/catcher` after this change rather than
   with a plain property read.**
3. **Item 5 changes a framework-wide fact, not a chip.** The brief scoped it to the
   showcase's `When`; the honest fix was one layer down, because the gate the brief
   named was already correct. `interactionClasses.primary` now answers differently in
   the mouse-plus-idle-pad session. I judged that in-scope because re-gating alone
   would have been a no-op the director would have seen fail on the next device round,
   but it is a bigger surface than the brief asked for and deserves a look.
4. **The cover's 44px floor overhangs neighbouring regions** (measured 12px). It is
   `hit_lift`'s governed population and the lift delivers it, and the spec asserts the
   lift — but a HUD with a very short zone directly above a control now has the
   framework's band over that control's top edge, resolved in the band's favour by a
   ruling made for a different case (a 44px divider that delivered 26px). Worth a
   director look on a device: it is the one place where item 1 gives the framework a
   bigger footprint than the chevron had.
5. **The reach-epoch defect was in the fixture and the class is not fixed.** The
   monotone-within-epoch latch is still load-bearing (the reservation feedback can
   change a zone's WIDTH, so a non-monotone sample can 2-cycle), which means the
   fixture's give-way decision remains history-sensitive whenever a NEW input to a
   zone's width is added and not added to the epoch. The epoch is now correct for
   every input I can find; there is no mechanism that makes it stay correct.
6. **Item 3's second half is diagnosed as not-a-defect and the director may
   disagree.** If they can see "12" and "9" painting in the collapsed state on a
   device, the model is unanimous that they are hidden — which would make it an
   engine-side paint latch, the class the HUD paint-latch round already met once, and
   a whole-live-tree diff rather than a model instrument is what would find it.
