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
| ADAPT-8 the ten-foot ladder is only type/overscan/focus | MISSING (director call) | **RE-VERDICTED 2026-08-20 → FIXED (wave TEN-FOOT)** | Director ruled AGAINST type-only. The whole metric ladder scales by the TYPE FLOOR'S OWN 1.5 (`themes.metricScale` is `tenFootFloor`, one constant, two ladders), applied in the environment's `themeMetrics` memo. Acceptance is the director's proportion equality — every text-to-control proportion at ten-foot equals its near proportion — asserted over every scaled metric of all nine shipped configurations and, separately, as the ratio itself over 6 type roles × 14 control metrics. [ADR-0039](../../../../docs/adr/ADR-0039-ten-foot-metric-ladder.md); `tests/ten_foot_metrics.spec.luau`. Art geometry (`chromeInsets`/`chromeOutsets`/`chromeBleed`) deliberately does NOT scale: a nine-slice border is painted at the size its recipe declares, so its reservation must stay the number the paint will be |
| ADAPT-10 no gamepad rung in the density ladder | MISSING (high) | **CONTESTED — `table.luau`** | `snapshot.luau:686-692` publishes two keys and I may add a third, but the SELECTION is `table.luau:470` (`if classes.touch then "touch" else "pointer"`). Publishing a rung nothing selects would be ceremony. **This one bit during the wave:** ADAPT-7's fix made Cartwheel's ten-foot table row overflow by 5px — a 41px button inside the densest row the framework ships — and the example had to absorb it (§4). |
| ADAPT-11 table density is caller-wired; 36px on a touch phone | AUTHORED-ONLY (high) | **CONTESTED — `table.luau`** | `table.luau:499-503` returns `rowBoxFor(nil, …)` when `spec.env` is absent. The channel this wave built (`surface_env.find(core)`) is exactly what would close it — three lines, in the closed file. |
| ADAPT-12 the 44px floor is unexamined off touch | MISSING (low) | **RE-VERDICTED 2026-08-20 → FIXED (wave TEN-FOOT)** | Exactly as the audit's own disposition asked: fixed WITH ADAPT-8. `targetSizes.minimum` is 44 near and 66 at distance, through one owner — `layout_node.effectiveHitFloor` reads the metric and both of its readers (the solve's `hitFloor` and `pushHitRects`) follow the ladder without knowing it exists. The pointer half stays deliberately unsplit: a denser floor for a precise mouse is a second decision with no measurement behind it yet |
| the env default `themeMetrics` resolves with `facts = {}` | hazard (under ADAPT-8) | **RE-VERDICTED 2026-08-20 → FIXED (wave TEN-FOOT)** — the architectural decision this row asked for was taken: [ADR-0039](../../../../docs/adr/ADR-0039-ten-foot-metric-ladder.md) Decision 2. `themeMetrics` is now published BOTH ways on one key: the fact the controller still commits atomically (unchanged), and a derived read that applies the display class's distance policy. The default snapshot stays `neutral()`; the display fact is what carries the density. This row's own worry — "a change to a fact the controller commits atomically with the native derive swap" — is why `env:set` normalises through `themes.baseOf`, so the fact always holds an authored base and a read-hold-write round trip is exact. Original note follows. | `environment.luau:136` defaults to `themeSnapshot.neutral()`, whose `density` is `"near"` even on a Large display, until a caller re-resolves with the live fact (`theme_controller` does, on a real client). ADAPT-23's solver-side cap reads that fact, so a headless surface with no theme controller keeps the near-distance lane count. Making `themeMetrics` DERIVED is a change to a fact the controller commits atomically with the native derive swap — architectural, and worth a decision rather than a patch. |

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
| ADAPT-8 · the ten-foot metric ladder | **CLOSED 2026-08-20 — director ruled BUILD (full Apple-TV-style scaling)** | Shipped by wave TEN-FOOT; see the Family I row above and [ADR-0039](../../../../docs/adr/ADR-0039-ten-foot-metric-ladder.md). ADAPT-12 closed with it. What remains is the human-factors half the audit correctly said a headless probe cannot answer: whether 1.5 is the right factor at three metres, which is a batched-Studio/device row and a director sign-off, not a fix. |
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
into two refusal messages. The file is **192,195** with a new ledger row naming the hosted
row-actions block (43,615 chars, 23%) as the next seam and its own 193,000 trigger —
**805 characters away, recorded as ARRIVED**; without the extractions it would have been
201,691, i.e. PAST the cap. The row first recorded 190,348 and was wrong by 1,847, which
is 92% of `check_source_size`'s allowance and therefore invisible to it: the wave's
reviewer found it, and the row now carries the discipline that prevents it — measure
LAST, after the final format pass.

## The re-verdicts

| cell | was | now |
|---|---|---|
| **B-7** paging / snapping (ADAPT-17) | MISSING (highest) | **FIXED** — `snap` on both collections, the paradigm on the rail, the fixture switching with no branch |
| **B-8** page sizing | AUTHORED-ONLY, inert | **SUPERSEDED** — `containerRelativeFrame` still works and is still authored; a carousel no longer needs it |
| **B-9** page-dot indicators | MISSING, blocked by B-7 | **DEFERRED — director**, unblocked. The peek is the shipped affordance; a dot strip is a second one with its own four-input reach story |

...and the LAYOUT matrix's three cells for the same finding, which were measured
against an anchor this wave had not yet landed at (`matrix-layout.md`, committed at
`ce56ac6`): **ADAPT-17** (its own Part-1 carry-over), **F-5** (the compact-touch card
carousel, "unreachable") and **ADAPT-L10** (the same, as a finding). All three are
closed by `f3d2fe8` and are ANNOTATED in place rather than rewritten — that artifact's
own preamble predicted it ("measured at the anchor and expected to be stale on
arrival") and asked the controller to re-check rather than route. Its device row 7 —
whether engine momentum was masking the gap — is the same question as this wave's
Studio row 12a and is answered by it.

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

---

# ADDENDUM — wave LAYOUT-FIX (2026-08-21): the layout primitives answer for themselves

**Anchor:** framework `fd59cae` (suite 6750), RascalRally `655cbd7` (suite 3437).
**End state:** Facet **6781**, RascalRally **3443**, both green, both measured in
private exports (an rsync of the working tree; the RR export in the multi-repo
shape, `GameStudio/ui/Facet` beside `games/RascalRally/code`). Nothing measured
in-tree. Two writers were live on the same working tree throughout (wave
THEME-UNBUNDLE in `tools/build`, `docs` and `examples/themes`), so every commit
here went through `tools/commit_isolated.py` and the suite tails above include
their in-flight work.

**Scope.** `matrix-layout.md`'s 61 cells, minus ADAPT-L1 (folded into wave
TEN-FOOT) and ADAPT-L10 (closed by wave CAROUSEL). `renderer.luau`,
`presenter.luau`, `solver.luau`, `virtual_list.luau` and `table.luau` are
extraction-locked per their `SOURCE_CAP_LEDGER` rows and none was touched; every
cell that needed one of them is CONTESTED below with the exact line it needed.

## 1. The cell-by-cell disposition

**Counting rule:** one row per non-RIGHT cell of the Part-2 tables — 61 cells, 42
RIGHT, so **19 non-RIGHT**. Every one appears.

| cell | verdict | disposition | evidence |
|---|---|---|---|
| **A-2** `AdaptiveStack` without `axis` is a permanent VStack (ADAPT-L4) | WRONG (high) | **FIXED** | `axis` is `required = true`; the refusal names the fact, the host and both unconditional classes. `layout_defaults.spec` carries it, the phrase check, and two null hypotheses (a bound axis still flips in place; the fixtures' own 132px-plate reproduction is a column at 320 and a row at 1280). The three shipped fixtures now bind `conditions.axis`, so their comments are TRUE |
| **A-4** `DEFAULT_STACK_ABOVE = 600` is content- and type-blind (ADAPT-L6) | WRONG (high) | **CONTESTED** | The cell's own expected column names the remedy as `ViewThatFits` — "the framework already owns the honest instrument" — i.e. the fix is to change what the guide TEACHES, not what the threshold answers. A threshold that knew its content would have to MEASURE it, which is the same seam A-5 is blocked on, in the same locked files |
| **A-5** the adaptive axis is a screen fact in a container that got less (ADAPT-L3) | WRONG (high) | **CONTESTED, measured and guarded** | Both candidate fixes are out of reach and the spec says why in the file. (a) is refused by the framework's own deprecation ledger: `src/init.luau` retired `adaptive.conditions().contentWidth` at 0.8.0 with the note *"alias; the value never subtracted insets"*, so giving it new meaning contradicts a published removal — and it would not close the audit's own reproduction anyway, which is PAGE PADDING rather than an inset. (b), the offer-derived axis, is not one file: `present/focus_map.luau:640-665` reads the axis PROP live to decide which way a pad navigates the stack (the D5 defect that had every segmented picker navigating vertically), so a solved axis must reach the focus derivation through solver, renderer and presenter — three locked files. The band is guarded instead: `layout_defaults.spec` pins that it exists at 600/610/640, closes at 560 and 680, and is never silent |
| **A-8** `wrap` is never bound to a size class anywhere | AUTHORED-ONLY | **CONTESTED** | One half of ADAPT-L5's fix (a) — see F-2 |
| **B-1** `UI.Grid` is one lane at every combo (ADAPT-L2) | WRONG (critical) | **FIXED** | The default is `minColumnWidth = "intrinsic"`, so a grid told nothing lanes itself from the box it got through the same `adaptive.columnsFor` call the declared route uses. Measured at the audit's own six combos: 2/4/6/9/5/7, identical to the declared answer, with the television under the desktop |
| **B-2e** the ten-foot lane cap (ADAPT-L1) | WRONG → **re-verdicted RIGHT** | **RESOLVED BEFORE THIS WAVE** | wave TEN-FOOT; re-measured here on the default path at 5 lanes against a desktop's 9 |
| **B-3** 0 of 35 `Grid` sites bind lanes reactively | AUTHORED-ONLY | **RESOLVED by ADAPT-L2** | There is nothing left to bind: the default now answers. §2 re-verdicts all 35 |
| **B-4** `GridRow` squeezes past declared fixed widths in silence (ADAPT-L8) | WRONG (medium) | **FIXED** | The squeeze is REPORTED, narrowed to a declared `fixed` width. Geometry unchanged and re-pinned at the audit's own five numbers |
| **B-6e** ten-foot `Composition` main lane is 1316px | AUTHORED-ONLY | **RULED, THEN FIXED** (controller ruling R14, 2026-08-21 — see §7) | This row was written CONTESTED, as the one cell blocked by nothing but a number. The number was ruled mid-wave: **900 = the regular-touch tablet measure (600, cell B-6c) x the 1.5 distance factor**, the same proportion-equality doctrine every ten-foot number rides, and derived rather than chosen so a re-ruling is one line. Shipped as the DEFAULT on a `fill` group's new `maxWidth`, with a director veto open at batched §13h |
| **C-1** ZStack children default to the top-left corner (ADAPT-L11) | WRONG (medium) | **CONTESTED** | The default is in the solver's zstack arrange (`solver.luau:3029`, locked) and moving it re-places children on ~140 shipped `ZStack` sites (the 148 first written here is the audit's inherited figure; a comment-aware recount measures 141 by my method and 139 by the reviewer's — immaterial to the contest, and corrected rather than left). The audit's own device row 10 asks the director whether it reads as a mistake at all |
| **C-3** no compact answer for overlaid content | MISSING | **CONTESTED** | Part 1's ADAPT-25 seen from the layout side, and contested there for the same reason: there is no `UI.Sheet` and `presentModal` has no size-driven form. A new presentation primitive, not a connection |
| **D-3** a `ViewThatFits` ladder never steps down for typography when the cross axis is free (ADAPT-L12) | WRONG (medium) | **CONTESTED** | `solver.chosenCandidate` (locked), and the audit is explicit that this is not a bug in contract 7 but "the boundary of what a width-plus-cut test can see". Closing it means a NEW fit criterion — a height budget a rung can fail — which is new machinery with its own authoring surface |
| **E-3** spacing tokens are combo-invariant (ADAPT-L9) | WRONG → **re-verdicted RIGHT** | **RESOLVED BEFORE THIS WAVE** | wave TEN-FOOT |
| **F-1** the default answer to overflow is paint-outside (ADAPT-L5) | WRONG (high) | **CONTESTED, guarded** | `render/renderer.luau:1483` keys the engine scroll host on `node.class == "ScrollView"`, not on the solved kind — so the one seam this wave could reach would buy a scroller's LAYOUT with no scrolling, which is worse than today rather than partial. Guarded instead: all three of the audit's reproductions, and the page shape at all six combos, asserted for a diagnosis that carries the container, the axis, a real pixel count and both fixes — the one property the always-on sweep cannot check, because it counts findings and never reads one |
| **F-2** `wrap = true` is the authored answer and is never a default | AUTHORED-ONLY | **CONTESTED** | `wrap` decides the solver KIND at the measure seam, and a wrapping stack has no shrink pair by design, so wrapping by default would silently disable the shrink cascade on every stack that has one — the "silent re-flow of shipped screens" the solver's own overflow comment refuses to be |
| **F-4** a scroll host is never the default | AUTHORED-ONLY | **ALREADY SHIPPED** | The cell's own stated minimum is *"the solver's finding should escalate"*, and `tests/overflow_sweep.spec.luau` is that escalation: every showcase surface at nine viewports, four text preferences and the themed and locale tiers, on every `./run-tests.sh`, with nobody deciding to run it. Recorded rather than rebuilt |
| **F-5** the compact-touch card carousel | MISSING (high) | **FIXED — wave CAROUSEL** | Annotated in `matrix-layout.md` at the anchor |
| **G-4** the default root policy ignores `deviceSafeInsets` (ADAPT-L7) | WRONG (medium-high) | **CONTESTED** | The policy is `renderer.luau:189` and `presenter.luau:1709`, both locked. The audit's own confidence is medium pending device row 1 (whether the CORE inset already subsumes the device area on a notched phone), which is the row that decides whether this is medium-high or low |
| **G-5** no title-safe full-bleed policy at ten-foot (ADAPT-L13) | MISSING (low) | **CONTESTED** | A new value on `rootPolicy`, resolved in `renderer.luau:1884-1885` (locked), and a new public word for a distinction the framework has not yet made |

### The counts

| disposition | cells |
|---|---|
| **FIXED** | **5** (A-2, B-1, B-3, B-4, B-6e) |
| RESOLVED before this wave (TEN-FOOT, CAROUSEL) | 3 (B-2e, E-3, F-5) |
| ALREADY SHIPPED (the cell's own stated minimum) | 1 (F-4) |
| **CONTESTED** (with the exact blocker) | **10** |
| **total** | **19 cells**, which is 61 − 42 RIGHT |

Of the ten contested, **eight are blocked by an extraction-locked file** —
`solver.luau` (A-4, A-5, C-1, D-3, F-1, F-2), `renderer.luau` (F-1, G-4, G-5) and
`presenter.luau` (A-5, G-4). Two are genuinely new capability (C-3, D-3's height
budget). The eleventh — B-6e — was the one blocked by nothing but a director's
number, and that number arrived mid-wave (§7).

## 2. The 35 `UI.Grid` sites, re-verdicted

A brace-matched census of every `UI.Grid{…}` call site in `examples/` and `src/`
(31 + 4, which reproduces the audit's own 35 — see the correction below):

| what it declares | sites | verdict |
|---|---|---|
| `columns = <integer>` | 7 in `examples/`, 3 in `src/` | **stay authored.** Every one is a semantically fixed lane count rather than a hand-computation dodging the default: a Wordle board (`COLS`), a tile-game board and its rack (`#RACK`), a match-3 board, a two-up dashboard tile grid, a five-seal run, and `level_picker`'s `columns = count` — which exists so the marks SHRINK TOGETHER rather than starving the tail, and says so at the call site |
| `minColumnWidth = <px>` | 17 | **stay authored.** Dense readouts and avatar/chip strips whose minimum is a deliberate device-pixel decision (48, 56, 72, 90, 96, 104…) |
| `minColumnWidth = "intrinsic"` | 6 | **stay authored, and are now a restatement of the default.** Left standing on purpose: they are what keeps the enum value exercised in a shipped surface, and none of them has "the default lanes itself" as its point |
| neither | 1 in `examples/`, 1 comment in `src/` | **unaffected.** The single real site (`adaptive_controls.luau:525` `Specs`) is a GRIDROW-mode grid, and the flow plan's lane count is never asked of one |

**Correction to the count, 2026-08-21 (fix round 1).** "31 + 4 = the audit's 35, bit
for bit" reproduced the audit's number by reproducing its METHOD, prose mentions
included. A comment-aware recount finds **32** real `UI.Grid` construction sites by
my method (30 examples + 2 src) and **33** by the wave reviewer's, the difference
being where each draws the line on a call that spans a comment boundary; the audit's
extra two or three are mentions inside doc comments (`virtual_grid.luau:96` and
`:144`, `05_word_game.luau:28`). The disposition above is identical under all three
counts, which is why the number was never load-bearing — and why it is corrected
here rather than swapped for another unverified one.

**Nothing was dropped, and that is the honest outcome rather than a shortfall.** The
brief's rule was "sites that hand-computed lanes to dodge the default drop the
hand-computation where the default now answers". Measured, no site did: the corpus
had already authored around the one-lane default with reasons, which is exactly the
AUTHORED-ONLY shape B-3 recorded. The blast radius of a critical default change was
therefore **zero shipped call sites**, and both of Rascal Rally's live grids already
name `"intrinsic"`.

## 3. The 38 three-plus-child `HStack` rows, re-verdicted

The audit counted **38** `HStack`s with three or more literal children, no `wrap`,
and no horizontal `ScrollView` ancestor — "the shape that overflows a 390 px phone".
Re-censused here at **21** by a stricter rule (direct `UI.*` children only; rows
assembled from helper locals are not counted, and the audit's own note says six more
build their children dynamically). The number is not the finding either way.

**The finding is that the shape is not where the corpus actually bleeds.** The
always-on sweep has 17 standing waivers, every one measured cosmetic under the
director's 2026-08-15 ruling, and their classes are the re-verdict:

- **exactly ONE is an `hstack` overflow** (`p2_cartwheel`'s `OpenPotions` rack);
- **six are `content overflows this vstack`** — a PAGE taller than its box with
  nothing to scroll it;
- five are zstack layer overlaps, three are the fixed-px-vs-text class, and two are
  collapsed content boxes — which accounts for all ten of the remainder. (The first
  draft of this list said "the rest are zstack overlaps and two collapsed content
  boxes" and covered seven of ten, omitting the three `fixed-px-vs-text` rows.)

**One labelling note, because the two counts are taken differently.** The six above
are counted by the waiver's `kind` field (`page-not-scrollable`), while the sentence
names them by their finding SIGNATURE. By signature alone there are **nine**
`content overflows this vstack` waivers against the one hstack — so the direction
this section draws is stronger under either reading, not weaker, and the number is
labelled here rather than left to be discovered.

So the row-shaped worry behind fix direction (a) — bind `wrap` by default — is
answered by the corpus itself: rows are not what overflow. **Pages are.** That is
direct evidence for direction (b), the implicit page scroll host, being the fix
worth the renderer work when F-1 is unblocked, and against (a) being worth its
shrink-cascade cost. No fixture was found misteaching, so none was edited.

## 4. The consequence found rather than claimed

ADAPT-L8's first version reported EVERY squeeze, and the always-on sweep answered
within one run: `adaptive_controls`'s spec table squeezes 168px at 320x640 under
`preferredTextOffset = +14` on classic-desktop, and every cell in it is
content-sized text that simply wraps into the narrower column. The audit had
measured that shape separately and called it RIGHT (cell B-5, *"wraps gracefully"*).
A finding there would have been the sweep learning to cry wolf on its own corpus.

So the finding is narrowed to a column holding a cell with a declared `fixed` width
— a promise the squeeze breaks — and the content case is a null-hypothesis case of
its own in `grid_row.spec`. Removing the narrowing reddens it. The instrument that
caught the over-report was the sweep, not a reading of the diff.

## 5. The tooling trap this wave hit, recorded where the next wave will look

`tools/commit_isolated.py` filters a diff to the HUNKS containing a marker, and
ADAPT-L4's commit landed WITHOUT `required = true` — the one load-bearing line of
the whole change — because that line is its own hunk three lines away from the
twelve lines of prose that carried the marker. HEAD was red for one commit. The
`docs/reference/api.md` signature change (`axis?` → `axis`) was dropped the same
way, in the same call.

**The discipline: read the `drop` list, not the `KEEP` list.** The tool prints both.
The `KEEP` list is the one an author scans, because it is the one they wrote; a
one-line mechanical change is exactly the shape that carries no prose, therefore no
marker, and therefore drops silently — and it is exactly the shape that matters
most. `8fd4779` is the correction and says so.

## 6. Carried to the director

1. **B-6e's number is RULED and SHIPPED** (R14) — see §7. What is carried is the
   director's veto on it, booked as batched Studio row §13h: whether a 900px line
   reads as one line at three metres, and whether the slack the cap frees reads as
   deliberate margin or as a screen that failed to fill.
2. **ADAPT-L5's direction, now that the corpus has voted.** §3 above says pages
   overflow and rows do not. If the implicit page scroll host is wanted, it is
   renderer work behind the `rect_pass` extraction that row already owes.
3. **The three locked-file bundles.** A-5/A-4 (an offer-derived axis, which also
   needs `focus_map` to read a solved fact rather than a prop), C-1 (the ZStack
   default, plus a director's eye on 148 sites), and G-4/G-5 (the root policy's
   inset source and a title-safe full-bleed word) are each one small change behind
   one big lock.

## 7. B-6e, ruled and shipped (controller ruling R14, 2026-08-21)

**The ruling.** The `Composition` content-lane measure caps at ten-foot to **900px
= the regular-touch tablet measure (600 — this matrix's own verified-RIGHT B-6c)
times the 1.5 distance factor**. Same proportion-equality doctrine as every other
ten-foot number (ADR-0039), and the director's veto is open at batched §13h.

**It is DERIVED, which is the half that makes a re-ruling cheap.** `900` appears
nowhere: `adaptive.LANE_MEASURE` is 600 and the factor is read from
`themes.snapshot.metricScale`, the one `tenFootFloor` behind the type ladder, the
metric ladder and the hit floor. A re-ruled measure is one edit and a red spec row
naming the new number.

**The seam is NOT the one the audit named, and the correction matters.** The row
nominated `maxMeasure` and the per-arrangement `eligible` gate. `maxMeasure` caps
the whole BOX and every lane then divides what is left — so capping at 900 would
have narrowed the HUG lanes with it, giving the content lane 452px, which is
*narrower than the tablet's* and the opposite of the intent. The measure is a
property of a `fill` lane, so the fill group gained **`maxWidth`**, `minWidth`'s
exact twin, and the ruled value is its ten-foot default. Authored wins in both
spellings (a group's own `maxWidth`, or `maxMeasure` on the composition), each
proved by a mutation.

**What the cap frees, the arrangement re-absorbs, and what is left centres the
band.** Other fill lanes water-fill up to their own caps; a `threeLane` with one
fill lane has nothing to re-absorb it, so the 196px on each side becomes the
centring offset the resolution already carried for `maxMeasure`. Parking a capped
band against the left edge would have been a worse answer than the one it replaced.

**The consequence found rather than claimed, again, and again by the sweep.**
Narrowing the ten-foot lane made Cartwheel's potion tiles overflow by 7px on all 17
visible cells — and the cause was NOT the cap. `metrics.tileMin` is a literal 96
device px while everything inside a tile is a theme metric, so at ten-foot the mark
grew to 72 and the button's padding to 18 a side: 108px of content asking for a
96px minimum. That is `docs/lessons/facet-fixed-px-heights.md`'s class read across
the DISTANCE axis, it had been there since the display class was added, and the
extra lane width was hiding it. The fixture now takes the same `metricScale` its
contents take — byte-identical at near distance — and says so at the call site.

**Rascal Rally moves, deliberately, and only at ten-foot.** `ResultsBody` is the one
`UI.Composition` the game ships and it declared a television display class three
commits before this wave. Its field lane goes 992 -> 900 on a television and is
byte-identical on every near viewport, both asserted at the same 1920x1080 rect so
the two cases differ in exactly one fact. Disabling the framework default reddens
the ten-foot case and leaves the near case green.
