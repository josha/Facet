# WP-B: Input auto-adaptation audit — the big composites (Table, VirtualList)

Scope: `src/controls/table.luau`, `src/controls/virtual_list.luau`, the Grip
resize handle, the presenter pointer/action seam (`src/present/presenter.luau`,
`src/client/screen_target.luau`, `src/render/renderer.luau`), and the four spec
files. Audited against the director standing principle (ui_todo.md §0): every
control must ship the right interaction for pointer / touch / keyboard / gamepad
**with no consumer wiring**.

Classification key:
- **FRAMEWORK-AUTOMATIC (FA)** — works by merely mounting the control (the
  gesture handlers live in the control's blueprint and the adapter/renderer
  capture them without the screen passing anything).
- **CONSUMER-WIRED (CW)** — works only because the screen hand-passes a handler
  or group to `present(...)`. **An api the control exposes that the consumer
  MUST call** (`buildFocusGroups`, `handleActivate`, `handleGrabNavigate`,
  `handleFocusMoved`, `handleAdjust`, `handleReorderNav`) is CW even though the
  logic lives in the control — mounting alone does not connect it.
- **MISSING (M)** — no path exists on that input class.

The canonical hand-wiring is `examples/gallery/examples/02_playlist_table.luau`
lines 273-316 (`navigationGroups` merges `tbl.api.buildFocusGroups` @284;
`onNavigateIntercept` = `tbl.api.handleGrabNavigate` @291-293; `onActivate`
dispatch chain calls `tbl.api.handleActivate` @304; `onFocusNav` =
`tbl.api.handleFocusMoved` @308-310). The Table test harness wires the same
plus `onAdjust`/`onReorderNav` (`tests/table.spec.luau` @76-85).

---

## 1. The matrix

Cell format: affordance — CLASSIFICATION (evidence).

### Table

| Behavior | pointer (mouse) | touch | keyboard | gamepad |
|---|---|---|---|---|
| **row-selection** | tap toggles/replaces/ranges by meta — **CW**. Button hit + `selected` visual are FA (`table.luau:616-627`), but the tap→selection routing runs through presenter `onNodeTap`→`handle.onActivate` (`presenter.luau:110-119`) which is the screen's `opts.onActivate`, and the screen must call `api.handleActivate` (`table.luau:1022`, `1063-1071`; example @304). | additive-toggle tap idiom — **CW**. Same `handleActivate` path; meta `pointer="touch"`→additive (`table.luau:1063`; test @912-919). | focus + Return/Enter selects; selection-follows-focus — **CW**. Return→`activate.onPressed`→`onActivate`→`handleActivate` (`presenter.luau:299-311`); arrow-move selection needs `onFocusNav`→`handleFocusMoved` (`table.luau:1247-1257`; presenter @281-286; test @811-823). | D-pad + A selects — **CW**. Same as keyboard; DPad bindings are FA (`presenter.luau:169-170`) but selection routing is the same consumer apis. |
| **header-sort** | tap a sortable header cycles `sortOrder` — **CW**. Sort hit Button is `focusable=false` (`table.luau:767-774`); tap routes via `onNodeTap`→`onActivate`→`handleActivate` sort branch (`table.luau:1039-1048`; test @460-468). | same tap path — **CW** (`table.luau:1039`). | **MISSING**. The sort hit is `focusable=false` (`table.luau:771`) so focus never lands on it and there is no `api.sort`/`handleActivate`-reachable keyboard route; test @474 asserts sort hits stay out of the focus ring. | **MISSING**. Same — no focusable sort target, no gamepad path. |
| **column-resize (Grip)** | drag the header grip; preview line + commit on release — **FA**. Grip handlers are in the blueprint (`table.luau:690-738`); adapter capture is automatic (`screen_target.luau:632-702`; `pointer.spec.luau:50`; test @931-949). | drag the grip on touch — **FA** (functionally). `InputBegan` handles `Touch` identically (`screen_target.luau:638-644`); no pointerType gate in `gripFor`. Caveat: 8px target, **no touch test** exists. | focused grip + Left/Comma Adjust resizes one step — **CW**. Grip focusability is FA (`table.luau:694`, deferred focus order `presenter.luau:54-65`), but Adjust routing needs `opts.onAdjust`→`api.handleAdjust` (`table.luau:1217-1241`; presenter binds Adjust keys ONLY when `opts.onAdjust` present @184-197; test @987-1001). Example 02 does **not** wire `onAdjust`, so resize-by-keyboard is dead in the shipped gallery. | ButtonL1/R1 Adjust or DPadLeft/Right — **CW**. Same `onAdjust`/`handleAdjust` seam (test @1002-1007). Headerless tables expose no grip at all (ADR-0008 rider). |
| **row-reorder** | direct row-body drag; ghost chip + drop line; commit via `onReorder` — **FA** (gesture). Handlers on the row Hit (`table.luau:614-627`, `383-556`); capture adapter-level; needs `reorderable=true` + data callback `spec.onReorder` (test @521-556). | pan scrolls, never reorders; reorder needs edit-mode ≡ handle — **CW**. Handle drag itself is FA (`table.luau:637-676`, `handleDragHandlers` @564-581), but entering edit mode requires activating the auto Edit/Done toggle, which routes `onNodeTap`→`onActivate`→`handleActivate` toggle branch (`table.luau:1024-1027`; test @1252-1265). No consumer `onActivate` ⇒ no way to enter edit ⇒ no touch reorder. | shift+Navigate moves the focused row — **CW**. Needs `opts.onReorderNav`→`api.handleReorderNav`/`moveRow` (`table.luau:1262-1288`; presenter @270-276; test @741-756). | A grabs, D-pad steps, A drops — **CW**. Grab = `handleActivate` w/ `meta.source=="action"` (`table.luau:1029-1035`); stepping = `onNavigateIntercept`→`handleGrabNavigate` (`table.luau:1081-1133`; presenter @247-253); all consumer apis (example @291-293; test @1337-1370). |
| **scroll** | mouse wheel, 40px/notch, clamped — **FA**. `UI.ScrollView` `onScrollWheel` in the control (`table.luau:821-834`); renderer `setScrollHandler` (`renderer.luau:295-299`; adapter `screen_target.luau:718-728`; test @1115-1126). | one-finger pan on a row body scrolls — **FA**. `panDrag` in the row handlers (`table.luau:402-408`, `437-439`; test @1088-1102). | **MISSING**. Focus can step to a row clipped off-screen; nothing calls `scrollOffset`. `handleFocusMoved` only selects (`table.luau:1247-1257`) — no scroll-into-view (unlike VirtualList `focusKey`). | **MISSING**. Same — D-pad focus does not scroll the body. |
| **cell/row focus-navigation** | click focuses (Apple model) — **FA**. `onNodeTap`→`graph.focusOn` (`presenter.luau:114`; test @801-806). | tap focuses — **FA** (same `onNodeTap`). | row-to-row up/down — **FA** (flat `focusOrder` auto-derives row Hit Buttons, `presenter.luau:67-73`, `247-288`; test @167-176). But **horizontal cell/column** nav (stepping across in-cell stars) is **CW** — needs `navigationGroups`→`buildFocusGroups` (`table.luau:1140-1200`; example @280-288; test @1321-1335). | D-pad up/down FA (auto DPad bindings); **left/right across a row = CW** via `buildFocusGroups` (same). |

### VirtualList

| Behavior | pointer (mouse) | touch | keyboard | gamepad |
|---|---|---|---|---|
| **scroll** | **MISSING**. The blueprint is a bare `UI.Anchor` with `overflow="clip"` (`virtual_list.luau:147-180`) — **no `UI.ScrollView`, no `onScrollWheel`, no `setScrollHandler`**. Verified: grep for ScrollView/onScrollWheel/onPointer in the file returns none. Only `scrollTop` (a Signal) drives position. | **MISSING**. No pan handlers, no `setPointerHandlers` — the explicit open item in ui_todo §3 ("Remaining open: VirtualList touch-pan wiring"). | driving `scrollTop:set(...)` / `focusKey()` scrolls into view — **CW** (programmatic only). `focusKey` scrolls the row into the band (`virtual_list.luau:130-145`), but nothing binds a key to it; the consumer must build the whole loop. | **CW** (same — consumer drives `scrollTop`/`focusKey`; no binding exists). |
| **focus/navigation** | **MISSING** (control-level). The row is a plain `VStack` (`virtual_list.luau:169-176`), not focusable; no row hit. Any focus ring exists only if the consumer's `cell` returns a Button. | **MISSING** (same). | focus-by-key exists but is entirely consumer-driven — **CW**. Exposes `pathOf`/`focusKey`/`focusedKey` (`virtual_list.luau:98-145`, `182-188`) and nearest-surviving-neighbor on removal (`:107-128`), but **no `buildFocusGroups`, no presenter integration**. The consumer must build groups from `pathOf` and call `focusKey` on every nav. | **CW** (same; no gamepad-specific path, no auto DPad→row mapping). |
| **activate** | **MISSING** (control-level). No `handleActivate`, no row hit. Activation exists only if the consumer's `cell` embeds its own Button and the screen routes `onActivate` to it. | **MISSING** (same). | **MISSING** (same — no control activate api). | **MISSING** (same). |

---

## Cell counts

36 cells total (9 behaviors × 4 input classes):

- **FRAMEWORK-AUTOMATIC: 7** — Table column-resize (pointer, touch), Table
  row-reorder (pointer), Table scroll (pointer, touch), Table focus-nav
  (pointer, touch).
- **CONSUMER-WIRED: 17** — Table row-selection ×4; Table header-sort (pointer,
  touch); Table column-resize (keyboard, gamepad); Table row-reorder (touch,
  keyboard, gamepad); Table focus-nav (keyboard, gamepad — cell/column axis);
  VirtualList scroll (keyboard, gamepad); VirtualList focus/nav (keyboard,
  gamepad).
- **MISSING: 12** — Table header-sort (keyboard, gamepad); Table scroll
  (keyboard, gamepad); VirtualList scroll (pointer, touch); VirtualList
  focus/nav (pointer, touch); VirtualList activate ×4.

The dominant fact: **the Table's entire input story on touch/keyboard/gamepad,
and all of its selection/sort, lives behind consumer-called apis** — mounting a
Table yields only mouse resize/reorder/scroll/wheel and pointer focus for free.
VirtualList is worse: mounting it yields **no pointer, touch, keyboard, or
gamepad interaction at all** — every class is MISSING or requires the consumer
to build the loop from raw signals.

---

## 2. What lifting looks like here

The goal (ui_todo §0): mounting a `Table`/`VirtualList` alone yields the full
four-input story. Today the presenter is a blank pipe — it only knows what the
screen's `opts` hand it (`presenter.luau:127-135` reads `opts.navigationGroups`;
`:110-119` calls `opts.onActivate`; `:234`/`:251` call `opts.onNavigateIntercept`;
`:281-286` call `opts.onFocusNav`; `:184` binds Adjust only if `opts.onAdjust`).
It never inspects the mounted tree for controls that could answer these itself.

The auto-wiring seam belongs at the **presenter ⇄ mounted-control boundary**: a
control should be able to advertise a small provider bundle
(`focusGroups(root)`, `activate(path, meta)`, `navigateIntercept(dir)`,
`focusMoved(path)`, `adjust(path,dir,rectOf)`, `reorderNav(path,dir)`) that the
presenter **discovers by walking the mounted tree** and composes automatically —
exactly the six methods every screen re-plumbs by hand today. Concretely, per
CONSUMER-WIRED cell:

- **Table row-selection / header-sort / focus-nav (all classes)** — the
  presenter's tap path (`onNodeTap`, `presenter.luau:110-119`), Activate
  (`:299-311`), and focus-move reporting (`:281-286`) should route to the owning
  control's advertised `activate`/`focusMoved` **without** the screen passing
  `onActivate`/`onFocusNav`. The control already has `handleActivate`/
  `handleFocusMoved` (`table.luau:1022`, `1247`); they just need to be
  presenter-discoverable rather than hand-dispatched.
- **Table cell/column horizontal nav** — the presenter's grouped-nav derivation
  (`presenter.luau:127-140`, refresh @416-422) should auto-collect
  `buildFocusGroups` (`table.luau:1140`) from every mounted control that
  provides it, instead of the screen merging them by hand (example @280-288).
- **Table column-resize (keyboard/gamepad)** — Adjust keys bind only when
  `opts.onAdjust` is set (`presenter.luau:184`); with control discovery, a
  mounted Table exposing a focusable Grip + `handleAdjust` (`table.luau:1217`)
  should make the presenter bind Adjust and route it automatically.
- **Table row-reorder (touch/keyboard/gamepad)** — grab (`handleGrabNavigate`),
  shift-reorder (`handleReorderNav`), and edit-toggle activation should ride the
  same discovered `activate`/`navigateIntercept` bundle.
- **VirtualList scroll / focus / activate** — needs both a discoverable provider
  bundle AND the missing gesture plumbing (see §3); today there is nothing to
  discover.

**Prior art that this seam should generalize (env-driven idiom switching already
exists):** the Table's auto Edit/Done toggle is gated on `env` preferred-input —
`showAutoToggle` (`table.luau:132-138`) reads
`use(spec.env:get("preferredInput")) ~= "KeyboardAndMouse"` so touch/gamepad
users get the ≡-handle edit affordance while mouse users keep direct drag,
purely from the environment, no consumer flag. The rendered toggle is gated by
the same signal via `UI.When` (`table.luau:862-884`). That is exactly the
"control adapts its idiom to the input class by reading the env, with no consumer
wiring" pattern the presenter-discovery seam should extend from a single
affordance to the whole activate/focus/adjust/reorder surface. The pointer-kind
adaptation inside `handleActivate` (touch→additive, mouse→replace/toggle/range,
`table.luau:1063-1071`, fed by adapter `Activated` meta `screen_target.luau:556-578`)
is the same principle already applied per-gesture.

---

## 3. VirtualList touch-pan gap

**Current state.** `virtual_list.luau` renders a bare `UI.Anchor`
(`:147-180`, `overflow="clip"`) whose only motion input is the `scrollTop`
Signal and the programmatic `focusKey`/`pathOf` (`:98-145`, `182-188`). There is
**no `UI.ScrollView`, no `onScrollWheel`, no `setPointerHandlers`/pan drag, no
`panDrag` state** — grep for `ScrollView|onScrollWheel|setPointerHandlers|
onPointer|panDrag` in the file returns nothing. So on a real device a finger
drag over a VirtualList does nothing, and there is not even a mouse-wheel path.

**Contrast with Table (which is fully wired both ways):**
- wheel: Table wraps its body in `UI.ScrollView` with `onScrollWheel` →
  `clampScroll` (`table.luau:821-834`), landing at adapter
  `setScrollHandler`/`MouseWheel` (`screen_target.luau:718-728`,
  `renderer.luau:295-299`). VirtualList: none.
- touch pan: Table's row `onPointerDown` detects `pos.pointerType=="touch"`,
  opens `panDrag` against the body rect, and `onPointerMove` writes
  `scrollOffset` (`table.luau:402-408`, `437-439`), driven by adapter
  `InputBegan`/`InputChanged` Touch capture (`screen_target.luau:638-672`).
  VirtualList: none — no pointer handler is ever attached to a VL node.

**Evidence it is a known, deliberate gap:** ui_todo §3 closing line —
"Remaining open: VirtualList touch-pan wiring"; ADR-0008 rider — "Touch reorder
vs. scroll: ... Before any scrolling reorderable consumer ships: long-press-to-
drag or dedicated drag handles." No gallery example consumes `newVirtualList`
(only `tests/virtualization.spec.luau`, `tests/extension_checker.spec.luau`,
`tests/conformance/controls_registry.luau`), so the gap has never surfaced in a
shipped screen. Closing it means giving VirtualList the same
ScrollView-or-pointer-capture plumbing Table already carries, feeding
`scrollTop` the way Table feeds `scrollOffset`.

---

## 4. Honest per-input-class test coverage

Which input classes are *actually simulated* per behavior (not merely asserted
in prose). Adapter simulation vocabulary: `adapter.tap(path, meta)` = pointer/
touch activate (meta carries `pointer`/`shift`/`toggle`); `pointerDown/Move/Up`
with a `"touch"`/`"mouse"` arg = drag/pan; `scrollWheel` = mouse wheel;
`system.deviceKey(key,...)` = keyboard/gamepad action input (`Down`/`Up`/`Return`
= keyboard, `DPad*`/`ButtonA`/`ButtonL1` = gamepad); direct `tbl.api.*` calls =
**not an input** (bypasses the presenter/adapter, so it does not prove the
device path is reachable).

### Table

| Behavior | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| row-selection | ✅ `tap` @139-165, 853-878 | ✅ `tap{pointer="touch"}` @912-919 | ✅ `deviceKey Down/Return` @167-176, 811-823 | ⚠️ DPad path not driven; A-select proven only via direct `api.handleActivate({source="action"})` @1342 (not through adapter) |
| header-sort | ✅ `tap` @460-468 | ❌ (asserted via mouse tap only) | ✅ negative — @474 asserts it's UNreachable by focus | ❌ none (MISSING behavior) |
| column-resize | ✅ `pointerDown/Move/Up` @931-949, clamp @1010-1020 | ❌ no touch drag test | ✅ `deviceKey Left` @997-1000 | ✅ `deviceKey ButtonL1` @1004-1007 |
| row-reorder | ✅ drag @521-556, group @558-617 | ✅ handle-drag `"touch"` @1209-1224, multi @1188-1207 | ✅ `LeftShift+Down` @741-756 | ⚠️ grab/step proven via direct `api.handleActivate/handleGrabNavigate` @1337-1407 — **not** via `deviceKey`/adapter |
| scroll | ✅ `scrollWheel` @1115-1140 | ✅ `pointerMove "touch"` @1088-1113 | ❌ none (MISSING) | ❌ none (MISSING) |
| focus-navigation | ✅ `tap` focus @801-806 | ❌ (touch focus not simulated) | ✅ `deviceKey Down` @167-176, 811-823 | ✅ `deviceKey DPad*` (navigation_groups @237-242) |
| buildFocusGroups shape | — | — | ✅ structural @1321-1335 | ✅ structural @1321-1335 (env=Gamepad) |
| auto Edit/Done env gate | ✅ mouse hidden @1252-1257 | ✅ `env:set("Touch")` shows toggle @1258-1265 | — | — (env "Gamepad" tested @1323 for groups) |

Gaps: **no touch column-resize**; **gamepad row-selection, grab-reorder, and
A-activate are exercised only by calling `tbl.api.*` directly, never through
`deviceKey`/the adapter** — so the end-to-end gamepad button path (ButtonA →
presenter Activate → control) is asserted for plain focus/nav but *assumed* for
grab/select. header-sort and Table-scroll have no keyboard/gamepad tests because
those cells are MISSING.

### VirtualList (`tests/virtualization.spec.luau`)

| Behavior | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| scroll | ❌ none — driven only by `list.scrollTop:set(...)` @64, 100, 161, 208 (a Signal write, not an input gesture) | ❌ none (the §3 gap) | ❌ none | ❌ none |
| focus/navigation | ❌ none — `focusKey`/`pathOf` called directly @109-138 (api calls, no adapter, no presenter) | ❌ none | ❌ none | ❌ none |
| activate | ❌ none (no activate api exists) | ❌ none | ❌ none | ❌ none |

**Every VirtualList test drives Signals/apis directly; not one input class is
simulated through the adapter or presenter.** The suite proves virtualization
correctness (bounded window, keyed survival, rect-only scroll, neighbor focus,
async cancellation) but proves **zero device reachability** — consistent with
VirtualList having no pointer/touch/keyboard/gamepad wiring to reach.

---

## Appendix — key file:line anchors

- Table apis the consumer must call: `handleActivate` `table.luau:1022`;
  `buildFocusGroups` `:1140`; `handleGrabNavigate` `:1081`; `handleFocusMoved`
  `:1247`; `handleAdjust` `:1217`; `handleReorderNav`/`moveRow` `:1262-1288`.
- Table FA gestures: grip `:690-738`; row drag `:383-556`; wheel `:821-834`;
  touch pan `:402-408`,`:437-439`; edit handle `:637-676`.
- env-driven idiom prior art: `showAutoToggle` `:132-138`; toggle `UI.When`
  `:862-884`; per-pointer activate `:1063-1071`.
- Presenter blank-pipe seam: `onNodeTap`→`opts.onActivate` `presenter.luau:110-119`;
  groups from `opts` `:127-140`,`:416-422`; Adjust gated on `opts.onAdjust`
  `:184-197`; nav intercept `:234`,`:251`; focus-move report `:281-286`.
- Adapter input origin: `Activated` meta `screen_target.luau:556-578`; pointer
  capture `:632-702`; wheel `:718-728`.
- VirtualList: bare Anchor `virtual_list.luau:147-180`; scroll seam
  (`scrollTop`/`focusKey`/`pathOf`) `:98-145`,`:182-188` — no gesture plumbing.
