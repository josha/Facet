# Decision packets — api-architecture-consistency (2026-08-02)

Larger-than-compatible proposals preserved with evidence, a recommendation, and a
migration cost. None is executed in this stage. Evidence citations live in
`ledger/*.md`; dispositions in `dispositions.md`.

> Scope note (phase-gate PG-A5): PKT-1 also covers **SEAM-1**, the drag family's
> call-convention split — `newDragRegistry` is the one dot-function object among
> four colon-method siblings; the 1.0 pass converts it to the colon convention its
> family teaches (documented per-entry until then).

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

**Migration cost:** mechanical rename with one-MINOR aliases; ~12 in-tree call sites for `context.destroy`, ~6 for `binding.remove`; zero RascalRally callers touch either directly (both reached via the presenter).

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

**Migration cost:** none for the recommended tightening (compatible predicate change + doc sentence); the bridging factory is additive when a consumer appears.

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

**Migration cost:** additive namespaces cost nothing; folding constants into `interactionTokens` touches only docs (no in-tree caller reaches the unreachable members today — that is the finding).

## PKT-6 — Per-control pure-rule exports (`resolvePresentation`)

**Evidence:** CTRL-10/CTRL-10a — api.md and both sources claim
`picker.resolvePresentation` / `popup_button.resolvePresentation` are "exported so
a caller can predict"; only `.build` is exported. Docs corrected this stage.

**Recommendation:** if prediction is worth an API, expose the rules as data/fn on
the control's returned `api` (available post-build) or under a `LuauUI.rules`
namespace at 0.9. Do not add per-control top-level namespaces.

**Migration cost:** additive (a member on the returned `api` or one `rules` namespace); the only consumers today are the two doc sentences corrected this stage.

## PKT-7 — Self-driven interaction-class loss (`onInteractionClassLost`)

**Evidence:** CTRL-13 — Slider/Rating require the CONSUMER to call
`onInteractionClassLost` (nothing in the framework calls it; only tests do), while
Table/TextInput self-drive from `env`. A shipped slider keeps a stale drag on a
real class flip under a green suite.

**Recommendation:** 0.9: controls that took `env` self-drive their CANCEL on
class loss (keep the callback as an override/notification). Needs a Studio
hot-switch canary; that's why it is not this stage's compatible fix.

**Migration cost:** behavior change on class-flip for Slider/Rating consumers (none in RascalRally today); needs one Studio hot-switch canary; the callback stays as an override so no caller breaks.

## PKT-8 — Typed theme schema

**Evidence:** SEAM-12 — every `themes.*` function is `any`-typed; ~100 lines of
api.md prose describe shapes that exist only as prose. Largest `any` surface in
the library.

**Recommendation:** author `ThemePackageDef`/`ThemePackage`/`ThemeSnapshot`/
`Report` types incrementally (identity+metrics first), keeping `define(any)`
accepting (validators keep `any` in — E-12) but typing the RETURNS. Sizeable,
mechanical, safe: a types-only stage.

**Migration cost:** types-only stage, zero runtime risk; the work is authoring ~4 record types and threading them through two modules; api.md prose already documents the shapes to encode.

## PKT-9 — Table sort-mark glyphs → semantic icon path

**Evidence:** controls ledger — Table's `"▲"/"▼"` are the exact geometric-shape
class recorded as tofu on a live device in Michroma; DisclosureGroup moved to
`themePackage.iconGlyph` for that reason. Changing the glyph source changes
visible text → breaks the 1140-node flat baseline, so it needs a deliberate
re-baseline window.

**Recommendation:** do it in the next stage that already re-baselines (Step 8
touches focus visuals) — one-line change + baseline refresh + device spot-check.

**Migration cost:** one-line glyph-source change + flat-baseline re-characterization + a device spot-check; no API change.

## PKT-10 — Error-prefix grammar unification

**Evidence:** BP-F21 — seven prefix shapes in the blueprint layer alone; styling
asserts leak `…/styling:408:` file-line prefixes; core has three unprefixed
throws; five control error vocabularies (controls ledger).

**Recommendation:** adopt `LuauUI <surface>: <problem>. <fix>` as the grammar
(constitution §4 examples already model it); convert bare `assert`s to formatted
errors mechanically at 0.9. Not brittle-lintable; enforce by review + the grammar
being written down.

**Migration cost:** mechanical message rewrites behind existing tests (~30 sites); the only risk is tests pinning exact message text — update them in the same pass.

## PKT-11 — `core:lastError` read semantics

**Evidence:** core-state MAJOR — monotonic, never cleared; the library's own
health-assertion idiom (`toBeNil()`) goes permanently red after one recovered
fault. Docs now state stickiness.

**Recommendation:** add `core:takeError()` (read-and-clear) at 0.9; keep
`lastError` sticky for post-mortems. One function, additive.

**Migration cost:** additive (`takeError()`); in-tree health-assertion idiom (~9 spec sites) migrates opportunistically; no consumer breaks.

## PKT-12 — Environment key introspection

**Evidence:** core-state ledger — `env:keys()` mixes settable facts and derived
memos with no way to tell them apart, zero callers, zero tests.

**Recommendation:** if a consumer appears, add `env:isDerived(key)`; otherwise
leave documented. Not worth surface today.

**Migration cost:** additive one-method change if ever needed; zero callers today.


## PKT-13 — Export the composite-control house conveniences (CTRL-11)

**Evidence:** ledger/controls.md CTRL-11 — `contract.enabledNow`/`enabledIn` (the
one `enabled` reading policy), `chrome_slots.attachHint` (paint-slot declaration),
`themePackage.iconGlyph`/`normalizeVariant` (semantic icons, per-state asset
grammar) are used by every shipped composite and exported by none, so an
out-of-repo control cannot follow the house pattern it can see. Constitution §13
now states the limit honestly (architecture review ARCH-2).

**Recommendation:** 0.9: one `LuauUI.controlKit` namespace (or fold `enabledNow`/
`enabledIn` into the public `contribution` seam and the icon/variant pair into
`themes`) — decide the home deliberately, not at a gate close. The REQUIRED
playbook obligations are already public; this unlocks the conveniences.

**Migration cost:** additive exports + api.md entries + the playbook paragraph;
zero existing callers change (in-repo controls keep their relative requires or
migrate opportunistically).


## PKT-14 — Promote (or split) `client/gamepad_contention`, the input-contention probes

**Raised by:** the `desktop-keyboard-navigation` architecture review (ARCH-1),
carried here as decision packet DKN-5 of that stage because it changes a closed,
checker-pinned public list and therefore belongs to this ledger rather than to a
keyboard stage.

**Evidence:** `src/client/gamepad_contention.luau` is **not** on the constitution
§12 blessed client entry-point list (`screen_target`, `billboard_target`,
`roblox_env`, `roblox_input`, `roblox_resources`, `theme_controller`,
`edit_preview`, `motion_driver`), and `tools/lune/check_boundary.luau` records it
in `EXAMPLE_INTERNAL_REACH` as *"not yet a blessed entry point"*. Yet
`docs/guide/07-input.md` instructs consumers to require it — for
`legacyStackActive()` (pre-existing) and now for `traversalKeyContended()`, the
probe that tells a game its Tab traversal is being eaten by the CoreGui players
list. A consumer following the guide reaches an unblessed module; a consumer
obeying the constitution cannot follow the guide.

**Recommendation:** promote the module. The two probes answer one question —
*"is a core script eating this key, and which?"* — for the two keys where the
answer is not observable any other way, they are documented, and they are the
only sanctioned diagnosis for two named failure modes. The alternative (move both
probes onto an already-blessed seam such as `roblox_input`) also works and keeps
the list shorter, but puts a diagnostic on the action-system adapter, which is a
different job. `responder_effects` sits in exactly the same position in
`EXAMPLE_INTERNAL_REACH` and should be decided in the same pass.

**Migration cost:** additive. Add the module(s) to the constitution §12 list and
api.md's client entry points, remove the `EXAMPLE_INTERNAL_REACH` entries, and
the existing guide snippets become correct with no consumer change. No behavior
moves; nothing is renamed.
