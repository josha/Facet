# The easing differential oracle — pure twin vs `TweenService:GetValue`

The claim this file exists to support: **`src/motion/curves.luau`'s pure evaluator
is the engine's evaluator.** Production runs `TweenService:GetValue`; Lune cannot,
so a twin ships, and a twin that is merely *plausible* would mean 5,500 headless
tests exercising something no player runs.

## Method

Live in `LuauUI-Showcase.rbxl`, Edit datamodel, Studio MCP, 2026-08-15. Rojo was
connected and the datamodel was confirmed to carry a marker string written minutes
earlier (`curves SYNCED, 12658 bytes; carries the marker string: true`) before any
result was trusted.

`require` is cached per datamodel, so the probe **cloned** `ReplicatedStorage.
LuauUI.motion.curves` and required the clone — reading the right source is not
proof of running it. The clone was destroyed and its absence asserted in the same
call.

Corpus: **11 styles × 3 directions × 1,001 alphas = 33,033 comparisons**, alpha
stepping `i/1000` for `i` in `[0, 1000]`. Threshold `1e-4` — below that no pixel
and no player can separate the two evaluators.

## Result

**Global max |twin − engine| = 4.73e-7**, at `elastic/out`, alpha 0.044.
**Zero** of the 33 style×direction pairs exceeded `1e-4`.

Per-style maximum:

| style | max abs error | style | max abs error |
|---|---|---|---|
| linear | 4.39e-08 | bounce | 2.54e-07 |
| sine | 8.67e-08 | elastic | 4.73e-07 |
| back | 2.24e-07 | exponential | 2.06e-07 |
| quad | 9.29e-08 | circular | 4.36e-07 |
| quart | 1.27e-07 | cubic | 1.16e-07 |
| quint | 1.51e-07 | | |

The vocabulary was checked against the enum in the same run: ours 11, engine 11,
nothing missing from either side.

## The run before this one — why the oracle earned its keep

The twin was first written with Penner's canonical elastic period, `p = 0.3`. That
run:

```
GLOBAL MAX |pure - engine| = 0.02475345 at elastic/in @ a=0.778
DISAGREEING PAIRS (3):
   elastic/in    maxErr=0.024753 @ a=0.778
   elastic/out   maxErr=0.024753 @ a=0.222
   elastic/inOut maxErr=0.012377 @ a=0.389
```

Eight of eleven styles agreed to `< 1e-4` on the first try; `elastic` was off by
2.5% of the full travel. Sweeping the period over `[0.1, 0.6]` and refining
against the engine gave `1/p = 3.250024` → **`p = 1/3.25` exactly**, dropping the
error to `7.4e-6`.

That constant is not in any easing reference. It would never have been found by
reading, and a hand-written twin without an oracle would have shipped a visibly
wrong elastic that every headless test called correct.

## What travels with the suite

A frozen 10-pair × 5-alpha subset of this corpus is embedded in
`tests/motion_tween.spec.luau` (`describe("motion curves: the pure twin IS the
engine's curve")`), captured from the same session, so drift reddens in CI rather
than only in a Studio session nobody re-runs. Mutating the elastic period back to
`0.3` reddens that case (mutation **M1**, `mutation-evidence.md`).

## Re-running it

Paste the oracle probe from this mission's transcript into
`mcp__Roblox_Studio__execute_luau` against the Edit datamodel with Rojo connected.
Confirm the marker-string freshness line first; clone before requiring; destroy the
clone. If Roblox ever adds an `Enum.EasingStyle` member, the vocabulary line of the
probe reports it as `missing-from-ours` — which is the intended signal, since the
twin's `STYLES` list is data, not an implementation.
