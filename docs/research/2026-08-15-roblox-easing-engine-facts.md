# Roblox easing / TweenService — measured engine facts (2026-08-15)

Measured live in `Facet-Showcase.rbxl` via the Studio MCP, Edit and Play
datamodels as noted. Companion to ADR-0033. Every number here is an observation,
not a recollection — the point of the file is that the next agent does not have to
re-derive them, and does not trust memory instead.

## `TweenService:GetValue` is a pure function, and that is the load-bearing fact

`TweenService:GetValue(alpha, EasingStyle, EasingDirection)` takes a number and
returns a number. It touches no `Instance`, so unlike `TweenService:Create` it can
drive a value a framework owns. This is what makes "the engine owns the curve"
possible at all.

## The eleven styles, read from the enum

`Enum.EasingStyle:GetEnumItems()` = `Linear, Sine, Back, Quad, Quart, Quint,
Bounce, Elastic, Exponential, Circular, Cubic` (11).
`Enum.EasingDirection:GetEnumItems()` = `In, Out, InOut` (3).

There are no `Expo` / `Circ` aliases; the names are exactly as above.

## Roblox's elastic period is `1/3.25`, not Penner's `0.3`

The single most valuable finding here, because reading would never have produced
it. A pure twin written with the textbook Penner elastic period of `0.3` disagreed
with the engine at **max |err| 0.0248** in all three directions while the other
eight styles agreed to `< 1e-4`.

Sweeping the period against the engine over 201 alphas and refining gave
`1/p = 3.250024`, i.e. **`p = 1/3.25` exactly**, which drops the error to
`7.4e-6`. Every other constant is the standard one (`back` overshoot `1.70158`,
`bounce` on the `7.5625 / 2.75` ladder).

Engine `Elastic/In` at alpha 0..1 by 0.1, for anyone re-deriving:
`0, 0.0017, -0.0032, -0.0012, 0.0149, -0.0221, -0.0193, 0.1235, -0.1469, -0.2270, 1`

## Curve-evaluation cost: the engine is ~6x a Lua formula, and it does not matter

Edit datamodel, 200,000 calls per run.

- **A/A control first**: four consecutive engine runs `0.01572 / 0.01144 / 0.01158
  / 0.01188 s`. The cold first run is 37.4% off the minimum; runs 2–4 spread
  **3.8%**. Report warm runs only.
- **ABBA**: engine `58.6 ns/call`, pure Lua `9.2 ns/call` → **engine is 6.3x**.
- Both accumulators over 200k samples agreed to `2e-5`.

At sixty concurrent tweens that is 3.5 µs per frame — 0.02% of 16.7 ms. **The
engine is not the cheaper option here; it is the correct one.** Do not let
"native" be quoted as "faster" from this file.

## An engine tween DOES update per frame — in Play. Edit mode lies about it.

The trap worth remembering. A 1.0 s linear `TweenService` tween on a `NumberValue`,
sampled every frame:

| datamodel | frames observed | distinct values seen | change-signal fires |
|---|---|---|---|
| **Edit** | 72 | 17 (**24%**) | 16 |
| **Play (Client)** | 17 | 16 (**94%**) | 15 |

Play-mode `Frame.Rotation` 89%, `Frame.BackgroundTransparency` 100%.

The Edit-mode 24% is an **instrument artifact** — Edit throttles property
propagation — and reading it as "the engine's tweens are low-rate" would have been
a confident false finding. Measure tween fidelity in Play.

## `TweenService:Create` costs an Instance per animated value

Play datamodel, 500 values, A/A control stated first (spread **41.0%**, small N).

- Arm (`Instance.new` + parent + `Create` + `Play`): **6.1 µs per value**, plus one
  `Instance` each.
- The pure-Lua equivalent of arming the same 500 ramps: **0.031 µs per value** —
  ~196x.
- `Cancel()` leaves the property exactly where it stood (26.69 → 26.69: no jump),
  and `Tween.Completed` fires with `Enum.PlaybackState.Cancelled` on cancel and
  `Completed` on finish. So a retarget is `Cancel` + `Create` + `Play`, i.e. a dead
  `Tween` object every time.

## A tween on a StyleSheet-claimed property takes it, silently and permanently

Directly relevant to this codebase, which already records that a second writer on
this platform is silent. Measured: a `StyleRule` setting `Frame.BackgroundTransparency`
to 0.25, then a `TweenService` tween on the same property to 1.

- mid-tween: `0.6257` (the tween is writing)
- post-tween: `1`, `PlaybackState = Completed`
- **then the rule was rewritten to `0.5` — and the property stayed at `1`.** The
  sheet did not regain it.
- No error, no warning, on either side.

So a `TweenService` tween pointed at a `GuiObject` property that Facet's native
StyleSheets claim does not merely conflict for the duration of the tween; it takes
the property for good. This is a second reason (beyond ADR-0022 Decision 2's write
authority) that the engine's interpolator must not be aimed at rendered UI
properties from inside the framework.

## The differential oracle

11 styles × 3 directions × 1,001 alphas = **33,033 comparisons** between
`src/motion/curves.luau`'s pure twin and `TweenService:GetValue`.

**Max |twin − engine| = 4.73e-7** (at `elastic/out`, alpha 0.044). Per style:
`linear 4.4e-8, sine 8.7e-8, back 2.2e-7, quad 9.3e-8, quart 1.3e-7, quint 1.5e-7,
bounce 2.5e-7, elastic 4.7e-7, exponential 2.1e-7, circular 4.4e-7, cubic 1.2e-7`.
Zero pairs above the 1e-4 threshold.

## Probe hygiene note

`require` is cached per datamodel, so a re-synced module must be **cloned and
required from the clone** or the probe reads the version a previous run loaded.
Every probe above created its instances under a named holder and destroyed it,
asserting absence in the same call.
