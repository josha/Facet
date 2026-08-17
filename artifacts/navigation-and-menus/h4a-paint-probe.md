# NM-H4a — the director's sequence, reproduced nowhere, instrumented on the phone

**2026-08-16.** The director, on a real phone, on a current build: *"Portrait. Tap the
control. Close it. Landscape. URL bar on then off again. Portrait. URL bar on and off
then landscape. Boom."* A large contiguous set of `hud` nodes stops painting and does
not come back (`h.jpeg`; screen recording `20529c3b-ScreenRecording_08162026_200329_1.mp4`).

This document records what was driven, what it proved, and why an on-screen instrument
ships instead of a fix.

---

## 1. The step every previous attempt missed — and it still did not reproduce

The prior lane ran 288 headless replays, 144 ordered viewport pairs, 36 live Studio
combinations and a device-emulator rotation, and **never opened and closed the ··· overflow
sink**. That step was added and the whole sequence driven again, in both instruments.

| Instrument | What was driven | Divergence against a fresh mount |
|---|---|---|
| Headless (`fake_target`) | sink open + close, then **two** full orientation/URL-bar cycles, portrait 393x852 ↔ landscape 852x393, insets arriving a frame **after** the viewport | **0** nodes, painted flag and rect |
| Headless, degenerate rotation | the same, routed through a 1x1 intermediate viewport (the known first-frame shape) | **0** |
| **Live Studio, the real Roblox adapter** (`LuauUI-Showcase.rbxl`, scenario runner, `hud`) | the same sequence through `setEnv`, viewport-only | **0** across 100 GuiObjects |
| **Live Studio**, full rotation | the same, with per-orientation `coreSafeInsets` / `deviceSafeInsets` / `topbarInset` and async fact arrival | **0** across 100 GuiObjects |

The Studio runs are the ones that matter, because the headless target is not the thing that
is broken: elision, recycling, ZIndex sync, Path2D holders and the StyleSheet paint claims
all live in `src/client/screen_target.luau`, and no Lune suite touches any of them. Driving
the real adapter and still diverging by zero is the finding, not a null result.

## 2. The signature is BELOW the resolution, and that is now proved rather than inferred

`Rounds` has **one form**, declares no `mayDrop`, sets `recover = "none"` and is rank 1.
**The composition cannot stop showing it at any viewport.** It is absent in the
photograph anyway.

The same reading kills the other candidate readings:

- It is not the ladder. Every zone that is missing in `h.jpeg` is either undroppable
  (`Rounds`, `Strip` — reserved while riding) or would take the whole HUD's remaining zones
  with it, and `Actions` in the photo is in its *compact* form, which is a legal rung.
- It is not a stale resolution. The prior lane established that `src/layout/composition.luau`
  holds no mutable module state and the resolution cache dies with the solve; both
  instruments above re-confirm it by diverging by zero on `arrangement`, `forms`,
  `dropped` and `elided` at every step of the sequence.
- The unpainted run cuts **inside** one `HStack`: `ScoreHome` is gone and `ScoreAway`,
  its sibling, is painted. No lane, no rank and no form boundary falls there. A
  document-order walk does.

**A live landscape tree was read back out of Studio at 852x393** (the photograph's own
viewport, 1180x2556 at 3x) and every one of those nodes paints: `Rounds/RoundStrip/R1..R3`
at 59,-12, `Tasks/TasksFull/Plate` 146x115, `Health/HealthPod/Plate`, `Feed/FeedLine`,
`ScoreHome/Plate`, the ring, `Rail/W1c`, `Readout`, three action discs, `Weapon`. That
dump is what the probe's watch list was written from, which is why none of its paths is a
bare stack — the real adapter elides those and they have no Instance at all.

## 3. What ships: a paint probe on a surface of its own

`examples/gallery/scenarios/hud.luau`. Fourteen rows in document order, spanning the
boundary the failure stops at, each naming every form the ladder may legally choose for it.
Per row, two verdicts:

- **model** — `controller.screenRectOf` plus an ancestor walk over `controller.hiddenRoots()`:
  what the framework *believes* it is painting.
- **engine** — the host's `ctx.geometry` seam, now answering `visible` off the live
  `GuiObject`, read for the row's paths **and every ancestor**: what actually painted.

A row is LOST only when the model says a form should be painting and the engine says none
of them is. That is a defect by construction and never fires on a legal step-down, which is
what keeps the plate quiet in portrait where the ladder elides three zones by design.

**It latches itself.** The failure is transient and the tester's next tap may clear it, so
the probe records the frame the disagreement appears on and stops sampling. The `Freeze` /
`Live again` button releases and re-arms a capture rather than taking one — the capture has
already happened by the time a human could reach for it.

**It mounts on its own surface** (`presenter.present`, `responder = "passive"`,
`setDisplayOrder(SURFACE_LAYER.toast + 100)`), so the HUD's own visibility walk cannot
reach it: separate mount, separate render controller, separate solve, separate walk. The
photograph corroborates the reasoning — the showcase chrome, a different surface, painted
perfectly while the HUD did not. `tests/hud_paint_probe.spec.luau` proves it by hiding the
HUD's screen root and re-reading the plate.

What a reviewer reads off it, in four short lines on a phone:

```
Paint probe · 852x393 · solve 61 · HELD
7 of 14 NOT PAINTED
Objective · Rounds · Tasks · Health · Feed · ScoreHome · TimerPlate
first painted: TimerRing
hidden under: /HudScreen/Hud
```

`hidden under` is the line worth the whole instrument: seven rows lost under **one** node is
a different defect from seven rows each hidden on their own, and no photograph can tell
those apart.

## 4. Two framework gaps, reported rather than worked around

1. **There is no per-node paint verdict on the public controller.** The renderer maintains
   exactly the bit this needs — `lastVisible` (`src/render/renderer.luau:829`), and the
   inherited `solverHidden` beside it — and neither has an accessor; `hiddenRoots()` answers
   the ROOT set and `coverRect()` only aggregates. There is also **no counter for the
   visibility walk**: `pushVisible` increments nothing, so "the walk ran to completion" is
   not observable, and `stats` is where such a counter belongs. Every consumer that wants
   this today must reconstruct it from an ancestor walk plus an engine read, which is
   exactly what this fixture does.

2. **There is no cross-surface focus traversal.** Measured headless in both responder
   modes: a second base surface's focusables are in NEITHER surface's Tab ring. That is why
   the probe's `Freeze` switch is on the probe's plate with a scripted route beside it
   (`steps.holdProbe` / `armProbe`) rather than in the HUD's driver row — and it cannot come
   back to that row either, because the HUD's Screen has **under 8px of headroom** at
   320x640 with `preferredTextOffset = +14`: a third labelled `UI.Toggle` overflows it by
   17-31px under all four ornate packages, a 36px circle by 6-8px (a circle sets its line's
   height 8px above a Toggle's 28px floor), and a 28px circle is smaller than an ornate
   package's own control chrome (Pixel Quest spends 16+16 of contentInset and the content
   box collapses to 0px). All three were measured by the always-on sweep, in that order.
   `tests/hud_paint_probe.spec.luau` pins the traversal gap so the day it closes, the switch
   moves.

## 5. What is now guarded

`tests/hud_paint_probe.spec.luau`, 10 cases:

- the director's full sequence — sink open **and close**, then two orientation cycles —
  asserted against the **painted tree**, not the resolution;
- the round strip is still on screen at the end, because no ladder may ever remove it;
- the probe stays quiet through the whole sequence and watches more than 8 rows;
- with the engine side forced to disagree, it names the lost rows in document order, the
  first painted row after them, and the node they are lost under;
- a latched probe holds its capture while the failure clears underneath it;
- a legal step-down is not a loss;
- it degrades honestly on a host with no engine read;
- its plate survives the HUD's root being hidden, files no cross-surface overlap finding,
  and is retired with the fixture;
- a second base surface's control is in neither traversal ring.

Three mutations were run against the fixture and each was seen to fail: making the probe
ignore the engine side (2 red), removing the latch (2 red), and counting ladder-hidden rows
as lost (2 red).

## 6. What this document does NOT claim

- **Nothing here reproduces the defect.** It says precisely where it is not, and hands the
  next device pass an instrument instead of a photograph.
- No cause is asserted. The signature is consistent with a document-order visibility walk
  that stopped, which is why the probe reports the first painted row after the run and the
  ancestor the run is lost under — but "consistent with" is a hypothesis and it is labelled
  one.
- The Studio runs used `setEnv` with a frozen env. That is a resize with the right facts
  attached, not an operating-system orientation change; Studio cannot perform the latter,
  and neither can the emulator.
