# ADR-0040 — Breaking changes may ride an unreleased version, if the record and the instrument both exist

**Date:** 2026-08-21
**Status:** Accepted
**Number:** 0040. 0039 is the ten-foot metric ladder; 0031 is a burned number
([ADR-0032](ADR-0032-nested-instance-tree.md) records why).
**Companions:** [ADR-0011](ADR-0011-semver-and-deprecation.md) (the versioning and
deprecation policy this qualifies), `docs/reference/constitution.md` §14 (which
declares ADR-0011 binding and now carries this ruling's clause),
`tests/api_surface.spec.luau` + `tests/lib/public_shape.luau` (the instrument),
`artifacts/release-candidate-review/adapt-audit/fixes.md` (where most of the
measurements below already live).
**Ruling:** controller ruling **R15**, 2026-08-21, from wave LAYOUT-FIX's fresh-context
review. Director veto open — see "Carried to the director".

## Context — a gate that was green over a hole

Wave LAYOUT-FIX made `UI.AdaptiveStack.axis` **required** and changed `UI.Grid`'s
undeclared **lane default** from one lane to the intrinsic measure. Both are
director-ordered fixes to critical paradigm findings, both shipped with red-first
specs and a green suite, and both turn code that worked at `0.10.0` into code that
does not work at `0.10.0` — a construction error in the first case, a silent
re-layout in the second.

**Nothing in the repository could see it, and that is the finding.** Three separate
mechanisms each had a reason not to fire:

* `blueprint_schema.deprecations()` emits a ledger row only for a prop carrying an
  explicit `deprecated` field. Making a prop **required** generates nothing at all.
* `tests/api_surface.spec.luau` enforced the ledger's *schema* and that ADR-0011
  names the current `VERSION` — which it still did, because nothing bumped.
* `VERSION` has been frozen at `0.10.0` for seventy commits across the whole
  release-candidate campaign, so "not bumping" reads as campaign practice rather
  than as an omission.

So the question is not "was this wave careless". It is: **what is the honest policy
for a pre-release library whose whole campaign is behaviour change, and what
instrument makes the answer checkable?**

## Decision

### 1. A breaking change may ride an unreleased version, with a record

ADR-0011's deprecation window — "a deprecated surface keeps working for at least one
MINOR after `since`" — is a promise to **published** consumers. `0.10.0` has not been
published: it is the version the release-candidate campaign is *building*, and every
consumer of it is inside this repository or is Rascal Rally, which moves in the same
task by the root constitution's own rule.

Therefore: **while a version is unreleased, a breaking change may land in it
directly, provided it is recorded here.** After the first publish of a version, the
full ADR-0011 window applies with no exception.

**A compatibility shim is explicitly NOT the answer for the two changes above**, and
the reason is not convenience. Both fixes exist *because* a silent default was the
defect: `AdaptiveStack` defaulting to `"y"` is a class named for adapting that could
be built unable to adapt, and `UI.Grid` defaulting to one lane is a card container
that ignored the box it was given. A shim that kept the old behaviour behind a flag
would re-ship the exact silence the refuse-don't-guess idiom was adopted to end, and
would have to be removed by the same argument that removed it. The record is the
obligation; the shim would be a second defect.

### 2. The record: what is breaking in the unreleased `0.10.0`

**Method, stated so the next reader knows what this is and is not.** This table was
built by reading the campaign's own artifacts (`fixes.md` and its three addenda, the
two paradigm matrices, ADR-0036/0037/0039) against the seventy commits between the
`0.10.0` bump (`8691380`) and this one, and by re-reading the diffs of the rows
marked *measured here*. **It is not a proof of completeness** — a behaviour change
with no artifact and an unremarkable commit subject would not appear. Decision 3 is
what makes the *next* one impossible to miss, and it is the half of this ADR that
does not depend on my reading.

| # | surface | what changed | why it is breaking | recorded |
|---|---|---|---|---|
| B-1 | `UI.AdaptiveStack.axis` | optional (default `"y"`) → **required** | a bare `UI.AdaptiveStack{…}` was a permanent VStack and now raises at construction | measured here; `tests/layout_defaults.spec.luau` |
| B-2 | `UI.Grid` with neither `columns` nor `minColumnWidth` | 1 lane at every width → `minColumnWidth = "intrinsic"` | a bare grid silently re-lays out — the same six cards go from one column to 2/4/6/9/5/7 across the audit's combos | measured here; `tests/layout_defaults.spec.luau` |
| B-3 | `newPicker`, `newMenu`, `newPopupButton`, `newTabView`, `newTextInput`, `newVirtualList` (`itemExtent = "cards"`) | each **refuses to construct** when no environment can be found | previously each silently substituted the large-screen / near-distance / no-cutout answer. Six controls, one line each: the refusal replaced *wrong* behaviour, not working behaviour, and the audit counted the consequence (0 of 17 shipped `Picker` sites reached the adaptive default). Rascal Rally, the only external consumer, migrated in the same wave | `44a495f`, `f3d2fe8`; `tests/adaptive_defaults.spec.luau`, whose refusal guard derives the set from the SOURCE rather than a hand-written list |
| B-4 | `adaptive.navPlacement` on a tablet | `bottomBar` → `topBar` | a documented policy answers differently for a real device class; six shipped assertions were re-pinned because they asserted the defect | `fixes.md` §2, with the full re-pin trail |
| B-5 | `adaptive.columnsFor` at ten-foot | uncapped → capped against `BREAKPOINTS.wide` | a television gets FEWER columns than a desktop where it used to get more | `fixes.md` Family B / ADAPT-23 |
| B-6 | unauthored text on a `Large` display | authored size only → the whole type ladder scales 1.5x | every screen written the natural way is 1.5x on a television | ADAPT-7 in `fixes.md`; [ADR-0039](ADR-0039-ten-foot-metric-ladder.md) |
| B-7 | every theme metric on a `Large` display | unscaled → scaled by the type floor's own factor | control heights, spacing, icon sizes and the 44px hit floor all move on a television | [ADR-0039](ADR-0039-ten-foot-metric-ladder.md) |
| B-8 | `UI.Composition`'s content lane at ten-foot | uncapped share → capped at `adaptive.LANE_MEASURE x metricScale` (900) | a shipped composition re-measures on a television; Rascal Rally's results lane moves 992 → 900 there and nowhere else | controller ruling R14; `fixes.md` §7 |
| B-9 | `newTable` narrower than its columns | clipped → **collapses** a column by priority and discloses it | shipped tables re-lay out at compact; a `fill` column's `minWidth` is now honoured (a playlist went 30px → 66px) | `fixes.md` wave TABLE addendum (J-1, J-2, J-3) |
| B-10 | `newTable` selection and edit-mode keys | arrow replaces; no modifier semantics | Ctrl/Cmd moves without selecting, Shift extends, and on a table with no `onPrimaryAction` a device Activate toggles | `fixes.md` wave TABLE addendum (L-6, L-7) |
| B-11 | a horizontal `UI.ScrollView`'s focus ring | vertical run → **horizontal** run | Left/Right now step the rail and Up/Down leave it; the opposite of what shipped | ADAPT-24 in `fixes.md` |
| B-12 | `newTabView` / `newPicker` band placement | corner-parked → centred in the band | shipped geometry moves on three placements | ADAPT-4 in `fixes.md` |
| B-13 | the library's own name and call shapes | `LuauUI` → `Facet`; `Facet.newTable(Facet, core, spec)` → `Facet.Controls.Table(core, spec)` | every consumer require path and nineteen call shapes | [ADR-0036](ADR-0036-facet-rename.md), [ADR-0037](ADR-0037-public-call-shapes.md) — recorded, and the builders still work |
| B-14 | `showcase_chrome.TOGGLE_GAMEPAD` (the gallery example, not the library) | `"ButtonY"` → **removed** | the showcase chrome bound the pad toggle to `ButtonY`, which is `newMenu`'s own gamepad trigger (`menu.luau` `TRIGGER_KEYS.gamepad`, a sinking context at priority 1200) — measured with the shipped `menu` demo mounted, one press opened both. Controller ruling **R20** (2026-08-21) gives `ButtonY` back to the menu verb; the pad reaches the chrome through `SECTION_GAMEPAD` (the two shoulders, R19), and the constant is deleted rather than left naming a binding that no longer exists. An example's export rather than a `src/` surface, recorded here because a consumer copying the showcase's key map is exactly who this ledger is for | `tests/gallery_chrome.spec.luau` case (16), which drives `menu.luau`'s OWN binding rather than asserting an absence |
| B-15 | `native_style.DEFAULT_ENABLED` — the library's DEFAULT paint path | opt-in (`false`) → **default-on** (`true`): a `screen_target.new({})` carrying no `nativeStyle` opt now paints through a Roblox `StyleSheet` | every screen target that never named a paint path changes PAINTER. Sheet rules and the phantom `::UICorner` / `::UIStroke` modifiers replace the adapter's per-property explicit writes, so no `UICorner`/`UIStroke` instance exists under a Facet root any more and a consumer reading those instances back finds nothing; the Style Editor becomes the paint authority for anyone who opens the place. NSS-A10 measured the two paths byte-equal on every mapped property, so the pixels are the same and the MECHANISM is what moved — which is exactly the kind of change a consumer's own code touches and a screenshot does not. The escape hatch is unchanged and still wins over everything: an explicit `nativeStyle = false` (and the gallery's `Facet_ForceStyleFallback`) keeps the explicit-write path, which stays a first-class tested path rather than a corpse. Rascal Rally — the only external consumer — passes NO opt at its four adapter sites, so it moves with the default in the same task, per the root constitution | game director's ruling, 2026-08-21; `tests/native_style_default.spec.luau` (the default, the escape hatch, the seam and this row); RR `tests/facet_theme_paint_contract.spec.luau`; `artifacts/native-stylesheets/promotion-readiness.json` |
| B-16 | `UI.Region{ expand }`'s synthesized affordance on a form that carries no control of its own | a **chevron** beside the form → a **cover** over the whole form (`expandTarget.role`, a closed set of two again) | the affordance a collapsing region synthesizes changes SHAPE and TARGET on the commonest case: a passive compact form draws **no mark at all** and the whole of it becomes the tap/A target at the standard hit floor, where it used to draw a caret in a column the form's own measure reserved. Shipped geometry moves — the form gets the mark's column back (the HUD demo's clock zone 100 → 80 at 360x691), so a value that was being cut may now fit and a screen tuned against the reserved width re-lays out. Director ruling, DIR5 2026-08-21: *"the controls should just be tappable by default to open more without the arrow. we'll only need the arrow if the thing is already a control the user can tap."* The cover was retired by the 2026-08-21 device round for painting over the author's content; it returns declared `zIndex = -1`, so it and the hit expander banded below it paint UNDER every form WITHIN ITS OWN REGION (review correction 2026-08-21: the floor initially reached past the region into sibling buttons — clamped by the follow-up round) — the retirement note's own condition ("placing the affordance BELOW the form"), met without an extraction, because the solver's last-child lookup is a TREE fact and paint order is a different axis. `UI.Foreign` and the lazy regions still force the chevron. Rascal Rally declines the default on every multi-form region (`ResultsScreen.luau`'s `region()` helper) and is unaffected, pinned game-side | `tests/region_expand.spec.luau` EXPAND 5/7/15/17/18; `tests/hud_composition.spec.luau` (the demo carries both roles); RR `tests/facet_composition_collision_contract.spec.luau` (the opt-out fence + a positive control) |
| B-17 | **The paint family scales at ten-foot, derived from `metricScale`** | Director, 2026-08-21, on the live console A/B (`captures/tv_corners_zoom_compare.png`): corner radii AND hairline strokes scale with the metric ladder at the ten-foot class, and stay DERIVED from `metricScale` so a future scale tweak moves them in lockstep. This supersedes **R13 in its result** and preserves its doctrine — *a metric may only scale where the framework owns the paint* — by doing the sheet-GENERATION work R13's own pointer named: `snapshot.paintForDisplay` is one derivation, and both authorities spend it (`sheet_model.build`/`buildPackage` bake the literal into the phantom `::UICorner`/`::UIStroke` rules; `screen_target` derives `ctx.style`; `client.host` carries the environment's `displaySize` to the target; `theme_controller` builds a package's sheet, its `styleFor` and its live-edit repaint at the same class). A radius rounds to a WHOLE pixel (a `UDim` Offset is an integer; a pixel package's grid wins where it has one), a stroke keeps its fraction (`Thickness` is a float): 12→18, 8→12, 1→1.5 at 1.5. The capsule sentinel scales (999→1499) and paints identically under `UICorner`'s clamp for every box up to 1998 px on its shorter side. A package's `metrics.tenFoot` may name a paint path and wins on both sides — closing a live gap where such a declaration moved the measure and not the paint. Near density is byte-identical: same table, same sheet stamp, same 99-token dump, and the eight built theme artifacts are unchanged (they carry Luau source, and every sheet is generated in the consuming client at that client's own distance). Guard: `tests/ten_foot_metrics.spec.luau` (11 new rows, 9 mutations). Consumer: Rascal Rally `4e271c312` — `FacetSponsor` builds its own target and now forwards the class, or the console HUD would have measured at three metres and painted at arm's length. |
| B-18 | `UI.Region{ expand }`'s plate/sheet SELECTION, and `plate.max` on the composition resolution | measured against the gutter allowance → measured against the allowance **minus the plate's own chrome**; `plate.max` changes meaning from "the cap the form was measured against" to "the widest the plate BOX may be declared" (at 390: 358 → 342) | a form whose natural width lands in the last `inset + straddle` px of the allowance now falls back to the **full-width sheet** instead of mounting an anchored panel. The panel it used to mount was **wider than the allowance it had just been chosen against** — reproduced headlessly at 390: a 320px form gave `plate.max=358, sheet=false, panel=380`, i.e. 22px past a 358 allowance, and near the top of the band wider than the viewport. This is the residue DIR5 fixed the inner half of and CONTESTED the rest of by name (`solver.luau` ~1113, beside `expandGutter`); it is closed with ONE declaration rather than one number — `layout/expand_plate.luau` owns the insets and the straddle, `blueprint` BUILDS the plate from them, the solver RESOLVES them onto the resolve context, `composition` SPENDS them on the cap. Two numbers rather than one because they sit on opposite sides of the declared box (padding inside, straddle outside): a single combined figure mis-sizes whichever of hug/fill it was not derived for. **Zero shipped screens move today** — no fixture is in the band, the Facet verdict set gains only the new cases and Rascal Rally is identical — which is exactly why it needs a register entry rather than a fixture: the next reader tuning a form against the allowance has no other way to learn the band exists | `tests/region_expand.spec.luau` EXPAND 19 (the band case and the in-allowance control), EXPAND 18 (`plate.rect.w == row.plate.max`, relational so both numbers move together); `docs/reference/api.md` §Region plate; three mutations bite (the cap stops reserving the padding, the cap stops reserving the straddle, the plate stops spending the declaration) |
| B-19 | the hit expander a `role = "cover"` affordance receives ([ADR-0041](ADR-0041-hit-floor-bound.md)) | unconditional 44px inflation of the solved rect → **grows one side at a time and each side stops at the first rect outside it that can sink a press**; boxed in on every side = retracted, the affordance reached through the region's own box | a cover IS its region's whole box, so the old floor left the region across its full width — measured at 390x150 as 960 px² of one neighbouring Button and 828 of another (26% of each) delivered to the plate instead of the button the player aimed at (DIR5 review H1; plate-B corrected the mechanism and could not fix it from an unlocked file). R18 as ruled bounds it: exempt over passive content, banned over interactive — an ordinary sub-floor control keeps its WHOLE F1 floor, including the part that leaves its parent. **R23 (2026-08-21) bounds it further: only rects the AUTHOR declared stop a floor** — a framework affordance may not take the accessibility floor off another one, which is the line `hit_lift`'s doctrine already draws on expander-vs-expander. Blast radius measured at MATRIX scale (`overflow_sweep`: viewport x package x preference x strip), not on one fixture: of 381 swept route boxes **38 end below the effective floor and every one is cut by an author node, 0 by a framework route**, smallest route 35px, 31 covers retracted. Counting framework routes as blockers read 43 / 20 / 25px / 32 — the 25px route one pixel above the dead-end bar. Outside that population nothing moves: the 800-tree differential oracle over every other walk's output is byte-identical, and at 359x718 with the default package the HUD demo's three stepped-down covers keep 44px | `tests/hit_floor_region_clamp.spec.luau` (14 cases, 8 mutations); `tests/overflow_sweep.spec.luau` "R23: no route falls below the touch floor except where an AUTHOR node is in the way" (381 routes, 4 mutations); `tests/region_expand.spec.luau` EXPAND 15; owner `src/render/commit_walks.luau` (`growWithin` + `hitRects`) |

**B-13 is the shape the rest should have had**: two ADRs, a ledger entry, and the old
builders kept working. B-1 through B-12 are the ones that had a *measurement* and no
*record*, which is what this document supplies.

### 3. The instrument: the two shape changes a ledger cannot see

`tests/lib/public_shape.luau` extracts the two facts, and
`tests/api_surface.spec.luau` pins them:

* **the REQUIRED set** — every `Class.prop` carrying `required = true`, by name;
* **every DOCUMENTED DEFAULT**, by extracted value — shared box/container props once,
  per-class props by `Class.prop`.

A prop flipping to required, or a documented default changing value, now moves a pin
and reddens the suite with a message naming the surface and pointing here. A change
that *is* intended is landed by updating the pin **and** adding a row to Decision 2 in
the same commit — and a third case asserts that every surface named in this ADR's
breaking table is really in the pinned sets, so the record and the schema cannot
drift apart in either direction.

The extraction has one owner for the usual reason: a pin produced by a different
parser than the live read is a claim about a parser that no longer exists.

### 4. Constitution §14 gains the pre-release clause

Stated there in one sentence so the rule is where the rules are, pointing here for
the reasoning and the table.

## Consequences

* **The two changes are on the record**, with their measurements, and a consumer
  reading `DEPRECATIONS` alone would still miss them — which is why §14 now names
  this document beside the ledger.
* **The blindness is closed for the future, not just apologised for.** The pins are
  the deliverable; the table is the backlog they were built to prevent.
* **The pins will collide with other waves, deliberately.** A wave that changes a
  documented default now has to say so in the same commit. That is the friction the
  policy is made of, and the pin is deliberately narrow — an extracted *value*, not
  the doc string — so rewording a doc without changing its default moves nothing.
* **The sweep in Decision 2 is a reading, not a proof.** It is signed as such.

## Carried to the director

1. **Does seventy commits of accumulated public behaviour change still belong inside
   `0.10.0`?** This ADR rules that it *may*, because nothing has been published. It
   does not rule that it *should*. A `0.11.0` bump with this table as its changelog
   is the alternative, and it is a release decision rather than an implementer's.
2. **The publish boundary is the only thing that makes this policy safe**, so it needs
   to be a real event with a name. After it, ADR-0011's window applies unqualified.

**Answered by the director, 2026-08-21:** question 1 — the release stays `0.10.0`
(there are zero outside users, so a bump would signal nothing to no one). Question
2 — the publish boundary is Step 14's publish event, the director's own manual
click; ADR-0011's window applies unqualified from that moment.
