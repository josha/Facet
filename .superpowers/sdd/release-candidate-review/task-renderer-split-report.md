# task-renderer-split — the last locked file stops being one file, and the room buys the fix that was gated on it

**Status: COMPLETE.** Both phases shipped plus the two debts the split itself
created, all suites green, and `src/render/renderer.luau` ends the mission with
**17,478 characters of headroom against the 1,026 it started with** — 17x, after
paying for everything.

| | at dispatch | after Phase A | at close |
|---|---|---|---|
| `src/render/renderer.luau` | **198,974** (1,026 to the cap) | 182,003 (17,997) | **182,522 (17,478)** |
| position vs the 190,000 warning line | **8,974 INSIDE** | 7,997 clear | **7,478 clear** |
| Facet suite | 7,000 | 7,016 | **7,036** |
| Rascal Rally suite | 3,465 | 3,465 | **3,466** |

Commits, all through `tools/commit_isolated.py` with hunk markers on every shared
file:

| commit | what |
|---|---|
| **`4cc5cb0`** | Phase A — the split |
| **`935f9a2`** | Phase B — the hit-floor rule (ADR-0041, row **B-19**) |
| **`5c407cc`** | the one hunk `935f9a2`'s marker filter left behind (see Concern 1) |
| **`2e6c7d9`** | the comment-code exemption the extraction ends |
| **`753e088`** | the brand-drift exemption on the same lock, which was already red |

No other agent's work was swept in. `src/client/native_style.luau`,
`src/client/screen_target.luau`, `tests/native_style_default.spec.luau`,
`tests/lib/overflow_guard.luau`, `tests/lib/overflow_waivers.luau` and
`tools/mkpair.sh` were held by concurrent rounds throughout and none was touched.

---

## Phase A — the split

**`src/render/commit_walks.luau`** holds the six write loops that spend a finished
solve: `textScale` and `padding` (the two typography paint seams), `textVerdicts`
(the compact-ladder and wrap verdicts), `visible` (the hidden-candidate paint
walk), `hitRects` (the target floor) and `scrollRegions` (the native canvas with
its autoscroll and indicator declarations).

### Two corrections to the ledger's own prescription, both found by writing it

* **The prescribed seam had already left.** The row said "lift the RECT WRITE half
  of `solveAndApply` — the diff-and-write loop, not the solve — once `lastRects`
  is owned by a record object". That loop went to `render/rect_pass.luau` in
  **`c2b68e5` on 2026-08-17, one day before the row was written**, and it took
  `lastRects` with it as a by-reference table rather than needing a record at all.
  What shipped is the **rest of the same half** — the five other write loops the
  commit span runs beside it.
* **It cost neither a record nor an accessor**, for a different reason than
  `measure_facts` did: all twenty names that cross were already tables, functions
  or a parameter, every one declared once and never reassigned. That is not a
  claim in a comment — the seam spec runs the mutable-upvalue test against all
  twenty-one names over the live sources.

### The mechanised seam spec — `tests/commit_walks_seam.spec.luau` (16 cases)

This seam has a parameter object with **twenty-one fields, eight of them mutable
records the renderer keeps writing to after the walks have read them**, so the
house method's three sets are joined by two rules no previous seam here needed:

* **READ == DECLARED == PASSED** — the `ctx` fields the module reads (comments
  stripped) == its own `CommitCtx` type == the keys the renderer's
  `commit_walks.new({ … })` hands over, both directions. The third comparison is
  the half a parameter object does *not* give for free: the call is a table
  CONSTRUCTOR, so a field the module declares and the renderer forgot arrives as
  `nil`, which is a walk that silently stops writing.
* **The shared WRITE surface is exactly twelve names.** A thirteenth is state
  that has acquired two owners. `paintHeld` in particular is presenter-owned and
  must stay read-only here.
* **Every per-path record the walks write is CLEARED by the renderer's removal
  sweep** — the lifetime claim, mechanised, and the reason those records stay with
  the file that owns mounting.
* Plus **EXPORTED == CALLED**, one consumer, one-way require, no module-level
  mutable state, and that the module names nothing off the renderer's own module
  table (`renderer.compactForm` was a re-export; the walk calls `layout_node`).

**Thirteen mutations proved to bite** (each applied to a copy of the measured
tree, run, discarded; unmutated control 16 passed):

| # | mutation | red |
|---|---|---|
| M1 | an undeclared `ctx` read in the module | 1 |
| M2 | a `CommitCtx` field nothing reads | 2 |
| M3 | a declared field the renderer stops passing | 1 |
| M4 | a thirteenth shared write (`paintHeld`) | 2 |
| M5 | a per-path record the removal sweep stops clearing | 1 |
| M6 | one of the shared names reassigned in the renderer | 1 |
| M7 | the module rebinds one of them | 1 |
| M8 | module-level mutable state in the module | 1 |
| M9 | an export nobody calls | 1 |
| M10 | `require("./renderer")` added to the module | 1 |
| M11 | a second consumer appears | 1 |
| M12 | the module calls back through `renderer.` | 1 |
| M13 | the `renderer_source` part is dropped | 1 |

### Behaviour: byte-identical, proved twice, and NO spec was edited

* **Verdict-set diff.** 7,000 -> 7,016 against a content-pinned `git archive`
  baseline, diffed line-for-line: **zero removals**, and the sixteen added rows
  are the seam spec's own. Nothing else moved.
* **One spec went red and it was the INSTRUMENT, not the verdict.**
  `button_shape.spec` pins the line `adapter.setProp(handle, "textWrapped", wraps,
  "layout")` inside "the renderer's source", and that line moved with the walk.
  `tests/lib/renderer_source.luau` — whose own header reads **"ADD A PART HERE
  WHENEVER MORE OF THE RENDERER MOVES OUT"** — gained the part, and the pin went
  green reading the same line in its new file. That is the cost this file's splits
  always pay and the reason the instrument exists; it is a `tests/lib/` file, not
  a spec, and no spec verdict changed.
* **The differential oracle**, written for this round because the solver round's
  was private: **800 seeded blueprint trees** over the vocabulary the six walks
  touch (`Text`/`Button`/`Toggle`/`Box`/`Spacer`/`Divider` leaves with sub-floor
  sizes, icons, padding and `zIndex`; `VStack`/`HStack`/`ZStack`/`ScrollView`/
  `Grid`/`ViewThatFits` containers; random viewports and safe insets), each driven
  **three times — mount, a viewport change, a ten-foot flip** — because five of
  the six walks are minimal-write and the interesting output is the writes the
  later frames DO NOT make. It compares the adapter's **ordered operation log**
  plus every per-path field the walks own (rect, z, hitRect, visible, textSize,
  textFont, padding, label, icon, compactLabel, textWrapped, the scroll region and
  its window) plus the work counters: **328,839 comparison lines, `diff` exit 0,
  byte-identical**, 0 errors, 0 refusals.
  It is proved **deterministic** (two runs of the same tree diff clean, once the
  op log's table addresses are canonicalised) and **not vacuous** by three
  negative controls: the floor stops inflating (456 lines differ), the indicator
  opt-out is ignored (6), the text scale is dropped (86).

---

## Phase B — the hit-floor rule, in the freed room (ADR-0041)

**Red-first at the review's exact numbers.**
`tests/hit_floor_region_clamp.spec.luau` run against an unmodified export of
`4cc5cb0`: **6 failed, 2 passed** — `First 960 px2`, `Last 828 px2`, and
`9,360 px2` of the cover's floor outside its own region. The two that passed
before are the non-vacuity instrument and the F1 control, which is the shape a
control case has to have. After: **14 passed**.

### The bound is R18 as it was ruled, and the region box is NOT it

The brief prescribed "a class-keyed clamp… clamps at the region's bounds". **A
measurement refused that and it is the finding of this phase.** Clamping a cover
into its region shipped for one suite run and `overflow_sweep`'s *no dead-end
compact* guard reported it on **five viewports of the shipped HUD demo**: three
stepped-down covers (`Tasks` 75x23, `Health` 44x30, `Clock` 80x30) lost the F1
floor purely because their regions are short, and **not one of their un-clamped
floors reaches an interactive node at all** — measured, all three take NOTHING.
"A route the thumb cannot land on is a route on paper." The guard was right and
the first rule was over-applied.

R18's own ruling splits by **what is underneath**: the floor is EXEMPT over
passive content (the F1 accessibility floor, the platform convention) and BANNED
over interactive content. So the shipped rule is `commit_walks.growWithin`: the
floor **grows one side at a time, each side stopping at the first pressable rect
outside the node, never shrinking past what the node already paints.**

* `ringScreen`: the regions are edge to edge, both asks are refused entirely, the
  cover is left with the box it paints and the expander is retracted. **960 + 828
  -> 0 px².**
* The HUD's three covers keep **44px**.
* The one HUD region that IS boxed in (landscape `Tasks`: three author Buttons
  9.5px above, another region's cover 9.5px below, against a 10.5px ask) grows
  **42 of its 44** instead of losing all of it.
* An ordinary sub-floor control is **exempt**: `20x20 -> 44x44`, including over a
  pressable node in another subtree.

**Why not `effectiveHitFloor(node)`.** `syncZOrder` calls that same function to
reserve the expander's z slot, and NM-H4a fixed a whole-band paint defect on a
real device by making that reservation a function of the CLASS rather than of the
current state. A node-aware floor would move every z below every cover.

### EXPAND 15 stops bounding the exposure and asserts its absence

The plate-B round had already replaced "the overhang lift delivered it" (green
*because* the theft happened) with a bound on the overhang. There is no band left
to bound: the case now collects every interactive node under either role's floor
and asserts the list is **empty**. Its cover arm reads `mark.rect` where it read
`markHit`, because for a cover in that fixture the correct hit rect is `nil`.

### Eight mutations bite — and FOUR were findings rather than drills

| # | mutation | red |
|---|---|---|
| B-M1 | the rule is dropped (the defect restored) | 3 |
| B-M2 | it is applied to EVERY expander, not only a cover | 2 |
| B-M4 | growth never stops at a blocker | 7 |
| B-M5 | the one-directional guard is dropped (a floor may SHRINK) | 2 |
| B-M6 | a HIDDEN node still blocks | 1 |
| B-M7 | the far-side skip is removed (a rect above blocks growing DOWN) | 3 |
| B-M8 | a blocker BESIDE the rect is treated as in its way | 2 |
| B-M9 | the blocker set is empty | 3 |

**B-M2 was green first.** The F1 control put the sub-floor Button and the row it
overhangs in ONE stack — and a blocker contained in the node's own host skips on
all four sides by construction, so the two arms of the rule were never told apart.
The control now sits in two columns.

**B-M3 was green and the check is gone.** A "not my own region" filter restated a
fact the arithmetic already guarantees, and no mutation could redden it. Removed,
with the reasoning in its place.

**B-M5 was green.** `math.max(0, room)` sat beside a `granted <= 0` guard: one
belt too many, and the mutation could not tell them apart. The `max` is gone and
the guard now carries the one-directional rule by name.

**B-M6 was green** until the case stopped asserting that a hidden node is hidden
and started measuring the floor: one fixture, two arms (`hidden` / standing), the
floor `390x44` against `390x32`.

**A real arithmetic defect was found by the battery, not by the suite**: the
first draft's per-side skip tested only the OTHER axis, so a blocker *above* the
box contributed a negative "room" to the DOWNWARD side and clamped it to zero.
Every boxed-in-on-one-side cover lost its whole floor. B-M7 is that mutation,
kept.

### No collateral

The **800-tree differential oracle is byte-identical across Phase B** — the rule
reaches covers and nothing else. Verdict-set diff against `4cc5cb0`: **zero
removals**; the one line that appears to leave is this round's own seam-spec case
renaming itself from "twenty" to "twenty-one" when `inputSinks` joined the ctx.

### ADR row (B-19), for the controller to append

> **B-19 — a cover's touch floor grows until it meets something pressable, and no
> further.** *Changed:* the hit expander a region's `role = "cover"` affordance
> receives is no longer the unconditional 44px inflation of its solved rect. It
> grows one side at a time and each side stops at the first rect outside it that
> can sink a press; where nothing is in the way it is unchanged, and where it is
> boxed in on every side it is retracted entirely and the affordance is reached
> through the region's own box. *Why:* a cover IS its region's whole box, so the
> floor left the region across its full width — measured at 390x150 as 960 px² of
> one neighbouring Button and 828 of another, 26% of each, delivered to the plate
> instead of to the button the player aimed at (DIR5 review H1; the plate-B round
> corrected the mechanism and could not fix it from an unlocked file). *Bound:*
> R18 as ruled — exempt over passive content, banned over interactive — so an
> ordinary sub-floor control keeps its whole F1 floor, including the part that
> leaves its parent. *Blast radius, measured:* on every shipped fixture the only
> hit rects that move are covers'; the 800-tree differential oracle over every
> other walk's output is byte-identical, and the HUD demo's three stepped-down
> covers keep 44px. *Owner:* `src/render/commit_walks.luau`
> (`growWithin` + `hitRects`); pinned by
> `tests/hit_floor_region_clamp.spec.luau` (14 cases, 8 mutations) and
> `tests/region_expand.spec.luau` EXPAND 15.

---

## The two debts the split itself created, both paid in this round

`docs/handoff/SOURCE_CAP_LEDGER.md` gained a rule yesterday: **an extraction out
of an `EXTRACTION_LOCKED` module inherits none of its exemptions, and when the
extraction lands the file comes out of the list.**

1. **`check_comment_codes` (`2e6c7d9`).** Forty-one private codes in
   `renderer.luau` became prose — 33 that resolved nowhere and 8 that resolved but
   would have pushed the 25/25 total ratchet to 33, which that checker's own
   header forbids. `src/render/renderer.luau` is out of the tuple: three modules
   and 130 codes where it was four and 171. **And the round almost certified a
   check it had not run**: the checker walks `git ls-files`, so at the moment the
   split was measured the new module was untracked and invisible to it and it
   reported PASS. The three codes that rode out with the walks (`ADAPT-7`,
   `RS-A16`, `NS-A2`) were live orphans the instant the file was tracked. The
   coordinator caught this mid-flight; it is now recorded in the ledger row.
2. **`check_brand_drift` (`753e088`) — THE SAME DEBT IS ON TWO LISTS, and only one
   of them is named in the ledger.** That guard carries a second allowlist over the
   same five files with the same removal rule ("when the renderer extraction
   lands"), and running it found it **already FAILING** — one match in
   `commit_walks.luau` (mine) and one in `layout/measure_facts.luau`, which is the
   **solver split's** own escape riding out of its locked host three days earlier,
   red since then, caught by no guard at the commit that caused it. Seven
   references swept, both allowlist positions closed, `--selftest` PASS.

---

## Evidence

**Facet, content-pinned** (`git archive` exports; every measurement run there,
never in the shared working tree):

```
baseline (aa46cda)              7000 passed, 0 failed
Phase A, no spec                7000 passed  — verdict-set diff EMPTY both ways
Phase A + seam spec             7016 passed  — diff: +16, all the seam spec's own
confirmed at 4cc5cb0            7021 passed  — (+5 from rounds that landed between)
Phase B                         7035 passed  — diff: +15, zero removals
FINAL, fresh archive of 753e088 7036 passed, 0 failed
```

**Rascal Rally, paired export** (`git archive` both sides at call time, per
`tools/mkpair.sh`'s own rule):

```
control  Facet 4cc5cb0 + RR c3c8d49    3465 passed, 1 failed
mine     + Phase B                     3465 passed, 1 failed   ← identical case
FINAL    Facet 753e088 + RR c3c8d49    3466 passed, 0 failed
```

The one red present in **both arms** was `facet_theme_paint_contract`'s "the
ROLLBACK survives" — a concurrent round's native-paint work that RR's `c3c8d49`
had already committed against; it went green when that round landed. My change is
neutral across it.

**RR lockstep — hit-rect behaviour is consumer-visible and RR is a real
consumer.** `tests/facet_hit_expander_overhang_contract.spec.luau` (4 cases) and
`facet_racer_list.spec:213` (`hitRectOf(...).h == 44`) pin it. All green,
unchanged, no edit: RR's racer rows are ordinary sub-floor Buttons with
`minHitSize = 44` and no `expandTarget`, which is exactly the population this rule
exempts. `ExpandPanel` / `ExpandPlate` / cover-role greps: RR builds no plate at
all (`expand = "none"` on every region that would get one). Evidence-only, no
churn.

**Guards, run at my own commits, in the real tree:** `check_source_size`,
`check_types`, `check_library_purity`, `check_doc_style`, `check_comment_codes`,
`check_brand_drift` (+ `--selftest`), `check_input_authority`,
`check_call_shape_drift`, `check_gate_pins`, `check_manifest_integrity`,
`check_reuse_ledger`, `check_no_screen_key_bindings` — **all PASS**.
`stylua --check src tests` clean. (`check_comment_codes` and
`check_call_shape_drift` report `FAIL_ENVIRONMENT git ls-files` inside a `git
archive` export, which has no repository; both PASS in the real tree.)

## Ledger

The `renderer.luau` row **moved from "The band" to "Cleared the band"** and was
re-recorded three times — at the Phase A number, at the Phase B number, and
finally at **182,522 measured after the last `stylua` pass**, which is the rule
its neighbours learned the hard way. It carries the two corrections to its own
prior analysis, what the split cost (nothing), what the room was spent on, what is
left (`structuralSync` 49 KB and `ensureTree` 22 KB still fail the test by
construction; the drag bridge ~12 KB is the next honest candidate, and its two
reassigned scalars are the `table.luau` record move), and both exemption debts.

**Trigger: NOT ARRIVED, and the gap is stated** — 17,478 characters is the largest
headroom this file has had since the cap was measured, so the next extraction is
owed by SHAPE rather than by size: *the next mission that changes the recycle pool,
the removal sweep or the parked-props record takes the drag bridge first*, failing
which **190,000**, which is 7,478 above the recorded size.

## Concerns

1. **A hunk with no marker did not make its commit, and HEAD was red for one
   commit.** `935f9a2` renamed the seam spec's pinned count from 20 to 21, and the
   markers I chose (`twenty-one`, `inputSinks`) appear on every changed line
   except the one that carries the number itself. `commit_isolated` filters by
   HUNK, which is what makes concurrent work safe; the cost is that a marker must
   be chosen for what the *change* says, and a bare number says nothing. Caught by
   the seam spec's own non-emptiness rule on the next suite run, fixed in
   `5c407cc`. **Recommendation for the next round: `--dry-run` and read the KEEP
   list against `git diff --stat`, or pass the whole file when you own it.**
2. **`check_brand_drift` was red for three days and no guard caught it.** The
   solver split's `measure_facts.luau` carried a vendor name out of a locked host
   on 2026-08-21 and neither that round nor its review ran the guard whose
   allowlist named the file it came from. Swept here. **The general defect is that
   two lists key on the same lock and only one is named in the ledger** — that
   sentence is now in the row, but a checker that enumerated its own lock lists
   would be better than a paragraph.
3. **The differential oracle is private, as the solver round's was.** It lives in
   the scratchpad rather than in `tests/`, because 800 mounted trees is a
   ~1.3 s run that nothing in `run.luau` would consume and an uncalled fuzz
   harness rots. Its generator, its three negative controls and its determinism
   proof are described above; if the next split wants it, it is worth promoting to
   `tools/lune/` with a case-count argument rather than re-deriving.
4. **A cover boxed in on every side now has NO hit expander and a target the size
   of its region.** In `ringScreen` that is 390x20, which is under the thumb floor
   on one axis. It is strictly better than the alternative (a 44px band that opens
   the wrong plate), and `overflow_sweep`'s dead-end guard is silent because the
   route is 390 wide — but the real answer is the **R18 hit-floor reserve still
   BOOKED on the solver row** (reserve `markW` plus the floor's overhang so the
   region is never shorter than the floor). This round makes that reserve
   *sufficient* rather than merely nice: with it, a cover would never be boxed in.
5. **`inputSinks` is a per-solve linear scan per standing cover.** Covers are 0-5
   per screen and the set is tens of paths, so this is tens to low hundreds of
   rect tests per solve on a screen that has any. Measured only through the suite's
   own timings (no regression observed); a screen with dozens of standing covers
   would want the set spatially indexed, and nothing ships one.
6. **`src/client/screen_target.luau` still spells two of the moved walks by their
   old names** (`applyTextScale`, `applyPadding`). Deliberate: that file is 6,205
   characters from the cap and the rename is +8 characters it does not have. The
   `commit_walks.luau` header names all six old identifiers so the prose still
   resolves; the rename belongs to that file's own extraction round.
