# Surface ledger — REACTIVE CORE AND STATE SERVICES

Area: `LuauUI.newCore`, `LuauUI.newEnvironment`, `LuauUI.replication`,
`LuauUI.newResourceProvider`, `LuauUI.valueModel`.
Baseline: `artifacts/api-architecture-consistency/baseline/public-surface-before.txt`
(VERSION 0.7.0). All evidence read this session; line numbers are as-shipped.

Shorthand used below: **LIB** = library root
`GameStudio/ui/LuauUI`, **GAME** = `games/RascalRally/code/src`.

---

### `LuauUI.newCore` (+ the whole Core object surface) — constructor / stateful object

- **Shipped shape:** `LuauUI.newCore = customCore.new` (`src/init.luau:46`), which is
  `factory.new = Custom.new` (`src/core/custom.luau:452-460`), a **zero-argument dot
  function** returning a plain table built at `src/core/custom.luau:337-447`:
  - public field `name = "custom"` (`custom.luau:338`; typed `contract.Core.name`,
    `src/core/contract.luau:57`)
  - `core:signal(initial, eq?) -> Signal` (`custom.luau:340-356`)
  - `core:memo(compute, eq?) -> Memo` (`custom.luau:358-374`)
  - `core:observe(source, onChange) -> Unsubscribe` (`custom.luau:376-398`)
  - `core:effect(run) -> Unsubscribe` (`custom.luau:400-418`) — **runs `run(use)`
    immediately at registration** (`custom.luau:403`)
  - `core:transaction(body)` (`custom.luau:420-430`) — `pcall(body)`, decrement,
    flush at depth 0, then **re-`error(err, 0)`**
  - `core:flush()` (`custom.luau:432-434`) — no-op if already flushing (`:240-242`)
  - `core:scope(label?) -> Scope` (`custom.luau:436-438` → `scope_impl.factory`)
  - `core:counters() -> { signals, memos, observers, effects, scopes }`
    (`custom.luau:440-442`, cloned)
  - `core:lastError() -> string?` (`custom.luau:444-446`)
  - Readable object (`custom.luau:294-335`): `{ kind, _node, get(self), set(self,v),
    dispose(self) }`. `set` on a memo asserts `"cannot set a memo"` (`:306`).
  - Scope object (`src/core/scope_impl.luau:50-124`): `own`, `use`, `child`,
    `dispose`, `isDisposed` — colon methods on a metatable.
  - Types: `src/core/contract.luau:19-83` (`Unsubscribe`, `Signal<T>`, `Memo<T>`,
    `Readable<T>`, `Use`, `Scope`, `Counters`, `Core`, `CoreFactory`).
- **Pattern:** "colon methods on a stateful object", owner-held Signal state,
  quarantine-everything error containment (every user callback is `pcall`-wrapped:
  `eq` at `custom.luau:72-79`, memo compute at `:109`, observer at `:231`, effect at
  `:148`, scope cleanup at `scope_impl.luau:85-104`) with a single diagnostic channel
  (`fail` → `lastError`, `custom.luau:59-61`). Argument order: required-first,
  optional-last, **positional** optional (`eq`), no opts table.
- **Callers:** LIB — every module takes `core` as its first parameter (35 hits of
  `core: any` across `src/`); `src/mount.luau:198,369,508` observe authored props;
  `src/render/renderer.luau:2288,2406,2424,2448` observe env keys.
  examples — `examples/gallery/client/init.client.luau:26`,
  `examples/table_phaseb/client/init.client.luau:21`.
  GAME — `client/GaragePilotGui.luau:33`, `client/LuauUIRacerListGui.luau:37`,
  `client/LuauUISettingsGui.luau:77`, `client/LuauUISponsor/init.luau:411` (with an
  injectable `newCore: (() -> any)?` seam at `:190`), `core:scope("LuauUISponsor")`
  at `:458`.
- **Lifecycle:** the caller owns the core; **there is no `core:dispose()`**. Scopes
  are the only teardown seam and a root scope from `core:scope()` is owned by nobody
  (`scope_impl.luau:45-48` sets `parent = nil`) — it leaks `counters.scopes` if the
  caller forgets. Signals/memos/effects/observers are individually disposable;
  `counters()` returning to baseline is the leak test. GAME disposes its scope
  (`LuauUISponsor/init.luau:2684`) but never the core or the env.
- **Proof:** `tests/conformance/suite.luau`, driven by
  `tests/conformance/conformance.spec.luau:15` `"core conformance (custom)"` — cases
  `signal-read-write` (:26), `memo-derives-and-updates` (:35),
  `transaction-batches-observer-to-one-fire` (:50), `glitch-free-diamond` (:71),
  `equal-write-skipped` (:102), `custom-equality-respected` (:115),
  `dynamic-dependencies-swap-atomically` (:134), `cycle-reported-not-hung` (:164),
  `write-during-memo-is-error` (:191),
  `effect-runs-post-commit-and-writes-schedule-later-round` (:209),
  `feedback-loop-hits-iteration-cap` (:236), `memo-error-quarantined` (:255),
  `scope-dispose-reverse-order-idempotent` (:282),
  `child-scope-disposed-with-parent-borrowed-not-disposed` (:305),
  `memory-neutral-churn` (:328), `no-spurious-fire-on-unchanged-recompute` (:359),
  `mid-transaction-derived-reads-fresh` (:383),
  `transaction-revert-produces-no-fire` (:399), `nan-equal-write-skipped` (:417),
  `scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose` (:447),
  `double-dispose-detected` (:484), `observer-disposed-by-sibling-does-not-fire`
  (:499), `observer-added-mid-flush-fires-next-flush-only` (:525),
  `disposed-observer-never-fires` (:550). Plus `tests/fuzz_scheduler.spec.luau:18`
  and the `core-eq-quarantine` / `scheduler-feedback` / `teardown` fault scenarios
  (`tests/lib/fault_scenarios.luau:605,611,623`).
  Docs: `docs/reference/api.md:41-88`.
- **Findings:**

  - `[MAJOR, H]` **`lastError()` is monotonic and can never be cleared, but the
    contract promises "nil when healthy".** `lastError` is a closure upvalue assigned
    only by `fail` (`src/core/custom.luau:54,59-61`); nothing ever resets it, and no
    `clearError`/`takeError` exists on the Core surface (`custom.luau:337-447`).
    `src/core/contract.luau:68-69` states "last quarantined error string …, **nil when
    healthy**" — false for the entire remaining life of a core after any single
    quarantine, including deliberate ones. Cost: `core:lastError()` is the library's
    own health assertion (`tests/chip.spec.luau:100`,
    `tests/examples_gallery.spec.luau:67,92`, `tests/theme_authoring_scenario.spec.luau:164`
    and 5 more all assert `toBeNil()`), so a consumer copying that idiom into a
    long-running client gets a permanently-red health signal after the first
    recovered fault, and cannot tell a fresh error from a stale one.

  - `[MAJOR, H]` **`core: any` / `scope: any` at every public boundary while the
    typed contract sits unreachable.** `src/core/contract.luau` exports `Core`,
    `Scope`, `Counters`, `Use`, `Unsubscribe`, `Signal<T>`, `Memo<T>` — and
    `grep 'contract\.(Core|Signal|Memo|Readable|Scope|Counters|Use|Unsubscribe)' src/`
    outside `src/core/` returns **nothing**; the only re-export is
    `blueprint.Readable<T>` (`src/blueprint.luau:52-54`). `src/init.luau` never
    requires `core/contract`, so `Core`/`Scope` are not reachable from the public
    entry at all. Meanwhile `src/` has 35 `core: any` and 19 `scope: any` parameters,
    including all five items in this area (`environment.new(core: any)`
    `env/environment.luau:88`; `adapters.snapshot/collection/mutation(core: any, …)`
    `replication/adapters.luau:18,47,105`; `resources.newProvider(core: any, …)`
    `async/resources.luau:76`; `provider.acquire(scope: any, …)` `:225`). Cost: an
    author writing a typed helper (`function build(core: ???, …)`) has no name to
    write and no way to import one; typos in a core-shaped argument are runtime
    errors instead of analysis errors, and the checked-in contract is decorative.

  - `[MAJOR, H]` **The `_node` back-channel: `Signal<T>`/`Memo<T>` are structural
    types the runtime does not actually accept.** `contract.Signal<T>` /
    `Memo<T>` (`contract.luau:21-32`) declare only `kind`/`get`/`set`/`dispose` —
    no `_node`. The public predicate `UI.isReadable` duck-types on exactly that
    (`src/blueprint.luau:327-330`: `v.kind == "signal" or v.kind == "memo"`). But
    `use()` and `observe()` reach for a private field: `local dep = source._node`
    at `custom.luau:105`, `:144`, `:378`. `src/mount.luau:504-508` calls
    `isReadable(value)` and then `core:observe(value, …)` on the same value. Cost: a
    hand-rolled or wrapped Readable (an adapter over a Roblox `ValueBase`, a test
    double, a lazily-computed façade) type-checks, passes the library's own public
    predicate, is accepted as a bound prop — and then dies at mount with
    "attempt to index nil with 'kind'". There is no exported factory or interface
    that would let a consumer produce a legal Readable other than `core:signal` /
    `core:memo`.

  - `[MINOR, H]` **`transaction` promises atomicity its implementation does not
    provide.** `core:transaction(body)` (`custom.luau:420-430`) `pcall`s the body,
    then flushes at depth 0 **and then** re-raises. Writes made before the throw are
    already in `node.value` and `writeSet`; there is no snapshot and no rollback
    anywhere in the file. It is a *batching* primitive named after an *atomic* one.
    `docs/reference/api.md:68-69` says only "batches writes; observers/effects fire
    once at the end" and never mentions error behaviour. Cost: a consumer who reaches
    for "transaction" for the reason the word exists gets a half-applied state
    commit with observers fired on it. No spec pins error-inside-transaction
    (`grep -c 'transaction(function' tests/` = 6, none with a throwing body).

  - `[MINOR, H]` **`scope:use` is a documented-nowhere public no-op, and reuses a
    word the core already owns.** `Scope.use(self, resource)` returns the resource
    and does nothing (`scope_impl.luau:56-59`); it *is* in the public type
    (`contract.luau:42`) but is absent from `docs/reference/api.md:72-75`, which
    lists only `own`/`child`/`dispose`/`isDisposed`. Its only caller anywhere is the
    conformance case that pins it (`tests/conformance/suite.luau:311`, case
    `child-scope-disposed-with-parent-borrowed-not-disposed`). Separately, `use` in
    this API means "borrow, do not dispose", while `use` in `memo(function(use) …)`
    means "read and subscribe" (`contract.luau:36-38`) — one public word, two
    unrelated meanings, in the same object graph.

  - `[MINOR, H]` **`scope:own` silently accepts and ignores anything without a
    `dispose`.** `Scope.own` inserts whatever it is handed (`scope_impl.luau:50-54`);
    `Scope.dispose` calls a function, recurses into a child Scope, calls
    `resource:dispose()` **if `resource.dispose ~= nil`**, and otherwise falls
    through with no diagnostic (`scope_impl.luau:85-101`). The library's own shipped
    scenario does exactly this: `examples/gallery/scenarios/sponsor_avatars.luau:48`
    writes `scope:own(LuauUI.newResourceProvider(core, {…}))`, and the provider table
    has no `dispose` member at all (`src/async/resources.luau:101,480`). Cost: the
    ownership statement reads as correct, reviews as correct, and does nothing. This
    is the accepted-but-ignored class, in the framework's own example.

  - `[MINOR, M]` **Disposing a signal with live dependents silently freezes them.**
    `dispose` clears `node.subs` (`custom.luau:317`) so dependents are never
    invalidated again, and `pull` short-circuits for a disposed node
    (`custom.luau:85-87`), so every downstream memo keeps serving the last value
    forever with no error and no `lastError`. Symmetrically, `signal:set` on a
    disposed signal succeeds silently (`custom.luau:305-308` → `write`, whose
    `subs`/`observers` are now empty). `docs/reference/api.md:52-55` documents
    `signal:dispose()` with no semantics at all. Cost: a teardown-ordering mistake
    presents as stale UI rather than as an error.

  - `[MINOR, H]` **Error-message prefixes are inconsistent inside one object.**
    `"LuauUI: writing state during memo evaluation is an error"` (`custom.luau:177`)
    and `"LuauUI cycle: …"` (`:94`) carry a prefix; `"cannot set a memo"` (`:306`),
    `"cannot own into a disposed scope"` (`scope_impl.luau:51`) and
    `"cannot create a child of a disposed scope"` (`:64`) do not. Cost: a consumer
    grepping their own logs for `LuauUI` misses three of the five ways this area
    throws.

  - `[MINOR, H]` **api.md omits `effect`'s most surprising semantic and the public
    `core.name` field.** `core:effect` runs its body *immediately* at registration
    (`custom.luau:403`) — `contract.luau:62` says so, `docs/reference/api.md:65-67`
    ("like observe but dependency-tracked") does not, and `observe` explicitly does
    NOT fire on registration (`custom.luau:381-388` baselines `lastSeen` instead).
    `core.name` (`custom.luau:338`, `contract.luau:57`) appears nowhere in api.md.

  - `[MINOR, M]` **Two public words for "stop listening".** `observe` returns an
    `Unsubscribe` and api.md calls it `unsubscribe` (`api.md:61`); `effect` returns
    the same `Unsubscribe` type (`contract.luau:63`) and api.md calls it `dispose`
    (`api.md:65`). Together with `Signal:dispose()`, `Scope:dispose()` and (in
    resources) `handle.release()`, this area ships four spellings of teardown.

  - `[NOTE, H]` `eq` is a positional optional second argument on both `signal` and
    `memo` (`custom.luau:340,358`) where the rest of the library puts optional
    configuration in a trailing opts table (`newProvider(core, opts?)`,
    `motion.newClock(core, opts?)` `src/motion/clock.luau:89`,
    `newPresenter(…, opts?)` `src/present/presenter.luau:735`). Defensible for a
    one-option hot path; recording it as a deliberate divergence, not a defect.

  - `[NOTE, H]` The 100-round feedback cap **discards** the pending write set and
    continues (`custom.luau:247-256`), reporting only through `lastError`.
    `docs/reference/api.md:66-67` calls this "trips a 100-round cap loudly" — it is
    as loud as `lastError` is, which given the monotonic-`lastError` finding above
    is quieter than the word implies. Likewise `core:flush()` inside a flush is a
    silent no-op (`custom.luau:240-242`), undocumented.

---

### `LuauUI.newEnvironment` — constructor / stateful object

- **Shipped shape:** `LuauUI.newEnvironment = environment.new` (`src/init.luau:53`)
  → `environment.new(core: any): Env` (`src/env/environment.luau:88`). Returns
  `env :: any` (`:305`) with three colon methods (`:281-303`):
  `env:get(key: string) -> any` (a Readable; asserts on an unknown key),
  `env:set(key: string, value: any)` (asserts on unknown **or derived**),
  `env:keys() -> { string }` (facts **and** derived, sorted, merged).
  `export type Env` at `:14-18`.
  **Fact keys** (`FACT_DEFAULTS`, `:20-86`): `viewportRect`, `deviceSafeInsets`,
  `coreSafeInsets`, `topbarInset`, `topbarSafeInsets`, `keyboardOcclusionRect`
  (nil-defaulted, hand-created at `:96`), `preferredInput`, `capabilities`,
  `reducedMotion`, `preferredTextSize`, `preferredTextOffset`,
  `preferredTransparency`, `locale`, `displaySize`, `overscanInsets`,
  `presentationSpace`, `themeMetrics`.
  **Derived memos** (`:102-277`): `typographyScale`, `typographyPaintScale`,
  `effectiveTransparency`, `sizeClass`, `motionPolicy`, `distanceProfile`,
  `effectiveOverscanInsets`, `presentationProfile`, `interactionClasses`,
  `effectiveInput`.
- **Pattern:** core-first constructor; "colon methods on a stateful object"
  (consistent with Core/Scope); per-key owner-held Signal state; derived-clamps-
  garbage policy in the memos.
- **Callers:** LIB — `src/render/renderer.luau:2288,2406,2424,2448`;
  `src/present/presenter.luau`; the client adapter `src/client/roblox_env.luau`
  pushes facts through `set`. examples —
  `examples/gallery/client/init.client.luau:27`,
  `examples/table_phaseb/client/init.client.luau:22`,
  `examples/gallery/scenarios/runner.luau:290` (a second billboard env on the same
  core). GAME — `client/GaragePilotGui.luau:34`, `client/LuauUIRacerListGui.luau:38`,
  `client/LuauUISettingsGui.luau:78`, `client/LuauUISponsor/init.luau:412`,
  `client/LuauUISponsor/OmenState.luau:145`; reads at
  `LuauUISponsor/init.luau:765,1215-1218,1330,1335,2101` and
  `OmenState.luau:121,146,149`.
- **Lifecycle:** **undefined.** `environment.new` allocates ~17 signals + 10 memos on
  the passed core and returns an object with **no `dispose`** and no scope parameter;
  nothing in `src/` or GAME ever tears one down. The runner even builds a *second*
  env on an existing core (`scenarios/runner.luau:290`) with no story for the first.
  GAME builds a fresh core+env per sponsor presenter (`LuauUISponsor/init.luau:411-412`)
  and disposes only its own scope (`:2684`), so 27 core registrations per session are
  never returned to baseline; they die only when the whole core is collected.
- **Proof:** the `accessibility` fault scenario (`tests/lib/fault_scenarios.luau:339-367`,
  registered at `:640`, run by `tests/faults.spec.luau:16` "fault injection (seeded,
  deterministic)") asserts `typographyScale` and `effectiveTransparency` stay in
  their legal domain under garbage facts; the `input-switch` scenario (`:652`) and
  `tests/adaptive.spec.luau:1058,1065,1071,1077` pin `interactionClasses.primary`,
  and `:1086` `"effectiveInput speaks the platform fact's vocabulary, resolved"`.
  `tests/adaptive.spec.luau:63-189` pins `sizeClass`/`displaySize` behaviour.
  Docs: `docs/reference/api.md:1654-1684`.
- **Findings:**

  - `[MAJOR, H]` **Eight public keys are documented nowhere, and production uses
    two of them.** Grepping all of `docs/` returns **zero** hits for
    `effectiveOverscanInsets`, `preferredTextOffset` and `overscanInsets`;
    `coreSafeInsets`, `deviceSafeInsets`, `presentationSpace`, `presentationProfile`
    and `typographyPaintScale` appear only in ADRs, plans, research notes or the
    device-verification guide — **never in `docs/reference/api.md`**, whose
    `newEnvironment` entry (`api.md:1658-1668`) lists 11 facts and 6 derived keys
    against the 17 + 10 that ship. GAME already depends on two of the undocumented
    ones: `env:get("coreSafeInsets")` (`LuauUISponsor/init.luau:1218`) and
    `env:set("presentationSpace", "billboard")` (`OmenState.luau:149`). Cost: the
    key *is* the API — an author cannot discover `overscanInsets`,
    `preferredTextOffset` or `effectiveOverscanInsets` at all without reading
    `src/env/environment.luau`, which is exactly the internal-import boundary the
    library forbids elsewhere.

  - `[MINOR, H]` **The "garbage facts clamp" promise is true only of derived keys.**
    `docs/reference/api.md:1665-1666`: "Garbage facts clamp into legal domains
    instead of leaking." `env:set` performs no validation whatever
    (`environment.luau:287-291`); only the derived memos clamp
    (`:102-131,132-143,165-198`). `env:get("viewportRect")` returns whatever was
    pushed, and `src/render/renderer.luau` and the solver read raw facts. Cost: an
    author reading that sentence believes a bad adapter is contained at the seam;
    it is contained only on the derived half.

  - `[MINOR, H]` **`env:keys()` mixes settable and unsettable keys with no way to
    tell them apart, and has no proof.** `keys()` merges `signals` and `derived`
    (`environment.luau:293-303`); `set` on any of the 10 derived names asserts
    (`:289`). There is no `factKeys()`/`isDerived()`. Grepping `tests/`, `src/`,
    `examples/` for `env:keys()` returns **no callers and no test** — the only hit
    in the repo is the api.md sentence documenting it (`api.md:1667`). A public
    method with zero proof and a built-in footgun.

  - `[MINOR, H]` **`Env.get`/`Env.set` are `any` on both sides.** `export type Env`
    (`environment.luau:14-18`) types `get` as `(self, key: string) -> any` and `set`
    as `(self, key: string, value: any) -> ()`. The key space is a closed set of ~27
    literals and the return is always a `Readable`, but neither is expressed; and the
    `Env` type is not re-exported from `src/init.luau`, so a consumer cannot name it
    even as-is. Cost: `env:get("veiwportRect")` is a runtime assert, and
    `env:get("themeMetrics"):get()` (GAME `LuauUISponsor/init.luau:1330`) has no
    type behind either call.

  - `[MINOR, M]` **`FACT_DEFAULTS` cannot express a nil-defaulted fact, and the
    workaround is a hand-written line.** `keyboardOcclusionRect = nil` at
    `environment.luau:44` never appears in the `for key, default in FACT_DEFAULTS`
    loop (`:92-94`) because Lua tables do not store nil; the key exists only because
    of the explicit `signals.keyboardOcclusionRect = signals.keyboardOcclusionRect or
    core:signal(nil)` at `:96`. The declaration table therefore is not the registry
    it looks like. Cost: the next nil-defaulted fact is added to `FACT_DEFAULTS`,
    silently does not exist, and `env:get` asserts.

  - `[MINOR, M]` **No env teardown, undocumented ownership.** See Lifecycle above.
    Nothing in api.md says who owns the env's ~27 core registrations or whether an
    env may outlive/precede a scope. Cost: `core:counters()` — the library's own
    leak instrument — can never return to zero on a client that built an env, so the
    "lifecycle-neutral code returns them to baseline" claim (`api.md:76-77`) is
    unusable at the application level.

  - `[NOTE, H]` `environment.new` declares `: Env` and returns `env :: any`
    (`environment.luau:88,305`), so the declared return type is not actually checked
    against the constructed table.

---

### `LuauUI.replication` (`snapshot` / `collection` / `mutation`) — namespace of dot factories

- **Shipped shape:** `LuauUI.replication = require("@self/replication/adapters")`
  (`src/init.luau:17,189`). Three dot factories, **zero exported types** in the file:
  - `replication.snapshot(core, initialRevision, initialData)` →
    `{ binding: Signal, ingest(rev, data) -> "applied"|"stale"|"duplicate",
    revision() -> number }` (`src/replication/adapters.luau:18-42`)
  - `replication.collection(core, initialRevision, initialItems, requestResnapshot)` →
    `{ binding, ingestPatch(rev, patch) -> "applied"|"stale"|"duplicate"|"gap",
    ingestResnapshot(rev, items) -> "applied"|"stale", revision() }`
    (`:47-100`)
  - `replication.mutation(core, opts?)` where
    `opts = { optimistic: { apply: (any) -> (), restore: () -> () }? }?` →
    `{ status: Signal, lastResult: Signal, send(payload, expectedRevision?) -> envelope,
    confirm(requestId, result), reject(requestId, reason), reset() }` (`:105-176`)
- **Pattern:** core-first factory returning a **dot-function** object (not colon —
  diverges from Core/Scope/Env); "returned verb string" outcome reporting
  (`"applied"`/`"stale"`/`"duplicate"`/`"gap"`), shared with the resource provider's
  `"applied"`/`"stale"`. Idempotent, id-matched responses.
- **Callers:** examples — `examples/gallery/examples/03_settings_sync.luau:33,44`;
  `examples/gallery/client/init.client.luau:699,702`. GAME —
  `client/GaragePilotGui.luau:51` (`snapshot`) and `:55` (`mutation(core, nil)`),
  with a hand-written one-in-flight guard at `:66-68`.
- **Lifecycle:** **no `dispose` on any of the three.** `snapshot` allocates 1 signal,
  `collection` 1, `mutation` 2 — all on the passed core, none scope-owned, none
  releasable. `requestResnapshot` is a caller-supplied callback held for the object's
  life. Neither api.md nor `docs/guide/06-client-server.md` says who owns them.
- **Proof:** `tests/replication.spec.luau` — `"applies newer, ignores stale and
  duplicate revisions"` (:14), `"applies in-order patches, ignores stale/dup"` (:26),
  `"gap requests one resnapshot, refuses patches until it lands, then converges"`
  (:40), `"reconnect = resnapshot from any newer authoritative revision"` (:60),
  `"optimistic apply reconciles on confirm via authoritative ingest"` (:70),
  `"rejection restores optimistic state; duplicate responses are idempotent"` (:96),
  `"confirm racing ahead of the snapshot cannot leave permanent divergence"` (:123),
  `"send while pending is a structured error, not silent corruption"` (:151),
  `"the envelope carries requestId and expectedRevision for server validation"` (:163),
  `"independent environments and presentation state converge on the same semantics"`
  (:173). Plus `tests/fuzz_replication.spec.luau:19,33`.
  Docs: `docs/reference/api.md:2105-2127`; `docs/guide/06-client-server.md:35-140`.
- **Findings:**

  - `[MAJOR, H]` **A resnapshot at the client's current revision wedges the
    collection permanently, and the guide promises the opposite.**
    `ingestResnapshot` returns `"stale"` for `newRevision <= revision` and returns
    *before* clearing the flag (`adapters.luau:85-90`), so `awaitingResnapshot`
    stays `true`. Every later `ingestPatch` then hits the
    `if awaitingResnapshot or …` branch, and because the branch only calls
    `requestResnapshot` `if not awaitingResnapshot` (`:65-70`), **no second
    resnapshot is ever requested** — the collection returns `"gap"` forever with no
    public reset (there is no `resync`/`rebase`/`reset` on the object, `:47-100`).
    `docs/guide/06-client-server.md:63-64` states "When the full set arrives via
    `ingestResnapshot`, the adapter catches up and resumes accepting patches", and
    `:67-68` "feed the client a fresh `ingestResnapshot` at whatever revision the
    server is now at, and it re-bases cleanly." Both are false for the exactly-equal
    case, which is the natural answer to `requestResnapshot(fromRevision)` when
    nothing has changed since the gap (`:68` passes the *current* revision). Cost:
    a live leaderboard/inventory stops updating for the rest of the session with no
    error surfaced. No test covers an equal-revision resnapshot — the only three
    `ingestResnapshot` call sites in `tests/` (`replication.spec.luau:52,63`,
    `lib/fuzzers/replication.luau:76`) all use a strictly newer revision.

  - `[MAJOR, H]` **A throwing `optimistic.apply` wedges the mutation permanently.**
    `send` sets `activeRequestId` and `status:set("pending")` and *then* calls
    `opts.optimistic.apply(payload)` **unquarantined** (`adapters.luau:124-129`).
    If `apply` throws, `send` never returns, so the caller **never receives the
    envelope** and therefore never learns the `requestId`; `reset()` is a no-op while
    pending (`:168-173`); a second `send` throws "one in flight" (`:117-121`);
    `confirm`/`reject` require the id the caller does not have (`:135`, `:156`).
    The mutation is unrecoverable. Cost: one bad line in a UI-draft `apply` — the
    most consumer-authored code in the adapter — permanently disables the control.
    Contrast the core, which quarantines *every* user callback
    (`custom.luau:72-79,109,148,231`).

  - `[MAJOR, H]` **A throwing `requestResnapshot` wedges the collection
    permanently.** `awaitingResnapshot = true` is set *before* the unquarantined
    `requestResnapshot(revision)` call (`adapters.luau:66-70`). A throw propagates
    out of `ingestPatch` with the flag already latched, and the `if not
    awaitingResnapshot` guard means the hook is never invoked again — the recovery
    request was never actually made, and never will be. Same class as the two above:
    the state services keep none of the core's quarantine discipline. Cost: a
    transient error in the game's remote-fire path silently converts a recoverable
    gap into a dead collection.

  - `[MINOR, H]` **One word, two meanings across siblings: an equal revision is
    `"duplicate"` in two entry points and `"stale"` in the third.**
    `snapshot.ingest` (`:29-31`) and `collection.ingestPatch` (`:62-64`) both return
    `"duplicate"` for `newRevision == revision`; `collection.ingestResnapshot`
    returns `"stale"` (`:86-88`). `docs/reference/api.md:2116-2120` documents
    `ingestPatch`'s four verbs and **does not document `ingestResnapshot`'s return
    values at all**. Cost: a transport that branches on `"duplicate"` to mean
    "harmless, ignore" and `"stale"` to mean "we are behind, resync" does the wrong
    thing on the one call where recovery depends on it — and this is the mechanism
    behind the MAJOR above.

  - `[MINOR, H]` **`mutation.reset()` is a silent no-op exactly when a caller needs
    it.** `if status:get() ~= "pending" then … end` (`adapters.luau:168-173`) — a
    mutation stuck pending (server never answered, or the `apply` throw above)
    cannot be reset, and `reset` reports nothing. `docs/reference/api.md:2124` lists
    `.reset()` with no qualification; `docs/guide/06-client-server.md:87` says
    "return an idle mutation to a clean state", which describes the case where the
    call already does nothing useful. Cost: the obvious recovery verb is the one
    that does not recover; the actual escape is `reject(id, "timeout")`, which is
    documented as the server's verdict, not as a client escape hatch.

  - `[MINOR, H]` **`restore` is one callback name doing two different jobs.** It is
    called on `confirm` (`:148`) *and* on `reject` (`:161`). On reject it genuinely
    restores; on confirm it is a *reconcile from authoritative truth*, which the
    code has to explain in an eight-line comment (`:140-147`) and the guide has to
    explain again in a paragraph (`docs/guide/06-client-server.md:114-115,135-140`).
    A single callback whose meaning depends on which terminal state invoked it.

  - `[MINOR, H]` **`requestResnapshot` is a required callback in a bare 4th
    positional slot.** `collection(core, initialRevision, initialItems,
    requestResnapshot)` (`:47-52`) — every other callback in this area lives in an
    opts table (`mutation`'s `opts.optimistic`, `resources`' `opts.now`) or is a
    trailing observer argument. It also breaks the `on*` naming used everywhere else
    for consumer callbacks (`onChange`, `onActivate`, `onPressed`).

  - `[MINOR, M]` **Return-shape drift: three names for "the Readable this object
    publishes."** `snapshot`/`collection` publish `.binding` (`:22,57`); `mutation`
    publishes `.status` and `.lastResult` (`:110-111`); the resource handle publishes
    `.state`/`.value`/`.error` (`resources.luau:254-259`). No shared vocabulary, and
    nothing marks which fields are Readables versus plain data
    (`envelope.requestId` is plain, `mutation.status` is a Signal).

  - `[MINOR, M]` **Verb drift within the collection:** `snapshot.ingest` vs
    `collection.ingestPatch` / `collection.ingestResnapshot`. Three spellings of one
    verb across two objects; `snapshot.ingest` is really "ingestSnapshot" and could
    have been the same word `collection.ingestResnapshot` uses.

  - `[MINOR, M]` **`nextRequestId` is module-global, shared across every mutation
    and every core.** `local nextRequestId = 0` sits at file scope
    (`adapters.luau:104`), outside the factory. Request ids are therefore globally
    unique but **not reproducible per core** — a headless run's ids depend on how
    many mutations any earlier test constructed. `tests/replication.spec.luau:163-171`
    deliberately only asserts `type(envelope.requestId) == "number"`, which reads as
    a test written around this. Low harm today; a determinism hazard for a
    replay/fingerprint fixture.

  - `[MINOR, H]` **No exported types at all.** `src/replication/adapters.luau` has
    zero `export type` declarations (verified by grep across all five area files) —
    no `Snapshot`, `Collection`, `Mutation`, `Envelope`, `MutationOpts`, `Patch`.
    `patch` is `any` (`:61`), `initialItems` is `{ [any]: any }` (`:50`), the
    optimistic callbacks are `(any) -> ()` (`:105`). GAME even calls
    `LuauUI.replication.mutation(core, nil)` (`GaragePilotGui.luau:55`) — an explicit
    nil for an optional it cannot name.

  - `[MINOR, M]` **No validation of `initialRevision` or an ingested revision.**
    Nothing checks that revisions are numbers or non-negative
    (`adapters.luau:19,29-34,48,62`); a `nil` revision produces a raw Lua comparison
    error from inside the adapter rather than a named LuauUI diagnostic. Contrast
    `value_model.new`, which is construction-strict (`value_model.luau:62-70`).

  - `[NOTE, H]` Dot-function objects here versus colon-method objects in Core/Env.
    Ruled "docs-acceptable" historically
    (`docs/research/2026-07-20-phase4-architecture-verifier-findings-resolution.md:17`
    "colon-call convention"), but no doc states the rule, so a reader has only the
    per-entry examples to go on. Recorded for the lead, not asserted as a defect.

---

### `LuauUI.newResourceProvider` — constructor / stateful object

- **Shipped shape:** `LuauUI.newResourceProvider = asyncResources.newProvider`
  (`src/init.luau:130`) → `resources.newProvider(core: any, opts: ProviderOpts?)`
  (`src/async/resources.luau:76`). `ProviderOpts` (`:45-56`) =
  `{ maxConcurrent: number? = 4, cacheBudget: number? = 16, retryAttempts: number? ,
  retry: RetryOpts?, now: (() -> number)? = os.clock }`; `RetryOpts` (`:39-43`) =
  `{ count: number?, delaySeconds: number?, giveUp: boolean? }`; `Retry` (`:33-37`)
  is the resolved triple. Provider is a **dot-function** object (`:101,480`):
  - `provider.acquire(scope, key, opts?: { retry: RetryOpts? }) -> handle`
    (`:225-283`); `handle = { key, state: Signal<"pending"|"ready"|"failed">,
    value: Signal, error: Signal, release() }` (`:254-279`), auto-registered with
    `scope:own(handle.release)` (`:280`)
  - `provider.preload(keys: { string }, opts?) -> { keys, release }` (`:416-453`)
  - `provider.pendingRequests() -> { { key, generation, attempt } }` (`:286-297`)
  - `provider.complete(key, generation, value) -> "applied"|"stale"` (`:300-321`)
  - `provider.fail(key, generation, message) -> "retrying"|"failed"|"stale"` (`:324-378`)
  - `provider.tick()` (`:383-408`), `provider.invalidate(key)` (`:457-467`),
    `provider.gaveUp(key) -> boolean` (`:471-473`),
    `provider.counters() -> { handles, active, queued, cached, staleRejected, dropped }`
    (`:97,475-478`)
- **Pattern:** core-first + opts-last constructor; pull-based transport (no
  callbacks at all — the transport drains `pendingRequests()`); generation-checked
  staleness; returned verb strings sharing `"applied"`/`"stale"` with replication —
  **a genuine cross-module vocabulary win**; scope-owned handles; injected clock.
- **Callers:** LIB — `src/controls/async_image.luau` (via `newAsyncImage`),
  `src/client/roblox_resources.luau:58-64` (the Heartbeat drain).
  examples — `examples/gallery/scenarios/async_images.luau:17`,
  `examples/gallery/examples/07_match3.luau:171` (`{ maxConcurrent = 8 }`),
  `examples/gallery/scenarios/sponsor_avatars.luau:48` (`scope:own(...)`, `retry =
  { count = 3, delaySeconds = 1 }`, injected `now`).
  tests — `tests/async_completeness.spec.luau`, `tests/async_image.spec.luau`,
  `tests/virtualization.spec.luau:233`, `tests/lib/fault_scenarios.luau:46-175`,
  `tests/examples_games.spec.luau:361`. **No RascalRally caller** (verified by grep
  over `GAME`).
- **Lifecycle:** handles are scope-owned (`:280`) and refcounted per key
  (`stateFor`/`releaseState`, `:140-173`); releasing the last waiter of a wave
  cancels the request (`:260-279`). **The provider itself has no `dispose`** — its
  cache, `gaveUp` map, `waiting` list and per-key signals live as long as the
  closure. **Preload handles are NOT scope-owned** (`:416-453` takes no scope): the
  caller must call `release()` by hand.
- **Proof:** `tests/async_completeness.spec.luau` — `"a failure retries up to
  `count` times and then reports failed"` (:67), `"a retry that succeeds resolves
  normally, and the failed attempt stays stale"` (:85), `"a spaced retry is invisible
  to the transport until its delay has elapsed"` (:97), `"releasing the last waiter
  cancels a retry that is still waiting out its delay"` (:110), `"a spent budget
  fails the key, and a later acquire does not start it over"` (:123), `"invalidate is
  the explicit reset"` (:139), `"the LEGACY retryAttempts option keeps its old
  promise: a failed key re-requests"` (:151), `"a per-acquire retry overrides the
  provider's policy for that key"` (:162), `"preloads exactly the keys it was handed,
  under the same concurrency window"` (:173), `"a released preload skips work that
  has not started"` (:181), `"a warmed key is already ready when the view finally
  acquires it — no placeholder"` (:192), `"a live view keeps a preloaded request
  alive after the warm set is released"` (:203). Plus the `async-fixed` /
  `async-storm` fault scenarios (`tests/lib/fault_scenarios.luau:585,593`) and
  `tests/async_image.spec.luau:50,62,74`.
  Docs: `docs/reference/api.md:2056-2101`.
- **Findings:**

  - `[MINOR, H]` **`preload` handles are not scope-owned while `acquire` handles
    are, and nothing says so.** `acquire` calls `scope:own(handle.release)`
    (`resources.luau:280`); `preload(keys, opts?)` takes no scope and returns a bare
    `{ keys, release }` (`:435-452`). `docs/reference/api.md:2082-2087` describes
    preload as "an acquire without a view: **the same requests, the same concurrency
    window, the same generations**" and explains what `release()` does — but never
    says the caller now owns calling it. Cost: an author who reads that sentence
    reasonably assumes the same ownership story; a forgotten release keeps a wave
    alive, so the request survives the view that wanted it and burns a concurrency
    slot for the session.

  - `[MINOR, H]` **`retryAttempts` and `retry` are two public words for one concept,
    with the legacy one outside the deprecation ledger.** Both live in the same
    `ProviderOpts` (`:48-54`), the source calls one "the LEGACY spelling", and they
    differ in semantics (immediate vs spaced, re-request vs permanent give-up)
    resolved by a precedence rule in `resolveRetry` (`:62-74,80-84`).
    `LuauUI.DEPRECATIONS` (baseline lines 154-156) contains only `UI.Text.color` and
    `UI.Text.font` — `retryAttempts` is not in it, so ADR-0011's machinery does not
    know about it and no removal date exists. Cost: two live spellings forever, and
    a reader of api.md:2062-2081 must hold both models in their head.

  - `[MINOR, H]` **Construction validation posture contradicts the sibling in this
    very area.** `maxConcurrent = (opts and opts.maxConcurrent) or 4` (`:77`) — in
    Lua `0` is truthy, so `maxConcurrent = 0` is accepted and `promote()` (`:130-138`)
    can never activate anything: every request queues silently forever. `cacheBudget
    = 0` (`:78`) makes `evictOverBudget` (`:123-128`) drop each value the instant it
    is cached. Negatives are accepted for both. In `resolveRetry`, a negative
    `count` or `delaySeconds` is **silently discarded** back to the fallback
    (`:68-71`) rather than reported. Contrast `value_model.new`, four files away in
    the same public surface, which raises named errors for an impossible range or a
    non-positive step (`value_model.luau:62-70`). Cost: a typo'd option produces a
    UI that loads nothing, with no diagnostic anywhere — not even `core:lastError()`.

  - `[MINOR, H]` **`provider.counters()` keys are undocumented.**
    `docs/reference/api.md:2101` names the method and stops; the shipped shape is
    `{ handles, active, queued, cached, staleRejected, dropped }`
    (`resources.luau:97`). `core:counters()` **is** fully enumerated in api.md
    (`:76-77`) — sibling drift in how a counters surface is documented.

  - `[MINOR, M]` **A released key's Readables are disposed under any reference the
    caller still holds.** When the last handle releases, `releaseState` disposes the
    shared `state`/`value`/`error` signals (`:161-173`). A consumer who copied
    `handle.state` into a blueprint prop keeps a disposed Signal that (per the core
    finding above) silently serves its last value forever. Nothing in api.md
    (`:2066-2068`) says the handle's Readables die with the handle.

  - `[MINOR, M]` **`invalidate` does not reset live per-key state.** It clears
    `cache`, `gaveUp` and the LRU entry (`:457-467`) but never touches
    `keyState[key]`, so a handle held across an `invalidate` keeps reading
    `state = "ready"` with a value the provider no longer has. Recovery depends on a
    *new* `acquire` happening to flip it (`:242-247`). `api.md:2100` says only "drops
    the cached value AND any session give-up".

  - `[MINOR, L]` **The module header documents a method name that does not exist.**
    `src/async/resources.luau:7-8`: "It drains `provider.pending()` … and answers
    with `provider.complete/fail(key, generation, ..)`." The shipped name is
    `pendingRequests()` (`:286`). Internal prose only — but this header is the first
    thing an extension author reads.

  - `[NOTE, H]` `resources.newProvider` → `LuauUI.newResourceProvider` is the only
    `new*` export in this area whose module-side name is not `.new`
    (`environment.new`→`newEnvironment`, `focus_graph.new`→`newFocusGraph`,
    `Custom.new`→`newCore`, `presenter.new`→`newPresenter`). Cosmetic.

  - `[NOTE, M]` `provider.fail`'s third parameter is `message` in code (`:324`) and
    `err` in api.md (`:2097`); `handle.error` shadows the Lua builtin's name. Both
    trivial, both recorded for completeness.

  - `[NOTE, H]` **Follows the pattern, no deviation:** the `"applied"`/`"stale"`
    verb vocabulary is genuinely shared with `replication` (`resources.luau:300,324`
    vs `adapters.luau:28,61,85`), the generation/staleness contract is pinned by
    tests, retry policy is call-site-overridable in the same `{ retry = RetryOpts }`
    shape at both `acquire` (`:229-231`) and `preload` (`:418-420`), and the clock is
    injected rather than yielded. This is the best-specified item in the area.

---

### `LuauUI.valueModel` — namespace of pure dot functions

- **Shipped shape:** `LuauUI.valueModel = require("@self/controls/value_model")`
  (`src/init.luau:90`) — a **table**, not a function, exporting
  `valueModel.new(spec: Spec) -> Model` (`src/controls/value_model.luau:61`) and
  `valueModel.defaultFormat(v: number) -> string` (`:47-59`).
  `Spec` (`:17-24`) = `{ min: number, max: number, step: number?,
  format: ((value: number) -> string)? }`.
  `Model` (`:26-39`, returned at `:121-140`) = data `{ min, max, step }` plus the dot
  functions `clamp`, `quantize`, `stepped(value, direction)`, `fraction`,
  `fromFraction`, `format`, `semanticText`, `atMin`, `atMax`.
  Construction-strict: non-finite bounds, `max <= min`, and a non-positive/non-finite
  `step` all raise named `LuauUI value control: …` errors at level 0 (`:62-70`).
- **Pattern:** "dot functions on a stateless module" + "construction-strict
  validation". No core, no scope, no Instances — the only item in this area that
  takes neither a core nor an opts table, correctly so (the header states the rule at
  `:9-13`: the owner holds the value Signal, this owns the arithmetic).
- **Callers:** LIB — `src/controls/slider.luau`, `src/controls/stepper.luau`,
  `src/controls/progress_view.luau` (all three via `valueModel.new`);
  `tests/conformance/controls_registry.luau`. examples/GAME — **no direct caller**
  (verified by grep over `examples/` and `GAME`); reached only through
  `newSlider`/`newStepper`/`newProgressView`.
- **Lifecycle:** none needed. The `Model` is a frozen-by-convention closure bundle
  with no reactive state, no core registration and nothing to dispose; the value
  Signal is owner-held by the calling control. Zero leak surface.
- **Proof:** `tests/value_controls.spec.luau`, describe block `"B-VAL1: the shared
  value model"` (:22) — `"clamps to its bounds"` (:23), `"quantizes onto a grid
  measured FROM min, so the bounds are reachable"` (:30), `"a non-integer grid still
  lands exactly on the bounds"` (:39), `"stepping always makes progress and never
  leaves the range"` (:46), `"a continuous model steps by a fraction of the range"`
  (:57), `"fraction and fromFraction round-trip through the grid"` (:63),
  `"formats without noise and never prints negative zero"` (:71), `"a custom
  formatter is honoured everywhere the value is shown"` (:79), `"semantic value text
  states the value IN ITS RANGE"` (:91), `"a NaN or infinite value resolves to the
  low bound instead of propagating"` (:96), `"an impossible range or step is a build
  error, not a silent degradation"` (:103). Cross-control tie-down:
  `"shares the value model with Stepper: identical bounds arithmetic"` (:595).
  Docs: `docs/reference/api.md:2581-2592`.
- **Findings:**

  - `[MINOR, H]` **`valueModel.defaultFormat` is a public export with zero
    documentation, and it is not the same function as `model.format`.** The baseline
    lists it (`public-surface-before.txt:152`); `grep -c defaultFormat
    docs/reference/api.md` = **0**, and the `valueModel` entry (`api.md:2583-2586`)
    enumerates only the `Model` members. Worse, the two differ: `model.format(v)`
    clamps first (`value_model.luau:130-132`), `valueModel.defaultFormat(v)` does not
    (`:47-58`). Cost: a consumer who found the export (e.g. to format a legend to
    match a Slider) gets un-clamped output and a silent mismatch at the bounds.

  - `[MINOR, M]` **`spec.format` is the one user callback in this area that is not
    quarantined.** It is called raw inside `format` (`:130-132`) and `semanticText`
    (`:115-119`), which are themselves called from the render path of Slider and
    Stepper. A throwing formatter unwinds a solve. The core quarantines its
    equivalent (`eq`, `custom.luau:72-79`) precisely so a user predicate cannot
    unwind a writer. Lower stakes than the replication wedges (a formatter is
    usually a one-liner), but the same inconsistency of principle.

  - `[NOTE, H]` `LuauUI.valueModel` is a **namespace table** where the control family
    around it exports flat functions (`newSlider`, `newStepper`, `newRating`,
    `newProgressView` — `src/init.luau:80-91`). It is consistent with the library's
    *other* namespaces (`themes`, `tokens`, `motion`, `adaptive`, `composition`,
    `replication`, `spatial`, `text`), so this is a legitimate second pattern rather
    than a deviation — but it means `valueModel.new(...)` is the only `.new(` a
    consumer types on the public surface. Recording, not asserting a defect.

  - `[NOTE, H]` **Follows the pattern, no deviation** on everything else:
    construction-strict validation with named `LuauUI value control:` errors and
    `level 0` (`:62-70`) matches the library-wide construction-strict pattern;
    argument shape (`new(spec)`) matches the spec-table convention; the exported
    `Spec`/`Model` types carry no `any` at any position — **the only item in this
    area with a fully-typed public boundary.**

---

## Cross-item observations (the questions the brief asked directly)

- **Colon vs dot.** Core, Signal/Memo, Scope and Env are colon-method objects
  (`custom.luau:340-446`, `:294-335`, `scope_impl.luau:50-124`,
  `environment.luau:281-303`). The three replication adapters, the resource provider,
  its handle, its preload handle, and the value Model are all dot-function objects.
  The split is clean along a "reactive graph vs state service" line, but **no doc
  states the rule** — api.md announces it once, per entry, for `newCore`
  (`api.md:50`) and for `newDragSession` (`api.md:2795`), and nowhere else. It was
  ruled docs-acceptable in 2026-07-20
  (`docs/research/2026-07-20-phase4-architecture-verifier-findings-resolution.md:17`).
  `[NOTE, H]`
- **Constructor argument order.** Core-first holds for all four core-taking items
  (`environment.new(core)`, `adapters.*(core, …)`, `resources.newProvider(core, opts?)`);
  opts-last holds wherever an opts table exists. The single order deviation is
  `collection`'s required callback in positional slot 4. **No finding beyond the
  MINOR already recorded.**
- **Callback naming.** `onChange` is used consistently for "the value moved"
  (`contract.luau:61`, `custom.luau:376`, and the control specs
  `popup_button.luau:38`, `rating.luau:104`, `stepper.luau:55`, `slider.luau:78`,
  `picker.luau:35`) — all `(newValue) -> ()`. The exceptions in/near this area are
  `requestResnapshot` (imperative verb, positional) and `optimistic.apply`/`restore`
  (see findings). Outside my area but same-word-different-signature:
  `src/present/toast_schedule.luau:67` types `onChange: (() -> ())?` with **no
  argument** — flagging for the presentation-area auditor. `[NOTE, H]`
- **Error/quarantine conventions.** Three different regimes ship side by side:
  the core quarantines every user callback onto `lastError` and never throws (except
  `transaction` re-raising the body's error, `custom.luau:427-429`); the replication
  adapters quarantine **nothing** and both throw (`send`) and return verbs (`ingest*`);
  the resource provider never throws from a runtime path and reports only via verbs
  and `counters`; `value_model` throws at construction only. The regimes are
  individually defensible; the *combination* is what produced the two permanent-wedge
  MAJORs above, because the modules with the most consumer-authored callbacks are the
  ones with no containment.
- **Contract lies found in `docs/`:** `contract.luau:69` ("nil when healthy"),
  `docs/guide/06-client-server.md:63-64` and `:67-68` (resnapshot re-bases cleanly),
  `docs/reference/api.md:1665-1666` (facts clamp), `api.md:2124` + guide `:87`
  (`reset()`), and the eight undocumented env keys. All recorded above.

---

## Coverage

Every assigned item has an entry:

| Assigned item | Entry | Findings |
|---|---|---|
| `LuauUI.newCore` + Core/Signal/Memo/Scope surface | ✅ | 3 MAJOR, 7 MINOR, 2 NOTE |
| `LuauUI.newEnvironment` | ✅ | 1 MAJOR, 5 MINOR, 1 NOTE |
| `LuauUI.replication` (snapshot/collection/mutation) | ✅ | 3 MAJOR, 9 MINOR, 1 NOTE |
| `LuauUI.newResourceProvider` | ✅ | 0 MAJOR, 7 MINOR, 3 NOTE |
| `LuauUI.valueModel` | ✅ | 0 MAJOR, 2 MINOR, 2 NOTE |
| Cross-item (colon/dot, arg order, callbacks, quarantine, lies) | ✅ | 3 NOTE |

**Totals: 0 CRITICAL, 7 MAJOR, 30 MINOR, 12 NOTE.**

### Public but unassigned (reported, not audited)

- `UI.isReadable` (baseline line 36) — public, and the duck-typing predicate behind
  the `_node` MAJOR above. It has **zero hits in `docs/reference/api.md`**. Belongs
  to the blueprint-area auditor; noting it here because my finding depends on it.
- `src/present/toast_schedule.luau:67` — an `onChange` with a zero-argument
  signature, unlike the seven `onChange(value)` callbacks elsewhere. Presentation
  area.
- `motion.newClock(...).lastError` (`src/motion/clock.luau:238`) and
  `feedback bus.lastError` (`src/present/feedback.luau:140`) are declared as **dot**
  functions (`function self.lastError(_: any)`) while `core:lastError` is a colon
  method — three objects, one diagnostic name, two call conventions. Motion /
  presentation areas.
- `src/core/fusion_adapter.luau` and `src/core/imperative.luau` implement the same
  `contract.Core` but are **not** exported from `src/init.luau`; `CoreFactory.claims`
  (`contract.luau:73-83`) is likewise internal-only. Not public today — recorded so
  the lead knows the contract has three implementations but one export.
