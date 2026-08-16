# D4 — the sliding selection indicator seam

Brief: `docs/plans/navigation-and-menus-brief.md` §2 D4. Acceptance rows NM-4.1 … NM-4.9
in `acceptance.md`. Built 2026-08-16 against LuauUI `0.9.0`.

## What shipped

**The public surface is a property, not a construct** (director ruling, mid-stage).
`newPicker` gained three spec keys:

```lua
indicator = "none" (default) | "underline" | "pill"
axis      = "x" (default) | "y"     -- the SEGMENTED presentation's axis
env       = <environment>?          -- so the bar's metrics follow a live theme
```

The mechanism — `src/controls/selection_indicator.luau` — is **internal**: no
`src/init.luau` export, no `api.md` heading of its own, and no dump schema of its own.
Its live state rides `picker.dump().indicator`, and its registry row names `newPicker`,
the shape `VirtualWindow` and `RowActionsTrays` already use for a module that returns
what its control mounts. D5's `TabView` will carry the same property. Everything is
documented under `docs/reference/api.md` → `newPicker`; the spec is
`tests/selection_indicator.spec.luau` (40 cases).

`indicator = "none"` leaves the pre-existing control byte-identical, which is why the
addition cost no shipped screen anything.

**The seam itself is a layout seam, not a control and not a modifier.** It owns no
value, takes no input, and is never a focus stop; and the constitution's
positional-scalar modifier family is closed (§16 E-18) while this needs its own
reactive state, motion and geometry intake.

**Neither consumer owns it.** D5's `TabView` is a strip with content below, D6's
segmented `Picker` is a pill with nothing below, and f1's left rail is that pill turned
vertical. The seam is told nothing about any of them: it takes `content` (the strip
blueprint, whatever shape), `segments` (`{value, id}` pairs) and `selected` (the owner's
Readable, never written), then resolves each child's *solved rect* by id at run time.

**Turning it on changes what the options paint**, deliberately: they drop the `selected`
style tag and go `surface = "plain"`, because a tag *and* a chip is the same statement
twice — and an opaque Button would paint over the chip meant to sit behind its label.
They also move one level deeper (`…/Indicator/Options/OptN`), because the decoration
layer and the option stack have to share one parent; activation is unaffected (the
control dispatches on the leaf segment) and a spec pins that.

**Wrapping is not free, and the game rider found the cost first.** A `fill` strip inside
a content-sized wrapper has nothing to fill and solved to **zero width** — an indicated
picker's options measured 0 px. The wrapper now inherits the strip's own dimension, and
the regression compares the indicated control against the plain one rather than against
a number somebody chose.

## How the selected child's rect reaches the indicator

1. The seam attaches its own input contribution to the wrapper's root, so the presenter
   discovers it by the ordinary `collectContributions` pre-order walk — no host
   forwarding.
2. `syncGeometry(rectOf, rootNode)` is fed on every solve and every refresh. On the
   first call it walks the mounted tree and learns the layer's path and each segment's
   path **by identity** (the `slider.luau` idiom — never by string arithmetic, because
   the mounted path depends on where the consumer placed the wrapper).
3. It writes a **flat numeric table** — the layer's rect, then four numbers per segment
   — into a scope-owned signal whose equality is `sameGeometry`.
4. A scope-owned **memo over (`fed`, `selected`)**, compared by the same comparator,
   produces the indicator's rect through the pure `resolveIndicatorRect`.

`rectOf`, not `screenRectOf`: the indicator lives in the *same parent* as the strip, so
it inherits every scroll offset and presentation shift the strip inherits, and
subtracting two raw host-space rects cancels them exactly. `screenRectOf` accumulates
those shifts, so inside D5's overflowing horizontal ScrollView it would apply the scroll
twice and fly the bar off the strip.

The comparator is `renderer.luau:2778-2800`'s `sameGeometryValue`, field for field:

```lua
local function sameGeometry(a: any, b: any): boolean
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in a do
        if type(v) == "table" then return false end   -- a nested field is REFUSED
        if b[k] ~= v then return false end
    end
    for k, v in b do
        if a[k] ~= v then return false end            -- ...and in both directions
    end
    return true
end
```

The nested-table refusal is the renderer's deliberate conservatism, kept for the same
reason: a rebuilt-outer/reused-inner shape compared by identity would report a false
"unchanged", which is a *missed* update, not a spare one. Storing the geometry flat is
what makes that refusal free rather than an obstacle.

**Both stages are load-bearing and they fail differently.** Without the guard on `fed`,
eleven idle refreshes cost eleven derivations (a cost). Without the guard on the memo, a
sibling growing above the strip re-places the bar *mid-flight* and snaps it (a visible
defect). Each has its own case; the second one only reddens when the wrapper moves while
its relative rect does not, which is why the fixture grows a spacer above it.

## Motion

`object` (ζ 1.0, response 0.28 s) — the class the framework already uses for "small
manipulable things, flights, chips", which is exactly what a travelling chip or bar is.
`container` (0.35 s) is for large surfaces materializing, and the indicator is not one.
Overridable through `motionClass`.

Four scalar springs carry x, y, w and h, built **lazily** on the first slide from the
presenter's own clock (`bindMotion`), each observed into the owned signal that is bound
into the blueprint — `row_actions.luau:1021-1049`'s shipped shape. With no clock (a bare
`mount` + `renderer.attach`, no presenter) every retarget is an instant placement: a
supported degradation, not a second code path.

Two rects, never two indices: segments stop being equal-width the moment labels differ
("For you" vs "Charts" in r2) and again under a 1.4x pseudo-localization.

The seam **never calls `presenter.withAnimation`**, which is presenter-wide and
hard-errors on re-entrant nesting; it drives its own motion values, so it is safe to
mount inside a caller that has already opened one.

## Reduced motion

There is **no reduced-motion branch in this module**. A `clock:spring` value is
decorative by default, and the motion authority's I-4 invariant already places a
decorative `setTarget` at its terminus instantly, on the same frame, with the same
events; the clock reads `motionPolicy`, which the environment derives from
`reducedMotion`. Reading the fact a second time here would be the re-plumbing the brief
forbids.

The proof counts frames, because that is what the claim is about:

| | writes to the bar's rect |
|---|---|
| reduced motion, one selection change | **1**, then **0** across twenty `tick(1/60)`s; `motionClock:activeCount() == 0` |
| full motion, the same change | **> 10**, with **> 3** frames strictly between the two segments' x |

Reading `env:get("reducedMotion")` back would have proved only that the fixture set it.

## Vertical

`axis = "y"`. The pill is the same arithmetic on both axes (inset on four sides), so a
vertical pill needs no second path at all; the axis decides only which edge an underline
spends its thickness on — the bottom of a horizontal segment (r2, f1's sheet strip), the
leading edge of a vertical one (f1's left rail). Proved as a unit case, as a mounted
vertical pill that moves along y, and through the public property.

**`axis` had nothing to overload.** `PICKER_KEYS` never contained it — the old `axis`
was a private memo derived from `presentation` — so `axis = "x" | "y"` is a new public
prop that applies to the **segmented** presentation. `"y"` is a real vertical *pill*;
`presentation = "inline"` is still the stacked row list, a different shape, and a spec
pins that an `inline` picker reports `axis = "y"` whatever was asked for.

The seam takes `axis` as a **Readable**, not a build-time string, because picker's own
option-stack axis is a memo: a live space change flips the presentation as a *re-solve*
(the A-AL2 rule), and an indicator holding a build-time axis would underline the wrong
edge for the rest of the session.

## Never a focus stop

`focus_map.collectFocusables` appends any node whose class is in
`FOCUSABLE = { Button, Toggle, TextField }`, and that flat order *is* the document order
Tab walks. The seam mounts an `Anchor` holding a `Box` — neither class is focusable —
and the layer is declared **first** inside the ZStack, so it paints behind the strip and
can never take a gesture from a segment (ZIndexBehavior is Sibling; a GuiButton sinks
input, so the decoration must never be the thing above it). The spec asserts the wrapped
strip's focusable paths are exactly its two buttons, in order, and that neither mounted
class appears in `FOCUSABLE` at all.

## Theme

`thickness` and `inset` default to `"space.xs"` — small distances the theme's own
spacing scale already owns, so **no new control family** was added and every package
published before this module answers both. They resolve through
`themeSnapshot.resolveNumber` against `env:get("themeMetrics")` (optional `spec.env`,
degrading to the neutral snapshot) because the arithmetic is Luau's: `child.h -
thickness` cannot be handed to the solver as a metric name. `corner` defaults to
`"pill"` on the pill skin and to square on the underline, which is what r2 and f1 draw.
`check_theme_drift` PASSes.

## Registration: one checker change, guarded

`check_registration` treated "attaches an input contribution" as "interactive". That was
right for every control that had ever attached one, but the bundle also carries two
**intake** seams — `syncGeometry` and `bindMotion` — and a composite declaring only
those advertises no verb on any class and mounts nothing focusable, so the four-input
bar has nothing to be about. `CONTRIBUTION_INTAKE_ONLY` is the explicit, reviewable
exemption (the shape `INTERACTIVE_ACTION_EXCEPT` and `check_theme_drift`'s `ALLOWLIST`
already use), and it is **guarded**: a listed module whose source mentions any
verb-bearing bundle field loses the exemption immediately. Adding
`handleActivate = function() return false end` to the seam reddens the checker with
three problems, naming the field.

## Mutation ledger — every check confirmed to BITE

Each mutation was applied to the shipped source, the spec run, and the source restored.

| # | Mutation | Reddens |
|---|---|---|
| M1 | `resolveTransition` always returns `"slide"` | `a re-solve under an unchanged selection PLACES…` |
| M2 | the `fed` geometry signal compared by identity | `repeated geometry feeds with UNCHANGED rects cost nothing (the by-value guard)` |
| M3 | the motion values declared `kind = "informational"` (RM keeps them running) | both reduced-motion cases — the seam's and the picker's |
| M4 | the vertical underline's height replaced by a constant | `underline y: a VERTICAL strip underlines the leading edge and spans the height` |
| M5 | the layer declared **after** the strip (painted on top) | `mounts one bar behind the strip and lands on the initial selection with no travel` |
| M6 | the pill's width replaced by a constant | `pill: the chip is the segment box inset…`, `a pill never inverts…` |
| M7 | the target memo compared by identity | `a geometry change that does not move the bar cannot interrupt a flight in progress` |
| M8 | `springs.x:setTarget` replaced by `:snap` (no flight) | three cases: the seam's flight, the flight-interrupt case, and the picker's chip |
| M9 | `handleActivate` added to the bundle | `check_registration` (3 problems, the exemption refused by name) |
| M10 | the wrapper drops the declared `width` | `wrapping does not collapse a \`fill\` strip — the options keep their width` |
| M11 | picker ignores the `indicator` property | seven cases, the whole public-surface block |
| M12 | picker ignores the `axis` property | `axis = "y" is a real VERTICAL PILL, and it does not overload \`inline\`` |
| M13 | an indicated option keeps its opaque plate | `turning it on makes the INDICATOR the selection paint, not a second one` |

Rascal Rally's rider was mutation-proved the same way: M8 reddens its full-motion
positive control, M3 reddens its reduced-motion count, and a file under `src/` mentioning
`newPicker` reddens its tripwire.

## Rascal Rally consumer impact

`tests/luauui_selection_indicator_contract.spec.luau`, registered in the game's
`tests/run.luau`. **No production-game edit**, and that is the audited answer rather than
an assumption: the game builds no `newPicker` at all and ships no tab strip, no segmented
control and no hand-rolled cross-fading selection fill (searched across `src/`), so there
is nothing to migrate — and `indicator` defaults to `"none"`, so nothing already mounted
moves. Manufacturing a caller edit is what the execution contract forbids. The rider is
three halves: the framework this package requires really carries the three new keys and
the closed spec that refuses anything else; a **tripwire** that fails the day any `src/`
file builds a picker; and a positive control that builds an indicated picker on *this*
package's presenter and drives it against the guarantee the game would notice first,
reduced motion, counted in frames.

**The rider earned its keep.** The zero-width wrapper defect above was found by this
file, not by the framework suite — the framework fixtures used fixed-width segments and
never asked a `fill` strip to survive being wrapped.

Suites: LuauUI **5704 passed / 0 failed**; Rascal Rally **3290 passed / 0 failed**.

## What this row does NOT claim

- **No device or human evidence.** Everything here is E1. Whether a 4 px bar reads under
  a finger, whether the chip's contrast survives a themed package, and whether the
  flight *feels* like one object moving are E3/E5 rows (NM-4.9), owed by D5 and D6 —
  the seam's first consumers and the only surfaces a device pass can be run against. An
  unconsumed construct is unproven, and this one is deliberately unconsumed today.
- **No claim about size-change cost.** `width`/`height` carry `dirty = { "measure" }`, so
  a slide between *unequal* segments re-measures once per animated frame. The size memos
  are compared by value, so an **equal**-width strip (r3's icon-only segments) slides
  arrange-only — but the unequal case pays a measure per frame and no benchmark was run
  against it here.
- **Nothing about cross-tree hero transitions.** `swiftui-parity.md`'s
  `matchedGeometryEffect` row moves Missing → **Partial**: the selection case ships, one
  tree; carrying identity across two layout trees does not.
- **D6's remaining work is still D6's.** `Option` gains no `icon` here, no shipped
  surface was migrated onto the property, and the default stays `"none"` — flipping it
  is a product decision this stage did not take.
