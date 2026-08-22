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

---

# FIX ROUND 1 — appended 2026-08-21, answering `task-dir5-review.md`

**Status: DONE for the two MEDIUMs assigned to me (M4, M1) and five of the six
LOWs.** Facet **6949 → 6957**, RR **3461 → 3464**, both green, both content-pinned
at the current HEADs. Five new mutations bite. The geometry HIGHs (H1, H2) and M2's
device evidence are not mine this round and are not touched — nor is
`src/region_expand.luau`, whose `anchoredOpts` comment carries a sentence this round
proves wrong (flagged below for whoever holds that file).

## M4 — the input-primacy flap: the house record applied, not re-derived

**The review is right and the finding is worse than it looks.** DIR5's item 5 read
`UserInputService:GetLastInputType()` — the exact function this repository already
refused, in a ledger entry it *enforces*. `tools/check_input_authority.py`
INPUT-100/101, on the consumer's `InputIdentity.luau`: *"deadzone drift flaps it
several times a second — so the classifier reads the raw stream and requires a
DELIBERATE act (past a 0.25 deadzone) before identity changes."* On the director's
own hardware (mouse in hand, three pads connected, one drifting) DIR5 traded a
preference that was stickily WRONG for one that FLAPS, and `primary` carries density,
scroll indicators and every pad affordance with it.

**The remedy is the house record, clause for clause** (`src/client/roblox_env.luau`):

* `GetLastInputType()` is **gone**. Primacy reads the RAW stream, which is what
  INPUT-100 prescribes and what `InputIdentity.luau` does.
* `InputBegan` is a press by definition and is taken at face value — including for a
  gamepad, where `InputBegan` can only be a BUTTON (sticks arrive on `InputChanged`).
* `InputChanged` claims the pad **only past `DELIBERATE_DEADZONE = 0.25`**, the same
  house number, and only for `Thumbstick1`/`Thumbstick2`. Drift never qualifies.
* **Mouse MOVEMENT is noise too** — `InputIdentity`'s own list says so, and it is the
  symmetric half of the deadzone. A click or a wheel is the deliberate pointer act.
* Nothing is claimed until something deliberate happens: `deliberateClass` starts
  `nil`, and a `nil` class leaves the engine's preference exactly as reported. So a
  session that has seen no input, and any engine whose raw stream this module cannot
  reach, are byte-identical to before.
* `capabilities.gamepad` is still untouched, and the `LastInputTypeChanged`
  connection is back to what it was at HEAD: a capability latch only. Nothing about
  primacy is decided there any more.

**The gate caught the new subscriptions and the remedy is the one it prescribes.**
`check_input_authority.py` flagged `roblox_env.luau: Input*:Connect×2` — correctly,
because reading the raw stream is exactly the class it polices. It is allowlisted
now with its inventory class (`2`), the platform text that makes it impossible (the
same INPUT-100/101 text the consumer's entry carries: no device-change event in IAS,
a STICKY `PreferredInput`, and a `GetLastInputType` this repo refused), and the event
that retires it — *the same event*, so the two entries retire together.

**Red-first.** The flap case drives the director's hardware: a deliberate mouse
click, then **forty** interleaved noise events (stick at 0.1 — under the deadzone —
alternating with mouse movement), and asserts the COUNT of changes to
`effectiveInput`, not its final value (a fix that flapped and happened to land right
would pass a value check). Then one deflection at 0.9 claims the pad, so the deadzone
is shown to be a threshold rather than a mute. Eleven cases, all green:

```
nothing deliberate yet: the engine's preference stands, whatever it says
a mouse CLICK claims primacy from a pad nobody has pressed
...and a real pad PRESS takes it straight back
stick drift interleaved with mouse movement does not flap primacy, or publish at all
MOUSE MOVEMENT is not an act either — a pad player brushing a mouse keeps the pad
TOUCH is a deliberate act too, on a hybrid the engine still calls a pad      <- L1
a device with NO pointer is a pad player whatever the player just did
an engine with no raw stream is taken at its word, and binds without a nil hole
...and `GetLastInputType` is never read, because this repository refused it
a pointer-primary desktop with no pad is exactly where it was
```

The last-but-one is INPUT-100/101 as an **executable pin**: the fake engine does not
offer `GetLastInputType` at all, so a module that reached for it would take the
pcall's failure path silently — the absence is an assertion, not an omission.

## M1 — the scrim mechanism, honestly

### (a) The published mechanism is FALSE, and here is what the numbers actually measure

The review is right: DIR5's own oracle resolves `plain` to
`BackgroundTransparency = 1` through `Button default`, so "its transparency is
whatever the class-default rule happens to leave" is true about OWNERSHIP and false
about the CONSEQUENCE — the number is 1, exactly the transparent-but-catching catcher
the code intended. **The class default was never the opaque source.**

**MEASURED LIVE** in the connected Studio (`Facet-Showcase.rbxl`, Edit datamodel),
building the adapter's own order — create root, `StyleLink`, parent, create node, tag
— against a sheet carrying Facet's own two rules, and reading back after N frames.
Full trail in `artifacts/expand-plate/catcher-paint-window.md`:

```
plain@0f styled=0.00 prop=0.00     scrim@0f  styled=0.00 prop=0.00
plain@1f styled=0.00 prop=0.00     scrim@1f  styled=0.00 prop=0.00
plain@2f styled=0.00 prop=0.00     scrim@3f  styled=0.45 prop=0.00
plain@3f styled=1.00 prop=0.00     scrim@10f styled=0.45 prop=0.00
plain@10f styled=1.00 prop=0.00
```

A sheet parented OUTSIDE the linked subtree settles identically, so sheet placement
is not a term. **Both of the director's numbers decompose:**

1. **`BackgroundTransparency = 0` (the property) is expected and PERMANENT.** In
   native mode the adapter writes that property on no node, ever — an explicit write
   would defeat every surface rule (spike m10) — so it reads the engine default for
   the life of every Facet node. My report treated it as corroborating. **It carries
   no information at all**, and that correction matters more than the rest: it was
   half of what made the false mechanism look measured.
2. **`GetStyled(...) = 0` is the styling-application window** — ~3 frames after an
   instance is created, and it reports the class default for `scrim` (0.45) exactly
   as much as for `plain` (1). A catcher root is created at the instant a surface
   opens, so a reading taken then is inside it.

So the director's measurement is **consistent with a correctly linked, correctly
ruled catcher**, which is what the review proved from the other side. The role change
did not remove a known cause; it replaced an unowned 1 with a theme-owned 0.45. That
is the right PRODUCT answer for a plate that covers content — and it is not a
mechanism, and the commit message should not have said it was.

**What is still open, and how to discriminate on report #4.** The window itself is a
real opaque flash of a full-viewport node and **no framework-side write can close
it**: the one property that would is the one native mode may not touch. Two live
candidates remain, each fenced — a root that never received a `StyleLink` (pinned
model-side by the root-link case), and the window (engine-side, unmeasurable
headlessly). **The discriminator is duration**: a reading 10+ frames after the plate
opened that still says 0 is the unlinked root; one taken immediately is the window.
Take both.

### (b) Every other `scrim = "none"` catcher, swept and dispositioned

The population is three, and it is the mechanism rather than the row:

| path | reached by | disposition |
|---|---|---|
| `mountScrim(owner, "none")` -> `plain` | an engaged-passive surface (`presenter.luau:2629` defaults every non-modal to `"none"`), `newMenu` (`menu.luau:636`), row-actions' floating menu (`row_actions.luau:2101`) | **stays `plain` — correct.** A menu at a button and an engaged HUD are tap swallowers, not backdrops; dimming there is a product regression |
| `mountPopupCatcher` -> `plain`, unconditionally | PopupButton's panel, an open row-actions tray | **stays `plain` — correct**, same reason |
| `mountScrim(owner, "scrim")` | a declared modal, and the region EXPAND plate since DIR5 | **dims — correct.** It covers content, and the dim is how a player is told the screen behind it is not live |

`plain` is the right DECLARATION for two of the three. What was NOT defended is the
number behind it, so that is what changed: the resolved-paint oracle now runs over
**every** catcher this presenter can mount, asserting **exactly 1** for the two
invisible paths (not "> 0" — a catcher resolving to 0.999 would be a near-opaque
full-screen fill that every "is it transparent" predicate here would call fine) and
the theme's own token for the dimming one, plus a live-driven case that mounts a
`newMenu`-shaped `scrim = "none"` modal and reads the number off the real node. If
`Button default` is ever renamed, reordered under a painting rule, or a state rule
starts carrying a fill, all three paths redden together instead of one shipping
opaque. The reasoning is recorded at the seam in `catchers.luau`, including why these
stay `plain` and the expand plate does not.

### (c) The mechanism story is corrected in place

`tests/popup_catcher_paint.spec.luau`'s section header now records the false answer,
why it was false, and what the numbers measure — kept rather than deleted, because a
mechanism contradicted by the instrument shipped to prove it is worth the space. The
`describe` is retitled ("every synthesized catcher resolves to a number somebody
chose"), since two of the three are deliberately class-default-owned.

**One correction I could not make**: `src/region_expand.luau`'s `anchoredOpts`
comment still carries the false mechanism (*"its transparency is whatever the CLASS
DEFAULT rule happens to leave"*). That file belongs to the plate-B round this turn.
**Owner action**: replace that paragraph with the artifact's finding, or delete the
mechanism claim and keep only the product argument (a plate that covers content dims;
the theme owns the number; ADR-0035 composes against it).

## The six LOWs

| | verdict | |
|---|---|---|
| **L1** `Touch` missing from the deliberate set | **FIXED** | it is a `DELIBERATE_CLASS` entry now, with a case ("TOUCH is a deliberate act too, on a hybrid the engine still calls a pad") that reddens when it is removed (MF4) |
| **L2** the report's RR-repo claim is wrong | **FIXED** | verified: `games/RascalRally/code` **is** the repository (`git log` shows `e6e1c56` carrying round 1's fence, and `4e271c3` after it). The round-1 statement was wrong and is corrected here rather than edited in place, so the mistake stays legible. Round 1's RR file was committed by the controller at `e6e1c56`; this round's RR file is committed below |
| **L3** no game-side evidence for item 5 | **FIXED** | three cases in RR's `facet_composition_collision_contract.spec.luau`, driving Facet's real `roblox_env` against a fake pad-desktop engine and asserting the predicate `FacetSponsor/init.luau:686` actually runs (`effectiveInput == "Gamepad"`, the gamepad-only seeded focus ring from the 2026-08-03 racer-sort ruling): a mouse player with idle pads does NOT get the ring; a real pad press still does (positive control); and the game reads that fact in exactly one place, enumerated from the source tree so a second consumer reddens the row. The review's line number (`:686`) is right and the report's `:672` was wrong |
| **L4** doc drift: the Close as "an icon chip" | **FIXED** | both sites now say "the corner disc" and point at the paragraph that describes it |
| **L5** the paint oracle is priority-blind and skips silently | **FIXED** | the cascade is `(priority, insertion)` — reading the field the engine reads costs one comparison and stops a future self-prioritising rule from making the oracle wrong quietly. `selectorMatches` returns a **channel** (`match` / `state` / `descendant` / `unknown`) and every channel is counted; the case asserts `unknown == 0` **and** that the two skipped families are non-empty, so the exemptions are about something. Plus a new case that makes the exemption's premise executable: no state rule in the built sheet carries a `BackgroundTransparency` at all |
| **L6** B-16's change column says "cover **over** the whole form" | **FIXED** in the row text below, together with the qualifier the review's H1 asks for ("under every form **within its own region**") |

## ADR-0040 row B-16 — CORRECTED text (supersedes the round-1 version)

| B-16 | `UI.Region{ expand }`'s synthesized affordance on a form that carries no control of its own | a **chevron** beside the form → a **cover UNDER the whole form** (`expandTarget.role`, a closed set of two again) | the affordance a collapsing region synthesizes changes SHAPE and TARGET on the commonest case: a passive compact form draws **no mark at all** and the whole of it becomes the tap/A target at the standard hit floor, where it used to draw a caret in a column the form's own measure reserved. Shipped geometry moves — the form gets the mark's column back (the HUD demo's clock zone 100 → 80 at 360x691), so a value that was being cut may now fit and a screen tuned against the reserved width re-lays out. Director ruling, DIR5 2026-08-21: *"the controls should just be tappable by default to open more without the arrow. we'll only need the arrow if the thing is already a control the user can tap."* The cover was retired by the 2026-08-21 device round for painting over the author's content; it returns declared `zIndex = -1`, so it and the hit expander banded below it paint **under every form within its own region** — the retirement note's own condition ("placing the affordance BELOW the form"), met without an extraction, because the solver's last-child lookup is a TREE fact and paint order is a different axis. **It is NOT under everything**: a cover's floor is the region's whole width, so where it overhangs a neighbouring region `hit_lift` lifts it ABOVE that neighbour to keep the band deliverable — measured 26% of each adjacent Button on the `ringScreen` fixture, and the open finding H1 in `task-dir5-review.md`. `UI.Foreign` and the lazy regions still force the chevron; `UI.Box{ active = true }` does not and is the review's M3. Rascal Rally declines the default on every multi-form region (`ResultsScreen.luau`'s `region()` helper) and is unaffected, pinned game-side | `tests/region_expand.spec.luau` EXPAND 5/7/15/17/18; `tests/hud_composition.spec.luau`; RR `tests/facet_composition_collision_contract.spec.luau` |

## Suite tails (content-pinned at the current HEADs)

| | baseline | after the fix round |
|---|---|---|
| Facet | **6949 passed, 0 failed** (`git archive HEAD`) | **6957 passed, 0 failed** (same archive + this round's six files) |
| Rascal Rally | **3461 passed, 0 failed** (RR `git archive HEAD` + Facet `git archive HEAD`) | **3464 passed, 0 failed** (same pair, this round's Facet files + RR spec file) |

An earlier pairing of RR's HEAD against a STALE Facet archive produced 3 reds in
`facet_theme_paint_contract.spec` — the consumer's own native-flip rider calling a
`native_style` function the older Facet did not have. Not a finding: a mis-pinned
pair, corrected by rebuilding both sides from their current HEADs, which is exactly
the failure mode content-pinning exists to make visible.

`stylua --check` clean. `check_input_authority` **clean** (after the allowlist entry
— it correctly failed first). `check_doc_style` PASS.

## Mutations (fix round; each applied to a private copy, run, reverted)

| # | mutation | red |
|---|---|---|
| MF1 | the deadzone removed — any stick change claims the pad | **1** (the flap case) |
| MF2 | mouse MOVEMENT counts as deliberate | **1** (the pad-player-brushing-a-mouse case) |
| MF3 | the whole correction removed | **6** |
| MF4 | `Touch` drops out of the deliberate set (L1 regressed) | **1** |
| MF5 | MF1 and MF2 together — the full noise pair | **2** |

MF1 is the red-first proof for M4 specifically: it is the shape of the code the
review objected to, and the case that reddens is the one that drives the director's
hardware.

## Concerns after the fix round

1. **The scrim's visual bug is still not proven fixed.** The mechanism is now
   honestly recorded and the settled paint is owned, but neither of those is a device
   pass. The discriminator for report #4 is written down (duration) and the artifact
   holds the numbers.
2. **The create-window flash is real and unclosable from here.** Every full-viewport
   catcher — `plain` and `scrim` alike — paints its class default for the frames
   before styling applies. If that turns out to be what the director saw, the fix
   belongs in the adapter's create path or in the presenter's mount ordering, not in
   a surface role, and it is a decision above my level.
3. **`roblox_env` now subscribes to the raw input stream.** It is allowlisted with
   the ledger's own reasoning and it routes no actions — but it is a second module in
   this repository doing device classification by hand, and the right end state is
   one classifier, shared with the consumer's, retired together by the same IAS
   event.
4. **H1, H2, M2 and M3 are not addressed here** by instruction. M3 in particular is a
   one-line population (`UI.Box{ active = true }` belongs in `UNSEEN_CONTENT`) whose
   file the plate-B round holds this turn.
