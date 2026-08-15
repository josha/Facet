# Surface ledger — master classification (api-architecture-consistency)

Every public item, classified. **Kind** and pattern names are the constitution's
(`docs/reference/constitution.md`); **E-n** = named exception (constitution §16);
**F-n / DOC-n / DEP / PKT-n / ENF-n / NOTE** = the disposition applied
(`dispositions.md`). Full evidence (shipped shape, callers, lifecycle, proof
cases, file:line) lives in the five audit fragments under `ledger/`:
[core-state](ledger/core-state.md) · [blueprints](ledger/blueprints.md) ·
[controls](ledger/controls.md) · [services](ledger/services.md) ·
[seams](ledger/seams.md).

Coverage rule: every line of `baseline/public-surface-before.txt` (plus the two
namespaces' members and the blessed client entry points) has a row here; the
`surface-ledger-complete` gate check verifies it mechanically.

## Library metadata

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `VERSION` | metadata | single-source constant | DOC-26 (0.8.0 notes) | blueprints |
| `DEPRECATIONS` | metadata | generated + declared ledger, frozen | F-34, DEP ×2, ENF-3 | blueprints, seams |

## Reactive core and state services

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `newCore` (+ Core: `signal` `memo` `observe` `effect` `transaction` `flush` `scope` `counters` `lastError`; Signal/Memo; Scope: `own` `use` `child` `dispose` `isDisposed`) | service | colon-object; quarantine-everything; E-9 (positional `eq`) | F-13 (own refusal), F-28 (type exports), DOC-16, PKT-4, PKT-11 | core-state |
| `newEnvironment` | service | colon-object; facts + derived clamps; session-lifetime | DOC-4, DOC-14 (lifetime), PKT-3, PKT-12 | core-state |
| `replication` · `replication.snapshot` · `replication.collection` · `replication.mutation` | namespace of factories | dot-object state services; verb-string results; E-16 (ingest verbs) | F-8, F-9, F-10, F-11, exported types (pkg1), DOC-17 | core-state |
| `newResourceProvider` | service | dot-object; pull transport; generation staleness | F-12 (strict opts), DEP (`retryAttempts`), DOC-8 | core-state |
| `valueModel` · `valueModel.new` · `valueModel.defaultFormat` | pure decision module | E-13; construction-strict; fully typed | F-38 (format quarantine), DOC-8 | core-state |

## Blueprint layer (`UI`)

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| Containers: `UI.Screen` `UI.VStack` `UI.HStack` `UI.ZStack` `UI.ScrollView` `UI.Anchor` `UI.AdaptiveStack` `UI.Grid` `UI.GridRow` | blueprint primitives | construction-strict single-spec-table; E-4 (`Screen`), E-6 (`ScrollView.axis`) | F-19 (`overflow="clip"`), DOC-10 | blueprints |
| Adaptive containers: `UI.ViewThatFits` `UI.Composition` `UI.Region` | blueprint primitives | construction-strict + bespoke semantic passes; E-5 (`Region` no BOX) | DOC-10, F-29 (`eligible` typed) | blueprints |
| Leaves: `UI.Text` `UI.Image` `UI.Box` `UI.Spacer` `UI.Divider` `UI.Path` `UI.Stage` `UI.Foreign` `UI.Grip` `UI.Toggle` `UI.TextField` | blueprint primitives | construction-strict; E-1 (`fill`/`crop`), E-2 (`focusable` polarity) | F-20 (thickness metric), DOC-13 (`TextField` data-only fields); `UI.Stage`'s engine content rides the adapter seam `controller.stageHost` (2026-08-08 ViewportFrame adoption); `UI.Foreign`'s caller-owned GuiObject rides `controller.foreignHost` and the framework claims exactly one property on it, `Foreign.Parent` on the `host` authority (ADR-0034) | blueprints |
| `UI.Button` | blueprint primitive (container) | construction-strict + largest semantic block | DOC-10 (docs called it a leaf) | blueprints |
| Structural: `UI.When` `UI.ForEach` `UI.ErrorBoundary` | structural regions | only mount/unmount owners; strict | F-18 (drag refusal on them), NOTE (ErrorBoundary adoption) | blueprints |
| Style modifiers: `UI.shadow` `UI.gradient` `UI.corners` `UI.stroke` `UI.strokeData` `UI.shadowData` `UI.gradientData` `UI.cornersData` `UI.styleGroup` | modifiers | `(bp, spec, style?) -> new frozen bp`; E-3 (`styleGroup` order) | F-4, F-5, F-7, PKT-10; `strokeData` sibling gap → DOC/PKT-5 class | blueprints |
| Layout modifiers: `UI.frame` `UI.padding` `UI.offset` `UI.aspectRatio` `UI.alignment` `UI.overlay` `UI.background` `UI.containerRelativeFrame` | modifiers | blueprint-first; positional sub-family (`offset`/`aspectRatio`/`alignment`) | F-3 (`background` meta), F-7 (attribution), F-21 | blueprints |
| `UI.draggable` `UI.dropTarget` | modifiers (meta channel) | typed specs; one legality path | F-18 (class gate) | blueprints |
| `UI.sensoryFeedback` | modifier (meta channel) | typed spec; closed-taxonomy verb + Readable trigger; composes (list, not last-wins) | F-18 (structural class gate, same ruling as the drag pair); plays nothing — the emission is one bus event | blueprints |
| `UI.schema` (11 members) `UI.isReadable` `UI.PROP_DIRTY` | tooling accessors | dot module; frozen after F-6/F-34 | F-6, F-34, DOC-9 | blueprints |
| `UI.sortedEntries` | pure authoring helper | value-first pure fn `(dict, compare?) -> {{key,value}}`; refuses an unorderable key type at construction | fusion-comparison.md §5 G-3 (2026-08-15): deliberately NOT a `UI.ForPairs` class and deliberately NOT a `Readable` — the reactive half is the caller's own `core:memo`, and `compare` orders KEYS so the determinism guarantee holds for any comparator | blueprints |
| Shared vocabularies: transitions, `tint`, dims/sides, metric names | closed grammars | one validator, many readers | DOC-10; BP-F25 timing NOTE | blueprints |

## Composite controls

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `newTable` | composite | control-build, `api`-nested variant; `onPrimaryAction` joins the spec in parity round 2 §3.4 (a second interactive verb on the same rows, four-input, cited in the registry row) | F-24 (gallery bind), F-25 (dump), F-27 (header align), PKT-1, PKT-9, NOTE (parity round 2 §3.4) | controls |
| `newVirtualList` | composite | control-build, flat variant (pre-rule) | F-25 (dump proof), DOC-11, PKT-1 | controls |
| `newVirtualGrid` | composite | control-build, flat variant (matches its `newVirtualList` sibling deliberately — the two share the `virtual_extents` index and are read against each other) | none (clean) | controls |
| `newPopupButton` | composite | control-build, `api` variant | F-1 (memo guard), DOC-22, PKT-6, PKT-1 (`presentation`) | controls |
| `newStepper` | composite | control-build, value family — the reference implementation | none (clean) | controls |
| `newSlider` | composite | control-build, value family | PKT-7 (`onInteractionClassLost`), PKT-1 | controls |
| `newRating` | composite | control-build; one-Grip strip | F-25 (dump/dispose proof), PKT-7 | controls |
| `newProgressView` | composite | control-build, non-interactive; `value` is OPTIONAL since parity round 2 §3.1 (`value = nil` = indeterminate), and `presentation` / `motionClock` join the spec — still no input contribution, so the registry row stays `inputProofs = false` | DOC-12, NOTE (parity round 2 §3.1, postdates the Step 7 F-n audit round) | controls |
| `newLabel` | composite | control-build, non-interactive | F-23 (`semanticText` Readable) | controls |
| `newPicker` | composite | control-build; adaptive presentation | DOC-22, PKT-6 | controls |
| `newDisclosureGroup` | composite | control-build; focus-restore | NOTE (dual bindFocus path — constitution names contribution as canonical) | controls |
| `newTextInput` | composite | control-build, `api` variant; commented dispose deviation (endEditing-first, deliberate) | F-26 (env guard), DOC-13, PKT-1 (`disabled`) | controls |
| `newChip` | composite | control-build, minimal — the template shape | F-2 (validation) | controls |
| `newAsyncImage` | composite | E-8 (caller-scope; no dump/dispose) | DOC (honest entry kept), registry `dump=false` reason (ENF-1) | controls |
| `newRowActions` | composite | control-build, `(LuauUI, core, spec)`; underscore-prefixed internal seam (`_open` `_close` `_isOpen` `_settleTo` `_closeMenu` `_menuHandle` `_pointerHandlers` `_commitFirst` `_handleActivate`) for Table's `rowActions` composition | NOTE (row-actions merge, postdates the Step 7 F-n audit round) | controls |
| `pathShapes` · `pathShapes.arc` · `pathShapes.ring` · `pathShapes.needle` · `pathShapes.MAX_CONTROL_POINTS` | pure decision module | stateless dot module | NOTE (ring comment count) | controls |

## Runtime services

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `mount` | service | `(core, blueprint, opts?)`; E-14 (dump envelope) | NOTE (untyped root — PKT-8 class) | services |
| `renderer` · `renderer.attach` · `renderer.EMITTED_PROPS` · `renderer.DIRECT_PROPS` · `renderer.BINDING_PROPS` · `renderer.STYLE_PROPS` · `renderer.compactForm` · `renderer.drawnButtonText` | service + conformance data | E-10; controller = dot methods | F-29 (opts truth), F-30 (read copies), DOC-5 | services |
| `newPresenter` (PresentOpts, toasts, feedback, handles) | service | core-first; unsubscribe convention (uniform) | F-15, F-16, DOC-1, DOC-14, PKT-3 | services |
| `newActionSystem` | service | contexts own priority/sink/lifetime; `_deliver` = adapter seam (DOC-28) | F-29 (handler types), DOC-5/api coverage, PKT-2 (`destroy`) | services |
| `inputHint` | reactive helper | `(core, env, …, opts?)` returning Readable | F-33 (`opts.scope`, style validation) | services |
| `newFocusGraph` | service | logical focus; predicates at nav time | F-14 (no caller mutation), PKT-2 (`remove`), PKT-3 | services |
| `newRowActionsCoordinator` | service | `(core) -> { claim, release, bindScroll }`; dot-object, one per shared list surface, at-most-one-row-open policy | NOTE (row-actions merge, postdates the Step 7 F-n audit round) | services |
| `contribution` · `contribution.attach` · `contribution.read` · `contribution.PROP` | modifier + seam | best-typed seam; meta channel | DOC-9 (`PROP` naming note) | services |
| `motion` · `motion.newClock` · `motion.registerClass` · `motion.resolveClass` · `motion.classNames` · `motion.isRegisteredClass` · `motion.resetClasses` · `motion.registerCurve` · `motion.resolveCurve` · `motion.curveNames` · `motion.isRegisteredCurve` · `motion.resetCurves` · `motion.newValueReveal` | namespace | colon side of E-7; `newValueReveal` matches pure-model shape (verified); the five `*Curve*` members are deliberately ONE-FOR-ONE with the five `*Class*` members (ADR-0033) — two sibling registries that read differently would be a lookup at every call site, and the symmetry is the decision, not the default | DOC-3, DOC-15; registry process-global NOTE | services |
| `adaptive` · `adaptive.sizeClass` · `adaptive.heightClass` · `adaptive.navPlacement` · `adaptive.orientationFor` · `adaptive.axisFor` · `adaptive.columnsFor` · `adaptive.conditions` · `adaptive.BREAKPOINTS` · `adaptive.HEIGHT_BREAKPOINTS` · `adaptive.DEFAULT_STACK_ABOVE` | pure decision module + reactive half | value-first pure fns; `opts.scope` ownership | F-28/F-29 (Readable typing, scope in type), DEP (`contentWidth`) | services |
| `composition` · `composition.resolve` · `composition.normalize` · `composition.dump` · `composition.floorPx` · `composition.arrangementOf` · `composition.ARRANGEMENTS` · `composition.HUD` · `composition.HUD_GROUPS` · `composition.ZONES` | pure decision module | strictest validator; E-12 | F-29 (types) | services |
| `text` · `text.measure` · `text.fit` · `text.size` · `text.facts` · `text.lineBox` | pure decision module (module-global caches noted) | spec-table canonical; E-15 (positional measure) | F-31, F-32, DOC-2 | services |

## Input mechanics

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `newDragSession` | pure model | opts-factory, colon methods | NOTE (SEAM-8 export-binding proof) | seams |
| `newDragRegistry` | service | dot functions (the family's one dot object — recorded, PKT-1-adjacent; documented per call) | F-29 (Opts truth), DOC-6 | seams |
| `newDragVelocity` | pure model | opts-factory, colon | PKT-5 (`WINDOW_S`) | seams |
| `newAutoscroll` | pure model | opts-factory, colon | PKT-5 (constants), DOC-21 | seams |
| `interactionTokens` · `interactionTokens.dragPromotionPx` · `interactionTokens.dragPromotionRangePx` · `interactionTokens.classForPointerType` · `interactionTokens.promotionPx` · `interactionTokens.promotionForPointerType` · `interactionTokens.promoted` | pure decision module | clean — no findings | — | seams |
| `touchGestures` · `touchGestures.normalize` · `touchGestures.newArbiter` | pure decision module + factory | positional engine-args contract | F-17 (adapter call shape), F-37 (opts refusal) | seams |
| `spatial` · `spatial.normalize` · `spatial.extend` · `spatial.of` · `spatial.isFlat` · `spatial.describe` · `spatial.PHASES` · `spatial.HANDEDNESS` | contract-only module | never-errors clamp; cleanest entry | DOC-20 | seams |

## Styling

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `tokens` · `tokens.compile` · `tokens.contrastRatio` · `tokens.dangerPair` | pure decision module | `(value?, report)` validator; E-12 | DOC-8 (`dangerPair`), PKT-8 (types) | seams |
| `themes` · `themes.define` · `themes.resolve` · `themes.neutral` · `themes.neutralPackage` · `themes.lintProperty` · `themes.checkCoverage` · `themes.SCHEMA` | curated namespace | strongest docs-coverage story (per-member check) | PKT-8 (types), NOTE (three return conventions — SEAM-13, constitution §6 rules future) | seams |

## Client entry points (blessed; required directly per ADR-0011)

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `client/screen_target` | engine adapter | opts factory; one adapter per root | F-17 (gesture args), DOC-7/DOC-24 | seams |
| `client/billboard_target` | engine adapter | root-swap decorator (elegant reuse) | DOC-7 | seams |
| `client/roblox_env` · `client/roblox_input` · `client/roblox_resources` | engine adapters | bind/unbind (+ `newSystem` factory) | DOC-7 | seams |
| `client/theme_controller` | engine adapter | capability-checked install; best lifecycle story | DOC-23 | seams |
| `client/edit_preview` | dev tooling | E-11 | DOC-7 | seams |
| `client/motion_driver` | engine adapter | bind → unbind (documented footgun stays documented) | DOC-7 | services |
| `client/haptics` | engine adapter | opts factory; opt-in, DEFAULT OFF; bind → unbind + attachButtons → detach | five-state capability lattice (no platform capability API); total verb map with explicit silences; pooled effects; unreachable from `src/` outside `src/client` | seams |

## Extension seams and process

| Item | Kind | Pattern / exception | Dispositions | Fragment |
|---|---|---|---|---|
| `render/target_contract` | extension contract | declared-name lists + checker | F-35 (nine missing methods), DOC-7 | seams |
| `tools/lune/scaffold` (control / adapter) | extension tooling | pure plan + CLI; control branch clean | F-36 (adapter branch) | seams |
| `docs/extending/*` (six playbooks) | extension docs | commands/paths verified live | ENF-4 (two playbook gaps) | seams |
| ADR-0011 process (`VERSION`, ledger, `api_surface.spec`, `check_boundary`) | process | single-source enforced | ENF-2, ENF-3, SEAM-31 fix | seams |

## Cross-cutting rulings

- **E-7 colon-vs-dot** is now written (constitution §16); every item above sits on
  its declared side.
- **Ownership spellings (X-2)** collapse to the constitution §8 preference order;
  `inputHint` gains `opts.scope` (F-33) so the two reactive helpers agree.
- **Quarantine regimes**: the core's rule extends to the state services (F-9/F-10)
  and `valueModel.format` (F-38); validators keep construction errors.
- **Error grammar**: constitution §4 models it; full unification is PKT-10.
- Items with **no findings**: `newStepper`, `pathShapes`, `interactionTokens`,
  `spatial`, `contribution`, the scaffold control branch, the VERSION chain, and
  RascalRally's clean client-entry-point compliance — recorded as successes.
