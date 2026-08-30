# World-surface spike — the engine's answers, measured

Acceptance row **WORLD-1**. Run before any adapter exists, because
`src/render/target_contract.luau`'s own words are that these questions are the
deliverable: *"each is something a Studio and physical spike must answer BEFORE an
adapter is written, because guessing at any of them produces an adapter that looks
correct and is not."*

## Session

| | |
|---|---|
| Studio | 0.736.0.7361346 |
| Place | `Facet-Showcase.rbxl`, PlaceId 0, `Facet_Showcase = true` |
| Mode | Play (Client VM), programmatic drive over Studio MCP |
| Viewport | 1441 × 1067 |
| Evidence class | **E2** — a live engine probe. These are Roblox facts, not Facet facts, which is why the place's own source stamp does not gate them. Nothing here is a claim about the retail client; that stays a device row. |

**Instrument proved before any null result was trusted.** A synthetic click on a
`ScreenGui` button at a known position registered `activated=1`, `inputBegan=2`
(`MouseMovement`, `MouseButton1`). Injected mouse coordinates are **gui space** —
inset-subtracted; `GetGuiInset()` read `(0, 58)` and the click landed only at the
inset-subtracted point.

Every measurement below has a **restore** — the control removed and the click repeated
— so a null is attributable to the thing that was changed and not to the weather.

---

## 1. The contract's stated interactivity precondition is WRONG on this engine

`target_contract.FUTURE.surface` says:

> "a SurfaceGui's GuiObjects are input-active only when the SurfaceGui lives under
> PlayerGui with Adornee set to the part; **parented INTO the part it is
> display-only**. A spike that parents it the wrong way measures a surface that can
> never be clicked."

Both topologies were built with an identical button and clicked at their own projected
screen points:

| Topology | `Activated` | `InputBegan` |
|---|---:|---:|
| **A** — `SurfaceGui` under `PlayerGui`, `Adornee` = the part | **1** | 2 |
| **B** — `SurfaceGui` parented **into** the part | **1** | 2 |

**Both are input-active.** Input arrived as `MouseButton1` on each.

`SurfaceGui.Active` is **`true` by default**, unlike `BillboardGui` — which is why
`billboard_target.luau` sets it explicitly and a surface target need not.

**This does not change the design.** The plan's requirement that the surface be
client-owned under `PlayerGui` stands, for a reason the contract's open question does
not mention and which is the better one: a `SurfaceGui` parented into a Workspace part
is **replicated to every player and server-owned**. That is shared UI, which is exactly
what Facet must never build. Topology A is required on **ownership** grounds, not input
grounds — and the adapter's documentation should say so, because a future reader who
tests input and finds topology B works will otherwise conclude the rule is superstition.

### The mistake this spike nearly made, recorded because it is the trap

The first two rounds measured **zero** on both surfaces while a `ClickDetector` on the
same part fired at the same coordinates and `Mouse.Target` named the console. The cause
was `Face`: for an unrotated part, `Enum.NormalId.Front` is the **−Z** face, and the
camera was looking along −Z, so it was seeing **`Back`**. Both surfaces had been painted
on the side of the console facing away from the camera the whole time — rendering
perfectly, measuring perfectly, and unclickable.

Measured, so nobody has to re-derive it:

```
Front   worldNormal=(0,0,-1)   Back    worldNormal=(0,0,1)  <- faces a camera looking along -Z
Left    (-1,0,0)   Right (1,0,0)   Top (0,1,0)   Bottom (0,-1,0)
```

A face error is indistinguishable from "the engine does not support this". The adapter
takes `face` as an **explicit required option with no default**, and the spike scenario
asserts the chosen face actually points at the camera before it measures anything.

---

## 2. Canvas mapping — fixed, linear, and independent of part size

`SizingMode = FixedSize`, `CanvasSize = 400 × 250`, one part resized underneath it:

| Part | `gui.AbsoluteSize` | button `AbsolutePosition` | button `AbsoluteSize` |
|---|---|---|---|
| 8 × 5 studs | 400, 250 | 40, 40 | 200, 80 |
| 4 × 2.5 studs | 400, 250 | 40, 40 | 200, 80 |
| 16 × 10 studs | 400, 250 | 40, 40 | 200, 80 |
| 8 × 2 studs | 400, 250 | 40, 40 | 200, 80 |

**The canvas is a fixed virtual-pixel rectangle, invariant to the part.** Descendant
`AbsolutePosition` and `AbsoluteSize` are **canvas-space pixels** — the same numbers a
`ScreenGui` would report for the same tree.

That is the whole answer to "whether solved rects map linearly at every part size", and
it is the best possible one for this framework: the solver is handed one exact
rectangle, every layout decision behaves as it does on a screen, and a part resize
costs **no re-solve**. The trade-off is aspect ratio — an 8 × 2 part shows a 400 × 250
canvas squashed — which is a fixture's problem, not the adapter's, and is why the
adapter states resolution and expects the part to match it.

(`PixelsPerStud = 50` on an 8 × 5 part also produced 400 × 250, as arithmetic demands.
It is not the shipped policy: it makes the canvas a function of the part, so a designer
resizing a console silently re-lays-out the UI.)

---

## 3. The queryable precondition — a real, silent killer

| | `Activated` |
|---|---:|
| `CanQuery = true` (baseline) | 1 |
| `CanQuery = false` | **0** |
| `CanQuery = true` (restored) | 1 |

And the surface **still renders**: `AbsoluteSize` stayed 400 × 250 throughout.

So a non-queryable adornee produces a terminal that looks completely correct and cannot
be touched, with no error anywhere. The adapter **requires** it and says so at
construction; the Studio matrix carries it as a negative control.

---

## 4. Occlusion, and why `AlwaysOnTop = false` is the policy

A wall placed between the camera and the console:

| | `Activated` |
|---|---:|
| Wall present, `AlwaysOnTop = false` | **0** |
| Wall present, `AlwaysOnTop = true` | **1** |
| Wall removed, `AlwaysOnTop = false` | 1 |

**With `AlwaysOnTop = true` a player operates the terminal through a wall** — not just
sees it, but *uses* it. The plan's "`AlwaysOnTop = false` unless evidence requires a
different value" now has evidence pointing the other way, and it is the correct
default rather than a preference.

A live surface also **sinks** the world input beneath it: with the surfaces inert the
part's `ClickDetector` fired (`clicked=1`); once the surfaces became active at the same
coordinates the detector fired **0** times. A walk-up prompt and a live terminal on the
same part therefore cannot both be listening in the same region, which is a real
constraint on the fixture's layout.

---

## 5. Adornee lifetime — the reference outlives the instance

| Event | What the surface reports |
|---|---|
| `Adornee = nil` | no error; `AbsoluteSize` unchanged at the canvas size; `Enabled` still true |
| Adornee **destroyed** | `gui.Adornee` **still names the destroyed part**; `AbsoluteSize` unchanged; `Parent` still `PlayerGui` |

**A destroyed or streamed-out adornee is invisible through the `Adornee` property
alone.** The adapter cannot detect it by reading `Adornee`; it must watch the
instance's own lifetime (`Destroying` / `AncestryChanged`, or an
`IsDescendantOf(workspace)` check) and resign the surface itself.

That is a concrete adapter requirement this spike exists to have found, and it is one
of the eight exit paths the terminal has to survive.

---

## 6. Clipping and the scroll host — same as a screen

- A 600 px-wide child inside a 400 px canvas reports `AbsoluteSize = 600, 60`.
  **Clipping is a paint fact, not a geometry one** — exactly as on a `ScreenGui`, so
  the solver's overflow diagnostics keep meaning what they mean.
- A `ScrollingFrame` on the surface accepted a scripted `CanvasPosition` write
  (`0, 120` on a 200 × 600 canvas in a 200 × 100 window). The native scroll host is
  live on a world surface.

## 7. Text measurement — target-independent by construction

`TextService:GetTextBoundsAsync` answered `327 × 24` for a 24 px string bounded at
380 px. `TextService` takes no target and knows nothing about where the text will land,
so there is no per-target text question to answer — which also means
`text_premeasure.warmUp()` serves a surface target exactly as it serves the screen.

*(The repository's own standing caution still applies and is not weakened by this: text
bounds are wrong-but-stable during the first moments of a session, which is why the
shipped adapter re-reads every batch 1.5 s later.)*

---

## 8. Still open after this session

**StyleSheet cascade — NOT ANSWERED.** Two attempts to apply a hand-built `StyleRule`
through a `StyleLink` failed to apply on the **`ScreenGui` control as well**, so the
setup was wrong and a shared null is not evidence of sameness. Recorded as open rather
than closed on a result that proves nothing. It is answered properly with Facet's own
`src/client/native_style.luau` — the mechanism that will actually be used — once the
adapter can mount a tree on a surface.

**Focus-ring legibility at distance and angle** (E3/E5), **cost per frame while the
part is visible** (E3, against the same showcase at idle), and **retail-client input**
(E4) all remain, as they must: none is a headless or emulated question.

---

## 9. What this changes in the plan

1. `target_contract.FUTURE.surface`'s interactivity open question is **replaced with a
   measured answer**, and the reason for the PlayerGui topology is restated as
   ownership rather than input.
2. `face` becomes an **explicit required adapter option**, and the spike's face-versus-
   camera assertion becomes part of the scenario, because a face error is
   indistinguishable from an unsupported engine.
3. `AlwaysOnTop = false` is kept **with evidence**, and the input-sinking behaviour is
   written into the fixture's constraints.
4. The adapter must **watch the adornee's lifetime directly**; reading `Adornee` cannot
   see a destroyed part.
5. The canvas policy is confirmed implementable exactly as the plan describes: a fixed
   virtual-pixel rectangle, fed to the solver once.
