# DIR contract 5 — the extended sweep's negative control

The block `overflow sweep: the HUD under the showcase's OWN chrome`
(`tests/overflow_sweep.spec.luau`) run against the **pre-fix tree** and against
**HEAD**, so the coverage it claims is a measurement rather than an assertion.

## How the control was set up

```
git worktree add --detach <tmp> 3859fba
```

The **instrument** travels into the worktree; the **subject** stays at 3859fba:

| copied in | why it is instrument and not fix |
|---|---|
| `tests/overflow_sweep.spec.luau` | the check itself |
| `tests/lib/showcase_chips.luau` | the derived chip-row rect it drives with |
| the `textFacts.lineHeight` field in `src/layout/solver.luau` (`recordTextFacts` + its three call sites) | a published FACT about the measure the solve already made — it changes no geometry, and without it the painted-fits oracle falls back to the measurer's default 1.2 factor and manufactures its own findings on packages whose lineHeight is 1.15 |

Nothing else was carried back. The fixture (`examples/gallery/scenarios/hud.luau`),
the theme packages and the showcase chrome are 3859fba's.

Then, in the worktree, a runner requiring only that spec file:

```
lune run tests/run_one     # tests/run_one.luau = require("./overflow_sweep.spec")
```

## PRE-FIX (worktree at 3859fba): 6 failed, 76 passed

**95 painted nodes inside the app's declared chrome**, on 6 of the 9 swept
viewports:

| viewport | findings |
|---|---|
| compact-phone-portrait 359x718 | 7 |
| compact-phone-landscape 705x338 | 17 |
| tablet-landscape 1079x809 | 14 |
| console-ten-foot 1920x1078 | 16 |
| narrow-landscape 640x320 | 30 |
| phone-390x844 390x844 | 11 |

Every one of them is the DIR-2 shape: a zone the majority-coverage rule left
level with the chip row, whose own content reaches into it. The three clean
viewports (desktop-standard, narrow-portrait, desktop-studio-1320) are the ones
where the derived chip row does not reach a column's content at all — which is
the rule working, at those cells, before the fix.

The painted-fits oracle reports **nothing** on the pre-fix tree at the swept
cells. That is recorded rather than hidden: the degenerate-box family the
director photographed (`"Tasks 1/3"` in a 48x0 box, the 4px ammo plates) does
not reproduce at these derived chip widths, and the oracle's bite is therefore
carried by the `ORACLE CONTROL` case — which passes in **both** trees, squeezing
a real text node to 0px and to 1px and asserting both are reported.

### transcript (excerpt — the first two failing viewports)

```
  ✗ compact-phone-portrait (359x718): the HUD clears the showcase's chip row and every box holds its own text
      compact-phone-portrait (359x718): 7 finding(s) under the showcase's own declared chrome — the HUD painting on the app's chips, or text in a box that cannot hold it (tests/overflow_sweep.spec.luau, "the HUD under the showcase's OWN chrome"):
  /HudScreen/Hud/Rail [110x83 at 241,58] paints 47x46px into the app's chrome
      [package = nil] [+0] [strip = true]
  /HudScreen/Hud/Rail/RailTall/W1/Plate [110x25 at 241,58] paints 47x17px into the app's chrome
      [package = nil] [+0] [strip = true]
  /HudScreen/Hud/Rail/RailTall/W1/W1Row/W1Name [38x15 at 249,63] paints 38x12px into the app's chrome
      [package = nil] [+0] [strip = true]
  /HudScreen/Hud/Rail/RailTall/W2/Plate [109x25 at 242,87] paints 46x25px into the app's chrome
      [package = nil] [+0] [strip = true]
  /HudScreen/Hud/Rail/RailTall/W2/W2Row/W2Name [45x15 at 250,92] paints 38x15px into the app's chrome
      [package = nil] [+0] [strip = true]
  /HudScreen/Hud/Clock [92x31 at 133,58] paints 3x23px into the app's chrome
      [package = fantasy-ornate] [+0] [strip = true]
  /HudScreen/Hud/Clock/TimerOnlyPod/Plate [92x11 at 133,78] paints 3x11px into the app's chrome
      [package = fantasy-ornate] [+0] [strip = true]
  ✗ compact-phone-landscape (705x338): the HUD clears the showcase's chip row and every box holds its own text
      compact-phone-landscape (705x338): 17 finding(s) under the showcase's own declared chrome — the HUD painting on the app's chips, or text in a box that cannot hold it (tests/overflow_sweep.spec.luau, "the HUD under the showcase's OWN chrome"):
  /HudScreen/Hud/Clock [193x28 at 256,58] paints 60x24px into the app's chrome
      [package = classic-desktop] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/ScoreHome/Plate [46x23 at 256,60] paints 46x21px into the app's chrome
      [package = classic-desktop] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/ScoreHome/ScoreHomeRow/ScoreHomeT [26x15 at 266,64] paints 26x15px into the app's chrome
      [package = classic-desktop] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/Plate [102x28 at 308,58] paints 8x24px into the app's chrome
      [package = classic-desktop] [+0] [strip = true]
  /HudScreen/Hud/Clock [191x26 at 257,58] paints 95x20px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/ScoreHome/Plate [46x25 at 257,58] paints 46x19px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/ScoreHome/ScoreHomeRow/ScoreHomeT [26x17 at 267,62] paints 26x15px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/Plate [100x26 at 309,58] paints 43x20px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Arc [18x18 at 321,62] paints 18x16px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Track [18x18 at 321,62] paints 18x16px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerText [52x17 at 345,62] paints 7x15px into the app's chrome
      [package = compact-pointer] [+0] [strip = true]
  /HudScreen/Hud/Clock [216x44 at 245,58] paints 99x36px into the app's chrome
      [package = scifi-hud] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/ScoreHome/Plate [48x29 at 245,65] paints 48x28px into the app's chrome
      [package = scifi-hud] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/ScoreHome/ScoreHomeRow/ScoreHomeT [28x21 at 255,69] paints 28x21px into the app's chrome
      [package = scifi-hud] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/Plate [122x44 at 299,58] paints 45x36px into the app's chrome
      [package = scifi-hud] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Arc [36x36 at 311,62] paints 33x32px into the app's chrome
      [package = scifi-hud] [+0] [strip = true]
  /HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Track [36x36 at 311,62] paints 33x32px into the app's chrome
```

(full run: `6 failed, 76 passed`)

## HEAD: 82 passed

```
overflow sweep: the HUD under the showcase's OWN chrome
  ✓ compact-phone-portrait (359x718): the HUD clears the showcase's chip row and every box holds its own text
  ✓ compact-phone-landscape (705x338): the HUD clears the showcase's chip row and every box holds its own text
  ✓ tablet-landscape (1079x809): the HUD clears the showcase's chip row and every box holds its own text
  ✓ desktop-standard (1232x1067): the HUD clears the showcase's chip row and every box holds its own text
  ✓ console-ten-foot (1920x1078): the HUD clears the showcase's chip row and every box holds its own text
  ✓ narrow-portrait (320x640): the HUD clears the showcase's chip row and every box holds its own text
  ✓ narrow-landscape (640x320): the HUD clears the showcase's chip row and every box holds its own text
  ✓ desktop-studio-1320 (1320x742): the HUD clears the showcase's chip row and every box holds its own text
  ✓ phone-390x844 (390x844): the HUD clears the showcase's chip row and every box holds its own text
  ✓ ORACLE CONTROL: a plate squeezed under its own styled line is reported, and a plate that holds it is not

```

(full file: `82 passed`, 0 failed)

## What the two runs together establish

1. the appChromeRects axis is **not vacuous** — it fires 95 times on the tree
   this wave started from, on 6 of 9 viewports and 5 of the 9 packages;
2. the fix closes **all** of them, at every viewport, every package and both
   strip states;
3. the painted-fits oracle is calibrated to **zero false positives** over the
   whole cross product at +0 and +14, and is proved to bite by the control case
   rather than by a finding it happens to have produced.
