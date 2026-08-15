# Time-based easing — per-frame cost

Two tiers, and they answer two different questions. **Headless Lune is a
regression signal; Studio is the real engine.** Neither is a device claim — no
device measurement was taken for this feature, and none is asserted.

## Tier 1 — headless (regression signal): a tween frame is not more expensive than a spring frame

`tools/lune/_bench_tween.luau` (throwaway, not kept: it has no consumer yet).
400 active values, 240 stepped frames, one clock.

**A/A control first**, four consecutive spring runs:
`0.01201 / 0.01170 / 0.01174 / 0.01287 s` → **spread 10.0% of the minimum**.

Interleaved ABBA:

| arm | total | per value per frame |
|---|---|---|
| 400 springs | 0.01181 s | **0.12 µs** |
| 400 tweens | 0.01038 s | **0.11 µs** |

**Delta: a tween frame is 0.88x a spring frame** — a 12% difference against a 10%
control spread, so the honest reading is **"no more expensive, and the sign
favours the tween"**, not "12% faster". The mechanism is unsurprising: a spring
substeps its integrator up to eight times per frame (`MAX_SUBSTEP = 1/120`,
clamped `dt`), while a tween evaluates its curve exactly once.

## Tier 2 — Studio (real engine): the engine's evaluator costs 6.3x a Lua formula, and it does not matter

Measured live, Edit datamodel, 200,000 calls per run (full method in
`docs/research/2026-08-15-roblox-easing-engine-facts.md`).

**A/A control first**: four engine runs `0.01572 / 0.01144 / 0.01158 / 0.01188 s`.
The cold first run is 37.4% off the minimum; **runs 2–4 spread 3.8%**, and only
warm runs are reported.

ABBA: engine `TweenService:GetValue` **58.6 ns/call**, pure Lua twin **9.2
ns/call** → **the engine is 6.3x**.

At sixty concurrent tweens that is **3.5 µs per frame**, 0.02% of a 16.7 ms
budget. The engine evaluator is therefore taken for correctness — it is the
engine's own curve semantics, and a style Roblox adds later is data rather than a
new implementation — and explicitly **not** for speed.

## Why no perf-lab arm was added

The perf lab's 16 workloads measure mount, scroll, press and windowing against
GuiObject counts and instance churn. A tween value adds **no instances and no new
write path**: it reaches the screen through the same signal write and the same
single per-frame transaction as a spring, and the two measure the same to within
the control spread above. An arm comparing them would be a workload with no
question in it.

The arm becomes worth adding when there is a production consumer whose frame cost
is in doubt — the showcase fixture is the first consumer and it animates a handful
of values. Recorded here so the next agent knows it was considered and why it was
declined, rather than finding a gap.
