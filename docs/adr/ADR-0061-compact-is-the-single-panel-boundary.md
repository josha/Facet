# ADR-0061 — Compact is the single-panel boundary for `newMenu`, not touch

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0061 (0058-0060 are taken by the concurrent INPUT/THEME/POP lanes).
A behavioral/geometry-shape fix to `newMenu`'s automatic presentation
resolution — no public prop became required and no documented prop DEFAULT
changed VALUE, so Decision 3's shape instrument (`tests/lib/public_shape.luau`
+ `tests/api_surface.spec.luau`) has nothing to record, exactly as
[ADR-0056](ADR-0056-lane-give-way-both-ends.md) (B-31) and
[ADR-0059](ADR-0059-themed-chrome-is-a-layout-fact.md) (B-32) record for their
own geometry repairs. It DOES change what a real, previously-reachable
environment class (a compact width with a pointer-primary interaction class)
resolves to for every automatic `newMenu`, which earns it
**[ADR-0040](ADR-0040-unreleased-breaking-changes.md) row B-33** on the B-4
precedent ("a documented policy answers differently for a real device class").
**Companions:** `docs/plans/navigation-and-menus-brief.md` §2 D2 (the
construct this changes), [ADR-0058](ADR-0058-physical-size-aware-ten-foot.md)
(the sibling fix this round's own shape mirrors — a signal conflated with a
question it does not answer, corrected without inventing a breakpoint).
**Home:** `src/controls/menu.luau` (`presentationMemo`, `ops.back`).
**Unchanged, on purpose:** `src/controls/menu_recipe.luau`
(`resolvePresentation`, `touchPrimary`) — still the exact function `popup_button`
and `picker` also call; this ADR does not touch their behavior (see "What this
round does NOT change").
**Guards:** `tests/menu.spec.luau` § "item 14 — COMPACT forces the
single-panel idiom, not touch" (10 cases); `tests/menu_scenario.spec.luau` §
"both idioms, from one control, on one machine" (three cases re-pinned off
`PHONE`, one case added at `PHONE` proving the new rule); RR
`games/RascalRally/code/tests/facet_menu_contract.spec.luau` (migrated).

## Context

Director's goal-prompt item 14, verbatim: "Design change: menus/five-triggers
'panel' on mobile — sub-menus (e.g. Layering) open a second panel; should be
ONE panel with a back button on mobile, expand on medium/large
(`shouldHaveSinglePanel.png`)."

`shouldHaveSinglePanel.png` is the "Menus and their five triggers" showcase
(`examples/gallery/scenarios/menu.luau`) on a phone: the root menu (Accessory
Adjustment / Layering ▸ / Skin Color / Report Avatar / Reset Avatar) and the
"Layering" submenu (Clothing Layering / Makeup Layering ▸) are BOTH visible,
overlapping each other and the page beneath them.

### `newMenu` already had the single-panel idiom — the branch condition was wrong

`src/controls/menu.luau` already implements exactly the shape the director is
asking for, and has since the D2 mission that shipped it: under a `sheet`
presentation, entering a submenu REPLACES the one surface's contents and
grows a `Back` row, rather than floating a second panel over the first
(`presentLevel`/`rebuild`; `tests/menu.spec.luau` § "touch does not nest").
The question is not "does the single-panel idiom exist" — it does — but
"which environments resolve to it."

`menu_recipe.resolvePresentation(optionCount, sizeClass, touchLive)`
(unchanged by this round):

```lua
function menu_recipe.resolvePresentation(optionCount, sizeClass, touchLive)
	if touchLive == true then
		return "sheet"
	end
	if sizeClass == "compact" and optionCount > 6 then
		return "sheet"
	end
	if optionCount <= 3 and sizeClass ~= "compact" then
		return "inline"
	end
	return "menu"
end
```

The PRIMARY gate is `touchLive` — "is touch the live interaction class" — and
`sizeClass == "compact"` only matters as a secondary rule, gated on an item
count over six. The showcase's own five-item root list never crosses that
count, so at a compact width with a pointer-primary interaction class (no
`touch = true` signal at all) this resolves `"menu"` — the floating,
per-level idiom — and that is `shouldHaveSinglePanel.png`: a submenu opened
as its own anchored panel beside a parent panel neither of which has room on
a phone-width screen.

**This is not a synthetic case.** `touchLive` answers "is touch primary right
now", a question a compact-width surface can genuinely answer "no" to: a
phone with a Bluetooth mouse attached, or — the load-bearing example, because
it is how this defect was actually captured — **Roblox Studio's own compact
device preset, which has no way to inject a `touch` capability signal at
all** and therefore reports `interactionClasses.primary = "pointer"`
unconditionally regardless of the simulated screen size
(`src/env/environment.luau`'s `derived.interactionClasses`: `primary =
"pointer"` is the literal starting default before `preferredInput` is
considered). `games/RascalRally/code`'s own consumer contract test
(`tests/facet_menu_contract.spec.luau`) was, unnoticed, a second live
instance of exactly this combination: a 390px-wide rig viewport with the
same unset, pointer-primary default (see "Rascal Rally" below).

## Decision

**Compact is the single-panel boundary, asked directly, in `menu.luau`'s own
automatic resolution — not a new breakpoint.** The framework's compact/
regular/wide partition is `layout/adaptive.luau`'s `adaptive.sizeClass`
(breakpoints `{ regular = 600, wide = 1000 }`, gap 7b's `isCompactOnly`/
`isRegularOrWider` naming the same two-way split this decision needs). It is
the same `sizeClass` string this file already reads as `sizeClassSource` and
already compares against the literal `"compact"` one line above (inside
`resolvePresentation`'s own count-gated rule) — this decision asks the
identical question unconditionally, rather than inventing a second one:

```lua
local resolved = menuRecipe.resolvePresentation(menuRecipe.actionableCount(spec.items), liveSizeClass, touchLive)
if resolved ~= "sheet" and liveSizeClass == "compact" then
	resolved = "sheet"
end
return if resolved == "sheet" then "sheet" else "menu"
```

This lives in `menu.luau`'s `presentationMemo`, downstream of
`resolvePresentation`, rather than as an edit to `resolvePresentation` itself
— see "What this round does NOT change" for why the shared function stays
untouched.

**The override only ever WIDENS which environments choose `sheet`.** Every
existing path into `"sheet"` (`touchLive == true`, or `compact` with more
than six items) still returns `"sheet"` unchanged; the new clause only
upgrades the OTHER outcomes (`"menu"`/`"inline"`) to `"sheet"`, and only when
`sizeClass == "compact"`. Medium/large (`regular`/`wide`) are untouched at
every branch — the side-by-side expansion `resolvePresentation` already
decided for them stands exactly as before.

**An author-forced `presentation` is untouched — forcing stays the escape
hatch.** The override sits inside the `automatic` branch of
`presentationMemo`, after the early return for an explicit,
non-`"automatic"` `presentation` value. A caller that names `"menu"`
outright still gets the floating idiom at any width, including compact —
exactly as forcing already worked before this round, and exactly as the
existing "author-forced value wins" tests already assert
(`tests/menu.spec.luau`'s domain-check describe block, untouched).

### Focus is restored on the way back out, which `sheet` never needed before

`sheet` REPLACES its one surface on every level change (`presentLevel` tears
the old surface down and builds a new one at the shorter chain), so the
fresh scope's own `entry = "first"` policy landed backing-out focus on the
level's first row (or its `Back` row, one level deeper) — sane on the way
IN, wrong on the way OUT, and invisible until `sheet` was reachable widely
enough that a nested back-navigation was worth fixturing on its own terms
(this round's own test does: `NESTED`'s "adjust ▸ layer" is the SECOND row
under "adjust", so a first-row default provably lands on the wrong item).

`ops.back()` now remembers the item id it is leaving (`table.remove(chain)`
already returns it) and, once the parent level is re-presented, calls
`graph.focusOn(path)` to move focus onto that row:

```lua
local leavingId = table.remove(chain)
...
if presentation == "sheet" then
	presentLevel(0, presentation, chain)
	local graph = graphs[#graphs]
	if graph ~= nil then
		graph.focusOn(`/{surfaceIdFor(0)}/Layer/{PANEL_ID}/Item:{leavingId}`)
	end
end
```

This is the identical technique `present/surface_lifecycle.luau`'s `raise`
already uses to restore a remembered focus across an equivalent
remove-then-push scope rebuild (capture the path, rebuild the scope, then
`graph.focusOn` it back) — not a new mechanism. `focusOn` is a harmless no-op
if the id is no longer present (an author removed the item while the level
was open), so no new failure mode is introduced.

Every OTHER input-mode route into "back" was already wired before this round
and is unchanged: the visible `Back` row (touch, `handleActivate`), the
generic `Cancel` action (`handleCancel` → `ops.back()`, bound to gamepad
`ButtonB` — **keyboard `Escape` is not a route at all**:
`present/presenter.luau`'s own standing comment states it is "permanently
bound to the Roblox CoreGui menu (engine VirtualInput refuses it outright;
verified live 2026-07-19, D1)", so the keyboard route back is the arrow key,
not Escape), and `navigateIntercept`'s `direction == "left"` (keyboard
arrow / gamepad D-pad, through the shared `Navigate` action) → `ops.back()`.
This round adds regression coverage that all three still reach `ops.back()`
when `sheet` is chosen AUTOMATICALLY (at a compact width) rather than only
when it is forced, since that is the newly-reachable path
(`tests/menu.spec.luau`'s item-14 describe block).

## What this round does NOT change, and why

- **`menu_recipe.resolvePresentation` itself is untouched.** It is also
  called directly by `popup_button.resolvePresentation` (an alias by
  identity) for a flat OPTION LIST that has no submenus and therefore no
  "second panel over the first" defect to close — `shouldHaveSinglePanel.png`
  is specifically a NESTING defect. Folding the compact override into the
  shared pure function would additionally change `popup_button`'s
  (and transitively `card_rail`'s `touchPrimary` read's neighboring)
  behavior for a product question the director's item 14 does not ask —
  "should a plain option list always become a bottom sheet on any compact,
  pointer-primary surface" is a separate decision this round does not make.
  The brief's own instruction is to prefer landing item 14's change in the
  menu control itself, and this is that: the override lives in
  `menu.luau`'s `presentationMemo`, one call site, not in the shared recipe.
- **`picker.resolvePresentation` is a different, pre-existing function**
  (`src/controls/picker.luau`, its own `longestLabel`-driven ladder) and is
  not called anywhere in this change.
- **The item-count rule inside `resolvePresentation`
  (`sizeClass == "compact" and optionCount > 6`) is now dead code for
  `newMenu`'s own call site** (compact forces `sheet` unconditionally,
  upstream of that branch ever mattering) but is left in place rather than
  removed: `popup_button` still calls the same function and still needs it.
  Deleting a branch one caller no longer reaches, out from under a second
  caller that does, is the kind of edit ENGINEERING.md's "flag refactors,
  don't smuggle them" rule exists to prevent.
- **Focus restoration on ENTER is unchanged.** Entering a submenu under
  `sheet` still lands focus on the level's first row (or its `Back` row, if
  one level deep) via the existing `entry = "first"` policy — no test or
  director ruling names this as broken, and there is a real, sane
  precedent for auto-focusing the header/back affordance first on a pushed
  screen. Only the OUT direction had an observable defect (a naive
  first-row landing after the player was already looking at a specific
  item), and only that direction is fixed.

## Rascal Rally

`games/RascalRally/code/tests/facet_menu_contract.spec.luau`'s rig presents
at a 390×844 viewport — genuinely compact — with no `interactionClasses`
override, which resolves to the same pointer-primary default this ADR's
whole fix targets. Its first case (`"newMenu is LIVE through this package's
own require path..."`) asserted the OLD, defective shape by coincidence:
opening the menu and tapping a row at
`/Menu-Ctx/Layer/Surface/Panel/Item:spectate` (the floating `"menu"` idiom's
path) and reading `w.presenter.anchoredSurfaces().count` (which only counts
ANCHORED, i.e. floating, surfaces — always `0` under `sheet`). Migrated to
the `sheet` shape this package's own real phone viewport now correctly
resolves to: the row path drops its `/Surface/` segment
(`/Menu-Ctx/Layer/Panel/Item:spectate`, matching this file's own
`sheetRow`-shaped path convention) and the surface-count assertion reads
`control.dump().surfaces` (idiom-agnostic, already how the Facet-side
showcase itself counts) rather than `anchoredSurfaces().count`. Per this
package's own tripwire case (`"TRIPWIRE: no shipped Rascal Rally source
opens a menu..."`), `newMenu` is not consumed by any shipped Sponsor screen
today, so no gameplay UI moves — this is a consumer-contract test proving
the construct is reachable through RR's require path, and it is reachable in
the corrected shape.

## Ledger integrity: a concurrent-commit collision found and repaired in the same round

While adding row B-33 to `docs/adr/ADR-0040-unreleased-breaking-changes.md`
(this campaign runs several lanes against the same shared file "in place on
main," R1), commit `9320a23` ("task INPUT fix round 1, IMPORTANT 1+2")
landed with the table's **row B-31 silently dropped and its own new row
mislabeled B-32 — a duplicate of [ADR-0059](ADR-0059-themed-chrome-is-a-layout-fact.md)'s
already-taken B-32.** Confirmed against git history: `9320a23^` (the
commit's own parent) still had B-30/B-31/B-32/B-33 in correct order and
sequence, so the regression is entirely inside that one commit's own diff —
not a merge artifact of this round's edit. The commit's own message even
cites "B-31" as an existing precedent in its prose, so the row existed when
that text was written; the working copy it wrote back did not carry it
forward.

**Repaired mechanically, not re-derived:** B-31's exact original text was
pulled verbatim from `9320a23^` (`git show 9320a23^:docs/adr/ADR-0040-...md`)
and reinserted; the colliding row was renumbered **B-32 → B-34** (the next
free number once B-31 is restored and B-32/B-33 stand), touching only its
leading table-cell label — its prose is untouched, and INPUT's own analysis
is INPUT's to stand behind, not something this round second-guesses.
`docs/adr/ADR-0058-physical-size-aware-ten-foot.md`'s two internal citations
of "row B-32" (its own front matter and body) are updated to B-34 to match,
with a pointer back here. No other file in `docs/`/`.superpowers/` cited the
collided number. Recorded here rather than silently fixed, per this
project's own discipline for a reviewed correction (the same discipline
ADR-0058's own front matter invokes for its reversal) — and because the
next lane to add a row should know the register's own integrity was
findable rather than assumed.

## Device-owed

Studio cannot inject a real `touch` capability signal, which is exactly the
gap this ADR's own load-bearing repro exploits — the compact phone preset,
driven by an actual finger on an actual phone, is the config this fix has
not been confirmed on live. Owed to the sweep round: one compact on-glass
capture of the "Menus and their five triggers" showcase — phone preset,
open a five-item root menu, enter "Layering" — confirming a single panel
with a working `Back` row rather than the two overlapping panels
`shouldHaveSinglePanel.png` shows, and that focus (an on-screen ring under
keyboard/gamepad, or an accessible reader's cursor under touch) lands on
"Layering" itself after backing out of its children.
