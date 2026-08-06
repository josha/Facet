# The low-end Android target, and the arithmetic behind it

**Status: an ESTIMATE, not a measurement.** Every number in the derivation below comes
from published hardware specs and general benchmark knowledge, not from running this
code on the device. Nothing here upgrades the evidence class. `PL-P1`/`PL-P2` stay
`PENDING_PHYSICAL`, and the first real capture on the hardware supersedes this whole
page.

Its purpose is narrower than it looks: give the optimization loop a **number to aim at**
in Studio, so "make it faster" has a finish line instead of being open-ended.

## The device

"2020 Amazon Fire tablet" is, in that model year, the **Fire HD 8 (10th generation)**:

| | |
|---|---|
| SoC | MediaTek MT8168 |
| CPU | 4× Cortex-A53 @ 2.0 GHz |
| GPU | PowerVR GE8300 |
| RAM | 2 GB |

The part that matters here is **Cortex-A53**. It is an *in-order* core with a short
pipeline and small caches — the efficiency core of the mid-2010s, used here as the
*only* core type. Layout solving is branchy, allocation-heavy, pointer-chasing Luau on
one thread, which is close to the worst case for that microarchitecture.

## The gap

| | single-thread |
|---|---|
| Cortex-A53 @ 2.0 GHz | Geekbench 5 single ≈ 130–170 |
| Apple M4 (Mac mini) | Geekbench 5 single ≈ 3300–3500 |

**≈ 22× single-thread**, with a defensible range of **15–30×** given how loosely a
synthetic score maps to interpreter work.

Two corrections, both pointing the same way:

- **The real gap is probably WORSE than 22× for this workload.** Geekbench is dominated
  by tight, cache-resident kernels. An in-order A53 with a small L2 suffers more on
  interpreted, allocating, pointer-chasing code than that score implies.
- **GPU is not the constraint.** The lab's scroll is CPU-bound: the MicroProfiler
  capture reads `RenderGPUFrameTime` p50 at **0.0005 ms** against a CPU frame of
  3.0 ms. A GE8300 is far slower than an M4 GPU, but it is drawing a few hundred
  flat 2D rectangles. This is a CPU problem, so single-thread is the right axis.

## The target

```
30 fps on the Fire HD 8              →  33.3 ms per frame
UI's share of that frame             →  25%  =  8.0 ms on device
                                         (generous, but scrolling a list IS
                                          the interaction — the UI has earned
                                          a quarter of the frame at that moment)
divide by the 22× single-thread gap  →  0.36 ms per frame in Studio on the M4
```

### → **≤ 0.4 ms/frame of LuauUI work, measured as the `LuauUI/scenario` span in a Studio Play session on the M4 Mac mini.**

Bounds from the range rather than the midpoint: **0.27 ms** (30× gap, pessimistic) to
**0.53 ms** (15× gap, optimistic). 0.4 ms is the number to aim at; anything under
0.53 ms is arguably inside the honest error bar.

**What this target is not.** It is not a claim that hitting 0.4 ms in Studio produces a
smooth scroll on a Fire HD 8. Studio on an M4 differs from a retail client on ARM
Android in more ways than clock speed: different allocator behaviour, different
thermal envelope (the Fire throttles; the Mac mini does not), 2 GB of RAM shared with
the OS, and a graphics driver that is not the same software. **The target is a proxy
chosen so the optimization loop can converge. Only the device settles it.**

## Where we started, and where we are

`LuauUI/scenario` is the per-frame span around the lab's `pres.tick` + `pres.refresh` —
the honest "what does LuauUI cost this frame" number.

| | Studio, phone portrait 360×691 | vs target |
|---|---|---|
| before this pass | **2.79 ms/frame** | 7.0× over |
| after the measure-key fix (L-9) | **1.93 ms/frame** | **4.8× over** |

Measured across the emulator matrix on the optimized build (all `ms/frame`):

| emulator row | viewport | `scenario` |
|---|---|---|
| compact-phone-portrait | 360×691 | 1.93 |
| compact-phone-landscape | 706×339 | 1.60 |
| tablet-landscape | 1080×810 | 3.52 |
| desktop (no simulation) | 907×1044 | 4.04 |

**Emulating a phone does not emulate phone hardware.** The numbers above track the
number of rows in the window, not the device class — a smaller canvas mounts fewer
rows, and that is the whole of the difference. This matrix proves the layout is correct
and the cost scales with the window; it says nothing at all about how a Fire HD 8 will
run it.

The same capture's per-call breakdown at the start: `arrange` 2.67 ms/call,
`commit` 1.44 ms/call, `mount` 2.14 ms/call, `measure` 0.48 ms/call — with **98% of all
measure calls happening inside the arrange pass**, which is why arrange dominates and
why the measure cache is the lever that moves it.


## What stands between here and the target

| lever | est. size | why not yet |
|---|---|---|
| ~~Instance recycling (PLN-5)~~ | **TRIED — measured ~0.035 ms/f, indistinguishable from noise.** Built, differential-verified, mutation-proved, shipped OFF. See optimization-log L-10 | the 12× per-row figure was real but misapplied: only ~2.8 objects churn per frame, so Instance churn is at most 5% of `mount` |
| **Incremental `structuralSync`** | the actual cost of `mount`. It is O(all live nodes) — a full `livePaths` walk, a sweep over every handle and a `syncZOrder` on every structural change. `mount` tracks LIVE row count (6 rows → 0.66 ms, 13 rows → 0.97 ms) while churn per scroll step is constant, which is the signature of a sweep | not started; this is now the top candidate |
| **Height-free rule for containers** | real (1 088 text + 1 088 hstack misses per 20 solves remain) | blast radius is the whole layout algorithm, and the differential fuzz could not construct a biting case even for the text-only over-broad rule |
| **Reduce per-row GuiObjects** | 23.6 per row vs 9.2 for the raw-Roblox reference | a design change to the row, not a framework fix |

Closing 4.8× is not a tuning job; it needs at least the first of those.
