# D6 — the segmented Picker's upgrades

Brief: `docs/plans/navigation-and-menus-brief.md` §2 D6. Director call:
`artifacts/navigation-and-menus/additive-vs-net-new.md` §1 — **D6 is a properties-only
stage: no new construct, no new module.** Built 2026-08-16 against LuauUI `0.9.0`, on
top of D4's seam (`0ad61ff`).

## The final public surface of `newPicker`

```lua
LuauUI.newPicker(LuauUI, core, {
    id?, label?,
    options,        -- { { value, label, icon? } }   icon = a SEMANTIC NAME
    selected,       -- owner-held Signal
    presentation?,  -- "automatic" (default) | "segmented" | "inline"
    indicator?,     -- "automatic" (default) | "none" | "underline" | "pill"   << D4, D6 default
    axis?,          -- "x" (default) | "y"           << D4, D6 shape
    iconOnly?,      -- boolean, default false        << D6
    sizeClass?, env?, enabled?, onChange?,
})
```

Three keys are new to `PICKER_KEYS` across D4+D6 (`indicator`, `axis`, `env`) plus
`iconOnly` here; `Option` gained `icon`. Nothing was removed and nothing was renamed.

## 1. The default changed, and that is the deliverable

`indicator` now spells `"automatic"` and **resolves to the pill** unless the caller
declared `presentation = "inline"`:

| declared presentation | automatic indicator |
|---|---|
| `"inline"` | `"none"` — the row list never wore a chip, and its painting is untouched |
| `"segmented"` or `"automatic"` | `"pill"` |

D4 shipped `"none"` as the default so nothing on screen moved. That was right for a
stage whose job was the mechanism and wrong to leave: **a mechanism nobody consumes by
default is an unproven mechanism**, and every reference screenshot of a segmented
control (`r3`, `f1`'s top pill, `f1`'s left rail) draws a chip.

**The rule deliberately reaches `presentation = "automatic"`**, which is what most
callers actually write. A default that only reached a *declared* `segmented` would have
changed 7 of the 15 callers instead of 14 — and the reference apps, the ones shaped
most like `r3`, are all in the `automatic` half.

**So an adaptive picker that flips into its stacked form carries its chip down with
it.** One selection paint re-solved, rather than two paintings swapping. This is a
deliberate reading of "inline keeps its current painting": a picker *declared* `inline`
is byte-identical, and only an adaptive one carries the decoration across the flip —
which is what the A-AL2 rule (a presentation flip is a re-solve, not a rebuild) already
promises about everything else in this control.

It is also the reading that survives contact with the renderer. The alternative —
switching the indicator off reactively when an adaptive picker stacks — needs the option
Buttons' `surface` to toggle between `"plain"` and *whatever an undeclared Button is*,
and there is no honest value for that: `applySurface` is reached with the literal string,
an undeclared Button gets no surface tag at all (so `"control"` is not equivalent), and a
reactive prop yielding `nil` reaches `adapter.setProp` and lands in the real adapter as
`tostring(nil)` → `"nil"`, a garbage native tag. Measured both ways on the fake target
before choosing.

`indicator = "none"` is the documented escape hatch, byte-identical to the pre-D4
control. D4's own spec case now asks for it by name (`indicator = "none" is
byte-identical to the pre-D4 control`), and **d4's gate grep was re-pointed in this
commit** rather than three stages later — D0.2's rule applied to its first rename.

## 2. The full caller survey — 15 callers, 1 pinned, 14 adopted

Every `newPicker` in `src/`, `examples/`, `tools/` and `games/RascalRally/code`, read at
this commit.

| # | Caller | Presentation | After the flip |
|---|---|---|---|
| 1 | `examples/gallery/scenarios/time_curves.luau:408` `MotionMode` | declared `segmented`, 2 opts | chip. Two peers, `Full` / `Reduced` — the shape the chip was drawn for |
| 2 | `examples/gallery/scenarios/sorted_entries.luau:174` `Construction` | declared `segmented`, 3 | chip |
| 3 | `examples/gallery/scenarios/text_degrade.luau:165` `Room` | declared `segmented`, 4 | chip |
| 4 | `examples/gallery/scenarios/with_animation.luau:234` `MotionMode` | declared `segmented`, 2 | chip. This fixture is *about* motion; its reduced-motion assertions still pass, because the chip snaps (D4's I-4 argument, unchanged) |
| 5 | `examples/gallery/scenarios/flow_wrap.luau:144` `BlockAlign` | declared `segmented`, 3 | chip |
| 6 | `examples/gallery/scenarios/adaptive_controls.luau:88` `Quality` | `automatic`, 3, live `sizeClass` | chip, and it **rides the flip** — `"Performance"` is 11 characters, so a compact space stacks this control and the chip goes with it. The scenario's own spec is green |
| 7 | `examples/gallery/client/settings_panel.luau:176` `MotionMode` | declared `segmented`, 2 | chip |
| 8 | `examples/gallery/client/showcase_chrome.luau:193` `Section` | declared `segmented`, 2 | chip. The most-seen surface in the repo (`Demos \| Settings`), and the one the keyboard/gamepad reachability specs walk |
| 9 | `examples/reference/p2_cartwheel/screens/gallery.luau:95` `Layout` | `automatic`, 2 short | chip |
| 10 | `examples/reference/p2_cartwheel/screens/gallery.luau:117` `Timeframe` | `automatic`, 4 | chip; stacks in compact |
| 11 | `examples/reference/p2_cartwheel/screens/topfive.luau:47` `Timeframe` | `automatic`, 4 | chip; stacks in compact |
| 12 | `examples/reference/p2_cartwheel/screens/ledger.luau:65` `Timeframe` | `automatic`, data-driven (gated labels are long) | chip; stacks in compact |
| 13 | `examples/reference/p5_wardrobe/init.luau:307` `Sort` | `automatic`, 3, inside a modal | chip |
| 14 | `examples/reference/p5_wardrobe/init.luau:954` `Section` | `automatic`, 3 | chip. `boutique / outfits / profile` is the `r3` shape almost exactly |
| 15 | `tools/lune/_theme_baseline.luau:142` `Quality` | `automatic`, 2 | **PINNED to `indicator = "none"`, with the reason in source** |

`games/RascalRally/code/src` — **no `newPicker` at all**, read off the shipped source by
the tripwire rather than remembered.

**Why #15 is the one pin, and why it is not a weakened default.** That fixture is not a
screen: it is the `control-vocabulary` half of the input `check_flat_baseline`
regenerates and compares node-for-node against the stored 0.6.0 render, and *that
comparison is* the flat-theme byte-compatibility claim (ADR-0020 R9). Letting the new
paint in would have re-pinned the framework claim in order to make a paint change quiet
— which is the exact failure `check_flat_baseline`'s own header warns about, and the
reason its allow-list exists. Three gate rows run that checker (`prior-gates`,
`theme-packages-and-skinning`, `layered-slots-and-posture`), and none of them reddened.

**What the survey cost in test edits** (all path moves, no behaviour changes):
`display_controls.spec` (an `optPath` helper resolved from the dump, so no case
hard-codes the answer it tests), `theme_roles.spec`, `examples_gallery.spec`,
`gallery_chrome.spec`, and the `Picker` large-text fixture, which now declares
`indicator = "none"` so the *unindicated* shape it exists to sweep keeps being swept
beside `Picker-indicator`.

## 3. Icons follow the shipped ruling instead of writing a second one

`Option.icon` is a **semantic icon name**, never an asset id — the currency
`row_actions.ActionSpec.icon` already spends. It rides `compactLabel` on the option
Button, because `Button.icon` (the top-level prop) is circle-only and a segment is a
rectangle.

`iconOnly` picks which of the **two readings of the 2026-08-12 device-round ruling**
applies, and it is a **group** decision:

| | reading | source of the ruling |
|---|---|---|
| `iconOnly = false` (default) | the segment keeps its word; the glyph is the **degrade** | `row_actions.luau:1774` — "a menu row is a list of names; it is where the words live" |
| `iconOnly = true` | `prefer = true`: the glyph is what every segment wears **at every width** | `row_actions_trays.luau:346` — the tray's inversion, and what `f1` draws |

It cannot be per-option for the reason the tray ruling itself gives: a per-segment
verdict is how one plate wears a glyph while its neighbour wears a word.

The ladder is proved to actually **run**, not just to be declared: at a 200 px viewport
an icon+label segment draws `B` / `P` instead of `Presentation` / `Enumeration`. Without
that case, "the word survives" is satisfied by never declaring the icon at all — which
is exactly what mutation M2 does.

**Three authoring rules refuse at construction** rather than on a screen:

1. **Every option needs a non-empty `label`.** It is the semantic name, it is what
   `dump().semanticText` announces, and an icon with no name is unreadable to every
   non-visual consumer. `check_registration` cannot see an unreadable glyph.
2. **Icons for all options in a group, or none of them** (HIG: Menus). A half-iconned
   group reads correctly at the one width it was authored at.
3. **`iconOnly` with no icons is refused**, not ignored — there would be nothing to
   draw.

An icon-only segment's semantic text is therefore free rather than special-cased:
`semanticText` reads `option.label`, which rule 1 guarantees exists. Mutation M13 (make
it announce the icon name instead) reddens it.

## 4. The vertical pill is a rail, and it is a second FACT

Both the vertical pill and the inline row list stack along y, and both report
`axis = "y"`. That is why they are computed as two separate memos (`axis` and
`verticalPill`) rather than one, and why `dump()` reports both.

|  | container | segments |
|---|---|---|
| segmented + `axis = "y"` | a **rail**: `{ type = "minMax", min = "targetSizes.minimum" }` — content-sized, floored at the tap target | cross-axis `fill`, so every segment shares the one width |
| `inline` | a **full-width column** (`fill`) | full width |

**The floor is load-bearing, not defensive.** An icon-only rail's natural width is a
glyph: measured at **36 px**, under the target on both axes. The height floor on the
segments cannot see it, because it is the *cross* axis there. With the floor, an
icon-only rail solves 44 × 46 per segment.

The width is a **memo on all three nodes** — the control root, the indicator wrapper and
the option stack — because an adaptive picker that stacks must give the offer back. A
build-time answer leaves a 44 px column standing where a full-width row list belongs
(mutation M12).

Honest note recorded in source: on the rail path the **wrapper's** width is not
observable, because the root above and the option stack below both pin it. Replacing it
with the band's width changes no solved rect (M10 did not bite). It is kept because it
is the true statement and because it is load-bearing on the band path, which D4 proved.

## 5. Docs: a segmented picker used as a tab bar IS TabView

Said in three places, so D5 finds it wherever it is standing:

- `docs/reference/api.md` → `newPicker`, first paragraph, plus a new
  "The vertical pill is not the inline row list" section and the icon table.
- `docs/reference/swiftui-parity.md` → the `Picker` row (still **Partial**, now naming
  what D6 added and what is still missing: no `.menu` / `.navigationLink` / `.wheel` /
  `.palette`), and the `PickerStyle` row in §6.1, which now says `.tabs` is not a picker
  style here at all.
- `src/controls/picker.luau`'s header, under **D5 COMPOSES THIS STRIP** — keep the
  option row reusable; anything a strip needs is a property.

No second tab construct was built.

## 6. Dump: still `/1`, decided rather than defaulted

`dump()` gained `verticalPill`, `requestedIndicator`, `iconOnly`, `iconCount` and
`selectedIcon`. The schema string stays `"luauui-picker-dump/1"` because **every field
that shipped keeps its name, its type and its meaning**: a reader written against `/1`
keeps working, and one that wants the new facts asks for them by name. A schema string
exists to warn about an *incompatible* shape, and adding fields is not one. (D4 added
`indicator` and `axis` on the same reasoning; a bump now would invalidate readers to buy
nothing.)

`verticalPill` is the field that earns its place: it is the only thing that separates
the two shapes that both answer `axis = "y"`, so "the picker went full width" is an
answerable bug report.

## Mutation ledger — 13 run against the shipped source, 12 bit

Each mutation was applied to `src/controls/picker.luau`, `lune run tests/run_one
picker_segments` was run, and the source restored.

| # | Mutation | Reddens |
|---|---|---|
| M1 | the automatic indicator resolves to `"none"` (D6 not applied) | 6 cases: the two default cases, the style-tag drop, both slides, and the `automatic` spelling |
| M2 | `Option.icon` never reaches `compactLabel` | `an icon rides compactLabel…`, `…the ladder really RUNS…`, `iconOnly INVERTS it…` |
| M3 | `iconOnly` drops `prefer = true` (the tray inversion lost) | `iconOnly INVERTS it: the glyph is what every segment wears at every width` |
| M4 | the rail falls back to the band's `fill` width | `axis = "y" … is a CONTENT-SIZED rail` |
| M5 | `verticalPill` is always false | the rail case **and** `dump().verticalPill is what tells the pill and the row list apart` |
| M6 | the rail loses its 44 px floor (`{ type = "content" }`) | `every segment of the rail still meets the 44px floor on BOTH axes` |
| M7 | the all-or-nothing icon lint never fires | `HIG: icons for ALL options in a group, or none` |
| M8 | an option may be nameless | `a nameless option is an AUTHORING ERROR` |
| M9 | `iconOnly` with no icons is silently ignored | `iconOnly with nothing to draw is refused rather than silently ignored` |
| M10 | the indicator wrapper hard-codes the band width | **NOTHING — recorded as a non-bite.** On the rail path the width is pinned twice over (root + option stack); no solved rect moves. Verified by dumping the geometry both ways, not inferred |
| M11 | the control root hard-codes the band width | the rail case **and** `flipping OUT of segmented gives the offer back` |
| M12 | the rail width is a build-time answer, not a memo | `flipping OUT of segmented gives the offer back: the rail becomes a column` |
| M13 | `semanticText` announces the glyph instead of the name | `an icon-only segment STILL CARRIES A NAME` |

M10's non-bite is why `wrapping does not collapse the rail` is labelled in the spec as a
**regression guard** rather than a mutation-proved check. A check nobody has seen fail is
decoration; saying so is cheaper than pretending otherwise.

## Rascal Rally consumer impact

**No production edit, and it is audited rather than assumed**: the game builds no
`newPicker` anywhere under `src/`, read off the shipped source by the D4 rider's tripwire
every run.

**The game rider caught the behaviour change before any D6 spec existed.** Its D4 case
asserted the old default (`indicator` defaults to `"none"`) and went red the moment the
framework flipped — 3289 passed / 1 failed. That is exactly the job the lockstep rule
gives it, and the second time in two stages that this file has earned its keep.

Consumer work:

- `tests/luauui_selection_indicator_contract.spec.luau` — the now-false "defaults to
  none, so every existing control is byte-identical" claim rewritten to name D6, and the
  case re-pointed at `indicator = "none"` (the escape hatch it was always really about).
- `tests/luauui_segmented_picker_contract.spec.luau` — **new**, registered in the game's
  `tests/run.luau`: the segmented default and its style-tag drop, the declared-inline
  no-change, an icon-only segment's glyph *and* surviving semantic name, the degrade
  reading, both lints, the rail's hug and its 44 px floor on both axes, and the closed
  spec — all through **this package's** framework require and presenter.

Suites: LuauUI **5772 passed / 0 failed**; Rascal Rally **3297 passed / 0 failed**.

## What this row does NOT claim

- **Everything here is E1.** No device and no human evidence. Whether an icon-only 44 px
  rail is comfortable under a thumb, whether the chip's contrast survives a themed
  package, and whether the degrade-to-glyph boundary lands where a designer would put it
  are NM-4.9's E3/E5 rows. They are still owed — but they are now owed by a **consumed**
  mechanism instead of an unconsumed one, which is the whole reason the default moved.
- **No example migrated to icons or to the vertical rail.** Both ship with spec consumers
  only. That is the honest state and the first thing a device pass should be pointed at.
- **Nothing about size-change cost.** D4's caveat stands: a slide between *unequal*
  segments re-measures once per animated frame. A picker's segments are equal-weight
  fills, so the shipped consumers slide arrange-only, and the unequal case is still
  unbenchmarked.
- **No claim that `.menu`, `.wheel`, `.navigationLink` or `.palette` moved.** The `Picker`
  parity row stays **Partial**, and says why.
