# D7 baseline — the HUD losing information, measured live

> **CORRECTION, 2026-08-16, after D7 executed.** One claim below is WRONG and is left in
> place rather than edited away, because the mistake is instructive. This document asserts
> that `Round 3 · Capture @(416,-37)` is "painted entirely above the top of the viewport"
> and calls it a fourth failure class. **It is not.** A LuauUI `ScreenGui` renders with
> `IgnoreGuiInset = true`, so `AbsolutePosition` is reported **inset-subtracted**: window
> y 21 reads back as 21 − 58 = −37. The node is on screen.
>
> D7 refuted it three ways, two of them from this document's own numbers: the x centres
> agree exactly at 456.5, and three separate hidden nodes all report y = −58 — the origin
> proving its own offset. The third was live: `/HudScreen/UrlBarWhen`, sitting at window
> y 0, reports `(0, −58)`.
>
> **The lesson is about the instrument, not the HUD.** I read `AbsolutePosition` as window
> space and it is not; a negative y here means "near the top", not "off the top". Every
> other measurement in this file is unaffected — the `Visible = false` readings are direct,
> and finding 1 (the overflow affordance being unreachable) held up and turned out to be
> *worse* than stated. See D7's evidence for the regression that pins the inset rule.

Frozen before any D7 edit, per the execution contract §6.1 ("freeze a baseline fixture,
trace, and capture where an existing behaviour is being preserved or matched"). This is
the *after* half of the brief's `hud-a/b/c` screenshots: the same failure with numbers on
it, so the repair has something falsifiable to be compared against.

## Studio preflight

| | |
|---|---|
| Studio version | `0.734.0.7340915` |
| Place | `LuauUI-Showcase.rbxl` (Rojo `examples/showcase.project.json`) |
| Mode | Play (client DataModel) |
| Viewport | **749 × 380** — a wide, short offer, the shape a landscape phone loses |
| Fixture | `hud` (`examples/gallery/scenarios/hud.luau`), reached with `LuauUIShowcaseAPI.showNext` |
| Mount confirmed | `{"mounted":"hud","current":"hud","ok":true}` — **`mounted`**, not `current`, per `b377fe9` |
| Screen | `LuauUI_HudScreen`, DisplayOrder 12000, 150 descendants |

## State A — URL bar CLOSED

Everything the rank ladder promises is on screen: the three Beginner tasks with their
rewards, health `84`, the kill feed, the scores `12`/`9`, the clock `2:14`, the FPS
readout, the weapon pocket. The stepped-down alternates are built but hidden
(`Tasks 1/3` at `0×29 vis=false`, `R3` at `0×15 vis=false`), which is the ladder working
exactly as designed.

**One thing is already wrong here**, and it is not in the brief's list of three:

```
Round 3 · Capture    @(416,-37) 81x15  vis=true
```

`Visible = true`, painted **entirely above the top of the viewport** — `y + h = -22`, and
the viewport starts at 0. It is inside the topbar strip
(`…/Hud/Strip/StripRow/StripFree/StripChip/then/StripFit/Objective/…`). Nothing elided it
and nothing dropped it; the resolver believes it is showing. This is a **fourth** failure
class beside the brief's three, and the worst-behaved of them: elision at least *knows*
it happened.

## State B — URL bar OPEN (the `hud-c` case), same 749 × 380 viewport

Driven by an injected click on `…/HudScreen/Drivers/UrlBar`.

**Gone — `Visible = false`, no recovery route of any kind:**

| What | Evidence |
|---|---|
| All three Beginner tasks and their rewards | `Win a round` `0×15`, `+50` `12×19`, `Land 25 hits`, `+120`, `Open a crate`, `+300` — all `vis=false` |
| The `Tasks 1/3` chip — the *stepped-down* form | `@(18,-54) 0×29 vis=false`. Even the fallback is gone, and it was never a Button anyway |
| Health | `84` `@(20,-54) 19×22 vis=false` |
| Kill feed | `Ravi eliminated Mo` `@(8,-58) **0×0**` |
| The whole weapon rail | `Rifle` `7×15`, `24/90` `3×17`, `Pistol`, `7/21`, `Knife`, `--` — all `vis=false`, and note the widths: 7px and 3px, painted at a size nobody measured |
| The `…` overflow button | `@(8,138) 36×36 **vis=false**` |
| The `v` pocket button | `@(640,181) 56×56 vis=false` |

**Still painted outside the viewport:** `Round 3 · Capture @(416,-37)`.

**Survives:** the scores `12`/`9`, the clock `2:14`, `60 FPS · 42 ms`, `Ranger rifle`, the
two driver toggles, and `example.com/play`.

## The two findings that matter

1. **The recovery route is itself droppable.** The `…` button — the one affordance that
   could host an overflow sink — is `vis=false` in exactly the state that needs it. D7.3
   says "rank-1 regions never drop, so a host always exists"; in this fixture the host
   does not exist, because the affordance was never rank-1. Whatever D7 builds has to fix
   the fixture's ranks as well as add the mechanism, or the sink is unreachable precisely
   when it is needed.

2. **`60 FPS · 42 ms` outranks the entire scoreboard, the tasks, the health bar and the
   kill feed**, and the ladder is doing what it was told: `fps` sits above `tasks` in
   `"first to give way last: feed, tasks, fps, weapon, health, rail, actions, clock,
   buttons"`. This is D7.4's re-rank, confirmed against a live screen rather than argued.

## What this baseline does NOT claim

- One viewport, one orientation, one device profile. The full device matrix sweep is
  NM-7.7 and has not run.
- The injected click arrives as `Touch`, not `MouseButton1` — it proves the downstream
  action path only, never native arbitration.
- Nothing here says the *repair* works. It says precisely what "works" will have to mean.
