# DIR5 review — `27af00f` against `813f779`

**Verdict: CHANGES REQUESTED.** 2 HIGH, 4 MEDIUM, 6 LOW.

Every number below was measured in `git archive` exports under
`scratchpad/{at813,at27,m1,m2,m5,m6,m7,pair}`. The shared tree was not written to
except for this file.

---

## What reproduced exactly

| claim | measured | verdict |
|---|---|---|
| Facet 6905 → 6915, 0 failed | `at813` **6905 passed, 0 failed**; `at27` **6915 passed, 0 failed** | ✅ exact |
| RR 3460 → 3463 | pinned pair (Facet `27af00f` + RR `e6e1c56`) **3463 passed, 0 failed** | ✅ |
| M1 passive role forced to chevron → 6 red | **6 failed, 6909 passed** | ✅ |
| M2 cover's `zIndex = -1` dropped → 4 red | **4 failed, 6911 passed**, and the four are EXPAND 5/7/15 + the role case | ✅ |
| M5 sticky-Gamepad correction removed → 2 red | **2 failed, 6913 passed** — "pads connected + a mouse…" and "…the very first pad press hands it straight back" | ✅ |
| M6 reach epoch forgets the insets → 3 red | **3 failed, 6912 passed** | ✅ |
| M7 catcher back to `scrim = "none"` → 3 red | **3 failed, 6912 passed** — `popup_catcher_paint` "wears the scrim ROLE", `transient_over_live` "…and neither does a region's EXPAND plate", EXPAND 8 | ✅ red-first proof holds |
| RR fence's positive control is not vacuous | forcing `role = "chevron"` in the pinned pair reddens **exactly** "POSITIVE CONTROL: the game's Facet really does synthesize a cover for a passive ladder" (3462/1) | ✅ |
| B-16's "clock zone 100 → 80 at 360x691" | `at813` `/HudScreen/Hud/Clock` **100x30@129.67,0**; `at27` **80x30@139.67,0** | ✅ exact |
| `check_source_size`, `check_doc_style`, `check_library_purity` | PASS on `at27` | ✅ |
| `check_input_authority` | PASS in the real tree (the export fails only on the RR relative path — environment) | ✅ |
| no fixture is in the contested plate band | the HUD demo's five affordances, five viewports, zero off-screen panel/disc nodes | ✅ |

**The load-bearing claim of item 1 — "the solver's last-child lookup is a TREE
fact and paint order is a different axis" — is correct as stated.**
`layout/solver.luau:991` and `:2978` both find the affordance as
`kids[#kids].expandTarget ~= nil`, by identity, with no reference to `zIndex`;
`render/renderer.luau` `orderedChildren` sorts a copy by `(zIndex or 0, declaration
index)` and returns it only to the z walk; `syncZOrder` walks that order
depth-first and reserves `hostZ - 1` for the hit expander, so the whole affordance
lands below every form. `present/focus_map.luau` walks `node.children` in
declaration order at all thirteen sites, so the focus stop does not move either.
Nothing in `src/` outside the renderer consumes `zIndex` for ordering
(`themes/package.luau` and `tokens/styling.luau` use it for shadow child
instances, a different scope). That half of the reasoning is sound and the two
mutations that attack it bite.

---

## HIGH

### H1 — the cover's floor now takes a quarter of each neighbouring Button, and the new spec ratifies it

A chevron's 44px floor is a ~44px-wide column at the region's trailing edge. A
cover's is the region's **whole width**. In `region_expand.spec`'s own
`ringScreen` fixture at 390x150 (`probes/overhang.luau`):

```
                cover rect  0.0,46.0  390.0x20.0   z=11
                cover floor 0.0,34.0  390.0x44.0
  /S/C/Before/First   80.0x46.0 z=5   overlap 80.0x12.0 =  960 px2  (26% of the button)
  /S/C/After/Last     69.0x46.0 z=8   overlap 69.0x12.0 =  828 px2  (26% of the button)
```

The same probe at `813f779` measures **0 px² on both** (the chevron's floor sat at
x 358..402; the neighbours are 80 and 69 wide from x=0).

`hit_lift` then does what it is designed to do: it lifts the Clock branch past both
neighbours so the band is deliverable — the framework's transparent expander at
z 10 outranks `First` (z 5) and `Last` (z 8). So a press in the bottom 12px of
`First`, or the top 12px of `Last` — **the full width of each, a quarter of each
button's area** — opens the Clock's expand plate instead of pressing the button
the player aimed at. That is the one-gesture-two-meanings collision R18 exists to
prevent, arriving across a region boundary instead of inside one.

Two things make this worse than a design trade:

* **EXPAND 15 asserts the lift as the desired outcome** (`expect(… and the
  overhang lift delivered it: {not below})` plus `overhangs >= 1`), so the case
  is now green *because* the theft happens. Nothing in the suite can redden on it.
* **B-16's change column says the cover "and the hit expander banded below it
  paint UNDER every form", unqualified.** The diff does not support that: the
  spec in the same commit proves the expander paints *above* author Buttons in
  neighbouring regions. The row needs the qualifier "within its own region".

The report's Concern 4 records "measured 12px" and "worth a director look". 12px
is the vertical depth; the stolen rect is the neighbour's full width, on **both**
sides, and it is present in the fixture the round shipped.

### H2 — the hugging plate hangs off the screen, and takes the framework's own Close with it

`probes/plate_band.luau` / `probes/plate_detail.luau`, one region, three text rows,
viewport 390x40, sweeping form 1's natural width:

```
 len  sheet  plate.w  plate.max  panelW  panelX   at 27af00f
  30  false   298.0    358.0      358.0    8.0    right=366  on-screen
  33  false   328.0    358.0      388.0    8.0    right=396  6px OFF
  40  false   358.0    358.0      390.0    8.0    right=398  8px OFF
```

At `813f779` every one of those rows is `panelW = plate.w`, right edge ≤ 366, and
**nothing leaves the viewport**. The node detail at len=40:

```
  .../Surface                  8.0..398.0   (viewport is 0..390)
  .../ExpandPanel              8.0..398.0
  .../ExpandPanel/ExpandClose 362.0..398.0   8 of 36px off-screen
  .../ExpandPlate/Full        16.0..346.0    content is fine
```

and with `safeInsets = {left = 20, right = 20}`:

```
  .../ExpandPanel             20.0..410.0    20px past the viewport
  .../ExpandPanel/ExpandClose 374.0..410.0   20 of 36px outside the viewport,
                                             36 of 36px outside the safe area
```

This is a regression the commit introduces, and it **refutes item 4's structural
argument directly**. The report and the blueprint comment argue that the straddle
is a margin "which is what keeps the disc inside the PANEL's box — and the
anchored placement's safe-area clamp knows only the surface's box, so … clamping
the panel clamps the disc." The panel's box does contain the disc; the clamp
cannot shrink a panel that is already wider than the space, so it pins the left
edge and lets the right run off. Containment buys the disc nothing once the panel
exceeds the clamp's box, which is exactly the band the fix created.

The band is entered whenever form 1's natural width exceeds
`plate.max - chrome` (chrome = `space.s` + `controlSizes.compact.height` +
`space.m` ≈ 60px; 298 of a 358 cap at 390px) — the top ~17% of the plate range,
and *every* wider case, because a wrapping form never trips the `sheet` fallback
(`sheet = natural > maxW`, and `measure` returns the wrapped width ≤ maxW).

The report's CONTESTED note calls the residual "the panel now exceeds the **gutter
allowance**". Measured, it exceeds the **screen**, and the thing hanging off it is
the plate's only pointer/keyboard exit. That description needs correcting whether
or not the solver field lands.

---

## MEDIUM

### M1 — item 2's mechanism is contradicted by the oracle shipped to prove it

The new spec's own first case asserts, and I reproduced independently
(`probes/probe_sheet.luau`):

```
  classifyTags{class=Button, surface="plain"}  ->  (no tags at all)
  the only matching rule                        ->  TextButton "Button default"
  BackgroundTransparency                        ->  1        (FULLY TRANSPARENT)
```

The bespoke path is the same answer written explicitly
(`screen_paint.luau:702`, `instance.BackgroundTransparency = 1`), and no rule in
the built sheet with a `:` state selector carries `BackgroundTransparency` at all
(79 rules, checked). So "its transparency is whatever the class-default rule
happens to leave — a number the plate neither states nor owns" is true about
ownership and **false about the consequence**: the number is 1, which is exactly
the transparent-but-catching catcher the code intended.

That leaves the director's live `GetStyled("BackgroundTransparency") = 0`
unexplained by the mechanism the commit message headlines ("THE OPAQUE POPUP,
REPORTED THREE TIMES, HAS ITS MECHANISM"). Two consequences:

* The role change works by **painting an owned 0.45 over whatever was there**, not
  by removing a known cause. The controller's live 0.45 confirms a sheet rule
  reaches that node *now* — which, if the sheet reached it before, would have made
  it 1. Something else was in play and is still in play.
* **Every other `scrim = "none"` catcher was deliberately left alone**: the Menu
  (report: "The Menu keeps `none`"), engaged-passive surfaces
  (`presenter.luau:2629` defaults non-modals to `"none"`), and the popup catcher,
  which `catchers.luau:358` mounts `plain` **unconditionally**. If the stated
  mechanism were the cause, all of those are still opaque full-screen fills.

Concern 2 hedges honestly ("the engine half is unverified by me", and names the
root-link fence as where to look next). The finding is that the report and the
commit message present the mechanism as *found* while the evidence in the same
commit says the suppressed surface resolves transparent. The fourth report is not
foreclosed.

### M2 — the restored cover has no device evidence, and it is the feature a device round killed

`blueprint.luau` keeps the retirement note verbatim: *"'it is transparent, so it is
harmless' is a claim about the ENGINE that no headless check in this repository
makes."* The new proof — EXPAND 15's z sweep — is the z the **adapter was told**,
i.e. a model fact of exactly the kind that was green while three pills rendered
empty. The gesture-still-arrives argument rests on Roblox routing input to the
topmost *interactive* object and on nothing in a passive form being `Active`; both
are engine behaviours the suite cannot execute. Item 2 got a live confirmation;
item 1 — the higher-risk half, on the same fixture, at the same viewport — did
not, and the report books no device pass for it.

### M3 — `formCarriesMeaning` does not see `active = true`, and that is a sinking node

`UI.Box{ active = true }` is public (`blueprint_schema.luau:948`, on `Box` at
`:1825`) and documented as *"engine `Active` flag — an input-sinking panel (modal
backdrops)"*; the adapter writes `instance.Active = value == true`
(`screen_target.luau:3592`). `Box` is in the passive class set, so a reduced form
containing one is classified passive, gets a cover **underneath**, and the Active
Frame above sinks the press — the cover is unreachable over that rect. This is the
identical failure mode the wave's own review found for `UI.Foreign` (MEDIUM-2) and
closed by adding it to `UNSEEN_CONTENT`; the framework's own explicit
"input-sinking panel" prop is the remaining hole. Narrow population, exact same
mechanism.

### M4 — item 5 trades a sticky wrong answer for a flapping one, on a function this repo already rejected

`tools/check_input_authority.py` (INPUT-100/101) records, as a shipped ledger
entry, that RR's `InputIdentity.luau` refuses `GetLastInputType()` because
*"deadzone drift flaps it several times a second"* and instead requires a
deliberate act past a 0.25 deadzone. DIR5 puts `GetLastInputType()` under
`interactionClasses.primary` framework-wide with **no deadzone and no hysteresis**.

On the exact hardware the director reported (mouse in hand, three pads connected,
one drifting), `LastInputTypeChanged` now alternates families, `familyChanged` is
true on every alternation, and `pushInput()` republishes `preferredInput` between
`"Gamepad"` and `"KeyboardAndMouse"` — moving `interactionClasses.primary`,
`effectiveInput`, `scrollIndicatorPolicy`, density and every pad affordance with
it. The engine's stickiness is the property that suppressed this; removing it
without adding any of its own is what makes the flap possible. The five new specs
cover one flip in each direction and no alternation.

The `MouseEnabled` guard is a real mitigation and keeps the handheld case (the one
INPUT-100 is about) entirely out. The residual is the desktop-with-a-pad case,
which is the case the change was made for.

---

## LOW

* **L1 — `Touch` is not in `POINTER_LAST_INPUT`.** The comment says the correction
  fires "while the last input actually seen is a POINTER or KEYBOARD one"; the
  table holds only the five mouse names and `Keyboard`. On a mouse-capable hybrid
  whose player is using the touchscreen, a sticky Gamepad preference still stands.
  No case covers it.
* **L2 — the report's RR-repo statement is wrong.** "Rascal Rally has **no git
  repository** (`games/RascalRally/.git` does not exist), so its one changed file
  … is left in the working tree." `games/RascalRally/code` **is** the repository
  and the file is committed at `e6e1c56` (whose own message records that the
  round "resolved the game repo's root wrong"). The report was not updated.
* **L3 — no game-side evidence for item 5.** RR reads `effectiveInput` at exactly
  one behavioural branch (`code/src/client/FacetSponsor/init.luau:686` — gamepad-
  only seeded focus on table engage; the report cites `:672`), and item 5 changes
  that branch's answer on a mouse-plus-idle-pad desktop. Item 1 got a fence with a
  positive control; item 5 got nothing. The root constitution asks for the
  compatibility evidence even when no production edit is warranted.
* **L4 — doc drift inside the same commit.** `docs/guide/01-concepts.md:439` and
  `docs/reference/api.md:913` still describe the Close as "an icon chip" while
  both files were rewritten elsewhere in the same diff to "a circular icon button
  on the plate's top-right corner".
* **L5 — the paint oracle is silently priority-blind.** `resolvedCatcherPaint`
  resolves the cascade by insertion order only, and `selectorMatches` drops every
  selector containing `:` **without** routing it to the `unknown` channel (only
  unrecognised shapes go there). It is correct today — `sheet_model` derives
  `rule.priority = #rules * 10` from the index, and no state rule carries
  `BackgroundTransparency` (both verified) — but a rule that ever declares its own
  priority, or a state rule that ever paints a fill, makes the oracle wrong
  quietly, on the one instrument three reports were waiting for.
* **L6 — B-16's change column reads "→ a **cover over the whole form**"** while the
  entire point of the round is that it is *under* it. The row's body corrects it
  two sentences later; the change column is the half a consumer skims.

---

## Not findings — checked and clear

* **Focus order, activation verbs, dismissal routes** are untouched by `zIndex`:
  `focus_map` never reads it, and EXPAND 10/12 run against the cover unchanged.
* **The empty `Zone` Box paints nothing** in either mode: no tags → `Frame
  default` `BackgroundTransparency = 1` natively, and `screen_target.luau:1236`
  writes 1 in bespoke. It is not a second empty-pill risk.
* **The close disc's label is not drawn**: `applyProp`'s icon branch routes it
  through `renderer.drawnButtonText`, so the ASCII glyph shows and `"Close"` stays
  semantics — consistent with the cover's "a Button with no children draws its own
  label" justification for the `Zone` box.
* **`capabilities.gamepad` really is untouched** by item 5; the spec asserts it and
  the diff moves only `preferredInput`.
* **`hit_lift` cannot lift the cover above its own forms**: `refresh` requires
  `not overlaps(hostRect, targetRect)` and a cover's rect contains every form.
* **No fixture is in H2's band today** — the HUD demo's five affordances at five
  viewports produce no off-screen panel or disc node. The report's claim holds.
* **`ten_foot_metrics.spec.luau` carries exactly one hunk** in the commit
  (`2 +-`), as claimed; the concurrent round's seven are not in it.
* **`Facet_PaintProbe` is the hud fixture's own surface** (`hud.luau:2285`,
  `tests/hud_paint_probe.spec.luau`), not a leak. The report's line numbers are
  pre-diff but the conclusion is right.
