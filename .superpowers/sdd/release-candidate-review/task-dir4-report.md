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
