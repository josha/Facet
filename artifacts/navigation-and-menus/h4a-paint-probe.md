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

---

# ADDENDUM, 2026-08-16 — the instrument shipped a false verdict, and this is why

The director drove the sequence on a real phone. The HUD failed. **The plate read
`13 of 13 painting`** (`fishy.jpeg`, 734x393 landscape, solve 15) while `ScoreHome`,
the tasks panel, the health pod, the kill feed, the round strip and the ladder caption
were all absent from the screen. The instrument built to catch this defect reported the
screen healthy, and the number it printed was acted on.

**Everything in §1 above — "diverged by ZERO" — is now unreliable evidence**, because a
probe with the defects below is exactly the instrument that reports zero divergence
against a real failure.

## A. Why `13 of 13` — the mechanism, measured

`13` was never a count of fourteen rows and `13 painting` was never a paint measurement.

**The denominator moved silently.** A row with no model-wanted path hit `continue` and
left `expected` entirely, so the plate's own denominator shrank with nothing said.
Measured over 28 viewport x URL-bar states before the fix (`_diag2`, headless, the fake
target): **one row leaves the count at every landscape size and four leave it at every
portrait size.** At the director's own 734x393 with a topbar the healthy fixture prints
`11 of 11 painting`; without one it prints **`13 of 13 painting`** — the exact string on
the photograph. *The plate on the failing phone was byte-identical to a plate with
nothing wrong.* There was no number the reader could have distinguished.

The rows that vanish are `ScoreHome`, `ScoreAway` and **`TimerRing`** — and `TimerRing`
is the fixture's first `Path` node, the exact boundary §2 says the unpainted prefix
stops at. The probe was silently dropping the one row it was built to resolve.

**And the `13 painting` half is not a paint verdict.** The engine seam has always
answered `AbsoluteSize`; `enginePaints` read only `Visible`. A node the engine draws at
zero pixels — a parked corpse still in `instancesByPath`, a node never materialised, a
collapsed box — is `Visible = true` and occupies nothing, which is precisely the "the
decision was right and the write never landed" class in §6. Worse: a surface root is
hidden with **`ScreenGui.Enabled`**, a different property on a class no path resolves to
(`src/client/screen_target.luau:1752`), so a whole screen can go dark with all fourteen
rows still reporting `Visible = true`.

## B. The four defects, each confirmed rather than assumed

| # | Defect | Status | Evidence |
|---|---|---|---|
| 1 | **The fallback claimed success.** With no `ctx.geometry`, `enginePaints` returned `true` for every path — "could not measure" published as "measured yes" | **CONFIRMED, latent on the phone** | Code. `ctx.geometry` *is* supplied by the shipped showcase host (`examples/gallery/client/init.client.luau:402`) and by the runner, so this was not the phone's mechanism — but a host whose `adapter.getInstance` is absent answers `{}`, forty paths asked and zero returned, which took the same false branch |
| 2 | **A row was painted if ANY path painted** | **CONFIRMED in code, measured LATENT** | Across the same 28 states, **no row ever has two model-wanted paths**: the rows are alternate forms and the model picks exactly one, so the `any` and the `all` agreed everywhere. It is a real false negative and it was not this one |
| 3 | **A row the model did not want was dropped from the denominator** | **CONFIRMED, and it is the mechanism** | §A above |
| 4 | **The engine's rect was collected and never read**, and `ScreenGui.Enabled` was invisible | **CONFIRMED in code** | The seam returns `w`/`h`; the verdict never looked at them |

**`Rounds` is not a model-side bug.** The director's suspicion was that the model was
calling it "not wanted". Measured: `Rounds` is model-wanted in **28 of 28** states — it
never once left the denominator. The rows that did are named above.

## C. What the plate says now

Three states per row — `painting`, `LOST`, `UNMEASURED` — and the denominator it actually
watched, first and always:

```
Paint probe · 734x393 · solve 15          Paint probe · 852x393 · solve 61 · HELD
11 of 14 rows wanted                      14 of 14 rows wanted
skipped: ScoreHome · TimerRing · ScoreAway 7 of 14 NOT PAINTED
11 of 11 painting                          Objective · Rounds · Tasks · Health · …
                                           first painted: TimerRing
                                           hidden under: /HudScreen/Hud
```

and when the engine side cannot be read, the count is **replaced**, never annotated:

```
Paint probe · 852x393 · solve 3
13 of 14 rows wanted
skipped: Objective
ENGINE SIDE UNAVAILABLE — MODEL ONLY
```

`13 of 13 painting` is now unprintable while anything is lost or unmeasured, and a
skipped row is named rather than omitted.

**A second clock.** `present.onGeometry` fires from the HUD's own solve — the thing under
diagnosis. A surface that stops solving stops sampling, and the plate then wears its last
healthy reading as a current one. The probe now also rides `presenter.onTick` at 4Hz,
which belongs to neither surface, and `report().samples` sits beside `solves` so the two
clocks can be seen to disagree.

## D. What is guarded, and the mutations

`tests/hud_paint_probe.spec.luau`, seven new cases written **before** the fix and seen to
fail against the shipped code (7 red / 10 green), then green (17/17):

- the host supplies no engine seam → the plate carries `ENGINE SIDE UNAVAILABLE` and the
  strings `painting` and `NOT PAINTED` appear nowhere on it;
- a seam that answers `{}` is unavailable, not a healthy screen;
- every skipped row is named and `wanted / declared` is on the plate;
- a row the engine paints at **zero pixels** is LOST;
- a row is painted only when **every** path the model wants is painting — proved on
  `Rounds`, whose watch list now names all three discs (they are siblings, not forms, and
  R3 is the ··· sink every dropped zone recovers through);
- a surface whose **root** is disabled loses every row;
- `13 of 13 painting` cannot be printed while anything is lost or unmeasured.

Six mutations were applied one at a time and every one was seen to redden its own case:
restoring the success-claiming fallback, treating an empty seam answer as a real read,
restoring the `any`, restoring the silent `continue`, deleting the zero-pixel rule, and
deleting both `enabled` checks.

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
