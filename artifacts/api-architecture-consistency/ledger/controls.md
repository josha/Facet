# Surface ledger — COMPOSITE CONTROLS

Area: `LuauUI.newTable`, `newVirtualList`, `newPopupButton`, `newStepper`,
`newSlider`, `newRating`, `newProgressView`, `newLabel`, `newPicker`,
`newDisclosureGroup`, `newTextInput`, `newChip`, `newAsyncImage`,
`LuauUI.pathShapes`, plus `src/controls/contract.luau` as the pattern reference.

Reference pattern (docs/extending/new-control.md §2–§3): `build(LuauUI, core, spec)
-> { blueprint, dump, dispose, …extras }`; owner-held settable Signals; the control
creates its own scope from `core` and `dispose()` = `scope:dispose()` and nothing
else; the input contribution is attached to the returned root; `dump()` is
deterministic and carries a `schema` string; the spec is validated strictly at
build; four-input reachability is proven by named spec cases cited in
`tests/conformance/controls_registry.luau`.

Baseline surface read: `artifacts/api-architecture-consistency/baseline/public-surface-before.txt`
(v0.7.0) — all 13 `newX` exports plus `pathShapes` are present there; `contract.luau`
is **not** exported (see CTRL-11).

---

## Cross-cutting shape table (evidence for the drift findings below)

| export | first args | returns (verbatim from source) | dump schema | contribution |
|---|---|---|---|---|
| `newTable` | `(LuauUI, core, spec: Spec)` `table.luau:130` | `{ blueprint, api, dump, dispose }` `table.luau:2131-2171` | `luauui-table-dump/1` | yes `table.luau:2139` |
| `newVirtualList` | `(LuauUI, core, spec: any)` `virtual_list.luau:114` | flat: `{ blueprint, focusGroupName, scrollTop, focusedKey, selectedKey, armedKey, dropIndex, autoscroll, pathOf, focusKey, select, toggleGrab, stepAutoscroll, bindNativeScroll, scrollTo, clearSelection, scrollPath, dump, debugWindow, dispose }` `virtual_list.luau:1175-1247` | `luauui-virtual-list-dump/1` | yes `virtual_list.luau:1175` |
| `newPopupButton` | `(LuauUI, core, spec: Spec)` `popup_button.luau:81` | `{ blueprint, api, presentation, dump, dispose }` `popup_button.luau:297-337` | `luauui-popup_button-dump/1` | yes `popup_button.luau:309` |
| `newStepper` | `(LuauUI, core, spec: Spec)` `stepper.luau:58` | `{ blueprint, model, semanticText, dump, dispose }` `stepper.luau:226-252` | `luauui-stepper-dump/1` | yes `stepper.luau:190` |
| `newSlider` | `(LuauUI, core, spec: Spec)` `slider.luau:115` | `{ blueprint, model, semanticText, fillWidth, thumbOffset, onInteractionClassLost, dump, dispose }` `slider.luau:502-551` | `luauui-slider-dump/1` | yes `slider.luau:428` |
| `newRating` | `(LuauUI, core, spec: Spec)` `rating.luau:107` | `{ blueprint, onInteractionClassLost, semanticText, dump, dispose }` `rating.luau:341-378` | `luauui-rating-dump/1` | yes `rating.luau:315` |
| `newProgressView` | `(LuauUI, core, spec: Spec)` `progress_view.luau:44` | `{ blueprint, model, semanticText, dump, dispose }` `progress_view.luau:108-145` | `luauui-progress-dump/1` | none (non-interactive, declared) |
| `newLabel` | `(LuauUI, core, spec: Spec)` `label.luau:29` | `{ blueprint, semanticText, dump, dispose }` `label.luau:83-110` | `luauui-label-dump/1` | none (non-interactive, declared) |
| `newPicker` | `(LuauUI, core, spec: Spec)` `picker.luau:53` | `{ blueprint, presentation, dump, dispose }` `picker.luau:163-190` | `luauui-picker-dump/1` | yes `picker.luau:152` |
| `newDisclosureGroup` | `(LuauUI, core, spec: Spec)` `disclosure_group.luau:33` | `{ blueprint, bindFocus, dump, dispose }` `disclosure_group.luau:191-215` | `luauui-disclosure-dump/1` | yes `disclosure_group.luau:165` |
| `newTextInput` | `(LuauUI, core, spec: Spec)` `text_input.luau:133` | `{ blueprint, api, dump, dispose }` `text_input.luau:596-621` | `luauui-text_input-dump/1` | yes `text_input.luau:600` |
| `newChip` | `(LuauUI, core, spec: any)` `chip.luau:28` | `{ blueprint, dump, dispose }` `chip.luau:83-89` | `luauui-chip-dump/1` | yes `chip.luau:66` |
| `newAsyncImage` | `(LuauUI, core, spec: any)` + **required `spec.scope`/`spec.provider`** `async_image.luau:44-48` | `{ blueprint, state, handle }` — **no dump, no dispose** `async_image.luau:126-130` | — | none (non-interactive, declared) |
| `pathShapes` | module of dot functions | `{ MAX_CONTROL_POINTS, arc, ring, needle }` `path_shapes.luau:22-82` | n/a | n/a |

---

### `LuauUI.newTable` — composite control (`src/controls/table.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, api, dump, dispose }`
  (`table.luau:130`, `:2131-2171`). Spec (`table.luau:68-127`): `id?, columns ({Column}),
  rows (Readable<{T}>), key ((T)->string), cellFor?, rowHeight? (number | (item)->number),
  header?, selection? ("none"|"single"|"multi"), gap?, sortOrder? (owner Signal), height?,
  scrolls?, rowGap?, cellPadding? (number|theme-metric string), reorderable?,
  onReorder? ((keys:{string}, toIndex)->()), dragLabel?, editing? (owner Signal), env?`.
  `Column` (`:48-66`): `id, title?, width, minWidth?, resizable?, alignment?, cell?,
  value?, sortable?`. `api` carries ~18 members (`api.select`, `api.clearSelection`,
  `api.selectedKeys`, `api.grabbedKey`, `api.selectedColumn`, `api.editing`,
  `api.setColumnWidth`, `api.columnWidthOverrides`, `api.moveRow`,
  `api.bindNativeScroll`, `api.scrollPath`, `api.rowKeyForPath`, plus the seven
  contribution handlers).
- **Pattern:** control-build, with the `{ blueprint, api, dump, dispose }` variant
  (shared with `newPopupButton` and `newTextInput`). Owner-held Signal state for
  `sortOrder` and `editing`; the control owns `selectedKeys`, `grabbedKey`, `scrollTop`,
  `widthOverrides` in its own scope. Strict-at-build validation (`:438`, `:444`, `:476`).
- **Callers:** `examples/gallery/examples/02_playlist_table.luau:156`;
  RascalRally `client/LuauUIRacerListScreen.luau:159` (re-exports `blueprint` + `api`
  and calls `tbl.dispose()`). Specs: `tests/table.spec.luau`,
  `tests/table_input.spec.luau`, `tests/paradigm_table.spec.luau`,
  `tests/auto_input.spec.luau`, `tests/interaction_tokens.spec.luau`,
  `tests/compact_label.spec.luau` — all `require("../src/controls/table")` directly,
  not `LuauUI.newTable`.
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:2170`). Row/item state lives in
  `ForEach` item scopes. `spec.rows`, `spec.sortOrder`, `spec.editing` are the caller's
  and are never disposed by the control. `api.bindNativeScroll` returns an unbind the
  consumer must call (`:2044-2052`) — the only manual-teardown obligation in the family.
- **Proof:** registry row `tests/conformance/controls_registry.luau:~93-160`
  (`dumpMarker = "function dump"`); `tests/table.spec.luau:305`
  "row churn + dispose are registry-neutral and dumps deterministic";
  four-input cases as cited in the registry row. api.md §`newTable` (`docs/reference/api.md:1907`).
- **Findings:**
  - `[MAJOR, H] CTRL-04` `onReorder` is one name with two contracts. Table:
    `onReorder(keys: {string}, toIndex)` where `toIndex` is a **0-based** insertion slot
    among the rows NOT being dragged (`table.luau:116-121`). VirtualList:
    `onReorder(key: string, index)` — a single key, and api.md documents it as the
    **1-based** resulting index (`virtual_list.luau:485`, `docs/reference/api.md:2036`).
    A consumer moving a list from one control to the other silently off-by-ones and
    loses multi-row moves. — user cost: data corruption in the owner's array, not a
    build error.
  - `[MAJOR, M] CTRL-05a` `api.bindNativeScroll` is nested under `api` while
    VirtualList publishes it at the top level (`table.luau:2034` vs
    `virtual_list.luau:1193`). The gallery's auto-bind loop probes
    `value.bindNativeScroll` on each member of the example's returned table
    (`examples/gallery/client/init.client.luau:300-302`, `:680-682`), and
    `02_playlist_table.luau:333` returns `table_ = tbl` — so the playlist table's
    CanvasPosition mirror is never bound. `table.luau:255-261` states the reorder drag
    math and keep-visible read that mirror, so both are canvas-wrong once the body is
    scrolled. api.md asserts the auto-bind works and that "newTable exposes the same
    seam for its body scroll" (`docs/reference/api.md:1998-2000`). — user cost: a
    scrolled table drops rows in the wrong slot in the shipped example.
  - `[MAJOR, M] CTRL-08a` Table's own `dump()` is never exercised. Every `.dump()` in
    `tests/table.spec.luau` (`:307`, `:308`) is `handle.root.dump()` — the MOUNT tree
    dump, not the control's. No test in the repo contains the string
    `luauui-table-dump`. The registration gate is satisfied by
    `dumpMarker = "function dump"`, a substring search
    (`tools/lune/check_registration.luau:144`). — user cost: the deterministic-dump
    promise for the largest control is unpinned; a regression ships green.
  - `[MINOR, H]` `column.alignment` is honoured on cells (`table.luau:945-954`) but
    **not** on header titles — the header `Title` Text carries only a left margin
    (`:1116-1126`) and the header cell hardcodes `alignV = "center"` with no `alignH`
    (`:1177-1183`). A `alignment = { h = "trailing" }` numeric column shows a
    left-aligned heading over right-aligned numbers. Partially-honoured property.
  - `[MINOR, M]` The sort mark is `"▲"`/`"▼"` (U+25B2/U+25BC) written inline
    (`table.luau:1163`) — the exact geometric-shape class
    `disclosure_group.luau:82-95` records as having rendered as **tofu** on a live
    screen in Michroma, which is why the caret moved to `themePackage.iconGlyph`.
    Table never took the same fix. — user cost: an invisible sort indicator under a
    display face, headlessly undetectable.
  - `[MINOR, M]` Table's `dump()` (`:2059-2076`) carries only `id`, `columns`,
    `rowCount`, `selection`, `sortOrder`. Live interaction state that a bug report
    actually needs — `selectedKeys`, `grabbedKey`, `editing`, the in-flight drag,
    `scrollTop` — is absent, while VirtualList's dump carries all of its equivalents
    (`virtual_list.luau:1201-1224`). Playbook §2.5 asks for "the state a bug report
    needs".
  - `[MINOR, M]` No selection callback. VirtualList has `onSelect(item, key)`
    (`virtual_list.luau:690-693`); Table's only selection surface is
    `api.selectedKeys` + `api.select` (`:1425`, `:1494`). Sibling asymmetry for the
    same concept.
  - `[NOTE, H]` `spec` is typed but the return is not; `build`'s first parameter is
    `LuauUI: any` and `Column.width` is `any` (`:53`). Unnecessary `any` at a public
    boundary.

### `LuauUI.newVirtualList` — composite control (`src/controls/virtual_list.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: any) -> { blueprint, focusGroupName,
  scrollTop, focusedKey, selectedKey, armedKey, dropIndex, autoscroll, pathOf, focusKey,
  select, toggleGrab, stepAutoscroll, bindNativeScroll, scrollTo, clearSelection,
  scrollPath, dump, debugWindow, dispose }` (`:114`, `:1175-1247`). Spec is documented
  only in the header comment (`:74-95`), never as an exported type: `id?, rows, key,
  rowHeight (number|Readable), viewportHeight (number|Readable), overscan?, cell,
  width?, onActivate?, selection?, onSelect?, reorderable?, onReorder?, reorderMotion?,
  motionClock?, grabOnActivate?, dropSurface?, rowDropTarget?, rowFocusable?,
  autoscroll?, navigation?`.
- **Pattern:** control-build with a **flat** return (the only large control that does
  not nest an `api`). Validation is strict for `rowHeight`, `viewportHeight`, `key`,
  `cell`, `selection`, and `navigation`'s field set (`:123-171`). Contribution attached
  at `:1173`, with `navigateIntercept`/`handleCancel` added conditionally (`:1165-1172`).
- **Callers:** `examples/gallery/scenarios/perf_capture.luau:72`,
  `sponsor_list.luau:256`, `sponsor_drop.luau:355`, `virtual_list_native.luau:22`;
  RascalRally `client/LuauUISponsor/RacerList.luau:749` (uses `selection`, `onSelect`,
  `rowFocusable`, `dropSurface`, `rowDropTarget`, `navigation`, `autoscroll`,
  `grabOnActivate`). Specs: `tests/virtualization.spec.luau`,
  `tests/virtual_list_input.spec.luau`, `tests/collection_list.spec.luau`.
- **Lifecycle:** `dispose()` is **not** just `scope:dispose()` — it unwatches the drag
  registry and tears down every live slide motion first (`:1240-1247`). Item state dies
  with the row's item scope on window exit. `bindNativeScroll` returns an unbind the
  consumer owns.
- **Proof:** registry row (`controls_registry.luau:~161-235`,
  `dumpMarker = "function list.dump"`); eight cited four-input cases;
  `tests/collection_list.spec.luau:678/686/726/735` and
  `virtual_list_input.spec.luau:146/449` read `list.dump()` fields.
  api.md §`newVirtualList` (`docs/reference/api.md:1970`).
- **Findings:**
  - `[MAJOR, H] CTRL-09a` api.md contains a stale claim inside the current section:
    "VirtualList has no reorder, so it contributes no navigate-intercept"
    (`docs/reference/api.md:1987-1989`), directly contradicted by
    `virtual_list.luau:1165-1166` and by the spec table 40 lines further down in the
    same doc section. — user cost: a reader planning focus interop believes the list
    never intercepts Navigate.
  - `[MAJOR, H] CTRL-04` (see `newTable`) — `onReorder` arity and index base differ
    from Table's.
  - `[MINOR, H]` The module header instructs `api.bindNativeScroll(controller)`
    (`virtual_list.luau:33`) and `api.bindNativeScroll` again at `:78`'s neighbours —
    VirtualList has no `api` member at all. A copy-paste of the documented call errors.
  - `[MINOR, M] CTRL-08b` No test proves `list.dump()` determinism (twice → identical);
    the cited registry cases are input cases, and `virtualization.spec.luau:200-205`
    compares `root.dump()` (mount tree), not the control dump.
  - `[MINOR, M]` `spec.rows` is required (`:1226` reads `spec.rows:get()`) but is the
    one required field with no build-time assert, while `key`, `cell`, `rowHeight`,
    `viewportHeight` and `selection` all have one (`:123-153`).
  - `[MINOR, M]` `select(key)` here vs `api.select(rowKey, opts)` on Table
    (`table.luau:1494`) — same verb, different arity, and only Table takes a mode.
  - `[NOTE, H]` `spec: any` with no exported `Spec` type — the only large control
    whose spec is prose-only; `Column`/`Spec` types exist for Table, Picker, Slider,
    Stepper, Rating, ProgressView, Label, DisclosureGroup, PopupButton, TextInput.

### `LuauUI.newPopupButton` — composite control (`src/controls/popup_button.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, api, presentation,
  dump, dispose }` (`:81`, `:297-337`). Spec (`:34-45`): `id?, options ({ id, label }),
  value (Signal<string>), onChange?, presentation? ("automatic"|"menu"|"inline"|"sheet"),
  sizeClass? (string|Readable), interactionClasses? (table|Readable)`.
  `api = { handleActivate, open, close, select, isOpen (Signal), presentation (function) }`
  (`:146-196`).
- **Pattern:** control-build, `{blueprint, api, dump, dispose}` variant. Open/closed is
  the control's own scope-owned signal (`:107`); the selection is owner-held.
  Transient-surface seams (`handleCancel`, `outsideDismiss`, `transientScope`) ride the
  contribution (`:309-328`).
- **Callers:** none in `examples/` and none in RascalRally. Only
  `tests/popup_button.spec.luau`, `tests/paradigm_popup.spec.luau`, and
  `tests/display_controls.spec.luau:544` (which `require`s the module directly).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:335`).
- **Proof:** registry row (`controls_registry.luau:~236-250`); dump determinism
  `tests/popup_button.spec.luau:236`; api.md §`newPopupButton`
  (`docs/reference/api.md:2303`).
- **Findings:**
  - `[MAJOR, H] CTRL-01` `value` is accepted as a **Memo** at build
    (`popup_button.luau:87-90`: `spec.value.kind == "signal" or spec.value.kind == "memo"`),
    and `select()` then calls `spec.value:set(optionId)` (`:138`). A memo's `set`
    is `assert(node.kind == "signal", "cannot set a memo")`
    (`src/core/custom.luau:305-308`). Every sibling rejects exactly this at build and
    says so in a comment: `stepper.luau:63-72`, `slider.luau:119-126`,
    `rating.luau:111-118`, `picker.luau:61-63`, `disclosure_group.luau:41-47`,
    `text_input.luau:136-138`. — user cost: the exact deferred crash the family's
    build-time check exists to prevent, on the first user selection.
  - `[MAJOR, M] CTRL-12` `presentation` is one public word with two types. Popup's
    returned `presentation` is a **function** `() -> string` (`popup_button.luau:330`,
    the local `presentationNow` at `:190`); Picker's returned `presentation` is a
    **Readable memo** (`picker.luau:165`, from `:85`). Sibling controls solving the
    same "which idiom did you pick?" question answer in incompatible shapes.
  - `[MAJOR, M] CTRL-10a` `popup_button.resolvePresentation` is commented "Pure and
    exported so a caller can predict it" (`:300`) but `init.luau:76` exports only
    `.build` — the function is unreachable from `LuauUI`. Same defect as Picker's
    (CTRL-10).
  - `[MINOR, H]` api.md documents the spec as `{ id?, options, value, onChange? }`
    (`docs/reference/api.md:2317-2318`) and the return as `{ blueprint, api, dump,
    dispose }` (`:2303`). `presentation`, `sizeClass`, `interactionClasses` and the
    returned `presentation` field are all undocumented public surface.
  - `[MINOR, M]` `interactionClasses` is Popup's spelling for "the live environment";
    Rating and Table and TextInput take `env` and read
    `env:get("interactionClasses")` themselves (`rating.luau:155`, `table.luau:2088`,
    `text_input.luau:392`). Three spellings, one concept.
  - `[MINOR, M]` Error prefix is `` PopupButton '{id}': `` (`:85`) where the display
    family uses `` LuauUI newX('{id}'): `` (`label.luau:35`, `picker.luau:58`, …),
    VirtualList uses `VirtualList.key is required` (`virtual_list.luau:139`), Table
    uses `` Table '{id}': `` (`table.luau:476`) and AsyncImage uses
    `newAsyncImage: …` (`async_image.luau:46`). Five error vocabularies.
  - `[NOTE, M]` No consumer anywhere in `examples/` or RascalRally — the only assigned
    control with no worked call site outside tests.

### `LuauUI.newStepper` — composite control (`src/controls/stepper.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, model,
  semanticText, dump, dispose }` (`:58`, `:226-252`). Spec (`:46-56`): `id?, label?,
  value (owner Signal<number>), min, max, step?, format?, enabled?, onChange?`.
- **Pattern:** control-build, `{blueprint, model, semanticText, …}` variant shared with
  Slider and ProgressView. Owner-held `value`, rejected at build if not `kind ==
  "signal"` (`:66-72`). Single mutation site `apply` (`:90`). `enabled` read through
  `contract.enabledNow`/`enabledIn` (`:85-87`, `:119`, `:126`) — the reference use of
  the shared policy.
- **Callers:** `examples/gallery/scenarios/adaptive_controls.luau:41`,
  `theme_authoring.luau:259`. No RascalRally caller. Spec:
  `tests/value_controls.spec.luau` (Stepper block from `:141`).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:248-250`); every memo is
  `scope:own(...)` (`:109`, `:114`, `:118`, `:124`).
- **Proof:** registry row (`controls_registry.luau:~430-470`,
  `dumpMarker = "function api.dump"`); `tests/value_controls.spec.luau:295`
  "dump is deterministic", `:301` "build/interact/dispose returns the registry to its
  baseline"; four-input + affordance cases as cited. api.md §`newStepper`
  (`docs/reference/api.md:2354`).
- **Findings:** none against the pattern. Stepper is the closest match to the house
  shape in the family (single mutation site, shared `enabled` policy, both Adjust seams,
  owner-held value rejected-if-not-settable, deterministic dump with proof).
  - `[NOTE, L]` `spec.label` defaults to `""` and always mounts a `Label` Text node
    (`:136`), so a label-less Stepper still pays a measured empty text node — Picker
    and ProgressView instead omit the node when `label == nil`
    (`picker.luau:143-150`, `progress_view.luau:100-102`). Cosmetically consistent,
    structurally not.

### `LuauUI.newSlider` — composite control (`src/controls/slider.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, model,
  semanticText, fillWidth, thumbOffset, onInteractionClassLost, dump, dispose }`
  (`:115`, `:502-551`). Spec (`:68-101`): `id?, label?, value (owner Signal<number>),
  min, max, step?, format?, enabled?, tapToPosition?, onChange?, onCommit?, thumbImage?,
  trackImage?`.
- **Pattern:** control-build, value-family variant. Owner-held value rejected at build
  if not a signal (`:119-126`). Rung-2 image props normalized once at build through the
  same `themePackage.normalizeVariant` the recipe schema uses (`:99-111`, `:133-135`).
  Contribution carries `syncGeometry`, `bindController`, `onStart`/`onContinue`,
  `adjustTargets`, `handleAdjust` (`:428-500`).
- **Callers:** `examples/gallery/scenarios/adaptive_controls.luau:49`,
  `theme_authoring.luau:106` and `:113`. No RascalRally caller. Spec:
  `tests/value_controls.spec.luau` (Slider block from `:363`).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:547-549`); the native detach
  handle is `scope:own(detachDetector)` (`:424`).
- **Proof:** registry row (`controls_registry.luau:~395-429`); dump determinism +
  registry neutrality `tests/value_controls.spec.luau:603`; hot-switch
  `:553` and `:567`. api.md §`newSlider` (`docs/reference/api.md:2447`).
- **Findings:**
  - `[MAJOR, M] CTRL-13` `onInteractionClassLost` is a **caller-driven** hot-switch
    entry point (`slider.luau:510`; api.md `:2504-2506` "Drive it from your live
    interaction-class watcher") while Table, TextInput and Rating's own class-loss
    handling is **self-driven** off `env:get("interactionClasses")`
    (`table.luau:2087-2131`, `text_input.luau:392`, `rating.luau:155`). Two mechanisms
    for one paradigm requirement, and the caller-driven one is silently a no-op for a
    consumer who never wires it — nothing in the framework calls it (the only two
    callers in the repo are `tests/value_controls.spec.luau:560` and
    `tests/rating.spec.luau:257`). — user cost: shipped sliders that keep a stale
    in-flight drag on a real class flip, with a green suite.
  - `[MINOR, M]` `onChange` + `onCommit` here vs `onChange` alone on Stepper, Picker
    and Rating, and `onCommit(text, reason)` on TextInput (a 2-arg version of the same
    name, `text_input.luau:47`). Same word, three signatures across the area.
  - `[MINOR, L]` `fillWidth` / `thumbOffset` are returned as raw Readables
    (`:506-507`) with no api.md explanation beyond the signature line
    (`docs/reference/api.md:2449`) — the only two return members in the area with no
    documented purpose.
  - `[NOTE, M]` `thumbImage`/`trackImage` are typed `(string | { [string]: any })?`
    (`:96-97`) — `any` at a public boundary where `themePackage.normalizeVariant`
    already knows the state key set.

### `LuauUI.newRating` — composite control (`src/controls/rating.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint,
  onInteractionClassLost, semanticText, dump, dispose }` (`:107`, `:341-378`). Spec
  (`:82-105`): `id?, value (owner Signal<number>), count?, allowZero?, enabled?,
  readOnly?, glyphs?, starSize? ("small"|"medium"|"large"), env?, onChange?`.
  Module also carries `rating.FILLED` / `rating.EMPTY` (`:79-80`).
- **Pattern:** control-build. Owner-held value rejected at build if not a signal
  (`:111-118`). ONE Grip over `count` glyph Texts, one focus stop, focus-gated Adjust.
- **Callers:** `examples/gallery/examples/02_playlist_table.luau:138` (one control per
  track row). No RascalRally caller. Spec: `tests/rating.spec.luau`.
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:374-376`).
- **Proof:** registry row (`controls_registry.luau:~471-505`,
  `dumpMarker = "function api.dump"`); four-input + affordance + hotSwitch cases all
  exist. api.md §`newRating` (`docs/reference/api.md:2510`).
- **Findings:**
  - `[MAJOR, H] CTRL-08c` Rating's `dump()` and `dispose()` are **never called by any
    test**. `grep '\.dump()\|dispose()\|counters()' tests/rating.spec.luau` returns
    nothing; the registration gate passes on the substring `"function api.dump"`
    (`tools/lune/check_registration.luau:144`). So the deterministic-dump promise, the
    dispose contract, and registry neutrality are all unproven for this control while
    every sibling in the value family has an explicit case
    (`value_controls.spec.luau:295`, `:301`, `:603`). — user cost: a dump or disposal
    regression here ships green.
  - `[MAJOR, M] CTRL-13` see `newSlider` — `onInteractionClassLost` caller-driven,
    while the control ALSO reads `env:get("interactionClasses")` itself for spacing
    (`:155`). The control has the env in hand and still requires the consumer to tell
    it a class went away.
  - `[MINOR, M]` `spec.env` is optional here (`:100-103`) but effectively required by
    Table and TextInput (`table.luau:2087` guards, `text_input.luau:392` does too but
    `:323` reads `spec.env:get(...)` — see TextInput findings). Three optionality
    stories for one injected dependency.
  - `[MINOR, L]` `rating.FILLED` / `rating.EMPTY` are module fields reachable only via
    an internal `require` — a consumer wanting to match the framework's default glyphs
    in its own art must retype them.
  - `[NOTE, L]` `semanticText` is assigned as a memo AFTER `api.blueprint`
    (`:356-358`) and then read inside `dump()` (`:371`), so `dump()` forces a memo
    evaluation. Harmless but the only dump in the area that pulls a memo.

### `LuauUI.newProgressView` — composite control (`src/controls/progress_view.luau`)

> **ADDENDUM 2026-08-13 (parity round 2 §3.1) — this section is the Step 7 audit
> snapshot and its `:line` citations are that snapshot's, not today's.** Since it
> was written, `value` became OPTIONAL (`value = nil` selects an indeterminate
> view), `presentation` (`"bar" | "spinner"`) and `motionClock` joined the spec,
> and `dump()` gained `indeterminate` / `presentation` (plus `phase` / `animating`
> on the indeterminate path). The determinate path's shape, geometry and every
> pre-existing dump key are unchanged and pinned on both sides — framework
> (`tests/display_controls.spec.luau`) and consumer
> (`games/RascalRally/code/tests/luauui_sponsor_results.spec.luau`, "the rally bar
> is still the DETERMINATE ProgressView"). It still attaches **no** input
> contribution, so "none (non-interactive, declared)" in the shape table above
> still holds.

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, model,
  semanticText, dump, dispose }` (`:44`, `:108-145`). Spec (`:33-42`): `id?, label?,
  value (number | Readable<number>), min? = 0, max? = 1, format?, showValue?,
  height? (number)`.
- **Pattern:** control-build, value-family variant. Non-interactive: no contribution,
  and the registry declares `inputProofs = false` / `affordanceProofs = false`
  (`controls_registry.luau:~315-328`). Paint declared through `chrome_slots.attachHint`
  slots `barTrack` / `barFill` (`:73-97`).
- **Callers:** `examples/gallery/scenarios/adaptive_controls.luau:68`,
  `perf_capture.luau:70`, `theme_authoring.luau:258`; RascalRally
  `client/LuauUISponsor/ResultsScreen.luau:1260` (passes `id`, `value`, `height`).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:141-143`); three memos are
  `scope:own(...)` (`:63`, `:66`, `:69`).
- **Proof:** registry row; `tests/display_controls.spec.luau:97` "carries semantic
  value-in-range text and a deterministic dump", plus "paint is style-owned through the
  BAR FAMILY, never a borrowed surface" and "is registry-neutral after dispose".
  api.md §`newProgressView` (`docs/reference/api.md:2383`).
- **Findings:**
  - `[MAJOR, H] CTRL-09b` api.md states "the track carries the `control` surface role
    and the fill `accent`, so retheming those rules restyles every progress bar"
    (`docs/reference/api.md:2390-2391`). The source removed exactly that and says why
    (`progress_view.luau:16-21`: an ornate package stretched a BUTTON plate across the
    track); paint is now the `barTrack`/`barFill` chrome slots (`:73-97`), and there is
    a spec case named for it. A theme author following api.md restyles the wrong
    rules. — user cost: a whole theming attempt that silently does nothing.
  - `[MINOR, H]` `Spec.height` is typed `number?` (`:41`) but is used as
    `{ type = "fixed", px = spec.height or TRACK_HEIGHT }` (`:77`) where
    `TRACK_HEIGHT` is a theme-metric **string** — so a metric name is accepted and
    works while the exported type refuses it. Label's equivalent fields are typed
    `(number | string)?` (`label.luau:22-24`). Type/behaviour disagreement.
  - `[MINOR, M]` `spec.value` is duck-typed inline
    (`type(spec.value) == "table" and (spec.value :: any).get ~= nil`, `:53`) — a
    fourth spelling of "is this readable?" beside `LuauUI.UI.isReadable`
    (`async_image.luau:82`), `text_input.luau`'s `kind`-based `isReadable` (`:103-105`)
    and Popup's `readFact` (`:182-187`). One concept, four private implementations, one
    of which (`UI.isReadable`) is already public.
  - `[NOTE, L]` `semanticText` here is a Readable memo (`:124`) — see CTRL-06 on Label.

### `LuauUI.newLabel` — composite control (`src/controls/label.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, semanticText,
  dump, dispose }` (`:29`, `:83-110`). Spec (`:16-25`): `id?, title (required),
  icon?, presentation? ("titleAndIcon"|"titleOnly"|"iconOnly"), iconSize?, textSize?,
  gap?` — the size fields typed `(number | string)?`.
- **Pattern:** control-build. Non-interactive (registry `inputProofs = false`). Strict
  validation of `title` and `presentation` at build (`:33-48`), with `iconOnly`
  degrading to `titleOnly` when there is no icon (`:51-54`).
- **Callers:** `examples/gallery/scenarios/adaptive_controls.luau:74`. No RascalRally
  caller. Spec: `tests/display_controls.spec.luau` "B-DSP1: Label keeps a semantic text
  fallback" (6 cases).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:106-108`) — but the scope owns
  **nothing**: the control creates no signals, memos or observers. The scope exists
  only to satisfy the shape.
- **Proof:** registry row (`controls_registry.luau:~329-343`); api.md §`newLabel`
  (`docs/reference/api.md:2396`).
- **Findings:**
  - `[MAJOR, H] CTRL-06` `semanticText` is a **plain string** here (`:91`,
    `api.semanticText = spec.title`) and a **Readable** on ProgressView (`:124`),
    Stepper (`:229`), Slider (`:504`) and Rating (`:356`). Generic consumer code doing
    `control.semanticText:get()` — the correct call for four of five controls — errors
    on Label; `tostring(control.semanticText)` is wrong for the other four. api.md
    lists `semanticText` in all five signatures with no type note
    (`docs/reference/api.md:2354`, `:2383`, `:2396`, `:2449`, `:2512`). — user cost: an
    accessibility/readout layer cannot be written once for the family.
  - `[MINOR, M] CTRL-08d` Label's `dump()` determinism and `dispose()` registry
    neutrality are unproven: the Label block reads `l.dump().effectivePresentation` and
    `.degradedToTitle` for content only (`tests/display_controls.spec.luau`, the two
    lines inside the `B-DSP1: Label` describe), and never calls `dispose()` or
    `core:counters()` — unlike Picker and DisclosureGroup, which both have
    "dump is deterministic and dispose is registry-neutral" cases in the same file
    (`:318`, `:472`).
  - `[MINOR, L]` The control opens a scope it never uses (`:32`). Harmless, but it
    means `dispose()` is a ceremonial no-op and a reader cannot tell that from the
    signature — the "who owns what" question the lifecycle rule exists to answer.

### `LuauUI.newPicker` — composite control (`src/controls/picker.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, presentation
  (Readable<string>), dump, dispose }` (`:53`, `:163-190`). Spec (`:27-36`): `id?,
  label?, options ({ value, label }), selected (owner Signal), presentation?
  ("automatic"|"segmented"|"inline"), sizeClass? (string|Readable), enabled?,
  onChange?`. Module also exposes `picker.resolvePresentation` (`:41`).
- **Pattern:** control-build. Strict validation of `options`, `selected` (must be
  `kind == "signal"`) and `presentation` at build (`:57-67`). `enabled` through
  `contract.enabledNow` (`:93-95`). Contribution with `handleActivate` only (`:152`).
- **Callers:** `examples/gallery/scenarios/adaptive_controls.luau:57`. No RascalRally
  caller. Spec: `tests/display_controls.spec.luau` "B-DSP2: Picker presentation adapts
  from space, not device names" (10 cases incl. `:318` dump determinism +
  dispose neutrality).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:186-188`); the presentation memo,
  axis memo and one per-option `selected` memo are all `scope:own(...)`
  (`:85`, `:120`, `:131`).
- **Proof:** registry row (`controls_registry.luau:~344-374`); api.md §`newPicker`
  (`docs/reference/api.md:2408`).
- **Findings:**
  - `[MAJOR, H] CTRL-10` api.md says "The rule is exported as
    `picker.resolvePresentation(optionCount, sizeClass, longestLabel)` so it is
    predictable" (`docs/reference/api.md:2417-2419`) and the source repeats the claim
    (`picker.luau:40` "pure and exported so a caller can predict it"). `init.luau:88`
    exports only `require("@self/controls/picker").build` — the function is reachable
    ONLY by an internal `require("../src/controls/picker")`, which
    `tools/lune/check_boundary` forbids consumers from doing. Same defect for
    `popup_button.resolvePresentation` (CTRL-10a). — user cost: a documented
    predictability guarantee that a consumer cannot actually call.
  - `[MAJOR, M] CTRL-12` `presentation` is a Readable here, a function on PopupButton
    (see that entry).
  - `[MINOR, M]` A disabled Picker swallows Activate: `handleActivate` returns `true`
    whenever the leaf is a known option (`:153-160`) even though `choose` refused the
    change because `isEnabled()` was false (`:98`). DisclosureGroup returns `toggle()`'s
    own `false` in the same situation (`disclosure_group.luau:169`), so the presenter
    can fall through. Same seam, opposite answer.
  - `[MINOR, L]` `semanticText` appears only inside `dump()` here (`:182`) and inside
    DisclosureGroup's dump (`disclosure_group.luau:207`), while the value family
    publishes it as a return member. One concept, two placements.
  - `[NOTE, M]` `Option.value: any` and `selected: any` (`:25`, `:31`) — `any` at a
    public boundary where the intent is "any comparable identity"; a generic would
    tie `Option.value`, `selected` and `onChange`'s parameter together.

### `LuauUI.newDisclosureGroup` — composite control (`src/controls/disclosure_group.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, bindFocus, dump,
  dispose }` (`:33`, `:191-215`). Spec (`:24-31`): `id?, label (required), expanded
  (owner Signal<boolean>), content (() -> Blueprint), enabled?, onToggle?`.
- **Pattern:** control-build. Strict validation of `label`, `expanded` (must be
  `kind == "signal"`) and `content` at build (`:37-50`). `enabled` through
  `contract.enabledNow` (`:56-58`). Content mounts through `UI.When` (`:161`). Caret
  glyphs requested by semantic name through `themePackage.iconGlyph` (`:112-118`).
- **Callers:** `examples/gallery/scenarios/adaptive_controls.luau:75`. No RascalRally
  caller. Spec: `tests/display_controls.spec.luau` "B-DSP2: DisclosureGroup updates
  focus correctly" (8 cases incl. `:472` dump determinism + dispose neutrality).
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:211-213`); the `collapsed` memo is
  `scope:own(...)` (`:114`). `expanded` is the caller's.
- **Proof:** registry row (`controls_registry.luau:~375-394`); api.md
  §`newDisclosureGroup` (`docs/reference/api.md:2428`).
- **Findings:**
  - `[MINOR, H] CTRL-14` Two public paths set the same field. `api.bindFocus(graph)`
    (`:196-198`) and the contribution's `bindController` (`:184-188`) both assign
    `focusGraph`, and api.md tells the reader to do either ("Call `bindFocus(...)` (or
    let the control pick the focus graph up from the controller)",
    `docs/reference/api.md:2442-2444`). `bindFocus` is the only member of its kind in
    the area — no other control publishes a manual bind for something the contribution
    already carries. — user cost: an author cannot tell which is the supported path,
    and dead consumer wiring survives review.
  - `[MINOR, M]` `headerPath` is discovered in two places with different mechanisms —
    string-suffix match inside `handleActivate` (`:167-168`) and a child scan inside
    `syncGeometry` (`:173-181`) — so the focus-restore-on-collapse feature is silently
    inert if neither has fired yet (`:68` guards on `headerPath ~= nil`). The cited
    proof case ("collapsing with focus INSIDE the content moves focus back to the
    header first") exercises the activate path only.
  - `[NOTE, L]` `Spec.expanded`, `Spec.enabled`, `Spec.content` are all `any` /
    loosely typed (`:26-29`) at a public boundary.

### `LuauUI.newTextInput` — composite control (`src/controls/text_input.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: Spec) -> { blueprint, api, dump,
  dispose }` (`:133`, `:596-621`). Spec (`:43-79`): `id?, value (owner Signal<string>),
  onChange?, onCommit? ((text, "enter"|"focusLost") -> ()), placeholder?,
  **disabled?**, keyboardType? ("default"|"numeric"|"email"|"phone"), submitLabel?,
  clearButton?, clearButtonMode?, maxLength?, validate?, env?, actionSystem?`.
  `api = { editing, keepVisibleOffset, bindActionSystem, focusGroups, handleActivate,
  syncGeometry }` (`:439-489`).
- **Pattern:** control-build, `{blueprint, api, dump, dispose}` variant. Owner-held
  value rejected at build if not settable (`:136-138`). `clearButtonMode` validated
  against a closed set at build (`:189-196`). Contribution carries `focusGroups`,
  `handleActivate`, `syncGeometry`, `keepVisibleOffset`, `bindActionSystem`
  (`:600-606`).
- **Callers:** `examples/gallery/examples/01_temperature_converter.luau:98`,
  `02_playlist_table.luau:107`, `scenarios/native_style.luau:27`,
  `scenarios/theme_authoring.luau:123` and `:133`. No RascalRally caller. Specs:
  `tests/text_input.spec.luau`, `tests/paradigm_textinput.spec.luau`,
  `tests/auto_input.spec.luau`.
- **Lifecycle:** `dispose()` is **not** just `scope:dispose()` — it calls
  `endEditing()` first so a mid-occlusion disposal cannot leave the screen root frozen
  shifted up, then sets `disposed = true`, then disposes the scope (`:610-619`). The
  deviation is deliberate and commented (ARCH-TI-2).
- **Proof:** registry row (`controls_registry.luau:~252-297`); dump determinism
  `tests/text_input.spec.luau:642`; hot-switch cases cited. api.md §`newTextInput`
  (`docs/reference/api.md:2594`).
- **Findings:**
  - `[MAJOR, H] CTRL-02` `disabled` is TextInput's spelling of the one concept the
    whole family calls `enabled`, at inverted polarity — Picker, DisclosureGroup,
    Stepper, Slider and Rating all take `enabled` (`picker.luau:34`,
    `disclosure_group.luau:29`, `stepper.luau:54`, `slider.luau:76`, `rating.luau:93`).
    `contract.luau:129-131` states outright: "Every composite control takes the same
    optional `spec.enabled`, and the reading is a policy, not arithmetic" — the claim
    is false for TextInput (and for Chip, Table, VirtualList, Label, ProgressView and
    AsyncImage, which take neither). TextInput additionally reimplements the policy in
    its own memo (`:172-183`) instead of using `contract.enabledNow`/`enabledIn`
    (`contract.luau:142-160`), which is the sixth private copy the ledger comment says
    was consolidated. — user cost: one word means two things at opposite polarity, and
    the file that decided the rule contradicts the shipped code.
  - `[MINOR, H]` `submitLabel` is accepted, validated and carried into `dump()`
    (`:56-61`, `:592`) but is **never applied** to anything — a documented
    engine-absent exception in the source, and it is absent entirely from api.md's
    spec list (`docs/reference/api.md:2609-2610`). An accepted-but-ignored property
    whose only public trace is a dump key.
  - `[MINOR, H]` api.md documents `keyboardType: "default" | "numeric"?`
    (`docs/reference/api.md:2624`) where the source accepts
    `"default" | "numeric" | "email" | "phone"` (`text_input.luau:52`). Two of four
    valid values are undiscoverable.
  - `[MINOR, M]` api.md documents `dump()` as
    `{ schema, id, value, editing, disabled, placeholderVisible, clearVisible,
    occlusionOffset }` (`docs/reference/api.md:2678-2680`); the source also emits
    `clearButtonMode`, `keyboardType` and `submitLabel` (`:586-593`).
  - `[MINOR, M]` `clearButton: boolean?` and `clearButtonMode` are two public words for
    one concept (`:63`, `:74`) — the source calls `clearButton` "sugar for
    clearButtonMode = 'always'" (`:63`) and collapses them at `:188`. Sugar is
    defensible; carrying both in the exported type and in api.md's spec table is the
    duplicate-vocabulary class.
  - `[MINOR, M]` `spec.env` is documented optional (`:78`, and api.md
    `:2669-2670`) and is guarded at `:392`, but is dereferenced unguarded at `:323`
    (`spec.env:get("interactionClasses"):get()`). Whether that path is reachable
    without `env` I did not prove; flagging as an optionality inconsistency to check.
  - `[NOTE, M]` `api.bindActionSystem` is wired into the contribution (`:605`) but is
    not in api.md's documented `api` surface (`:2673-2675`).

### `LuauUI.newChip` — composite control (`src/controls/chip.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: any) -> { blueprint, dump, dispose }`
  (`:28`, `:83-89`). Spec is undeclared (no exported type); read fields are `id?`
  (default `"Chip"`), `selected` (owner Signal<boolean>, required in practice),
  `label?` (default `""`), `onToggle?` (`:30-42`).
- **Pattern:** control-build, the **minimal** `{blueprint, dump, dispose}` shape — the
  cleanest example of the documented house pattern in the area. Contribution attached
  to the root with `handleActivate` only (`:66-71`). Deterministic dump with schema
  (`:74-81`).
- **Callers:** none in `examples/` (the "Chip" hits there are a `surface = "chip"` Box
  and unrelated node ids) and none in RascalRally. Specs: `tests/chip.spec.luau`,
  `tests/display_controls.spec.luau`, `tests/theme_roles.spec.luau`.
- **Lifecycle:** `dispose()` = `scope:dispose()` (`:86-88`); the scope owns nothing
  (the control creates no signals or memos), like Label.
- **Proof:** registry row (`controls_registry.luau:~506-548`,
  `dumpMarker = "function dump"`); four-input + four affordance cases +
  `hotSwitch = false`; `tests/chip.spec.luau:219` "dump() is deterministic and reflects
  the live state", `:237-252` registry neutrality. api.md §`newChip`
  (`docs/reference/api.md:2722`) — the most complete entry in the area.
- **Findings:**
  - `[MAJOR, H] CTRL-03` Chip performs **zero** spec validation. `spec.selected` is
    required (`:32`, then `selected:get()` at `:38`) but nothing checks it is present
    or settable, so `nil` errors at first activation and a read-only Memo errors with
    "cannot set a memo" (`src/core/custom.luau:305`) — precisely what
    `stepper.luau:63-72`, `slider.luau:119-126`, `rating.luau:111-118`,
    `picker.luau:61-63`, `disclosure_group.luau:41-47` and `text_input.luau:136-138`
    each reject at build with a message naming the control and the reason. The
    "authoring is strict / fail at BUILD not first render" rule
    (docs/extending/new-control.md §2, ADR-0010) is unenforced here. — user cost: a
    typo'd or memo'd `selected` surfaces as an unattributed crash on a user tap
    instead of a named build error.
  - `[MINOR, M]` Chip has no `enabled`, so it cannot be disabled at all — its inner
    Button never receives one (`:49-57`). Every other interactive composite in the area
    except Table/VirtualList gates activation on `enabled`, and api.md's Chip spec
    table lists no such field (`docs/reference/api.md:2733-2738`), so this is a
    consistent-but-absent capability rather than a lie. Flagging as a family gap.
  - `[NOTE, H]` `spec: any` with no exported `Spec` type (`:28`), unlike its display-
    family siblings.
  - `[NOTE, M]` No consumer outside tests, so the "no `present()` opts needed" promise
    in api.md is proven only headlessly.

### `LuauUI.newAsyncImage` — composite control (`src/controls/async_image.luau`)

- **Shipped shape:** `build(LuauUI, core, spec: any) -> { blueprint, state, handle }`
  (`:44`, `:126-130`). Spec (`:11-19`, asserted at `:46-48`): `id (required, string),
  scope (required, a Scope the CALLER owns), provider (required), key (required,
  non-empty string), width?, height?, failureLabel?, retry?, dimmed? (Bound<boolean>)`.
- **Pattern:** **unique** — it is the only control in the area that (a) takes a `scope`
  in its spec instead of creating one from `core`, (b) returns no `dump()`, and (c)
  returns no `dispose()`. Its resources (the provider handle and four memos) are
  `spec.scope:own(...)` (`:57`, `:64`, `:67`, `:76`, `:83`), so the caller's scope
  disposal is the teardown.
- **Callers:** `examples/gallery/scenarios/async_images.luau:21`, `:27`, `:33`;
  `scenarios/sponsor_avatars.luau:132`. No RascalRally caller. Specs:
  `tests/async_image.spec.luau` (4 cases), `tests/async_completeness.spec.luau:25`.
- **Lifecycle:** owned entirely by the caller's `spec.scope`; releasing it makes late
  completions stale but does not cancel an in-flight engine fetch (documented,
  `docs/reference/api.md:1218-1223`).
- **Proof:** registry row (`controls_registry.luau:~566-582`,
  `dumpMarker = "async_image"`); api.md §`newAsyncImage` — filed under **Blueprints**
  (`docs/reference/api.md:1197`), not under "Composite controls".
- **Findings:**
  - `[MAJOR, M] CTRL-07` The registration gate's dump check is satisfied by a marker
    that proves nothing: `dumpMarker = "async_image"` is the module's own local
    variable name (`async_image.luau:37`), and the checker is a plain
    `string.find(source, entry.dumpMarker, 1, true)`
    (`tools/lune/check_registration.luau:144`). So the one gate that enforces
    "§10.2 deterministic dump form" passes for a control with no dump at all. The
    same weak-marker shape appears on PathShapes (`"path_shapes"`) and ValueModel
    (`"function value_model.new"`), which legitimately have no dump — meaning the gate
    cannot distinguish "exempt" from "missing". — user cost: the registration checker
    reads as proof and is not.
  - `[MAJOR, M] CTRL-15` Constructor-shape drift: `spec.scope` is required
    (`:47`) and `core` is used only to build memos into that foreign scope
    (`:64`, `:67`, `:76`, `:83`). Every other composite derives its scope from `core`
    (`core:scope("<name>-" .. id)`). A consumer moving between controls has to know
    that this one alone inverts scope ownership, and there is no `dispose()` to hint
    at it. — user cost: an author who copies the sibling teardown idiom
    (`control.dispose()`) gets a nil-call.
  - `[MINOR, H]` No `dump()`. It is the only composite control row in the registry
    with no diagnostic summary, so a failing async image cannot be reported the way
    every other control can. api.md documents the return honestly
    (`docs/reference/api.md:1197-1199`), so this is a family gap, not a lie.
  - `[MINOR, M]` `spec.id` is REQUIRED here (`:46`) while every sibling defaults it
    (`"Chip"`, `"Label"`, `"Picker"`, `"Slider"`, …). Inconsistent required-set.
  - `[MINOR, L]` Documented under "Blueprints" in api.md (`:1197`) alongside
    `pathShapes` (`:1225`), while `newPopupButton` … `newChip` (`:2303`–`:2722`) sit
    under "Styling" and only `newTable`/`newVirtualList` are under "Composite
    controls" (`:1905`). Three doc homes for one family — discovery cost.
  - `[NOTE, H]` `spec: any`, and the returned `handle` is the raw provider handle with
    no declared type.

### `LuauUI.pathShapes` — stateless module (`src/controls/path_shapes.luau`)

- **Shipped shape:** `{ MAX_CONTROL_POINTS = 100, arc(startDeg, sweepDeg, { segments?,
  radius? }?) -> {PathPoint}, ring({ radius? }?) -> {PathPoint}, needle(angleDeg,
  { innerRadius?, radius? }?) -> {PathPoint} }` (`:22-82`), with
  `export type PathPoint = { x, y, inX, inY, outX, outY }` (`:20`).
- **Pattern:** "dot functions on stateless module" — correctly, not the control-build
  pattern. It is a control-adjacent pure helper, and the registry says so explicitly
  (`controls_registry.luau:~549-565`: "NOT a control"). Fully typed, no `any`.
- **Callers:** `examples/gallery/scenarios/path_ring.luau:13`,
  `scenarios/sponsor_billboard.luau:28`; RascalRally
  `client/LuauUISponsor/StoryFlow.luau:1629` (`pathShapes.ring({ radius = radius })`),
  referenced in `Roster.luau:45`, `StoryTokens.luau:178`, `ChipRow.luau:15-17`.
  Spec: `tests/path.spec.luau`; also required by `tests/controls_conformance.spec.luau:18`.
- **Lifecycle:** none — pure functions, no state, nothing to dispose.
- **Proof:** registry row with `inputProofs = false` / `affordanceProofs = false`;
  `tests/path.spec.luau`; api.md §`pathShapes` (`docs/reference/api.md:1225`).
- **Findings:**
  - `[NOTE, M]` `arc`'s `segments` assert (`:35`) enforces the 100-point limit, but
    `ring` hardcodes `segments = 8` (`:68`) while the header comment says "4 exact
    quarter segments, 5 points" (`:66`) — the comment and the code disagree on the
    segment count. Cosmetic (the code is the safer of the two), but it is a stated
    invariant that is wrong.
  - `[NOTE, L]` `MAX_CONTROL_POINTS` is public and documented as an engine limit
    (api.md `:1232`), but `needle` and `ring` never assert against it; only `arc` does.
    A caller passing a huge `segments` to `arc` is caught, nothing else can overflow
    today.
  - Otherwise: follows the stateless-module pattern, no deviation.

### `src/controls/contract.luau` — pattern-reference module (NOT exported)

- **Shipped shape:** `{ ControlContract type, enabledNow(enabled) -> boolean,
  enabledIn(use, enabled) -> boolean, forClass(class) -> ControlContract?,
  all() -> { [string]: ControlContract } }` (`:17-168`). The `CONTROLS` table
  (`:24-126`) declares focus role, semantic actions, `minHitSize` and an accessibility
  summary for every **leaf** primitive.
- **Pattern:** stateless dot-function module + a frozen-ish declaration table. It is the
  single owner of the `enabled` reading policy (`:128-160`), added by the Step 5.5
  cleanup ledger (C-01) precisely to kill five private copies.
- **Callers:** `picker.luau:20`, `disclosure_group.luau:17`, `stepper.luau:30`,
  `slider.luau:34`, `rating.luau:49`; `tests/authoring.spec.luau:20`,
  `tests/controls_conformance.spec.luau:15`; `tools/lune/check_registration`.
- **Lifecycle:** module-level, no state.
- **Proof:** `tests/controls_conformance.spec.luau:117-140`
  (`{class}: contract + mount/dispose neutrality + deterministic dump`) iterates
  `contract.all()` — leaf primitives only; composites are not covered by that kit.
- **Findings:**
  - `[MAJOR, M] CTRL-11` The house pattern is not reachable from outside the library.
    `LuauUI.contribution` is public precisely so an out-of-repo composite can attach an
    input bundle (`init.luau:64-70`, and the playbook says so at
    docs/extending/new-control.md §3), but four other things the shipped composites all
    rely on are **not** exported: `contract.enabledNow` / `enabledIn`
    (`contract.luau:142-160`), `chrome_slots.attachHint` (used by
    `progress_view.luau:73`, `slider.luau:309`, `stepper.luau:154`,
    `disclosure_group.luau:118`, `table.luau`), `themePackage.iconGlyph`
    (`stepper.luau:41-42`, `disclosure_group.luau:112-113`) and
    `themePackage.normalizeVariant` (`slider.luau:107`). I confirmed none appears in
    `src/init.luau`. So an external control cannot read `enabled` the house way, cannot
    declare a paint slot, and cannot request a semantic icon — the exact three things
    the playbook's rules demand of it. — user cost: a third-party control is
    structurally unable to follow the documented playbook.
  - `[MINOR, H] CTRL-02` (see `newTextInput`) — `:129-131`'s claim "Every composite
    control takes the same optional `spec.enabled`" is false: TextInput uses
    `disabled` at inverted polarity, and Chip, Table, VirtualList, Label, ProgressView
    and AsyncImage take neither. The file that owns the decision misstates its own
    coverage.
  - `[MINOR, M]` The `CONTROLS` table registers only **leaf** classes; no composite
    (Table, Slider, Rating, …) has a row, so no composite declares a `minHitSize`,
    focus role or accessibility summary at this seam even though several are
    focusable-in-aggregate (Rating is one Grip, Slider is one Grip). The registry in
    `tests/conformance/` carries composites; the contract module carries leaves. Two
    registries, one concept — worth a naming/ownership ruling.
  - `[NOTE, H]` `enabledNow(enabled: any)` / `enabledIn(use: (any) -> any, enabled:
    any)` — `any` on both parameters of the family's most load-bearing shared function.

---

## Cross-cutting findings (recorded once; each is also cited on the affected items)

- `[MAJOR, H] CTRL-05` **Return-shape drift among siblings — five distinct shapes for
  one pattern.** `{blueprint, dump, dispose}` (Chip); `{blueprint, api, dump, dispose}`
  (Table, PopupButton, TextInput); `{blueprint, model, semanticText, dump, dispose}`
  (Stepper, Slider, ProgressView) with Slider adding four more members;
  `{blueprint, <one extra>, dump, dispose}` (Label `semanticText` as a string, Picker
  `presentation` as a Readable, DisclosureGroup `bindFocus` as a function, Rating
  `onInteractionClassLost`); flat-everything (VirtualList, 20 members, no `api`);
  and `{blueprint, state, handle}` with no dump and no dispose (AsyncImage). There IS a
  pattern under the noise — `{ blueprint, …extras, dump, dispose }` — but "is the extra
  surface nested under `api` or flat?" has no rule, and the answer is load-bearing:
  the gallery's `bindNativeScroll` auto-bind (CTRL-05a) works for VirtualList and
  silently misses Table. — user cost: no consumer can write generic control-handling
  code, and the shipped example table loses its scroll mirror.
- `[MINOR, H] CTRL-16` **`dump().schema` token naming is inconsistent and unasserted.**
  Kebab (`luauui-virtual-list-dump/1`), snake (`luauui-popup_button-dump/1`,
  `luauui-text_input-dump/1`), and abbreviated (`luauui-progress-dump/1` for
  ProgressView, `luauui-disclosure-dump/1` for DisclosureGroup). No test in `tests/`
  asserts any control dump's `schema` value — the only `schema` assertions are
  composition/layout/perf (`tests/composition.spec.luau:622`,
  `tests/layout.spec.luau:539`, `tests/perf_*.spec.luau`). A schema string is a
  versioning contract with nothing pinning it.
- `[MINOR, H] CTRL-17` **Specs test the module, not the export.** Every control spec
  does `require("../src/controls/<name>")` and calls `.build` directly
  (`tests/table.spec.luau:12`, `chip.spec.luau:19`, `virtualization.spec.luau:18`, …).
  Nothing asserts `LuauUI.newX == <module>.build`; the registration checker only does
  `string.find(initSource, entry.export)` (`tools/lune/check_registration.luau:149`), a
  substring search that a comment would satisfy. The public export names are proven
  only by the surface-dump baseline artifact.
- `[MINOR, M] CTRL-18` **Four private "is this readable?" implementations** across the
  area — `progress_view.luau:53`, `text_input.luau:103-105`, `popup_button.luau:182-187`,
  `picker.luau:79` — while `UI.isReadable` is already public
  (baseline surface, and `async_image.luau:82` uses it). One of these
  (`popup_button`'s `readFact`) also silently accepts a Memo where the others check
  `kind`.
- `[NOTE, H] CTRL-19` **`LuauUI: any` on every `build`** (all 13), and no control
  declares a return type. The first parameter of the entire public control surface is
  untyped, so a wrong first argument is a runtime nil-index rather than a type error.

---

## Coverage

Every assigned item has an entry above:

1. `LuauUI.newTable` — entry ✓ (7 findings)
2. `LuauUI.newVirtualList` — entry ✓ (7 findings)
3. `LuauUI.newPopupButton` — entry ✓ (7 findings)
4. `LuauUI.newStepper` — entry ✓ (1 NOTE; **follows the pattern**, the family's
   reference implementation)
5. `LuauUI.newSlider` — entry ✓ (4 findings)
6. `LuauUI.newRating` — entry ✓ (5 findings)
7. `LuauUI.newProgressView` — entry ✓ (4 findings)
8. `LuauUI.newLabel` — entry ✓ (3 findings)
9. `LuauUI.newPicker` — entry ✓ (5 findings)
10. `LuauUI.newDisclosureGroup` — entry ✓ (3 findings)
11. `LuauUI.newTextInput` — entry ✓ (7 findings)
12. `LuauUI.newChip` — entry ✓ (4 findings)
13. `LuauUI.newAsyncImage` — entry ✓ (6 findings)
14. `LuauUI.pathShapes` — entry ✓ (2 NOTEs; **follows the stateless-module pattern**)
15. `src/controls/contract.luau` (pattern reference) — entry ✓ (4 findings)

Plus 5 cross-cutting findings recorded once above.

**Severity tally:** CRITICAL 0 · MAJOR 15 · MINOR 27 · NOTE 17.

### Public but UNASSIGNED, found while auditing (reported, not audited in depth)

- `LuauUI.valueModel` (`src/controls/value_model.luau`, `init.luau:90`) — lives in
  `src/controls/`, has a registry row (`controls_registry.luau:~298-314`) and an api.md
  section (`docs/reference/api.md:2581`), but was not on my list. Note for whoever owns
  it: it is a `new(spec) -> Model` factory, not a `build(LuauUI, core, spec)` control,
  and its registry `dumpMarker` is `"function value_model.new"` — the same
  proves-nothing-marker shape as CTRL-07.
- `LuauUI.contribution` (`init.luau:70`) — the seam every composite in this area
  attaches through; audited only as far as "the control calls `attach`".
- `LuauUI.newResourceProvider` (`init.luau:130`) — `newAsyncImage`'s required
  `spec.provider` comes from here; the two are contractually coupled but only
  AsyncImage was assigned.
- `LuauUI.newAutoscroll` / `LuauUI.newDragRegistry` / `LuauUI.newDragSession` /
  `LuauUI.interactionTokens` (`init.luau:101-120`) — VirtualList and Table consume all
  four internally; their public shapes are outside this fragment.
- `LuauUI.adaptive` (`init.luau:161`) — `Picker.sizeClass` and
  `PopupButton.sizeClass`/`interactionClasses` are documented as coming from
  `adaptive.conditions(core, env)`; the coupling is a control-area concern but the
  module is not.
