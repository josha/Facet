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
