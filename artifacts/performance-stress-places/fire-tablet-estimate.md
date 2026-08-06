# Where we landed, and what a fling costs on a Fire HD 8

**The measurements are real. The device number is an ESTIMATE** — no LuauUI code has run
on that hardware. `PL-P1`/`PL-P2` remain `PENDING_PHYSICAL`, and the first real capture
supersedes this page.

## Measured now (Studio, M4 Mac mini, 360×691, 2 000 rows)

The workload is the one the question is about: each row is an avatar image, two text
labels, a Ready toggle, a Rate stepper and an Open button — ~20 GuiObjects per row, 6–7
rows in the window, ~185 GuiObjects on the surface.

`LuauUI/scenario` is the per-frame span around all LuauUI work.

| | `scenario` | `mount` | `arrange` | `commit` | `measure` |
|---|---|---|---|---|---|
| steady scroll | **1.97** | 0.664 | 0.520 | 0.123 | 0.155 |
| **fling** (whole window replaced per step) | **2.26** | **1.52** | 0.311 | 0.251 | 0.115 |

All figures ms/frame.

### What the optimisation work changed

| | before | now |
|---|---|---|
| steady scroll, `scenario` | 2.79 | **1.97** (−29%) |
| arrange, per solve | 2.67 | 2.03 → 0.52 ms/f |
| one bound value, nodes arranged | 121 | **8** (−93%) |
| Instance creates per fling | 9 964 | **6 188** (−38%) |

**Incremental layout does not help a scroll, and the numbers say so plainly** (1.97 vs
1.99 with it off). Scrolling is a *structural* change — rows enter and leave — so the
partial path correctly falls back to a full solve. It pays on data changes, where a
ticking value now re-arranges 8 nodes instead of 121.

**During a fling the cost is `mount` — 1.52 of 2.26 ms — which is row materialisation,
not layout.** Layout is 0.31 ms of it.

## The Fire HD 8 estimate

Device: Fire HD 8 (10th gen, 2020) — MediaTek MT8168, 4× Cortex-A53 @ 2.0 GHz, 2 GB RAM,
PowerVR GE8300.

**The gap is not one number, because the work is not one kind.** Splitting the fling
frame by what the time is actually spent on:

| component | measured (M4) | scaling assumption | estimated on device |
|---|---|---|---|
| `mount` — Instance creation, parenting, property writes | 1.52 ms | **~10×** (engine C++/allocator, not interpreted) | ~15 ms |
| `arrange` + `measure` + `commit` — interpreted Luau | 0.68 ms | **~22×** (A53 in-order, small caches; Geekbench-derived) | ~15 ms |
| | | | **≈ 30 ms/frame** |

### Updated after inert-container elision (L-21)

The surface went from 137 GuiObjects to **91** and a fling frame from 2.26 ms to
**~1.90–2.05 ms**, with `mount` **1.52 → ~0.80–1.24 ms**. Re-running the same split on
the mid-point of those readings:

| component | measured (M4) | gap | on device |
|---|---|---|---|
| `mount` | ~1.0 ms | ~10× | ~10 ms |
| `arrange`/`measure`/`commit` | ~0.8 ms | ~22× | ~18 ms |
| | | | **≈ 28 ms/frame** |

**Still ~20–25 fps on a fling, still short of 30.** The instance win is real and it moved
`mount` substantially, but it shifted the balance rather than closing the gap: interpreted
Luau is now the larger half. The next lever is therefore solver/renderer CPU, not object
count — and the 10× assumption for engine work is doing less of the work in this estimate
than it was, which makes the whole number slightly more trustworthy than before.

### → **Flinging this list would run at roughly 15–25 fps on a Fire HD 8. It would not hold 30.**

At 30 fps the whole frame budget is 33 ms, and LuauUI alone is estimated at ~30 ms of it
— leaving nothing for rendering, input, audio, or the game. Even on the optimistic end of
the range (15× gap → ~20 ms) the UI would be consuming two-thirds of the frame.

**Steady scrolling is close but not clear**: 1.97 ms × the same split ≈ 26 ms — around
30 fps with almost nothing to spare.

### What this estimate does not cover

- **The GPU.** The capture reads `RenderGPUFrameTime` p50 at 0.0005 ms on an M4, which
  is why every conclusion here is CPU-based. A GE8300 drawing ~185 GuiObjects with
  avatar images is a different proposition and is **unmeasured**. It could be a second
  constraint or a non-issue; nothing here says which.
- **Thermals.** The Fire throttles; the Mac mini does not. A sustained fling is exactly
  the case where that shows up.
- **Memory.** 2 GB shared with the OS, against a workload holding 2 000 logical rows.
- **The 10× for engine work is the weakest number on this page.** It is a judgement that
  C++ Instance allocation scales better than interpreted Luau across this hardware gap,
  not a measurement. If it is really 22×, the fling frame is ~48 ms and the answer is
  ~20 fps.

## What would actually move it — revised after the object work

1. ~~**Fewer GuiObjects per row.**~~ **DONE, and it was not the row.** Enumerating one row
   showed its CONTENT is already at parity with the native reference (9 elements against
   9.2); the entire 2.6× was framework container instances. Eliding the inert ones took
   the surface from 137 GuiObjects to 91 and `mount` from 1.52 to ~1.0 ms on a fling.
2. ~~**Cheaper adoption.**~~ **DONE.** The property caches now travel with the recycled
   instance, so adoption writes only what differs: propWrites −56% headless, −18% Studio.
3. ~~**Incremental `structuralSync`.**~~ **MEASURED AND DROPPED.** It is not O(all live
   nodes): of a 2.166 ms pass, the no-op walk is ~6% and the rest is ~83 µs of setup per
   genuinely new node. The "scales with row count" observation had a different cause —
   the wide row's 56px pitch crosses more row boundaries per scroll than the compact
   row's 152px, so more visible rows meant more churn, not more walking (L-22).
4. **Per-new-node setup — ~83 µs each.** Raw `Instance.new` is only 12.4 µs of it; the
   rest is `applyProps`, handler wiring and chrome construction. Three passes have
   already attacked this from different angles (recycling, the property diff, elision);
   what remains is the wiring and chrome on nodes that genuinely are new.
5. **Solver/renderer CPU.** With `mount` roughly halved, interpreted Luau is now the
   larger half of the estimated device frame (~18 ms of ~28). `arrange` and `commit` are
   where a fling's remaining time goes.

**The conclusion has flipped.** Instance materialisation was the problem; it is now
roughly balanced with interpreted layout work, and further object-count wins will move
the device number less than solver work would.
