# Surface ledger — RUNTIME SERVICES

Area: mount / render / present / input / focus / motion / layout-decision services.
Audited read-only against the source at 2026-08-02 (VERSION 0.7.0, baseline
`baseline/public-surface-before.txt`). Every claim below carries a file:line I
read this session. Dispositions are the lead's call; this fragment only flags.

Two cross-cutting observations are recorded once here and referenced by the
entries, rather than repeated twelve times:

**X-1 — the colon/dot split has no written rule.** Services hand back tables of
DOT functions (`root.dispose()`, `controller.refresh()`, `presenter.present()`,
`graph.pushScope()`, `context.createAction()`, `contribution.attach()`); motion,
the reactive core and the pure input models hand back COLON objects
(`clock:step()`, `value:setTarget()`, `reveal:sync()`, `tracker:push()`,
`model:step()`, `core:signal()`, `scope:own()`). The split is real and
self-consistent per family, but it is documented nowhere: `grep -rn "colon" docs/`
returns exactly two hits, one of which
(`docs/research/2026-07-20-phase4-architecture-verifier-findings-resolution.md:17`)
records an *earlier* verifier raising the same point and dispositioning it as
"docs-acceptable … covered in docs/guide/ and docs/reference/api.md" — and the
only mention in api.md is `docs/reference/api.md:2795` ("Methods (colon-called)")
about `newDragSession`. The promised doc coverage was never written. Every entry
below records which side of the split its item is on.

**X-2 — three ownership spellings for one need.** A caller that must not leak a
service's reactive resources is told three different things:
`adaptive.conditions(core, env, { scope = … })` (opts-carried scope,
`src/layout/adaptive.luau:176-181`); `motion.newClock` → `scope:own(clock)`
(scope-owns-the-object, `src/motion/clock.luau:287-289`); `inputHint(...)` → "the
caller owns the returned memo … dispose it" by hand
(`src/input/hint.luau:16`, `docs/reference/api.md:1717`). A fourth exists inside
the same area — `presenter.onTick(fn) -> unsubscribe`, "`scope:own(presenter.onTick(...))`"
(`docs/reference/api.md:1755`). These are four spellings of "who kills this",
and nothing names the canonical one.

---

### `LuauUI.mount` — service constructor (mount graph)

- **Shipped shape:** `mount(core, blueprint, opts?) -> MountedRoot`
  (`src/mount.luau:49`). `MountOpts = { scope: any?, transitions: Transitions? }`
  (`src/mount.luau:42-45`); `Transitions` is a real exported type
  (`src/mount.luau:34-40`). Returned root is an **untyped anonymous table**
  (`src/mount.luau:561-577`): `.node`, `.dispose()`, `.takeDirty()`,
  `.counters()` (cloned, `:572`), `.dump()` → `{ schema = "luauui-mount-dump/1",
  tree = … }` (`:575`).
- **Pattern:** core-first service constructor, opts table last, dot-method result
  (X-1, dot side). Follows the `newX(core, …, opts?)` shape the rest of the
  library uses.
- **Callers:** `src/present/presenter.luau:972, 1057, 1194, 1252, 2494`;
  RascalRally `games/RascalRally/code/src/client/LuauUISponsor/OmenState.luau:440`
  (`LuauUI.mount(core, view.blueprint, { scope = hostScope })`); `tests/mount.spec.luau`.
- **Lifecycle:** `opts.scope` supplied → caller's scope owns everything; omitted →
  `mount` builds `core:scope("mount-root")` (`:50`) and `root.dispose()` is the
  only way to reach it. The presenter deliberately passes `scope:child("mount")`
  and never calls `root.dispose()` — disposing the parent scope is the single
  teardown (`src/present/presenter.luau:2270-2278`, comment names the historical
  double-dispose). Leak posture proven by `tests/mount.spec.luau` "50 mount/dispose
  cycles return mount and core registries to baseline".
- **Proof:** `tests/mount.spec.luau` — "mounts each node exactly once with stable
  paths", "duplicate explicit sibling ids are a hard error", "duplicate keys are a
  hard error", "50 mount/dispose cycles return mount and core registries to
  baseline", "dumps are deterministic and carry dirty flags". Docs:
  `docs/reference/api.md:1248-1267`.
- **Findings:**
  - `[NOTE, H]` `MountedRoot` has no exported type — the whole return surface is
    an anonymous table literal — while its own `opts` argument type
    (`Transitions`, `MountOpts`) IS exported — `src/mount.luau:34-45` vs `:561`.
    User cost: a strict consumer typing a variable that holds a mounted root gets
    `any`, and no type-checker catches a misspelled `.takeDirty`. Same defect in
    `renderer.attach` and `newPresenter` (below) — it is a family, not a one-off.
  - `[NOTE, M]` `dump()` nests under `tree` (`{ schema, tree }`,
    `src/mount.luau:575`) while its sibling `composition.dump` is flat
    (`{ schema, arrangement, lanes, … }`, `src/layout/composition.luau:1672-1690`).
    Two public `schema = "luauui-*-dump/N"` producers, two envelope shapes. User
    cost: a generic dump reader/differ has to special-case each.

---

### `LuauUI.renderer` — module namespace + `attach` service constructor

- **Shipped shape (module):** `renderer.attach` (`src/render/renderer.luau:850`),
  `renderer.STYLE_PROPS` (`:141`), `renderer.BINDING_PROPS` (`:142`),
  `renderer.EMITTED_PROPS` (frozen, `:176`), `renderer.DIRECT_PROPS` (frozen clone,
  `:177`), `renderer.compactForm(props)` (`:201`),
  `renderer.drawnButtonText(props, compact?)` (`:228`). All seven appear in the
  frozen baseline (`baseline/public-surface-before.txt:112-119`).
- **Shipped shape (`attach`):** `attach(core, root, env, adapter, opts?) -> controller`,
  `opts: { rootPolicy: string?, onNodeTap: ((string) -> ())? }?`
  (`src/render/renderer.luau:850-856`). Controller (all dot functions, untyped
  table at `:2295`): `refresh` `:2319`, `setFocusPath(path?, visible?)` `:2368`,
  `initialRender` `:2453`, `rectOf` `:2461`, `screenRectOf` `:2468`,
  `scrollTo` `:2479`, `hiddenRoots` `:2488`, `attachDragDetector` `:2498`,
  `dragRegistry` `:2509`, `peekDragRegistry` `:2517`, `setDragCollaborators` `:2529`,
  `scrollPosition` `:2541`, `scrollToVisible` `:2555`, `scrollHostFor` `:2612`,
  `setPointerDrag` `:2665`, `stepAutoscroll` `:2709`, `observeScroll` `:2801`,
  `setPresentationTransform` `:2843`, `setPresentationTransparency` `:2872`,
  `setPresentationOffset` `:2898`, `setDisplayOrder` `:2909`, `setRootVisible` `:2919`,
  `stats` `:2927`, `diagnostics` `:2931`, `compositionAt` `:2939`,
  `textPending` `:2950`, `dispose` `:2957`. That is **27** public members.
- **Pattern:** core-first constructor + dot-method controller (X-1, dot side);
  construction-strict validation for `rootPolicy` (unknown value errors and lists
  the legal set, `:863-879`).
- **Callers:** internal — `src/present/presenter.luau:973, 1058, 1201, 1253, 2495`;
  `src/client/edit_preview.luau:84`. examples — `examples/gallery/scenarios/runner.luau:293`.
  tests — `tests/renderer.spec.luau`, `tests/pointer.spec.luau`,
  `tests/text_premeasure.spec.luau`, `tests/button_complete.spec.luau` and ~20 more.
  RascalRally — `games/RascalRally/code/src/client/LuauUISponsor/OmenState.luau:441`
  (`{ rootPolicy = "edgeToEdge" }`); controller consumers at
  `.../StoryFlow.luau:755, 768, 1710-1729`, `.../OmenState.luau:451`,
  `.../init.luau:930`.
- **Lifecycle:** `attachScope = core:scope("renderer-attach")` (`:881`) is built and
  owned by `attach`; `controller.dispose()` (`:2957-2989`) tears down the drag
  registry, every `pathClipObservers` detach, the attach scope, and the adapter
  root. Callers own the controller (`presenter.dismiss` → `handle.controller.dispose()`,
  `src/present/presenter.luau:2271`). `observeScroll` returns an unsubscribe the
  caller owns (`:2801-2807`).
- **Proof:** `tests/renderer.spec.luau` — "initial render creates every mounted
  node with rects inside the safe content rect", "a paint/semantics-only change
  writes the prop and never re-solves or writes rects", "a viewport change
  re-solves and writes only changed rects", "When toggling creates/removes adapter
  nodes and re-solves", "dispose destroys the adapter root".
  `tests/render_target_contract.spec.luau` pins `EMITTED_PROPS` adapter parity
  (named at `src/render/renderer.luau:153`). Docs:
  `docs/reference/api.md:1268-1345`.
- **Findings:**
  - `[MAJOR, H]` **The `attach` opts type is a lie by omission: `engineSelectionBridge`
    is read but not declared.** Type says `{ rootPolicy: string?, onNodeTap: … }?`
    (`src/render/renderer.luau:855`); the body reads
    `(opts and (opts :: any).engineSelectionBridge) == true` (`:2362`) and the
    presenter passes it (`src/present/presenter.luau:1262`). User cost: a strict
    consumer who wants the bridge on a hand-attached surface gets a type error for
    a supported option, and the `:: any` cast means no checker would catch its
    removal. Note it also is not listed in api.md's `attach` line (`:1270`); the
    only mention of the flag is under `presentModal` (`docs/reference/api.md:1234`).
  - `[MINOR, H]` **`onNodeTap` is declared one-arg and always called two-arg.**
    Type `((string) -> ())?` (`:855`); call sites pass `(path, meta)` at `:1357`
    and `(tapPath, { via = "dragDetectorTap" })` at `:1452`, and both in-tree
    consumers write `function(_path: string, meta: any?)`
    (`src/present/presenter.luau:976, 1060, 1265`). User cost: an author who trusts
    the type writes a one-arg handler and never learns `meta` (which carries
    `x`/`y` for outside-tap geometry and `via`) exists.
  - `[MINOR, H]` **Two absent-capability conventions on sibling controller
    "subscribe" methods.** `observeScroll` returns a **no-op unsubscribe** when the
    adapter has no seam (`:2806`); `attachDragDetector` returns **nil**
    (`:2498-2500`, comment at `:2495-2497` calls the nilability deliberate). Both
    are "attach a thing to a path, get a detach". User cost: every caller of
    `attachDragDetector` must nil-guard, and a caller who pattern-matched on
    `observeScroll` writes `detach()` on nil.
  - `[MINOR, H]` **Defensive-copy convention is not uniform across the read
    methods.** `stats()` clones (`:2928`) and `mount.counters()` clones
    (`src/mount.luau:572`), but `hiddenRoots()` returns the live internal table
    (`:2489`), `diagnostics()` returns the live `lastDiagnostics` (`:2932`), and
    `compositionAt(nil)` returns the live `lastCompositions` (`:2941`). User cost:
    a caller who caches `diagnostics()` sees it mutate under them next solve, and a
    caller who mutates `hiddenRoots()` corrupts the renderer's own state.
  - `[MINOR, H]` **Six public module exports are documented nowhere.**
    `EMITTED_PROPS`, `DIRECT_PROPS`, `BINDING_PROPS`, `STYLE_PROPS`, `compactForm`,
    `drawnButtonText` all sit in the frozen public dump
    (`baseline/public-surface-before.txt:113-119`) and `grep -c` each of them in
    `docs/reference/api.md` returns 0. User cost: an adapter author (the exact
    audience for `EMITTED_PROPS`, per `src/render/renderer.luau:144-154`) has to
    read the renderer source to find the conformance list they are supposed to
    implement against.
  - `[MINOR, H]` **Six public controller methods are undocumented.** `scrollHostFor`,
    `peekDragRegistry`, `setDragCollaborators`, `hiddenRoots`, `textPending`,
    `setDisplayOrder` — 0 hits each in `docs/reference/api.md`, while api.md's
    Controller sentence (`:1272-1279`) enumerates only 8 of the 27 members. User
    cost: `scrollHostFor` exists precisely so a control does not re-derive the
    autoscroll host (`src/render/renderer.luau:2597-2611`) and no consumer reading
    only the docs can know it is there.
  - `[NOTE, M]` `renderer` is a **namespace with a `new`-shaped function named
    `attach`** while every sibling service is `LuauUI.newX`. `LuauUI.renderer.attach`
    vs `LuauUI.newPresenter` / `LuauUI.newFocusGraph` (`src/init.luau:52-58`). Not
    obviously wrong (the module also exports prop tables), but it is the one
    construction verb in the library that is not `new*`.
  - `[NOTE, M]` `attachDragDetector(path, handlers: any)` (`:2498`) and
    `setDragCollaborators(collaborators: { [string]: any })` (`:2529`) and
    `setPointerDrag(info: any)` (`:2665`) and `stepAutoscroll(dt?) -> any` (`:2709`)
    all take/return bare `any` at the public boundary, with the real shape only in
    prose comments. `setPresentationTransform` by contrast is fully typed (`:2843-2846`).

---

### `LuauUI.newPresenter` — service constructor (presentation)

- **Shipped shape:** `presenter.new(core, env, adapter, actionSystem, opts?)`
  (`src/present/presenter.luau:735`), `PresenterOpts = { clock: any?, now: (() -> number)? }`
  (`:726-733`). Returns an untyped `self` table (`:736`, `:2615`).
  Fields: `focus` `:739`, `emitFeedback` `:758`, `onFeedback` `:759`,
  `feedbackTypes` `:760`, `SURFACE_LAYER` `:764`, `motionClock` `:783`,
  `exclusiveSurfaceActive` `:824`.
  Methods: `syncPopupCatcher` `:1079`, `topPopupCatcherPath` `:1091`,
  `topScrimPath` `:1111`, `present` `:2196`, `presentModal` `:2200`,
  `onModalPresented` `:2218`, `presentCritical` `:2234`, `dismiss` `:2252`,
  `back` `:2300`, `refresh` `:2310`, `presentToast` `:2532`, `toastCounts` `:2561`,
  `tick` `:2574`, `onTick` `:2601`, `depth` `:2611`.
  `PresentOpts` is a real exported type with 21 fields (`:33-146`); `ToastOpts`
  with 7 (`:149-157`). Handle is `local handle: any` (`:1703`) with ~25 fields.
  `presentToast` returns `{ id, dismiss() }` (`:2548-2558`).
- **Pattern:** core-first constructor, opts last, dot methods (X-1, dot side);
  subscription methods return an unsubscribe closure (`onFeedback` → `bus.subscribe`
  `src/present/feedback.luau:80`; `onModalPresented` `:2221-2226`; `onTick`
  `:2603-2608`) — this is the one convention in the area that is genuinely uniform.
- **Callers:** RascalRally — `games/RascalRally/code/src/client/LuauUIRacerListGui.luau:48`,
  `.../LuauUISettingsGui.luau:89`, `.../GaragePilotGui.luau:45`; `handle.onFeedback`
  at `.../LuauUISponsor/init.luau:2003`; `presenter.onTick` at
  `.../LuauUISponsor/OmenState.luau:169` (scope-owned, correctly);
  `presentToast` threaded as an injected function through
  `.../StoryFlow.luau:87,505` and `.../PlayFlow.luau:96,415`.
  examples — `examples/gallery/client/init.client.luau:48-49`.
  tests — `tests/presenter.spec.luau`, `tests/responder.spec.luau`,
  `tests/late_contributions.spec.luau`, `tests/sponsor_scenarios.spec.luau`.
- **Lifecycle:** per-surface teardown is `dismiss(handle)` (`:2252-2298`) →
  context destroy, focus scope removal, controller dispose, `handle.scope:dispose()`,
  coordinator dispose; deferred behind the surface's exit transition when one is
  declared. Presenter-private surfaces (scrim `:915-921`, popup catcher `:1023-1029`,
  toast layer `:2404-2413`, drag proxy `:1144-1152`) each own their own dispose.
  **There is no `presenter.dispose()`** (grep of `function self.` at
  `src/present/presenter.luau` returns 15 names, none of them `dispose`).
- **Proof:** `tests/presenter.spec.luau` — "presents a screen with document-order
  focus and device navigation", "a modal sinks navigation from the base screen and
  traps focus", "Cancel dismisses the modal, restores focus, and disposes its
  context", "open/close churn is registry-neutral across the whole slice",
  "dismissing a modal from inside its own onActivate is safe".
  `tests/late_contributions.spec.luau` pins the refresh-time contribution
  re-discovery. `tests/sponsor_scenarios.spec.luau:1139` pins the toast
  supersede verb. Docs: `docs/reference/api.md:1346-1510` (+ Toasts `:1471`,
  feedback `:1511`).
- **Findings:**
  - `[MAJOR, H]` **api.md contract lie: toast supersede.** api.md says "Every
    retirement emits `dismiss` with a reason: `timeout`, `supersede`, `capacity`,
    `preempt`, `manual`" (`docs/reference/api.md:1498-1500`). The code emits
    supersede as **its own type with `reason = nil`**:
    `type = if reason == "supersede" then "supersede" else "dismiss"; reason = if
    reason == "supersede" then nil else reason`
    (`src/present/presenter.luau:2430-2435`), and the suite pins exactly that —
    `tests/sponsor_scenarios.spec.luau:1139` "a same-subject toast replaces in
    place (supersede, not churn)" asserts `#supersedes == 1` and that no dismiss
    carries `reason == "supersede"` (`:1144-1147`). api.md's own taxonomy list
    (`:1521-1522`) correctly includes `supersede` as a type, so the document
    contradicts itself. User cost: a game wiring a "replaced" cue off
    `event.type == "dismiss" and event.reason == "supersede"` — literally what the
    doc instructs — fires never. **The same stale claim is repeated in the source
    comment at `src/present/feedback.luau:59-60`.**
  - `[MAJOR, H]` **Two of the four string-enum `PresentOpts` are unvalidated, and
    the file states the opposite rule.** `makeHandle` refuses an unknown
    `cancelPolicy` loudly, with the comment "the same way an unknown `rootPolicy`
    is (renderer.attach): a typo that silently kept the default would read as 'the
    framework ignored my mandatory modal'" (`src/present/presenter.luau:1228-1234`).
    But `responder` is compared by equality only —
    `isPassive = kind == "screen" and (opts and opts.responder) == "passive"`
    (`:1561`) — and `scrim` is passed through raw into
    `scrimMode = (opts and opts.scrim) or …` (`:1739`), where `mountScrim` does
    `if mode ~= "none" then "scrim" else "plain"` (`:955`). User cost: `responder =
    "Passive"` silently presents an engaged surface that sinks nothing it was
    supposed to sink; `scrim = "None"` silently DIMS the screen. Both are exactly
    the failure mode the `cancelPolicy` comment says the framework refuses to have.
  - `[MAJOR, M]` **No `presenter.dispose()`.** The presenter owns a feedback bus
    (`:748`), a motion clock it may have BUILT itself (`:782` — only when
    `opts.clock` is absent), a `core:signal` (`:823`), two unscoped
    `core:observe` subscriptions on the focus graph (`:869`, `:873`), `tickHooks`,
    `modalWatchers`, and up to four presenter-private surfaces. Nothing releases
    any of it. Every other service in the area has a teardown verb
    (`root.dispose`, `controller.dispose`, `clock:dispose`, `context.destroy`,
    `bus.dispose` at `src/present/feedback.luau:144`). User cost: a client that
    tears down and rebuilds a presenter (a UI reload, a scenario harness, a
    per-round HUD) leaks the clock and the bus with no sanctioned way not to; the
    focus graph it created is also unreachable for teardown (see `newFocusGraph`).
    Confidence M only because it may be an intentional "one presenter per client
    session" contract — but that contract is written nowhere.
  - `[MINOR, H]` **api.md's `newPresenter` signature omits the 5th argument.**
    `docs/reference/api.md:1348` states `LuauUI.newPresenter(core, env, adapter,
    actionSystem) -> Presenter`; the real signature takes `opts?`
    (`src/present/presenter.luau:735`). The full form appears only later, buried in
    the `presenter.motionClock` bullet (`docs/reference/api.md:1758-1760`). User
    cost: the headline signature a reader copies cannot share a clock.
  - `[MINOR, H]` **`presentCritical` silently drops every opt but `onActivate` on
    the fallback path.** `makeHandle(opts.fallbackScreen(err), { onActivate =
    opts.onActivate }, "screen")` (`src/present/presenter.luau:2247-2249`). So a
    critical screen declared `rootPolicy = "edgeToEdge"`, `navigationGroups`,
    `transition`, `keepVisibleOffset`, `sinkNavigation`, `revealWhenTextExact` etc.
    loses all of them exactly when things have already gone wrong. Undocumented
    (`docs/reference/api.md:1354-1357` says only "presents `opts.fallbackScreen(err)`
    instead"). User cost: the fallback screen renders under the wrong root policy
    and with the wrong navigation model — a second failure stacked on the first.
  - `[MINOR, H]` **`sinkNavigation` is accepted-and-ignored on a passive surface.**
    `sink = kind == "modal" or (not isPassive and (opts and opts.sinkNavigation) ==
    true)` (`:1574`). The `isPassive` term drops it. Documented for modals ("modal
    contexts sit above and SINK", `:1540-1551`) but nothing says a passive surface
    ignores it. User cost: `{ responder = "passive", sinkNavigation = true }` reads
    as "a HUD that sinks once engaged" and quietly is not that (engagement sets
    sink itself at `:1816`, so the end state is right by accident, but the opt did
    nothing).
  - `[MINOR, H]` **`presentToast`'s `position` and `transition` are
    accepted-and-ignored for every toast after the first.** `ensureToastLayer`
    returns immediately when a layer exists (`:2441-2443`) and only the first call
    fixes `toastPosition`/`toastTransition` (`:2447-2453`). Documented
    (`docs/reference/api.md:1505-1507`, code comment `:2444-2446`) and defensible
    (one layer, one stacking direction), so severity is low — but it is still the
    accepted-but-ignored shape, with no error and no way for the caller to find out.
  - `[MINOR, H]` **Four string-enum opts are typed `string?`, not unions**, while
    the same library exports `ActionType = "Bool" | "Direction1D" | …`
    (`src/input/actions.luau:17`). `rootPolicy: string?` (`:34`), `responder:
    string?` (`:48`), `cancelPolicy: string?` (`:107`), `scrim: string?` (`:115`) —
    each with the legal values in a trailing comment. User cost: no editor
    completion and no compile-time catch for the exact typos finding 2 says are
    unvalidated at runtime either.
  - `[MINOR, M]` **Handle is `any` and its documented field list is a subset.**
    `local handle: any = { … }` (`:1703-1750`) carries ~25 fields; api.md lists
    eight (`docs/reference/api.md:1436-1439`: `.root .controller .blueprint
    .actions .displayOrder .responder .engage() .resign()`) plus `handle.onFeedback`
    in the feedback bullet. Undocumented-but-reachable: `.kind`, `.scope`,
    `.contributions`, `.cancelPolicy`, `.outsideTapCancel`, `.coordinator`,
    `.transition`, `.transitionNode`, `.scrimMode`, `.isPassive`, `.feedGeometry`,
    `.syncContributions`, `.navigationGroupsFn`, `.emitFeedback`,
    `.textRevealPending`, `.textRevealedExact`. User cost: no boundary — a consumer
    cannot tell which of these it may rely on, and the framework cannot tell which
    it may change.
  - `[MINOR, M]` **Three public methods are undocumented:** `toastCounts()`
    (`:2561`), `syncPopupCatcher()` (`:1079`), `topPopupCatcherPath()` (`:1091`),
    plus the field `feedbackTypes` (`:760`). None appear in api.md's method list
    (`:1350-1439`). `syncPopupCatcher` in particular is an internal sync step that
    is reachable as if it were API.
  - `[NOTE, M]` **Two public words for activation-handling, with different return
    contracts:** `PresentOpts.onActivate(path: string?, meta: any?) -> ()`
    (`:35`) and `Bundle.handleActivate(path: string, meta: any?) -> boolean`
    (`src/input/contribution.luau:77`). One is nil-tolerant on `path` and returns
    nothing; the other is not and consumes by returning true. The double-fire
    hazard is documented as an invariant (`docs/reference/api.md:1843-1846`), which
    is a mitigation, not a resolution.

---

### `LuauUI.newActionSystem` — service constructor (input actions)

- **Shipped shape:** `actions.newSystem(core) -> system`
  (`src/input/actions.luau:19`). `system.createContext{ name, priority?, sink? }`
  `:183`, `system.modifiers()` `:247`, `system.deviceKey(keyCode, isDown)` `:259`,
  `system.deviceAxis(axis, x, y)` `:301`. Context: `.name .priority .sink .enabled
  .destroyed .actions` (raw fields, `:184-191`), `.createAction(name, type)` `:192`,
  `.setEnabled(on)` `:197`, `.setSink(on)` `:215`, `.destroy()` `:218`. Action:
  `.name .type .context .state (Signal) .bindings`, `.onPressed(fn) -> unsub` `:34`,
  `.onReleased(fn) -> unsub` `:44`, `.bind(spec) -> binding` `:74`,
  `.bindAxis(spec) -> binding` `:115`, `.preferredBinding(kind)` `:167`,
  `._deliver(value)` `:55`. Binding: `.fire(value)` `:91`, `.remove()` `:97`,
  `._sample(x, y)` `:137`. `ActionType` is a real string union (`:17`).
- **Pattern:** core-first constructor, dot methods (X-1, dot side),
  subscription-returns-unsubscribe (`onPressed`/`onReleased`) — matches the
  presenter's convention exactly.
- **Callers:** internal — `src/present/presenter.luau:1570-1691` (the whole
  navigate/activate/cancel/adjust binding set), `:2043` (`actionSystem.modifiers`).
  Client swap-in: `src/client/roblox_input.luau` (`newSystem`), used by RascalRally
  `games/RascalRally/code/src/client/LuauUIRacerListGui.luau:48` and
  `.../GaragePilotGui.luau:45`. tests — `tests/input.spec.luau`,
  `tests/paradigm_input_axis.spec.luau`.
- **Lifecycle:** `context.destroy()` (`:218-230`) disposes every action's state
  signal, clears handler arrays and removes the context from the system's list.
  The presenter owns one context per surface and destroys it in `dismiss`
  (`src/present/presenter.luau:2258`). `binding.remove()` is the per-binding
  teardown the presenter uses for the dynamic Adjust gate (`:1665-1669`). There is
  **no `system.dispose()`** — a destroyed context self-removes, so an abandoned
  system holds nothing but an empty list; acceptable.
- **Proof:** `tests/input.spec.luau` — "T1: a higher-priority Sink context blocks
  the lower context on the same key", "T2: disabling the high context releases the
  key to the lower one", "T3: a scriptable fire bypasses arbitration even under an
  active sink", "T4/dedup: repeated identical states are deduplicated like the
  engine", "T6a: firing a binding of a destroyed context is a silent no-op",
  "disabling a context resets held Bool state", "preferredBinding follows the
  preferred input kind and tolerates nil", "deviceKey tracks shift and ctrl/cmd
  modifier state". `tests/paradigm_input_axis.spec.luau` pins the axis latch and
  its Sink parity. Docs: `docs/reference/api.md:1690-1700`.
- **Findings:**
  - `[MINOR, H]` **`destroy` vs `dispose`: two public words for one concept.**
    `context.destroy()` (`src/input/actions.luau:218`) is the only teardown verb in
    the whole area not named `dispose` — cf. `root.dispose` (`src/mount.luau:563`),
    `controller.dispose` (`src/render/renderer.luau:2957`), `clock:dispose`
    (`src/motion/clock.luau:290`), `bus.dispose` (`src/present/feedback.luau:144`),
    `MotionValue:dispose` (`src/motion/motion.luau:113`). A third word,
    `binding.remove()` (`:97`), covers the same concept one level down, and
    `graph.remove(id)` (`src/focus/focus_graph.luau:608`) uses `remove` for
    something else entirely (a structural focus-order edit). User cost: an author
    guessing the teardown verb guesses wrong two-thirds of the time.
  - `[MINOR, H]` **`onPressed`/`onReleased` are typed `(fn: () -> ())` and always
    invoked with the value.** `function action.onPressed(fn: () -> ())` (`:34`)
    and `function action.onReleased(fn: () -> ())` (`:44`), but `_deliver` calls
    `fn(value)` (`:67`). Same class as `renderer` `onNodeTap`. User cost: the
    boolean the handler is handed is invisible to the type-checker and to the docs.
  - `[MINOR, H]` **Underscore-prefixed "internal" members on public objects.**
    `action._deliver` (`:55`) and `binding._sample` (`:137`) are reachable from any
    consumer holding an action, and `_deliver` is the *only* way an alternate input
    adapter delivers state (`src/client/roblox_input.luau` is a first-party
    consumer of it). User cost: an underscore is a convention, not a boundary —
    either it is the adapter seam and should be named as one, or it is private and
    the client adapter is violating it.
  - `[MINOR, M]` **`context.sink`/`.enabled`/`.priority` are public mutable fields
    beside setters that exist because field writes are dead on the real adapter.**
    `setSink`'s own comment (`:210-214`) says the headless model would tolerate a
    bare field write but the Roblox adapter would not. Nothing prevents the field
    write. User cost: the exact bug platform verifier P1 found (a field write that
    works headlessly and is dead live) is still writable.
  - `[MINOR, M]` **api.md documents 6 of ~18 members.** `docs/reference/api.md:1694-1699`
    lists `createContext`, `createAction`, `bind`, `onPressed`, `state`, `deviceKey`.
    Undocumented and load-bearing: `bindAxis` / `deviceAxis` (the entire analog
    path, which the presenter binds unconditionally at
    `src/present/presenter.luau:1594`), `system.modifiers()` (which the presenter
    reads for shift/toggle Activate semantics, `:2086-2089`), `onReleased`,
    `setSink`, `setEnabled`, `destroy`, `preferredBinding`, `binding.remove`.
  - `[NOTE, L]` `system` has no exported type; `createContext`'s spec is typed
    inline but `context` and `action` are anonymous tables.

---

### `LuauUI.inputHint` — reactive helper (dot function on a stateless module)

- **Shipped shape:** `hint.inputHint(core, env, action, opts?) -> Readable<string>`,
  `opts: { style: string? }?` where style is `"key"` (default) or `"phrase"`
  (`src/input/hint.luau:37-57`). Returns `core:memo(...)` (`:39`).
- **Pattern:** core-first pure-ish helper, opts last, returns a Readable. Matches
  `adaptive.conditions(core, env, opts?)` (`src/layout/adaptive.luau:164`) — the
  two reactive helpers in this area agree on argument order.
- **Callers:** examples/gallery (per the docs' own account at
  `src/input/hint.luau:30-33`); tests — `tests/hint_no_remount.spec.luau`. **No
  RascalRally caller** (`grep -rn "inputHint" games/RascalRally/code/src` → 0 hits).
- **Lifecycle:** X-2 spelling #3 — "The caller owns the returned memo (dispose it
  with the rest of the screen's resources, or via a scope)"
  (`src/input/hint.luau:16`), echoed at `docs/reference/api.md:1717` as
  `hint:dispose()`. No `opts.scope`, unlike its direct sibling
  `adaptive.conditions`.
- **Proof:** `tests/hint_no_remount.spec.luau` — "preferredInput flip updates the
  hint text prop only; zero factory reruns". Docs: `docs/reference/api.md:1701-1733`.
- **Findings:**
  - `[MINOR, H]` **Ownership spelling diverges from its nearest sibling for no
    stated reason.** `adaptive.conditions(core, env, opts?)` takes `opts.scope` and
    owns its memos (`src/layout/adaptive.luau:176-181`); `inputHint(core, env,
    action, opts?)` already has an `opts` table (`:37`) and does not. One memo vs
    twelve is a fair reason to care less, but it is not a reason for the *shape* to
    differ. User cost: a screen that owns its conditions by scope and its hints by
    hand has two disposal disciplines for two calls that look identical.
  - `[MINOR, M]` **`opts.style` is unvalidated and silently defaults.**
    `local style = if opts ~= nil and opts.style ~= nil then opts.style else "key"`
    then `if style ~= "phrase" then return label end` (`:38, :46`). `style =
    "Phrase"` silently yields the bare key label. Contrast `rootPolicy` /
    `cancelPolicy`, which error and list the legal set. `style: string?` is also
    not a union.
  - `[NOTE, L]` Return type is `any` (`:37`), not a `Readable<string>` type. The
    library has no exported `Readable<T>` — the same `any` appears on every
    reactive return in this area (`adaptive.Conditions`, `Bundle.keepVisibleOffset`,
    `presenter.exclusiveSurfaceActive`).

---

### `LuauUI.newFocusGraph` — service constructor (focus)

- **Shipped shape:** `focus_graph.new(core) -> graph` (`src/focus/focus_graph.luau:68`).
  Fields `focused` `:98`, `focusVisible` `:100`. Methods (all dot):
  `setFocusOrigin(kind)` `:104`, `focusOrigin()` `:113`, `pushScope(scope)` `:319`,
  `popScope()` `:328`, `removeScope(name)` `:346`, `navigateDirection(dir)` `:416`,
  `navigate(delta)` `:470`, `replaceGroups(scopeName, groups)` `:519`,
  `setOrder(name, order)` `:548`, `setGroupOrder(scopeName, groupName, order)` `:575`,
  `remove(id)` `:608`, `focusOn(path)` `:651`, `beginInteraction(id?)` `:670`,
  `endInteraction()` `:674`, `interactionTarget()` `:678`, `isFocusable(id)` `:683`,
  `activeScopeName()` `:687`. Exported types `OrderEntry` `:41`, `NavigationGroup`
  `:43-51`, `FocusScope` `:53-58`.
- **Pattern:** core-only constructor (no opts table), dot methods (X-1, dot side).
  Predicate-bearing order entries are a genuinely well-shaped extension:
  `OrderEntry = string | { id, focusable? }` keeps every bare-string caller working
  (`:41`, `:121-138`).
- **Callers:** internal — `src/present/presenter.luau:737` (the presenter builds
  exactly one and exposes it as `presenter.focus`), and drives
  `pushScope/setOrder/replaceGroups/removeScope/focusOn/setFocusOrigin/
  beginInteraction` throughout. tests — `tests/focus.spec.luau`,
  `tests/focus_skip.spec.luau`, `tests/focus_structural.spec.luau`,
  `tests/navigation_groups.spec.luau`. No direct RascalRally construction (`grep
  -rn "newFocusGraph" games/RascalRally/code/src` → 0); the game reaches it via
  `presenter.focus`.
- **Lifecycle:** **none declared.** `new` creates two `core:signal`s
  (`:70`, `:96`) unowned by any scope and the graph exposes no `dispose`. A scope
  disappears via `popScope`/`removeScope`; the graph itself never goes away.
  Compounding this, the presenter's two observers on it are not scope-owned:
  `core:observe(graph.focused, syncFocusVisuals)` (`src/present/presenter.luau:869`)
  and `core:observe(graph.focusVisible, …)` (`:873`) are bare calls whose
  unsubscribes are discarded.
- **Proof:** `tests/focus.spec.luau` — "navigates the screen ring and wraps at the
  edges", "modal traps navigation with wrap and restores previous focus on pop",
  "nested modals restore in LIFO order", "removing the focused item falls to the
  nearest surviving neighbor". `tests/focus_skip.spec.luau` pins the whole
  predicate + interaction-exemption contract, including "the predicate is re-read
  every navigation, never cached", "the interaction's target keeps its focusability
  while its predicate says no", "the exemption MOVES with the target: the graph
  holds exactly one", "removing the exempt node clears the exemption (it cannot
  protect a ghost)", "pointer focus REFUSES an ineligible node — but that is not
  refusing the tap". Docs: `docs/reference/api.md:1851-1904`.
- **Findings:**
  - `[MAJOR, H]` **`pushScope` mutates the caller's scope and group tables in
    place, and injects private fields into a public exported type.**
    `normalizeScope(scope)` writes `scope.order = normalizeOrder(...)` and
    `scope._focusable = sink` (`src/focus/focus_graph.luau:150-154`), and for a
    grouped scope writes `group.order = …` and `group._focusable = sink` into every
    element of the caller's `{ NavigationGroup }` array (`:144-149`). Later
    `graph.remove(id)` does `table.remove(order, i)` on that array
    (`:625`, `:639`) and `setGroupOrder` overwrites `(group :: any)._focusable`
    (`:588`). Neither `FocusScope` (`:53-58`) nor `NavigationGroup` (`:43-51`)
    declares `_focusable`/`_lastFocus`. User cost: (a) a caller who passes a
    `table.freeze`d group array — the library's own idiom for immutable data,
    e.g. `composition.ARRANGEMENTS` at `src/layout/composition.luau:202` — gets a
    hard error from inside the graph; (b) a caller who reuses one
    NavigationGroup literal across two surfaces has the two scopes share a
    predicate map; (c) after `pushScope`, the caller's own `order` array is no
    longer what the graph is using, so reading it back is stale. Nothing documents
    that the argument is consumed.
  - `[MAJOR, M]` **No `dispose`, and no scope argument.** `focus_graph.new(core)`
    (`:68`) is the only service constructor in the area that takes neither an opts
    table nor a scope and offers no teardown, while creating two long-lived core
    signals (`:70`, `:96`). Because the presenter that owns it also has no
    `dispose` (above), a presenter rebuild leaks both signals plus the two unscoped
    observers at `src/present/presenter.luau:869, 873`. Confidence M for the same
    reason as the presenter finding — it may be a deliberate session-scoped
    contract, written nowhere.
  - `[MINOR, H]` **`remove` is overloaded vocabulary.** `graph.remove(id)` removes a
    FOCUSABLE from the active scope's order (`:608`); `graph.removeScope(name)`
    removes a SCOPE (`:346`); `binding.remove()` in the sibling action system
    (`src/input/actions.luau:97`) is a teardown. Three public `remove`s, three
    meanings.
  - `[MINOR, M]` **The graph object and its scope argument are untyped.**
    `pushScope(scope: FocusScope)` is typed (`:319`) but `setOrder(name, order: { any })`
    (`:548`), `setGroupOrder(..., order: { any })` (`:575`) and
    `NavigationGroup.order: { any }` (`:46`) all take `{ any }` where the exported
    `OrderEntry` union (`:41`) is exactly the right type and exists three lines
    above. User cost: a typo'd `{ id = …, focsable = … }` is silently a
    permanently-eligible bare entry (`normalizeOrder` only reads `entry.focusable`
    if it is a function, `:132`).
  - `[NOTE, L]` `graph.focusOrigin()` (`:113`) and `graph.setFocusOrigin(kind)`
    (`:104`) — the getter is undocumented (api.md documents only the setter and
    `focusVisible`, `docs/reference/api.md:1878-1889`), and `kind: string` is not a
    union despite having exactly two legal values normalized at `:105`.

---

### `LuauUI.contribution` — module namespace (input-contribution seam)

- **Shipped shape:** `contribution.PROP: string = "inputContribution"`
  (`src/input/contribution.luau:99-100`), `contribution.attach(rootBlueprint,
  bundle) -> Blueprint` (`:106`), `contribution.read(node) -> Bundle?` (`:119`).
  `Bundle` is a fully-typed exported record of 13 optional fields (`:75-96`).
- **Pattern:** dot functions on a stateless module; `attach` is a
  `modifier: (blueprint, data) -> new frozen Blueprint`
  (`:109-115` returns `table.freeze`), which matches the blueprint-modifier family
  (`UI.corners`, `UI.shadow`) rather than a service. `read` is the type-guarded
  inverse (`:124-131`).
- **Callers:** internal — `src/present/presenter.luau:1360` (`collectContributions`
  walks the mounted tree), every composite control (`src/controls/*`).
  RascalRally — `games/RascalRally/code/src/client/LuauUISponsor/init.luau:1823`
  (`LuauUI.contribution.attach(hand.blueprint, {...})`), plus three injected uses
  at `.../ResultsScreen.luau:2873, 3393` and `.../TableScreen.luau:95`.
- **Lifecycle:** nothing to own — the bundle rides `bp.meta`, copied verbatim onto
  the mounted node (`src/mount.luau:492-494`). Binding lifetime is the presenter's:
  keyed on bundle identity in `boundBundles` (`src/present/presenter.luau:1378-1383`),
  re-discovered every refresh (`:1485-1523`), and a bundle whose region closes
  simply leaves the array.
- **Proof:** `tests/late_contributions.spec.luau` — "the region is closed at present
  time, so nothing of it is wired yet", "opening the region wires handleActivate —
  a REAL finger tap dispatches", "...and its one-time bindings run exactly once, on
  the frame it appears", "a LATE focusGroups upgrades the scope's navigation model
  (flat -> grouped)", "closing the region drops it again: a dispatch can never reach
  a dead control". `tests/paradigm_popup.spec.luau` pins the
  `handleCancel`/`outsideDismiss`/`transientScope` trio. Docs:
  `docs/reference/api.md:1816-1848`.
- **Findings:** this is the best-shaped item in the area — a typed record, a frozen
  return, a type-guarded read, and the widest live-caller proof. Two small ones:
  - `[MINOR, H]` **`PROP` is the wrong noun and it is undocumented.** The constant
    is named `PROP` (`:99-100`) but its own comment two lines up calls it "the
    reserved **metadata** key", and the module header spends eight lines explaining
    that the bundle rides `bp.meta` and specifically **not** the prop bag
    (`:12-20`). It also has 0 hits in `docs/reference/api.md` while sitting in the
    frozen public dump (`baseline/public-surface-before.txt:64`). User cost: an
    author reading the export name concludes the bundle is a prop and looks for it
    in the schema, which is exactly the confusion the design avoids.
  - `[NOTE, M]` `attach(rootBlueprint: any, bundle: Bundle): any` (`:106`) — the
    blueprint in and out are `any`, though `blueprintLib.Blueprint` is an exported
    type the module could name (`src/mount.luau:16` imports it). `read(node: any)`
    likewise. Only the `Bundle` half of this seam is typed.

---

### `LuauUI.motion` — namespace: `newClock`, class registry, `newValueReveal`

- **Shipped shape:** `motion = { newClock, registerClass, resolveClass, classNames,
  isRegisteredClass, resetClasses, newValueReveal }` (`src/init.luau:140-155`).
  - `newClock(core, opts?) -> Clock` (`src/motion/clock.luau:89`), `Opts = { now?,
    motionPolicy? }` (`:44-50`), `Clock` is a fully declared **colon-method** type
    (`:75-87`): `step, activeCount, stats, spring, counter, timer, chase, timeline,
    isReduced, dispose, isDisposed`. Plus an **undeclared** `lastError` (`:238`).
    `Stats = { steps, writes, transactions }` (`:52-73`).
  - Registry: `registerClass(name, params) -> Class` (`src/motion/classes.luau:134`),
    `resolve(name)` `:166`, `names()` `:97`, `isRegistered(name)` `:106`,
    `reset()` `:193` — dot functions on a **process-global** registry.
  - `newValueReveal(spec) -> Reveal` (`src/motion/value_reveal.luau:93`), typed
    `Spec` (`:58-66`), `Animator` (`:51-56`), `Cue` (`:68-81`), `Reveal` (`:83-91`)
    — colon methods `sync(cue)`, `landed()`, `rest()`.
  - Values built off the clock: `MotionValue` (`src/motion/motion.luau:109-124`),
    colon, with `onSettle(fn) -> unsubscribe` (`:116`) and `dispose` (`:113`).
- **Pattern:** colon-method objects (X-1, colon side) with a core-first clock
  constructor. `newValueReveal(spec)` matches the pure-model constructor shape its
  non-motion siblings use — `newDragVelocity(opts?)`
  (`src/input/drag_velocity.luau:42`, colon `tracker:push(x,y,t)` at `:57`) and
  `newAutoscroll(opts?)` (`src/input/autoscroll.luau:118`, colon `model:step(input)`
  at `:208`): one table argument, colon result, no core, injected time. **On the
  question the stage asked — does `newValueReveal`'s shape match its older
  siblings? — the answer is yes.**
- **Callers:** `newClock` internal at `src/present/presenter.luau:782` and
  `src/render/transitions.luau`; the client driver is
  `src/client/motion_driver.bind(presenter)` (`src/client/motion_driver.luau:35`).
  `newValueReveal` — RascalRally
  `games/RascalRally/code/src/client/LuauUISponsor/ResultsScreen.luau:3011` and
  `:3016` (two reveals, wired to `barFill:onSettle` / `coinCount:onSettle` at
  `:3023-3030`); no LuauUI-internal caller, no example caller.
  Registry — every `clock:spring/chase/timeline` call site.
- **Lifecycle:** clock is X-2 spelling #2: `scope:own(clock)`
  (`src/motion/clock.luau:287-289`); `dispose` releases every value it built
  (`:300-312`) and defers a mid-step dispose to the step tail (`:294-299`).
  `MotionValue:onSettle` returns an unsubscribe. **`newValueReveal` owns nothing** —
  no clock, no signals, stated at `src/motion/value_reveal.luau:45-46` — so `rest()`
  is a state reset, not a teardown, and there is nothing to leak. The class
  registry is process-global mutable state with `reset()` as its only teardown
  (`src/motion/classes.luau:193`).
  **The documented `motion_driver.bind` unbind footgun** (`src/client/motion_driver.luau:14-19`,
  `docs/reference/api.md:1739-1744`): the returned unbind is the caller's, nothing
  watches presenter lifetime, and `bound` keys presenters strongly — a discarded
  unbind keeps ticking and retaining a dead presenter. The gallery example takes
  exactly that risk: `motion_driver.bind(pres)` with the return discarded
  (`examples/gallery/client/init.client.luau:49`).
- **Proof:** `tests/motion_clock.spec.luau` — "commits every value in ONE
  transaction per stepped frame", "settled values leave the active set: rest costs
  zero steps and zero writes", "lands EXACTLY on the target and fires onSettle
  exactly once per flight", "refuses inline class params at the call site",
  "refuses an unknown motion kind", "a decorative value snaps to the target and
  fires the SAME settle event". `tests/runtime_quarantine.spec.luau:202`
  "transactions counts frames that really committed, never the aborted ones".
  `tests/value_reveal.spec.luau` — all ten: "a sync before the payload exists
  leaves the hold ALONE", "the animator holds the START value before anything reads
  it", "an explicit abandon releases, and cannot be restarted by a later cue", "a
  window already PAST releases instead of holding — the late-arrival path", "a
  window still COMING holds", "`rest` releases and rearms", "runs once, and a
  repeated cue is a no-op", "a NEW epoch rearms on the settled state of the last
  one", "with NO animator the fact is stated immediately, never held", "`landed`
  stops the count without re-holding". Docs: `docs/reference/api.md:3001-3178`.
- **Findings:**
  - `[MAJOR, H]` **`motion.newValueReveal` is entirely undocumented.**
    `grep -rn "newValueReveal" docs/` → 0 hits. It is in the frozen public dump
    (`baseline/public-surface-before.txt:79`), has a first-party consumer
    (`games/RascalRally/.../ResultsScreen.luau:3011`) and a ten-case spec, and no
    reference entry. **The drift check cannot catch this**: `check_registration`
    only scrapes TOP-LEVEL `LuauUI` keys (`tools/lune/check_registration.luau:161-163`,
    `for key in string.gmatch(initSource, "\n\t(%w+) = ")`) and never descends into
    the `motion` table — `motion` itself is documented, so the check passes
    (verified: `lune run tools/lune/check_registration_cli` → PASS, exit 0). User
    cost: the shape exists specifically so nobody re-hand-rolls it, and the only
    way to discover it is to read `src/init.luau`.
  - `[MINOR, H]` **api.md contract lie: `transactions` always equals `steps`.**
    `docs/reference/api.md:3044` states "`clock:stats()` — `{ steps, writes,
    transactions }` for leak and perf assertions; `transactions` always equals
    `steps`." The source's own `Stats` doc says the invariant is
    `transactions <= steps` and records a measurement of "30 steps under a
    persistently throwing live target -> 0 transactions"
    (`src/motion/clock.luau:56-71`), and `tests/runtime_quarantine.spec.luau:222-233`
    pins `stats.transactions == 0` with 30 steps. User cost: a consumer writing the
    leak assertion the doc suggests (`transactions == steps`) has written a test
    that fails the moment a `pre`/`advance` callback throws — i.e. exactly in the
    scenario worth asserting on.
  - `[MINOR, H]` **`clock.lastError()` is public but absent from the exported
    `Clock` type and from api.md.** Defined at `src/motion/clock.luau:238`,
    described there as "RR-1's instrument"; the `Clock` type at `:75-87` lists 11
    members and not this one; 0 hits for `lastError` in api.md's motion section.
    User cost: the diagnostic that explains a wedged clock is invisible to both the
    type-checker and the reader.
  - `[MINOR, M]` **`newValueReveal` sits in `motion` while its structural twins sit
    at top level.** `LuauUI.newDragVelocity` / `LuauUI.newAutoscroll` /
    `LuauUI.newDragSession` are top-level (`src/init.luau:117-119, 101`); the
    identically-shaped `newValueReveal` is namespaced (`:154`). It is also the only
    member of `motion` that is neither the clock nor part of the class registry, and
    the only motion primitive **not** built from a clock (`clock:spring`,
    `clock:counter`, `clock:timer`, `clock:chase`, `clock:timeline` are all clock
    methods — `src/motion/clock.luau:260-285`). Defensible (it owns no clock, so it
    cannot be a clock method), but it means `LuauUI.motion` now holds three
    unrelated shapes: one constructor, five registry functions, one free model.
  - `[MINOR, M]` **The motion-class registry is process-global with no ownership
    story.** `registerClass`/`reset` mutate module state (`src/motion/classes.luau:134,
    193`) shared by every core, presenter and clock in the process. api.md documents
    re-registering a built-in as "the sanctioned ±30 % tuning dial"
    (`docs/reference/api.md:3066-3068`) without saying that a second game/surface in
    the same VM sees it. Same class as the `text_metrics` global state below.
  - `[NOTE, M]` `newClock(core, opts?)`'s `Opts.motionPolicy: any?` (`:49`) and
    `Clock.spring(..., class: any, ...)` (`:79`) are `any` where the library has
    real types (`Readable<string>` does not exist; `classes.Class` at
    `src/motion/classes.luau:34` does).
  - `[NOTE, L]` `value_reveal`'s `Spec.held`/`Spec.counting` are typed as
    `{ set: (self, boolean) -> () }` (`src/motion/value_reveal.luau:61-62`) — a
    structural subset of a Signal rather than the Signal type. Correct minimalism,
    but it is the only place in the area that types a reactive collaborator
    structurally instead of as `any`; worth noting as the *better* pattern.

---

### `LuauUI.adaptive` — module namespace (layout decisions)

- **Shipped shape:** pure — `sizeClass(width, opts?)` `:78`, `heightClass(height,
  opts?)` `:94`, `orientationFor(w, h)` `:109`, `axisFor(width, opts?)` `:124`,
  `columnsFor(available, minColumnWidth, gap?)` `:132`; data — `BREAKPOINTS` `:36`,
  `HEIGHT_BREAKPOINTS` (**the same table**, `:57`), `DEFAULT_STACK_ABOVE` `:62`;
  reactive — `conditions(core, env, opts?) -> Conditions`
  (`src/layout/adaptive.luau:164`) returning 15 keys / 12 memos (`:204-235`).
  Types `ClassOpts` `:64-68`, `AxisOpts` `:119-121`, `Conditions` `:142-159`.
- **Pattern:** dot functions on a stateless module for the pure half;
  `(core, env, opts?)` core-first for the reactive half — the same order
  `inputHint` uses. Value-first-then-opts is consistent across all five pure
  functions.
- **Callers:** internal — `src/env/environment.luau` (`sizeClass` memo, per the
  comment at `:30-35`), `UI.AdaptiveStack`. RascalRally —
  `games/RascalRally/code/src/client/LuauUISponsor/init.luau:737` and `:1370`, both
  correctly passing `{ scope = scope }`; consumed as an injected `conditions` in
  `.../StoryFlow.luau:73` and `.../TableScreen.luau:54`.
  tests — `tests/adaptive.spec.luau`.
- **Lifecycle:** X-2 spelling #1 — `opts.scope` owns the memos
  (`src/layout/adaptive.luau:170-181`); omitted, the caller owns twelve memos by
  hand. The RR-8 leak that motivated it is written into the source comment
  (`:170-175`) and api.md (`:1776-1789`).
- **Proof:** `tests/adaptive.spec.luau` — "classifies width into compact / regular
  / wide at the documented breakpoints", "a ten-foot display never resolves the
  densest class, however wide it is", "tolerates a nonsense width instead of
  producing a nonsense class", "exposes the class and its boolean tests as
  Readables", "re-resolves live when the viewport changes, with no remount",
  "sizeClass answers exactly what it answered before the height half landed",
  "**opts.scope owns ALL of them, so the height half cannot leak**", "a rotation
  maps a class pair onto its mirror". Docs: `docs/reference/api.md:1734-1794`.
- **Findings:**
  - `[MINOR, H]` **`opts.scope` is not in any exported type and is read through a
    cast.** The signature is `opts: (AxisOpts & { scope: any? })?`
    (`src/layout/adaptive.luau:164`) — an inline intersection — and the body reads
    `(opts :: any).scope` twice (`:177-178`). `AxisOpts` (`:119-121`) declares only
    `stackAbove`. User cost: the single most important argument in the function (it
    is what stops a twelve-memo leak) is not discoverable from the exported types,
    and the `:: any` means a rename would not be caught.
  - `[MINOR, H]` **`contentWidth` and `viewportWidth` are the same value under two
    public names** (`:218-219`, both `= contentWidth`), documented as an
    intentional back-compat alias (`:212-217`, `docs/reference/api.md:1762`). This
    is textbook duplicate vocabulary: `contentWidth` is a *wrong* name for a value
    that does not subtract insets, kept alive so callers do not break. Flagging for
    the deprecation-vs-exception call; there is no `DEPRECATIONS` entry for it
    (`baseline/public-surface-before.txt:154-157` lists only the two `UI.Text`
    rows).
  - `[MINOR, M]` **`HEIGHT_BREAKPOINTS` is literally `BREAKPOINTS`** (`:57`,
    `adaptive.HEIGHT_BREAKPOINTS = adaptive.BREAKPOINTS`) — one frozen table under
    two public names. Deliberate and well-argued (`:46-52`, and the spec pins it:
    "BREAKPOINTS and DEFAULT_STACK_ABOVE are the same numbers"), but a consumer who
    mutates or compares by identity gets a surprise, and it means the two names can
    never diverge without a breaking change.
  - `[MINOR, M]` **Every one of `Conditions`' 15 fields is typed `any`**
    (`:142-159`) with the real type in a trailing comment
    (`sizeClass: any, -- Readable<"compact" | "regular" | "wide">`). User cost:
    `use(conditions.axis)` type-checks against anything, including a typo'd key.
    Root cause is the absent `Readable<T>` export, which is a library-wide gap
    worth raising once at the constitution level.
  - `[NOTE, L]` `ClassOpts.distanceProfile: string?` (`:67`) is another
    non-union string enum with two legal values.

---

### `LuauUI.composition` — module namespace (declared-content adaptive composition)

- **Shipped shape:** `resolve(decl, offer, ctx) -> Resolution`
  (`src/layout/composition.luau:1513`), `normalize(decl) -> Declaration` `:372`,
  `dump(resolution)` `:1634`, `floorPx(floor, metrics) -> number?` `:227`,
  `arrangementOf(value) -> Arrangement` `:317`, `ARRANGEMENTS` (frozen presets)
  `:202`. Types: `Floor` `:101`, `GroupDecl` `:110`, `RegionDecl` `:124`,
  `Arrangement` `:137`, `Declaration` `:142`, `Offer`/`Rect` `:152-153`,
  `MeasureFn` `:156`, `ResolveCtx` `:157`, `RegionResolution` `:165`,
  `Resolution` `:178`.
- **Pattern:** dot functions on a stateless, pure module; **construction-strict
  validation** throughout (`normalize` and `arrangementOf` `fail(...)` with the
  legal set and a did-you-mean, `:326-329`, `:361-365`) — the strictest and
  best-typed item in the area. `resolve(decl, offer, ctx)` is subject-first with
  the collaborator table last, matching `mount(core, blueprint, opts)`.
- **Callers:** internal — the solver publishes per-node dumps that surface as
  `controller.compositionAt(path?)` (`src/render/renderer.luau:2939-2944`);
  declaration face is `UI.Composition` / `UI.Region`. RascalRally uses the
  declaration face, not the pure module directly
  (`games/RascalRally/code/src/client/LuauUISponsor/ResultsScreen.luau:114, 266`).
  tests — `tests/composition.spec.luau`.
- **Lifecycle:** pure; nothing to own. `normalize` is idempotent via a
  `__normalized` marker (`:376-378`) and returns frozen output, so calling it per
  solve is free.
- **Proof:** `tests/composition.spec.luau` — "a short wide offer resolves the
  richest arrangement (landscape phone)", "a tall narrow offer falls to the column,
  and SAYS why the lanes lost", "the choice follows the OFFER, not a viewport: the
  same width decides differently by height", "Q9: with twoLane withheld, an offer
  that fails threeLane falls to the column", "when NO candidate is legal the LAST
  one shows, flagged as the declared fallback", "a lane that overflows steps its
  LEAST important region down first". Docs: `docs/reference/api.md:1795-1815`.
- **Findings:**
  - `[MINOR, H]` **`Arrangement.eligible` is validated, read and documented in
    prose, but absent from the exported type.** `arrangementOf` type-checks it and
    names it in the legal-fields error (`src/layout/composition.luau:340-346, 362-363`);
    `resolve` reads `(arr :: any).eligible` (`:1549`) and reports an `ineligible`
    rejection; the `Arrangement` type is `{ name, lanes }` only (`:137-140`). User
    cost: an author writing a strict custom arrangement with `eligible` gets a type
    error for a field the runtime explicitly accepts.
  - `[MINOR, H]` **`Resolution.hugOverflow` is dumped but not typed.**
    `composition.dump` emits `hugOverflow = resolution.hugOverflow or {}` (`:1689`,
    dated 2026-08-02) and `Resolution` (`:178-195`) does not declare it. User cost:
    the authoring diagnostic the field exists to carry is invisible to a typed
    reader of `resolve`'s return.
  - `[NOTE, M]` `resolve(decl: any, …)` and `normalize(decl: any)` and
    `arrangementOf(value: any)` take `any` on the way in (`:1513`, `:372`, `:317`)
    while returning fully-typed values. Defensible for a validator (the whole point
    is to accept malformed input and rule on it), and the trade is explicitly the
    strict-validation pattern — recording it as a justified exception rather than a
    defect.
  - `[NOTE, L]` `floorPx(floor, metrics: any)` (`:227`) takes the theme snapshot as
    `any`; `themes.resolve` produces a real snapshot type elsewhere in the library.

---

### `LuauUI.text` — module namespace (measurement + fit), NEW 2026-08-02

- **Shipped shape:** `text = { measure = text_metrics.measure, fit = text_fit.fit,
  size = text_fit.size }` (`src/init.luau:170-174`).
  - `measure(text, font, fontSize, maxWidth, lineHeight?, maxLines?) -> Metrics`
    — **six positional arguments** (`src/layout/text_metrics.luau:447-454`);
    `Metrics = { width, height, lines, naturalLines, truncated, state, exact,
    requestKey?, error? }` (`:172-191`).
  - `fit(spec: FitSpec) -> Fit` (`src/layout/text_fit.luau:75`) and
    `size(spec: FitSpec) -> number` (`:109`) — **one spec table**;
    `FitSpec = { text, font, cap, width, height?, lines?, lineHeight?, floor? }`
    (`:40-54`), `Fit = { size, fits, lines, height, exact }` (`:56-62`).
- **Pattern:** dot functions on a stateless module — except the module is **not**
  stateless (see findings). `fit`/`size` follow the spec-table pattern; `measure`
  does not.
- **Callers:** internal — `src/render/renderer.luau:18` (the solver's measure
  seam), `src/layout/text_fit.luau:65, 82`. RascalRally — `LuauUI.text.size` at
  `games/RascalRally/code/src/client/ItemFx.luau:95` and threaded as an injected
  `M.textFit` through `.../ResultsModels.luau:31`, `.../ResultsParts.luau:42, 413`,
  `src/shared/HudZoneModel.luau:86`; `LuauUI.text.measure` at
  `.../ResultsParts.luau:907`. No `examples/` caller.
- **Lifecycle:** no per-call resource — but `text_metrics` carries **module-global
  mutable state**: the calibration table, the exact-width store (`EXACT_CAP = 8192`,
  `src/layout/text_metrics.luau:137`) and the collect queue
  (`collecting`, `:164`; `COLLECT_CAP = 1024`, `:166`). Ownership is
  process-wide and there is no scope or reset in the public namespace
  (`resetCalibration` `:87` / `resetMeasured` `:306` / `beginCollect` `:243` /
  `endCollect` `:250` are NOT exported through `LuauUI.text` — correctly, but that
  leaves the state unownable by a consumer).
- **Proof:** `tests/text_fit.spec.luau` — "returns the cap untouched when the
  string already fits at it", "the answer FITS and the next size up does NOT —
  verified against the measurer", "a box that cannot hold the string at its floor
  says `fits = false`", "honours a HEIGHT constraint as well as a width", "is
  monotone: a wider box never returns a smaller size", "an empty string is a fit at
  the cap, and a zero-width box never errors", "reports whether the answer is EXACT
  or the conservative fallback". `measure` is pinned indirectly by
  `tests/text_premeasure.spec.luau` and the solver specs. **Docs: none.**
- **Findings:**
  - `[MAJOR, H]` **The entire `LuauUI.text` namespace is undocumented.**
    `grep -rn "text\.fit\|text\.measure\|text\.size" docs/` → 0 hits; there is no
    `### \`text\`` heading in api.md. It is in the frozen public dump
    (`baseline/public-surface-before.txt:132-135`) and has five first-party
    RascalRally call sites. **The drift check passes vacuously**: it does
    `string.find(apiMd, "`" .. export .. "`")` as a fallback
    (`tools/lune/check_registration.luau:190`), and the bare token `` `text` ``
    appears 5 times in api.md as the `UI.Text` **prop** name — so the export named
    `text` collides with an unrelated documented token and the check reports PASS
    (verified: `lune run tools/lune/check_registration_cli` → PASS, exit 0). User
    cost: the very defect the export exists to prevent — three private copies of a
    guessed 0.62 glyph constant in one consumer
    (`src/layout/text_fit.luau:7-18`) — recurs for the next consumer, because
    nothing in the reference tells them the real measurer is reachable.
  - `[MAJOR, H]` **Two argument conventions inside one three-function namespace.**
    `text.measure` is six positional arguments with two trailing optionals
    (`src/layout/text_metrics.luau:447-454`); `text.fit`/`text.size` take a single
    spec table (`src/layout/text_fit.luau:75, 109`). Both were exported in the same
    commit (`src/init.luau:163-174`, dated 2026-08-02). User cost:
    `text.measure(s, font, 18, 200)` and `text.size{ text = s, font = font, cap =
    18, width = 200 }` are the same question asked two ways, and a caller who
    learns one cannot guess the other. `measure`'s shape is inherited from its life
    as a solver-internal; that is a reason, not a justification, and it is the
    clearest candidate in this fragment for a compatible additive repair (a spec
    overload) or an explicit recorded exception.
  - `[MINOR, M]` **`text.fit` has an undocumented side effect on the renderer's
    premeasure budget.** `fit` binary-searches ~log2(cap) sizes, each calling
    `measure` (`src/layout/text_fit.luau:65, 95`), and `measure` → `wordWidth`
    enqueues an engine-measurement request for every unmeasured word **while a
    collect window is open** (`src/layout/text_metrics.luau:337-345`), capped at
    `COLLECT_CAP = 1024` (`:166`) shared with the solver's own round. A consumer
    calling `text.fit` from inside a `presenter.onTick` hook during a solve can
    therefore consume the surface's premeasure budget with words at sizes nothing
    will ever paint. Confidence M: the mechanism is proven by the code path, the
    live impact is not measured.
  - `[MINOR, M]` **`Fit` drops the `state` the `Metrics` it is derived from
    carries.** `Metrics.state` is `"ready" | "pending" | "failed"`
    (`src/layout/text_metrics.luau:186`); `Fit` keeps only `exact`
    (`src/layout/text_fit.luau:56-62`). A caller of `fit` cannot tell "the font is
    uncalibrated" from "an engine measurement failed" — `exact = false` covers both.
  - `[NOTE, M]` `text.measure` exposes exactly one of `text_metrics`' 12 public
    module functions; the other eleven (calibration, the collect window, the
    measured store) stay internal and are reachable only through
    `require("…/layout/text_metrics")`. That is the right boundary, but it means an
    adapter author implementing the premeasure seam is on the internal-import path
    the boundary checker otherwise forbids — the same argument that made
    `contribution` public (`src/init.luau:64-69`).
  - `[NOTE, L]` `Metrics.state` IS a proper string union (`:186`) while
    `FitSpec`/`Fit` carry no enums at all — no inconsistency, recorded only because
    it shows the library can express unions where it chooses to.

---

## Coverage

Every assigned item has an entry above:

| Assigned item | Entry | Findings |
|---|---|---|
| `LuauUI.mount` | ✔ | 2 (NOTE ×2) |
| `LuauUI.renderer` (module + `attach` + full Controller, 27 members enumerated) | ✔ | 8 (MAJOR 1, MINOR 5, NOTE 2) |
| `LuauUI.newPresenter` (incl. PresentOpts, ToastOpts, PresenterOpts, handle, feedback taxonomy, SURFACE_LAYER, topScrimPath, exclusiveSurfaceActive) | ✔ | 11 (MAJOR 3, MINOR 7, NOTE 1) |
| `LuauUI.newActionSystem` | ✔ | 5 (MINOR 4, NOTE 1) |
| `LuauUI.inputHint` | ✔ | 3 (MINOR 2, NOTE 1) |
| `LuauUI.newFocusGraph` (scopes, groups, predicates, interaction exemption) | ✔ | 5 (MAJOR 2, MINOR 2, NOTE 1) |
| `LuauUI.contribution` (attach/read/PROP + Bundle) | ✔ | 2 (MINOR 1, NOTE 1) |
| `LuauUI.motion` (newClock, class registry, spring/counter/timer/chase/timeline, newValueReveal) | ✔ | 7 (MAJOR 1, MINOR 4, NOTE 2) |
| `LuauUI.adaptive` | ✔ | 5 (MINOR 4, NOTE 1) |
| `LuauUI.composition` | ✔ | 4 (MINOR 2, NOTE 2) |
| `LuauUI.text` (measure + fit + size) | ✔ | 6 (MAJOR 2, MINOR 3, NOTE 1) |
| Cross-cutting: colon-vs-dot (X-1), ownership spellings (X-2) | ✔ | recorded as X-1 / X-2 |

**Totals: 58 findings — 9 MAJOR, 34 MINOR, 15 NOTE. 0 CRITICAL.**

Items in this area that follow their pattern with no deviation worth a finding
(recorded as successes, not omissions): the **unsubscribe-closure convention** —
`action.onPressed`/`onReleased`, `presenter.onFeedback`/`onTick`/`onModalPresented`,
`handle.onFeedback`, `controller.observeScroll`, `MotionValue:onSettle`,
`feedback.bus.subscribe` all return a plain `() -> ()` and nothing else, with
`controller.attachDragDetector` the one flagged exception; **core-first argument
order** — `mount(core, …)`, `renderer.attach(core, …)`, `presenter.new(core, …)`,
`newActionSystem(core)`, `inputHint(core, env, …)`, `newFocusGraph(core)`,
`motion.newClock(core, …)`, `adaptive.conditions(core, env, …)` are uniform with
no exception; **`newValueReveal`'s constructor shape** vs `newDragVelocity` /
`newAutoscroll` — asked by the stage plan, answered: it matches (single table
argument, colon-method result, injected collaborators, no clock);
**`contribution`** as the best-typed seam in the area.

### Public-but-unassigned, found while auditing (reported, not audited in depth)

- `presenter.toastCounts()`, `presenter.syncPopupCatcher()`,
  `presenter.topPopupCatcherPath()`, `presenter.feedbackTypes`
  (`src/present/presenter.luau:2561, 1079, 1091, 760`) — reachable on the instance
  the public API hands out, undocumented; flagged in the `newPresenter` entry but
  they were not in the assignment list.
- `src/present/feedback.luau`'s `Bus` (`subscribe`/`emit`/`count`/`dispose`,
  `:65-70`) and `feedback.TYPES`/`TYPE_LIST` (`:50-51`) — reachable as
  `presenter.feedbackTypes` and via `handle.onFeedback`; the `Event` type
  (`:53-63`) is the taxonomy's real declaration and carries the stale
  supersede-as-reason comment.
- `src/client/motion_driver.bind(presenter) -> unbind`
  (`src/client/motion_driver.luau:35`) — client-only, deliberately off the public
  `LuauUI` table (not in `baseline/public-surface-before.txt`) yet documented as
  public API (`docs/reference/api.md:1739-1744`) and reached by internal require in
  `examples/gallery/client/init.client.luau:48`. It is the canonical "feature
  usable only via internal import" in this area, sanctioned by the client-entry-point
  rule (`src/init.luau:1-6`); recorded here so the lead can rule on whether a
  documented-but-unexported surface belongs in the ledger's scope.
- `src/render/transitions.luau` `.new{ core, clock, metrics, feedback }` — api.md
  instructs a bare `mount` + `renderer` consumer to build one via
  `require("…/render/transitions")` (`docs/reference/api.md:1258-1260`), i.e. the
  docs prescribe an internal import for a documented capability. Same class as the
  point that made `contribution` public.
- `tools/lune/check_registration.luau:161-190` — not a public export, but the
  enforcement check for the `enforcement-checks` gate row. Its two defeats
  (top-level-keys-only; token-collision fallback) are evidenced in the
  `motion.newValueReveal` and `LuauUI.text` findings and are the mechanical reason
  two whole namespaces shipped undocumented under a green gate.
