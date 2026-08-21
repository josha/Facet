# Wave DIR4 — implementer report

**Status: COMPLETE**, with **two CONTESTED** items reported rather than papered over
(MAJOR-2's display-layer counter; the modal/chrome priority tie) and **one correction to
the brief's premise** (the R1 loss is a DOUBLE-FIRE, not a loss — measured; see item 3).

- Facet suite **6881**, green. Baseline 6865 at `3ad40b0`; **+16** is exactly this
  round's new cases (14 in `gallery_chrome`, 2 in `transient_over_live`).
- All measurement in private `git archive` exports (`export-head` = pristine `3ad40b0`,
  `export-mine` = HEAD + only my six files, `export-parent` = `130dcae`, `mut` = one
  mutation at a time). Nothing measured in the shared tree — it holds another round's
  in-flight edits to `src/init.luau`, `tools/check_types.py` and five more files.
- Every commit through `tools/commit_isolated.py`. Zero dropped hunks, zero foreign
  files, and the CAS caught a concurrent commit landing underneath (`9de8bfd`).
- `src/` **untouched**. No extraction-locked file edited.
- `stylua --check` clean. `check_input_authority` (real tree) **clean, 0 new binders**;
  `check_no_screen_key_bindings`, `check_source_size`, `check_library_purity`,
  `check_comment_codes`, `check_doc_style` all pass.

---

## Commits

| sha | what |
|---|---|
| `68f813e` | the chips were inside the bezel, said nothing, and one shoulder press fired twice |
| `67256d2` | the two new node ids were the only lowercase ones on the surface |

Files: `examples/gallery/client/{showcase_chrome,demo_picker,init.client}.luau`,
`tests/{gallery_chrome,transient_over_live}.spec.luau`, `docs/reference/api.md`.

---

## The brief's premise, corrected

> "ButtonR1: does NOTHING live … Diagnose the real arbitration headlessly … find why R1
> loses while L1 wins."

**R1 was never losing, and the headless arbitration is symmetric.** I built the candidate
cut and dumped it per key on the real `deviceKey` path, with a real focused adjust target:

```
[closed, slider focused]
  candidates for ButtonL1:
    prio 3500 sink=false ctx=ShowcaseChromeToggle action=Activatedemos(Bool)
    prio 1500 sink=true  ctx=Nav-Demo             action=Adjust(Direction1D) dir=-1
  candidates for ButtonR1:
    prio 3500 sink=false ctx=ShowcaseChromeToggle action=Activatesettings(Bool)
    prio 1500 sink=true  ctx=Nav-Demo             action=Adjust(Direction1D) dir=+1
```

Perfectly symmetric, chrome first on both, and both shoulders performed all three
transitions headlessly at `3ad40b0`. That is a **null result on the stated hypothesis**,
and I report it as one rather than manufacturing a fix for it.

The DIR3 review seat's MAJOR-1 (which arrived mid-round) names the real defect and it is
the one I could reproduce: **both contexts fire on one press.** The chrome's context was
non-sinking, so `deviceKey` never cut the demo's Adjust below it — measured on a surface
declaring `onAdjust`, one `ButtonR1` moved the value under the ring AND opened the panel.
That is fixed (item 3). **The live "R1 does nothing" observation is still unexplained by
anything headless and is owed a device re-check** — see Concerns.

---

## Per-item outcomes

### 1. The chrome respects overscan on a ten-foot surface — **DONE**

**Root cause, measured.** `rootPolicy = "edgeToEdge"` is honoured by
`solver.solve`, which sets `contentRect = the whole viewport` and **reads no insets at
all** (`src/layout/solver.luau:3800`). `renderer.luau:1911-1922` computes the ten-foot
margin into `insets` and hands it to the solver as `safeInsets` — so for an edge-to-edge
surface the margin is computed and then discarded. Every content surface got it; the one
surface that draws nearest the glass never did. Headless repro at 1920x1080 / Large:

```
before:  demo /Demo at (90,149)   chips at (12,12)   overscan 90/60
after:   demo /Demo at (90,149)   chips at (102,72)
```

**Fix** (`showcase_chrome.luau`): the `Bar` VStack takes `offsetX = overscanLeft`,
`offsetY = barTop` (= `coreTop + overscanTop`), from two SCALAR memos — a memo returning
the insets table hands a fresh identity to every reader and re-arranges a strip nothing
moved. The gate is `distanceProfile == "ten-foot"`, the **same** condition the renderer
uses, so a near display is arithmetic with zero in it. The predicate is one pure function,
`showcase_chrome.overscanEdge(distanceProfile, insets, edge)`, shared by the memo (`use`)
and the host heartbeat (`:get`).

**And the demo body does not move down to pay for it.** `barReservation` publishes
`coreSafeInsets.top`, and the renderer ADDS the overscan to the core insets for content —
so with the chips inside the margin, reserving the raw bottom edge spends it twice and
opens a 60px dead band (measured: demo top 209 instead of 149). `barReservation` gained an
optional 4th argument `overscanTop` and subtracts it; zero on every near row, so the
five-view matrix is byte-identical.

**Guard** — `gallery_chrome (12)`, four cases: the console row is at/inside the inset on
both axes (chip row AND the chip a player presses); the demo body's gap under the chips is
unchanged and the demo is still inset by 90; **all three near rows** (390x844, 844x390,
1232x1067) start at exactly `screen + gutter`; and the pure predicate's four branches.

### 2. Shoulder discoverability — **DONE**

**No new API.** The icon set ships 13 marks and no gamepad glyph
(`src/themes/standard_icons.luau`), so per the brief it is a text glyph — declared as the
BINDING's own `displayName` (`"LB"` / `"RB"`, `showcase_chrome.SECTION_GLYPH`) and read
back through the framework's existing `Facet.inputHint`, so there is exactly one spelling
of "LB" in the tree and a platform-aware re-spelling changes one table.

**Placement.** A sibling `UI.Text` at the OUTSIDE edge of each chip — `[LB] Demos
Settings [RB]` — in BOTH `ViewThatFits` rungs. Siblings, not wrappers: every existing path
(`…/Full/DemoToggle`) is unchanged, the focus map is unchanged (a Text is not a focus
stop), and the ladder measures the marks so it still steps down when they do not fit.
`textSize = "caption"` + `role = "secondary"` is the framework's own aside pair; it wraps
rather than clips, so ~1.4x expansion stays readable.

**The gate is explicit and separate**, because `action.preferredBinding` answers the first
keyCode binding for *every* non-touch class — an ungated `inputHint` tells a keyboard
player to press LB. It reads `effectiveInput` (the RESOLVED class, so a pad nobody has
touched yet still reporting KeyboardAndMouse is handled), via `UI.When` and not an empty
string: an empty `UI.Text` is still a child and a child costs the HStack a gap.

**Guard** — `gallery_chrome (13)`: gamepad sees both marks and they equal the bindings'
own display names; they are still there with the panel OPEN; keyboard AND touch see
nothing **and the first chip still starts at the row's own edge** (the assertion that
proves the `When` and not a blank string); and the row still fits its screen at 320px.

### 3. Both shoulders work, always — **DONE** (= review MAJOR-1, ruling R19)

`showcase_chrome.luau`'s context now declares **`sink = true`**, and the false comment is
replaced by a new §5 that states the contention (`presenter.luau:2292-2293` for `onAdjust`
surfaces, `:2394-2395` dynamically for a focused `adjustTargets` member), the measurement,
ruling R19, and the one remaining tie (below). Sinking is per-KEY, so `Backquote`/`ButtonY`
consume nothing that was ever bound elsewhere — pinned by its own case.

**The harness is why the suite never saw it.** Case (11) presses the same two buttons
against a two-button stand-in that binds nothing. `showcase(o)` now takes `demoPresent`,
forwarded verbatim to the demo's `pres.present`, so a case can make the demo contend.

**Guard** — `gallery_chrome (14)`, four cases including the negative control the round
demands: `Period`/`Comma` first, proving the demo's Adjust IS live (`adjust fired 1
time(s), direction 1`), because "adjustHits 0" is otherwise equally explained by "the demo
never bound Adjust". Then both shoulders, all three transitions (idle→open,
other→switch, same→close, both directions), `adjustHits 0` throughout.

### MAJOR-2 (the raise doubles the layer climb) — **CONTESTED**, mitigated, documented

**The exact seam.** `presenter.luau:2635-2638` — `displayLayer += 100` inside `makeHandle`
— and `:3553` — the reset, which fires only when `#stack == 0`, a condition the showcase
never reaches because the backdrop is permanent. The operation that would remove the
workaround entirely is a `presenter.raise(handle)` in that same file. **`presenter.luau`
is extraction-locked** (`docs/handoff/SOURCE_CAP_LEDGER.md`: extraction OWED, the 195,000
trigger already fired), so it is reported, not edited.

**Why no app-side fix removes it.** I checked the alternatives and each fails on a
measurement, not an opinion: the review's own suggestion ("raise only when the panel is
below") never skips, because a demo swap re-presents the demo and it therefore climbs
above the panel *every time*; `presentModal` would put the panel in a band the demo cannot
cross but ties the modal context at 3500 with the chrome's own and changes the DIR3-vetted
passive+engage shape; the only zero-layer route is writing `handle.controller
.setDisplayOrder`, and `handle.controller` is not in `api.md`'s documented handle surface
(`.root`, `.controller` is listed but its methods are not) — an example that pokes an
internal teaches the wrong thing.

**What I did do.** The raise takes the demo handle (`watchRaise` now passes it) and
returns without spending a present when `panelHandle.displayOrder > demoHandle
.displayOrder` — using only `handle.displayOrder`, which IS documented ("cross-surface
z"). It bites on the failed-mount path, where `mounted` is nil, nothing climbed, and the
old code re-presented anyway. The halved horizon (~48 swaps to the toast band, vs ~96) is
written into the `raisePanel` hazard note with the numbers and into `api.md`. **My round
does not make the rate worse: it was already +200/swap at HEAD.**

### MAJOR-3 (the guard was green on its own defect) — **DONE, and proved at the parent**

`tests/transient_over_live.spec.luau` rebuilt. **It now FAILS at `130dcae`** with exactly
the reported numbers, which is the definition of it working:

```
export-parent (130dcae): ✗ expected panel 10400 over the live screen 11000: false …
                         1 failed, 6 passed
export-mine   (HEAD+mine): 7 passed
```

Four changes, one per finding:
1. **The inert case is live.** The size threshold is derived from the world's own
   `viewportRect` instead of a module constant, so the 390x40 expand-plate case can trip
   it. Proved: the `surface = "base"` mutation on `anchored.luau`'s `LAYER_ID` now reddens
   **all three** construct cases (it reddened two before).
2. **`base` is a SET, not one id** — the app in the photograph has two live base surfaces.
3. **All eight shipped packages' own scrim rules are read** through `buildPackage`, not the
   neutral model alone; a package shipping an opaque scrim reddens it (mutation M8).
4. **A fifth construct**: the picker panel that commissioned the rule, driven through the
   real `demo_picker` + `settings_panel` + `showcase_chrome`, with a demo root that
   declares its own opaque `surface = "base"` (the class the flat rectangle is made of),
   plus a negative control proving the predicate can actually see that fill.

### Review MINORs

| # | disposition |
|---|---|
| 1 — stale "nothing else binds either key" | **fixed**, replaced by §5 with the measurement |
| 2 — `pcall(listener)` swallows | **fixed**: routed through the module's existing `warn` seam, matching `onRaise`'s neighbour |
| 3 — `sectionActions` is dead | **fixed**: the table is gone; the actions are keyed by section (`sectionAction[kind]`) because the glyphs read them |
| 4 — `raisePanel` resets focus | **fixed**: the panel's own ring position is tracked and restored across the re-present. Two traps found doing it — reading `focused` inside the raise reads the NEW demo (the swap has already presented it), and a `focusOn` on the line after `present` is a no-op because the rows live behind `UI.When`s that materialize on the next SOLVE. Restored through the `onGeometry` seam, with a 4-frame budget because `initialFocus = "first"` lands after the first callback |
| 5 — the rule is documentation-free | **fixed**: `docs/reference/api.md` gains "The standing rule: a transient opens OVER the live screen", including both mechanics (present-order z, and what a re-present costs) |
| 6 — guard skips exactly one root | **fixed** with MAJOR-3 |
| 7 — `presenter.luau:3531-3553` carries the same 12-line comment block **twice** | **NOT FIXED — locked file.** Confirmed present at HEAD (`:3531` and `:3542`, verbatim). ~740 free characters for whoever performs the owed extraction |
| MINOR-4 (named) — the causal story is unproven | **NOT FIXED — needs a device photograph.** No Studio access this round. The two candidates the review left standing (`PreferredTransparency = 0` scrim; the failed-mount blank screen at `demo_picker.luau:621-628`) are still open |

---

## Mutation ledger — 8 mutations, each reddens its own case and nothing else

| # | mutation | reddens |
|---|---|---|
| M1 | `sink = true` → `false` | (14) ×2 |
| M2 | `offsetX/offsetY` → `offsetY = opts.coreTop` | (12) console row |
| M3 | drop the `shoulderHint` children | (13) ×2 |
| M4 | `barReservation` ignores `overscanTop` | (12) demo body |
| M5 | drop the focus restore | (15) ring |
| M6 | drop the already-above guard | (15) layer |
| M7 | `anchored.luau` LAYER paints `surface = "base"` | `transient_over_live` ×3 (was ×2 — this is finding 1, proved) |
| M8 | `pixel_quest` ships `scrimOpacity = 0` | `transient_over_live` package case |

---

## RascalRally lockstep

**Nothing owed, with evidence.** `src/` is untouched (`git show --stat` on both commits:
`examples/gallery/client/`, `tests/`, `docs/` only). Every symbol this round added or
changed lives in the showcase example, which Rascal Rally does not consume; grep across
the whole `games/RascalRally` tree for `showcase_chrome`, `demo_picker`, `barReservation`,
`transient_over_live` and `inputHint` returns **zero files**. `check_input_authority`
(run in the real tree, where the consumer path resolves) reports **0 new binders** with
the consumer scanned.

---

## Concerns

1. **The live "ButtonR1 does nothing" is still unexplained.** Headless arbitration is
   symmetric and both shoulders worked at `3ad40b0` (probe above). The `sink = true` fix
   addresses the *double-fire* the review measured, not a *loss*. Candidates I could not
   rule out without Studio: injection asymmetry in the console emulation (the brief
   already records that `ButtonB` cannot be injected at all), or an engine-side contention
   this repo has not measured. **Owed on the device pass: press L1 and R1 from idle, from
   panel-open-same and from panel-open-other, and read the console.** If R1 is still dead
   live while L1 works, the cause is below the action system and this round did not find it.
2. **CONTESTED — the modal/chrome priority tie.** `topModalPriority() + 500` = 3500 for
   the FIRST modal, the same number as `TOGGLE_PRIORITY`, and the engine's own rule is
   "contexts with the same priority will receive the input"
   (`artifacts/release-candidate-review/input/ias-inventory.md` §A.2). A **modal** demo
   with a focused adjust target still double-fires. Recorded in §5 rather than fixed:
   moving that number is a framework-wide re-banding, not an example's call.
3. **CONTESTED — MAJOR-2's counter**, seam named above. The horizon is halved while a
   panel is open; the hazard note and `api.md` both carry the numbers.
4. **The `UI.ViewThatFits` icon rung keeps the marks but drops the labels**, by
   construction. On a screen narrow enough to force the icon rung, a pad player sees
   `[LB] ☰ ⋯ [RB]` — the marks survive, the words do not. Deliberate, and the 320px case
   pins that the row still fits.
5. **Restoring focus costs up to 4 extra `focusOn` calls per raise** (the budget). It is
   self-limiting and stops the moment the ring is where it belongs, but it is a retry loop
   in an example and a reviewer should look at it.
6. Two repo checks are **environmentally** unrunnable inside a `git archive` export —
   `check_comment_codes` (needs `git ls-files`) and `check_input_authority` (walks a
   relative path to the consumer). Both were run in the real tree instead and both pass.

---

# Fix round 1 — corrections and additions (2026-08-21)

Everything above is left exactly as it was written, including the two sentences the
DIR4 review proved false. This section is the correction; nothing above was edited.

**Suite 6892** (baseline 6883 at the fix round's HEAD; +9 = the nine new cases).
Commits: see the fix-round table at the end of this section.

## CORRECTION 1 — "MAJOR-2 … It bites on the failed-mount path" was FALSE

The report's MAJOR-2 section says the shipped guard bit on the failed mount. It did
not, and the review is right about why: the guard led with
`type(demoHandle) == "table"`, and `demo_picker`'s `raise()` passes
`mounted.handle`, which is **nil** on exactly that path — so the one case the guard
was claimed to save was the one case it could not fire on. The other branch
(`panelHandle.displayOrder > demoHandle.displayOrder`) is unreachable in this
example, because a successful swap has just presented the demo. The mitigation was
inert, and the shipped hazard note said the same false thing.

**Fixed.** The guard is now `if demoHandle == nil then return end` — nothing was
presented, a dismissal does not move `displayLayer`, so nothing climbed and the
re-present is provably waste. The unreachable comparison is deleted rather than kept
with an excuse. The hazard note in `showcase_chrome.luau` is rewritten to claim only
what happens.

**And the fixture was worse than the code.** Case (15) drove
`chrome.raise({ displayOrder = … })`, a table no call site can produce — a check
that proves nothing, certifying dead code. It is replaced by a **driven** failed
mount (`showcase{ failMount = flag }` makes `mountDemo` throw, exactly as a missing
scenario module does live), plus its control: a successful swap still spends a slot.
`self.raise` was only ever exported for that fixture and is gone with it.

## CORRECTION 2 — §5's rebuilt audit re-asserted the same false claim, one key over

The report presented §5 as the corrected audit. It said "for `Backquote`/`ButtonY`
that is still true" — and `src/controls/menu.luau:70-76` declares
`TRIGGER_KEYS.gamepad = ButtonY`, bound at `:884-899` on a **sinking** context at
priority 1200 for every `Menu` control with an action system. The catalogue ships
the `menu` demo. So the chrome at 3500 was deleting the pad route that demo exists
to demonstrate — the identical failure the round diagnosed for the bumpers, written
into the paragraph that corrected it, because the harness's stand-in demo binds
nothing and I did not go and look.

**RULING R20 (controller, 2026-08-21): the chrome toggle drops `ButtonY` entirely.**
The bumpers are already the pad's two doors (R19), so a pad toggle is redundant; the
platform convention gives the right face button to menus and context actions; the
framework's own menu verb claims it. Keyboard keeps `Backquote`.
`showcase_chrome.TOGGLE_GAMEPAD` is **deleted**, not nil'd — a consumer printing the
chrome's key map from it would otherwise print a route that no longer exists. It
shipped un-released inside `0.10.0`, so the removal rides R15 and is recorded as
**ADR-0040 row B-14**.

§5 is now an audit as a **table of what was actually read**, per key, with the
measurement beside each. The plan doc that first chose `ButtonY`
(`docs/plans/parity-round3.md`) carries a SUPERSEDED note on its gamepad row rather
than being rewritten.

## CORRECTION 3 — R19's stated price was wrong (review MINOR-3), and the director should see it

§5 and the DIR4 commit message both said the framework's Adjust "keeps DPad / Comma
/ Period". That holds only for a control that declares `adjustAxis` (Slider,
LevelPicker), whose D-pad pair moves to `AdjustAxis`. For a **legacy**-state adjust
target on a screen with horizontal navigation, `presenter.luau:2398-2402` returns
after binding **Comma, Period, ButtonL1, ButtonR1 and nothing else** — and the first
two are keyboard keys. So on a pad, once this chrome takes the bumpers, a TabView
strip and a Table column grip keep **no Adjust route at all**. That is the
`tab-view` and `table-virtualized` demos, and `tests/tab_view.spec.luau` asserts the
shoulders as the pad's paging affordance.

R19 authorises the trade and this round does not reopen it — but the price is higher
than the sentence the ruling was taken against, it is stated accurately in §5 now,
and **the director should see it**. It is a showcase-only cost: a game embedding
Facet chooses its own chrome keys.

## The five MINORs

| review # | what | disposition |
|---|---|---|
| MINOR-5 | the ten-foot fix insets two edges of four | **fixed** — and re-shaped: the overscan moved off the Bar's two `offset*` props onto the `Dock` anchor's `padding`, which insets every edge at once, composes with the screen's own `gutter`, and makes `width = fill` fill the VISIBLE width so the `ViewThatFits` ladder's offer is honest. New case (17); mutation drops `right` and it reddens. **The `bottom` edge is a recorded null** — the bar is top-anchored and hugs, so mutating it to 0 reddens nothing; declared anyway so the answer cannot be half-applied a second time, and the spec says exactly that |
| MINOR-1 | dead `BAR_ID` | **fixed** — deleted. It is the `sectionActions` defect re-created in the same commit that removed it; the bar's id appears once in the file |
| MINOR-4 | the `warn` fix is unpinned | **fixed** — the harness gained a capturing `warnSink` (it passed a swallowing `warn`, which is why it was unpinned), and case (18) drives one throwing listener: exactly one report line, the chrome survives, `core:lastError()` nil. Mutation re-swallows and it reddens |
| MINOR-7 | loose `isPanelPath` prefix | **fixed** — matches the root exactly or requires the `/`. **Knowingly unpinned**: there is no second `/ShowcasePanel*` surface in the place, and fabricating one to pin it would be the same class of fixture this round just deleted |
| MINOR-3 | R19's price | **fixed** in §5 — see CORRECTION 3 |
| MINOR-2 | the `api.md` heading splits `present`'s docs | **fixed** — the standing-rule section moved below the closed-option-key block, where it no longer reads as owning it |
| MINOR-6 | CONTESTED-2 filed as though no app-side option exists | **fixed** — §5 now records the `TOGGLE_PRIORITY = 3501` option, and why it was declined: it breaks the FIRST modal's tie in the chrome's favour and leaves the second (4000) winning, so the rule becomes "the chrome wins one modal depth and loses the next", which is worse to explain than the tie. The honest fix is a band with room in it |

Nothing was skipped.

## Fix-round mutations (all bite)

| # | mutation | reddens |
|---|---|---|
| N1 | the raise guard neutered | (15) failed mount |
| N2 | the chrome re-binds `ButtonY` | (7) contended keys, (16) ×2 — including the REAL `menu` fixture |
| N3 | overscan padding drops `bottom` | **nothing** — the recorded null, disclosed in the spec |
| N3b | overscan padding drops `right` | (17) ×2 |
| N4 | the raise listener re-swallows its error | (18) |
| N5 | `demo_picker` stops passing the handle | (15) failed mount — the contract, not just the guard |

## What is still owed after this round

Unchanged from Concerns 1-4 above, plus: the modal/chrome tie (CONTESTED-2) is live
and now has its declined option on the record; and the pad's `ButtonY` route through
`newMenu` should be exercised on the device pass alongside the two shoulders.
