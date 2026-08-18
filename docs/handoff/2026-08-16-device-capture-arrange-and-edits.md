# Device capture — the two levers, now that they have workloads (2026-08-16)

> **UPDATE 2026-08-15 — LEVER 1 IS FIXED; THIS PAGE'S `deep` NUMBERS ARE THE
> "BEFORE".** The candidate mechanism named at the bottom of this page was
> confirmed by instrumenting the cache key (16.33 distinct offered heights per
> node against 1.00 distinct width and 1.00 distinct scope) and repaired. Tier 2,
> Studio, ABBA, A/A control 1.74 %: **`deep` −82.5 %, `deepScroll` −82.2 %,
> `scroll` −13.4 %**, every other arm inside the control band; the measure
> fan-out at depth 30 goes **17.33 → 1.95** per arranged node and no longer rises
> with depth at all. Full method, differential-oracle proof and mutation table:
> `artifacts/performance-stress-places/optimization-log.md` **L-37**.
>
> **The capture is still worth taking**, and its question has changed: the shape
> to look for is now `deep ≈ flat` rather than `deep ≫ fill`, and the open
> question is whether `MEMO_ARM_DEPTH = 4` — a break-even swept on this laptop —
> is the right threshold on ARM. Lever 2 (`edit-locality`) is untouched by any of
> this and its section below stands as written.

You asked: *"Do we have a perf test for incremental layout and to gather info on
how to optimize arrange?"* The answer was **no, for both**. It is now yes, for
both. This is how to run them.

Everything below was measured here (**tier 2 — real engine, real Luau VM, this
laptop**) and headlessly (**tier 1 — regression signal only**). **A device
capture is the only thing that makes any of it a device claim.** Two specific
numbers a handset is likely to disagree with are named at the bottom, so the
capture has a question rather than just a dump.

## First: reopen the place

`examples/places/Facet-PerformanceLab.rbxl` has been rebuilt from current
source. **Close the copy you have open without saving and open the rebuilt
file.**

It now declares **sixteen** workloads. The two new ones sit just above
`lifecycle-soak` at the end of the cycler:

- **`arrange-shapes`** — nine arms, one per tree shape
- **`edit-locality`** — five arms, one per (edit location × reuse path)

## What changed about how you press the buttons

Two things, both because the old shape could not answer the question:

1. **An arm is now a PASS, not a loop inside a pass.** One lap = one arm. The
   `variable-extents` dump could never work: one lap there is 5 arms × 108
   frames = 540, and a MicroProfiler window is 60. Here one lap is 24 frames.
2. **There is a new `Arm >` button** in the action grid, next to `Profile 1`.
   It does not start anything — it just moves a pointer to the next arm and
   says so on the status line (`arm 4/9: deepScroll — press Profile 1`).
   `Profile 1` then loops that arm. Two buttons because `Profile 1` runs until
   Stop, and one button that both advanced the arm and started a run would race
   the loop it had just started.

The arm name goes into `workspace.Facet_ProfilingPass` automatically, so no
dump has to be identified by forensics.

## The capture, step by step

1. Open the rebuilt place, press **Play**.
2. Cycle to **`arrange-shapes`**.
3. Press **Profile 1**. Watch the status line. It should read:

   ```
   PROFILING arrange-shapes/flat · lap 2 · arrange=24 mount=0 react=26 resource=0 — DUMP NOW: ...
   ```

   **`arrange=24` is the number that matters before you spend a dump.** If it
   reads `arrange=0` or `arrange=1`, stop — the lap is inert and the capture
   would be worthless (that is exactly what happened to `asyncImage.html`).
4. Let it run three or four laps, then **Ctrl+F6** (**Cmd+F6** on macOS),
   **Ctrl+P** to pause, then **Dump → Dump in binary format**.
5. Press **Stop**.
6. Press **Arm >** three times — the status line should read
   `arm 4/9: deepScroll`. Actually, press it **twice** to land on `deep`
   (`arm 3/9`). Press **Profile 1**, dump again.
7. If you have patience for a third: **Arm >** once more to `deepScroll`, dump.
8. Cycle to **`edit-locality`**, press **Profile 1** (it defaults to
   `editOffWindowIncremental`), dump. Then **Arm >** twice to `editOffWindow`
   and dump that one too — that pair is the whole A/B.

**Two dumps is the minimum that answers anything** (`arrange-shapes/flat` and
`arrange-shapes/deep`). Five is the full picture.

## What the numbers should look like

A handset will be several times slower in absolute ms. What should hold is the
**shape** — the ordering and the ratios.

### `arrange-shapes` — every arm is 240 leaves, only the tree differs

The A/A control first, because nothing below it is a result without it: `flat`
and `flatRepeat` are the *same arm run twice*, and here they differ by **2.3 %**.
Anything smaller than that is noise.

| arm | µs per arranged node | vs `flat` | measures per arranged node |
|---|---:|---:|---:|
| `flat` (control) | **1.196** | — | 2.00 |
| `flatRepeat` (A/A) | 1.224 | +2.3 % ← **the noise band** | 2.00 |
| `zstack` | 1.295 | +8 % | 2.99 |
| `wrap` | 1.288 | +8 % | 2.00 |
| `scroll` | 1.811 | **+51 %** | 1.99 |
| `fill` | 3.014 | **+152 %** | 2.99 |
| `deep` | 10.355 | **+766 %** | **16.39** |
| `deepScroll` | 14.971 | **+1152 %** | 16.33 |

**The headline: nesting is what makes arrange expensive, and it is not the
placement — it is re-measuring.** The same 240 leaves cost 8.7× more per node
when they hang under 30 nested stacks than under one, and the mechanism is in
the last column: a flat tree measures each node twice, a 30-deep tree measures
it **sixteen** times. Every enclosing level re-measures the subtree below it.

**What should hold on the device:** `deep` ≫ `fill` > `scroll` > `flat`, and
`deep`'s measure ratio at ~16. **What would be a surprise worth knowing:** if
`fill` closes the gap on `deep` (that would mean the handset's cost is the
distribution arithmetic and the `table.sort` in it, not the re-measuring), or if
`text` — which this laptop cannot price honestly, because headless text metrics
are a stub — turns out to dominate everything.

**`deepScroll` was a refuted hypothesis, kept on purpose — and it is where the fix
started.** The measure cache in the solver only armed itself when the tree
contained a ScrollView, so putting the deep tree inside one was expected to
collapse that 16× fan-out. It did not: the uncached-measure count went 4 425 →
4 426, i.e. **the cache produced zero hits**, and the scroller's own double
measurement made the arm 45 % *slower*. Instrumenting the key showed why — it
carried the offered height, which a nested chain varies at every level and which
those nodes' answers never read. Fixed 2026-08-15 (L-37): both arms now sit within
1.4× of the `flat` control.

### `edit-locality` — does incremental layout help on a collection edit?

A/A control: two identical `reuse=off` arms differ by **4.1 %**.

| | full solve | with incremental layout | change |
|---|---:|---:|---:|
| off-window edit (a row inserted ~475 rows below the window) | 0.331 ms | **0.218 ms** | **−34 %** |
| in-window edit (one visible row's value) | 0.335 ms | **0.221 ms** | **−34 %** |
| nodes arranged | 101 | **2** / 5 | −98 % |
| nodes skipped | 0 | **99** / 96 | — |

**L-27 found incremental layout inert on a resize. On a collection edit it
bites, hard.** A resize changes every constraint so nothing can be reused; an
edit below the window changes one number and 99 of 101 subtrees land on exactly
the rect they had.

**And here is the thing that reframes the last three capture sessions: the lab
has been running with incremental layout switched OFF.** The framework ships it
ON (a surface opts *out*); the lab's own selector defaults to off. So
`collectionChurn.html`'s 26 solves at 9.384 ms each were 26 *full* solves in a
configuration your players never run.

**What should hold on the device:** `arranged` drops from ~101 to ~2, and the
time drops by more than the 4 % control band. **What would be a surprise:** the
node count drops and the time does not. That would say arrange is not where the
edit's cost is on ARM — which is checkable, because the same dump has
`Facet/measure` and `Facet/commit` beside it.

## If you want more samples

Both workloads' passes take `frames/reps`. The defaults are 60/24, which is one
lap per ~24 frames. On a device, raising reps narrows the control band:

```
step: pass:flat=60/60
step: pass:editOffWindow=60/60
```

(through `workspace.FacetScenarioAPI.step`; or just press `Profile 1` and take
the defaults.)

## The two questions this capture is actually asking

1. ~~**Is the 16× measure fan-out at depth the real arrange lever on ARM?**~~
   **ANSWERED AND FIXED (L-37, 2026-08-15).** The cache key did include the
   offered height and did miss every time — confirmed by counting distinct key
   terms per node, not by reading the code. The remaining ARM question is
   narrower: the memo now arms on nesting at `MEMO_ARM_DEPTH = 4`, a break-even
   swept on this laptop, and a device dump of these same arms is what would
   confirm the threshold on the hardware that matters.
2. **Should incremental layout be on by default in the lab — and is it already
   earning its keep in the game?** It is ON in production and OFF in every
   measurement we have taken, which means the log's collection numbers describe
   a configuration nobody ships. A device dump of the pair settles what it is
   worth on the hardware that matters.

Full analysis, control bands, mutation evidence and method:
`artifacts/performance-stress-places/optimization-log.md` **L-36**.
