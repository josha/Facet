# Unified collection — mutation evidence and perf numbers (2026-08-14)

Every new check was broken on purpose, watched to redden by NAME, and restored.
Method: patch one line in `src/controls/table.luau`, run the spec in isolation,
record which named case failed, restore from a byte copy taken before the run.

Framework spec: `tests/table_virtualized.spec.luau` (21 cases).
Consumer spec: `games/RascalRally/code/tests/luauui_racer_list.spec.luau` (2 cases).

## Framework — 20 mutations, 19 killed

| # | mutation | result | named case that reddened |
|---|---|---|---|
| M1 | `window()` ignores the viewport — mount every row | KILLED | a 400-row table mounts a bounded window |
| M2 | `window()` ignores the scroll — always the top of the list | KILLED | scrolling mounts the rows at the new offset |
| M3 | the canvas reports no content extent | KILLED | the canvas carries the FULL content extent |
| M4 | every row is painted at slot 1's offset | KILLED | every windowed row lands at the index's own offset |
| M5 | the index takes the FIRST row's extent for every row | KILLED | every windowed row lands at the index's own offset (ragged) |
| M6 | selection is mount state — a scroll clears it | KILLED | a selected row that scrolls away comes back selected |
| M7 | keep-visible refuses a row with no solved rect | KILLED | revealRow reaches a row with no solved rect |
| M8 | the insertion slot drops the live scroll (window-relative) | KILLED | a drag while scrolled names a slot two hundred rows down |
| M9 | the anchor re-apply never fires | KILLED | the row under the viewport's leading edge stays under it |
| M9b | the anchor re-apply compares the CLAMPED memo (the shrink defect returns) | KILLED | shrinking the rows at the BOTTOM leaves the list flush |
| M10 | the anchor captures against the NEW index (`clampedTop`, not `scrollTop`) | **SURVIVED** | — see below |
| M11 | a derived-height change REMOUNTS the rows (the key carries the height) | KILLED | FRAME ONE already fills the body (+ others) |
| M12 | `virtualized` + `scrolls = false` is quietly accepted | KILLED | `virtualized` + `scrolls = false` is refused |
| M13 | `virtualized` + `rowActions` is quietly accepted | KILLED | `virtualized` + `rowActions` is refused (v1) |
| M14 | the shared index drops the gap | KILLED | a FLOWING table's drop hairline is the index's own boundary |
| M15 | the range select is clipped to the mounted window | KILLED | multi-selection ranges reach rows the window never held |
| M16 | `moveRow` refuses a row outside the window | KILLED | a reorder addresses an unmounted row |
| M17 | the first-frame seed goes back to zero (the 3-row first frame) | KILLED | FRAME ONE already fills the body |
| M18a | `OVERSCAN` → 0 | KILLED | the row just BELOW the viewport is mounted |
| M18b | `OVERSCAN` → 4 | KILLED | the row just BELOW the viewport is mounted |
| M20 | `ROWS_REGION` forgets the Canvas segment (paths silently miss) | KILLED | a selected row that scrolls away comes back selected (+ others) |

### The one survivor, and why it is recorded rather than papered over

**M10 — the anchor captures from `scrollTop` (the raw engine mirror) rather than
from `clampedTop` (the memo that clamps it against the content). Swapping them
reddens nothing.**

Measured rather than assumed, in three steps:

1. Both spellings pass with the observers registered in either order, so it is
   not an ordering accident.
2. The reason: `clampedTop`'s clamp only BINDS at the end of the list. Growing
   the rows lengthens the content, the clamp does not bind, `clampedTop` never
   notifies, and the capture never fires on a geometry change either way.
3. So the distinguishing case would have to be **shrinking** the rows at the
   BOTTOM — and there the anchor is *supposed* to lose to the clamp, because
   holding the leading row would mean showing blank space past the last row. The
   case exists in the spec ("shrinking the rows at the BOTTOM leaves the list
   flush with its last row") and asserts that outcome; it cannot separate the two
   dependencies because both produce it.

`scrollTop` is kept because it is correct by construction — a geometry change
cannot fire it at all — and the code comment at SCROLL ANCHORING says exactly
that rather than claiming a behavioural difference that does not exist. Attempt
number three at that comment; the first two claimed a failure that measurement
did not support.

## Consumer (Rascal Rally) — 4 mutations, 4 killed

| # | mutation | result | named case |
|---|---|---|---|
| G1 | the shared index drops the gap — against the FLOWING differential oracle | **SURVIVED** (expected; see below) | — |
| G1' | the same mutation against the `virtualized` use-proof | KILLED | `virtualized` is a legal newTable key here |
| G2 | `virtualized` leaves the closed key set | KILLED | `virtualized` is a legal newTable key here |
| G3 | the `scrolls = false` refusal is dropped | KILLED | `virtualized` is a legal newTable key here |
| G4 | the canvas stops carrying the content extent | KILLED | `virtualized` is a legal newTable key here |

G1 survived on purpose and the spec says so in its own comment: a FLOWING table's
rows are positioned by the solver from the blueprint's `gap`, so that case is a
differential ORACLE (the index reproduces the solver's flow for this consumer's
exact `ROW_HEIGHT`/`ROW_GAP`) and not a use-proof. The use-proof is the second
half, added after G1 survived, and G1' is it reddening.

## Perf — the A/A control first

The only thing that changed on the SHIPPED (flowing) path is the arithmetic:
three hand-rolled O(N) loops became one `virtual_extents` index. Measured
directly, N = 2 000 ragged rows, `rowGap = 4`, 200 reps of "one geometry build
plus 60 queries" — the mix a real table pays (one build per data/theme change,
many queries per pointer move, scroll and keep-visible).

**A/A CONTROL — the same implementation measured twice, interleaved:**

| pair | run 1 | run 2 | delta |
|---|---|---|---|
| old vs old | 101.11 ms | 102.11 ms | **+1.0%** |
| new vs new | 4.29 ms | 4.17 ms | **−2.7%** |

So the noise band on this machine is roughly **±3%**. Every number below is read
against that band.

**A/B, order-swapped across three rounds** (round 2 measures `new` first, so a
first-world/second-world bias would show as a sign change):

| round | old | new | delta |
|---|---|---|---|
| 1 | 95.69 ms | 4.30 ms | −95.5% |
| 2 (order swapped) | 99.02 ms | 4.61 ms | −95.3% |
| 3 | 90.17 ms | 4.18 ms | −95.4% |

**−95.4% ± 0.1**, thirty times the A/A band and stable under order swap. The
query mix is dominated by the old `contentHeight()` being O(N) *per call* —
which is the shipped hot path, since `clampScroll` calls it.

**Build alone** (one geometry rebuild, no queries), 2 000 reps:
old `rowTops` 15.23 ms vs new index 11.78 ms → **−22.7%**, also outside the band.

### The virtualization win is a COUNT, not a timing

Timings on a headless runner cannot resolve mount cost honestly (the perf lab's
own A/A on list scenes measured a ±5%..±28% band). The property that matters is
counted instead, in `tests/table_virtualized.spec.luau`:

- a 5 000-row virtualized table builds only the windowed cells, and **the build
  count is IDENTICAL to a 50-row table's** — it does not grow with the data;
- the mounted set has a ceiling (`viewport/extent + 1 + 2·OVERSCAN`) **and a
  floor** (every row the viewport touches). The floor was added after a mutation
  showed the ceiling alone was satisfied by mounting three rows.

## Suite counts

| suite | before | after |
|---|---|---|
| LuauUI | 5192 passed / 0 failed | **5214 passed / 0 failed** |
| Rascal Rally | 3203 passed / 0 failed | **3205 passed / 0 failed** |

`tools/check_source_size.py`: PASS (`table.luau` 169 348 chars, under the 200 000
Source-write cap).
