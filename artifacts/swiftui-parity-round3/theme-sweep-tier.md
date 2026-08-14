# The overflow sweep's theme axis — what it cost, and what it does not cover

**Measured 2026-08-14.** The numbers `tests/overflow_sweep.spec.luau`'s header
cites, with the runs behind them. Everything here is the **headless Lune tier** —
a regression signal, never a device claim (round-3 standing rule 3).

## The instrument defect (O-24)

`tests/overflow_sweep.spec.luau` swept 43 surfaces × 8 viewports × 4 text
preferences and ran every one of them on the flat Studio Neutral resolution. The
round-3 brief's standing rule 4 requires every gap closure to be *"verified to not
overlap or clip **across every shipped theme** — Pixel Quest and Parchment have
both broken layouts that Studio Neutral survived."* That clause was carried by
three hand-written per-file sweeps (`theme_matrix_audit`,
`theme_reference_packages`, `instance_recycling_themed`), none of which asks the
question of the showcase corpus.

It is the house defect class — a check that proves less than it claims — and it
hid the two defects below.

## The measurement that chose the tier

One collector ran the **whole** cross product: 43 surfaces × **12 themes** × 8
viewports × 4 preferences = 45 115 finding rows, 24 963 distinct findings, in
**33.5 s**.

### 1. A package is the geometry axis; a theme is its palette

Three packages ship two themes each. Over the whole cross product their finding
sets are **byte-identical**:

| package | themes | rows each | identical |
|---|---|---|---|
| `classic-desktop` | Day / Night | 527 | yes |
| `fantasy-ornate` | Crypt / Grand Hall | 3 863 | yes |
| `fantasy-parchment` | Candlelight / Daylight | 2 202 | yes |

That is ADR-0019's "a swap moves the palette, not the geometry" **measured**
rather than recalled. The axis is therefore the **eight shipped packages**, not
the twelve themes — a 12 → 9 reduction that costs nothing at all in coverage.

### 2. Swinging the package is the same mount

The sweep commits a package the way the theme picker does —
`env:set("themeMetrics", snapshot)`, the metric half of ADR-0019 §7's one
transaction — so one mount per (surface, viewport) serves every package, exactly
as it already serves every preference.

Proved, not assumed. The same collector was run in **`remount`** mode (a fresh
world per package, 39.8 s):

```
swing    45 115 rows   24 963 distinct
remount  45 460 rows   24 963 distinct
only in swing:   0
only in remount: 0
```

The 345-row difference is multiplicity, not content: `sponsor_drop`'s virtual
list materialises a few more generated rows of the *same* finding (same node,
same class, same 48px) when it mounts under the package instead of swinging into
it — and `normalizePath` collapses those to one key anyway.

### 3. Every viewport, because a viewport changes the TREE

240 distinct defect keys appear only under a package. Coverage of the cheap
narrowings:

| tier | coverage | cost |
|---|---|---|
| all viewports × +0 | 186 / 240 | 3.00× |
| two narrowest × all preferences | 224 / 240 | 3.00× |
| two narrowest × +0 | 182 / 240 | 1.50× |
| **all viewports × +0, plus two narrowest × +14** | **224 / 240** | **3.50×** |
| all viewports × +0 and +14 | 237 / 240 | 5.00× |
| all viewports × all preferences | 240 / 240 | 9.00× |

The narrow-only tiers look competitive on the count and are wrong on the
structure: **16 of the 240 are on nodes a narrow pass never *builds*.**
`p4_foyer`'s NavRail sits behind a `SideRailWhen` that only exists on desktop;
`p3_sipworks`' panes likewise. That is `the-solver-already-told-you.md` §13.1
again — a sweep only covers the configurations its fixture actually builds — so
the structural pass keeps every viewport.

The preference axis is the opposite case: it moves text inside a tree that does
not change, and the neutral pass already sweeps all four preferences on all 43
surfaces. So packages get the default preference everywhere plus the largest one
where space is tightest.

## The cost, before and after

| | wall | ×
|---|---|---|
| `overflow_sweep.spec` before (3 runs: 3.03 / 3.02 / 3.02 s) | **3.02 s** | 1.00× |
| `overflow_sweep.spec` after | **10.0 s** | **3.31×** |
| the naive 9× (all packages × all viewports × all preferences) | 25.2 s | 8.3× |
| the whole 12-theme cross product | 33.5 s | 11.1× |

Same-arm spread of the harness on the before arm: **0.3 %** (3.02–3.03 s over
three runs). Lune + `require("../src")` floor: 0.20 s.

Suite: **61.8 s → ~68 s**, +11 %. The sweep becomes the fourth-costliest spec and
stays in the slow tier (`tests/lib/tiers.luau`), so `--fast` is unaffected.

## What the axis does NOT cover

Printed by the sweep on every run (`COVERAGE:` case), not left in a comment:

1. **The six wide viewports at any preference above the default** — 22 of the 32
   (viewport, preference) cells carry no themed pass. Measured cost of the 16
   findings this loses: 9.00× instead of 3.50×.
2. **The two narrow viewports at +4 and +10** — 3 further findings. The
   preference axis is *not* monotone (this file's own neutral header proves it on
   `03_settings_sync` and `p5_wardrobe`), so this is a known hole rather than a
   claim that +14 dominates.
3. **A package's second theme** — free by the equivalence above on the *solver*,
   and blind to every palette defect (contrast, a tint that eats a label). Those
   need `theme_matrix_audit` and a human.
4. **`ornate_gauge` and `custom_control`** — control contributions, not packages
   — and the two `testOnly` fixtures the picker also hides.
5. **The 1.4× pseudo-locale**, which this whole file already skips on every axis.

## What turning it on found

**264 distinct themed findings**, recorded in `tests/lib/theme_sweep_ledger.luau`
as **146 rows** after collapsing runs of hand-named siblings that carry one defect
(`05_word_game`'s 26 keyboard keys, `p2_cartwheel`'s 11 rail rows). By class:

| n | class |
|---|---|
| 115 | `theme-inset-yield` — a control smaller than the theme it wears. The renderer gives the inset back and the content still draws, so it is the mildest row here; it is also the direct signal of `a-fixed-box-cannot-hold-a-themes-frame.md` |
| 48 | `row-cannot-shrink` |
| 53 | `collapsed-box` |
| 16 | `layer-overlap` |
| 5 | `lying-itemExtent` |
| 1 | `wrap-clamp` |

Two were framework defects no consumer could reach, and both are **fixed**:

- **O-23** — `progress_ring`'s spinner row overflowed by **40 px** under Glossy
  Mobile and Glossy Touch and **6 px** under Fantasy Ornate and Parchment, at
  320×640, at the **default** preference. Two of the three progress shapes are a
  fixed px box from a theme metric, so the label was the only thing that could
  give and it was not allowed to. Fixed in `src/controls/progress_view.luau`
  (`shrinkWeight = 1` on the label); pinned by `tests/progress_circular.spec.luau`.
- **O-25** — every `02_playlist_table` cell painted **4 px** outside its cell
  under Pixel Quest, at the default preference, on every viewport. The Table
  derived its row height without the `chromeInsets.selection` the same control
  makes its cells *spend*. Fixed in `src/controls/table.luau`; pinned by
  `tests/paradigm_table.spec.luau`.
