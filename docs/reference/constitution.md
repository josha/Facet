# The Facet constitution

**This is the one authoritative rule set for how a Facet public surface is shaped.**
Learn one control, service, or extension seam and the rules here tell you what the
next one looks like. The [API reference](api.md) documents each item; this document
governs the *patterns*; [ADR-0011](../adr/ADR-0011-semver-and-deprecation.md) governs
how any of it may change. Every current public item follows a named rule below or
appears in [§16 Exceptions](#16-exceptions) with the reason uniformity would be worse.

New public work is held to this document by the phase gates: the surface ledger
(`artifacts/api-architecture-consistency/surface-ledger.md`) classifies every item,
and `tools/lune/check_registration_cli` + `tools/lune/check_docs_cli` +
`tools/lune/check_prop_parity_cli` + `tools/lune/check_boundary` enforce the
mechanically checkable rules.

---

## 1. The kind ladder

Every feature is exactly one of these kinds. Choose by the question, not by taste:

| Kind | It is… | Test | Shipped examples |
|---|---|---|---|
| **Blueprint primitive** | a node class the solver/renderer understand natively | needs its own layout/paint/input semantics an existing class cannot compose | `UI.Text`, `UI.ScrollView`, `UI.Grip`, `UI.Path` |
| **Structural region** | the only things that may mount/unmount nodes later | its job is presence, not paint | `UI.When`, `UI.ForEach`, `UI.ErrorBoundary` |
| **Modifier** | `(blueprint, …) -> new frozen Blueprint` | it decorates or re-frames an existing node | `UI.shadow`, `UI.frame`, `UI.draggable`, `contribution.attach` |
| **Composite control** | primitives assembled behind `build(Facet, core, spec)` | it could be written outside the library with public API only | `newTable`, `newStepper`, `newChip` |
| **Service** | a stateful runtime collaborator created per client/surface | it owns live state and a lifetime | `newCore`, `newPresenter`, `newEnvironment`, `renderer.attach` |
| **Pure decision module** | engine-free functions + frozen data, no ownership | the whole contract is (input → answer) | `adaptive`, `composition`, `valueModel`, `interactionTokens`, `text` |
| **Engine adapter** | the only code that touches Instances / real input / device facts | it would not compile under Lune | `client/screen_target`, `client/roblox_env` |
| **Theme data** | inspectable declarative data, never code | a designer could write it | `themes.define` packages |

A feature that seems to need two kinds is two features (Slider = a composite control
over the `valueModel` decision module plus adapter seams).

## 2. Naming

- **`newX(…)`** — a factory returning a stateful object you may have to dispose
  (`newCore`, `newTable`, `newDragSession`). Nothing else starts with `new`.
- **`UI.Pascal{ spec }`** — blueprint constructors. **`UI.lowerCase(bp, …)`** —
  modifiers.
- **lowercase namespaces** (`motion`, `text`, `themes`, `adaptive`, `composition`,
  `tokens`, `replication`, `spatial`, `touchGestures`, `interactionTokens`,
  `valueModel`, `contribution`) — curated tables of related functions/constants. A
  namespace may carry its own `newX` when the factory belongs to that domain
  (`motion.newClock`, `touchGestures.newArbiter`).
- Callbacks a consumer supplies are **`onVerb`** (`onChange`, `onCommit`,
  `onActivate`). Framework-internal seams an adapter drives carry a leading
  underscore (`action._deliver`) — underscore means *engine-adapter seam*, not
  "free to break", and each one is documented as such.
- One concept gets one public word. The shipped vocabulary: `dispose` (teardown),
  `release` (async handles), `destroy` (input contexts) and `binding.remove()` —
  both grandfathered, see PKT-2 — and an `unsubscribe` closure (event listeners).
  New surface uses `dispose` or an unsubscribe closure; do not add a sixth word.

## 3. Constructors and argument order

- Services: **`(core, …collaborators, opts?)`** — core first, options last
  (`mount(core, blueprint, opts?)`, `newPresenter(core, env, adapter, actionSystem, opts?)`).
- Composite controls: **`build(Facet, core, spec)`** — the library table is
  injected so an out-of-repo control uses the identical seam.
- Pure models: **`new(opts?)`** single table (`newAutoscroll`, `newDragVelocity`,
  `motion.newValueReveal`).
- Modifiers: **`(blueprint, spec, style?)`** and always return a **new frozen**
  blueprint; the input is never mutated.
- One spec table, never a parade of positionals. A constructor with no required
  field takes `spec?`. (`text.measure`'s positional form is a grandfathered
  solver-internal shape; the spec-table form is canonical — see §16.)

## 4. Specs and validation: strict at the boundary

Since 0.5.0, **silent acceptance is the defect**. Every public spec is validated at
construction; each refusal names the item, the field, the problem, the fix, and the
legal set, with a did-you-mean where possible:

```
UI.Button: unknown property 'lable'. Did you mean 'label'?
Facet newStepper('Volume'): spec.value must be a settable Signal you own — a Memo cannot be set.
```

Rules:

- An unknown key, wrong type, missing required field, illegal enum value, or a
  reactive value on a construction-only prop is an **immediate error** — never a
  value that silently does nothing. This applies to `UI.*` props, modifier specs,
  control specs, AND service/model option tables (`spec_guard.assertKnownKeys` is
  the shared refusal every non-schema boundary uses; architecture review ARCH-1
  closed the last silent acceptors in 0.8.0).
- A property that is *accepted* must *do something*; a declared-intent-only field
  says so in its doc line. An option reserved for the future is **refused**, not
  ignored (`touchGestures.newArbiter`).
- Anywhere a theme-owned number is legal, its **metric name** is legal too
  (`"s"`, `"targetSizes.minimum"`, `"-s"`); a literal number is a declared
  theme-independent value.
- Validation failures at construction are errors; failures at runtime inside user
  callbacks are **quarantined** (§8).

## 5. Reactive values

- `Signal<T>` (settable), `Memo<T>` (derived), `Readable<T>` (either) — the types
  are exported from `src/init.luau`. `UI.isReadable` is the one public predicate.
  Readables come from `core:signal`/`core:memo`; the framework does not accept
  hand-rolled get/set tables (PKT-4 tracks a future adapter seam).
- **Durable state is owner-held.** A control never creates state that must outlive
  it: `value`, `selected`, `expanded`, `sortOrder` are settable Signals the caller
  owns; the control reads and writes them and holds only presentation state in its
  own scope. A control REJECTS a read-only Memo where it must write.
- A prop is reactive when it answers a question about **state**; it is
  construction-only when it answers what the node **is** (`shape = "circle"`,
  `canvasGroup`, `ScrollView.axis`). The schema declares which; binding a
  construction-only prop is a construction error naming the rebuild idiom.

## 6. Result objects

- Composite controls return a frozen table
  **`{ blueprint, …extras, dump, dispose }`**. `dump()` is deterministic (two
  calls, identical result), carries a `schema = "facet-<name>-dump/N"` string, and
  reflects the state a bug report needs. `dispose()` tears down the control scope
  and nothing else. Control-specific verbs either sit flat (few) or under `api`
  (many) — today both exist (see §16/PKT-1); new controls put extra surface under
  **`api`** once it exceeds two members.
- Services return their instance directly (`Controller`, `Presenter`, `Env`);
  subscription methods return an **unsubscribe closure** and nothing else.
- Validators return `(value?, report)` (`tokens.compile`, `themes.define`); state
  machines return **verb strings** from a closed set (`"applied" | "stale" |
  "duplicate" | "gap"`), shared across modules where the concept is shared
  (replication and the resource provider deliberately speak the same
  `"applied"/"stale"`).

## 7. Callbacks

- `onChange(value)` fires per accepted live change; `onCommit(value, reason?)`
  fires once at a terminal; the two may coexist (`newSlider`, `newTextInput`).
- `onActivate(path, meta)` is the semantic Activate verb — one activation site per
  control: when a contribution declares `handleActivate`, inner focusables carry no
  `onActivate` (double-fire).
- **Causal-frame exactness**: an event fires synchronously in the call that caused
  it, exactly once, after the effect it reports (the feedback bus taxonomy is
  closed — see api.md §Semantic feedback).
- Every consumer-authored callback that runs inside framework machinery is
  **quarantined** (§8). A callback that computes a value the framework needs
  (an `eq`, a `format`, an `accepts`) has a stated fallback on throw.

## 8. Ownership, lifecycle, errors

- **Scopes own everything.** Every subscription, memo, handle, and child scope is
  owned by a scope; disposal is reverse-order, exactly-once, double-dispose
  detected. `dispose()` = `scope:dispose()` and nothing else. `scope:own` refuses a
  resource it cannot dispose.
- **The caller owns what it is handed.** The canonical spellings, in order of
  preference: pass `opts.scope` and the helper owns its resources there
  (`adaptive.conditions`, `inputHint`); else `scope:own(handle)` the returned
  object (`motion.newClock`); else the return IS an unsubscribe you own
  (`presenter.onTick`). A helper that builds more than one resource MUST offer
  `opts.scope`.
- Session-lifetime services (`newPresenter`, `newFocusGraph`, `newEnvironment`)
  are built once per client session and have no dispose today — that contract is
  stated in their reference entries (PKT-3 tracks adding teardown).
- **Error ladder**: refuse at construction → quarantine user callbacks at runtime
  (recorded via `lastError`, sticky until read source is rebuilt — never cleared)
  → `UI.ErrorBoundary` contains a subtree → `presentCritical` contains a screen.
  One broken corner must never black out the player's screen, and a recoverable
  fault must never permanently wedge a service (the replication adapters follow
  the same rule as the core).

## 9. Input and focus

- Controls never bind hardware key codes; they speak **semantic actions**
  (Activate, Cancel, Navigate, Adjust, Traverse) through contexts that own
  priority/sink/lifetime. The vocabulary is closed: a new verb is an ADR, not a
  new binding at a call site.
- A composite advertises its whole four-input story by attaching **one
  contribution bundle** to its blueprint root (`contribution.attach`); the
  presenter discovers and composes it — consumers wire zero `present()` opts.
- Every interactive control proves **four-input reachability** and the
  **paradigm idiom** per class (registry `inputProofs` + `affordanceProofs`), and
  declares its hot-switch semantic (CARRY or CANCEL) when it owns in-flight state.
- Focus is logical (`newFocusGraph`); engine selection is a render output. Focus
  order predicates are evaluated at navigation time; the active interaction holds
  its target's focusability. Adjust is bound only while focus sits on a declared
  target, so screens never shadow gameplay keys.
- **One focus map, read two ways.** Directional Navigate and linear Traverse
  (Tab/Shift+Tab) walk the *same* scope order. A second order, derived from
  Instances or maintained alongside, is the defect — the two would disagree the
  first time a node was hidden. Scope-level policy (traversal wrap, trap) is
  declared by the surface; a control may not invent its own.
- **A key belongs to one action at a time.** Where two verbs want the same key,
  the presenter *moves the binding* (a focused value control's declared
  `adjustAxis` suspends that axis's Navigate bindings and restores them on
  leaving) rather than delivering one press to two actions in one context.
- **Device-selected behavior comes from live capability plus responder state**,
  never a device name. The rule is about how such a decision is *made*, not a
  claim that every binding is gated: today only the desktop keyboard additions
  (Tab, Space-as-Activate) are capability-and-responder gated, while the older
  Return/ButtonA/arrow bindings are unconditional and harmless where their device
  is absent. When a binding IS gated it must add and remove real bindings, so a
  capability that goes away leaves no dead sink behind.

## 10. Adaptation

- Device truth lives in the **environment** (`newEnvironment`): facts are settable,
  derived policy is memoized and clamps garbage. Read **`effectiveInput`**, not
  `preferredInput`, unless you mean "what did they touch last".
- Three tools, three scopes: `adaptive.*` answers **viewport**-relative classes;
  `UI.ViewThatFits` answers one **container**'s candidate; `UI.Composition`
  resolves a whole **screen** on both axes. A device name appears nowhere.
- Adaptation is **re-solve, never rebuild**: axis flips, arrangement changes,
  theme swaps, and text-scale changes keep mount identity, focus, scroll, and
  in-flight state.

## 11. Styling and property authority

- Every engine render property has exactly **one** authority (layout / style /
  binding / presentation, declared in `render/authority.luau`); the renderer
  asserts every write. Motion drives **signals only** and reaches pixels through
  the presentation channel; a fade needs a declared `canvasGroup`.
- Paint is data: token roles, theme packages, decoration slots, style tags. A
  finite state is a **tag** (`selected`, roles); `tint` is the one continuous
  channel and it *claims* its properties, permanently and on the record.
- Style modifiers normalize to bounded data at construction and are materialized
  by the adapter (one named child, reused, never stacked).

## 12. Engine adapters

- Everything except `src/client/` is engine-free and runs under Lune
  (UI-BOUND-001; `tools/lune/check_boundary`, which also scans consumers).
- The **blessed client entry points** — required directly, never exported from the
  Facet table — are exactly: `host`, `screen_target`, `billboard_target`,
  `roblox_env`, `roblox_input`, `roblox_resources`, `theme_controller`,
  `edit_preview`, `motion_driver`, `haptics`, `gamepad_contention`,
  `responder_effects`. That is **twelve**. `tools/lune/check_boundary.luau` holds
  the same list in code and is the authority; api.md §Client entry points
  documents each one. Everything else under `src/` is internal to consumers.
  (`haptics` was blessed with the round-2 feedback bus; `gamepad_contention` and
  `responder_effects` on 2026-08-17, because the guide had been teaching a direct
  require of both while the checker refused it — neither engine-level side effect
  has a `Facet.*` route, so the list moved rather than the guide. `host` was
  added 0.10.0 as the FIRST of these: it composes the other four a bootstrap
  needs, and the getting-started guide teaches it rather than the six-step
  sequence that three of four shipped bootstraps got wrong — REUSE-109.)
- A render target implements `render/target_contract.luau`: six REQUIRED methods,
  the OPTIONAL set (each absence degrades one named behavior), and the THEME set
  (required for `theme_controller.install`). Engine facts are **measured, then
  recorded** (docs/research), never assumed from memory.

## 13. Extensions

Four seams, each a contract — never an edit to library internals:

1. **Composite control** — `docs/extending/new-control.md`; scaffolded
   (`scaffold_cli control <name>`), registered, four-input-proven. Everything the
   playbook **requires** is reachable from public API. Honest limit (CTRL-11,
   tracked PKT-13): three house *conveniences* the in-repo controls share — the
   `enabled` reading policy, chrome-slot hints, semantic icon glyph lookup — are
   not yet exported; an out-of-repo control writes its own until PKT-13 lands.
2. **Render target** — `docs/extending/new-render-target.md` + the target
   contract.
3. **Engine feature** — `docs/extending/new-engine-feature.md`: schema first,
   authority declared, `check_prop_parity` proves all seven views agree.
4. **Theme / skinned control** — `docs/extending/new-theme.md`,
   `docs/extending/skinned-control.md`; contributed controls declare namespaced
   needs (`ns:role`) and gate with `themes.checkCoverage`.

Contributed vocabulary is namespaced (`ns:name`); the framework never interprets
foreign names, it resolves or falls back visibly.

## 14. Versioning, deprecation, documentation

- ADR-0011 is binding: `VERSION` single-sourced in `src/init.luau`;
  `Facet.DEPRECATIONS` is the machine-readable ledger (schema-generated property
  entries plus declared entries), frozen; a deprecated surface keeps working for
  ≥ one MINOR unless it never worked (diagnosed-not-preserved).
- **Pre-release clause (ADR-0040, controller ruling R15).** While a version is
  UNRELEASED, a breaking change may land in it directly — provided it is recorded
  in `docs/adr/ADR-0040-unreleased-breaking-changes.md`. **After a version's first
  publish, the full ADR-0011 window applies with no exception.** The ledger cannot
  see two of these on its own — a prop flipping to `required`, and a documented
  default changing value, both generate no schema row — so `api_surface.spec` pins
  the required set and every documented default *by value*, and reddens when either
  moves without a record. A compatibility shim is not a substitute for the record,
  and where the old behaviour was itself the defect (a silent default the fix
  exists to remove) it is not an option at all.
- Every public item has an api.md entry — signature, spec fields, return surface,
  invariants, example — written for a reader with no repo context.
  `check_registration` enforces heading-anchored coverage of top-level exports
  **and** nested namespace members, in both directions.
- Documentation states what ships. A claim the code does not honor is a defect of
  the same severity as the reverse.

## 15. Evidence

What every public addition owes before it is called done (the execution contract,
`docs/plans/agent-execution-contract.md`, governs the full ladder):

- red-first headless specs for every deterministic decision, registered in
  `tests/run.luau` (suite count must grow);
- registry row with input/affordance proofs (interactive), dump/dispose proof;
- api.md entry + guide paragraph when it introduces a concept;
- live real-adapter (Studio) evidence when it can affect visible / input / layout
  / adapter / lifecycle behavior — a green headless suite is necessary, never
  sufficient;
- honest PENDING rows for anything only a physical device or a human can observe.

## 16. Exceptions

Approved deviations. Each is deliberate; making it uniform would make the API worse.

| # | Exception | Why uniformity loses |
|---|---|---|
| E-1 | `Image.scaleMode` ships `fill` and `crop` as synonyms | Roblox's `Crop` *is* the cover behavior other vocabularies call fill; both audiences find their word without a lookup. Declared in the schema and api.md |
| E-2 | `focusable` is opt-OUT on `Button`/`Toggle`/`TextField`, opt-IN on `Grip` | each default matches the class's overwhelmingly common use; flipping either would make the common case noisy |
| E-3 | `UI.styleGroup(spec, blueprints)` is spec-first | Group semantics: the collection is the subject being produced; `(bp, spec)` has no collection to be first |
| E-4 | `Screen` duplicates `VStack`'s schema | a Screen *means* presenter-root (safe-area resolved, fill-defaulted); the meaning, not the prop set, is the API |
| E-5 | `Region` takes no BOX props | a Region IS its ranked forms; a width on it would be a second source of truth against the composition's own resolution |
| E-6 | `ScrollView.axis` is construction-only while `AdaptiveStack.axis`/`Divider.axis` are reactive | a reactive engine scroll axis would rebuild native scroll state mid-gesture; `AdaptiveStack` exists to be the reactive flip |
| E-7 | Colon methods vs dot functions split | colon = reactive-graph objects and pure stepped models (`core`, signals, scopes, `clock`, drag/velocity/autoscroll models); dot = services, controllers, namespaces. The line is "does the object's identity matter to every call". Written here; per-entry api.md notes the convention where confusion was recorded |
| E-8 | `newAsyncImage` takes `spec.scope`, returns no `dump`/`dispose` | its resources must die with the owner's scope alongside the provider handle; a control-owned scope would be a second teardown path racing the first |
| E-9 | `core:signal(initial, eq?)` / `core:memo(fn, eq?)` take a positional optional | the hottest constructors in the library, one option; an opts table would tax every call site for one rare argument |
| E-10 | `renderer.attach` is not `newRenderer` | the module is also the adapter-conformance data (`EMITTED_PROPS`, …); `attach` names what happens — a controller bound to an existing mount's lifetime |
| E-11 | `edit_preview.start(Facet, opts)` | dev tooling injected like a composite so the plugin can hand in the game's own library table |
| E-12 | `themes.define` / `composition.normalize` / `arrangementOf` accept `any` in | they are validators; ruling on malformed input is their job. Their *outputs* are typed/frozen |
| E-13 | `valueModel.new` is the one `.new` a consumer types | it is a namespace module's factory (like `motion.newClock`), kept beside its `defaultFormat` constant |
| E-14 | `mount.dump()` nests under `tree`; `composition.dump()` is flat | a mount dump IS a tree; a resolution is a record. Forcing either shape flattens meaning |
| E-15 | `text.measure` keeps its six-positional form (spec-table form added, canonical) | it is the solver's own hot seam, called thousands of times per solve; the positional form stays for the solver, the spec form is the public idiom |
| E-16 | `replication` verbs: `ingest` / `ingestPatch` / `ingestResnapshot` | the three names encode *what arrives* (a whole state, a delta, a recovery), which call sites branch on; one overloaded verb would hide the protocol |
| E-17 | `context.destroy()` (input contexts) keeps its name | grandfathered pre-1.0; renaming now costs every consumer more than the inconsistency does. PKT-2 proposes the 1.0 unification |
| E-18 | `UI.offset(bp, x?, y?)`, `UI.aspectRatio(bp, ratio)`, `UI.alignment(bp, h?, v?)` take positional scalars, not a spec table | one or two numbers/words are the whole message; a spec table there is ceremony. The sub-family is internally consistent and closed — a new modifier with ≥3 fields takes a spec table |

Candidates that were **not** granted exceptions and are queued as decision packets
(rename/unification proposals with migration costs) live in
`artifacts/api-architecture-consistency/decision-packets.md`: control return-shape
unification, `disabled`/`enabled` polarity, teardown-verb unification, presenter
dispose, module-vs-`.new` export policy, error-prefix grammar, and the rest.

---

*Adopted 2026-08-02 (stage `api-architecture-consistency`, v0.8.0). Change this
document by ADR, in the same commit as the rule-affecting change.*
