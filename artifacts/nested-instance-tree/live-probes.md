# Nested instance tree — live probes (this round)

Tier discipline: **headless Lune is a regression signal only, Studio is the real
engine, a physical device is the only device claim.** Everything on this page is
tier **Studio**, taken in the `LuauUI-Showcase` session over the MCP bridge unless
a row says otherwise.

## 0. The staleness gate, run before anything was trusted

`require` is cached per datamodel, so reading the right source does not prove you
ran it. Before any measurement below, the datamodel was asked what it actually
carries:

| module | Source length | carries |
|---|---|---|
| `ReplicatedStorage.LuauUI.render.renderer` | 198,700 | `require("./instance_boundary")` ✓ |
| `ReplicatedStorage.LuauUI.render.instance_boundary` | 6,430 | the D4 sentence ✓, `kindOf` ✓ |
| `ReplicatedStorage.LuauUI.client.screen_presentation` | 25,684 | `handle.lastWriteX ~= px` ✓, `registerHost` ✓ |

`instance_boundary.luau` did not exist twenty minutes before this reading, so the
sync is live and current rather than a place file from last week.

## 1. A PLAIN FRAME CARRIES BOTH TERMS — Decision 4 costs one Frame, not a buffer

**The question ADR-0032 left open.** Its Decision 4 measurement used
`canvasGroup = true`, because a group was the only way to get nesting at the time.
That left "does a plain `Frame` parent do it too" unanswered, and the answer decides
whether an authored `rotation` on a container costs one extra instance or an
offscreen render buffer on every one.

Three arms, one call. Each parent is `200x100`; each child is an `80x40` `Frame`
parented inside it. The transformed arms carry `Rotation = 30` and a `UIScale` of
`1.5` **on the parent only**.

| arm | parent Abs | parent rot | **child Abs** | **child AbsoluteRotation** | child's own `Rotation` | child has a `UIScale`? |
|---|---|---|---|---|---|---|
| plain `Frame`, no transform (control) | 200x100 | 0.0 | **80x40** | **0.0** | 0.0 | no |
| **plain `Frame`** parent | 300x150 | 30.0 | **120x60** | **30.0** | 0.0 | no |
| **`CanvasGroup`** parent | 300x150 | 30.0 | **120x60** | **30.0** | 0.0 | no |

**A plain `Frame` carries `Rotation` and `UIScale` to its descendants, identically
to a `CanvasGroup`.** 80x40 becomes 120x60 — exactly 1.5x — and the child's
`AbsoluteRotation` is 30 in both arms. So the implementation choice is confirmed
rather than assumed: `scale`/`rotation` take a plain `Frame`, and only `opacity`
buys the group, because `GroupTransparency` is the only thing a group adds.

**This also removes the last reason to prefer a group anywhere.** ADR-0032 Decision 3
already refuted the idea that a `CanvasGroup` is an ordering boundary (pixel-level,
last round). This shows it is not a composition boundary either. Frame nesting and
`CanvasGroup` nesting differ in exactly one thing: the buffer, and therefore
`GroupTransparency`.

## 2. Decision 5 CONFIRMED LIVE: an engine-composed effect is not a property write

The right-hand two columns above are the pin ADR-0032 Decision 5 asked for and could
not take at decision time. In both transformed arms the child **visibly rotated and
measurably scaled** while:

- its own `Rotation` stayed **0.0**, and
- it grew **no `UIScale` of its own**.

So an inherited composition is a *rendering* fact, not a claim on the descendant's
property, and the authority manifest is unchanged — one writer per engine property
per class still holds, because there was no second write at all. That was the one
question in this ADR that could have forced a manifest change; it does not.

*Probe hygiene: the probe mounted one `ScreenGui` under `CoreGui`, destroyed it, and
verified its absence in the same call ("cleanup: verified absent").*

## 3. END-TO-END through the real framework and the real adapter

The probe above measures the engine. This one measures LuauUI: a real `UI.Screen`
mounted through `LuauUI.mount` + `renderer.attach` onto a real `screen_target`, with
one container carrying `rotation = 30, scale = 1.5` around an 80x40 `UI.Box`, and a
second, ordinary container beside it as the control.

**Clone-and-require**, because `require` is cached per datamodel: this session may
already hold a renderer loaded from older source, and reading the right source does
not prove you ran it. A cloned `ModuleScript` is a new identity, so it and every
relative require beneath it load fresh. (`VERSION = 0.9.0` read back off the clone.)

| path | class | **Parent** | Abs | **AbsRot** | own `Rotation` | own `UIScale` |
|---|---|---|---|---|---|---|
| `/Probe/Turned` | **Frame** | `LuauUI_Probe` (root) | 120x60 | 30.0 | 30.0 | yes |
| `/Probe/Turned/Content` | Frame | **`/Probe/Turned`** | **120x60** | **30.0** | **0.0** | **no** |
| `/Probe/Plain` | — | **NO INSTANCE (elided)** | — | — | — | — |
| `/Probe/Plain/Inner` | Frame | `LuauUI_Probe` (root) | 80x40 | 0.0 | 0.0 | no |

Five things at once, and every one of them is a decision this round rests on:

1. **The container is a plain `Frame`.** Not a `CanvasGroup`, so no offscreen buffer
   was spent to get composition (§1 says none is needed).
2. **Its content is genuinely re-parented inside it** — `Parent = /Probe/Turned`,
   not the root. That is the delivery mechanism the headless suite can assert and
   the engine half it cannot.
3. **The engine composed both terms**: the content is `120x60` (exactly 1.5x its
   authored `80x40`) at `AbsoluteRotation = 30`. Before this round it would have been
   `80x40` at `0` — the container detaching from its own contents.
4. **Decision 5 again, in production shape**: the content's own `Rotation` is `0.0`
   and it has no `UIScale`. Nothing wrote to the descendant.
5. **ELISION SURVIVED, which is the number this round is most likely to give back.**
   `/Probe/Plain` is an ordinary container with children and no boundary reason, and
   it has **no instance at all** — still elided, exactly as before. Its child is
   still flat under the root. Decision 2's "register only where nesting pays" is
   working on a live surface, not just in the census.

*Probe hygiene: the clone was destroyed and its absence verified in the same call;
the adapter's own `ScreenGui` was torn down with `controller.dispose()`.*

## 4. THE ARRANGE MEASUREMENT — 241 engine Position writes become 1

**Instrument:** `GetPropertyChangedSignal("Position")` on all 120 descendants of a
`ScrollView`, plus the ScrollView itself. It fires only on a real VALUE change, which
is what makes it the right instrument here: it cannot be fooled by a redundant write
and it cannot miss a real move.

**Workload:** a 20-row list (each row 6 fixed-height `UI.Box` cells, 120 leaf nodes)
inside a `UI.ScrollView`, with a header above it whose height goes `20 -> 60`. That is
the commonest layout event there is — something above a list grows — and it is the one
ADR-0032 says incremental layout is "structurally defeated by".

**A/A control, stated before any delta:** the measurement was run twice per arm and
both arms are exact integers that repeated identically. **Control spread: 0.** This is
a count of discrete engine events, not a timing, so it has no variance to quote — which
is precisely why it was chosen over a clock for this claim.

| | descendant `Position` CHANGES | of which a WRONG value | host's own write |
|---|---|---|---|
| **before** (ordering defect present) | **240** | **120** | 1 |
| **after** (document order + deferred re-base) | **0** | **0** | 1 |

**241 -> 1.** And the middle column is the half that is not about performance: before
the fix, every one of the 120 descendants was written once to a WRONG position and once
to the right one, so for the moment between them the entire subtree is drawn displaced.
A frame landing in that window shows it jump. That is now zero as well.

**The sequence, before, recorded on one cell** — this is what the two writes were:

```
BEFORE: cell.Position = {0,0},{0,20}   list.Position = {0,0},{0,20}
  1. cell -> {0,0},{0,60}      WRONG: new window rect against the host's OLD origin
  2. LIST -> {0,0},{0,60}      the host finally moves, and its entry origin updates
  3. cell -> {0,0},{0,20}      corrected, when the host re-bases its own children
AFTER:  cell.Position = {0,0},{0,20}   list.Position = {0,0},{0,60}
```

The cell ends where it started, which is exactly what "a `GuiObject.Position` is
parent-relative" predicts. The old path paid 240 writes to arrive at no change.

**Why the minimal-write contract alone did not deliver this.** It was landed first and
measured zero improvement on this workload, which was the finding that led here: the
two writes were two DIFFERENT values, so there was nothing for a write skip to skip.
The cause was upstream — the renderer applied a solve's rects by iterating a hash, and
the adapter compensated with an inline child re-base. Both had to change, and the skip
is what makes the corrected path cost nothing rather than N.

**Tier: Studio.** This is an engine claim and it is measured on the engine. It is NOT a
frame-time claim: what is counted here is engine property writes, not milliseconds, and
the engine's own C++ descendant walk is still unmeasured — ADR-0032's standing risk. A
device pass with the MicroProfiler is still owed and is the only thing that can turn
this into a frame number.

## 5. THE SHOWCASE DEMO, DRIVEN LIVE — the capability and its control, side by side

`examples/gallery/scenarios/nested_compositing.luau` mounted through the real
framework and real adapter, and its `turned` driver set from `false` to `true`.
Two halves: a container that CARRIES (authored `rotation`/`scale` on a container
holding a plate and a corner marker) and one that is ALONE (the identical marker
given the same terms as a bare leaf, beside a static plate — the pre-ADR-0032
behaviour, reproduced on purpose as the control).

| | at rest | turned (30°, 1.5x) | own `Rotation` | own `UIScale` |
|---|---|---|---|---|
| **carried** container | 100x70 | 150x105, AbsRot **30** | 30 | yes |
| **carried** plate | 70x40 | **105x60, AbsRot 30** | **0** | **no** |
| **carried** marker | 20x20 | **30x30, AbsRot 30** | **0** | **no** |
| **alone** marker | 20x20 | 30x30, AbsRot 30 | **30** | **yes** |
| **alone** plate | 70x40 | **70x40, AbsRot 0.0** | 0 | no |

Read the last two rows together: the alone marker rotates and scales ITSELF, and
the plate it belongs beside **does not move at all**. That is the defect ADR-0032
Decision 4 describes — "a container visibly detaching from its own contents" —
reproduced deliberately, next to the fixed case, on the same surface, driven by the
same two signals.

And the carried rows are Decision 5 again, in the shape a reader will actually meet
it: both descendants are at `AbsoluteRotation` 30 and exactly 1.5x their authored
size, with their own `Rotation` at `0` and no `UIScale` of their own. The engine did
all of it.

**THE GROUP-OPACITY HALF, structurally**, read off the live tree at the default fade:

    /Opacity/Panels/One/OneGroup          CanvasGroup  GroupTransparency=0.600  children=2
    /Opacity/Panels/Two/TwoGroups/Back    CanvasGroup  GroupTransparency=0.600  children=0
    /Opacity/Panels/Two/TwoGroups/Front   CanvasGroup  GroupTransparency=0.600  children=0

One group holding BOTH plates against two groups holding one each, at the same
transparency — which is the A/B that produces double-darkening on the right and not
on the left.

**WHAT IS NOT HERE, AND WHY.** A pixel capture. `screen_capture` over the MCP bridge
returns the 3-D viewport only; a `CoreGui` `ScreenGui` is not in it, so the
before/after image pair the brief asks for needs a human with a screenshot key. The
numbers above are the stronger witness for the composition claim in any case — this
project's own rule is that "a screenshot of a thing you asked to be true" is not a
witness, and `AbsoluteRotation` read back off the descendant is.

*Probe hygiene: every surface and every clone this session mounted was destroyed and
`ReplicatedStorage` verified back to its four real folders in the same call.*
