# Device capture — the two new collection workloads (2026-08-14)

Everything below was measured in Studio on this laptop (**tier 2 — real engine,
real Instances**). **A device capture is the only thing that makes any of it a
device claim**, and there are two specific numbers a handset is likely to
disagree with. They are named at the bottom so the capture has a question, not
just a dump.

## First: reopen the place

`examples/places/Facet-PerformanceLab.rbxl` has been rebuilt from current source
(`rojo build examples/performance.project.json`). **Close the copy you have open
without saving and open the rebuilt file** — the open copy was live-patched
during this session's profiling.

The place now declares **fourteen** workloads. The two new ones are last but one
and last but two in the cycler:

- **`variable-extents`** — one pass, `extentArms`
- **`table-unified`** — one pass, `tableUnified`

## The capture, step by step

1. Open the rebuilt place, press **Play**.
2. Cycle to **`table-unified`** (start here — it is the more interesting of the
   two and the one with a real open question).
3. Press **Profile**, not `Run all`. Profile loops ONE pass, so the ~1.3 s dump
   window lands inside the workload you chose. Every rep yields a frame, so the
   screen repaints and the profiler has frames to sample — the two failures that
   made the 2026-08-13 captures unusable are both structurally impossible here.
4. Let it run three or four laps (the status line counts them).
5. **Ctrl+F6** (**Cmd+F6** on macOS) opens the MicroProfiler, **Ctrl+P** pauses,
   then **Dump → Dump in binary format**.
6. Repeat for **`variable-extents`**.

The workload identity is written into `workspace` attributes
(`Facet_ProfilingWorkload`, `Facet_ProfilingPass`, `Facet_ProfilingRows`,
`Facet_ProfilingTheme`) and warned to the console, so neither dump has to be
identified by forensics.

## What the numbers should look like

Studio, this laptop, flat package, 2 000 rows. A handset will be several times
slower in absolute ms; what should hold is the **shape** — the ordering and the
ratios.

### `table-unified`

| | Studio p50 | what it means |
|---|---:|---|
| scroll step (steady) | **0.45 ms** | 25 rows in the tree of 2 000 |
| 201-row range select across ~180 unmounted rows | **0.76 ms**, **0 arranges** | selection is model state; only mounting is windowed |
| `moveRow` on an unheld row | **5.6 ms** | ~1.2 solves |
| `revealRow` on an unheld row | **10.8 ms** | a full window replacement — a seek, not a scroll |

**`revealRow` being the most expensive verb by 2x is expected and correct.** For
comparison, `newVirtualList`'s equivalent seek (`dense-scroll` → `scrollSeek`)
costs **23.66 ms** worst-case here while windowing FEWER rows, so the Table is
already the cheaper of the two at this.

**The one number that must NOT move: `selectRange` must report `arrangesPerRep`
of 0.** Anything above zero means selecting a row started re-solving the surface,
which is the whole promise of the unified container failing.

### `variable-extents`

Read `harnessSpreadScrollMs` and `harnessSpreadGrowMs` FIRST. Any arm-to-arm
difference smaller than the matching spread is noise. On this laptop at 40 edits
they were 0.003 ms and 0.064 ms.

| | Studio |
|---|---|
| B (variable, flat) vs A (uniform), scroll step | no measurable cost |
| B vs A, grow edit (the O(N) prefix-sum build over 2 000 rows) | **+0.12 ms (+3.2 %)** |
| B vs A, same-count edit (the O(N) extent walk, cache hits) | **+0.17 ms (+5.5 %)** |
| arranges per grow edit | **1.00 in every arm** |

Arm C (ragged) is NOT a like-for-like — its rows are taller so it windows 19
against 33. Its cheaper scroll step is less work, not faster work.

## If you want more samples

Both passes take `frames/reps`. The default reps were deliberately raised after
the first cut's control band came out at 20 % — on a device, raise them further:

```
step: pass:tableUnified=30/40
step: pass:extentArms=60/60
```

(through `workspace.FacetScenarioAPI.step`, or just press Profile and accept the
defaults, which are 60/12 and 60/24.)

## The two questions this capture is actually asking

1. **Does instance recycling still buy a windowed Table almost nothing?** Here it
   served **1 648 of 6 821 creates (24 %) from the pool** and moved `revealRow` by
   **1.7 %** — against a 0.5 % A/A control band — while `moveRow`, the range select
   and the scroll step all stayed INSIDE their bands. On a flat `newVirtualList`
   recycling is worth **−32 %** (L-27). A handset's Instance-creation cost relative
   to its solve cost is not this laptop's, so this contrast is the single most
   likely thing to invert on a device. Take one dump with `recycle=on` and one with
   `recycle=off` (`step: select:recycle=off`) if you have the patience for two.

2. **Is `$newindex` still bigger than `arrange`?** The Studio capture counted
   **79 538 engine property writes across 127 frames — 626 per frame — costing more
   of the frame than `Facet/arrange`**. No framework scope can see any of it. If a
   device dump agrees, the property-write volume is the next lever and the property
   diff (L-18) needs its coverage on this path measured.

Full analysis, control bands and method:
`artifacts/performance-stress-places/optimization-log.md` **L-33**.
