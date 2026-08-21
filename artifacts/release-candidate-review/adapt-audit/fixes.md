# Wave ADAPT-FIX — what was fixed, what is contested, what is deferred

**Anchor:** framework `d783648` (suite 6546), RascalRally `ddc4de4` (suite 3418).
**End state:** Facet **6579**, RascalRally **3419**, both green, both measured in
private exports (`git archive` for the base, an rsync of the working tree for the
in-flight arms; the RR export is the multi-repo shape, `GameStudio/ui/Facet` beside
`games/RascalRally/code`, because that is how RR's specs require the framework).
Nothing was measured in-tree.

**Scope, as briefed.** `src/controls/table.luau` and `src/layout/solver.luau` are
off-limits (extraction-first debts) and neither was touched. ADAPT-17 (scroll
snapping), ADAPT-18 (table column priority-collapse) and ADAPT-8 (the ten-foot metric
ladder) are the director's, and are untouched. Every cell that needed one of those
four is CONTESTED or DEFERRED below with the exact line it needed.

---

## 1. The cell-by-cell disposition

**Counting rule:** one row per non-RIGHT cell of the audit's Part 2 tables — the same
unit the audit counted (114 cells, 58 RIGHT, so **56 non-RIGHT**). Every non-RIGHT cell
appears; nothing is silently skipped. **Two rows below are work items rather than
cells** and are not counted as such (re-review, 2026-08-19): the ADAPT-9 hybrid row
comes from Family G's *probe* table rather than its verdict table, and ADAPT-6 is a
FINDING under Family F, whose five cells are counted on their own row. `RESOLVED` means the wave fixed it, `CONTESTED` means it is a real
gap this wave may not close (with the reason), `DEFERRED` means it belongs to a
director item, and `BY RULING` means the audit itself records a documented decision
and the honest disposition is to leave it and cite the ruling.

### Family A · Navigation, and the centered placements

| cell | verdict | disposition | evidence |
|---|---|---|---|
| regular touch → `bottomBar` | WRONG (ADAPT-2) | **FIXED** | short-side test replaces the DisplaySize test; `adaptive.spec` pure + reactive + a both-orientations case; four rows re-pinned (§2) |
| `bottomBarCompact` left-aligned | WRONG (ADAPT-4) | **FIXED** | `tab_view.spec` "the landscape phone's inline band is centered too" — a measured gap, red at the anchor |
| `topBar` left-aligned (tablet) | WRONG (ADAPT-4) | **FIXED** | same fix, same ZStack; the tablet row now reaches `topBar` at all (ADAPT-2) |
| `topBar` left-aligned (ten-foot) | WRONG (ADAPT-4) | **FIXED** | `tab_view.spec` "the ten-foot top bar is centered in its band, not parked in the corner" |

### Family N · Ten-foot specifics

| cell | verdict | disposition | evidence |
|---|---|---|---|
| `contentWidth` is the RAW viewport (ADAPT-5) | WRONG | **CONTESTED** | The fix is a NEW public fact (`safeContentWidth` beside `viewportWidth` on `adaptive.conditions`), and a previous round already DECLINED it in writing ("belongs in `ViewThatFits`, which measures"). Re-deciding a recorded decline is a director call, not an implementer's. The audit's own framing — "the decline left a hole rather than a route" — is the argument to put to them. |

### Family C · Pickers and value controls

| cell | verdict | disposition | evidence |
|---|---|---|---|
| C-1 width axis never consulted | AUTHORED-ONLY | **FIXED** (ADAPT-1) | `adaptive_defaults.spec` "Picker: a compact surface collapses four long labels to the row list, unwired" |
| C-3 no input-class rung on `newPicker` | MISSING | **CONTESTED** | Genuinely new capability: "a ten-foot pad and a desktop mouse should not get identical option rows" is a design rule nothing in the framework has stated. No documented promise to complete. |
| C-4 `menu`/`stepper` presentations refused on `newPicker` | MISSING | **CONTESTED** | New capability, and the audit records the route that exists (`newPopupButton` owns the menu idiom). Widening `newPicker`'s closed presentation set is an API decision. |
| C-5 menu touch rung never fires | AUTHORED-ONLY | **FIXED** (ADAPT-1) | `adaptive_defaults.spec` "Menu: the same rung, through the same recipe, unwired"; and in a shipped app, `cartwheel_spec` "a touch phone resolves the SHEET; a desktop pointer never does" |
| C-8 Slider has no touch detents | MISSING (low) | **CONTESTED** | The audit itself says "possibly deliberate — no ruling found". Building it would invent a requirement. |
| C-9 level-picker density is env-gated and silent | AUTHORED-ONLY | **FIXED** (ADAPT-1) | `adaptive_defaults.spec` "LevelPicker: the touch run is wider than the pointer run, with no `env` key" — measured on the solved gap, not on a metric name |

### Family D · Text entry

| cell | verdict | disposition | evidence |
|---|---|---|---|
| D-1 `clearButtonMode` is `"never"` everywhere | AUTHORED-ONLY | **BY PARITY** | The audit records that this matches the reference platform's own `.never` default. api.md states the default and the four modes honestly; there is no adaptivity claim to correct and no ruling to build against. |
| D-3 occlusion response needs `env` | AUTHORED-ONLY | **FIXED** (ADAPT-1) | `adaptive_defaults.spec` "TextInput: the field lifts itself off the keyboard with no `env` key" — and this control REFUSES without one |
| D-5 `submitLabel` carried and never applied | MISSING | **BY ENGINE** | `TextBox.ReturnKeyType` is `[Hidden, NotScriptable]`; documented exception, no action available |

### Family E · Transient-surface dismissal

| cell | verdict | disposition | evidence |
|---|---|---|---|
| `Escape` unbound on desktop | MISSING but justified | **BY RULING** | Engine-reserved (CoreGui menu); the ruling is inline at `presenter.luau` and `target_contract.luau`, and the REVEAL round re-stated it in four shipped locations |
| sidebar has no collapse (ADAPT-29) | MISSING | **CONTESTED** | New capability on a closed spec (`collapsed`/`collapsible`/`sidebarCollapsed` are all refused today). A collapsible rail is a product decision with its own focus, persistence and animation surface. |
| `bottomBarCompact` is byte-identical to `bottomBar` (ADAPT-30) | MISSING (low) | **FIXED — the doc half** | The audit offers an either/or ("ship the compact metric + `compactLabel` pass, **or** correct the doc"). The band is 46px with the same words; api.md and `adaptive.luau` now say so, and name the two routes to a terser thumb-zone name that DO exist. Shipping a tighter metric is a product change and is not smuggled in here. |

### Family K · Editable collections

| cell | verdict | disposition | evidence |
|---|---|---|---|
| K-2 a `rowActions`-only Table has zero focus stops (ADAPT-13) | MISSING (high) | **CONTESTED — `table.luau`** | The fix is one clause on `table.luau:1926` (`focusable = selectionMode ~= "none" or spec.reorderable == true`). I checked the brief's hypothesis that it might live in shared row machinery: it does not. `src/row_capability.luau` only NARROWS a declared capability, `row_actions*.luau` never decides focusability, and the VirtualList fix the audit cites (`virtual_list.luau:1780-1792`) is a LIST-level key context of its own, not a shared helper. api.md:4445 stays wrong until that clause lands. |

### Family L · Selection

| cell | verdict | disposition | evidence |
|---|---|---|---|
| L-5 edit mode paints no selection affordance (ADAPT-27) | WRONG | **CONTESTED — `table.luau`** | The row's children are built in `table.luau`; there is nowhere else to mount a leading circle |
| L-6 an arrow press destroys a multi-selection (ADAPT-14) | MISSING (high) | **CONTESTED — `table.luau`** | Exactly `table.luau:3680`, `api.select(rowKey, { mode = "replace" })` inside `handleFocusMoved`. The modifier table it needs is already published by the presenter. |
| L-7 a pad can never hold two rows (ADAPT-15) | MISSING (high) | **CONTESTED — `table.luau`** | The activate handler in `table.luau` is where the `else` branch replaces; the audit's cheaper option (edit-mode Activate means `toggle`) is one clause in the same file |
| L-8 `newVirtualList` refuses multi-selection | MISSING but declared | **CONTESTED** | A loud, named construction refusal and a declared hole in the parity doc — closing it is new capability with its own range/anchor semantics |

### Family M · Drag

| cell | verdict | disposition | evidence |
|---|---|---|---|
| M-4 keyboard-only Table reorder degrades | AUTHORED-ONLY | **CONTESTED — `table.luau`** | The auto Edit-toggle union (`touch ∨ gamepad`) is `table.luau:815`; a keyboard-only session's route is decided there |
| M-5 `newVirtualList` has NO touch reorder route (ADAPT-21) | MISSING (high) | **CONTESTED, and the false claim is corrected** | The in-file comment asserting "touch reaches reorder through the grab verbs — Table's precedent" was false and now says so, states the author's route today, and states why the framework-side answer is a director call: `armOnTap` is opt-in *because* "what a tap MEANS is the consumer's call", so defaulting it on changes what a tap does on every reorderable list already shipped |
| M-7 `grabOnActivate` flips off when the list declares `onActivate` | AUTHORED-ONLY | **BY RULING** | Documented in api.md:4742 with the named route (`bind list.toggleGrab()`); the two verbs would otherwise shadow each other |
| M-9 the public drag verb has no non-pointer pickup (ADAPT-16) | AUTHORED-ONLY (high) | **FIXED** | `drag_public.spec` "ButtonA on a focused card ARMS it, DPad aims it, ButtonA commits", "Return does the identical thing", "ButtonB puts it back down", and the safety half "a card with its own onActivate keeps it" |

### Family B · Card sets

| cell | verdict | disposition | evidence |
|---|---|---|---|
| B-1 `UI.Grid` defaults to ONE lane at every width (ADAPT-22) | WRONG (high) | **CONTESTED** | `grid.luau:173-181` returns 1 deliberately when neither `columns` nor `minColumnWidth` is declared. Changing that default re-lays out every `UI.Grid` in the framework, the examples and the shipped game — a product decision, and the audit's own reference calibration says the reference platform does not auto-adapt card sets either. The director's call; the recommendation is a default `minColumnWidth` rather than a lane count. |
| B-2 `minColumnWidth` adapts, but is authored | AUTHORED-ONLY | **BY PARITY** | The reference platform's `GridItem(.adaptive(minimum:))` is authored too; and this route is now density-capped at ten-foot (B-3) |
| B-3 `columnsFor` uncapped at ten-foot (ADAPT-23) | WRONG (high) | **FIXED** | `adaptive.spec` "ADAPT-23: the ten-foot cap reaches the column count too" **and** `grid_column_flow.spec` "a ten-foot grid gets FEWER lanes than the same grid at near distance", which also asserts predictor and solver return the SAME number |
| B-4 `VirtualGrid` requires `columns` | AUTHORED-ONLY | **BY RULING** | A documented refusal WITH a route (`minColumnWidth` is refused by name, pointing at `columnsFor`) |
| B-6 `ScrollView{axis="x"}` navigates vertically (ADAPT-24) | WRONG (high) | **FIXED** | `navigation_groups.spec` "a horizontal ScrollView is a HORIZONTAL run, and a vertical one is not", plus the container null-hypothesis case |
| B-7 no scroll snapping anywhere (ADAPT-17) | MISSING (highest) | **FIXED — wave CAROUSEL** | See the CAROUSEL addendum below |
| B-8 `containerRelativeFrame` page sizing | AUTHORED-ONLY | **SUPERSEDED — wave CAROUSEL** | Still correct and still authored, but a carousel no longer needs it: `itemExtent = "cards"` sizes the page from the arrangement, and the rail is the surface that carries it |
| B-9 no page-dot indicators | MISSING | **DEFERRED — director** | No longer blocked by B-7. The peek IS the shipped affordance (the audit's own words for it), and a dot strip is a second one with its own reach story on four inputs; carried to the director rather than assumed |
| B-12 Tab does not traverse a rail | AUTHORED-ONLY, deliberate | **BY RULING** | Director playtest ruling 2026-08-03 ("the keys it claims are the ones an avatar is already using") |

### Family J · Tables

| cell | verdict | disposition | evidence |
|---|---|---|---|
| J-1 no column collapse by priority (ADAPT-18) | MISSING (highest) | **DEFERRED — director** | Out of scope by the brief |
| J-2 a `fill` column's `minWidth` is dropped (ADAPT-19) | WRONG (highest) | **CONTESTED — `table.luau`** | `resolveDim` at `table.luau:1203-1216`: the `fill` branch is `return dim`, untouched. One branch, in the closed file. |
| J-3 a wide table clips at compact with a y-only scroller | WRONG | **CONTESTED — `table.luau`** | The header/body scroll region and the column resolution are both in `table.luau`; falls out of J-1 |
| J-4 truncation recovery is dead on keyboard/pad (ADAPT-20) | WRONG (highest) | **CONTESTED** | The disclosure walk starts at the FOCUSED node and the truncated text is a SIBLING (`Row/Hit` vs `Row/Cells/…`). A general "walk the parent's subtree" would raise plates for unrelated siblings on every control; the honest fix needs the Table's own knowledge of what a row is, which is `table.luau`. |
| J-6 no list-detail arrangement primitive (ADAPT-26) | MISSING | **CONTESTED** | `NavigationSplitView` is recorded Missing in the parity doc; a new construct with its own selection, back-stack and focus semantics |
| J-9 focus lands on a clipped column | WRONG | **DEFERRED** | The audit's own disposition: "falls out of J-1/J-3, no separate fix wanted" |

### Family G · Transient surfaces

| cell | verdict | disposition | evidence |
|---|---|---|---|
| menu on compact touch is a floating plate | AUTHORED-ONLY (critical) | **FIXED** (ADAPT-1) | 125×110 plate with 36px rows → a 390-wide sheet with 56px rows, from facts nobody passed |
| the hybrid resolves a sheet under a mouse (ADAPT-9) | WRONG (latent) | **FIXED** | `menu_recipe.touchPrimary` asks which class is PRIMARY, once, for both controls; `menu.spec` "ADAPT-9: a hybrid follows its PRIMARY class, not merely what it has" |
| no general modal→sheet form (ADAPT-25) | MISSING (high) | **CONTESTED** | There is no `UI.Sheet`/`newSheet` and `presentModal` has no size-driven form — a new presentation primitive, not a connection |
| tooltip does not appear on touch | MISSING BY RULING | **BY RULING** | `help_plate.luau:11-32`, with `text_audit.helpRoutes` as the mechanical guard that a `help` string is never the ONLY route |

### Family H · Hover-dependent affordances

| cell | verdict | disposition | evidence |
|---|---|---|---|
| `help` tooltip has no touch route (#9) | MISSING BY RULING | **BY RULING** | Same ruling as above; the other twelve cells are RIGHT |

### Family I · Density, spacing and hit targets

| cell | verdict | disposition | evidence |
|---|---|---|---|
| ADAPT-7 the type floor misses unauthored text | WRONG (critical) | **FIXED** | Both seams in one commit; four new cases in the ten-foot spec family, three red at the anchor (§3) |
| ADAPT-8 the ten-foot ladder is only type/overscan/focus | MISSING (director call) | **DEFERRED — director** | Out of scope by the brief |
| ADAPT-10 no gamepad rung in the density ladder | MISSING (high) | **CONTESTED — `table.luau`** | `snapshot.luau:686-692` publishes two keys and I may add a third, but the SELECTION is `table.luau:470` (`if classes.touch then "touch" else "pointer"`). Publishing a rung nothing selects would be ceremony. **This one bit during the wave:** ADAPT-7's fix made Cartwheel's ten-foot table row overflow by 5px — a 41px button inside the densest row the framework ships — and the example had to absorb it (§4). |
| ADAPT-11 table density is caller-wired; 36px on a touch phone | AUTHORED-ONLY (high) | **CONTESTED — `table.luau`** | `table.luau:499-503` returns `rowBoxFor(nil, …)` when `spec.env` is absent. The channel this wave built (`surface_env.find(core)`) is exactly what would close it — three lines, in the closed file. |
| ADAPT-12 the 44px floor is unexamined off touch | MISSING (low) | **DEFERRED** | The audit's own disposition: "fix it with ADAPT-8" |
| the env default `themeMetrics` resolves with `facts = {}` | hazard (under ADAPT-8) | **CONTESTED, and it now matters more** | `environment.luau:136` defaults to `themeSnapshot.neutral()`, whose `density` is `"near"` even on a Large display, until a caller re-resolves with the live fact (`theme_controller` does, on a real client). ADAPT-23's solver-side cap reads that fact, so a headless surface with no theme controller keeps the near-distance lane count. Making `themeMetrics` DERIVED is a change to a fact the controller commits atomically with the native derive swap — architectural, and worth a decision rather than a patch. |

### Family F · Disclosure / reveal

| cell | verdict | disposition |
|---|---|---|
| all five combos AUTHORED-ONLY at the anchor | AUTHORED-ONLY | **RESOLVED BEFORE THIS WAVE** — the REVEAL round landed the expand knob, the affordance, the plate and its dismissals; per the brief the landed behaviour is the contract |
| ADAPT-6 `reveal` about to mean two things | medium | **RESOLVED BEFORE THIS WAVE** — the region knob was renamed `expand` mid-REVEAL, before anything consumed it |

### The counts

| disposition | cells |
|---|---|
| **FIXED** | **14 cells** (+1 work item: the ADAPT-9 hybrid row) |
| RESOLVED before this wave | **5 cells** (Family F) (+1 work item: ADAPT-6) |
| **CONTESTED** (with the exact blocker) | **21** |
| **DEFERRED** (director items and their consequences) | 6 |
| BY RULING / BY PARITY / BY ENGINE (documented decisions, no action) | 10 |
| **total** | **56 cells**, which is 114 − 58 RIGHT |

Of the 21 contested, **ten are `table.luau`** — ADAPT-13, 14, 15, 27, 11, 10, M-4,
J-3, J-4, and J-2 (whose finding id is ADAPT-19: they are the SAME cell, counted once,
corrected 2026-08-19 after the re-review found it listed twice). The single
highest-value unblock available to this project is that file's extraction.

---

## 2. ADAPT-2 — the re-pin evidence trail

Every row below asserted the OLD answer and every one of them was the DEFECT rather
than the rule: the engine calls a tablet `DisplaySize.Small` ("Most
tablet/mobile/handheld devices"), so the documented tablet placement was reachable
only by a touchscreen laptop. Each re-pin carries the finding id in the file, beside
the assertion, so the change is traceable from the test rather than from this
artifact alone.

| row | was | now | where the citation lives |
|---|---|---|---|
| pure policy: `wide`/`tall`/touch, no display fact | `bottomBar` | `topBar` | `tests/adaptive.spec.luau`, in the block comment above both re-pinned lines |
| pure policy: `regular`/`medium`/touch/`Small` | `bottomBar` | `topBar` | same |
| reactive: 1080×810 touch surface with `displaySize = "Small"` | `bottomBar` | `topBar` | `tests/adaptive.spec.luau`, inline comment naming the live tablet row |
| `p1_glade`: 1280×720 touch, `Small` | bottom band | top bar | `tests/reference/glade_spec.luau`, inline |
| `p4_foyer`: 1280×720 touch, `Small` | bottom band | top band | `tests/reference/foyer_spec.luau`, inline |
| `tests/lib/device_views.luau` `tablet-landscape` (1079×809, `Small`) | resolved the phone bottom bar in every sweep that visits it | resolves the tablet paradigm | a block comment ON THE ROW, which also records that prior tablet-row evidence in this repository's gate artifacts measured a phone-class placement |

**The honest history, stated once here as well:** every five-view gate artifact
produced before 2026-08-18 has a "tablet" row whose navigation placement was the
phone's. The viewport and the display fact in those artifacts are correct; the
placement they recorded is not the placement the same row produces now. They are not
rewritten.

**What did NOT change:** the gamepad branch. A near-distance handheld keeps the
display-fact rule and the director ruling behind it ("Small and joystick can vary —
bottom tabs are ok there"). Nothing in the audit measured a pad-in-the-hands tablet,
so nothing here invents one.

---

## 3. The instrument fixes (the audit's own "the suite cannot see it")

| instrument | what it could not see | what it sees now |
|---|---|---|
| `tests/paradigm_tenfoot.spec.luau` UI-PARADIGM-003 | both cases declared `textSize = 16`, so the spec tested the one branch that worked. An unauthored `UI.Text{ text }` painting 16px on a television was invisible to the whole suite | a new describe with four cases that declare NO size — Text, Button label, Toggle label, and the measure/paint agreement on the flip. Three are red at the anchor (16 vs 24, 18 vs 27, and the box that did not grow) |
| `tests/adaptive.spec.luau` navPlacement | the tablet rows asserted the defect, so the policy was "green" while no tablet could reach the tablet paradigm | a both-orientations case that also demonstrates why the intuitive fix (`sizeClass == "wide"`) fails a portrait tablet |
| `tests/tab_view.spec.luau` | nothing measured where the strip sat inside its band, so a 193px cluster in a 1740px band was green | three cases measuring the strip against the control's own box — and they measure a NODE FOUND BY ID, so the structural change cannot make them pass by making a path disappear |
| `tests/lib/large_text_fixtures.luau` | the `Picker` fixture declared `allowClipped` for LT-G4 | the entry is DELETED, because an automatic picker now reflows to the row list instead of ellipsizing. LT8-ALIVE (the check that every allowlist entry is a real truncation) is what reported it had stopped catching anything — an instrument catching an instrument |
| `tests/adaptive_defaults.spec.luau` (new) | nothing asserted that a control gets its facts without being handed them | 14 cases: the channel, its ambiguity rule, the six controls unwired, the four refusals, and a hosted surface adapting with zero authoring |
| `tests/reference/cartwheel_spec.luau` | no shipped app exercised an adaptive default | a phone resolves the SHEET and a desktop never does, through a screen that wires neither fact |

---

## 4. Standing guards, and the bite-check for each

Every guard below fails when its fix is removed — most were RED at the anchor, which
is the strongest form of that check; the two that could not be (a structural change
and a safety-half case) are marked.

| guard | bite-check |
|---|---|
| ADAPT-7's four unauthored-text cases | 3 of 4 red at the anchor; the fourth (a near display is byte-identical) is the null hypothesis and must stay green |
| ADAPT-2's pure + reactive + both-orientations cases | all red at the anchor |
| ADAPT-1's `adaptive_defaults.spec` | every "unwired" case red without the channel; every refusal case red if the refusal is softened to a default |
| ADAPT-9's hybrid case | red at the anchor (a mouse-driven touchscreen laptop resolved a sheet) |
| ADAPT-16's three arm/aim/commit cases | red at the anchor ("expected nil to be armed"); the fourth is the safety half (a card with its own `onActivate`) and is green before and after by design |
| ADAPT-4's three band cases | two red at the anchor on a MEASURED gap; the third asserts the new structure |
| ADAPT-23's pure and solver cases | both red at the anchor (11 vs 6), and the solver case additionally asserts predictor == solver |
| ADAPT-24's two group cases | the horizontal one red at the anchor; the container one is the null hypothesis |
| Cartwheel's unwired-popup cases | red at the anchor (the sheet rung had never fired) |
| RascalRally's `ADAPT-1` consumer case | red at the anchor from the other side of the boundary: `sizeClassFrom` did not exist and the refusal did not fire |

**The refusal is itself the standing guard for the census.** The audit's finding was
that zero of seventeen shipped picker call sites used the adaptive default, so the
nil-fact path was never exercised in situ. A control that cannot find its facts now
refuses to construct, which means the every-example mount sweeps (`examples_gallery`,
`example_readouts`, `overflow_sweep`) fail loudly rather than measuring the
large-screen answer. A mechanical re-run of the call-site census (the audit's
brace-matched scan) is NOT mechanised here and is a fair follow-up.

---

## 5. The consequence found rather than claimed

ADAPT-7's fix reddened one thing in the whole suite, and it is evidence for a
different finding: Cartwheel's brews table reported 5px of overflow on all 24 visible
rows at 1920×1080 — a 41px button inside a 36px row, because a television gets
`controls.table.rowHeight.pointer`, the densest row the framework ships (ADAPT-10,
whose fix is in `table.luau`). The example absorbs it by giving the row's verb the
row's own type scale and says so at the call site. When ADAPT-10 lands, that
authored `textSize` is the first thing to delete.

---

## 6. Director-item placeholders

| item | status | what it is waiting on |
|---|---|---|
| ADAPT-17 · scroll snapping / paging | **OPEN — director** | The audit's highest-severity MISSING: no `snap`/`paging`/`scrollTarget` symbol anywhere in `src/`, so the director's own carousel example cannot be built even by an author. B-9 (page dots) follows it. |
| ADAPT-18 · table column priority-collapse | **OPEN — director** | J-1, and J-3/J-9 fall out of it. Blocked twice over: the design call AND `table.luau`. |
| ADAPT-8 · the ten-foot metric ladder | **OPEN — director** | Four named rows (type, overscan, focus, density cap) shipped; whether that is enough at three metres is a human-factors judgement. ADAPT-12 rides with it, and ADAPT-10 is the one piece of it this wave met head-on (§5). |
| ADAPT-22 · `UI.Grid`'s one-lane default | **RECOMMENDED for the same queue** | Not on the director's list, but it is the same shape: a default that re-lays out every shipped grid. |
| ADAPT-21 · VirtualList touch reorder | **RECOMMENDED for the same queue** | The framework-side fix changes what a TAP means on every reorderable list; the drag contract has already ruled that this is the consumer's call. |

---

## 7. Not measurable headlessly — additions to the batched Studio pass

The audit's own sixteen rows stand. This wave adds five:

1. **The centred bands at ten-foot** (ADAPT-4). A zoomed capture of the top band at
   1920×1080: the headless proof is `leftGap == rightGap`, and whether a centred
   193px cluster reads better than a corner one at three metres is the director's eye.
2. **Unauthored type at ten-foot** (ADAPT-7). Every screen written the natural way is
   now 1.5× on a Large display. The acceptance row asks for ~29pt at 3m; a capture at
   equivalent angular size is what settles whether the fix lands where D.1 wanted it.
3. **The touch→sheet rung on a real device** (ADAPT-1). Cartwheel's sort menu now
   presents a bottom sheet under a thumb. Sheet placement, the 56px rows and the
   dismissal all have headless proofs; the feel does not.
4. **The pad pickup on a real controller** (ADAPT-16). ButtonA on a focused card arms
   it and the ring aims it — worth one physical-pad session, because gamepad ButtonA
   arbitration against CoreGui is the audit's own row 9.
5. **The tablet paradigm, on a tablet** (ADAPT-2). The whole point is that no tablet
   could reach it; the confirming instrument is a real tablet reporting
   `DisplaySize.Small` and getting the top bar.

---

# ADDENDUM — wave TABLE (2026-08-18/19): the thirteen cells `table.luau` was holding

**Anchor:** framework `30cec7f` (suite 6579), RascalRally `5ce9d09` (suite 3419).
**End state:** Facet **6633**, RascalRally **3425**, both green, both measured in
private exports (an rsync of the working tree; the RR export is the multi-repo shape,
`GameStudio/ui/Facet` beside `games/RascalRally/code`). Nothing was measured in-tree.

**Why these cells and not others.** §1 above closed with "of the 21 contested,
ELEVEN are `table.luau` — the single highest-value unblock available to this project
is that file's extraction." (The count §1 carries is now **ten**: ADAPT-19 and J-2 are
one cell, corrected 2026-08-19 after the re-review found it listed twice. The argument
is unchanged.) That extraction is the first half of this wave
(`table_rows.luau`, then `table_header.luau` and `table_disclosure.luau` as the
paradigm needed the room), and this addendum re-verdicts every cell it unblocked,
plus the two director items that fall out of the collapse paradigm.

## The re-verdicts

| cell | was | now | evidence |
|---|---|---|---|
| **J-1 / ADAPT-18** column collapse by priority | DEFERRED — director | **FIXED** | `Column.priority` (a number, `1` most important; `"always"` a refusal; absent = declaration order), the first column immune, the trigger a DECLARED floor. `table.spec` carries the arithmetic (order, both directions, the no-floor null hypothesis, the override-clamp-first interaction); `table_input.spec` carries the director's own device case — landscape → portrait collapses Rating with the disclosure present, NOT pushed off screen, and widening brings it back |
| **J-2 / ADAPT-19** a `fill` column's `minWidth` is dropped | CONTESTED — `table.luau` | **FIXED** | the floor is spent where the width is divided: a fill whose share falls under it is pinned and leaves the pool. Shipped consequence, measured: the playlist at 320x640 in edit mode went from 30px and 14px of readable text to 66px of each |
| **J-3** a wide table clips at compact with a y-only scroller | CONTESTED — `table.luau` | **FIXED, and it falls out of J-1 exactly as predicted** | a fixed column's floor IS its width, so the rule reaches an all-fixed table with no `minWidth` anywhere: `table.spec`'s J-3 case drops 720px of columns to what a 420px and then a 390px body can hold |
| **J-9** focus lands on a clipped column | DEFERRED (falls out of J-1/J-3) | **FIXED** | a collapsed column takes the framework's space-reserving hide, which leaves the focus ring with its whole subtree — `table_input.spec` asserts the headers group loses the stop, and that the column's resize target goes with it |
| **J-4 / ADAPT-20** truncation recovery dead on keyboard/pad | CONTESTED | **FIXED** | `contribution.discloseScope` — a control may widen the disclosure walk to its own row when the focus stop is a SIBLING of the disclosed label. It answers a SCOPE, not a target, so the presenter's hidden gate, truncation test and document order all still decide |
| **K-2 / ADAPT-13** a `rowActions`-only Table has zero focus stops | CONTESTED — `table.luau` | **FIXED** | the audit's own one clause, plus the api.md sentence it makes true, plus a null hypothesis (a table with none of the three verbs still takes no focus stop per row) |
| **L-5 / ADAPT-27** edit mode paints no selection affordance | CONTESTED — `table.luau` | **FIXED, with two named residues** | a leading mark in the gutter the cells were already inset into, reading the same memo the row's `selected` prop reads. RESIDUE 1: a table that is both selectable and reorderable still shows none — two marks do not fit one 32px gutter and moving the ≡ to the trailing edge is a layout change to every reorderable table. RESIDUE 2: the mark mounts only where edit mode is REACHABLE, because a `UI.When` materialises even while its branch is absent and an ungated mark is one engine node per ROW — **caught by RascalRally's own contract tests, not by ours** |
| **L-6 / ADAPT-14** an arrow press destroys a multi-selection | CONTESTED — `table.luau` | **FIXED** | Ctrl/Cmd moves the ring and selects nothing, Shift extends from the anchor, a plain arrow still replaces (the Finder's model, and never the defect). The modifier state comes from `system.modifiers()` through `bindActionSystem`, the same source the presenter fills an Activate's meta from |
| **L-7 / ADAPT-15** a pad can never hold two rows | CONTESTED — `table.luau` | **FIXED, narrowed** | the audit's own cheaper option: edit mode IS the selection mode, so a device Activate toggles and a focus move leaves the selection alone. NARROWED to tables with no `onPrimaryAction` — see below |
| **M-4** keyboard-only Table reorder degrades | CONTESTED — `table.luau` | **FIXED** | the auto Edit/Done union gains a third clause: a keyboard with NO MOUSE on a reorderable table. Narrow twice over (reorder only; mouse-less only), with both narrowings as null-hypothesis cases |
| **ADAPT-10** no gamepad rung in the density ladder | CONTESTED — `table.luau` | **FIXED, and the finding's title is corrected** | a third rung (`tenFoot`, one line, floored at the theme's LARGE control height) selected by DISTANCE rather than by the pad — a controller sixty centimetres from a monitor is a near session. Cartwheel's absorbing authored `textSize` is deleted in the same commit, which was §5's own test |
| **ADAPT-11** table density is caller-wired | CONTESTED — `table.luau` | **FIXED** | `surface_env.find(core)` — the ADAPT-1 channel — with a DEGRADE rather than a refusal, because unlike a picker's presentation a table has an honest default (the neutral package at authored size) |
| **the env default `themeMetrics` resolves with `facts = {}`** | CONTESTED, "and it now matters more" | **AVOIDED here, still open there** | this wave needed the same distance fact and read `env:get("distanceProfile")` instead of `metrics.density`, precisely because the latter answers "near" on any surface whose `themeMetrics` is still the default neutral package. ADAPT-23's solver-side cap still reads the snapshot fact and the hazard stands for it |

## What is carried to the director rather than taken

1. **ADAPT-15's remainder.** A `multi` table that ALSO declares `onPrimaryAction`
   keeps its shipped device behaviour: Return and ButtonA OPEN the row in edit mode
   rather than toggling it. That is not a doubt — it is RED-TEAM item 3 (2026-08-13),
   which restored the device Activate on exactly that shape after edit mode had eaten
   it, with two live cases pinning it. Flipping it is a second answer to "what does A
   mean in edit mode on a table with two verbs", which is a product decision. On that
   shape a pad still cannot build a multi-selection; a keyboard can, with Shift.
2. **ADAPT-27's remainder.** Where the ≡ handle goes on a table that is both
   selectable and reorderable. iOS puts the reorder grip trailing and the selection
   circle leading; this framework puts the grip leading, and moving it carries its own
   path grammar and its own press-zone arithmetic (`isHandleZonePress` reads the
   zone's leading edge).
3. **The batched Studio pass gains three rows**, on top of §7's five: the collapse
   and its disclosure on a real phone rotation (the headless proof is the hidden
   verdict and the chip's 44px band; whether a player reads "1 more" as "there is
   more of this row" is the director's eye); the ten-foot row rung at 1920x1080 with
   a pad, against the same Cartwheel table that measured the defect; and the
   edit-mode selection mark under a skinned package, where the gutter it sits in is
   carved rather than flat.

## What the sweep learned, and what it deliberately did not

`tests/overflow_sweep.spec.luau` gains **"a collapsed column with no route on the
screen"**, checked on every swept surface at every viewport, text preference and
theme package — the rider the paradigm ships with, and it bites (26 findings with
the chip removed).

The COMPLEMENT — "a cell that clipped instead of collapsing" — was attempted as a
truncation scan and is **not honest at that altitude**, which is worth recording
because it looks obvious: the fact that separates a defect from an ordinary long
string is the column's DECLARED FLOOR, and the sweep holds no control handle to read
one. Measured rather than assumed: the scan reported the mail list's sender column at
1920x1078 and the playlist's rating column at every viewport, neither of which is
narrow. That half reddens the sweep through the route it already had — proven in this
round, in this order: honouring the floors alone put 196 solver overflow findings on
the shipped playlist at compact, and the collapse rule is what answered them.

## The extraction, since it was the point

`src/controls/table.luau` 198,764 → 181,588 while GAINING a paradigm and six device
fixes. Three seams left it: the row/cell builder (`table_rows.luau`, the seam the
ledger had been holding the file for), the disclosure (`table_disclosure.luau`, taken
the moment writing the plate in place put the file back inside the warning band), and
the header band (`table_header.luau`, whose own trigger fired on the very next
feature). `tests/table_rows_seam.spec.luau` mechanises the property that makes the
first one safe — READ == DECLARED == PASSED as three set comparisons over the live
sources, the shared write surface pinned by name, the require asserted not to come
back — with three mutations confirmed to redden it.

---

# ADDENDUM — wave CAROUSEL (2026-08-20): the cell that failed the director's own example

**Anchor:** framework `e25ad06`, RascalRally `5f955ef`.
**End state:** Facet **6696**, RascalRally **3431**, both green, both measured in
private exports (an rsync of the working tree; the RR export in the multi-repo shape,
`GameStudio/ui/Facet` beside `games/RascalRally/code`). Nothing measured in-tree.

**What B-7 actually was.** Not a missing option — a missing SUBSTRATE. The audit
parked the shipped rail mid-card (x=77 on a 140px pitch), settled thirty frames and
read x=77 back; no `snap`, `paging` or `scrollTarget` symbol existed anywhere in
`src/`, so the compact carousel could not be built by anyone, and B-8's page sizing
and B-9's dots were both inert behind it. It is the one cell in the whole matrix the
director's own worked example fails on outright.

## Layer 1 — `snap` on the scroll substrate

`snap = "none" | "item"` on `newVirtualList` and `newVirtualGrid`, live (a string or
a Readable), refused by value at construction. `src/controls/scroll_snap.luau` holds
both halves: a pure `resolve(...)` over an extent index, and the small settle machine
that decides when to ask.

**The engine gives neither a snap nor a release event**, which shaped everything:

* "the gesture released" is not observable — "the offset stopped changing" is, so the
  detector is a quiet window (0.12 s) re-armed by every mirror sample;
* "release velocity" is not observable — the peak SPEED across the travel is, from the
  samples themselves, and it is timed by the quiet ramp itself (a linear 0→1 glide, so
  the seconds between two samples are `ramp × QUIET_S`) rather than by a second time
  source. One clock drives detection, timing and travel, which is why a scripted
  `pres.tick(dt)` replays a flick exactly;
* **no second scroll driver and no input listener.** The samples arrive on the
  `CanvasPosition` mirror the collections already keep, and every write goes through
  `controller.scrollTo` — the framework's one programmatic scroll write.

**One extent source.** The boundaries are `index.offsetOf(i)` from the SAME
`virtual_extents` index the windowing divides by, so variable-extent rows snap to
their measured boundaries with no parallel arithmetic to drift.

**The three bounds the brief asked for, and what each cost.**

* *A flick advances.* Round-to-nearest alone makes a short, fast flick undo itself;
  above 240 px/s a travel may not land short of the next boundary in its direction. A
  slow drag keeps round-to-nearest, which is what lets a player change their mind.
* *An item taller than the viewport disables snap for that settle* — both the item the
  offset is inside and the one it would land on are asked. Content access beats
  alignment, the localization rule applied to the scroll axis.
* *The end is a resting place.* `maxScroll` is a member of the candidate set, not a
  clamp artefact: any rail whose viewport is not a whole number of pitches — every
  one-up rail with a peek — has a last page no boundary can express, and without the
  terminal a settle 5px short is dragged 95px back forever. A flick was given an
  exemption from that rule and then had it taken back: to be pulled back to the end a
  flick would have to leave it at speed and travel less than half a card, which is not
  a gesture a hand can make, and **a rule for a case nobody can reach is a rule
  nothing can check** — it was measured as a vacuous mutation before it was deleted.

**Reduced motion and idle cost are the motion authority's, not a second policy.** The
travel is a `clock:spring` of the default `decorative` kind, so reduced motion places
the offset at the terminus and announces the same arrival on the same frame; both
motion values are settled at rest and a settled value has left the clock, so a
snapping list nobody is touching runs zero per-frame work (asserted against
`clock:activeCount()` and the clock's own write counter).

**Keep-visible, `scrollTo` and focus traversal land ON a boundary**, by rounding the
solver's minimal answer outward in the direction the scroll is already going — the
plain answer still decides whether to move at all and which way.

**Every framework-issued write announces a REST first** (keep-visible, the programmatic
scroll, and the variable-extent anchor correction). Read as a travel, an anchor
correction looks like a flick of exactly its own size and advances a card nobody
swiped.

## Layer 2 — the compact card paradigm

`itemExtent = "cards"` is a fifth extent form beside `"measured"`, and it is the only
one that answers "how big is one item" with an ARRANGEMENT. `cards` is its options
table (`perView` / `minWidth` / `peek`) and is refused without it, the same relation
`estimatedItemExtent` has with `"measured"`.

* **compact + touch-primary → one card per view, a peek of the next, `snap = "item"`.**
  The peek is the affordance that there is more (the audit's own words in B-9); the
  snap default follows the ARRANGEMENT, not a second decision — a rail that resolved
  one card is a pager and pages snap.
* **regular and wide → a multi-up rail, snap unset** unless authored.
* **Authored always wins**, both keys, in both directions.
* The rung is asked of the RAIL'S OWN EXTENT, not the screen's `sizeClass` (a rail in
  a sidebar on a 1600px desktop has 300px), and of `touchPrimary` rather than
  `classes.touch` (ADAPT-9's ruling, through the one function that owns it).
* The thresholds are `adaptive.CARD_MIN_WIDTH` / `adaptive.CARD_PEEK` with
  `adaptive.cardsPerView` / `adaptive.cardPeek` beside `columnsFor`: pure, exported,
  predictable, and reachable by the next card surface without copying a number out of
  a control. They are arrangement facts, not theme metrics — a package decides how a
  card is painted, never how many of them a phone shows.
* **ADAPT-1 discipline, including the refusal.** A rail that leaves `perView` to the
  facts refuses to construct without an environment, in `tab_view`'s shape;
  `newVirtualList` is the sixth control the api.md refusal guard now finds, and its
  section names both the refusal and the environment. A rail that pins `perView` asks
  nothing.

**The fixture proves it with no branch.** `examples/gallery/scenarios/card_rail.luau`
lost its `ITEM_EXTENT = 132` constant and declares `itemExtent = "cards"`; a spec
reads the source back and fails on `sizeClass`, `interactionClasses` or `ITEM_EXTENT`
appearing in it. At 390 touch it is one card and snapping; at 1232 it is five and not.
The gallery's own pins moved from the constant to `rail.dump().itemExtent` — the rule
that file already kept for its rail width, applied to the card width.

## The paradigm-matrix conformance

`tests/paradigm_cards.spec.luau` derives the set of scrolling collections that can
hold a card set from the SOURCE — every control whose closed key set accepts `snap` —
and fails when one of them has no declared compact answer. A deliberate refusal is an
answer (VirtualGrid's `columns` is required, with a route, and the row asserts that is
still true); what is refused is SILENCE, because silence is exactly how the
large-screen arrangement ships everywhere.

## Extraction, since the file was the constraint

`virtual_list.luau` was 181,028 — 18,972 from the 200,000-char write cap — and this
feature is 9,320 of it. Two seams left in the same wave: `controls/card_rail.luau`
(the arrangement, one-way today — it reads nothing of the list and every input arrives
through a parameter object) and the `snap` vocabulary/refusal/read, which went into
`scroll_snap.modeReader` and is SHARED with the grid so two collections cannot drift
into two refusal messages. The file is 190,348 with a new ledger row naming the hosted
row-actions block (43,615 chars, 23%) as the next seam and its own 193,000 trigger;
without the extractions it would have been 199,844, i.e. 156 characters from the cap.

## The re-verdicts

| cell | was | now |
|---|---|---|
| **B-7** paging / snapping (ADAPT-17) | MISSING (highest) | **FIXED** — `snap` on both collections, the paradigm on the rail, the fixture switching with no branch |
| **B-8** page sizing | AUTHORED-ONLY, inert | **SUPERSEDED** — `containerRelativeFrame` still works and is still authored; a carousel no longer needs it |
| **B-9** page-dot indicators | MISSING, blocked by B-7 | **DEFERRED — director**, unblocked. The peek is the shipped affordance; a dot strip is a second one with its own four-input reach story |

## Carried to the director

1. **B-9's dots.** Unblocked and deliberately not taken: the peek is an affordance the
   framework can prove; a dot strip is a control, and a control needs a reach story on
   pointer, touch, keyboard and pad before it ships. One director call decides whether
   a peeking carousel wants dots at all.
2. **`snap` on a plain `UI.ScrollView` is CONTESTED**, not built — see the report's
   contested section. The route that exists today (`Controls.VirtualList{ axis = "x" }`)
   is the shape B-5 already calls right and ADAPT-24 made pad-navigable.
3. **0.12 s and 240 px/s are numbers a thumb can disagree with.** Headlessly they are
   only self-consistent. Three Studio rows are booked (§7 row 12).
