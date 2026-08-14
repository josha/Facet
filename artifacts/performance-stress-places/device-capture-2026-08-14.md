# Device MicroProfiler capture, 2026-08-14 — the L-29 verdict

**Evidence tier: 3 — physical device.** Two binary MicroProfiler dumps taken by the
game director on a real low-end Android handset from the rebuilt
`LuauUI-PerformanceLab.rbxl` (the place that carries the L-29 fix), using the
**Profile** button, which loops ONE pass so the ~30-frame dump window is guaranteed
to land inside the chosen workload. Tier 3 is authoritative over every headless
(Lune) and Studio (tier 2) number in this log; where a figure here disagrees with a
bench number, this file wins.

| | |
|---|---|
| device | Samsung **SM-A102U1** (Galaxy A10e), Android 11 |
| CPU / GPU | ARM, 8 cores · Mali-G71, Vulkan 1.1, 64 MB VRAM |
| system memory | **1 708 MB** |
| display | 698 × 1513 @ ScreenDpiScale 1.9375, QualityLevel 3 (auto) |
| client | Version 734, Release, `Technology=Unified`, `LightingStyle=Soft` |
| captures | `mount.html` (`mount-ramp`), `resize.html` (`resize-relayout` → `resizeStorm`) |

Both dumps contain **all twelve** `LuauUI/*` scopes with non-degenerate counts, so
unlike `perfPlace2gb.html` (nine of twelve at zero) and the first
`resize-relayout` attempt (one several-hundred-millisecond frame) these are
**usable**. The two workload-identification fixes recorded in the handoff
(`docs/handoff/2026-08-13-microprofiler-capture.md`) did their job: `resize.html`
carries `Cause=LuauUI_PerfWorkload`, `mount.html` carries `Cause=/PerfWorkload/Rows`.

---

## 1. The L-29 verdict: it landed — the count dropped while the solve did not

`resize-relayout` / `resizeStorm`. One pass step = one `telemetry.step()` = one
Heartbeat = **one frame**, so "per step" and "per frame" are the same quantity here
and both are directly comparable to the pre-fix capture.

| quantity | `rr.html` (pre-fix, tier 3) | `resize.html` (post-fix, tier 3) | delta |
|---|---:|---:|---:|
| `arrange` **occurrences per step** | **9.67** | **7.12** | **−26.4 %** |
| `arrange` ms per occurrence | 8.270 | **9.136** | +10.5 % |
| `measure` ms per occurrence | 3.057 | **3.236** | +5.9 % |
| `arrange` + `measure` share of wall | **58.5 %** | **50.8 %** | −7.7 pts |
| `react` (reactive flushes) per step | not recorded | **3.03** | — |

**The per-occurrence cost did not move, which is exactly what L-29 predicted** —
`env:batch` plus the coalescing geometry memo target the *number* of solves, never
the solve. 8.270 → 9.136 ms and 3.057 → 3.236 ms are capture-to-capture noise on a
handset whose frame time is itself varying 129–204 ms; neither is a regression and
neither would be evidence of anything if it had moved by that much in the other
direction.

**The raw −26 % understates the win, because the workload got six times harder
underneath the comparison.** The pre-fix `resizeStorm` set `viewportRect`
**alone** — a resize no device performs (plan §"And the lab was measuring a resize
no device performs"). The post-fix pass drives the whole six-fact adapter group
(`viewportRect`, `coreSafeInsets`, `deviceSafeInsets`, `topbarSafeInsets`,
`topbarInset`, `displaySize`), batched exactly as `roblox_env.pushViewport()`
batches it. So the honest reading of the table is:

> **9.67 arranges per step for ONE fact, before → 7.12 arranges per step for SIX
> facts, after.**

On the pre-fix build those six facts cost 5 workload solves rather than 1 (L-27's
record, re-confirmed tier 2 in L-29 at 4–5 solves on the real engine). With two
mounted surfaces sharing one environment and the overlay's two extra unbatched
writes, the same step on the pre-fix build would have cost roughly
5 × 2 + 2 × 2 + 1 ≈ **15 arranges per step**. Against that, 7.12 is about a **2×**
like-for-like win.

**The direct evidence that batching is live on the device is `react`.** `react`
opens once per reactive flush (`src/core/custom.luau:257`). Six loose writes plus
the overlay's two plus the data change is **nine** flushes per step; the device
measured **3.03**. The six-fact group is arriving as ONE flush. And the guard the
handoff asked for is green: nothing here resembles ~5 solves per resize from
per-key fan-out — the fan-out is gone, and the residual count is fully accounted
for below.

**Verdict: L-29 landed.** Recorded as L-30 in `optimization-log.md`.

---

## 2. Where the time goes now — per scope, both captures

### Method, stated so the numbers can be checked

The dumps are base64 inside an HTML comment: a 3-byte `GAK` magic, `u32`
uncompressed size, `u32` compressed size, then a zlib stream. Inside, the aggregate
timer table is **1 347 records of 80 bytes** at offset `header[0x50]`
(count at `header[0x4c]`, end at `header[0x58]`), each record being
`u64 total · u64 worst · u32 id · u32 group · u32 color · u32 count · u32 nameOffset`.
Names are `\0`-terminated in a string blob of `header[0xc4]` bytes at the tail of
the file. Timer frequency is `header[0x28]` = **1 000 000 000**, i.e. the totals are
nanoseconds. `header[0x20]` = **60** is the aggregate frame window.

Cross-checks that make the decode trustworthy rather than plausible:

* the event log (parallel `u16` token column at `header[0x90]`) reproduces the
  aggregate `count` **exactly** for 9 of the 12 `LuauUI` scopes and is 3 short on
  the other 3 (boundary truncation);
* `LuauUI/tick`, `LuauUI/scenario`, `queuePresent`, `Pass2d/PlayerGui`, `Prepare`,
  `Perform` and `fillGuiVertices` all read **exactly 60** — one per frame over the
  60-frame aggregate window;
* the frame count of the event-log ring is **30** by three independent counts —
  30 `RenderTotalTime` strings, 30 `Steps Simulated` strings, and 30
  `queuePresent` occurrences;
* frame time from the log clock (173.2 ms) agrees with the physics scheduler's
  own view (1 266 required 240 Hz steps over 30 frames = 175.8 ms) to **1.5 %**.

**The field the format defeated me on, stated rather than guessed.** The event log's
`u64` timestamp column reconstructs engine scopes correctly (`queuePresent`:
30 pairs, 308.3 ms, against the aggregate's 297.5 ms) but **not** the Lua
`LuauUI/*` scopes — it returns ~0.06 ms per `arrange` where the aggregate says
9.14 ms. So the per-occurrence *distribution* of a Lua scope is not recoverable
from these files; only its total, count and worst. Everything below comes from the
aggregate table, which is the same source the `rr.html` reference numbers came
from. A second, harmless ambiguity: the aggregate window can be read either as 60
frames with `count` = occurrences, or as 30 frames with `count` = log entries and
the accumulators doubled. **Every quantity reported here — ms/occurrence,
occurrences per step, and % of wall — is identical under both readings**; only the
absolute total-ms column and the absolute window length differ, and those are
labelled with the window they assume.

### `resize.html` — `resize-relayout` / `resizeStorm`

Window: **60 frames × 173.2 ms = 10 391 ms wall**, i.e. **5.77 fps**.
Render thread: `RenderTotalTime` mean **22.87 ms**, `GPU Time` ~21.6 ms — the
frame is **not** GPU-bound; it is CPU-bound on layout by a factor of about eight.

| rank | scope | occ | occ/step | total ms | ms/occ | % wall | worst ms |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `LuauUI/arrange` | 427 | **7.12** | **3 901.1** | 9.136 | **37.5 %** | **131.23** |
| 2 | `LuauUI/measure` | 427 | 7.12 | 1 381.9 | 3.236 | 13.3 % | 45.16 |
| 3 | `LuauUI/react` | 182 | **3.03** | 860.5 | 4.728 | 8.3 % | 28.26 |
| 4 | `LuauUI/mount` | 120 | **2.00** | 766.4 | 6.387 | 7.4 % | 23.11 |
| 5 | `LuauUI/commit` | 609 | 10.15 | 726.1 | 1.192 | 7.0 % | 23.57 |
| 6 | `LuauUI/present` | 178 | 2.97 | 469.4 | 2.637 | 4.5 % | 15.61 |
| 7 | `LuauUI/focusmap` | 356 | 5.93 | 116.4 | **0.327** | 1.1 % | 4.23 |
| 8 | `LuauUI/mutate` | 58 | 0.97 | 9.2 | 0.159 | 0.1 % | 0.40 |
| 9 | `LuauUI/tick` | 60 | 1.00 | 5.2 | 0.087 | 0.1 % | 0.26 |
| 10 | `LuauUI/scenario` | 60 | 1.00 | 0.6 | 0.010 | 0.0 % | 0.01 |
| — | `LuauUI/resource` | **0** | 0 | 0.0 | — | 0 % | — |
| — | `LuauUI/reset` | **0** | 0 | 0.0 | — | 0 % | — |

`measure` and `arrange` are **siblings** inside one `solve()`
(`src/layout/solver.luau:4208` and `:4216`), not nested — so adding their shares is
legitimate and the 50.8 % figure is directly comparable to `rr.html`'s 58.5 %.
`focusmap` is nested inside `present`.

Top non-LuauUI scopes for scale: `queuePresent` 297.5 ms (2.9 %), `GC` 215.5 ms
(2.1 %), `FrameCheck` 198.6 ms (1.9 %), `FMOD::Output::mix` 160.8 ms,
`LocalizationService::attemptLocalization` 110.7 ms over 762 calls. Everything the
engine does put together is a rounding error next to `arrange`.

### `mount.html` — `mount-ramp` / `ramp`

Window: **60 frames × 286.8 ms = 17 207 ms wall**, i.e. **3.49 fps**.
`RenderTotalTime` mean 23.74 ms — again not GPU-bound.

| rank | scope | occ | occ/frame | total ms | ms/occ | % wall | worst ms |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `LuauUI/scenario` | 86 | 1.43 | **1 554.0** | **18.070** | 9.0 % | **102.99** |
| 2 | `LuauUI/arrange` | 67 | 1.12 | 409.9 | 6.117 | 2.4 % | 26.61 |
| 3 | `LuauUI/commit` | 71 | 1.18 | 282.7 | 3.982 | 1.6 % | 41.25 |
| 4 | `LuauUI/mount` | 53 | 0.88 | 233.2 | 4.401 | 1.4 % | 20.37 |
| 5 | `LuauUI/reset` | 26 | 0.43 | 216.3 | 8.320 | 1.3 % | 17.88 |
| 6 | `LuauUI/measure` | 67 | 1.12 | 156.0 | 2.328 | 0.9 % | 9.80 |
| 7 | `LuauUI/focusmap` | 172 | 2.87 | 46.0 | 0.268 | 0.3 % | 8.81 |
| 8 | `LuauUI/present` | 86 | 1.43 | 20.4 | 0.237 | 0.1 % | 2.05 |
| 9 | `LuauUI/tick` | 60 | 1.00 | 6.2 | 0.104 | 0.0 % | 0.47 |
| 10 | `LuauUI/react` | 107 | 1.78 | 6.6 | 0.062 | 0.0 % | 1.84 |
| 11 | `LuauUI/resource` | 28 | 0.47 | 1.1 | 0.038 | 0.0 % | 0.28 |
| 12 | `LuauUI/mutate` | 8 | 0.13 | 0.2 | 0.028 | 0.0 % | 0.08 |

`Script_PerfLab` — the engine's bar for the lab's own script — is **3 865 ms
(22.5 % of wall)** over 387 resumptions at 9.99 ms each; `LuauUI/scenario` sits
inside it. See the anomalies section: this capture does **not** rank LuauUI levers,
because only ~9 % of its wall is inside any LuauUI phase scope at all.

Ranked across both captures, the single largest LuauUI cost on this device is
`resize.html`'s `arrange` at **3 901 ms / 37.5 % of wall**; the second is the same
capture's `measure` at 13.3 %. Nothing in `mount.html` reaches either.

---

## 3. The overlay's cost — a dock panel costing as much as a 2 000-row list

optimization-log **L-29 residual 1** predicted this precisely: the lab's overlay
re-publishes `coreSafeInsets` twice per resize (`forgetReservation` zeroes it when
the viewport or typography scale moves, then `onGeometry` republishes the measured
dock height), each write unbatched, each its own flush, each its own solve. The
device confirms it from two independent instruments.

**Instrument 1 — the framework's own flush counter.** `react` = **3.03 flushes per
step**. One of those is the pass's batched six-fact `env:batch`. The other two are
the overlay's dance, exactly as residual 1 describes. Every geometry flush
re-solves **every mounted surface**, and there are two (workload + overlay —
confirmed by `focusmap` = exactly 2 × `present`, 356/178, in both captures). So the
per-step solve budget decomposes as

```
3 flushes × 2 surfaces  +  1 workload-only data-change solve  =  7
```

against a **measured 7.12** arranges per step. Of that, **~4 of 7.12 solves per
step (≈ 57 % of all solves) exist only because of the overlay's measure-then-publish
loop** — two extra workload solves and two extra overlay solves.

**Instrument 2 — Roblox's own layout counters**, which are engine-side and owe
nothing to the framework's bookkeeping. Extracted verbatim, both files:

`resize.html`

```
Context=Rendering            Cause=LuauUI_PerfWorkload            Root=LuauUI_PerfWorkload            Relayouts=8  Updates=73 Resizes=66
Context=AbsoluteWindowSize   Cause=/PerfLabOverlay/Dock/Panel     Root=LuauUI_PerfLabOverlay          Relayouts=8  Updates=37 Resizes=38
Context=AbsoluteWindowSize   Cause=/PerfLabOverlay/Dock/Panel     Root=LuauUI_PerfLabOverlay          Relayouts=7  Updates=37 Resizes=38
Context=AbsoluteWindowSize   Cause=/PerfLabOverlay/Dock/Panel     Root=LuauUI_PerfLabOverlay          Relayouts=6  Updates=37 Resizes=38
Context=AbsoluteCanvasSize   Cause=/PerfLabOverlay/Dock/Panel     Root=/PerfLabOverlay/Dock/Panel     Relayouts=1  Updates=1  Resizes=27
Context=Rendering            Cause=LuauUI_PerfLabOverlay          Root=LuauUI_PerfLabOverlay          Relayouts=0  Updates=0  Resizes=0
```

`mount.html`

```
Context=AbsoluteWindowSize   Cause=/PerfWorkload/Rows                     Root=LuauUI_PerfWorkload                     Relayouts=92 Updates=92 Resizes=91
Context=AbsoluteCanvasSize   Cause=/PerfWorkload/Rows                     Root=/PerfWorkload/Rows                      Relayouts=1  Updates=71 Resizes=64
Context=AbsoluteWindowSize   Cause=/PerfLabOverlay/Dock/Panel             Root=LuauUI_PerfLabOverlay                   Relayouts=39 Updates=39 Resizes=38
Context=AbsoluteCanvasSize   Cause=/PerfLabOverlay/Dock/Panel             Root=/PerfLabOverlay/Dock/Panel              Relayouts=1  Updates=27 Resizes=27
Context=AbsoluteCanvasSize   Cause=/PerfLabOverlay/Dock/Panel/Stack/Picker Root=/PerfLabOverlay/Dock/Panel/Stack/Picker Relayouts=1  Updates=1  Resizes=11
Context=Rendering            Cause=LuauUI_PerfWorkload                    Root=LuauUI_PerfWorkload                     Relayouts=4  Updates=6  Resizes=12
Context=Rendering            Cause=LuauUI_PerfLabOverlay                  Root=LuauUI_PerfLabOverlay                   Relayouts=0  Updates=0  Resizes=0
```

The three `LuauUI_PerfLabOverlay` / `AbsoluteWindowSize` rows in `resize.html` carry
identical `Updates=37 Resizes=38` with `Relayouts` 8 / 7 / 6 — the same counter
sampled at three moments, not three separate costs. So the overlay's engine-side
totals are **Relayouts 8, Updates 37, Resizes 38**, against the workload's
**Relayouts 8, Updates 73, Resizes 66**:

> **The overlay — one dock panel with a handful of controls — provokes the SAME
> number of engine relayouts as the entire 2 000-row workload, and 33.6 % of the
> layout updates (37 of 110) and 36.5 % of the resizes (38 of 104).**

In `mount.html` the same panel takes **39 of 131 window-size relayouts (30 %)**
while the ramp is building thousands of rows.

**How much of the resize capture is the overlay rather than the workload?**
Two answers, because they measure different things and both are true:

* **By solve count:** ~4 of 7.12 solves per step — **≈ 57 %** — are attributable to
  the overlay's reservation dance (2 overlay solves + the 2 extra workload solves
  its unbatched writes force).
* **By CPU time:** far less, because an overlay solve walks a dock panel and a
  workload solve walks a windowed 2 000-row list. Attributing the 3 901 ms of
  `arrange` across 4 workload and 3 overlay solves per step, and taking the
  overlay's own solves as small, puts the overlay's *direct* time at roughly
  **1–2 % of wall** but its *induced* time — the two extra full workload
  re-solves it forces every step — at roughly **half of `arrange` + `measure`,
  i.e. ~25 % of wall.**

The induced half is the number that matters, and it is the top lever.

---

## 4. The new top levers, ranked

### Lever 1 — the measure→publish feedback loop (L-29 residual 1). ~25 % of wall.

**The number that justifies it:** `react` = **3.03 flushes per step** where the
framework's own contribution is **1**; `arrange` = 7.12/step where the framework's
own contribution to a batched six-fact resize is 1 per surface.

**Estimated saving:** removing the two extra unbatched writes takes the workload
from ~4 solves per step to ~2 and the overlay from 3 to 1. `arrange` −~1 950 ms,
`measure` −~690 ms, `commit` −~300 ms of a 10 391 ms wall ≈ **−25 to −28 % of wall**,
which on this device is a resize step going from ~173 ms to ~125 ms.

**File / mechanism:** the *occurrence* is `examples/performance/lab/perf_lab.luau`
(`forgetReservation` / `onGeometry`), but L-29 was right that the honest fix is a
framework one and is a design question, not a patch: **a measure→publish cycle must
be able to settle inside one flush.** Any app that reserves space from measured
geometry — a HUD reserving under a topbar, a game reserving under a results
banner — has this exact shape, so fixing it in the lab alone buys the lab a number
and buys consumers nothing. The seam is `env:batch` / `core:transaction`
re-entrancy plus a settle phase in `src/core/custom.luau`'s flush, so that a write
made *while responding to* a geometry change joins the flush that caused it instead
of opening a new one. `tests/perf_lab.spec.luau` already excludes `coreSafeInsets`
from its batching oracle for this reason and says so — that exclusion is the
regression test that would have to be deleted when this lands.

### Lever 2 — the solve itself. `arrange` is 37.5 % of wall, worst occurrence 131 ms.

**The number:** `arrange` **9.136 ms/occurrence**, 3 901 ms total, **37.5 % of
wall** — and a **worst single occurrence of 131.23 ms**, which is 76 % of a whole
173 ms frame in one call. `arrange` is 2.8× `measure` per occurrence, so the cost
is in rect derivation and stack distribution, not in text metrics or intrinsic
sizing.

L-27 concluded *"the lever for a resize is the solve COUNT, not the solve."* With
L-29 paid and lever 1 scoped, **that is no longer true: the solve is now the
frontier.** Incremental layout cannot help here by construction (L-27 measured 2
partial solves out of 65 — a resize changes every constraint), so this is work on
`arrange()` itself in `src/layout/solver.luau`, and it should start from the 131 ms
tail rather than the 9.1 ms mean: a single 131 ms arrange is what a player feels as
a hitch on rotation.

**Estimated saving:** a 30 % cut in `arrange` is **−11 % of wall**; halving the
tail is worth more to perceived smoothness than either.

### Lever 3 — two structural syncs per viewport change, still. 7.4 % of wall.

**The number:** `LuauUI/mount` = **120 occurrences = exactly 2.00 per step**, at
**6.387 ms each = 12.8 ms per step, 766 ms, 7.4 % of wall**. This reproduces
L-27's *"one viewport change costs 5 solves and 2 structural syncs"* to three
significant figures — L-29 removed the 5, and **left the 2 untouched**.

A width change does not change the tree's structure. `structuralSync`
(`src/render/renderer.luau:3460`, wrapped as `profile.span("mount", …)`) running
twice per resize is either one redundant pass or one pass that should be a no-op
and is not.

**Estimated saving:** halving it is **−383 ms = −3.7 % of wall**; making the second
one the no-op it ought to be could take more.

### Lever 4 — `commit` at 10.15 per step. 7.0 % of wall, but not independent.

609 commits over 60 steps at 1.192 ms — ~1.4 commits per solve, from the two commit
call sites (`src/render/renderer.luau:2687` and `:3484`). Most of this falls out of
lever 1 automatically (fewer solves, fewer commits). Ranked here so it is not
mistaken for a fifth independent prize.

### Not a lever, recorded as healthy

`LuauUI/focusmap` at **0.327 ms/occurrence and 1.1 % of wall** — L-27's
`structureEpoch` cache is doing its job on the device, on a resize workload where
every viewport change is a legitimate structural invalidation. Same for
`LuauUI/tick` (0.087 ms) and `LuauUI/scenario` (0.010 ms): the instrument costs
nothing it measures.

---

## 5. Anomalies, and what each one means

1. **`LuauUI/resource` and `LuauUI/reset` are both ZERO in `resize.html` — and
   this is correct.** `resizeStorm` lands no async asset and tears nothing down.
   The contrast worth keeping is `perfPlace2gb.html`, where *nine of twelve* scopes
   were zero because the window sampled `dense-scroll-native`; two zeros in the two
   scopes that structurally cannot fire is a healthy capture, twelve minus nine is
   a missed one. `mount.html` has **all twelve** non-zero, including
   `resource` 28 and `reset` 26 — the ramp does mount and tear down.

2. **Suspiciously round numbers, all three of which are correct by
   construction.** `mount` = exactly **120** (2.00/step), `tick` = exactly **60**
   (1.00/step), `scenario` = exactly **60** (1.00/step). The `tick`/`scenario` pair
   confirms the aggregate window is exactly 60 frames; `mount`'s 2.00 is lever 3.

3. **`focusmap` = exactly 2 × `present` in both captures** (356/178 and 172/86).
   Two presented surfaces on every refresh — the workload and the lab overlay.
   This is the cleanest single proof that the overlay is a full second surface
   paying full surface costs, not a decoration.

4. **`Relayouts` equals `Updates` exactly in `mount.html`** — `/PerfWorkload/Rows`
   92 = 92, `/PerfLabOverlay/Dock/Panel` 39 = 39. Every engine-side update
   triggered a relayout; the engine batched nothing during the ramp. Worth a look
   as a separate question from anything L-29 touched.

5. **`mount.html` cannot rank LuauUI levers, and should not be used to.** Its
   frames run 287–306 ms (one `Steps Simulated: 16/167` frame = 696 ms) while the
   *entire* LuauUI phase inventory sums to ~1.5 s of a 17.2 s wall (**8.6 %**) and
   `Script_PerfLab` to 22.5 %. Roughly half the wall is not inside any named scope
   at all. `mount-ramp`'s cost is dominated by work outside every LuauUI phase
   scope — most plausibly view-tree construction in the pass and engine-side
   Instance creation — and until an instrument can see it, `mount.html` answers
   "how slow is the ramp" but not "which LuauUI phase to fix".

6. **`Script_PerfLab` is only 27 ms in `resize.html`** against 3 865 ms in
   `mount.html`. In the resize capture essentially all LuauUI work runs off the
   Heartbeat connection, not under the pass's script bar — so a reader triaging
   that capture by "which script is hot" would conclude LuauUI costs nothing and be
   wrong by 8 000 ms. Recorded because that is a trap the next reader will walk
   into.

7. **`LocalizationService::attemptLocalization` fires 762 times (110.7 ms) in
   `resize.html` and 3 541 times (423.9 ms, 2.5 % of wall) in `mount.html`.**
   Not a LuauUI scope and not investigated here; recorded because a per-label
   localization attempt on every mount is the kind of cost that scales with row
   count and nobody is watching it.

8. **Neither capture is GPU-bound, by a wide margin.** `RenderTotalTime` 22.87 ms
   and 23.74 ms, `GPU Time` ~21.5 ms, against frame times of 173 ms and 287 ms.
   On this device the entire performance question is main-thread CPU layout. Any
   future proposal that trades CPU layout for GPU work is trading in the right
   direction.

---

## Files

* `resize.html` → `resize-relayout` / `resizeStorm`, 60-frame aggregate window,
  30-frame event ring, 173.2 ms/frame.
* `mount.html` → `mount-ramp` / `ramp`, 60-frame aggregate window, 30-frame event
  ring, 286.8 ms/frame.

Both were taken with the **Profile** button (one looped pass), per
`docs/guide/12-performance-lab.md` §12.4 and
`docs/handoff/2026-08-13-microprofiler-capture.md`.
