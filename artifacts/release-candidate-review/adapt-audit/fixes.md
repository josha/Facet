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
unit the audit counted (114 cells, 58 RIGHT). Every non-RIGHT cell appears; nothing is
silently skipped. `RESOLVED` means the wave fixed it, `CONTESTED` means it is a real
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
| B-7 no scroll snapping anywhere (ADAPT-17) | MISSING (highest) | **DEFERRED — director** | Out of scope by the brief |
| B-8 `containerRelativeFrame` page sizing | AUTHORED-ONLY | **BY PARITY** | Correct and matching; inert as a carousel until B-7 |
| B-9 no page-dot indicators | MISSING | **DEFERRED** | Follows B-7 |
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
| **FIXED** | **15** |
| RESOLVED before this wave (Family F + ADAPT-6) | 6 |
| **CONTESTED** (with the exact blocker) | **21** |
| **DEFERRED** (director items and their consequences) | 6 |
| BY RULING / BY PARITY / BY ENGINE (documented decisions, no action) | 10 |

Of the 21 contested, **eleven are `table.luau`** (ADAPT-13, 14, 15, 19, 27, 11, 10,
M-4, J-3, J-4 and the `fill`-column half of J-2) — the single highest-value unblock
available to this project is that file's extraction.

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
