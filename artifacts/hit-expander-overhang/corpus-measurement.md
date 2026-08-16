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

## Outcome — the rule shipped the same day (2026-08-15)

`src/render/hit_lift.luau` (its own module because `renderer.luau` is at the
200k `Script.Source` cap), applied by the renderer's z walk. Three clauses:

1. **it lifts** — a host whose expander overhangs is walked, with its expander,
   after the sibling BRANCHES that expander reaches into (resolved at the two
   nodes' nearest common parent, so whole subtrees travel and a `zIndex` scope
   stays intact);
2. **it stops at the host** — a target the host's own PAINTED rect already
   overlaps is not "past its host". Without this clause the header cell's own
   28px floor lifts the cell OVER the 8px divider inside it and buries the thing
   the rule exists to make reachable. It is also what makes the zero-overlap
   property above true by construction going forward;
3. **the qualifier** — only a real input-sinking rect creates a lift; another
   expander's invisible rect never does.

Two facts the corpus did not surface, both found by building it:

- **`hostZ - 1` collided.** The expander's z is the z of whatever node the walk
  visited immediately before its host — a tie the engine breaks by insertion
  order. The walk now reserves that counter. Without the reservation a host
  lifted one position past a LEAF sibling lands its expander level with it, and
  level is not above (`keyboard_navigation`: Row1 z 37 over Row2 z 36).
- **A tiled list reverses.** Where every row is sub-floor and the rows tile,
  each row's floor reaches into the next and the constraint chain reverses the
  whole list's paint order. It is a TRANSFER, not a gain: each row delivered its
  own extent minus one overhang either way — before the rule the overhang went
  to the row below, after it the row above. Painted rects do not overlap, so the
  reorder is invisible; whether either direction is noticeable to a finger is a
  device question, still owed.

**Delivered band, re-measured live per pixel** (`table_columns`, showcase place,
parallel real-engine mount, native stylesheets): x `EXP 18 + Grip 8 + EXP 18` =
**44 of 44** (was 26); y `EXP 8 + Grip 28 + EXP 8` = **44 of 44** (was 38). An
outer-half drag resizes; an outer-half tap sorts nothing; a clean header tap still
sorts.

**Rascal Rally is in the population and says so** (`code/tests/
luauui_hit_expander_overhang_contract.spec.luau`): its racer rows paint 28px at a
30px pitch under a 44px floor, so this screen's rows genuinely reordered. The
shipped Sponsor surface grows no expander at all.
