# Dispositions — api-architecture-consistency (Fable lead, 2026-08-02)

Every audit finding (ledger/*.md) receives exactly one disposition:

- **FIX** — small compatible repair in this stage (behavior-preserving, or a
  diagnosed-at-construction upgrade under the 0.5.0 / ADR-0011 pre-1.0 MINOR rule).
- **DOC** — public-contract lie or gap; the document changes, the code is the contract.
- **DEP** — ADR-0011 deprecation: surface keeps working, ledger entry + replacement.
- **EXC** — intentional exception, named in the constitution with its justification.
- **PKT** — decision packet: larger change preserved with recommendation, not done here.
- **ENF** — enforcement/tooling repair (checkers, scaffold, playbooks, specs).
- **NOTE** — recorded; no action beyond the ledger.

The stage ships as **v0.8.0** (pre-1.0 MINOR): several FIX rulings convert silent
acceptance into construction-time errors, which ADR-0011 allows in a MINOR with
notice; the ADR's version-history entry enumerates them.

## A. Compatible code fixes (FIX)

| ID | Finding | Ruling |
|---|---|---|
| F-1 | CTRL-01 PopupButton accepts a Memo `value`, crashes on first select | Reject at build exactly like the six siblings; red-first regression |
| F-2 | CTRL-03 Chip validates nothing | Validate `selected` present + settable at build, error names control+field+fix |
| F-3 | BP-F3 `UI.background` drops the content's `meta` channel | Carry `meta` through the inflated backing node; regression pins a draggable surviving |
| F-4 | BP-F1 `UI.styleGroup` drops `stroke` + unknown keys silently | Accept `stroke` (4th family member); refuse unknown spec keys naming the set |
| F-5 | BP-F2 `normalizeShadow`/`normalizeGradient` accept unknown keys | Close both key sets like `normalizeStroke`/`checkTint` |
| F-6 | BP-F5 `schema.all()`/`forClass()` hand out live mutable authority | Freeze the schema tables at build (verify no internal post-build mutation first) |
| F-7 | BP-F4 modifier errors blame the class/internal prop, never the modifier | `withProps` carries the modifier name; errors read "LuauUI UI.alignment on UI.When: …" |
| F-8 | Core-state MAJOR: equal-revision `ingestResnapshot` wedges the collection forever | While awaiting, `newRevision >= revision` applies and clears the gap (re-base at same revision is legal, as the guide promises); red-first regression at exactly-equal |
| F-9 | Core-state MAJOR: throwing `optimistic.apply` wedges the mutation | Compute + return path made throw-safe: envelope bookkeeping first, `apply` pcall-quarantined, on throw `restore()` (also quarantined) and continue un-optimistic |
| F-10 | Core-state MAJOR: throwing `requestResnapshot` latches `awaitingResnapshot` | pcall; on throw reset the flag so the next patch retries |
| F-11 | `mutation.reset()` is a silent no-op while pending | `reset()` works from any state (restores optimistic if pending); matches its name, doc, and the guide |
| F-12 | Provider accepts `maxConcurrent = 0`/negatives etc. silently | Construction-strict like `valueModel.new` (named errors) |
| F-13 | `scope:own` silently ignores a table without `dispose` | Diagnose at `own` time (error naming the resource); fix the gallery `sponsor_avatars` misuse it exposes; audit all internal `own` sites first |
| F-14 | Services MAJOR: `pushScope` mutates caller scope/group tables | Normalize into internal copies; callers' tables never written; internal aliasing callers audited |
| F-15 | Services MAJOR: `responder`/`scrim` typos silently default | Validate both at present time like `cancelPolicy`, naming the legal set |
| F-16 | `presentCritical` drops every opt but `onActivate` on fallback | Pass the caller's opts through to the fallback presentation |
| F-17 | SEAM-3: screen_target calls `touchGestures.normalize` with named keys — every native gesture normalizes empty | Fix the six call sites to positional args; extend the gallery gesture scenario to record positions/scale; Studio canary required (adapter/input change); physical row NS-P2 stays pending |
| F-18 | BP-F15 `UI.draggable`/`dropTarget` accepted-and-inert on structural nodes | Refuse on `When`/`ForEach`/`ErrorBoundary` at attach, naming the fix |
| F-19 | BP-F11 `overflow` accepted on nine classes and drives nothing | `overflow = "clip"` now implies `clipChildren` (unless explicitly authored); other values stay declared intent consumed by diagnostics, documented as such. No author exists in examples/game, so no visible change anywhere |
| F-20 | BP-F12 `Divider.thickness`/`Path.thickness` refuse the metric grammar; doc default wrong | Add `"metric"` to both props' accepted types; doc states the real default (`strokes.hairline`) |
| F-21 | BP-F14 `id`/`children` typos get no suggestion | Suggester considers both reserved keys |
| F-22 | BP-F18 blueprints frozen one level deep | Deep-freeze `props`/`children` at `make` (audit internal post-make mutation first — ScrollView clones, modifiers copy; expected clean) |
| F-23 | CTRL-06 `semanticText` is a string on Label, a Readable on 4 siblings | Label returns a Readable like the family (zero external consumers; the one example updated). Recorded in ADR-0011 notes |
| F-24 | CTRL-05a gallery auto-bind misses Table's `api.bindNativeScroll` | Gallery probes `api.bindNativeScroll` too; shipped playlist example regains its scroll mirror; VirtualList header comment corrected |
| F-25 | Table `dump()` missing live interaction state; CTRL-08 family (Table/VirtualList/Rating/Label dumps + dispose unproven) | Enrich Table dump (additive keys); add dump-determinism + dispose-neutrality cases for all four |
| F-26 | TextInput `spec.env` unguarded deref at :323 | Guard like :392 (nil-env path proven by test) |
| F-27 | Table `column.alignment` ignored by header titles | Header title honors the column alignment; layout tests pin it |
| F-28 | Core types unreachable (`core: any` everywhere, `contract.Core` unexported) | Re-export `Core`, `Scope`, `Signal<T>`, `Memo<T>`, `Readable<T>`, `Unsubscribe` types from `src/init.luau` (zero runtime); adopt `Readable<T>` in `adaptive.Conditions` and `inputHint` signatures |
| F-29 | SEAM-5/renderer/actions type lies (`engineSelectionBridge` undeclared; `onNodeTap`/`onPressed`/`onReleased` arity; drag_registry `Opts` omits `isPathLive`/`isSourceEnabled`; composition `eligible`/`hugOverflow` untyped; adaptive `opts.scope` cast) | Fix the declared types to the shipped truth (no behavior change) |
| F-30 | Renderer read methods return live internal tables | `hiddenRoots`/`diagnostics`/`compositionAt(nil)` return copies like `stats()` |
| F-31 | `text.measure` positional vs `fit`/`size` spec-table in one new namespace | Additive spec-table overload on `measure` (table arg detected); canonical form documented; positional form remains |
| F-32 | `Fit` drops `Metrics.state` | Additive `state` field on `Fit` |
| F-33 | `inputHint` lacks `opts.scope`; `opts.style` unvalidated | Add `opts.scope` (same idiom as `adaptive.conditions`); validate `style` naming the set |
| F-34 | UI.PROP_DIRTY / DEPRECATIONS arrays unfrozen; init comment says "Empty = nothing deprecated" | Freeze both; fix the comment |
| F-35 | SEAM-20 target_contract missing nine methods the framework calls | Add them (OPTIONAL + a named THEME group with consequences); fake_target implements the missing ones; contract spec updated |
| F-36 | SEAM-25 scaffold adapter template wrong `create` arity, no registration edits | Template matches the contract (decorationHint/createOpts); stamps a spec stub |
| F-37 | SEAM-4 `newArbiter(_opts)` accepted-and-ignored | Refuse a non-empty opts table (reserved), naming the fact — silence is the failure class |
| F-38 | valueModel `spec.format` unquarantined in render path | pcall with fallback to defaultFormat + core-style containment note (lowest-risk quarantine) |
| F-39 | BP-F7: the reactive pulse idiom existed for `strokeData` alone — a reactive shadow/gradient/corner radius needed an internal require | Export `UI.shadowData` / `UI.gradientData` / `UI.cornersData` mirroring `strokeData` (additive family completion; architecture review ARCH-2) |
| F-40 | ARCH-1: nine public constructors accepted unknown spec/opts keys silently while the constitution claimed universal strictness | One shared `spec_guard.assertKnownKeys` refusal applied to every composite spec and service/model opts boundary (same diagnosed-at-construction class as F-4/F-5/F-12) |

### Declared boundary exception (BEX)

**BEX-1 — F-23 (`newLabel.semanticText` string → Readable).** The architecture
review (ARCH-3) is right that this is a source-incompatible change to a public
return field, not a pure compatible repair. It ships anyway, DECLARED: the field
was a family lie (four siblings publish a Readable; api.md never distinguished),
zero consumers exist (game grep: none; the one example never reads it), and the
pre-1.0 MINOR rule allows a behavior change with notice — the notice is the
ADR-0011 0.8.0 entry's own line plus the api.md entry and the pinned spec case.
`dump().semanticText` stays a plain string by design (dumps are snapshots).

## B. Documentation repairs (DOC) — api.md/guide/source-comment lies and gaps

DOC-1 toast supersede taxonomy (api.md + feedback.luau comment) · DOC-2 `LuauUI.text`
namespace section · DOC-3 `motion.newValueReveal` section · DOC-4 the eight
undocumented env keys + settable-vs-derived table + honest clamp wording ·
DOC-5 renderer module exports (EMITTED_PROPS et al) + all 27 controller members ·
DOC-6 drag-registry members (`heldSource`, `registerSource/Target`, `onUpdate`,
`setCollaborators`) + `Opts` fields · DOC-7 client entry points: new api.md section
enumerating the blessed eight with signatures (the ADR-0011 list made real) ·
DOC-8 `tokens.dangerPair`, `valueModel.defaultFormat`, provider `counters()` keys,
preload ownership sentence · DOC-9 `UI.schema` all eleven members + stability note;
`UI.isReadable`; `UI.PROP_DIRTY` (advanced/tooling) · DOC-10 api.md shared-property
"Accepted on" rows + containers list + Button-is-a-container (BP-F6) · DOC-11
VirtualList stale claims (reorder/navigate-intercept; module header) · DOC-12
ProgressView theming claim → bar-family slots · DOC-13 TextInput keyboardType 4
values, dump keys, submitLabel honesty · DOC-14 `newPresenter` 5-arg signature;
`sinkNavigation` passive note; presenter session-lifetime contract (no dispose — one
per client session, stated) · DOC-15 `transactions <= steps`; Clock `lastError` ·
DOC-16 core: `effect` immediate-run, `core.name`, `transaction` = batching (error
semantics stated), disposed-signal semantics, `lastError` sticky ("nil until the
first quarantine" — contract.luau comment fixed) · DOC-17 replication:
`ingestResnapshot` verbs, `reset` semantics (true after F-11), `restore`'s two roles ·
DOC-18 guide README: DEPRECATIONS sentence, complete/reworded public-surface list ·
DOC-19 08-without-rojo folder list (+ motion, themes) · DOC-20 spatial "ten"→eleven ·
DOC-21 autoscroll band defaults inlined (no unreachable `bandForViewport` call
instruction); WINDOW_S stated as data · DOC-22 picker/popup `resolvePresentation`
"exported" claim removed; rule stated as a table (export decision → PKT-6) ·
DOC-23 theme_controller Opts completeness + `core` required-with-selectBy ·
DOC-24 screen_target Opts documented under the new client entry-point section ·
DOC-25 resources module header `pending()` → `pendingRequests()` · DOC-26 ADR-0011
version-history entry for 0.8.0 + api.md deprecated-marking for the two ledger rows ·
DOC-27 X-1 colon-vs-dot rule and X-2 ownership idiom written down (constitution +
one-line pointers where confusion was recorded) · DOC-28 `_deliver`/`_sample`
documented as the adapter seam (underscore = engine-adapter seam rule).

## C. Deprecations (DEP) — ADR-0011 ledger entries, surface keeps working

| Surface | Replacement | Note |
|---|---|---|
| `newResourceProvider` opts `retryAttempts` | `retry = { count, … }` | two words, one concept; legacy immediate-retry semantics preserved until removal |
| `adaptive.conditions().contentWidth` | `viewportWidth` | alias whose name states an inset subtraction it does not do |

Mechanism: `LuauUI.DEPRECATIONS` becomes the union of schema-generated property
entries and a declared static list (still machine-readable, still complete).

## D. Intentional exceptions (EXC) — constitution §Exceptions, with the why

E-1 `Image.scaleMode` `fill`/`crop` synonyms (both audiences' word; declared in
schema + docs) · E-2 `focusable` polarity split (interactive leaves opt OUT, `Grip`
opts IN — the default matches each class's overwhelmingly common use) · E-3
`UI.styleGroup` spec-first argument order (SwiftUI `Group` semantics; collection is
the subject) · E-4 `Screen` vs `VStack` (presenter-root semantics carry meaning
beyond the schema) · E-5 `Region` omits the BOX group (a Region IS its forms; a box
prop would be a second source of truth) · E-6 `ScrollView.axis` construction-only
while `AdaptiveStack.axis` is reactive (AdaptiveStack exists to be the reactive one;
a reactive engine scroll axis would rebuild native state) · E-7 colon-vs-dot split
(reactive-graph objects + pure stepped models are colon; services and namespaces are
dot) — now a WRITTEN rule with the boundary stated · E-8 `newAsyncImage` caller-scope
shape (its resources must die with the OWNER's scope; a dispose() would be a second
teardown path) — documented loudly · E-9 `eq` positional-optional on
`signal`/`memo` (hot-path, one option) · E-10 `renderer.attach` (a namespace that
also carries adapter-conformance data; `attach` is not `new` because the controller's
lifetime is the mount's, not the module's) · E-11 `edit_preview.start(LuauUI, opts)`
(dev tooling injected like a composite, deliberately) · E-12 `composition`/`themes`
validators take `any` in (their job is ruling on malformed input) · E-13
`valueModel` namespace-with-`.new` (the one value-arithmetic factory; consistent
with namespace modules) · E-14 `mount.dump()` nests `tree` (a mount dump IS a tree;
composition's is a record) — recorded, low value in forcing either.

## E. Decision packets (PKT) — preserved, not executed

PKT-1 Unify control return shapes (the `api`-nested vs flat split; `onReorder`
arity/base split CTRL-04; `select` arity; `presentation` fn-vs-Readable CTRL-12;
`disabled`-vs-`enabled` CTRL-02) — one breaking pass at 1.0, with the recommended
target shape written out · PKT-2 Teardown verb unification (`destroy`/`remove`/
`dispose`/`release`) — 1.0 · PKT-3 `presenter.dispose()` / `newFocusGraph` scope
arg / env teardown (the session-lifetime trio) — recommend adding dispose at 0.9
behind the session contract · PKT-4 Readable adapter seam (the `_node` back-channel:
accept any get/set-shaped table or export a wrapper) · PKT-5 Module-vs-`.new` export
policy (autoscroll/velocity constants unreachable; recommend namespace exports at
1.0, additive namespaces earlier if needed) · PKT-6 Export `resolvePresentation`
rules (per-control pure-rule namespaces) · PKT-7 Self-driven `onInteractionClassLost`
(controls watch env themselves like Table) · PKT-8 Typed theme schema
(`ThemePackage`/`ThemeSnapshot` types, SEAM-12) · PKT-9 Table sort-mark glyphs →
semantic icon path (visible glyph change; needs a re-baseline window) · PKT-10
Error-prefix unification (`LuauUI <domain>:` grammar everywhere; styling asserts
lose their file-line prefixes) — mostly mechanical, propose for 0.9 with the
constitution's grammar · PKT-11 `core:lastError` take/clear semantics · PKT-12
`env` factKeys/isDerived introspection.

## F. Enforcement (ENF)

ENF-1 `check_registration`: api.md coverage anchored to `###`-heading (not bare
token); nested-namespace member coverage for every namespace export (motion, text,
tokens, adaptive, composition, replication, spatial, touchGestures,
interactionTokens, valueModel — themes already checked by check_docs); dumpMarker
replaced by exact `function <x>.dump` or explicit `dump = false, reason = …` ·
ENF-2 `check_boundary`: consumer scan of `games/RascalRally/code/src` + `examples/`
for `LuauUI.<internal>` instance-path requires against the blessed client
entry-point list (which now exists in api.md; the list is pinned both places) ·
ENF-3 `tests/api_surface.spec.luau`: semver-parse `since`/`removeNoEarlierThan`,
window rule (≥ one minor), non-empty `replacement`, api.md marks each deprecated
surface · ENF-4 playbooks: `new-engine-feature.md` gains the schema step +
`check_prop_parity_cli` gate; `new-render-target.md` teaches the full optional list
+ parity caveat; one place lists all six playbooks · ENF-5 ledger-coverage check:
every export in the public-surface dump has a classification row in
`surface-ledger.md` (new focused check) · ENF-6 constitution linkage: guide README +
all six playbooks link `docs/reference/constitution.md`; check_docs pins the links +
the README DEPRECATIONS sentence + the 08-without-rojo folder list.

## G. Notes (NOTE, no action)

**SEAM-1 disposition (for traceability): PKT-1.** The drag family's call-convention
split (`newDragRegistry` dot vs four colon siblings) is ruled into PKT-1's scope
(see decision-packets.md preamble); documented per api.md entry until the 1.0 pass.


`nextRequestId` module-global (determinism hazard recorded) · `HEIGHT_BREAKPOINTS`
=== `BREAKPOINTS` (deliberate, spec-pinned) · Spacer/ScrollView/Divider optional-spec
vs required-table (BP-F13: unlearnable rule — constitution states the rule as
"constructors take one spec table; `spec?` is legal only where zero-config is the
common case", existing set grandfathered; new constructors must take `spec?` when
they have no required prop) · ErrorBoundary zero adoption · VERSION spec weak-pin ·
`text.fit` premeasure-budget interaction (documented in the new text section) ·
`sheet_model.dangerPair` internal alias · BP-F32 duplicate isReadable predicate
(internal) · CTRL-18 four private readable checks (internal; constitution names
`UI.isReadable` as the one public predicate).
