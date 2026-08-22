# Declarative-purity sweep, phase 1 — report

**Status: COMPLETE.** Five Facet commits + one Rascal Rally commit, every one green.
Measured from a content-pinned pair built at the final refs
(`tools/mkpair.sh`, resolved at measurement time):

| pin | sha | suite |
|---|---|---|
| `PIN_FACET` | `b3f9c89a46424d1122d9d78927e167fc652a953d` | **7057 passed** (dispatch baseline 7040) |
| `PIN_RR` | `ca50fdbdf1c3cf63ed26c6d01b85def7cc7420eb` | **3469 passed** (dispatch baseline 3466) |

Guards certified AT those refs, from inside the pair: `check_theme_drift_cli` exit 0,
`check_example_drift_cli` exit 0, `stylua --check` exit 0 in both repos.

---

## The lint flip — the evidence

**Reproducible red-first.** The flipped lint from `HEAD`, run unmodified against the
**pre-sweep tree** (`git archive 82b0406` + the two `HEAD` lint files):

```
theme drift: 365 violation(s) — 0 framework, 365 example
 139 [example] textSize = 12      27 [example] textSize = 14      4 [example] padding = 4
  77 [example] gap = 8            26 [example] gap = 4            4 [example] gap = 16
  40 [example] padding = 8        22 [example] textSize = 18      3 [example] textSize = 24
  16 [example] padding = 16        4 [example] textSize = 16      1 [example] textSize = 20
                                                                  1 [example] padding = 24
```

(364 literals + 1 `PROBE_EXEMPT_FILES` header-guard finding, because the pre-sweep
`probe.luau` did not yet warn its own reader.)

**Green now**, same command, same file:

```
theme drift: clean — framework 45 files / 38158 lines (1 allowlisted);
             examples 165 files / 70460 lines
             (11 marked THEME-OPT-OUT, 4 PROBE-EXEMPT across 1 listed files)
```

**Corpus share on the three theme-owned props**, counted directly rather than
inferred: raw **519 → 166**, named **797 → 1150** — i.e. **39.4% raw → 12.6%**,
against the shipping game's 22%. The showcase now practises better than the game it
teaches, which was the charge.

### What the flip actually is

`check_theme_drift.luau` gained a second scope. The framework scope is unchanged
(every metric family, allowlist-only). The **example scope** is deliberately
narrower in two ways, and both are what make it mechanical rather than a judgement
call:

* it asks about the three prop families the audit measured — `textSize`,
  `gap`/`rowGap`, `padding` — and no others. A demo canvas that is 300×200 is
  structure; the hit-target-floor and `minColumnWidth` classes are swept **by name**
  in their own batch rather than by grep.
* it fires **only when a theme name resolves to exactly that number** on the neutral
  snapshot, so every fix it demands is pixel-identical. `gap = 8` is reported because
  `"s"` is 8; `gap = 6` is **not**, because no space step is 6 and there is nothing to
  rewrite it to. That is a *pending finding*, not a loophole: the day the spacing
  scale grows a rung for 6, the lint fails all sixty of those sites for free with no
  edit — which converts the out-of-scope spacing question into a standing alarm.

The vocabulary is read from `themes/package` + `themes/snapshot`, never restated, so
a package that re-ladders its type scale re-ladders the lint. Ladder order decides a
collision (`control` wins 18 from the derived `numeral`; `s` wins 8 from `gutter`).

**RR and every other game stay out of scope permanently** — an app author's literal
is a legitimate opt-out, and the file says so.

### Markers, and why the doctrine differs from the framework allowlist

In `src/controls` the reason for an exception belongs in one reviewable place because
nobody reads those files to learn. Here the reader **is** reading the file, and "no
reader can tell which is the house style" is the whole finding — so the reason lives
at the site:

* `-- THEME-OPT-OUT: <reason>` on the line or in the comment above it. **One marker
  covers one reportable LINE**: the pending reason is consumed by the first line it
  excuses, so a marker written for one number in a long constructor cannot go on
  silently excusing every number under it. *Corrected 2026-08-22 (review LOW-4): the
  first write-up said "one literal" — `optedOut += #found` means a single marker can
  excuse two nameable literals sharing one line. No shipped site depends on it, and a
  marker is correctly NOT consumed by a line with nothing to report.* A marker with no
  reason is a suppression comment and is refused.
* `-- PROBE-EXEMPT: <reason>`, also as a `BEGIN:`/`END` region. Whole instrument files
  are listed in `PROBE_EXEMPT_FILES`, and **that listing is guarded**: a listed file
  with no `-- PROBE-EXEMPT` line in its own header is itself a violation.

`check_theme_drift_cli.luau` is new because the old header **lied**: it said "CLI: run
this file directly", and the module ends in `return checker`, so `lune run
tools/lune/check_theme_drift` built the module and exited 0 whatever the tree said.
**The `d3a-help` gate row still spells it that way and is therefore a check that proves
nothing today** — the row is left alone (it is another round's pinned evidence) and the
defect is reported here.

**Thirteen new spec cases**, every direction: a literal a step names, a size a role
names, a value no name resolves to (silent, on purpose), zero, a prop this scope does
not own, a marker with and without a reason, a marker in the comment above plus the
second literal under it that is still reported, a PROBE-EXEMPT region and an unclosed
one, and the file listing driven from the case so both halves — silence the literal,
report the missing header — are measured against a real corpus file.

---

## Per-class counts

| Class | Done | Skipped / kept | Where |
|---|---:|---:|---|
| **1. Lint flip** | 1 | — | `d48983226` |
| **2. Raw literals on theme-owned props** | **353 swept** | **11 kept with a measured marker**; 147 unreachable (no name resolves) | `a81beb252` |
| **3. Hand-rolled hit-target floors** | **12 named** | 0 | `22fc4cd80` |
| **4. `minColumnWidth` raw px** | **2** | **7 measured and reverted, each annotated** | `22fc4cd80` |
| **5. Deprecated `rowHeight`/`viewportHeight`** | **27** | **7 are not that** (see below) | `22fc4cd80` |
| **6. Live defects** | **6 fixed red-first** | **1 MOVE-blocked, measured and documented** | `5e50c4783`, RR `ca50fdb` |
| **7. Mistakable probes** | **13 marked** | — | `b3f9c89a4` |

### 2 — the literals

353 sites across 47 files became the name the framework already resolved to that
exact number. Pixel-identical under Studio Neutral **by construction**; what it is
*not* identical under is the point — a theme package and the ten-foot ladder now move
these numbers, which is what the corpus was claiming to demonstrate and was not.

**The eleven that stayed, each with the measurement at the site.** Nine were swept,
**measured to break**, and reverted; two are not Facet props at all. Every one is a
fixed-px box that cannot follow a value that now grows — the audit's MOVE §3 (a box
declaring its height in *content* terms):

| site | measured failure with the name |
|---|---|
| `with_animation` Card `padding` | ten-foot ladder scales the step; the 20px pip no longer clears it — 4px past the card's own box at **+0, Studio Neutral**, 1920×1078 |
| `adaptive_controls` screen `padding` | 320×640 under glossy-mobile/glossy-touch: body narrows to 242px, the Slider row overflows **4px at +0** — a default-text-size regression on a shipped package |
| `keyboard_navigation` screen `padding` + Actions `gap` | the row is already 145px past a 320px phone at +14 in the ledger; the names measured 149 and 151 |
| `perf_capture` Actions `gap` | already 126px over (waived); the name measured 128 |
| `selection_bridge` screen `padding` + `gap` | 640×320 at +14 under glossy-mobile: 6px and 2px past the box |
| `level_picker` Pair `gap` | all five rows 2px past their box, 320×640 +14 glossy-touch (and the file records why it may not wrap) |
| `row_actions` cell `textSize` | value overflows its zstack by 24px (compact-pointer) / 25px (scifi-hud) at +14 against a 21px ceiling — the table pins the row height |
| `foreign_content` pane `textSize` | **not a Facet prop**: it crosses the FOREIGN seam to a raw `TextLabel.TextSize`, where a role name is a runtime type error |
| `variable_extents` METRICS `gap` | **arithmetic**: `rowExtent` adds it to two `text.lineBox` results; a metric name cannot be added to a number |

*Corrected 2026-08-22 (review LOW-3).* Only **one** of the two was invisible to the
suite. Re-measured: the wrong form of `variable_extents`' `METRICS.gap` (a metric name
added to a `text.lineBox` number) reds **11 cases** with `attempt to perform arithmetic
(add) on number and string` — a strong pin that already existed. The wrong form of
`foreign_content`'s `textSize` passed the whole suite (**7057, exit 0**) *and* passed
the lint, because a name is exactly what the lint asks for; `foreign_instances` only
materializes with a live engine seam. That one really was caught by reading the diff,
and it now has a mechanical pin — see the fix-round-1 appendix, MED-2.

**147 literals name a value the scale cannot spell** (`gap = 6` sixty times over; the
framework concedes the same gap in `snapshot.luau`'s own `label = { gap = 6 }`), so
there was nothing to rewrite them to. The spacing-scale question is a separate design
call and is left as the lint's standing pending finding.

**R23's route census moves 381 → 385** with the corpus, which is exactly what its own
note asks for. The two lists the R23 ruling is about — framework-cut and unexplained
sub-floor routes — are still pinned EMPTY and still are.

### 3 — hit-target floors: NAMED, not deleted

All 12 `height = { type = "minMax", min = 44 }` became
`min = "targetSizes.minimum"`. Deleting outright would have been wrong in the
direction that matters: the framework enforces the **hit** floor for a Button
(`class_contract`'s `minHitSize` via `layout_node`'s `effectiveHitFloor`), but the
**visual** height would then be whatever the label and the theme's padding came to.
The corpus already had the right spelling in its own sponsor fixtures, and that is the
whole point: **44 stays 44 on a television; the name ten-foot-scales to 80.**

### 4 — `minColumnWidth`: the audit's "17 stale sites" does not survive measurement

`"intrinsic"` is right for 2 of 9: `native_style`'s 90 duplicated the fixed width of
the chips it was measuring, and `sponsor_avatars`' 56 was stale against a face already
sized `targetSizes.minimum`. The other seven were measured and reverted, each carrying
the measurement at the site:

* **six sponsor control grids** are a *packing* floor, not a font guess. `"intrinsic"`
  lets the widest verb ("AddRemove") decide every column, which costs a column on a
  320px phone, doubles the grid's height, and collapses the `fill` stage column above
  it to **zero — 144 solver findings across five scenarios** (`sponsor_motion` 70,
  `sponsor_avatars` 32, `sponsor_celebration` 25, `sponsor_markers` 12,
  `sponsor_billboard` 5; 48 of the resulting boxes measure zero-width). *Corrected
  2026-08-22 (review LOW-1): the first write-up quoted 70 — `sponsor_motion`'s own
  count — for the whole set. Direction and conclusion unaffected;*
* **two all-`fill` tile grids** — `grid.luau` says outright that a fill child cannot
  express an intrinsic minimum, so the grid falls back to ONE LANE, deleting the very
  thing those fixtures demonstrate;
* **`adaptive_controls`' readout field** re-columns short enough that its page stops
  overflowing its scroller, and that fixture's §2.5 case is about what a scroller's
  viewport measures.

### 5 — deprecated aliases: 27 of 34, and 7 are not that

27 sites now speak `itemExtent` / `viewportExtent`: 13 VirtualList specs, 8 local names
feeding them, 4 report keys, 2 dump reads, plus `sponsor_scenarios`' four assertions
moved with them. The other seven are left on purpose: `row_actions`' and
`table_phaseb`'s `rowHeight` belong to `Facet.Controls.Table`, whose prop of that name
is **current**; `perf_lab`'s pair at `:864/:867` goes to `native_list.luau`, the **raw
Roblox reference implementation** with its own option names — the arm the lab measures
Facet against; and four are "WHAT IT WAS" history in comments.

### 6 — the seven live defects

Six fixed, each red first. One skipped as MOVE-blocked, with its measurement written
into the code.

| # | defect | red-first evidence |
|---|---|---|
| 1 | `p5_wardrobe` turntable ignored reduced motion — `env:get(k) == true` compares a **Readable to a boolean**, permanently false | yaw moved under reduced motion; now it does not, with a positive control that motion allowed still turns it |
| 2 | `p5_wardrobe` section names froze at the boot locale (`Lnow` at build time on Picker options) | the flip left all three words in English; now all three move |
| 3 | the **shipped** showcase clipped its theme chip and not its demo chip (gated on `collapsible`, sibling gates on `composed`, host mounts both) | the composed chip showed a truncated name; the case picks a package long enough that the clip would have bitten |
| 4 | `p2_cartwheel` drove `setPresentationTransform` **every tick** for a prop that is reactive | **61 imperative writes** → 0, nudge still peaks above rest and settles back to exactly 1. *Corrected 2026-08-22 (review LOW-2): 31 was measured in a 30-frame window during the round; the case that SHIPS runs 60 frames and reports 61 — one per frame plus one at the arrival. The `→ 0` half is unchanged.* |
| 5 | RR ticker strip sat **inside** the card it stands above at large text | `@10 clears=false \| @14 clears=false` → all four preferences clear; measured 22px overlap at +14 on 390×844 |
| 6 | RR autoscroll band: an option api.md says has **no correct non-default value**, wrong three ways at once | with `bandH = 44` a pointer 42px deep arms; with the option gone it does not, and 38px still does |

Defect 4's neighbour `celebration.luau` is **left imperative on purpose**, and the
comment says why: it moves a *translation*, which has no declarative twin. That is the
distinction worth copying — reach for the write when there is no prop, not because a
sibling did. The registry-neutrality case caught the new memo before it shipped
unowned, which is why it hangs off the app scope.

**Two of the audit's three "non-reactive `:get()`" sites did not reproduce**, and the
null result is recorded rather than dropped: `StoryFlow:_refreshTicker`'s
`sizeClass:get()` and `init.luau`'s `tickerOf` both sit inside `_refreshTicker`, which
`StoryFlow:step` (`StoryFlow.luau:1290`, the per-frame step — *corrected 2026-08-22,
review LOW-4, from `StoryFlow:tick`*) calls **every frame**, so each is a live
per-frame read and a rotation
lands on the next tick. Only the third — `autoscrollBand` — was latched at
construction, and it is gone. A new case now **guards the null result**: it turns the
phone with no new play and no pose change and asserts the ticker re-publishes at the
compact cap, so the obvious future optimization (move the republish off the tick onto
the feed) reintroduces exactly the defect the audit described, and reddens.

---

## Skipped, and why — the MOVE-blocked list

Per the brief's rule: a DELETE row that needs a MOVE capability to stay honest is
skipped and listed, never smuggled.

1. **The 11 opted-out literals** (table above) wait on **MOVE §3** — a box that can
   declare its height in CONTENT terms — and, for `with_animation`'s card, the
   theme-owned decorative-chrome floor. Each says so at the site with its measurement.
2. **RR `FacetRacerListScreen.ROW_HEIGHT = 28`.** The audit was right that the
   justification expired, and re-measuring found it expired **twice over**:
   `ScrollView` clips by default now, AND `Table.rowHeight` is a floor the framework
   *grows* — measured 28 / 31 / 38 / 43 px at offsets 0 / 4 / 10 / 14 on 812×375 — so
   "28px rows keep the full 8-racer grid inside the panel" is already false above the
   default preference. What is genuinely broken is `buildDocked`'s
   `n * ROW_HEIGHT + gaps` reserve: **238px reserved for content that wants 358** at
   +14, plus a racer cell **72px** over its row and an avatar initial **10px** over its
   icon box (16 solver findings on a shipping screen). The honest fix is a Table that
   can declare its height in content terms (**MOVE §3**, "Table has no content-hugging
   height"). Changing the number without it would move a shipping panel's density for
   no gain, so the comment now carries the whole measurement and the row goes to the
   directed phase.
3. **`with_animation`'s `TWO_COLUMN_MIN_WIDTH = 520`** — the corpus's single
   hand-rolled breakpoint, re-implementing `adaptive.axisFor` line for line. Mechanically
   fixable and *not* in this phase's DELETE list; flagged for the directed round.
4. **The `d3a-help` gate row** runs `lune run tools/lune/check_theme_drift`, which
   cannot fail. `check_theme_drift_cli` now exists; re-pointing that row means re-running
   its full grep chain across both suites, which is another round's pinned evidence.

---

## 7 — the thirteen mistakable probes

Marked, no behaviour moved:

`hud.luau` ×3 (the probe's strings, its hard-coded watch list, and the ~800-line probe
surface — a **region**, because it runs inside the exemplar's own `build`) ·
`rows.luau` (the `heightFor` extent arithmetic; the idiom is `itemExtent = "measured"`
and `variable_extents.luau` is the scenario that teaches it) · `card_rail.luau` (the
hand-derived viewport window — MOVE §4) · `nested_compositing.luau` (the transcribed
scale/rotation trigonometry — teaches-wrong §12) · and seven whole files:
`probe.luau`, `foreign_instances.luau`, `perf_lab.luau`, `overlay.luau`, `levers.luau`,
`capture.luau`, `dataset.luau`.

**Only `probe.luau` is LISTED in the lint**, because only there is the literal
load-bearing (its geometry *is* ledger row NS-A2's frozen baseline). The rest carry the
reader-facing marker and are swept like every other example — the distinction the
list's own comment insists on: *"it is instrument, not example" does not earn a lint
exemption on its own.*

**And the stale comment on a taught helper is corrected.** The audit found the probe's
`glass()` call site citing 168, 208 and "a third of the narrowest landscape window"
against code that says **164** — prose left describing an intermediate step after the
same round's right-inset measurement narrowed the plate again. It now says what 164 *is*
and points at the spec that holds the property in both orientations rather than either
number.

---

## Rascal Rally consumer position

**No Facet `src/**` file changed in this round.** The work was confined to
`examples/**`, `tools/lune/*` and specs, and the lint's new scope explicitly and
permanently excludes games. So nothing here is a consumer migration. The RR commit is
its own three DELETE §5 rows, red first in RR's own suite; RR's suite was re-run from
the pinned pair against the final Facet sha and is green at **3469**.

---

## Commits

| repo | sha | subject |
|---|---|---|
| Facet | `a81beb252` | the showcase stops spending numbers the theme system already names |
| Facet | `d48983226` | the lint that guards the framework now guards the corpus that teaches it |
| Facet | `22fc4cd80` | three stale spellings leave the showcase, and the two that were load-bearing say so |
| Facet | `5e50c4783` | four live defects in the teaching corpus, each red first |
| Facet | `b3f9c89a4` | thirteen places where instrument was standing in a corpus that teaches |
| RR | `ca50fdb` | the strip stands above the card the card is actually drawn at, and the band nobody should pick is gone |

**Commit order note.** The sweep is committed *before* the flip so every commit is
green: the flip's own gate ("the teaching corpus is clean") can only pass on a swept
tree, and a deliberately red intermediate commit would have made the round unbisectable.
The causal order is the other way round and the messages say so — the lint was built
first and is what produced the 365-site worklist, reproducible above against the
pre-sweep tree.

## Out of scope, untouched

The 34 MOVE gaps · the `gap = 6` spacing-scale question · any framework API change ·
`examples/themes`' authored base metrics (a theme package writing `space = { xs = 4 }`
*is* the declarative act) · every Rascal Rally flag and behaviour not named above.

---

# Fix round 1 — response to `task-purity-sweep-review.md` (`c4aa319`)

**Verdict addressed: PASS WITH FINDINGS, 1 HIGH / 3 MED / 4 LOW.** MED-1 is not mine
(the navgate-repin round owns those gate rows and is editing `gate_manifest.luau`; I
did not touch it — it shows as modified in the shared tree and is excluded from every
commit below). Everything else is closed, and the HIGH turned up a **second instance**
the review had not found.

Measured from a content-pinned pair built at the final refs (`tools/mkpair.sh`,
resolved at measurement time), both suites run from inside the pair:

| pin | sha | suite |
|---|---|---|
| `PIN_FACET` | `779f59081e1ce89650e9de1e61aa735d5be9899d` | **7062 passed**, exit 0 (was 7057; +5 cases) |
| `PIN_RR` | `7db53a86e1cde364d0041c9a96054c6b7be7540d` | **3470 passed**, exit 0 (was 3469; +1 case) |

Guards re-run at those refs from inside the pair: `check_theme_drift_cli` exit 0,
`check_example_drift_cli` exit 0, `stylua --check src tests examples
tools/lune/check_theme_drift*.luau` exit 0, RR `stylua --check src tests` exit 0.

**One observation that is not mine to fix:** `stylua --check tools` reports a diff in
`tools/lune/gate_manifest.luau` **in the committed tree** (the pair is a `git archive`
of `HEAD`, so this is what landed, not a working-tree artifact). That is the
navgate-repin round's file — MED-1's territory — and it is excluded from all four
commits below. Flagging it for that round rather than touching it.

## HIGH-1 — the ten-foot drift: instance, class, **and a second instance**

**The instance, and I took the option the coordinator called the honest one.**
`rows.ROW_PADDING_V = 16` predicted the slot while the row spent `padding = "xs"`. The
predictor now resolves the same token off the same snapshot the call site already
hands it (`itemExtent`'s memo passes `env:get("themeMetrics")`, the distance-adapted
authority), read by plain table access exactly as its neighbour `themeInset` reads
`chromeInsets` — this module has no requires by contract:

```lua
rows.ROW_PADDING_STEP = "xs"          -- the token the row SPENDS
rows.ROW_PADDING_HEADROOM = 8         -- what 16 always was on top of the row's real 8
rows.ROW_PADDING_V = 16               -- the NEUTRAL answer, kept under its old name
function rows.rowPaddingV(snapshot)   -- 2 * space.xs + headroom
```

`padding = 4` has been the row's real value since Step 9 while the constant's comment
said "8px above and below", so 16 was always 8px of over-reserve — which the file's own
doctrine calls the correct direction. That headroom is **kept and named** rather than
invented or dropped, so **the neutral answer is byte-identical** and no calibration in
the file or its spec moves.

**Measured, same probe as the review, same harness, same seed:**

| rung | pre-sweep | after the sweep (the regression) | after this fix |
|---|---|---|---|
| console-ten-foot 1920×1078 / Large | slot **60**, content **77** (17 over) | slot 60, content **81** (**21** over) | slot **64**, content 81 (**17** over) |
| desktop-standard 1232×1067 / Medium | mounts clean, 56/54 | identical | identical |

The *relationship* is restored exactly: 17 over in both trees. The residual 17 is
pre-existing and not mine — the predictor charges `IMAGE_SIZE`/`TEXT_BLOCK × s` while
the row's real height at ten-foot is set by `controlSizes.regular.height` (44 → **66**).
That is a fifth entry for the file's own list and is booked, not fixed here.

**The second instance, found while verifying the other five files.** `levers.luau`
declares `itemExtent = 28` **inline** — no named constant at all, so the first draft of
the detector could not see it — against a cell whose `padding` the sweep had named.
Measured at the same rung: the row grew **30 → 34** against that unmoved 28px slot.
Fixed the other way, and deliberately: a lever's cell is a cheap, *identical* leaf and a
stable tree is its whole subject, so the literal is what belongs there. It carries a
`-- THEME-OPT-OUT:` naming the extent it is half of, and the detector was extended so
this shape is mechanically visible (`itemExtent`/`viewportExtent`/`estimatedItemExtent`
given as a raw number is a prediction too). Post-fix delta on that surface: **zero**.

### HIGH-1(a) — the guarantee statement, and what the lint does about it

The header now says it exactly: **"the rewrite cannot move one pixel" is a
Studio-Neutral, scale-1.0 guarantee and nothing more.** A name resolves per solve
against the ACTIVE snapshot and a distance-adapted one scales the whole `space`
section, so `"xs"` is 4 at arm's length and 6 on a television — that is the feature.
It becomes a defect in exactly one shape, and the shape is detectable.

**`coupledConstants(source)`** reads every example file for (i) a raw numeric constant
whose name carries a spacing/size word, spent in arithmetic, and (ii) any raw declared
extent. A finding in such a file is **reported with the coupling message** — it names
the constants, states the ladder, and offers the two honest exits — instead of the
plain one.

**Reported, not refused, and the reason is stated in the file.** Refusing to demand a
swap in a coupled file would silence the lint across ten files that today carry
correctly named sites, trading a loud, informative demand for no demand at all. The
proven failure was never that the swap happened; it was that **nobody was told the file
predicts its own geometry**. So the demand stays and the telling is what was missing.
Of the 365 red-first findings, **35 were in coupled files** — that is the size of the
class the original lint reported without that sentence.

The coupled SET is **pinned by a spec case** (10 files, each with its constants), the
same discipline the route census uses: it changes with the corpus and the next author
re-reads the case rather than deleting it.

**One more lint defect fell out of the fix and is closed.** Writing the words
`padding = 4` into a long comment in `rows.luau` made the lint report *itself* — only
the opening line of a long comment starts with a dash pair, so every continuation line
looked like code, and this repository writes most of its prose that way. The example
scope now tracks long-comment nesting level. **The red-first number is unchanged at
365**, so no pre-sweep finding was ever inside one. It is deliberately not applied to
the framework scope, whose counts are pinned by four mutation cases.

Five new cases: the coupled message (naming the class, the ladder, the constants and
both exits), the uncoupled control, the pinned set, and long comments in both
directions.

### HIGH-1(b) — the six files outside the always-on sweep, each verified

The probe: mount at **console-ten-foot 1920×1078 / `displaySize = Large`** and
**desktop-standard 1232×1067 / Medium**, 15 lab workloads, dumping every solved rect at
mount, after the passes, and — via a wrapped `present` — for surfaces that exist only
*inside* a pass. Run identically on `82b0406` (pre-sweep) and on this tree, and diffed.

| # | file | covered how | desktop 1232×1067 | console 1920×1078 / Large |
|---|---|---|---|---|
| 1 | `performance/lab/rows.luau` | measured — 15 workloads mount its cell | **0 delta** | slot 60→**64**, content 77→**81**; over-by **17 in both trees** (was 21 — the regression, now closed) |
| 2 | `performance/lab/perf_lab.luau` | measured — `/PerfWorkload` tree at mount | **0 delta** | **0 delta** |
| 3 | `performance/lab/overlay.luau` | measured — `/PerfLabOverlay` at both rungs | **0 delta** | panel padding 8→**12** per side (the ladder, intended): panel 1904→1896 wide at x 8→12; **heights unchanged, structure identical (0 path differences), no overflow, no scenario flipped** |
| 4 | `performance/lab/levers.luau` | measured — `/EditArm` + `/ShapeArm`, captured inside the pass | **0 delta** | **0 delta after the fix** (was row 30→**34** against `itemExtent = 28` — the second instance) |
| 5 | `gallery/client/init.client.luau` | **not mountable headlessly** (`game:GetService` at module scope) — verified mechanically | — | **uncoupled**: no raw constant in the file predicts a box, so there is no predictor to de-calibrate. Its 5 sites are leaf props on a `UI.Screen`/`UI.Text` the solver sizes |
| 6 | `table_phaseb/client/init.client.luau` | same | — | **uncoupled**. Its `rowHeight = 44` is a `Facet.Controls.Table` **floor the framework grows**, not this file's own arithmetic — the framework owns both sides |

**Aggregate: desktop byte-identical across all 15 scenarios and the whole tree; at
ten-foot the only remaining movement is the overlay's own padding riding the ladder,
with identical structure and no overflow, and the `rows.luau` slot moving WITH its
token.** No scenario changed mounting status; node counts identical.

For files 5 and 6 the honest statement is: the *mechanism* of the defect is absent
(nothing in either file predicts a box), which is checkable mechanically over the
shipped source and re-checkable on every run — but neither was mounted, because
neither can be, and I am not claiming a measurement I did not take.

**The round's own false claim is retracted.** `a81beb2`'s message says *"The overflow
sweep runs every one of these surfaces … and it is what caught every one of the
nine."* That is true for the 41 gallery scenarios and **false for these six files**.
The recommended follow-up — adding `examples/performance/lab` to the sweep's corpus —
is booked, not done here: the lab currently *refuses to mount* at the ten-foot rung
(17px over, pre-existing), so adding it would land a red on a defect this round did
not create.

## MED-2 — `foreign_content`'s seam literal now has a mechanical pin

The wrong form passed the whole suite *and* the lint; only a comment stood in the way.
The refusal ladder `foreign_instances.luau`'s header already describes now covers a
wrong-typed **field** as well as an unknown **kind**: `CONTENT_SCHEMA` declares each
kind's field types beside the code that writes them onto engine properties, and
`validate()` runs at the top of `build()`.

The case drives it from the **shipped descriptors** (`foreign_content.build(...)`'s own
`foreignContent` table), not from a fixture's copy, and pins both directions.
**Proven to bite:** with `textSize = "control"` planted in the shipped scenario —

```
✗ every SHIPPED foreign descriptor crosses the seam with the types the engine takes
    expected /ForeignContent/Page/Panes/Rich/Pane: foreign 'richText' field 'textSize'
    must be a number — it is written straight onto an ENGINE property, which takes no
    theme name — got string (control) to be
```

…and `build` raises rather than answering a half-built Instance; the number form and
the absent-optional form are both still accepted, so the check is not "refuse always".

## MED-3 — the autoscroll witness for sub-finding (a), produced honestly

The review was right: the shipped fixture at 844×390 is **regular**, so the deleted
option already resolved to the framework's 40 there and sub-finding (a) — *"branched on
the SCREEN's size class rather than the HOST's shape"* — had no witness.

I found the configuration where the two genuinely disagree and added a case at it:
**599×700** is under Facet's 600px compact boundary (`sizeClass = compact`, measured),
so the deleted code would have asked for `autoscrollBandCompact = 44`, while the racer
list host solves **567×309** — wider than it is tall, which is the shape api.md gives
**40**. The host's half-height (154) clears both bands, so the band is the band rather
than `rect.h / 2` — the case asserts all three of those facts before it measures
anything.

**Red against the SHIPPED PRE-FIX SOURCE, not a mutation.** Restoring
`RacerList.luau` + `TableMetrics.luau` + `init.luau` to `ca50fdb^`:

```
✓ the autoscroll band is the HOST's 40, not the screen-class 44 this package used to force
✗ the band follows the HOST even where the SCREEN's size class disagrees (599x700)
    expected 42px deep: dwelling to be 42px deep: idle
```

The old case stays green and the new one reds — which is precisely the review's
finding, demonstrated.

## LOW-1..4 — corrected in place, above

* **LOW-1** 70 → **144 across five scenarios**, with the per-scenario split; 70 was
  `sponsor_motion`'s own count.
* **LOW-2** "31 in a 30-frame window" → **61**, which is what the case that ships
  reports over its 60 frames.
* **LOW-3** the "caught by reading the diff" sentence now says only `foreign_content`
  was invisible; `variable_extents`' wrong form reds **11 cases**.
* **LOW-4** `StoryFlow:tick` → **`StoryFlow:step` (`:1290`)**; "one marker covers one
  literal" → **one reportable LINE**. Two other LOW-4 items are commit-message text
  (`d489832` says 364 where 365 reproduces; `a81beb2` says 355 where 353 reconciles) —
  the report's numbers were the right ones and are unchanged; the messages are
  immutable and the discrepancy is recorded here.

## Fix-round-1 commits

| repo | sha | subject |
|---|---|---|
| Facet | `f64230b21` | the predictor spends what the row spends, and the lever keeps its literal |
| Facet | `a8c5b39ea` | the lint says what its guarantee is worth, and reports the files that can break it |
| Facet | `779f59081` | the seam that crosses types is checked at the crossing |
| RR | `7db53a8` | the band's third bug gets the configuration that can see it |

**Case accounting.** Facet 7057 → **7062**: four in `theme_drift.spec` (the coupled
message, the uncoupled control, the pinned coupled set, long comments in both
directions) and one in `foreign.spec` (the seam's type contract). RR 3469 → **3470**:
the 599×700 band witness. `f64230b21` adds no case — its evidence is the differential
above, which is reproducible from the two trees at any time.

**Not touched, on instruction:** `tools/lune/gate_manifest.luau` (MED-1; the
navgate-repin round owns those rows and is mid-edit in the shared tree — it is the one
file `stylua --check tools` reports, and it is excluded from all four commits).
