# Device MicroProfiler capture, 2026-08-15 — the collections round, priced

**Evidence tier: 3 — physical device**, and therefore authoritative over every
headless (tier 1) and Studio (tier 2) number in `optimization-log.md`. Four binary
MicroProfiler dumps taken by the game director on the same handset as the
2026-08-14 pair, from `LuauUI-PerformanceLab.rbxl`.

| | |
|---|---|
| device | Samsung **SM-A102U1** (Galaxy A10e), Android 11 — verified in every blob's own device record |
| CPU / GPU | ARM, 8 cores · Mali-G71, Vulkan 1.1, 64 MB VRAM |
| system memory | **1 708 MB** |
| display | 698 × 1513 @ ScreenDpiScale 1.9375, QualityLevel 3 (auto) |
| client | Version 734, Release, `Technology=Unified`, `LightingStyle=Soft` |
| captures | `variableExtent.html`, `tableUnified.html`, `asyncImage.html`, `collectionChurn.html` |

---

## 0. The headline, up front

| question asked | answer |
|---|---|
| Are all four usable? | **Two are evidence, one is half-evidence, one is a lab defect.** `collectionChurn` and `variableExtent` are evidence; `tableUnified` proves the workload ran but carries **no timings at all** (its aggregate window is zero frames); `asyncImage` is **twenty-nine byte-identical frames of a pass that does nothing** — the third aiming failure in this lab's history. |
| Does the device agree with the +96% measured-extent number? | **The instrument cannot answer it, and it never could.** One `extentArms` lap is ~540 frames across five arms; a MicroProfiler window is 60. The dump landed inside one arm's *edit* phase and nothing in the dump names which arm. The arm-level numbers exist — the pass computes them — but they live in the pass's return value, not in the dump. |
| Does the device confirm the Table's 0-arrange range selection? | **No — `tableUnified.html` carries no aggregate at all.** Its event ring landed in a uniform stretch (2 arranges/frame, 29 of 29 frames), not on the `select` reps. |
| Is `$newindex` still the top lever? | **Unanswerable from a device dump.** `$newindex` is present as a registered timer in all four blobs with **count = 0** in every one. Roblox client dumps do not populate Luau function-level scopes; L-33's 626 writes/frame came from LibMP in Studio and only Studio can re-measure it. |
| What is the top cost, and is it ours? | **`LuauUI/arrange`, in all four captures, by a wide margin** — 28.3 %, 19.6 % and (composed) ~44 % of wall respectively, worst single occurrence **298.87 ms**. It is ours, it is `src/layout/solver.luau`, and it is **not touched here**: another agent is live in that file. Evidence routed, not acted on. |

**The one new framework finding the captures do support**, and it is a good one:
> **25 inserts into a 2 000-row virtual list, at an index ~475 rows outside the
> mounted window, provoke ZERO structural syncs and 26 full solves — and all 25
> land inside ONE 557 ms frame.** The mounting is proportional to visible content
> exactly as the workload's question demands; the *solving* is not.

---

## 1. Method, and the two places it differs from 2026-08-14

Decode is as recorded in `device-capture-2026-08-14.md` §2 (base64 in an HTML
comment → zlib → aggregate timer table of 80-byte records at `header[0x50]`,
names `\0`-terminated in the tail string blob). Two corrections and one addition:

1. **The event log's `u16` token is the record's `id` field, NOT its array
   index.** `id != index` for every record in these blobs (index 3 carries id 0 =
   `MicroProfileFlip`). Mapping by index silently attributes every `LuauUI/*`
   scope to its neighbour: `LuauUI/measure` and `LuauUI/arrange` read **zero**
   tokens while `LuauUI/mount` read 120. Any past event-log reading taken by index
   is wrong by one or two rows.
2. **The event log is three parallel columns of equal length**, delimited by
   header start/end pairs: a `u8` column at `0x80..0x84`, a `u64` timestamp column
   at `0x88..0x8c`, a `u16` token column at `0x90..0x94`. All three hold exactly
   the same entry count (52 144 / 60 207 / 52 293 / 112 039 here). **Enter/leave
   pairing across the flat array does not work** — the `u8` column is not a clean
   type or thread id and per-scope *durations* remain unrecoverable from the log,
   exactly as 2026-08-14 recorded. **Occurrence COUNTS are recoverable and exact.**
3. **New: per-frame attribution.** `queuePresent` fires exactly once per frame and
   reads **30 occurrences in all four rings**, so the ring is 30 frames in every
   capture and events between consecutive `queuePresent` entries belong to one
   frame. That is what produces the per-frame histograms below, and it is the
   instrument that identified both lab defects.

**Cross-checks that make the decode trustworthy rather than plausible.** The
event-log counts and the aggregate counts agree per frame on all three captures
that have both: `variableExtent` arrange 61/60 frames (aggregate) against 30/30
frames (ring) — 1.02 vs 1.00 per frame; `asyncImage` 1.77 vs 2.00. And the
headless probe `tools/lune/_probe_profile_aim` reproduces the device's per-frame
histogram **to the unit** on `collection-churn/insert` (26 arrange, 26 measure,
52 commit, 0 mount, device and Lune alike) and on `async-image-churn/imagesCold`
(1 arrange, 0 mount, 0 resource; the device reads one higher on each solve scope
because it carries the lab overlay as a second surface).

**Frame period** is taken from consecutive `queuePresent` entries in the ring.
Where a capture's ring and aggregate disagree about *rates* (see §5) the ring is
used for occurrences-per-frame and the aggregate for ms-per-occurrence, and no
number multiplies one by the other without saying so.

---

## 2. Per-file usability verdict

| file | workload identity, from the blob | aggregate | ring | verdict |
|---|---|---|---|---|
| `variableExtent.html` | surface **`LuauUI_ExtentArm`**, `/ExtentArm/ExtentRows` | **60 frames**, all scopes populated | 30 frames @ **37.97 ms** | **EVIDENCE**, with a caveat: it samples one *unidentifiable* arm's edit phase |
| `tableUnified.html` | surface **`LuauUI_TableUnified`** | **0 frames — every timer reads zero** | 30 frames @ **99.95 ms** | **HALF-EVIDENCE**: the workload demonstrably ran; no timing survives |
| `asyncImage.html` | **no LuauUI surface name, no engine layout counters** | 60 frames | 30 frames @ **47.46 ms** | **NOT EVIDENCE — lab defect** |
| `collectionChurn.html` | surfaces **`LuauUI_PerfWorkload`** + `LuauUI_PerfLabOverlay`, `/PerfWorkload/Rows` | 60 frames | 30 frames @ **557.06 ms** | **EVIDENCE** (and the most informative of the four) |

### `tableUnified.html` — why it has no numbers

`header[0x20]`, the aggregate frame window, is **0**. The timer table is present
and correctly named (1 332 records) and every `total`, `worst` and `count` in it
is zero. This is not a decode failure and not a workload failure: the
MicroProfiler's aggregate accumulator had collected no frames when the dump was
taken, while the event ring had. It is a **capture-procedure** difference from the
2026-08-14 pair (both `0x20 = 60`), not a code defect.

What survives is real and worth keeping:

```
Context=Rendering  Cause=LuauUI_TableUnified  Root=LuauUI_TableUnified  Relayouts=6  Updates=57  Resizes=71
Context=Rendering  Cause=LuauUI_TableUnified  Root=LuauUI_TableUnified  Relayouts=0  Updates=57  Resizes=0
```

and a 30-frame ring at **99.95 ms mean / 104.40 ms median** per frame, whose
per-frame shape is near-constant: **2 arranges, 2 measures, 2 reacts, 1 mount, 3
commits, 2 presents**, on 26 of 29 frames, with three isolated frames at zero
arranges. `focusmap = 2 × present` (120/60) confirms two presented surfaces, as
in every previous capture.

**It does not confirm or refute the 0-arrange range selection.** `selectRange`'s
12 reps are 12 of a ~116-frame lap and the ring did not land on them. The
handoff's invariant (`selectRange` reports `arrangesPerRep` of 0) remains a
tier-2 Studio claim.

### `asyncImage.html` — not evidence, and the reason is a lab defect

Twenty-nine consecutive frames, **byte-identical**:

```
frame:   arrange  measure  react  mount  commit  present
 0..28:        2        2      2      0       3        2
```

Zero mounts. Zero `LuauUI/resource`. Zero `LuauUI/reset`. No `Context=` layout
counter emitted for any LuauUI root. Nothing in this capture is image work.

**Cause, from source and confirmed headless.** `profileWindow` loops
`w.passes[1]`, and `async-image-churn` declares
`{ imagesCold, imagesWarm, imagesFail, imagesReuse }`. `imagesCold`'s entire body
is `settings.resourceState = "cold"` followed by one `presenter.refresh()`.
Looped, it re-sets a flag that is already set. `tools/lune/_probe_profile_aim`
prices all four passes per lap:

| pass | arrange | measure | mount | react | commit | resource |
|---|---:|---:|---:|---:|---:|---:|
| `imagesCold` | 1 | 1 | **0** | 3 | 2 | **0** |
| `imagesWarm` | 1 | 1 | **0** | 3 | 2 | **0** |
| `imagesFail` | 1 | 1 | **0** | 3 | 2 | 2 |
| **`imagesReuse`** | **9** | **9** | **8** | 11 | 18 | 0 |

Only `imagesReuse` churns the window. The other three are one-shot **state
changes**, meaningful in the declared order `steps.run()` executes and meaningless
on a loop.

This is the **third** aiming failure in this lab's history and it is a new class.
The first two are already guarded (`dense-scroll-native` has no framework in it;
`steps.run()` cannot escape pass #1). This one is a pass that is legitimate inside
its sequence and inert on a loop. **Fixed — see §6.**

---

## 3. Per-scope tables

Occurrences per frame and ms per occurrence are exact (the 60-frame aggregate
window is confirmed by `LuauUI/tick` = 60 and `queuePresent` = 60 in every file).
`% wall` uses the ring's frame period × 60 and is therefore an estimate; it is
omitted for `collection-churn`, where ring and aggregate disagree about rates
(§5). `measure` and `arrange` are siblings inside one `solve()`, so their shares
add; `focusmap` is nested inside `present`.

### `variableExtent.html` — `variable-extents` / `extentArms`

60-frame window, 37.97 ms/frame → **2 278 ms wall, 26.3 fps**.
`RenderTotalTime` mean **18.35 ms** — not GPU-bound.

| scope | occ | occ/frame | total ms | ms/occ | % wall | worst ms |
|---|---:|---:|---:|---:|---:|---:|
| `arrange` | 61 | 1.02 | 644.7 | **10.569** | **28.3 %** | 22.60 |
| `measure` | 61 | 1.02 | 290.8 | 4.767 | 12.8 % | 14.95 |
| `react` | 73 | 1.22 | 203.8 | 2.792 | 8.9 % | 13.00 |
| `present` | 120 | 2.00 | 188.1 | 1.568 | 8.3 % | 8.89 |
| `commit` | 121 | 2.02 | 110.7 | 0.915 | 4.9 % | 8.29 |
| `mount` | 13 | 0.22 | 64.4 | 4.953 | 2.8 % | 14.47 |
| `focusmap` | 240 | 4.00 | 30.1 | **0.125** | 1.3 % | 1.84 |
| `tick` | 60 | 1.00 | 3.9 | 0.065 | 0.2 % | 0.32 |
| `scenario` | 60 | 1.00 | 1.0 | 0.016 | 0.0 % | 0.07 |
| `mutate` | 0 | — | 0.0 | — | 0 % | — |
| `resource` / `reset` | — | — | — | — | — | never registered in this session |

### `asyncImage.html` — `async-image-churn` / `imagesCold` (NOT EVIDENCE)

Recorded so the shape of an inert capture is on file next to a live one.
60-frame window, 47.46 ms/frame → 2 848 ms wall.

| scope | occ | occ/frame | total ms | ms/occ | % wall | worst ms |
|---|---:|---:|---:|---:|---:|---:|
| `arrange` | 106 | 1.77 | 558.5 | 5.269 | 19.6 % | 29.95 |
| `measure` | 106 | 1.77 | 449.5 | 4.240 | 15.8 % | 26.47 |
| `commit` | 166 | 2.77 | 155.7 | 0.938 | 5.5 % | 5.95 |
| `present` | 120 | 2.00 | 150.6 | 1.255 | 5.3 % | 16.07 |
| `focusmap` | 240 | 4.00 | 17.0 | 0.071 | 0.6 % | 1.57 |
| `react` | 106 | 1.77 | 7.0 | 0.066 | 0.2 % | 0.38 |
| `tick` / `scenario` | 60 / 60 | 1.00 | 5.8 / 1.1 | — | 0.2 % | — |
| **`mount` / `resource` / `reset` / `mutate`** | **0** | **0** | **0.0** | — | **0 %** | — |

**Four zeros is not health here.** 2026-08-14 recorded the rule: two zeros in
scopes that structurally cannot fire is a healthy capture; nine of twelve is a
missed window. `async-image-churn` is the workload whose entire subject is the
resource path, and `LuauUI/resource` reads zero.

### `collectionChurn.html` — `collection-churn` / `insert`

60-frame aggregate; ring 30 frames @ **557.06 ms mean / 572.72 ms median** →
**1.8 fps**. `RenderTotalTime` mean 33.97 ms — not GPU-bound, by 16×.

| scope | occ | total ms | ms/occ | worst ms |
|---|---:|---:|---:|---:|
| `arrange` | 343 | 3 218.9 | **9.384** | **298.87** |
| `measure` | 343 | 1 044.3 | 3.044 | 93.78 |
| `present` | 386 | 912.9 | 2.365 | 80.22 |
| `react` | 351 | 909.1 | 2.590 | 84.27 |
| `commit` | 681 | 405.7 | 0.596 | 49.62 |
| `scenario` | 61 | 53.9 | 0.884 | 52.55 |
| `focusmap` | 772 | 36.2 | **0.047** | 3.29 |
| `tick` | 60 | 7.4 | 0.123 | 1.48 |
| `reset` | 1 | 7.0 | 7.039 | 7.04 |
| `mount` | 3 | 5.2 | 1.725 | 5.17 |
| `resource` / `mutate` | 2 / 2 | 0.1 / 0.1 | — | — |

Engine scopes for scale: `Layout` 116.5 ms (354), `queuePresent` 413.1 ms,
`FMOD::Output::mix` 169.6 ms, `GC` 105.6 ms.

---

## 4. `collection-churn` is the capture that earns its keep

Per-frame histogram, **29 of 29 frames identical**:

```
frame:   arrange  measure  react  mount  commit  present
 0..28:       26       26     26      0      52       26
```

`passes.insert` performs 25 iterations of `table.clone` → `table.insert` at
`#list * 0.25` → `rowsSignal:set(list)` → `presenter.refresh()`, **with no yield
inside the loop**; `profileWindow` yields once per lap. 25 + 1 = **26**. The
headless probe returns 26 / 26 / 52 / 0-mount for the same pass. Two instruments,
one answer, and the composition is internally consistent: 26 × 9.384 ms = 244 ms
of `arrange` inside a 557 ms frame — **~44 % of the frame in one scope.**

Three things fall out of it, and they are not the same thing:

1. **The mounting is right.** `LuauUI/mount` = **0** across all 29 frames. Twenty-
   five inserts at logical row ~500 of 2 000, with the window at the top, provoke
   **not one structural sync**. The workload's own question — *"do updates stay
   proportional to changed and visible content?"* — is answered **yes for
   materialisation**, on hardware, at 2 000 rows.
2. **The solving is not.** Each of those 25 inserts costs a **full solve** of the
   surface: 26 arranges, 26 measures, 52 commits. An edit that changes nothing any
   mounted row displays still re-derives every rect. This is the same frontier
   L-30 named for the resize path, reached from a completely different direction,
   and it is the honest reason the frame is 557 ms.
3. **"It didn't do anything visually" is fully explained, twice over** — the
   insertion point is ~475 rows below the last mounted row, so there is nothing to
   repaint; and at 1.8 fps with the whole lap in one frame, a screen that did
   repaint would still read as frozen. The workload is *not* broken. It is coarse:
   one lap = one frame, which is the shape the log already recorded for
   `resizeStorm` and `ramp` (the passes that hung the phone in 2026-08-13).

**`arrange`'s worst single occurrence is 298.87 ms** — 54 % of an already
catastrophic frame in one call, and the largest single-occurrence figure ever
recorded in this lab (L-30's resize tail was 131.23 ms).

---

## 5. `variable-extents`: what the capture does and does not settle

The ring's per-frame histogram identifies the **phase** unambiguously:

```
frames  0..22:  1 arrange  1 measure  1 react  0 mount  2 commit  2 present
frames 23..28:  1 arrange  1 measure  2 react  1 mount  2 commit  2 present
```

Twenty-three frames with **zero structural syncs** cannot be the scroll phase (a
40 px step re-windows). They are `sameCountEdit`'s 24 reps — one row's `value`
changes, no row count changes, nothing remounts. Frames 23+ pick up exactly one
`mount` per frame: `growEdit`'s 24 reps, which append a row and therefore change
the canvas and the window. The 23 / 6 split matches the pass's 24 / 24 structure.

**The device confirms L-33's zero-extra-solve claim.** Arrange is **exactly 1.00
per data edit** across 29 consecutive frames, in both the cache-hitting
(`sameCount`) and the cache-missing (`grow`) case. L-33 recorded
`arrangesPerGrow = 1.00` at tier 1; it now holds at tier 3, and it holds while a
structural sync is also happening.

**The device cannot confirm or refute the +96 % measured-extent number, and no
device dump ever could.** One `extentArms` lap is five arms × (24 + 24 + 60)
= **540 frames**; a MicroProfiler aggregate window is 60 and the event ring is 30.
The window lands inside one arm, and **nothing in the dump names which arm** —
every arm mounts the same surface id (`LuauUI_ExtentArm`), the same
`/ExtentArm/ExtentRows` canvas, and the engine layout counters are
indistinguishable between them (six `Cause=LuauUI_ExtentArm` rows, Relayouts
4–7, Updates 58–61).

This is an **instrument mismatch, not a missing measurement**. The arm-level p50s
and the `harnessSpreadScrollMs` / `harnessSpreadGrowMs` control bands the whole
comparison rests on **are computed** — by the pass, every lap — and they are
returned to the caller. They simply are not in the binary dump, and the person
holding the phone has no way to read them. Until that is closed, the `+96 %`
scroll-step cost of `itemExtent = "measured"` and the `+27–40 %` steady-state
residual remain **tier 1** (`artifacts/variable-item-extents/perf.md`), and the
justification for making `"measured"` opt-in rests on a headless number with a
1.6 % A/A control — which is a good number, honestly labelled, and not a device
claim.

**What a device capture of this would take:** the arm's own p50s put somewhere a
phone can show them. That is the same gap `lapWork` (§6) opens the door on and
is named as a residual rather than built here.

---

## 6. The lab defects found, and what was done

### D1 — `profileWindow` looped a pass that does nothing. FIXED.

`profileWindow` defaulted to `w.passes[1]`, which for `async-image-churn` is
`imagesCold`. Two changes, both in `examples/performance/lab/perf_lab.luau`,
neither touching any workload's `passes` list (so `SCENARIO_VERSION` does **not**
move and `tools/check_perf_captures.py` stays PASS at 18 admissible rows — L-33's
ruling on additive changes applies unchanged):

1. **`profilePass` on the workload declaration**, set to `"imagesReuse"` for
   `async-image-churn`. An explicitly named pass still overrides it.
2. **`lapWork` — the scope deltas of the last lap**, returned by `profileWindow`
   and written to the overlay's status line every lap:
   `arrange=9 mount=8 react=11 resource=0`. A lap reading `arrange=1 mount=0` is
   now visible **on the phone, before the dump is taken**, instead of after a
   binary blob has been parsed on a laptop.

   A **readout, not a refusal**, deliberately: `idle-baseline` is a legitimate
   zero, and a threshold separating "inert" from "cheap" would be a number
   invented rather than measured. `lapWork.measured` is the honesty field —
   `cleanCapture` turns phase scopes off, and a bare `mount=0` in that
   configuration would accuse a healthy pass of exactly this defect.

**Tests** (`tests/perf_lab.spec.luau`, four new cases in
*"profileWindow cannot be aimed at a pass that does nothing (device capture 5)"*,
sited with the two existing aiming guards), **mutation-proved one at a time**:

| mutation | result |
|---|---|
| M1 — delete `profilePass = "imagesReuse"` | *"loops the workload's declared PROFILE pass"* ✗, other three ✓ |
| M2 — `work.measured = true` unconditionally | *"says the readout is UNMEASURED…"* ✗, other three ✓ |
| M3 — lap delta computed as `after - after` | *"reports what ONE lap provoked"* ✗, other three ✓ |

Each mutation reddened exactly its own case and nothing else.

### D2 — `collection-churn`'s `insert`/`remove`/`reorder` run a whole lap in one frame. NOT FIXED, deliberately.

Quantified above: 26 solves, 557 ms, one frame. The obvious fix is the pattern the
lab already uses everywhere else (`extentArms`, `tableUnified.verb`,
`scrollSteady`): time each rep between `clock()` calls, `telemetry.step()`
*outside* the timed region, report `summarize(samples)` and `arrangesPerRep`.

**It is not taken here because it changes the workload's STEPS**, which by this
log's own rule (L-33) requires bumping `SCENARIO_VERSION` — and that immediately
declares all **18** admissible Studio capture rows to describe a workload that no
longer exists, with no way to re-take them in this session. The trade is a lab
ergonomics win against discarding eighteen real measurements of unchanged work.
L-33 faced the same choice and refused the bump; the same answer holds. **Named
as a residual, with the diff already designed.**

### D3 — a 60-frame window cannot aim at a 540-frame pass. NOT FIXED, named.

`extentArms` (540 frames/lap, 5 arms) and `tableUnified` (~116 frames/lap, 5
phases) both compute their headline numbers and both put them out of a binary
dump's reach. `profileWindow`'s `lapWork` is the seam a fix would extend: the pass
already returns a result table, and the status line is already the thing the
person holding the phone reads. Surfacing a pass's own headline p50s there would
make a device capture of §5 possible for the first time. Named, not built — it is
a lab feature, not a patch.

---

## 7. Levers, ranked, and what was deliberately not touched

### Lever 1 — `arrange`. Top cost in all four captures. NOT TOUCHED.

| capture | ms/occ | occ/frame | share of frame | worst |
|---|---:|---:|---:|---:|
| `collectionChurn` | **9.384** | 26.0 | **~44 %** (composed) | **298.87 ms** |
| `variableExtent` | **10.569** | 1.02 | 28.3 % | 22.60 ms |
| `asyncImage` (inert) | 5.269 | 1.77 | 19.6 % | 29.95 ms |
| `resize.html` (2026-08-14) | 9.136 | 7.12 | 37.5 % | 131.23 ms |

`arrange` is between **9.1 and 10.6 ms per occurrence on this handset across four
independent workloads and two capture sessions** — a remarkably stable number, and
one that does not depend on what provoked the solve. It is 2–3× `measure` per
occurrence everywhere, so the cost remains rect derivation and stack distribution
rather than text metrics, exactly as L-30 concluded.

**Not touched, and this is a routing decision rather than a judgement:**
`arrange()` lives in `src/layout/solver.luau`, which another agent is currently
editing (`UI.Grid` column-major wrapping). The evidence above — and specifically
the **298.87 ms tail**, which is new and 2.3× the previous worst — is the thing to
hand that agent, or to schedule after them.

### Lever 2 — a data edit that changes no visible row still costs a full solve.

`collection-churn` prices it: 25 off-window inserts, 0 structural syncs, **26 full
solves**. `variable-extents` prices the floor: **exactly 1 arrange per edit**, which
is already minimal *per edit* — so the lever is not "fewer solves per edit", it is
"a solve that skips subtrees whose constraints did not move". L-27 measured
incremental layout as inert on a *resize* (2 partial solves of 65, because a resize
changes every constraint). **A collection edit is the opposite case** — one row's
data moved and the viewport did not — and no capture in this log has ever measured
incremental layout on it. That is the next honest question, and it is the same
file as lever 1.

### Not a lever — `focusmap`, again.

**0.125 ms/occurrence** (`variableExtent`) and **0.047 ms/occurrence**
(`collectionChurn`, over 772 occurrences), 1.3 % and 0.1 % of frame. L-27's
`structureEpoch` cache holds on a container that restructures constantly, on a
handset. Third capture session in a row.

### Cannot be resolved — `$newindex` (L-33 residual 2).

`$newindex` and `$index` appear as **registered timers with count 0 in all four
blobs**, and **no `$`-prefixed timer has a non-zero count in any of them**. Roblox
retail client dumps do not populate Luau function-level scopes; L-33's
79 538 writes / 127 frames came from LibMP inside Studio. **The device instrument
does not contain this cost, so it cannot report it.** L-33 residual 2 stays open
and is a Studio + LibMP question, not a device one. Nothing here says the finding
is wrong — only that this capture cannot see it.

---

## 8. Anomalies worth keeping

1. **The event-log token is an `id`, not an index** (§1). This invalidates any
   past claim taken from the event log by index.
2. **`tableUnified.html`'s aggregate window is 0 frames.** A dump can carry a full
   event ring and an entirely empty aggregate. Check `header[0x20]` before reading
   a timer table, or a legitimate capture reads as twelve zeros and gets filed as
   a workload defect.
3. **`collectionChurn`'s ring and aggregate disagree about rates by 4.6×** (26.0
   vs 5.72 arranges/frame). They are different windows: the aggregate accumulates
   from when it was armed, the ring holds the last 30 frames before the dump. Per-
   *occurrence* costs are unaffected; per-*frame* rates must come from the ring.
   Do not multiply an aggregate rate by a ring frame period.
4. **`focusmap = 2 × present` in all four captures** (240/120, 240/120, 120/60,
   1571/792). Two presented surfaces every refresh — workload plus lab overlay.
   Fourth session in a row; it remains the cleanest proof the overlay is a full
   second surface.
5. **`asyncImage.html` emitted no `Context=` engine layout counters at all**,
   while the other three did. A capture with no layout counters is a capture in
   which the engine relaid nothing out — worth treating as a first-pass liveness
   check on any future dump.
6. **`variableExtent` never registered `LuauUI/resource` or `LuauUI/reset`** (the
   names are absent from its timer table entirely), while `asyncImage` registered
   both and then recorded zero. A scope name only appears once it has fired at
   least once in the session, so *absent* and *zero* mean different things.
7. **`LuauUI/scenario`'s worst occurrence is 52.55 ms in `collectionChurn`**
   against 0.010–0.019 ms elsewhere. The lab bootstrap's own per-frame scope
   absorbed one 52 ms frame. Not investigated; recorded because the instrument
   costing 52 ms once is worth knowing before it is quoted as workload time.
8. **Neither `collectionChurn` (33.97 ms `RenderTotalTime` against a 557 ms
   frame) nor any other capture here is GPU-bound.** Four sessions, eight
   captures, same verdict: on this device the whole performance question is
   main-thread CPU layout.

---

## Files

* `variableExtent.html` → `variable-extents` / `extentArms`, 60-frame aggregate,
  30-frame ring, 37.97 ms/frame. **Evidence** (one unidentified arm's edit phase).
* `tableUnified.html` → `table-unified` / `tableUnified`, **0-frame aggregate**,
  30-frame ring, 99.95 ms/frame. **Half-evidence** (ran; no timings).
* `asyncImage.html` → `async-image-churn` / `imagesCold`, 60-frame aggregate,
  30-frame ring, 47.46 ms/frame. **Not evidence — lab defect, fixed.**
* `collectionChurn.html` → `collection-churn` / `insert`, 60-frame aggregate,
  30-frame ring, 557.06 ms/frame. **Evidence.**

Decoder and probes: `tools/lune/_probe_profile_aim.luau` (per-lap scope deltas for
every pass of the captured workloads). Recorded as **L-35** in
`optimization-log.md`.
