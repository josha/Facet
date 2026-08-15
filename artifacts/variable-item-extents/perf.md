# Performance — variable item extents (2026-08-14)

**Tier 1 (headless Lune, regression signal only).** Device is authoritative
(§14.3); nothing here is a device claim.

## The gate

`tools/perf.sh` — 20 scenes × 5 profiles, reference `floorAndroid` @ 30 Hz —
**PASS**, every scene inside its ceiling. `virtual-list-scroll` 2.37–2.58 ms
against an 8.333 ms ceiling; `lab-dense-scroll` 2.60–2.95 ms; no budget moved
and none was re-baselined.

## The before/after, and why it says nothing

An ABBA round (three runs each, medians) over the pre-change
`virtual_list.luau` (`2b26e93`) and the post-change one:

| scene | before | after | delta |
|---|---|---|---|
| virtual-list-scroll | 2.4559 | 2.4801 | +0.99% |
| collection-mutation | 1.0469 | 1.1911 | +13.77% |
| lab-dense-scroll | 2.8364 | 2.9548 | +4.17% |
| lab-collection-churn | 1.5833 | 1.3815 | −12.75% |
| screen-lifecycle-churn | 1.5959 | 1.5508 | −2.83% |

**Then the A/A control**, six runs of the SAME source split into two groups:

| scene | group 1 | group 2 | delta | min | max |
|---|---|---|---|---|---|
| virtual-list-scroll | 2.2300 | 2.1175 | −5.04% | 2.0489 | 2.2954 |
| collection-mutation | 1.0693 | 1.1800 | +10.35% | 0.9419 | 1.2546 |
| lab-dense-scroll | 2.5271 | 2.7135 | +7.38% | 2.4257 | 2.7567 |
| lab-collection-churn | 1.2172 | 1.5598 | **+28.15%** | 1.1995 | 1.6257 |
| screen-lifecycle-churn | 1.4346 | 1.3577 | −5.36% | 1.3236 | 1.5021 |

**Every B→A delta is inside the A/A band, and the largest B→A number
(`collection-mutation`, +13.77%) is on a scene that does not build a
`newVirtualList` at all — it is a `newTable` scene** (`bench/perf_scenes.luau`
scene 4). The honest verdict is therefore: *this instrument cannot resolve a
difference of this size, and it did not see one.* The measured claim is the
gate PASS, nothing more.

## What was fixed on mechanism instead

The first draft rebuilt the running-offset index — six closures and a table —
on every DATA EDIT, because the index memo depends on the row data. A list is
edited far more often than its geometry moves, so every shipped uniform list
would have paid an allocation per edit for a feature it does not use.

The obvious fix does not work, and that is worth recording: handing `core:memo`
an equality does NOT stop a downstream memo recomputing. A memo's `eq` is
OBSERVER-facing only (`src/core/custom.luau`: `notify` compares with it,
`markMemosStale` invalidates the subtree unconditionally, and `pull` overwrites
`node.value` without comparing). The cache therefore lives inside the memo body,
keyed on the numbers that decide the geometry, returning the SAME index object
when none of them moved.

Because the perf instrument cannot see this, the property is a COUNTED test
rather than a timed one — `virtual_list_variable_extents.spec` wraps the
constructor and asserts a rename rebuilds nothing while a row count or an extent
rebuilds exactly once. Mutation-proved (C11/C12/C13 in `mutation-evidence.md`).

## What remains device-owned

The claim that a variable-extent list *feels* right — that the anchored scroll
is invisible to the hand, and that a 249px row at `preferredTextOffset = 14` on
a 320×640 phone is comfortable rather than merely correct — is `PENDING_PHYSICAL`.
The gallery fixture `variable_extents` is the surface to drive for it.

---

# Stage 2 — measured extents (2026-08-15)

**Tier 1 (headless Lune, regression signal only).** Device is authoritative
(§14.3); nothing here is a device claim. What IS claimed is a comparison between
two arms of one harness in one process, which is the thing this instrument can
actually resolve.

## The control, first

`extentArms` gained a fifth arm, D (`measuredRagged`): arm C's picture exactly —
same 2 000 rows, same 1..4-line cells, same viewport, same overscan — with
`itemExtent = "measured"` and `estimatedItemExtent` seeded at the SHORTEST row, so
the arm pays the maximum convergence work rather than a flattering amount of it.

Three runs, `extentArms=60/40`, medians of p50:

| control | value |
|---|---|
| A vs A′ scroll-step p50 spread (the same uniform arm twice, one process) | **0.0197 ms** (≈2.7% of 0.73 ms) |
| A vs A′ grow-edit p50 spread | **0.0551 ms** (≈9.5%) |
| per-arm range across the three runs | **2.4% – 15.5%** |

| arm | scrollStep p50 | sameCountEdit p50 | growEdit p50 | mounted | canvas |
|---|---|---|---|---|---|
| A uniform | 0.7291 | 0.6913 | 0.5810 | 21 | 48 960 |
| A′ uniform (control) | 0.7315 | 0.6754 | 0.5895 | 21 | 48 960 |
| B variable, flat | 0.8538 | 0.7255 | 0.7258 | 21 | 48 960 |
| C variable, ragged | 0.7544 | 0.7049 | 0.8549 | 13 | 104 040 |
| **D measured, ragged** | **1.4805** | 0.7971 | 0.7335 | 13 | 50 526 |

## The reading, and the one number that is outside the band

**D-minus-C on the scroll step is +0.726 ms (+96%) — about 37× the A/A control
spread.** That is real and it is the headline. The two edit rows are not: +13% on
the same-count edit sits inside a 14–15% per-arm range, and the grow edit is
−14%, inside the band and in the direction a measured list would be cheaper
anyway (it evaluates no per-item function). **Neither edit number is a claim.**

D's canvas is 50 526 against C's 104 040 because D has NOT converged — only the
windowed rows are measured and the rest are still the estimate. That is the
feature, not a flaw in the arm, but it means the lab's arm cannot separate "the
seam costs this" from "converging costs this".

## So the seam was isolated separately

A second, purpose-built probe: one list, 60 scroll frames of 40px, run **three
times over the same rows**. Pass 1 walks territory no row has been measured in;
passes 2 and 3 walk the identical rows with every measurement already cached.

| list | pass 1 | pass 2 | pass 3 |
|---|---|---|---|
| declared (A) | 0.6980 | 0.6826 | 0.6823 |
| declared (A′, control) | 0.6870 | 0.6937 | 0.7111 |
| measured | 1.4234 | 0.9646 | 0.9027 |
| measured (repeat) | 1.4201 | 0.8832 | 0.8635 |

A/A control spread: **0.0110 ms (1.6%)**; the declared arm's own three-pass band
is ±2%.

**The split, both outside that band:**

* **converging: ≈ +104%.** Every window entry is a NEW measurement, so the epoch
  moves, the index rebuilds, and everything downstream of it — canvas, clamp,
  window, every mounted row's offset — invalidates. Roughly one extra solve per
  frame while the finger is over rows nobody has seen.
* **steady state, over seen rows: ≈ +27% to +40%.** The residual is the per-solve
  walk of the window reading rects back, plus the one `Content` node a measured
  row mounts.

## What that buys and what it costs

This is why `"measured"` is an **opt-in fourth form and not the default**, and the
api.md entry says so in those words. A row whose height a consumer really can
predict should still be declared; measured mode is for the rows nobody can — text
that wraps with no `lineLimit`, user content, a localization you do not control —
where the alternative is not a cheaper list but a wrong one (the `row_actions`
waiver: 84 declared, 88 measured at the DEFAULT preference, 249 at +14 on a
320×640 phone).

## Flagged, not taken

`measureWindow` walks the entire window on every solve, and once a region is
converged that walk finds nothing. It is most of the steady-state +30%. Gating it
on a per-row dirty signal is a real optimization with a real before/after and is
its own change.

## What remains device-owned

Everything about how it FEELS: whether the thumb's proportion moving as the canvas
converges is noticeable on a phone, and whether the convergence frame is visible on
a fast fling. `PENDING_PHYSICAL`. The surface to drive is
`examples/gallery/scenarios/measured_extents.luau` (picker id `measured-extents`).
