# Task report — the overflow guard (layers 1 and 3)

**Director order, 2026-08-21:** *"how do we ensure our test system catches those
overflows like with the 9 and prevents them"*.

**Status: DONE.** Layer 1 (the harness containment invariant, on by default) and
layer 3 (sweeps open declared states) are built, rolled out over the whole suite
and the whole sweep corpus, and CALIBRATED AGAINST THE ESCAPE ITSELF — checked
out at `27af00f^`, the new state walk reports the director's own `9`, 8px and 4px
past the plate's right edge, at four of nine viewports. The same walk at HEAD is
silent. Layer 2 (solver-side enforcement) is untouched: it is the extraction
mission's charter and the solver is locked.

---

## 1. What escaped, and which of the three holes each layer closes

The region-expand plate painted its `9` 8px past its own panel edge, live, at
every viewport, while the 180-cell demo sweep and the whole suite were green.
Three independent holes, and the instance fix (`27af00f`) closed none of them:

| # | Hole | Closed by |
|---|---|---|
| a | **The sweeps never open stateful surfaces.** The plate exists only after a tap; every sweep mounts, settles and judges. | **Layer 3** — `built.states()` on the scenario contract, driven by `tests/overflow_sweep.spec.luau` and by the §14a Studio driver. |
| b | **The oracles ask the wrong question.** `device_matrix.observe()` asks "is this rect off the VIEWPORT" (`absPos.x < -1 or right > vw + 1`). The plate was fully on screen. Nothing anywhere asked "is this rect outside the box it lives in". | **Layer 1** — `tests/lib/overflow_guard.luau`, mirrored into the Studio driver. |
| c | **Nothing forbade a zero box.** A visible, non-empty Text solving 0 wide is copy the player cannot read. | **Layer 1**, second rule. |

---

## 2. What was built

### Layer 1 — the containment invariant, on by default in every fixture world

* **`tests/lib/overflow_guard.luau`** (new). Two rules, over the adapter's own
  node census:
  1. every **effectively-visible painted** node's rect is contained by its
     nearest **containment boundary**;
  2. a visible, non-empty Text never has a zero-width or zero-height box.

  **Effectively visible is the ANCESTOR CHAIN**, not the node's own flag. This is
  the campaign's own instrument lesson made structural: the forensics on this
  defect misread own-`Visible` on a hidden variant subtree and reported the
  collapsed `12`/`9` solving width 0 as a second defect. They are the hidden
  form-1 subtree, every node of which the framework marks invisible. A guard on
  own-`Visible` would have shipped a permanent false positive on the exact
  surface it was built for. There is a spec case for precisely that pair.

  **A containment boundary** is the nearest ancestor that is a scroll host
  (`ScrollView` — its box is the engine `windowRect`, and it binds on the CROSS
  AXIS ONLY, because content along the scrolled axis is reachable), a clip host
  (`clipChildren`, a CanvasGroup fade group, a `Foreign` box), or a **panel**
  (any node with a real `surface`). `plain` is not a panel — it is the suppressed
  surface and paints nothing, so treating one as a boundary would invent an edge
  the player cannot see.

  **What it deliberately cannot see**, stated in the module rather than left to
  be discovered: motion (travel is composed into `presentedPosition`, ADR-0022
  Decision 2, so a node in flight is inside its box as far as this census is
  concerned) and the R18 hit-expander floor (`setHitRect` is a FIELD on the
  control's handle on both targets — never a node — so it never enters the
  census at all).

* **`tests/lib/overflow_waivers.luau`** (new) — the explicit waiver registry.
  A waiver names a node pattern, a kind, a REASON, an OWNER and a `maxPx` cap
  (deliberate overflow has a size; a cap is what stops a waiver covering the next
  bug). **It ships EMPTY, and that is a measurement** — see §4.

* **`tests/lib/world.luau`** — the invariant runs after every `present()` and
  after every `settle()` (once, after the frame loop, not per frame). **Off is a
  REASON, not a boolean**: `overflowGuardOff: string?`. `false` is not accepted,
  because an unexplained "off" is how an always-on check quietly stops being one.

* **`tests/overflow_guard.spec.luau`** (new, 15 cases) — every rule shown biting
  on a screen built to break it AND silent on the screen one edit away that is
  legal: the plate that does not hold its content (28px, named edge) vs the same
  plate 36px wider; the transparent `Hit` vs the same Button with a label; the
  scroll canvas along its axis vs a row across it; the zero-box vs the identical
  box inside a hidden subtree; the world red-by-default vs the stated exemption;
  and the waiver machinery (a match silences and counts, a smaller cap refuses
  and names itself, and a **negative control** proves the unused-waiver detector
  works on a ledger of its own). Required **last** in `tests/run.luau` because
  "every waiver still fires" is a claim about the whole process.

### Layer 3 — sweeps open things

* **`examples/gallery/scenarios/hud.luau`** — the HUD declares `states()`:
  every expandable region (derived from the framework's own resolution, so the
  list is correct at each viewport rather than hand-written and short) plus the
  overflow sink. Measured: 4 states at compact-phone portrait, 1 at desktop.

* **`examples/gallery/scenarios/runner.luau`** — the scenario runner gains
  `api.states()` / `api.openState(id)`, both published as BindableFunctions for
  the MCP bridge, **and the missing generic `expand` step** (booked as L3):
  `presenter.expand(path)` is the framework's own second route to a region's
  disclosure, and until now a driver could only reach it if a fixture had
  hand-written a step. `api.steps()` lists the generic ones too, because a step a
  driver cannot discover is a step nobody drives.

* **`tests/overflow_sweep.spec.luau`** — a `stateProblems` walk (fresh mount per
  state, for the same reason the resize probe already takes one), wired into both
  the generic surface sweep and a new per-viewport HUD case,
  *"every state the HUD opens into holds its own boxes"* (9 new cases). The
  settled screen also gets the containment oracle at the default preference on
  the neutral pass.

* **`tools/studio/device_matrix.luau`** — the §14a driver (Studio-only; it is
  installed into the open place from `studio_sync`'s `/driver` route). Two
  changes: `observe()` now also reports `containment` and `zeroBoxes` — the same
  two questions, asked in the one vocabulary a live tree has (paint = non-empty
  `ContentText` or a `facet-surface-*` tag; ancestry = the flat instance NAME
  prefix, because the live instance tree is FLAT; the walk stops at a clip host
  or `ScrollingFrame`) — and `rowRecord().ok` now requires both to be empty. A
  new **`mode = "states"`** opens each declared state and re-observes it.

---

## 3. Roll-out and triage — found / fixed / filed / waived

| | count | detail |
|---|---|---|
| **Found** | **1 class, 19 suite cases** | Every one was `scroll_snap.spec`: a virtual list/grid row's full-width transparent `Hit` Button overhanging its list by exactly **8px** — the scroll bar, whose window the fixture's layout does not reserve (`fake_target._deriveWindowRect`). |
| **Fixed** | **1 (the instrument)** | A transparent hit target paints nothing, so it cannot paint outside anything. This is the HOUSE rule, not a new one: `tools/lune/triage_overflow_waivers.luau` had already measured it from the other direction ("counting one is how this probe manufactured its first false positives"). Pinned both ways in `overflow_guard.spec` — the bare `Hit` is silent, the same Button with a label is reported. |
| **Filed** | **0** | No real product defect was found by the roll-out. |
| **Waived** | **0** | See §4. |

**The corpus this was measured over, not guessed at:** the whole overflow-sweep
corpus — 46 surfaces × 9 viewports = **630 mounted cells, 49,224 nodes, 24,892 of
them painting** — reports **ZERO** containment violations at settle, plus the 33
fixture worlds of the suite. That number is what makes the state walk the
headline: at settle everything in this framework is inside its box, and the
defect lived entirely in a surface no settle had ever seen.

---

## 4. The waiver registry ships empty, and one expected waiver was measured wrong

The brief named three candidates. All three were checked and **none needs a
waiver**:

* **the R18 hit-expander floor** — not a node. `setHitRect` is a field on the
  control's own handle on both targets, so a sub-44px control's expanded target
  never enters the census. The floor is pinned where it belongs.
* **motion** (marquee / reveal / slide-in) — the guard reads SOLVED rects and
  travel is composed separately (`presentedPosition`). Outside the census by
  construction rather than by a waiver somebody has to remember.
* **the corner close disc (DIR5 item 4)** — **expected to need one and measured
  not to.** DIR5's own construction proves itself: *"the straddle is a MARGIN on
  the plate rather than an offset on the disc, which is what keeps the disc
  inside the panel's box"*. Driven at HEAD on all three HUD expand states at
  compact-phone portrait, `ExpandPanel/ExpandClose` sits inside its panel on
  every edge. **A waiver written from the prose rather than the geometry would
  have been rot on the day it was added** — which is the whole argument for the
  no-rot rule, made by the first waiver anybody tried to write.

An empty registry makes "every waiver still fires" a sentence about nothing, so
the no-rot case proves the **detector** on a ledger of its own first (a waiver
matching `/NoSuchNodeAnywhere$` is NAMED as unused), and only then applies the
real check to the real registry.

---

## 5. Calibration — the proof bar

### 5a. The guard catches the escape (private copy at `27af00f^` = `813f779`)

`git archive 27af00f^`, the two new guard files copied in, the HUD's `states`
block ported onto that commit's `hud.luau`, driven through the declared state
walk. **Verbatim:**

```
=== compact-phone-portrait (359x718) — declared states: expand:Tasks(expand), expand:Health(expand), expand:Clock(expand), overflow(disclosure) ===
   state 'expand:Tasks': OPEN, clean
   state 'expand:Health': OPEN, clean
   state 'overflow': OPEN, clean
  compact-phone-portrait (359x718) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ClockStack/ScoreAway/Plate [Box] overflows /Expand:Clock/Layer/Surface/ExpandPanel past its right edge by 8.0px
  compact-phone-portrait (359x718) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ClockStack/ScoreAway/ScoreAwayRow/ScoreAwayT [Text] "9" overflows /Expand:Clock/Layer/Surface/ExpandPanel past its right edge by 4.0px

=== compact-phone-landscape (705x338) — declared states: expand:Tasks(expand), expand:Rail(expand), overflow(disclosure) ===
   state 'expand:Tasks': OPEN, clean
   state 'expand:Rail': OPEN, clean
   state 'overflow': OPEN, clean

=== tablet-landscape (1079x809) — declared states: overflow(disclosure) ===
   state 'overflow': OPEN, clean

=== desktop-standard (1232x1067) — declared states: overflow(disclosure) ===
   state 'overflow': OPEN, clean

=== console-ten-foot (1920x1078) — declared states: overflow(disclosure) ===
   state 'overflow': OPEN, clean

=== narrow-portrait (320x640) — declared states: expand:Tasks(expand), expand:Health(expand), expand:Clock(expand), overflow(disclosure) ===
   state 'expand:Tasks': OPEN, clean
   state 'expand:Health': OPEN, clean
   state 'overflow': OPEN, clean
  narrow-portrait (320x640) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ClockStack/ScoreAway/Plate [Box] overflows /Expand:Clock/Layer/Surface/ExpandPanel past its right edge by 8.0px
  narrow-portrait (320x640) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ClockStack/ScoreAway/ScoreAwayRow/ScoreAwayT [Text] "9" overflows /Expand:Clock/Layer/Surface/ExpandPanel past its right edge by 4.0px

=== narrow-landscape (640x320) — declared states: expand:Tasks(expand), expand:Rail(expand), expand:Actions(expand), overflow(disclosure) ===
   state 'expand:Tasks': OPEN, clean
   state 'expand:Rail': OPEN, clean
   state 'overflow': OPEN, clean
  narrow-landscape (640x320) with state 'expand:Actions' OPEN: outside-parent: /Expand:Actions/Layer/Surface/ExpandPanel/ActionsCol/A1 [Button] "..." overflows /Expand:Actions/Layer/Surface/ExpandPanel past its left edge by 8.0px
  narrow-landscape (640x320) with state 'expand:Actions' OPEN: outside-parent: /Expand:Actions/Layer/Surface/ExpandPanel/ActionsCol/A2 [Button] "=" overflows /Expand:Actions/Layer/Surface/ExpandPanel past its left edge by 8.0px
  narrow-landscape (640x320) with state 'expand:Actions' OPEN: outside-parent: /Expand:Actions/Layer/Surface/ExpandPanel/ActionsCol/A3 [Button] "v" overflows /Expand:Actions/Layer/Surface/ExpandPanel past its left edge by 8.0px

=== desktop-studio-1320 (1320x742) — declared states: overflow(disclosure) ===
   state 'overflow': OPEN, clean

=== phone-390x844 (390x844) — declared states: expand:Tasks(expand), expand:Health(expand), expand:Clock(expand), overflow(disclosure) ===
   state 'expand:Tasks': OPEN, clean
   state 'expand:Health': OPEN, clean
   state 'overflow': OPEN, clean
  phone-390x844 (390x844) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ClockStack/ScoreAway/Plate [Box] overflows /Expand:Clock/Layer/Surface/ExpandPanel past its right edge by 8.0px
  phone-390x844 (390x844) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ClockStack/ScoreAway/ScoreAwayRow/ScoreAwayT [Text] "9" overflows /Expand:Clock/Layer/Surface/ExpandPanel past its right edge by 4.0px

TOTAL CONTAINMENT VIOLATIONS ACROSS THE STATE WALK: 0  ← at HEAD
TOTAL CONTAINMENT VIOLATIONS ACROSS THE STATE WALK: 9  ← at 27af00f^
```

The raw geometry behind the headline row, read off the same run: panel
`ExpandPanel` at `129.3,150.0 208.0x98.0`, `ScoreAway/Plate` at
`319.3,159.0 26.0x30.0` (right edge 345.3 vs the panel's 337.3 → 8px), and the
`9` itself at `323.3,163.0 18.0x22.0` (right edge 341.3 → 4px). That is the
director's own measurement — *"panel 208 wide at x=130, children spanning
138..346"* — reproduced by an instrument rather than by an eye.

**Three things this calibration also establishes:**

1. **The SETTLED screen is clean at BOTH commits** (0 violations, `27af00f^` and
   HEAD). Layer 1 alone would not have caught this. It took layer 3 to put the
   surface on the screen.
2. **The defect was not one node.** The same walk found a SECOND instance the
   director never saw: at narrow-landscape, `Expand:Actions`' three buttons 8px
   past the panel's **left** edge — the same `plate.w` defect on a different
   zone. The fix was general; nobody had proved it.
3. **A viewport-only sweep would have missed it too**: it fires at 4 of the 9
   swept viewports and is silent at 5.

### 5b. A fresh mutation at HEAD

Planted in a private copy at HEAD: `src/blueprint.luau`'s `panelOf` width reverted
from the DIR5 hug to the pre-fix `{ type = "fixed", px = plate.w }` — i.e. the
panel shrunk under its own content, exactly as the brief asks. The new sweep case
goes RED at 4 of 9 viewports:

```
  ✗ compact-phone-portrait (359x718): every state the HUD opens into holds its own boxes
      compact-phone-portrait (359x718): 2 containment violation(s) in a state this HUD can be OPENED into — a surface that does not exist until it is tapped, and that no settled sweep has ever laid eyes on (tests/overflow_sweep.spec.luau, the state walk):
  compact-phone-portrait (359x718) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/ClockStack/ScoreAway/Plate [Box] overflows /Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate past its right edge by 8.0px
  compact-phone-portrait (359x718) with state 'expand:Clock' OPEN: outside-parent: /Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/ClockStack/ScoreAway/ScoreAwayRow/ScoreAwayT [Text] "9" overflows /Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate past its right edge by 4.0px
  ✓ compact-phone-landscape … ✓ tablet-landscape … ✓ desktop-standard … ✓ console-ten-foot
  ✗ narrow-portrait (320x640): … 2 containment violation(s) …
  ✗ narrow-landscape (640x320): … 3 containment violation(s) … past its left edge by 36.0px
  ✓ desktop-studio-1320
  ✗ phone-390x844 (390x844): … 2 containment violation(s) …
  4 failed, 90 passed
```

Every OTHER case in the file — including all nine settled-screen HUD cases —
stayed green under the mutation. The mutation was removed; nothing was committed
with it.

---

## 6. Suite tails

All suite measurement was done in **private content-pinned copies**
(`git archive <sha> | tar -x` into a scratch tree), never in the shared working
tree, because two other rounds are in flight there (the paint-lockstep round and
the native-style flip round). An early measurement taken against a working-tree
copy reported 11 red — every one of them `native_style_default.spec`, i.e. the
flip round mid-edit. That is exactly why the rule exists; every number below is
from a pinned archive.

**Facet**, pinned at `66b49de` (the commit-time pin), same archive for both runs:

```
baseline (archive as-is):                6949 passed, 0 failed
with the overflow guard overlaid:        6973 passed, 0 failed
```

`+24` cases: 15 in `tests/overflow_guard.spec.luau`, 9 in the sweep's new HUD
state walk. **Zero failures on either side.** The same paired measurement taken
earlier at pin `a9af1a1` gave `6939 -> 6963` — the same `+24`, on a suite that
grew by 10 cases underneath this task while three rounds were landing.

**RascalRally**, run in a mirrored tree (`GameStudio/ui/Facet` = archive at
`4f86ac5`, RR at working tree):

```
Facet HEAD, unmodified:                  2 failed, 3462 passed
Facet HEAD + this task's changes:        2 failed, 3462 passed
```

**Byte-identical.** The two failures are PRE-EXISTING at Facet HEAD with an
entirely unmodified tree — `facet_large_text_sweep` (NameTag overflows) and
`facet_large_text_results` (`/Results/…/Ctas` painting) — and this task touches
no `src/` file at all, so they belong to whichever concurrent round is mid-flight
in `src/layout/solver.luau` / `src/client/screen_target.luau`. Reported, not
adopted.

> **ERRATUM (2026-08-21, `task-rr-reds-report.md`) — the paragraph above is
> WRONG and is retracted.** `4f86ac5` was **not** Facet HEAD; HEAD was `3183740`,
> seven commits later. The pin sits one commit *before* `4110ba1`, the DIR5
> `src/client/roblox_env.luau` input-primacy fix — and RR `4fdb0e6`, the working
> tree used here, is that fix's own consumer rider. So the pair ran the game's
> proof of a framework fix against a framework without it. The two reds are
> `facet_composition_collision_contract.spec:502` and `:516`, **not** the
> large-text specs (both of those are green in that very run, 46/46). Rebuilt
> honestly, RR is **3464 passed / 0 failed** at `19dc1cb`, `3183740`, `6addc5e`
> and every commit since. Nothing was mid-flight in `solver.luau` /
> `screen_target.luau`; nothing needed adopting.

**Cost.** `overflow_sweep.spec` alone, same machine, back to back:
**27.00s → 27.26s (+1.0%)** for the settled containment oracle on 414 cells plus
9 state-walk cases at 9 viewports. Well inside `check_tier_costs`' 50% tolerance,
so `tests/lib/tiers.luau`'s recorded 16,342 ms needs no re-record.

`stylua --check` clean on all nine touched files.

### Commits

| sha | what |
|---|---|
| `19dc1cb` | the guard, the waiver registry, the spec, the world wiring, the state walk, the HUD's `states`, the runner's `states`/`openState`/`expand`, the Studio driver's oracle + `states` mode, and this report |
| `3183740` | the repair: six lines of another round's `tests/run.luau` edit that rode in on my hunk, handed back (see §8.6) |

**The committed tree was run, not just the working tree:**
`git archive 3183740` into a private copy → **6982 passed, 0 failed**.

---

## 7. The RascalRally seam (checked, no churn manufactured)

**RR does NOT share `tests/lib/world.luau`** — measured: zero RR specs require
it. It shares `tests/lib/fake_target.luau` (19+ specs). So the layer-1 invariant
does **not** ride along into RR's contract specs automatically.

**The seam is one line wide, and it is worth booking rather than taking now.**
`overflow_guard.violations(adapter)` reads nothing but the adapter's own census,
so any RR spec already holding a `fake_target` can call it with no new machinery
and no new dependency direction. The honest follow-up is either (a) an RR
`tests/lib/world` of its own that runs the invariant, or (b) a single RR
contract spec that walks its shipped screens through the guard. Both are product
decisions about RR's harness, not framework work, and neither is needed to make
this task's claim true.

---

## 8. Concerns and limits, stated

1. **The Studio driver half is NOT verified live this session.**
   `tools/studio/device_matrix.luau` is Studio-only (it needs
   `StudioDeviceSimulatorService`, `GetStyled`, `TextFits`, `AbsolutePosition`);
   no Studio session was driven here. The logic is written to mirror the headless
   oracle and its two known limits are stated in the file — instance names cap at
   100 chars (so a deep node's boundary may be MISSED, never invented) and the
   `facet-surface-*` tag exists in the sheet-paint vocabulary (a bespoke-painted
   surface is not a boundary there). Both failure directions are silence, which
   is the right way for a live oracle to be wrong, but the row still owes a live
   pass on the next Studio session.
2. **The live oracle is a MIRROR, not the same code.** The headless guard reads
   the adapter census; the driver reads the engine dump. They are kept in
   lockstep by comment and by shared reasoning, which is this repository's
   existing idiom (`SCALE_MODE_ENGINE_NAME`, `SCROLL_BAR_THICKNESS`) but is
   weaker than one module. A shared pure oracle would need a home under `src/`,
   which means a manifest row, a public-surface baseline and a source-cap
   ledger entry — churn this task deliberately did not take.
3. **Layer 3's generic hook has one consumer.** Only `hud` declares `states`
   today. The walk is wired into the generic surface sweep as well (one table
   lookup for a surface that declares nothing), so the day a second fixture grows
   a plate the sweep opens it without anybody remembering to — but until then the
   generic arm is an extension point rather than coverage, and it should be said
   plainly rather than counted.
4. **The state walk does not CLOSE what it opens.** Headless it takes a fresh
   mount per state, which is clean. In Studio it opens and leaves open, because
   driving a dismissal from the driver would be counterfeiting input — the one
   thing that file's header forbids. The caller resets between walks
   (`FacetScenario.reset()`), and the mode says so in its own `note` field.
5. **One instrument gap found and NOT fixed** (out of scope, worth booking):
   `tests/lib/world.luau`'s `fake_target` does not publish
   `adapter.scrollBarThickness`, while `tests/overflow_sweep.spec`'s world does.
   So every scroll fixture built on the shared world lays out against the frame
   while the engine window is 8px narrower — the exact disagreement
   `fake_target.setScrollRegion`'s own comment warns about. It surfaced here as
   19 hit-target findings and was correctly ruled not-paint, but the underlying
   fixture/engine divergence is real and is a separate mission.
6. **`commit_isolated`'s one documented hole was hit for real, and is recorded
   rather than smoothed over.** The tool diffs at `-U1` to keep the marker window
   narrow, and its header says plainly that when two agents are inside the same
   few lines nothing short of a worktree separates them. That happened: the
   extraction round's `require("./containment_diagnostic.spec")` landed six lines
   above mine in `tests/run.luau`, INSIDE that one-line window, so the marker
   filter took the whole hunk and `19dc1cb` shipped a require for a file that is
   still untracked — HEAD did not load. Caught by the discipline that exists for
   it: the post-commit verification run of the COMMITTED tree, not of the working
   tree. Repaired in `3183740` by removing only those six lines through the same
   private-index/CAS mechanism, leaving the working tree untouched so the
   extraction round still holds its edit and its file and can commit both
   together. Verified after the repair: **6982 passed, 0 failed**, with the
   no-waiver-rot case last in the run, as designed.
7. **The lesson, generalised:** `git show <mine> -- <shared file>` after the
   commit, and a suite run of the COMMITTED tree, are the only things that can
   see this class. A dry-run's KEEP/drop list cannot — it reported one clean
   `KEEP` for the hunk that contained somebody else's line.

---

## 9. Follow-up triage — the composition-region class (312), routed here by the solver-split round

**Handover.** `435dade`'s report (concern 2) counted, while scoping its own
settle-time containment diagnostic, a class it deliberately did not ship: **a
composition REGION placed below its composition's own content box, 312 times
suite-wide** — `/HudScreen/Hud/*`, `/CompositionScreen/.../Summary/*`, `/S/C/*`,
overhangs 2–235px — on the grounds that the collision finding compares regions
against EACH OTHER and never against the box.

### The count: 312, reproduced exactly

Same probe, same place — the composition's own arrange branch in
`src/layout/solver.luau`, comparing each `placed.rect` against the composition's
content box — installed in a content-pinned private copy and run over the whole
suite:

```
TOTAL 312   fallback=true 312   fallback=false 0
-- by composition --
    107  /CompositionScreen/Body/OfferFrame/Summary
    197  /HudScreen/Hud
      8  /S/C
```

Not corrected. **312.**

### VERDICT: deliberate composition behaviour — it is the declared FALLBACK, and the framework already reports it

Four measurements decide it, and each is a different way the verdict could have
gone the other way:

1. **312 of 312 carry `fallback = true`; zero are a legal composition.** The
   fallback is the framework's own statement that nothing fits — the one finding
   in this framework marked `designed = true` — filed once per solve on the
   composition, naming the offer and the last rejection: *"no declared
   arrangement is legal in 304x0 — showing 'hud' as the declared fallback (last
   rejection: overflow — lane 1 (left) needs 78px but the composition was
   offered…)"*. A per-region re-telling would be the same duplication the solver
   round rejected 4,103 main-axis rows for, and would call the framework's own
   `designed` verdict a defect in the same breath.
2. **312 of 312 are the BOTTOM edge.** There is no horizontal instance and cannot
   be: `placed.rect` is the SLOT the partition allotted and the partition is
   clamped to the box. Only the fallback column's tail runs past it. (Measured
   directly: a trail region declared 800 and 1200px wide in a 700px composition
   produces no horizontal escape at all — its *content* overflows its slot, which
   is a different question already answered by the inner stack's own overflow
   finding and by this guard's panel/clip containment.)
3. **A LEGAL composition cannot produce one**, and this is structural rather than
   incidental. Measured at the boundary on a 700x400 composition: a lead form
   **400** tall keeps `threeLane` legal and every region inside the box; **420**
   — twenty pixels later — has the arrangement REJECTED and the fallback places
   `Hero` 20px, `Field` 48px and `Ctas` 116px below the box. The legality check
   bounds vertical fit, so *"a region left the box"* and *"the composition fell
   back"* are the same event.
4. **Where it fires, nothing escapes paint.** On the worst cell in the suite —
   narrow-portrait 320x640, `preferredTextOffset` +14, Pixel Quest, strip down —
   the composition is offered **304x0**, and: **0** region-vs-region collisions,
   **0** regions outside the screen, **0** violations from this guard. The three
   surviving regions land inside 320x640.

**The underlying pressure is fixture-side and the fixture already documents it.**
`/HudScreen` carries the HUD composition (`fill`) beside `Drivers`, two developer
`UI.Toggle`s that WRAP to two lines (168px) at that size under that package;
with the showcase's 120px chip reservation the `fill` composition is left zero
height. `examples/gallery/scenarios/hud.luau`'s own comment already records it:
*"This Screen has UNDER 8px of headroom at 320x640 with preferredTextOffset =
+14"*. **No fix taken**: there is no small fixture-side change here — buying the
HUD headroom means changing what the demo demonstrates — and the framework's
report of the state is already correct, specific and marked designed.

### What shipped instead: a documented negative rule, and two cases that pin it

A composition is **deliberately not a containment boundary** in
`tests/lib/overflow_guard.luau`, the way `anchor` and `zstack` are deliberately
unpoliced one layer down. The reason and its measurement are written into the
module's boundary docstring and into `tests/lib/overflow_waivers.luau`'s
"things that are not here" list — **not** as a waiver, because a waiver would
have hidden a class where a stated rule explains it.

And the verdict is pinned by two cases in `tests/overflow_guard.spec.luau`, so
the class can never again be countable-but-invisible:

* *"A LEGAL composition keeps every region inside its own box"* — the property,
  positive, at hero 400;
* *"...and twenty pixels later NOTHING is legal, so the regions leave the box AND
  the framework says so"* — the class reproduced in miniature at hero 420, with
  the `designed = true` fallback finding asserted by name and this guard asserted
  silent.

**Three mutations bite, one red each** (17 cases in the file):

| # | mutation | result |
|---|---|---|
| C-M1 | the positive case is handed the fallback height (its property goes vacuous) | **1 red** |
| C-M2 | the fallback finding stops being marked `designed` | **1 red** |
| C-M3 | a `Composition` becomes a containment boundary in the guard | **1 red** |

### Suite

Content-pinned at `233de1a`, same archive both runs:

```
baseline                       7000 passed, 0 failed
with the two pinning cases     7002 passed, 0 failed
```

**RascalRally**, mirrored tree at the same Facet HEAD, paired:

```
before   3465 passed, 0 failed
after    3465 passed, 0 failed
```

**And a correction to §6, made rather than left standing:** the two RR failures
that section records as pre-existing at Facet HEAD (`facet_large_text_sweep`,
`facet_large_text_results`) are **gone** — RR is 3465/0 at the current HEAD. They
were the concurrent solver/paint rounds mid-flight, exactly as §6 attributed
them, and those rounds have since landed. The attribution was right; the number
in §6 is a snapshot of a tree that no longer exists.
