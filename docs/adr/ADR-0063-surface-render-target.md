# ADR-0063 — The world surface ships as a render target, and two of its declared premises were wrong

**Date:** 2026-08-29
**Status:** Accepted
**Supersedes:** the "not implemented" half of ADR-0021 §4 (the seam itself stands)
**Stage:** `example-games-and-standalones` (roadmap Step 13.5)

## Context

Facet has had two render targets since ADR-0009: `screen_target` (a `ScreenGui`) and
`billboard_target` (a `BillboardGui`). A third — flat UI on a world surface, on a part
a player can walk up to and use — has been **declared and deliberately unbuilt** since
ADR-0003, with its unanswered questions written into
`target_contract.FUTURE.surface` so that adding it later would be a new adapter rather
than a change to every control.

That declaration said, in its own words, that the questions were the deliverable:
*"each is something a Studio and physical spike must answer BEFORE an adapter is
written, because guessing at any of them produces an adapter that looks correct and is
not."*

Step 13.5 needs one: an Outpost Power Terminal the player uses to allocate a limited
power budget, in the showcase and as a standalone place. So the spike was run.

## Decision

**Ship `src/client/surface_target.luau`** as the thirteenth blessed client entry point:
a thin root swap over `screen_target`, exactly as `billboard_target` is, so everything
below the root — style, bindings, states, z-order, recycling, teardown — is the same
flat instance renderer and the three targets cannot drift.

No second renderer. No `SurfaceGui` branch inside any control. Nothing in `src/render/`
changes except the declaration this ADR replaces.

## What the spike measured, and what it overturned

Studio 0.736.0.7361346, Play mode, instrument proved before any null was trusted, every
control restored. Full record:
`artifacts/example-games-and-standalones/spike/world-surface.md`.

### Two premises in our own contract were wrong

**1. "Parented INTO the part it is display-only."** The declaration warned that *"a
spike that parents it the wrong way measures a surface that can never be clicked"*.
Measured: **both topologies take input** — `activated=1`, `inputBegan=2` on each.

The `PlayerGui` + `Adornee` requirement stands anyway, and the reason is better than the
one we had: a `SurfaceGui` inside a Workspace part is **replicated to every player** and
server-owned. That is shared UI, which Facet does not build. **It is an ownership rule,
not an input rule**, and the adapter says so — because a future reader who tests input,
finds the other topology works, and concludes the rule is superstition would be
reasoning correctly from a wrong premise.

**2. `AlwaysOnTop` was to be `false` "unless evidence requires a different value".** The
evidence points the other way, hard. With a wall between the camera and the console:
activation read **0** with `AlwaysOnTop = false`, **1** with it `true`, and **1** with
the wall removed. With it true a player does not merely *see* the terminal through
geometry — they **operate** it.

So it is pinned `false` and **is not an option**. A consumer who needs the other value
brings evidence and an ADR, not a flag.

### What else the spike settled

- **The canvas is a fixed virtual-pixel rectangle, invariant to the part.** With
  `SizingMode = FixedSize`, one `CanvasSize` held while the part was resized 8×5 → 4×2.5
  → 16×10 → 8×2 studs reported `400, 250` every time, and descendants read in canvas
  pixels exactly as on a screen. The solver is handed one exact rect; a part resize
  costs no re-solve. `PixelsPerStud` is deliberately not offered: it makes the canvas a
  function of the part, so resizing a console silently re-lays-out the UI.
- **`CanQuery = false` renders perfectly and receives nothing.** Activation went
  1 → 0 → 1 as the flag was cleared and restored. Asserted at construction.
- **A live surface sinks the world input under it.** A `ClickDetector` on the same part
  fired while the surfaces were inert and **zero** times once they were live at the same
  coordinates. A walk-up prompt and a live terminal cannot both listen in one region.
- **A destroyed adornee is invisible through `.Adornee`** — the property still names the
  destroyed part with the canvas size unchanged. The adapter watches the instance's own
  lifetime and reports through `onAdorneeLost`.
- Clipping, the scroll host's canvas writes, and `TextService` text bounds all behaved
  as they do on a screen.

### The trap, recorded because it nearly became a false conclusion

The first two rounds measured **zero** on both surfaces while a `ClickDetector` on the
same part fired at the same coordinates. The cause was `Face`: for an unrotated part
`Enum.NormalId.Front` is the **−Z** face, and the camera was looking along −Z, so it was
seeing `Back`. Both surfaces had been painted on the side facing away from the camera —
rendering, measuring, and unclickable.

A face error is indistinguishable from "the engine does not support this". So **`face`
is a required option with no default**, and its assertion message says why.

## What is withheld, and why each

The contract's degrade mechanism is to **delete** the optional method, so
`target_contract.check` reports it absent and the renderer degrades by name — rather
than a screen-space capability appearing to work while its coordinate space is wrong.

| Withheld | Because |
|---|---|
| `setPointerHandlers`, `setTouchGestureHandlers` | Activation reaches a surface control; what coordinates a *capture* carries is unmeasured. On a `SurfaceGui` the `ScreenGui` inset correction is not merely wrong, it is the wrong **kind** of correction — the position is screen space and the solver's rects are canvas space. |
| `stageHost` | A `ViewportFrame` rendering its own scene inside a canvas that is itself a world surface is a composition nobody has measured, at any distance. |
| `foreignHost` | A caller's own `GuiObject` in that canvas is the same unmeasured question (ADR-0034). |
| `nativeStyle = false` | **The one question the spike could not close.** Two attempts to apply a hand-built `StyleRule` through a `StyleLink` failed to apply on the *screen* control as well, so the setup was wrong and a shared null proves nothing about the cascade. It closes when `native_style` itself is driven on a surface. |
| `forceScrollFallback = true` | A scripted `CanvasPosition` write took, but a wheel, a drag and a touch flick are what a consumer gets, and none has been driven. |

## Consequences

- `target_contract.FUTURE.surface` keeps its questions **and stays where it is**, now
  split into `answered` and `openQuestions`. Where the next implementer looks for the
  questions is where the answers belong, and two of them corrected the declaration's own
  premises — which is the best available argument for having written them down.
- The blessed client list goes from twelve to **thirteen**
  (`tools/lune/check_boundary.luau` is the authority; the constitution and api.md are
  reconciled to it).
- `presentationSpace = "world"` gains its first real consumer. Before this the fact
  existed, clamped unknown values to `"screen"`, and nothing in the library read it.
- `tests/spatial.spec.luau`'s XP-D3 block changes from "declared, not implemented" to
  "declared **and** shipped", and gains a case asserting that **every still-open question
  has a matching capability the adapter withholds** — because an open question with the
  capability quietly shipped anyway is worse than no declaration at all: it reads as
  caution while the unproven path is live.
- **No VR claim is created or implied.** `docs/extending/new-platform-mode.md`'s gate
  table is unchanged in substance: every spatial row stays `PENDING_PHYSICAL`. A flat
  world surface driven by an ordinary pointer answers none of them.

## Rejected alternatives

**A second renderer for world space.** The whole point of the target contract is that
where a tree materializes is an adapter's business and nothing else's. A second renderer
would have to be kept in step with the first forever, and ADR-0009 already proved the
root-swap shape works.

**`SizingMode = PixelsPerStud`.** It makes the canvas a function of the part, so a
designer nudging a console's size re-lays-out the UI on it. The fixed canvas trades
aspect-ratio flexibility for a solver input that never moves, which is the better trade
for a framework whose layout is measured.

**Offering `alwaysOnTop` as an option, defaulted false.** Tempting, and wrong: the
measurement shows the true value is not a cosmetic preference but a hole in the world's
own occlusion. A flag invites it to be set by someone who has not measured what it does.

**Deleting `FUTURE.surface` now that it shipped.** The questions are the artefact. A
future reader of an adapter wants to know what was asked, what was answered, and what is
still open — and deleting the record would leave only the answers, which is the half you
can reconstruct from the code.
