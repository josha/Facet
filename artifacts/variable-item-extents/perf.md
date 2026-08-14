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
