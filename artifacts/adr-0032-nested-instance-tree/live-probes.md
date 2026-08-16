# ADR-0032 evidence — every number, and what instrument produced it

**Date:** 2026-08-15. **Session:** `LuauUI-Showcase.rbxl`, the one connected Studio
instance (`LuauUI-PerformanceLab` was NOT connected this round — checked, not assumed).
**Tier vocabulary** (per the standing rule): *headless Lune* = regression signal only;
*Studio* = the real engine on a desktop; *device* = the only device claim. **Nothing
below is a device claim.**

---

## 0. Instrument integrity — two traps hit, both recorded

**Trap 1 — the synced datamodel was BROKEN by a concurrent agent, and a naive probe
would have reported a framework failure that does not exist.** Every attempt to mount a
LuauUI surface threw:

```
ReplicatedStorage.LuauUI.render.renderer:1072: attempt to index nil with 'Screen'
```

Read back from the datamodel's own `Source`, line 1072 is
`if NO_DECORATION_CLASSES[node.class] then` — and a scan of the *whole* synced source
found **exactly one** occurrence of that identifier. Disk carries two:

| | disk `src/render/renderer.luau` | synced datamodel |
|---|---|---|
| module-scope declaration | **line 58** `local NO_DECORATION_CLASSES: { [string]: boolean } = { Stage = true, Foreign = true }` | **absent** |
| use site | line 1082 | line 1072 |
| total lines | 3949 | 3974 |

So the Rojo-synced copy carried the *use* of a table without its *declaration* — an
in-flight intermediate state from the concurrent `UI.Foreign` (ADR-0031) work, not a
defect in anything this ADR touches. **Every LuauUI mount in that session was failing.**

**Workaround used (the recorded clone-and-require trick).** The whole `LuauUI` tree was
`:Clone()`d, the clone's `renderer` `Source` patched with the one missing declaration
line, and the clone required. No file on disk was touched; the clone was destroyed and
verified absent at the end of the session.

**Trap 2 — the frame-time instrument was saturated and could see nothing.** The first
harness measured `RenderStepped` deltas and reported **66.65–66.80 ms in every arm,
flat and nested alike** — Studio's background/unfocused throttle (~15 fps), not the
work. That number is reported here only so nobody mistakes it for a result: **this
session cannot measure total frame cost.** Every timing below is Luau-side write cost,
which is the half the profiler attributes to `arrange`.

---

## 1. `ZIndexBehavior` — the brief and the coordinator both predicted `Global`; it is `Sibling`

Read live off all three LuauUI ScreenGuis in the running Showcase:

```
ScreenGui "LuauUI_ShowcaseBackdrop" ZIndexBehavior=Enum.ZIndexBehavior.Sibling DisplayOrder=10100
ScreenGui "LuauUI_ShowcaseChrome"   ZIndexBehavior=Enum.ZIndexBehavior.Sibling DisplayOrder=10200
ScreenGui "LuauUI_AdaptiveScreen"   ZIndexBehavior=Enum.ZIndexBehavior.Sibling DisplayOrder=10300
```

Source of record: `src/client/screen_target.luau:909` — `gui.ZIndexBehavior =
Enum.ZIndexBehavior.Sibling`, with the module header (line 7) stating it as a
foundational fact. (Roblox's own CoreGui ScreenGuis in the same PlayerGui — `Chat`,
`BubbleChat`, `Freecam` — are `Global`, which is the likely source of the expectation.)

### 1a. What each mode does to a nested child — programmatic oracle

`PlayerGui:GetGuiObjectsAtPosition(x, y)`, topmost-first. Shape: parent `P` (ZIndex 10)
containing `MID` (20) containing `DEEP` (**500**); flat sibling `S` (**100**) overlapping
`DEEP`.

| ScreenGui mode | parent class | topmost-first at the overlap |
|---|---|---|
| `Sibling` | `Frame` | `S(100)` **>** `DEEP(500)` > `MID(20)` > `P(10)` |
| `Global` | `Frame` | `DEEP(500)` **>** `S(100)` > `MID(20)` > `P(10)` |
| `Sibling` | `CanvasGroup` | `S(100)` **>** `DEEP(500)` > `MID(20)` > `P(10)` |
| `Global` | `CanvasGroup` | `DEEP(500)` **>** `S(100)` > `MID(20)` > `P(10)` |

### 1b. The same thing in pixels, because a hit-test oracle is not a rasterizer

Mounted under `StarterGui` in Edit mode (`screen_capture` sees only the Edit viewport —
it cannot see a Play client's `PlayerGui`; the first capture attempt returned a bare
baseplate and is discarded).

- **`Sibling`**: red `S` (z=100) **covers** green `DEEP` (z=500). Identical for
  `parent=Frame` and `parent=CanvasGroup`.
- **`Global`**: green `DEEP` (z=500) **covers** red `S` (z=100). Identical for
  `parent=Frame` and `parent=CanvasGroup`.

**A `CanvasGroup` is NOT an ordering boundary — refuted at pixel level.** The
coordinator's hypothesis was that an offscreen buffer composites as one layer that
outside content cannot interleave with. It does not behave that way. Re-run with
`GroupTransparency = 0.5` to force a *real* buffer (visibly desaturated, so the buffer is
demonstrably active, not optimised away at `GT=0`): the nested children still paint over
the outside sibling under `Global`. **Ordering follows `ZIndexBehavior` alone; the group
buffer changes compositing, not sort order.**

### 1c. Why `Global` is refused — ADR-0009's "verifier F1", reconfirmed live

ADR-0009 recorded: *"Instance.new LayerCollectors keep the legacy Global behavior, under
which nested control internals sort behind their opaque parents — verifier F1."*
Measured: parent `Frame` z=**50**, child `Frame` z=**20** (LuauUI's real shape — its icon
child is pinned at a fixed `ZIndex = 20`, seen in the live tree dump on every
`LuauUIIcon`).

- **`Sibling`**: yellow child **visible** — a child always paints above its parent.
- **`Global`**: yellow child **invisible** — it sank behind its own opaque parent.

---

## 2. Today's behaviour: what a container's `rotation` / `scale` / `opacity` do to its children

### 2a. Through the real framework, read off the engine

One `UI.Screen`, two `UI.ZStack`s with identical props `rotation = 30, scale = 1.5`,
`200×100`, each holding two `UI.Box` children of `80×40`. The only difference is
`canvasGroup = true` on the second. Verbatim adapter output (indentation = real engine
parenting):

```
Frame       /NestProbe                      Rot=0  UIScale=-    absSize=(800,600)
Frame       /NestProbe/Root/PlainRot        Rot=30 UIScale=1.50 absSize=(300,150)
  UIScale     LuauUIMotionScale
Frame       /NestProbe/Root/PlainRot/PA     Rot=0  UIScale=-    absSize=(80,40)
Frame       /NestProbe/Root/PlainRot/PB     Rot=0  UIScale=-    absSize=(80,40)
CanvasGroup /NestProbe/Root/GroupRot        Rot=30 UIScale=1.50 GT=0.00 absSize=(300,150)
  UIScale     LuauUIMotionScale
  Frame     /NestProbe/Root/GroupRot/GA     Rot=0  UIScale=-    absSize=(120,60)
  Frame     /NestProbe/Root/GroupRot/GB     Rot=0  UIScale=-    absSize=(120,60)
```

Read it twice:

1. **`PA` and `PB` are at the SAME INDENTATION as their own container** — they are flat
   siblings of it under the ScreenGui, not children. They stay `80×40`, `Rot=0`. **The
   container scaled to 1.5× and its contents did not.**
2. **`GA` and `GB` are real descendants** and are `120×60` — exactly `80×1.5` and
   `40×1.5`. **The engine scaled them; no framework code did.** `UIScale` applies to an
   instance *and its descendants*, so one bespoke `LuauUIMotionScale` covers the whole
   subtree for free the moment the subtree is real.

This is the capability hole the user named, measured: **`scale` and `rotation` on a
container are per-node paint today, and reach the container's contents only where a real
parent already exists.** Source of record, `src/client/screen_presentation.luau:289-343`:
*"the paint half of a transform: SCALE and ROTATION reach only the node's own instance
(and whatever is really parented under it), which is why the reference points a
subtree-scaling caller at a `canvasGroup` node."*

Position is the exception and the asymmetry is deliberate — `presentationShift`
(`src/render/presentation_channel.luau:162-184`) sums every ancestor's `x`/`y` **by
walking the path string**, stopping at the nearest real parent. LuauUI hand-computes in
Luau precisely what an engine parent gives for free, and only for the one channel it can.

### 2b. In pixels — the plainest statement of the whole ADR

Two identical blue plates at `Rotation = 25`, each with two yellow boxes. Left: boxes are
flat siblings. Right: boxes are real children.

- **Left (flat):** the plate is rotated; **the yellow boxes sit bolt upright**, axis-aligned,
  visibly detached from the plate they are supposed to be on.
- **Right (nested):** the yellow boxes are rotated with the plate, about the plate's pivot.

### 2c. Group opacity — LuauUI already refuses the incorrect version

The double-darken failure mode named in the brief (*"if LuauUI fades a panel by writing
transparency on every node independently, overlapping children double-darken"*) is
**structurally unreachable in LuauUI today**, and that is a deliberate, documented
refusal rather than luck:

- `opacity` is offered on **`Box` and `ZStack` only**, and declaring it *implies*
  `canvasGroup = true` (ADR-0026 D4; `src/render/renderer.luau:1063-1065`).
- On every other rendered class it is **refused by name** with a message that states the
  rule and the spelling (ADR-0029 D3), pinned across all 21 classes by
  `tests/authored_presentation.spec.luau`.
- So a LuauUI fade is *always* one `CanvasGroup.GroupTransparency` over a real subtree —
  never N independent per-node writes. The correct compositing behaviour is the only one
  the framework will construct.

**ADR-0029 is the precedent that decides this ADR's shape**, and it should be read as
such: it establishes that `opacity` is offerable only on a class *"whose engine instance
can BE a `CanvasGroup`"*, i.e. that the fade capability is downstream of the node being a
**real instance parent**. Nesting is the general form of the thing ADR-0029 licensed
specifically.

---

## 3. Arrange — the second argument, and the headline number

### 3a. Through the real framework: what a container move costs in a flat tree

Surface: `VStack[ Box(reactive height), VStack[ 120 × Box ] ]`, 122 GuiObjects. Changing
the spacer's height moves the second stack and **every one of its 120 descendants**.
Engine writes counted directly with `GetPropertyChangedSignal("Position")` on every
materialised instance; solver work read from `controller.stats()`.

| spacer height | `stats.rectWrites` | `lastArranged` | `lastSkipped` | **engine `Position` writes** | row60 y |
|---|---|---|---|---|---|
| → 30 | **+123** | 124 | **0** | **120** | 208 |
| → 50 | **+123** | 124 | **0** | **120** | 228 |
| → 70 | **+123** | 124 | **0** | **120** | 248 |
| → 90 | **+123** | 124 | **0** | **120** | 268 |

**`skipped = 0` is the important cell.** LuauUI's incremental layout — the shipped
optimisation that skips subtrees whose rect is bit-identical — **cannot help here at
all**, because a container move genuinely changes every descendant's absolute rect. The
one optimisation the codebase already has is structurally defeated by the single most
common layout event there is. In a nested tree this is **one** write and the engine moves
the subtree.

A control that matters: the *first* attempt used `offsetY`, which routes through the
**presentation** channel, and reported `rectWrites +0, arranged=2, skipped=120`. That is
a different channel (it accumulates by path-string walking, §2a) and measuring it would
have understated the layout cost to zero. Recorded so the next person picks the right
lever.

### 3b. Engine-level scaling harness — the control first

Pure engine, no LuauUI. N frames; "move the container" = **N** `Position`+`Size` writes
flat (the shape `applyRect` actually writes) vs **1** `Position` write nested. Min-of-5,
300 iterations per rep, per-move cost.

**A/A control (same arm twice) — before any delta is quoted:**

| arm | N=50 | N=200 | N=800 |
|---|---|---|---|
| flat | **−9.88%** | −0.22% | +0.45% |
| nested | +1.75% | +2.21% | −2.06% |

**A/B, interleaved:**

| N | flat | nested | ratio |
|---|---|---|---|
| 50 | 0.0145 ms | 0.00023 ms | **63×** |
| 200 | 0.0625 ms | 0.00022 ms | **281×** |
| 800 | 0.2556 ms | 0.00022 ms | **1157×** |

Flat is **O(N)** (≈0.32 µs per node, linear across a 16× span). Nested is **O(1)** —
flat 0.00022 ms at every N, which is the cost of one property write. Every delta is
orders of magnitude outside the widest control spread (9.88%).

**What this number is NOT.** It is the **Luau-side** write cost only. The engine must
still recompute every descendant's `AbsolutePosition` in the nested arm — that work moves
from Luau into C++, it does not vanish. The frame-cost instrument was saturated (§0) and
could not measure it. **The honest claim is: the half of `arrange` that Luau pays
collapses from O(N) to O(1). The total frame win is unmeasured in this session and is
owed a Performance Lab run and a device pass.**

---

## 4. Elision — the measurement that argues AGAINST, and the mechanism that rescues it

Surface: 20 rows, each `HStack[ Box, VStack[Box, Box], Spacer, Box ]` = 142 nodes.

| | `creates` | `elided` | **GuiObjects** |
|---|---|---|---|
| elision ON (shipped default) | 142 | **61** | **81** |
| elision OFF | 142 | 0 | **142** |

**Elision removes 43.0% of GuiObjects on this surface. Naively un-eliding every container
so it can be a real parent costs +61 instances, or +75.3%.** That is the number that
argues against this ADR and it is larger than the −34% previously on record.

**But the two are not actually in conflict, and this is the load-bearing structural
finding.** Parenting does not walk the node tree. `hostFor(path)`
(`src/client/screen_presentation.luau:94-104`) is a **longest-path-PREFIX match over a
registry of hosts** (`clipHosts`), and everything else parents to the root:

```lua
-- clip-host parenting: descendants of a clip host live INSIDE it so
-- the engine crops them; everything else stays flat under the root
local host = hostFor(path)
if host ~= nil then ... instance.Parent = host.instance
else instance.Parent = rootHandle.gui end
```
(`src/client/screen_target.luau:1318-1327`)

An unregistered container — elided or merely materialised-but-not-a-host — is therefore
**completely transparent to parenting**. Proven by the live Showcase tree, not by reading:

```
ScrollingFrame /AdaptiveScreen/BodyScroll                          clip=true
  Frame        /AdaptiveScreen/BodyScroll/Body
  TextLabel    /AdaptiveScreen/BodyScroll/Body/Settings/Heading     <- SIBLING of Body
  TextButton   /AdaptiveScreen/BodyScroll/Body/Settings/Volume/Dec  <- also a sibling
```

`Body` is materialised and is *not* a host, so `.../Settings/Heading` parents straight
past it to `BodyScroll`. **Three path segments were skipped.** Nesting is a
**host-registration policy**, not a tree mirror — which is why elision survives a switch
untouched, and why "nest everything" is the wrong reading of the ruling.

---

## 4b. A stale constraint, corrected

ADR-0025 and ADR-0028 both recorded that their mechanism could not be canaried in Studio
because `renderer.luau` exceeded Studio's 200 000-character `Source` limit (ADR-0028 cites
**238 000**). Measured today:

| file | chars | Studio limit |
|---|---|---|
| `src/render/renderer.luau` | **185 633** | 200 000 |
| `src/layout/solver.luau` | **178 598** | 200 000 |

Both are under. Proven the strongest available way rather than by arithmetic: the
renderer's full `Source` was read back **out of the live datamodel** (3974 lines) and the
patched clone was successfully required and used to mount surfaces. **The live canary
those two ADRs recorded as owed is now takeable.**

## 4c. Nesting disables recycling on the hosted node — source-verified

`parkEligible` (`src/client/screen_target.luau:3375-3386`) refuses to park a handle when
any of eight conditions hold, one of which is:

```lua
or clipHosts[path] ~= nil
```

**A registered host cannot be parked, so it cannot be recycled.** Since a virtualised list
row is simultaneously the highest-value move boundary and the case the instance pool was
built for (recycling is ON by default; L-28 added themed recycling), registering rows as
hosts trades one measured win for another. This is unpriced by this session and is the
sharpest open question for the first build step.

## 5. What the flat tree bought, verified from source rather than assumed

Three real things, all still true and none given up by a registration-policy widening:

1. **The render seam takes no parent handle.** `src/render/target_contract.luau` —
   `create(rootHandle, path, class, …)`, six required methods, **none of them a
   `setParent`**. Nesting is expressed entirely inside the adapter.
2. **Elision** (§4) — class-gated (`VStack, HStack, ZStack, Grid, Anchor, Spacer`), and
   explicitly **not** children-gated today (`src/client/screen_target.luau:998-1034`).
3. **Path-string identity.** `Instance.Name = path` verbatim
   (`screen_target.luau:1064-1065`), with `instancesByPath` / `handlesByPath` as the
   lookups — the framework never uses `GetChildren()`/`Name` to find a node, so
   diagnostics, dumps and the flat baseline key on the path string, which nesting does
   not change.

## 6. Ordering, restated — why `Sibling` + nesting is already correct

`syncZOrder` (`screen_target.luau:2694-2716`) is a **depth-first walk over the mounted
node tree** assigning one strictly-increasing counter, with its own comment:

> *"A child's counter is always higher than its parent's, whatever its `zIndex`."*

DFS document order is **exactly** what `ZIndexBehavior.Sibling` expresses natively, and a
`zIndex` lift is already scoped to a parent's sibling set — *"its whole SUBTREE travels
with it"*. So nesting does not change today's paint order for any node; it makes the
engine deliver an order the framework is currently computing by hand.

**What nesting genuinely forecloses** is a node escaping its ancestor's z-slot (§1a). The
framework does not use `ZIndex` for that today — it uses **separate surfaces**: the
presenter raises eight kinds on banded `DisplayOrder`s (`base 10000 / toast 20000 /
dragProxy 30000 / modal 40000`) and `src/controls/row_actions.luau` raises a ninth
directly through `renderer.attach` (ADR-0028). A separate `ScreenGui` is unaffected by
any parent's z-slot. **The escape hatch a popover needs already exists and is already the
one in use.**

The one live symptom of the boundary, in today's *limited* nesting, is already recorded
in the source and is the shape the migration must watch — the focus ring float
(`screen_target.luau:2506-2529`) cannot be parented under a clipped row and is instead
parented into the clip host at topmost z.
