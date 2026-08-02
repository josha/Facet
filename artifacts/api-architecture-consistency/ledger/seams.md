# Surface ledger — input mechanics, styling, client entry points, extension seams

Area: `newDragSession` / `newDragRegistry` / `newDragVelocity` / `newAutoscroll` /
`interactionTokens` / `touchGestures` / `spatial`; `LuauUI.tokens`; `LuauUI.themes`;
the seven `src/client/*` entry points; `src/render/target_contract.luau`;
`tools/lune/scaffold*` + `docs/extending/*.md`; ADR-0011 versioning/deprecation.

All paths relative to the library root
`GameStudio/ui/LuauUI`. Baseline read: `artifacts/api-architecture-consistency/baseline/public-surface-before.txt`.

---

## Part 1 — Input mechanics

### `LuauUI.newDragSession` — factory (pure model)
- **Shipped shape:** `src/init.luau:101` binds `require("@self/input/drag_session").new`.
  `drag_session.new(opts: Opts)` (`src/input/drag_session.luau:55`) → object with
  `update(_, x, y) -> targetId?` (:101), `drop(_, x, y) -> DropResult` (:113),
  `cancel(_, reason?) -> CancelResult` (:129), `retarget(_, targets)` (:145),
  `state(_) -> State` (:155). Exported types `Rect`/`Target`/`Opts`/`DropResult`/
  `CancelResult`/`State` at :24–46.
- **Pattern:** "opts-table factory returning a stateful object with colon methods"
  — every method takes a discarded `_: any` first parameter, i.e. dot-declared,
  colon-called. Well-typed except `payload: any` (deliberately opaque).
- **Callers:** `src/input/drag_registry.luau:44` (the registry owns one session and
  is the only in-library consumer); `examples/gallery/scenarios/drag_session.luau:89`;
  `bench/perf_scenes.luau:530`. No RascalRally caller (the game drives drag through
  the blueprint face `UI.draggable`).
- **Lifecycle:** owned by whoever constructs it; no `dispose` — the terminal
  (`drop`/`cancel`) makes it inert and it holds only closures over caller data. The
  registry cancels its session in `registry.dispose()` (`drag_registry.luau:1108`).
  Leak posture: nothing registered with the core, nothing to leak.
- **Proof:** `tests/drag_session.spec.luau` — `"fires enter/leave exactly once per
  hover change"` (:47), `"accepts-filter makes a target illegal: no hover, no enter"`
  (:78), `"overlapping targets: the LAST in the array wins (paint z-order)"` (:98),
  `"drop over a legal target returns dropped with payload; then inert"` (:110),
  `"cancel mid-hover fires leave for the hovered target, then goes inert"` (:130),
  `"retarget re-evaluates hover at the last position…"` (:149), `"retarget after a
  terminal state stays inert"` (:182). Docs: `docs/reference/api.md:2780`.
- **Findings:** see SEAM-1 (family call-convention split) and SEAM-8 (the export
  binding itself is untested — the spec requires `../src/input/drag_session`, never
  `LuauUI.newDragSession`).

### `LuauUI.newDragRegistry` — factory (stateful, core-owning)
- **Shipped shape:** `src/init.luau:119` binds `drag_registry.new`.
  `drag_registry.new(opts: Opts)` (`src/input/drag_registry.luau:94`), `Opts` at :63–73
  (`core`, `rectOf` required — asserted at :95–96 — plus `zOf`, `now`, `feedback`,
  `proxy`, `motionClock`, `promotionPx`). Returns a table of **dot** functions:
  `registerSource` (:691), `registerTarget` (:708), `refreshTargets` (:732),
  `pointerDown/Move/Up/Cancel` (:747–:813), `detectorHandlers` (:832), `arm` (:888),
  `armTo` (:914), `commit` (:946), `cancel` (:961), `surfacePresented` (:991),
  `onUpdate` (:1001), `setCollaborators` (:1023), `isActive` (:1041), `session`
  (:1045), `payload` (:1049), `mode` (:1053), `sourcePath` (:1057),
  `pointerPosition` (:1063), `interactionTarget` (:1073), `dump` (:1080),
  `dispose` (:1102); plus two Readable fields `registry.verdict` (:688) and
  `registry.heldSource` (:1101).
- **Pattern:** *unique* in this family — an opts-table factory whose returned object
  uses **plain dot functions with no self parameter**, unlike its four siblings.
- **Callers:** `src/render/renderer.luau:1162` builds one per attached surface and
  exposes it as `controller.dragRegistry()` (:1160); `renderer.luau:1382/1409`
  register targets/sources; `renderer.luau:1186` observes `heldSource`. No test and
  no example constructs it through `LuauUI.newDragRegistry`.
- **Lifecycle:** the renderer's attach scope owns the auto-built instance;
  `dispose()` (:1102) cancels the live session, kills detached flights, clears
  sources/targets/watchers and disposes both signals so `core:counters()` returns to
  baseline. A hand-built registry is the caller's to dispose — api.md says so only
  by listing `registry.dispose()` among "Reads".
- **Proof:** `tests/drag_public.spec.luau` drives the renderer-owned registry
  end to end — `"past the token the session begins and emits \`select\`"` (:190),
  `"the predicted verdict is readable while hovering, with the game's reason"` (:240),
  `"an ILLEGAL drop rejects ONCE, carrying the game's reason code"` (:293),
  `"overlapping targets resolve to the TOPMOST drawn one"` (:349), `"arm -> navigate
  -> commit drives the SAME session and the SAME legality"` (:601), `"a modal
  presented mid-drag CANCELS the session (F7)"` (:706). Docs: `api.md:2893`.
- **Findings:** SEAM-1, SEAM-5, SEAM-6, SEAM-7, SEAM-8.

### `LuauUI.newDragVelocity` — factory (pure model)
- **Shipped shape:** `src/init.luau:117` binds `drag_velocity.new`.
  `drag_velocity.new(opts: Opts?)` (`src/input/drag_velocity.luau:42`), `Opts =
  { windowS: number? }` (:34). Colon methods `push(_, x, y, t)` (:57),
  `velocity(_) -> (vx, vy)` (:71), `reset(_)` (:84), `sampleCount(_)` (:88),
  `last(_) -> Sample?` (:94), `windowSeconds(_)` (:98). Module constant
  `drag_velocity.WINDOW_S = 0.1` (:105) — **not** reachable publicly.
- **Pattern:** matches `newDragSession`/`newAutoscroll` exactly (opts-table factory,
  colon methods via `_: any`). Fully typed; no `any` at the boundary.
- **Callers:** `src/input/drag_registry.luau:45` (one per session);
  `examples/gallery/scenarios/sponsor_motion.luau:337`.
- **Lifecycle:** plain closure state, no disposal seam and none needed; the registry
  drops its tracker when the session ends. The read-order contract ("read
  `velocity()` at release BEFORE any state reset") is documented in the header
  (:21–25) and in api.md, and is a caller obligation, not an enforced one.
- **Proof:** `tests/interaction_tokens.spec.luau` §`"drag velocity: the rolling
  release window (SF-D2)"` (:75) — `"answers zero until it has two samples"` (:76),
  `"drops samples older than the window: a flick after a pause reads as a FLICK"`
  (:97), `"keeps TWO samples even when both are stale…"` (:114), `"a non-advancing
  clock is zero, never a division by zero"` (:124), `"refuses non-finite samples…"`
  (:133), `"honours a custom window and reports it"` (:151). Docs: `api.md:2838`.
- **Findings:** SEAM-2 (WINDOW_S unreachable), SEAM-8.

### `LuauUI.newAutoscroll` — factory (pure model)
- **Shipped shape:** `src/init.luau:118` binds `autoscroll.new`.
  `autoscroll.new(opts: Opts?)` (`src/input/autoscroll.luau:118`), `Opts` at :71–78
  (`bandH`, `dwellS`, `rampS`, `exitEaseS`, `vMin`, `vMax`). Colon methods
  `reset(_)` (:169), `step(_, input) -> Step` (:208), `state(_)` (:288), `band(_)`
  (:292), `penetration(_)` (:296), `options(_)` (:302). Module-level and **not
  publicly reachable**: `autoscroll.BAND_H` (:59), `autoscroll.DEFAULTS` (:69),
  `autoscroll.bandForViewport(w, h)` (:97).
- **Pattern:** same opts-table + colon-method factory as the two above; typed
  `Input`/`Step` records, no `any`.
- **Callers:** `src/render/renderer.luau:2742/2744` (the `ScrollView.autoscroll`
  prop path, which is where `bandForViewport` is actually used);
  `src/controls/virtual_list.luau:633`; `examples/gallery/scenarios/sponsor_drop.luau:653`.
- **Lifecycle:** owned by the scroller/list that constructed it; no dispose seam,
  pure closure state, `reset()` is the only teardown verb.
- **Proof:** `tests/autoscroll.spec.luau` — 25 cases across five describes, e.g.
  `"the top band arms upward and the bottom band arms downward"` (:51), `"a flick
  THROUGH the band never arms"` (:113), `"the penetration mapping is v = vMin +
  (vMax - vMin) * p"` (:169), `"a DIRECT band cross coasts the old velocity out
  instead of cutting it (D-11)"` (:220), `"clamps at the canvas end and STAYS armed
  (no re-paying the dwell)"` (:272), `"ships the ratified numbers, and reports the
  tuning in force"` (:320), `"portrait takes the taller band"` (:330). Docs:
  `api.md:2860`.
- **Findings:** SEAM-2 (documented `bandForViewport` has no public path), SEAM-8.

### `LuauUI.interactionTokens` — namespace module (stateless)
- **Shipped shape:** `src/init.luau:116` exports the whole module.
  `dragPromotionPx` frozen (`src/input/interaction_tokens.luau:36`),
  `dragPromotionRangePx` frozen (:40), `classForPointerType(pointerType?)` (:55),
  `promotionPx(class?, overrides?)` (:65), `promotionForPointerType(pointerType?,
  overrides?)` (:74), `promoted(dx, dy, pointerType?, overrides?)` (:81).
- **Pattern:** "dot functions on a stateless module + frozen constant tables" —
  the house pattern for pure token modules (`adaptive`, `spatial`, `composition`).
  Fully typed, no `any`.
- **Callers:** `src/controls/table.luau:587` (`DRAG_THRESHOLD` reads the token,
  replacing the private copy the header describes); `src/input/drag_registry.luau:46`.
  No RascalRally caller.
- **Lifecycle:** stateless module singleton; frozen tables; nothing to dispose.
- **Proof:** `tests/interaction_tokens.spec.luau` — `"ships the ratified per-class
  values, inside their published ranges"` (:15), `"non-pointer classes carry ZERO…"`
  (:25), `"maps engine pointer types to classes, and an unknown type is a pointer"`
  (:32), `"promotion is a MAGNITUDE test, not two axis tests"` (:43), `"per-call
  overrides win, and absent keys still fall through to the token"` (:57), `"Table's
  reorder threshold is now the TOKEN, not a private copy"` (:63). Docs: `api.md:2807`.
- **Findings:** none. Follows the pattern; the docs at api.md:2807–2837 describe
  every member accurately, including the "event in hand, not the live class set"
  rule the code implements at :55–60.

### `LuauUI.touchGestures` — namespace module (one stateless fn + one factory)
- **Shipped shape:** `src/init.luau:120` exports the module.
  `normalize(kind: string, args: { any }?) -> Gesture`
  (`src/input/touch_gestures.luau:109`) — `args` is the engine callback's
  **positional** arguments as an array (documented at :101–108).
  `newArbiter(_opts: { [string]: any }?) -> Arbiter` (:177) with colon methods
  `feed`/`owner`/`reset` (:182/:215/:219), returned via `arbiter :: any` (:223).
- **Pattern:** hybrid — a stateless dot function plus a nested `new*` factory,
  the only `new*` in the library that lives inside a namespace rather than at the
  top of `LuauUI`.
- **Callers:** `src/client/screen_target.luau:2718–2752` (`adapter.setTouchGestureHandlers`,
  the only production wiring); `examples/gallery/scenarios/drag_session.luau:169`
  (consumes the sink, does not call `normalize`). Nothing in `src/render` or
  `src/present` calls the seam.
- **Lifecycle:** the arbiter is caller-owned plain state; the adapter's
  `setTouchGestureHandlers` returns a disconnect closure (`screen_target.luau:2754`),
  and `billboard_target.luau:100` deletes the method outright so billboards degrade
  honestly.
- **Proof:** `tests/touch_gestures.spec.luau` — `"normalizes a tap: instantaneous,
  positions extracted, state 'none'"` (:18), `"normalizes a pan: Vector2 velocity +
  totalTranslation + state"` (:37), `"normalizes a pinch: scalar velocity + scale"`
  (:46), `"normalizes a swipe: direction name, no positions, state 'none'"` (:62),
  `"tolerates missing optional fields without erroring"` (:70), `"pinch preempts pan:
  two-finger intent takes ownership"` (:89), `"ownership releases on the owning
  gesture's 'ended' frame"` (:122). Docs: `api.md:2939`.
- **Findings:** SEAM-3 (the shipped adapter calls `normalize` with the wrong argument
  shape), SEAM-4 (`newArbiter` opts accepted and ignored), SEAM-26.

### `LuauUI.spatial` — namespace module (contract only)
- **Shipped shape:** `src/init.luau:127` exports the module.
  `PHASES` frozen (`src/input/spatial.luau:69`), `HANDEDNESS` frozen (:70),
  `normalize(raw: any) -> Spatial?` (:119), `extend(pos: any, raw: any) -> any`
  (:182), `of(pos: any) -> Spatial?` (:192), `isFlat(pos: any) -> boolean` (:203),
  `describe(pos: any) -> string` (:207). Exported types `Vec3`/`Ray`/`Pose`/
  `Spatial` (:35–64).
- **Pattern:** same stateless-namespace pattern as `interactionTokens` — frozen
  closed vocabularies plus pure dot functions. The `any` parameters are the
  deliberate "untrusted platform datum" boundary the header (:115–118) names.
- **Callers:** none in `src` — nothing produces or consumes spatial data today, by
  design (`src/env/environment.luau:216` publishes the matching
  `capabilities.spatialPointer` fact, and :76/:190 the `presentationSpace` /
  `presentationProfile` pair). No game caller.
- **Lifecycle:** stateless; `extend` returns a NEW table and leaves the input
  untouched (:187–189), so there is no shared mutable state at all.
- **Proof:** `tests/spatial.spec.luau` — `"spatial pointing is a capability among
  others, never a replacement mode"` (:64), plus the XP-D2 describe at :84 covering
  degenerate rays, NaN/infinite coordinates, unknown vocabulary fallbacks
  (:110), "an event with no spatial content is not a spatial event" (:118), and the
  non-mutating `extend` at :125–132. Docs: `api.md:2957`.
- **Findings:** SEAM-27 (the "ten unanswered questions" count both docs quote is
  eleven in code); otherwise no deviation — this is the cleanest entry in the area.

### Input-mechanics findings

- `[MAJOR, H]` **SEAM-1 — the drag family ships two call conventions.**
  `newDragSession`, `newDragVelocity`, `newAutoscroll` and `touchGestures.newArbiter`
  all return objects whose methods take a discarded `_: any` first parameter and must
  therefore be **colon**-called (`drag_session.luau:101`, `drag_velocity.luau:57`,
  `autoscroll.luau:208`, `touch_gestures.luau:182`). `newDragRegistry` returns plain
  dot functions with no self parameter (`drag_registry.luau:691`, :747, :946).
  api.md documents both faithfully (`api.md:2794` "Methods (colon-called)" vs
  `api.md:2916` "`registry.pointerDown(...)`"), so this is a shape drift rather than
  a doc lie. **User cost:** `registry:pointerDown(path, pos)` — the habit the other
  four teach — silently passes the registry table as `path`, misses the `sources`
  lookup and returns nil. No error, no session, no diagnostic.
- `[MAJOR, H]` **SEAM-2 — three of the four drag factories export only `.new`, so
  documented module members have no public path.** `src/init.luau:117–119` bind
  `.new` for velocity/autoscroll/registry, while :116/:120/:127 export the whole
  module for tokens/gestures/spatial. `autoscroll.BAND_H` (:59), `autoscroll.DEFAULTS`
  (:69) and `autoscroll.bandForViewport` (:97) and `drag_velocity.WINDOW_S` (:105)
  are consequently unreachable from `LuauUI`. `docs/reference/api.md:2869` tells the
  reader "`autoscroll.bandForViewport(w, h)` picks one" and `api.md:285` repeats it —
  a call a consumer cannot make. **User cost:** an author tuning a bespoke autoscroll
  host must hard-code 40/44 px and the ratified defaults, which is exactly the copy
  the module header (:6–15) exists to prevent.
- `[MAJOR, H]` **SEAM-3 — the only production caller of `touchGestures.normalize`
  passes the wrong argument shape, so every engine gesture normalizes to empty.**
  `normalize(kind, args)` reads `args` positionally (`touch_gestures.luau:109–146`;
  `a[1]` positions, `a[2]`/`a[3]`/`a[4]` payload+state), and the spec drives it that
  way (`tests/touch_gestures.spec.luau:19,38,47`). `src/client/screen_target.luau:2721,
  2724, 2727, 2735, 2743, 2751` pass a **named-key** table
  (`{ positions = positions, state = state.Name, … }`), so `a[1]..a[4]` are all nil:
  every gesture the real ScreenTarget delivers is `{ kind, state = "none",
  positions = {} }`, with translation/velocity/scale/rotation/direction dropped.
  The suite cannot see it because `tests/lib/fake_target.luau:570–580` only stores the
  sink and tests hand it already-normalized objects, and the gallery scenario that
  does connect (`examples/gallery/scenarios/drag_session.luau:169–178`) records only
  `kind`, which survives. `target_contract.luau:80` already flags gesture FIRING as
  physical row NS-P2, so no live drive closed it either. **User cost:** any consumer
  wiring native touch gestures on a device gets kind-only events with no positions and
  no lifecycle state — a pinch that never reports a scale.
- `[MINOR, H]` **SEAM-4 — `touchGestures.newArbiter` accepts an options table and
  ignores it.** `touch_gestures.luau:177` names the parameter `_opts:
  { [string]: any }?` and no line reads it; the arbitration policy (RANK, :158) is
  fixed. api.md:2951 documents it as `newArbiter(opts?)`. Accepted-but-ignored option,
  plus an unnecessary `{ [string]: any }` at a public boundary. **User cost:** an
  author passing `{ rank = … }` to bias pinch-over-pan gets silence.
- `[MINOR, H]` **SEAM-5 — `drag_registry.Opts` omits two options `new` actually
  reads.** `opts.isPathLive` (`drag_registry.luau:103`) and `opts.isSourceEnabled`
  (:109) are read and used (:104–112) but are absent from the exported `Opts` type
  (:63–73) and from api.md:2905's opts list. The repo runs no `luau-analyze`
  (`run-tests.sh` is `lune run tests/run` only), so the internal read is not caught;
  a typed consumer supplying either field gets an analyzer error against the exported
  type. **User cost:** two shipped behaviours (retiring-subtree liveness, per-source
  enable) are invisible unless you read the constructor body.
- `[MINOR, H]` **SEAM-6 — five public registry members are undocumented.**
  `registry.heldSource` (`drag_registry.luau:1101`, a Readable the renderer binds at
  `renderer.luau:1186`), `registerSource` (:691), `registerTarget` (:708), `onUpdate`
  (:1001) and `setCollaborators` (:1023) appear nowhere in `docs/reference/api.md`
  (grep count 0 for each). api.md:2893–2938 documents the rest. **User cost:** the
  "host that owns its own registry" use case the export exists for cannot be written
  from the reference — registration and the collaborator injection point are missing.
- `[MINOR, M]` **SEAM-7 — `any` at the registry boundary.** `Opts.core: any`,
  `rectOf: (string) -> any`, `motionClock: any?` (`drag_registry.luau:64–72`);
  `registerSource(path, decl: any)` (:691), `pointerDown(path, pos: any)` (:747),
  and `commit()`/`cancel()`/`session()`/`payload()`/`dump()` all returning `any`
  (:946–:1080). The sibling models are fully typed, and the module already exports
  `Feedback`, `ProxyHost` and `Verdict`. **User cost:** no editor completion and no
  type checking on the object with the largest surface in the family.
- `[MINOR, H]` **SEAM-8 — no spec reaches any of these seven through the `LuauUI`
  table.** Every input-mechanics spec requires the source module directly
  (`tests/drag_session.spec.luau:10`, `tests/autoscroll.spec.luau:10`,
  `tests/interaction_tokens.spec.luau:11`, `tests/touch_gestures.spec.luau:10`,
  `tests/spatial.spec.luau:16`); a grep of `tests/` for `LuauUI.newAutoscroll |
  newDragVelocity | newDragRegistry | newDragSession | interactionTokens |
  touchGestures | LuauUI.spatial` returns nothing. The only public-table uses are
  `examples/gallery/scenarios/{drag_session,sponsor_motion,sponsor_drop}.luau` and
  `bench/perf_scenes.luau:530`, and `tests/sponsor_scenarios.spec.luau:27–36` drives
  only the eight `sponsor_*` scenarios — `drag_session` is Studio-only. `newDragRegistry`
  has **zero** callers anywhere outside the renderer's internal require.
  Deletion of an export is caught by `check_registration` (reverse api.md check), but a
  mis-bound export (`.new` → the wrong function) is not. **User cost:** low today;
  the risk is a silent break of the documented standalone construction path.
- `[NOTE, M]` **SEAM-9 — `spatial.extend` returns `any`.** `spatial.luau:182`
  returns `any` where the module could export a `Position` type and return it;
  `of`/`isFlat`/`describe` likewise take `pos: any`. Justifiable at the
  platform-datum edge (`normalize`), less so for `extend`, whose input is LuauUI's
  own normalized position.

---

## Part 2 — Styling

### `LuauUI.tokens` — namespace module (stateless)
- **Shipped shape:** `src/init.luau:190` binds `require("@self/tokens/tokens")`.
  Public members: `contrastRatio(a: Rgb, b: Rgb) -> number`
  (`src/tokens/tokens.luau:30`), `dangerPair(colors: any) -> (Rgb, Rgb)` (:44),
  `compile(schema: any) -> (any, any)` (:50). Exported type `Rgb` (:13).
- **Pattern:** stateless dot-function module; `compile` follows the house
  "(value?, report)" validation-tuple convention shared with `themes.define`.
- **Callers:** `src/themes/package.luau:2712` and `src/tokens/sheet_model.luau:267`
  (which re-exports it as `sheet_model.dangerPair`, :268, and
  `src/client/screen_target.luau:552–553` reads it through that alias);
  `tests/renderer.spec.luau:16`. No RascalRally caller (the game consumes the
  default style).
- **Lifecycle:** pure; `compile` deep-freezes its result (:106–120). Nothing owned.
- **Proof:** `tests/renderer.spec.luau` §`"tokens and authority"` (:189) —
  `"compiles a valid schema and reports contrast"` (:190) and `"rejects an incomplete
  or low-contrast schema with a named report"` (:209); `tests/sheet_model.spec.luau:244`
  compiles a custom game style through the public function. Docs: `api.md:2133`.
- **Findings:** SEAM-10, SEAM-11.

### `LuauUI.themes` — curated namespace over two internal modules
- **Shipped shape:** `src/init.luau:198–213` builds the table by hand from
  `themes/package` and `themes/snapshot`: `define` (`src/themes/package.luau:971`,
  `(def: any) -> (any, any)`), `resolve` (`src/themes/snapshot.luau:285`,
  `(package: any, themeName: string?, facts: Facts?, overrides: { [string]: any }?)
  -> any`), `neutral` (`snapshot.luau:767`, `-> any`), `neutralPackage`
  (`snapshot.luau:215`, `-> any`), `lintProperty` (`package.luau:393`,
  `(prop: string, scope: string?) -> (boolean, string?)`), `checkCoverage`
  (`package.luau:2857`, `(pkg: any, declarations: { any }) -> any`), and
  `SCHEMA = "luauui-theme/1"` (`package.luau:46`).
- **Pattern:** "curated public façade over internal modules" — the same shape as
  `LuauUI.motion` and `LuauUI.text` (`init.luau:140`, :170). Six of `package.luau`'s
  ~16 and `snapshot.luau`'s ~15 module functions are lifted; the rest stay internal
  and are consumed by `screen_chrome`/`theme_controller` directly.
- **Callers (public path):** `tests/theme_reference_packages.spec.luau:22`
  ("uses the PUBLIC `LuauUI.themes` surface and nothing else", header :6),
  `tests/theme_layers.spec.luau:377`, `tests/rating.spec.luau:274`,
  `tests/renderer.spec.luau:773`, `tests/theme_matrix_audit.spec.luau:920`,
  `examples/themes/*` (every reference package's `build(themes)` entry point).
  No RascalRally caller — the game runs the default Studio Neutral snapshot.
- **Lifecycle:** `define` returns a **deeply frozen** package with a content stamp;
  `resolve` returns a frozen snapshot that rides the environment as the single
  `themeMetrics` fact, so the commit point is `env:set` and the environment owns it.
  Nothing here allocates a core resource; the client-side install/swap transaction
  lives behind `theme_controller` (below).
- **Proof:** `tests/theme_package.spec.luau`, `tests/theme_snapshot.spec.luau`,
  `tests/theme_reference_packages.spec.luau`, `tests/theme_docs.spec.luau`; plus the
  only per-member documentation gate in the repo — `tools/lune/check_docs.luau:504–520`
  reads the `themes = { … }` block out of `src/init.luau` and fails when any member is
  undocumented in `docs/reference/api.md`. Docs: `api.md:2146–2250`.
- **Findings:** SEAM-12, SEAM-13. Note the coverage story here is the **strongest**
  in this fragment: `LuauUI.themes` is the one nested namespace with a mechanical
  per-member docs check.

### Styling findings

- `[MINOR, H]` **SEAM-10 — `tokens.dangerPair` is public and undocumented.**
  Present in the shipped surface (`baseline/public-surface-before.txt:147`,
  `tokens.luau:44`) and referenced nowhere in `docs/reference/api.md` (grep count 0);
  the reference's `tokens` entry (`api.md:2135–2145`) names only `compile` and
  `contrastRatio`. `check_registration`'s api.md coverage check is top-level-only
  (`tools/lune/check_registration.luau:159–162`), so a nested member cannot fail it.
  It also has no direct test — only the internal alias path
  (`sheet_model.luau:377–378`) is exercised. **User cost:** a game overriding the
  destructive palette has no documented way to ask what the effective pair is.
- `[NOTE, M]` **SEAM-11 — `tokens.compile` is `any`-in/`any`-out.**
  `compile(schema: any) -> (any, any)` (`tokens.luau:50`) although the module already
  exports `Rgb` and the compiled/report shapes are closed and documented in prose at
  `api.md:2135`. **User cost:** the token schema — the thing a game author writes
  first — has no type to write against.
- `[MAJOR, M]` **SEAM-12 — every `LuauUI.themes` function is `any`-typed at the
  boundary.** `define(def: any) -> (any, any)`, `resolve(package: any, …) -> any`,
  `neutral() -> any`, `neutralPackage() -> any`, `checkCoverage(pkg: any,
  declarations: { any }) -> any` (`package.luau:971`, `:2857`; `snapshot.luau:285`,
  `:215`, `:767`). There is no exported `ThemePackage`, `ThemeSnapshot` or `Report`
  type, even though both modules do export types where the author chose to
  (`package.luau:575` `Error`, `snapshot.luau:230` `Facts`). This is the largest
  documented public data contract in the library (api.md:2146–2250, ~100 lines of
  prose describing shapes that exist only as prose). **User cost:** a theme author
  gets no completion, no field checking, and no compile-time signal when a package
  field is renamed — the compiler's runtime "did you mean" is the only feedback.
- `[MINOR, M]` **SEAM-13 — three return conventions inside one namespace.**
  `define` → `(value?, report)` tuple; `lintProperty` → `(boolean, string?)` tuple;
  `checkCoverage` → a `{ ok, covered, missing }` record; `resolve`/`neutral`/
  `neutralPackage` → a bare value. All three validation-shaped functions
  (`define`, `lintProperty`, `checkCoverage`) answer "is this legal and why not" and
  answer it three different ways. **User cost:** every call site has to remember
  which one it is; a `local ok = themes.checkCoverage(...)` reads as truthy always.

---

## Part 3 — Client entry points (`src/client/*`)

### Which the docs actually bless

ADR-0011 defines the public surface as "what `src/init.luau` exports (plus the
documented client entry points under `src/client/`)"
(`docs/adr/ADR-0011-semver-and-deprecation.md:29–31`) — **and never enumerates them.**
There is no client-entry-point section anywhere in `docs/reference/api.md`. The two
places that come closest disagree:

| Module | `guide/02-architecture.md:28` client table | `docs/reference/api.md` | required by RascalRally |
|---|---|---|---|
| `screen_target` | listed | mentioned only (`api.md:2254`, `:2299`) | **yes** ×4 |
| `roblox_env` | listed | mentioned only (`api.md:1668`) | **yes** ×4 |
| `roblox_input` | listed | mentioned only (`api.md:1693`) | **yes** ×4 |
| `billboard_target` | listed | **absent** (grep 0) | **yes** ×1 |
| `theme_controller` | listed | documented (`api.md:2251–2302`) | no |
| `edit_preview` | listed | **absent** (grep 0) | no |
| `roblox_resources` | **absent** | documented (`api.md:1222`) | no |

Game requires, verified in `games/RascalRally/code/src`:
`src/client/LuauUIRacerListGui.luau`, `src/client/GaragePilotGui.luau`,
`src/client/LuauUISettingsGui.luau` each require
`ReplicatedStorage.LuauUI.client.{screen_target, roblox_env, roblox_input}`;
`src/client/LuauUISponsor/init.luau:226–228` requires the same three lazily; and
`src/client/LuauUISponsor/OmenState.luau:79` requires
`root.client.billboard_target`. **Nothing the game requires is unblessed** — all four
appear in `guide/02-architecture.md:28`, and the game requires no library-internal
module beyond them (`ReplicatedStorage.LuauUI` itself is the only other require).
That is a clean result for the boundary rule, achieved without any mechanical check
(see SEAM-31).

### `src/client/theme_controller.luau` — client entry point (documented)
- **Shipped shape:** `install(adapter: any, package: any, opts: Opts?) -> controller`
  (:320) with `Opts` at :214–237 (21 fields). Also public on the module table:
  `styleFor` (:121), `sheetModelFor` (:151), `sheetNameFor` (:164),
  `fontDescriptors` (:171), `dumpFromRecords` (:187), `dumpFromPackage` (:204),
  `profileOf` (:261). Controller members documented at `api.md:2280–2291`
  (`swap`, `swapPackage`, `current`, `snapshot`, `inspect`, `dumpTokens`, `onChange`,
  `uninstall`).
- **Pattern:** "positional required collaborators + trailing opts table" —
  `(adapter, package, opts?)`.
- **Callers:** none in `src` (it is the top of the client stack);
  `tests/theme_controller.spec.luau`, `tests/theme_selectby.spec.luau`;
  `docs/guide/09-custom-themes.md:869`, `docs/guide/05-styling.md:255`,
  `docs/guide/10-rich-skinning.md:520`. No RascalRally caller.
- **Lifecycle:** `install` runs every capability check before the first mutation and
  leaves target+env untouched on failure (api.md:2270–2276); `uninstall()` restores
  the pre-install link and snapshot. Ownership is explicit and documented — the best
  lifecycle story of the seven.
- **Proof:** `tests/theme_controller.spec.luau` (incl. `dumpFromPackage` at :668),
  `tests/theme_selectby.spec.luau` (`profileOf` at :132/:145/:385/:508),
  `tests/theme_drift.spec.luau`, `tools/lune/check_docs.luau` anchor set. Docs:
  `api.md:2251`.
- **Findings:** SEAM-16, SEAM-17.

### `src/client/screen_target.luau` — client entry point (blessed, undocumented contract)
- **Shipped shape:** `screen_target.new(opts: Opts?)` (:155); `Opts` at :118–152:
  `style`, `isReducedMotion`, `parent`, `rootFactory`, `forceScrollFallback`,
  `forceDragFallback`, `nativeStyle`, `themePackage`. Returns the RenderTargetAdapter
  (39 methods, see Part 4).
- **Pattern:** opts-table factory; same as `billboard_target.new`.
- **Callers:** `src/client/billboard_target.luau:37`, `src/client/edit_preview.luau:78`;
  RascalRally ×4 (above); `docs/guide/03-getting-started.md:183`,
  `docs/guide/08-without-rojo.md:142`.
- **Lifecycle:** one adapter per root (ADR-0009: "`instancesByPath` and the
  capture/cursor state are adapter-scoped, so an adapter must never host two roots");
  `destroyRoot` releases the tree. That invariant lives only in
  `docs/adr/ADR-0009-billboard-target.md:12`, not in the reference.
- **Proof:** indirectly, everywhere — `tests/render_target_contract.spec.luau:80–176`
  reads its source as the live-adapter contract (it cannot load headless);
  `tools/lune/check_prop_parity.luau:39` pins its `setProp` switch against the schema.
  No spec constructs it. Docs: no reference entry.
- **Findings:** SEAM-14, SEAM-15.

### `src/client/billboard_target.luau` — client entry point (blessed by the guide only)
- **Shipped shape:** `billboard_target.new(opts: Opts)` (:33), `Opts` at :23–32
  (`parent`, `adornee`, `canvas` required by assert at :34–36; `studsOffset`,
  `alwaysOnTop`, `maxDistance`, `style`, `isReducedMotion`), plus
  `billboard_target.canvasRect(canvas)` (:105). Deletes two optional adapter methods
  after construction: `setPointerHandlers = nil` (:96) and
  `setTouchGestureHandlers = nil` (:100).
- **Pattern:** "root-swap decorator over `screen_target.new`" — a genuinely elegant
  reuse; the removal-by-assignment idiom is the contract's own degrade mechanism
  (`target_contract.luau:6–8`).
- **Callers:** `games/RascalRally/code/src/client/LuauUISponsor/OmenState.luau:79`
  (the only production consumer of this target anywhere).
- **Lifecycle:** one adapter per billboard (ADR-0009:12); the game parents it to the
  kart part so it dies with the kart.
- **Proof:** `tests/render_target_contract.spec.luau:28` (the headless pixel-canvas
  half) and the Studio drive `artifacts/studio/part2-billboard.json`; ADR-0009 §7 for
  the bench proxy. Docs: `docs/adr/ADR-0009-billboard-target.md:8`,
  `docs/guide/02-architecture.md:115` — **nothing in `api.md`**.
- **Findings:** SEAM-14 (no reference entry for a target a shipping game depends on).

### `src/client/roblox_env.luau` / `roblox_input.luau` / `roblox_resources.luau`
- **Shipped shape:** `roblox_env.bind(env: any) -> () -> ()` (`roblox_env.luau:12`);
  `roblox_input.newSystem(core: any)` (`roblox_input.luau:17`);
  `roblox_resources.bind(provider: any) -> () -> ()` (`roblox_resources.luau:28`).
- **Pattern:** "single verb, single collaborator, returns an unbind closure" —
  `bind`/`bind`, with `newSystem` as the odd one out (a factory, matching
  `LuauUI.newActionSystem` which it replaces).
- **Callers:** RascalRally ×4 for env/input; `roblox_resources` has exactly one
  caller anywhere — `examples/gallery/scenarios/runner.luau:247`.
- **Lifecycle:** each returns its own unbind; the caller owns it. `roblox_input`
  returns a system whose disposal contract is the headless system's.
- **Proof:** none directly — all three reach engine globals at load and cannot be
  required headless; their behaviour is proven by the headless twins
  (`src/env/environment.luau`, `src/input/actions.luau`, `src/async/resources.luau`)
  plus Studio drives. Docs: `api.md:1668` (env, one sentence), `api.md:1693` (input,
  one clause), `api.md:1222` (resources, one clause), `docs/guide/03-getting-started.md:176–184`,
  `docs/guide/07-input.md:263`.
- **Findings:** SEAM-14; `roblox_resources` is the entry point documented in the
  reference but *missing* from the guide's client table.

### `src/client/edit_preview.luau` — client entry point (dev tooling)
- **Shipped shape:** `edit_preview.start(LuauUI: any, opts: StartOpts) -> handle`
  (:34), `StartOpts` at :25–32 (`parent`, `blueprint`, `profile?`, `style?`).
  Handle: `controller`, `profile`, `setProfile(name)` (:108), `refresh()` (:115),
  `dispose()` (:119).
- **Pattern:** *unique* — the only client entry point that takes the `LuauUI` table
  as a positional first argument (dependency injection, matching the composite-control
  `build(LuauUI, core, spec)` seam rather than the client-module seam).
- **Callers:** `tools/studio/LuauUI_EditPreview.plugin.lua` (per header :15) and the
  Studio command bar. No src, no test, no game caller.
- **Lifecycle:** best-in-class — the fallible section at :81–96 tears down every
  parented instance and re-raises so `start()` never orphans preview furniture
  (verifier F1), and `dispose()` (:119) disconnects the heartbeat, disposes the
  controller and root and destroys the decoration ScreenGui. The
  "always `dispose()` before saving the place" hazard is documented in the header
  (:12–14) and nowhere else.
- **Proof:** `tests/preview.spec.luau` covers `src/preview/device_profiles`, not this
  module (it cannot load headless). Docs: `docs/guide/02-architecture.md:28` names the
  file; no contract is documented anywhere.
- **Findings:** SEAM-14, SEAM-18.

### Client entry-point findings

- `[MAJOR, H]` **SEAM-14 — "the documented client entry points" is not a list
  anybody can read.** ADR-0011:29–31 makes the phrase load-bearing for the whole
  compatibility promise; `docs/reference/api.md` has no section for any of the seven
  (grep: `screen_target` ×2, `roblox_env` ×1, `roblox_input` ×1, `billboard_target`
  ×0, `edit_preview` ×0, all as passing mentions); the only enumeration is the
  architecture table at `docs/guide/02-architecture.md:28`, which lists six and omits
  `roblox_resources` — the one `api.md:1222` documents. Nothing mechanical checks
  either list (`check_registration.luau:159` reads only `src/init.luau`;
  `check_docs.luau:504` only the `themes` block). **User cost:** a consumer cannot
  tell which client modules are contract and which are internal; four of the five the
  game actually depends on have no documented signature at all.
- `[MINOR, H]` **SEAM-15 — `screen_target.Opts` is documented only in source
  comments.** Of the eight fields (`screen_target.luau:118–152`), `style` appears in
  `docs/guide/05-styling.md:71`, `nativeStyle` in `:192`, `rootFactory` in
  ADR-0009:8, and `isReducedMotion` in ADR-0006:8 — `parent`, `forceScrollFallback`,
  `forceDragFallback` and `themePackage` appear in no document. `style: any?`,
  `themePackage: any?` and the `nativeStyle` union's `model: any? / handle: any?` are
  also `any` at a public boundary. **User cost:** the Edit-mode/preview `parent`
  override and the two A/B fallback switches are discoverable only by reading a
  165 000-byte source file.
- `[MINOR, M]` **SEAM-16 — `theme_controller` exposes seven undocumented module
  functions.** `styleFor` (:121), `sheetModelFor` (:151), `sheetNameFor` (:164),
  `fontDescriptors` (:171), `dumpFromRecords` (:187), `dumpFromPackage` (:204),
  `profileOf` (:261) sit on the same public table as `install`; api.md:2251–2302
  documents `install` and the controller instance only. Four of them
  (`styleFor`, `sheetModelFor`, `sheetNameFor`, `fontDescriptors`) have **no caller
  anywhere outside the module** — internal helpers on a documented public entry point.
  **User cost:** no rule says which members of a client entry point are contract, so
  a consumer that adopts `sheetNameFor` has no way to know it may vanish in a patch.
- `[MINOR, M]` **SEAM-17 — six of `theme_controller.Opts`' 21 fields are
  undocumented, and one conditional requirement is missing.** api.md:2258–2268 names
  `env`, `rootGui`, `theme`, `selectBy` and then lists `core?, selectBySettleSeconds?,
  overrides?, host?, transitions?, forceFallback?, preflightFonts?, fontFiles?` in a
  comment. Undocumented: `facts`, `sheetModel`, `nativeStyle`, `selectBySettle`,
  `calibrate`, `warn` (`theme_controller.luau:217, 220, 221, 231, 233, 235`). The
  source says `core` is "REQUIRED with selectBy" (:230); api.md marks it `core?`.
  **User cost:** a `selectBy` install without `core` fails at a point the reference
  says is optional.
- `[MINOR, H]` **SEAM-18 — the install-verification list in the no-Rojo chapter is
  stale.** `docs/guide/08-without-rojo.md:56–57` tells a consumer to verify
  `async, client, controls, core, env, focus, input, layout, present, preview,
  render, replication, tokens` beneath `ReplicatedStorage.LuauUI` — omitting
  `motion` and `themes`, both of which are real `src/` directories that
  `src/init.luau:23–25, :140–155` requires at load. **User cost:** an install missing
  either folder passes the documented verification and then errors on first require.
- `[NOTE, M]` **SEAM-19 — seven entry points, five constructor shapes.**
  `screen_target.new(opts)` / `billboard_target.new(opts)` (opts table),
  `roblox_env.bind(env)` / `roblox_resources.bind(provider)` (single positional +
  unbind closure), `roblox_input.newSystem(core)` (positional factory),
  `theme_controller.install(adapter, package, opts?)` (two positional + opts),
  `edit_preview.start(LuauUI, opts)` (library-table DI + opts). Each is individually
  defensible; the set has no stated rule.

---

## Part 4 — The render-target adapter seam

### `src/render/target_contract.luau` — extension contract
- **Shipped shape:** `REQUIRED` — 6 names (:24–31: `createRoot`, `create`, `setRect`,
  `setProp`, `remove`, `destroyRoot`). `OPTIONAL` — 15 names (:33–97:
  `setActivateHandler`, `setFocusVisual`, `enableHover`, `setZOrder`,
  `setPointerHandlers`, `setTextInputHandlers`, `setScrollRegion`,
  `setScrollPosition`, `observeScroll`, `setEngineSelection`, `setVisible`,
  `setDragDetector`, `setTouchGestureHandlers`, `measureTextWidths`,
  `setRootVisible`). `FUTURE.surface` frozen (:112–134) with `openQuestions`
  (11 entries, :120–132). `check(adapter) -> { missing, optionalAbsent }` (:136).
- **Pattern:** "declared-name lists + a feature-detect checker" — the renderer probes
  optional methods with `~= nil` and calls required ones unconditionally (:2–8).
- **Callers:** `tests/render_target_contract.spec.luau:17` (the only caller of
  `check`); `docs/reference/api.md:2995–2999` and
  `docs/extending/new-platform-mode.md:23` reference `FUTURE.surface` by name.
  **Not exported from `src/init.luau`** (absent from the baseline surface).
- **Lifecycle:** static data + a pure function; nothing owned.
- **Proof:** `tests/render_target_contract.spec.luau` — `"the FakeTarget satisfies
  every required and optional method"` (:22), `"a billboard-sized pixel canvas
  renders a nameplate and updates paint-only"` (:28), plus the SF-M9 prop-parity
  trio: `"every prop the renderer can emit is handled by the LIVE adapter"` (:99),
  `"…by the FAKE adapter"` (:122), `"the two adapters agree: nothing is handled by one
  and not the other"` (:137), `"the FakeTarget REFUSES an undeclared prop instead of
  recording it"` (:166).
- **Findings:** SEAM-20, SEAM-21, SEAM-22, SEAM-23.

### Render-target findings

- `[MAJOR, H]` **SEAM-20 — the contract is missing nine adapter methods the
  framework actually calls.** The renderer calls, feature-detected, five names that
  appear in neither `REQUIRED` nor `OPTIONAL`: `getScrollPosition`
  (`renderer.luau:933`, :2543), `setHitRect` (:1923, :1961 — the 44 px effective-target
  floor, `src/controls/contract.luau:10`), `setScrollHandler` (:1589 — the
  `onScrollWheel` channel), `setNativeTransitionsEnabled` (:2446), `setRootDisplayOrder`
  (:2910). `theme_controller` calls four more: `themeRootGui`
  (`theme_controller.luau:445`), `setThemePackage` (:904, :1636), `relinkThemeSheet`
  (:1114, :1319, :1625), `nativeStyleInfo` (:432). `screen_target` implements all
  nine; `tests/lib/fake_target.luau` implements only five of them
  (`setNativeTransitionsEnabled`, `setThemePackage`, `nativeStyleInfo`,
  `themeRootGui` are absent). **User cost:** an author following the seam and passing
  `target_contract.check` with `#optionalAbsent == 0` ships a target with no
  hit-target expansion, no wheel scrolling, no display-order control, no
  reduced-motion transition suppression, and **no theming at all** — every one a
  silent degrade. It also weakens the headline case at
  `render_target_contract.spec.luau:22`: "satisfies every required and optional
  method" is true of the list, not of the seam.
- `[MINOR, H]` **SEAM-21 — the extension contract is reachable only by internal
  import.** `target_contract` is not in `src/init.luau` (confirmed against
  `baseline/public-surface-before.txt`), yet `api.md:2995` names
  `target_contract.FUTURE.surface` to the reader and
  `docs/extending/new-render-target.md:26` instructs an author to work against
  `src/render/target_contract.luau`. This is the documented "features usable only via
  internal imports" class — though note it is *inside* the library's own boundary
  rule (a target lives in `src/client/`, which may require it). **User cost:** an
  out-of-repo render target cannot check itself against the contract without an
  import ADR-0011:31 tells games not to make.
- `[MINOR, H]` **SEAM-22 — `setTouchGestureHandlers` is a declared optional seam
  nothing in the framework invokes.** Declared at `target_contract.luau:81`,
  implemented by `screen_target.luau:2713` and `fake_target.luau:570`, deliberately
  removed by `billboard_target.luau:100` — and a grep of `src/` finds no caller. Its
  only invocation anywhere is `examples/gallery/scenarios/drag_session.luau:170`.
  Combined with SEAM-3, the entire native-touch-gesture path is unreachable through
  normal LuauUI use and mis-wired where it is reachable. **User cost:** an adapter
  author implements a method that will never be called, and a consumer who reaches
  around for it gets the SEAM-3 empty gestures.
- `[NOTE, H]` **SEAM-23 — "ten unanswered questions" is eleven.**
  `target_contract.FUTURE.surface.openQuestions` holds eleven entries
  (`target_contract.luau:120–132`); `api.md:2997` says "its ten unanswered questions"
  and `docs/extending/new-platform-mode.md:26` says "one of the ten open questions".
  The eleventh — the "interactivity precondition" entry (:127) — reads as a later
  addition. **User cost:** trivially small; a spike planner counting the deliverable
  from the docs misses a row.

---

## Part 5 — Extension machinery

### `tools/lune/scaffold.luau` + `scaffold_cli.luau` — extension tooling
- **Shipped shape:** `scaffold.plan(kind, name) -> Plan` (:304, pure) and
  `scaffold.applyEdit(source, edit) -> string` (:361, pure and idempotent); CLI
  `lune run tools/lune/scaffold_cli <control|adapter> <lower_snake_name>`
  (`scaffold_cli.luau:11–18`). `kind = "control"` stamps
  `src/controls/<name>.luau` + `tests/<name>.spec.luau` and applies four registration
  edits (:327–351); `kind = "adapter"` stamps `src/client/<name>.luau` with **no**
  edits (:309–318).
- **Pattern:** "pure plan + thin applying CLI".
- **Verification of the control skeleton against the current house pattern —
  all four anchors resolve live:** `tests/run.luau:180` (`local ok = testkit.run()`),
  `tests/conformance/controls_registry.luau:567`
  (`-- scaffold: new control rows are appended above this line (anchor — keep)`),
  `src/init.luau:129` (`\t-- async resources`), and api.md append. The stamped
  template also matches the shipped seams: `build(LuauUI, core, spec)` and
  `{ blueprint, dump, dispose }` (`scaffold.luau:47, :112–118`) match
  `api.md:1909`'s `newTable(LuauUI, core, spec)`; `core:scope(label)` exists
  (`src/core/custom.luau:436`); `LuauUI.contribution.attach(blueprint, bundle)`
  exists (`src/init.luau:70`, `src/input/contribution.luau:106`); the registry-row
  template's field set (`scaffold.luau:243–274`) matches the documented row schema
  (`controls_registry.luau:12–56`); and the stamped case names ship verbatim in a
  real control's row — `tests/conformance/controls_registry.luau:511–527` (Chip) is
  the scaffold's text unchanged.
- **Proof:** `tests/extension_checker.spec.luau`;
  `tools/lune/check_registration.luau` §1/§5/§6 enforces the row the scaffold writes.
- **Findings:** SEAM-25 for the adapter branch; **the control branch is
  "follows the pattern, no deviation"**.

### `docs/extending/*.md` — the six playbooks
- **Shipped shape:** `new-control.md` (270 lines, 6 steps + traps),
  `new-engine-feature.md` (84), `new-platform-mode.md` (166),
  `new-render-target.md` (86), `new-theme.md`, `skinned-control.md`.
- **Cross-checks run this session:** every `src|tests|tools|docs|examples|artifacts|
  assets|bench` path cited across all six resolves to a real file (0 missing); every
  `lune run` command names a real tool (`scaffold_cli`, `check_registration_cli`,
  `check_prop_parity_cli`, `check_docs_cli`, `gate`) and both cited gate ids exist
  (`phase-4-hardening` at `tools/lune/gate_manifest.luau:543`,
  `theme-packages-and-skinning` at :1496); the CLI usage strings match
  (`scaffold_cli.luau:14` vs `new-control.md:28` / `new-render-target.md:16`);
  `new-platform-mode.md:23`'s "Shipped (contracts only)" row is accurate
  (`presentationSpace` `src/env/environment.luau:76`, `presentationProfile` :190,
  `capabilities.spatialPointer` :216, `LuauUI.spatial` `init.luau:127`,
  `target_contract.FUTURE.surface` :112).
- **Findings:** SEAM-26, SEAM-27, SEAM-28, SEAM-23 (shared with Part 4).

### Extension-machinery findings

- `[MINOR, H]` **SEAM-25 — the scaffolded adapter's `create` has the wrong arity.**
  `scaffold.luau:216` stamps `adapter.create(rootHandle, path, class)`; the contract
  is `create(rootHandle, path, class, decorationHint?, createOpts?)`
  (`target_contract.luau:26`, with the rationale at :12–17 — both are creation-time
  facts that "cannot arrive as a later prop write"). The scaffolded adapter therefore
  cannot ever skin a decoration slot or make a CanvasGroup, and nothing tells the
  author. `plan("adapter")` also applies **zero** registration edits (:316), so unlike
  the control path there is no registry row, no spec, and no api.md stub — the
  playbook asks for a spec in prose only (`new-render-target.md:29`).
  **User cost:** the scaffold's output is a contract the author will silently
  under-implement.
- `[MAJOR, M]` **SEAM-26 — `new-engine-feature.md` omits the two steps that make a
  new property work.** Its whole subject is adopting a new engine property, yet it
  never mentions `src/blueprint_schema.luau` (grep across `docs/extending/`: the only
  hit is `new-control.md:111`), and its gate list (`new-engine-feature.md:78–79`)
  omits `check_prop_parity_cli`. Since 0.5.0 strict authoring, a public property
  absent from the schema is rejected at construction
  (`ADR-0011:75–82`), and `check_prop_parity` is precisely the checker that pins
  schema ↔ dirty class ↔ authority ↔ renderer ↔ adapter `setProp` ↔ spec type ↔
  api.md (`tools/lune/check_prop_parity.luau:1–26`). `new-control.md:110–119` states
  both obligations correctly. **User cost:** an agent following
  `new-engine-feature.md` verbatim implements normalization, authority, renderer and
  adapter, then finds every `UI.*` call using the new prop erroring at construction
  with no step telling it why.
- `[MINOR, M]` **SEAM-27 — `new-render-target.md` teaches 4 of the seam's 15
  optional methods and none of the 9 undeclared ones.** Lines :19–22 list
  `setZOrder`, `setActivateHandler`, `setFocusVisual`, `setPointerHandlers` "plus your
  target-specific opts"; the contract has fifteen optional names
  (`target_contract.luau:33–97`), several of which (`setScrollRegion`/`observeScroll`,
  `setTextInputHandlers`, `setRootVisible`) gate whole features. Step 2 then tells the
  author to "assert your adapter satisfies the contract", using a checker that cannot
  see the nine methods in SEAM-20. Its gate list (:82–84) also omits
  `check_prop_parity_cli`, though a new target is exactly the SF-M9 defect class the
  parity checker exists for — and that checker hard-codes
  `SRC_ADAPTER = "src/client/screen_target.luau"`
  (`tools/lune/check_prop_parity.luau:39`), so a second live target is outside it
  either way. **User cost:** the playbook's completion bar is lower than the seam's.
- `[NOTE, M]` **SEAM-28 — the playbook set is enforced by two checkers with
  different lists.** `tools/lune/check_registration.luau:43–47` requires four
  playbooks (`new-control`, `new-engine-feature`, `new-platform-mode`,
  `new-render-target`); `new-theme.md` and `skinned-control.md` exist only in
  `check_docs.luau`'s anchor set (`PLAYBOOK` :37, `RUNG3_PLAYBOOK` :55).
  `docs/guide/README.md:76–86` advertises five of the six. No single place lists six.

---

## Part 6 — Versioning and deprecation (ADR-0011 compliance)

### `LuauUI.VERSION` / `LuauUI.DEPRECATIONS` — library metadata
- **Shipped shape:** `VERSION = "0.7.0"` (`src/init.luau:30`);
  `DEPRECATIONS = require("@self/blueprint_schema").deprecations()` (:35) typed as
  `{ { surface, since, removeNoEarlierThan, replacement, note? } }` (:36–43),
  currently two entries (`UI.Text.color`, `UI.Text.font` —
  `baseline/public-surface-before.txt:155–156`).
- **Pattern:** single-source constant + a **generated** ledger (ADR-0011:95–97: "the
  ledger itself is now GENERATED from the property schema, so an entry cannot go
  missing when a property is retired"). Verified: `init.luau:35` calls
  `schema.deprecations()`, it is not a hand-maintained array.
- **Enforcement actually shipped:**
  - VERSION single-source across prose: **strong** —
    `tools/lune/check_docs.luau:359–380` (`VERSION_DOCS`) + :705–726 fails when
    `api.md`, `guide/08-without-rojo.md`, `guide/README.md` or ADR-0011 names a
    version other than the `src/init.luau` constant.
  - Public surface ↔ api.md: `tools/lune/check_registration.luau:158–200` fails an
    undocumented top-level export **and** a documented non-export (both directions).
  - `LuauUI.themes` members ↔ api.md: `tools/lune/check_docs.luau:504–520`.
  - Ledger schema: `tests/api_surface.spec.luau:33` — `"deprecations are a
    machine-readable ledger with the ADR's required fields"`.
  - Semver shape + ADR naming: `tests/api_surface.spec.luau:18` — `"VERSION is a
    plain semver MAJOR.MINOR.PATCH (scaffold suffixes are gone)"`, :26 — `"the
    semver/deprecation ADR exists and states the policy"`.
- **Findings:** SEAM-29, SEAM-30, SEAM-31, SEAM-32.

### `tools/lune/check_boundary.luau` — the boundary claim
- **Shipped shape:** walks `src` only (`check_boundary.luau:85`), matching
  `require("…")` **double-quoted string literals** (:40) and flagging two rules:
  `non-client-requires-client` (:53) and `engine-free-zone-requires-engine-vendor`
  (:56–66). Writes `artifacts/boundary.json`, exits nonzero on any violation.
- **Findings:** SEAM-31.

### Versioning/deprecation findings

- `[MAJOR, H]` **SEAM-31 — the boundary checker does not check consumers, and
  cannot see the require form a consumer must use.** `src/init.luau:5–6` says client
  modules stay unexported "keeping this module safe for shared/server require graphs
  (UI-BOUND-001; enforced by tools/lune/check_boundary)", and ADR-0011:31 says
  "Games must not require library-internal modules". The checker walks only `src`
  (`check_boundary.luau:85`) — `games/`, `examples/` and `tests/` are never scanned —
  and its require pattern (:40) matches only `require("string")`, so the
  instance-path form (`require(ReplicatedStorage.LuauUI.client.screen_target)`,
  the *only* form available to a Roblox consumer, and also used inside `src` itself
  at `screen_target.luau:2718`) is invisible to it. What it does enforce — the
  intra-`src` layering rule and the engine-free-zone vendor rule — it enforces
  correctly. **User cost:** ADR-0011's consumer clause has no mechanical
  enforcement whatsoever. (Empirically the game complies today: RascalRally requires
  only `screen_target`, `roblox_env`, `roblox_input`, `billboard_target` — but that
  is discipline, not a gate.)
- `[MINOR, H]` **SEAM-29 — `api_surface.spec` pins the ledger's field *types* and
  nothing else about the policy.** `tests/api_surface.spec.luau:33–42` checks that
  each entry's four fields are strings. It does **not** check that `since` /
  `removeNoEarlierThan` are semver, that `removeNoEarlierThan` is at least one minor
  after `since` (ADR-0011:38–40 — the policy's core promise), that `replacement` is
  non-empty, or that api.md marks the surface deprecated (ADR-0011:41–44 claims "the
  API reference marks deprecated surfaces"). The ADR-naming check (:30) is a plain
  substring search for the version string anywhere in the ADR. The spec's own
  comment at :35 ("empty today; every future entry must carry the policy fields") is
  stale — two entries ship. **User cost:** the one rule a deprecation ledger exists
  to keep (a surface survives a minor) is unenforced.
- `[MINOR, H]` **SEAM-30 — `docs/guide/README.md:67` says `LuauUI.DEPRECATIONS` is
  "currently empty".** Two entries ship (`baseline/public-surface-before.txt:155–156`)
  and `api.md:24–39` describes them correctly. `check_docs`' `VERSION_DOCS` pins the
  version sentence in this same file but nothing pins this one. **User cost:** the
  first document a new consumer reads tells them nothing is deprecated when
  `UI.Text.color` and `UI.Text.font` now hard-error at construction.
- `[NOTE, M]` **SEAM-32 — the api.md coverage check is top-level-only and matches on
  a bare mention.** `check_registration.luau:159–162` reads only
  `\n\t<key> = ` from `src/init.luau`, and a key counts as documented if a backticked
  occurrence appears **anywhere** in api.md (:187) rather than in a `###` heading.
  Nested members are therefore unchecked outside `LuauUI.themes` — which is exactly
  how SEAM-6 (five undocumented registry members) and SEAM-10 (`tokens.dangerPair`)
  survive a green gate. **User cost:** the "every public export is documented"
  guarantee is weaker than it reads by roughly the size of every namespace export.

---

## Coverage

Every assigned item has an entry above.

**Input mechanics (7/7):** `newDragSession` ✓, `newDragRegistry` ✓,
`newDragVelocity` ✓, `newAutoscroll` ✓, `interactionTokens` ✓ *(no findings)*,
`touchGestures` ✓, `spatial` ✓.

**Styling (2/2):** `LuauUI.tokens` ✓, `LuauUI.themes` ✓ (all seven members —
`define`, `resolve`, `neutral`, `neutralPackage`, `lintProperty`, `checkCoverage`,
`SCHEMA`).

**Client entry points (7/7):** `theme_controller` ✓, `screen_target` ✓,
`billboard_target` ✓, `roblox_env` ✓, `roblox_input` ✓, `roblox_resources` ✓,
`edit_preview` ✓ — with the blessed-vs-required table in Part 3 and the explicit
result that **RascalRally requires nothing the docs do not bless**
(`screen_target`, `roblox_env`, `roblox_input`, `billboard_target`; all four in
`docs/guide/02-architecture.md:28`).

**Render-target seam (1/1):** `target_contract` ✓ — REQUIRED/OPTIONAL/FUTURE/`check`,
compared against `screen_target` (39 methods), `billboard_target` (2 removals) and
`tests/lib/fake_target.luau`.

**Extension machinery (2/2 + 6/6):** `scaffold.luau` + `scaffold_cli.luau` ✓
(control branch: no deviation; adapter branch: SEAM-25); all six playbooks
cross-checked ✓ (`new-control`, `new-engine-feature`, `new-platform-mode`,
`new-render-target`, `new-theme`, `skinned-control`).

**Versioning/deprecation (1/1):** ADR-0011 compliance ✓ — VERSION single-source,
generated DEPRECATIONS ledger, `tests/api_surface.spec.luau`, and
`tools/lune/check_boundary.luau`.

### Finding count

| Severity | Count | IDs |
|---|---|---|
| CRITICAL | 0 | — |
| MAJOR | 8 | SEAM-1, 2, 3, 12, 14, 20, 26, 31 |
| MINOR | 17 | SEAM-4, 5, 6, 7, 8, 10, 13, 15, 16, 17, 18, 21, 22, 25, 27, 29, 30 |
| NOTE | 6 | SEAM-9, 11, 19, 23, 28, 32 |
| **Total** | **31** | |

Confidence split: 19 findings at H, 12 at M, 0 at L.

Items with **no findings at all** (a success, per FORMAT.md): `interactionTokens`;
the `scaffold` control branch; the VERSION single-source enforcement chain; and the
game's client-entry-point compliance.

### Public but unassigned (reported, not audited)

- `LuauUI.contribution` (`src/init.luau:70`) — the public input-contribution seam the
  new-control playbook depends on; adjacent to this area but assigned elsewhere.
- `LuauUI.motion` (`init.luau:140–155`) and `LuauUI.text` (:170–174) — curated
  namespaces built with the same façade pattern as `LuauUI.themes`; the `any`-typing
  question in SEAM-12 likely applies to them too.
- `controller.dragRegistry()` (`src/render/renderer.luau:1160`) — a renderer-controller
  member that is the *primary* way a consumer reaches a drag registry, documented at
  `api.md:2896`; it belongs to the renderer/controller surface, not this fragment.
- `sheet_model.dangerPair` (`src/tokens/sheet_model.luau:268`) — a second public name
  for `tokens.dangerPair`; duplicate vocabulary, but `sheet_model` is not an exported
  module, so it is only reachable internally.
- `screen_target`'s 18 adapter methods outside `target_contract` (e.g.
  `chromeCensus`, `connectionCensus`, `chromeArtJudgement`, `getInstance`,
  `driveActivate`, `themeAssetsToPreload`, `setChromeAssetLoaded`) — instrumentation
  and theme seams that are neither contract nor documented; nine of them are called
  by the framework and are covered by SEAM-20, the rest are test/diagnostic surface.
