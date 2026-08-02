# Decision packets — api-architecture-consistency (2026-08-02)

Larger-than-compatible proposals preserved with evidence, a recommendation, and a
migration cost. None is executed in this stage. Evidence citations live in
`ledger/*.md`; dispositions in `dispositions.md`.

## PKT-1 — Control return-shape and callback unification (breaking, target 1.0)

**Evidence:** CTRL-05 (five return shapes for one pattern), CTRL-05a (the
`api`-nested vs flat split silently broke the shipped playlist example's scroll
mirror), CTRL-04 (`onReorder(keys: {string}, toIndex0)` on Table vs
`onReorder(key, index1)` on VirtualList — silent off-by-one on migration),
CTRL-12 (`presentation` is a function on PopupButton, a Readable on Picker),
CTRL-02 (`disabled` on TextInput vs `enabled` on five siblings, inverted polarity;
`contract.luau` misstates its own coverage), `select(key)` vs
`api.select(rowKey, opts)`.

**Recommendation:** one breaking pass at 1.0: every composite returns
`{ blueprint, api, dump, dispose }` with ALL verbs/readables under `api`;
`onReorder(keys: {string}, toIndex: number1)` everywhere; `presentation` is always
a Readable; `enabled` everywhere (TextInput's `disabled` kept one MINOR as a
deprecated alias). Until then the constitution §6 rule ("new controls nest under
`api` past two members") stops the drift from growing.

**Migration cost:** LuauUI examples + tests mechanical; RascalRally touches
`LuauUIRacerListScreen` (Table api — already nested, unaffected), `RacerList`
(VirtualList flat reads — ~8 sites). Estimated one focused day with the suite as
the net.

## PKT-2 — Teardown verb unification (breaking, target 1.0)

**Evidence:** `dispose` (core/scopes/controls/clock/bus/controller/root),
`release` (resource handles), `destroy` (input contexts), `remove` (bindings; and
`graph.remove` means a structural edit, not teardown), plus `unsubscribe`
closures. Core-state ledger "two public words for stop listening"; services
ledger `destroy vs dispose`.

**Recommendation:** at 1.0: `context.dispose()` (alias `destroy` one MINOR),
`binding.dispose()`; `release` stays (a refcounted handle is genuinely not a
dispose); `graph.remove` renamed `graph.removeEntry`. Document now (done),
rename later.

## PKT-3 — Session-lifetime teardown: `presenter.dispose()`, focus-graph/env scope

**Evidence:** services ledger MAJORs — presenter owns a bus, possibly its own
clock, a signal, two unscoped observers, four private surfaces, with no dispose;
`newFocusGraph(core)` creates two unowned signals, no dispose; `newEnvironment`
~27 registrations, no dispose; the scenario runner builds a second env on one core.
`core:counters()` can never return to baseline at application level.

**Recommendation:** 0.9: add `presenter.dispose()` (tears down bus, own-built
clock, observers, private surfaces, focus scopes it pushed), `graph.dispose()`,
`env.dispose()`, each documented as optional-for-the-normal-session. The
session-lifetime contract is now WRITTEN (api.md), so this is additive when it
lands.

**Cost:** low — additive; the hard part is ordering (presenter → graph → env →
core) which the presenter can own.

## PKT-4 — A public Readable adapter (the `_node` back-channel)

**Evidence:** core-state MAJOR — exported `Signal<T>`/`Memo<T>` are structural,
`UI.isReadable` duck-types on `kind`, but `use`/`observe` index the private
`_node`; a hand-rolled readable passes the predicate and dies at mount.

**Recommendation:** either export `core:readable(getter, subscribe)` (a bridging
factory) or narrow the public story to "Readables come from this core" and make
`isReadable` check `_node` too (compatible tightening). Recommend the latter at
0.9 + the factory only when a real consumer appears. Constitution §5 states the
narrow contract today.

## PKT-5 — Module-vs-`.new` export policy (autoscroll/velocity constants)

**Evidence:** SEAM-2 — `LuauUI.newAutoscroll`/`newDragVelocity`/`newDragRegistry`
bind `.new` only, so documented `autoscroll.bandForViewport`, `BAND_H`, `DEFAULTS`,
`WINDOW_S` are unreachable; api.md instructed calls a consumer cannot make (doc
fixed this stage).

**Recommendation:** the constitution rule going forward is "a module with public
constants exports as a namespace". For the three shipped `.new` bindings, add
namespaces at 0.9 (`LuauUI.autoscroll`, keeping `newAutoscroll` as the factory
alias) only if a consumer actually needs the constants; otherwise fold the
constants into `interactionTokens` where tuning data already lives.

## PKT-6 — Per-control pure-rule exports (`resolvePresentation`)

**Evidence:** CTRL-10/CTRL-10a — api.md and both sources claim
`picker.resolvePresentation` / `popup_button.resolvePresentation` are "exported so
a caller can predict"; only `.build` is exported. Docs corrected this stage.

**Recommendation:** if prediction is worth an API, expose the rules as data/fn on
the control's returned `api` (available post-build) or under a `LuauUI.rules`
namespace at 0.9. Do not add per-control top-level namespaces.

## PKT-7 — Self-driven interaction-class loss (`onInteractionClassLost`)

**Evidence:** CTRL-13 — Slider/Rating require the CONSUMER to call
`onInteractionClassLost` (nothing in the framework calls it; only tests do), while
Table/TextInput self-drive from `env`. A shipped slider keeps a stale drag on a
real class flip under a green suite.

**Recommendation:** 0.9: controls that took `env` self-drive their CANCEL on
class loss (keep the callback as an override/notification). Needs a Studio
hot-switch canary; that's why it is not this stage's compatible fix.

## PKT-8 — Typed theme schema

**Evidence:** SEAM-12 — every `themes.*` function is `any`-typed; ~100 lines of
api.md prose describe shapes that exist only as prose. Largest `any` surface in
the library.

**Recommendation:** author `ThemePackageDef`/`ThemePackage`/`ThemeSnapshot`/
`Report` types incrementally (identity+metrics first), keeping `define(any)`
accepting (validators keep `any` in — E-12) but typing the RETURNS. Sizeable,
mechanical, safe: a types-only stage.

## PKT-9 — Table sort-mark glyphs → semantic icon path

**Evidence:** controls ledger — Table's `"▲"/"▼"` are the exact geometric-shape
class recorded as tofu on a live device in Michroma; DisclosureGroup moved to
`themePackage.iconGlyph` for that reason. Changing the glyph source changes
visible text → breaks the 1140-node flat baseline, so it needs a deliberate
re-baseline window.

**Recommendation:** do it in the next stage that already re-baselines (Step 8
touches focus visuals) — one-line change + baseline refresh + device spot-check.

## PKT-10 — Error-prefix grammar unification

**Evidence:** BP-F21 — seven prefix shapes in the blueprint layer alone; styling
asserts leak `…/styling:408:` file-line prefixes; core has three unprefixed
throws; five control error vocabularies (controls ledger).

**Recommendation:** adopt `LuauUI <surface>: <problem>. <fix>` as the grammar
(constitution §4 examples already model it); convert bare `assert`s to formatted
errors mechanically at 0.9. Not brittle-lintable; enforce by review + the grammar
being written down.

## PKT-11 — `core:lastError` read semantics

**Evidence:** core-state MAJOR — monotonic, never cleared; the library's own
health-assertion idiom (`toBeNil()`) goes permanently red after one recovered
fault. Docs now state stickiness.

**Recommendation:** add `core:takeError()` (read-and-clear) at 0.9; keep
`lastError` sticky for post-mortems. One function, additive.

## PKT-12 — Environment key introspection

**Evidence:** core-state ledger — `env:keys()` mixes settable facts and derived
memos with no way to tell them apart, zero callers, zero tests.

**Recommendation:** if a consumer appears, add `env:isDerived(key)`; otherwise
leave documented. Not worth surface today.
