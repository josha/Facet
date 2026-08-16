# Hit-expander overhang: the corpus measurement (2026-08-15)

**Tier: Studio, real engine.** Every number here comes from a parallel real-engine
mount — `require(RS.LuauUI)` + a real `screen_target.new({})` per scenario, built
through each fixture's own `build(ctx)`, presented, refreshed, measured off
`AbsolutePosition`/`AbsoluteSize`, then destroyed (fresh ScreenGuis diffed against
a pre-mount snapshot and removed). **The showcase demo picker was NOT used** — see
"instrument trap" below.

## What was asked

Before adopting the rule *"an expander that overhangs its parent must outrank the
siblings it overhangs"* (and its stronger, satisfiable form, below), two questions:

1. enumerate every control that produces an overhanging expander;
2. for every host the rule would lift, does its **painted** rect intersect the
   painted rect of the sibling it would be lifted over?

## Result

| | |
|---|---|
| scenarios mounted | **48 of 53** (5 `ref_*` fail on an unrelated asset dependency) |
| hit expanders in the corpus | **86** |
| overhang relations (expander reaches past its host into a higher-z interactive sibling) | **82** |
| **painted-rect overlaps among those 82** | **0** |

**Zero.** Not one host the rule would lift has a painted rect that intersects the
painted rect of the sibling it would be lifted over. The paint-reorder worry was
theoretical: the expander is an invisible hit-test extension, the host's own
painted rect does not reach into the neighbour, and **a z change between
non-overlapping rects is invisible by construction.**

So the rule ships **unqualified across all four `minHitSize` classes**
(`Grip`, `Button`, `Toggle`, `TextField`). No `Grip` special case.

## The population — and it is not a Table bug

The three distinct shapes, all `PAINT=false`:

| scenario | shape | overhang | relations |
|---|---|---|---|
| `virtual_list_native` | row `Hit` buttons 20px tall | ±12px vertically into the adjacent row's `Hit` | 31 |
| `keyboard_navigation` | `Row1..Row12` buttons 36px tall | ±4px vertically into the next row's Button | 44 |
| `table_columns` | `Grip` 8px wide (the reported defect) | 18px horizontally into the neighbour's `Column` | 2 |
| `table_columns` | `Column` / `Grip` | vertically into the first row's `Hit` | 5 |

**`keyboard_navigation` and `virtual_list_native` have this defect silently right
now.** A row whose button is under the 44px floor advertises a floor that reaches
into the row below and loses the overlap there, so the bottom strip of every such
target belongs to the next row. Nobody has reported it because the two rows do
the same *kind* of thing and a miss lands on a plausible neighbour — unlike the
Table, where a miss sorts a column the player never touched.

## The qualifier that IS required

> ...outrank non-expander siblings only; leave **expander-vs-expander** to the
> existing host z order.

Two neighbouring sub-44px controls each have a 44px floor, and those floors
overlap each other (measured: `hud`, host `R1`, two 44x44 expanders overlapping by
5%). Under an unqualified rule each would want to outrank the other in that
sliver — circular for the exact population the rule governs. The tie is broken by
host z order, as it is today.

## Why "raise the expander" alone is unsatisfiable

`adapter.setZOrder(handle, z)` derives `expander.ZIndex = z - 1`, and the `- 1` is
load-bearing: hover is wired as `instance.MouseEnter`/`MouseLeave` **on the host**
(`screen_pointer.luau`), so an expander above its host swallows hover and the
cursor hint for the host's own rect. The expander therefore needs
`expanderZ < hostZ` **and** `expanderZ > neighbourZ`, while the neighbour is
always walked later (`neighbourZ > hostZ`). No integer satisfies both.

The satisfiable form is therefore:

> a host whose expander overhangs is lifted, **with its expander**, above the
> non-expander siblings that expander reaches into.

and the measurement above is what makes that safe to say out loud.

(The tempting alternative — park every expander in a top hit layer — is a bigger
change than it looks for the same reason: it would need hover and cursor-hint
forwarding as well, not just `Activated` and pointer-began.)

## Instrument trap, recorded so the next sweep does not repeat it

`LuauUIShowcaseAPI.showNext` **returns** the advanced demo id (`surface-overlap`,
`sorted-entries`) while a subsequent `current` read answers `hud` and
`LuauUI_HudScreen` stays mounted. A 32-demo sweep run through the picker in that
state scans `hud` 21 times and **reports a clean bill of health for demos it never
looked at** — a null result that agrees with whoever ran it. It was caught only
because a known-positive case (the Table's own Grip) failed to appear in a sweep
that had just found it on a direct scan.

**Do not sweep through the picker.** Mount the scenarios directly off
`ReplicatedStorage.LuauUIScenarios.modules[name]` (they are ModuleScripts, so
`require` them) — it removes a whole subsystem from between the measurement and
the thing measured, and it is what produced every number above.
