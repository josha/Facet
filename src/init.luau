--!strict
-- Facet public entry point (design §5): the game-agnostic, engine-free
-- surface. Client-only modules (ScreenTarget, roblox_env, roblox_input) are
-- NOT exported here — client entry points require them from @self/client/*
-- directly, keeping this module safe for shared/server require graphs
-- (UI-BOUND-001; enforced by tools/lune/check_boundary).
-- Library-internal requires stay RELATIVE/@self so the same source runs
-- headless under lune and mounted under Rojo.

local coreContract = require("@self/core/contract")
local blueprint = require("@self/blueprint")
local environment = require("@self/env/environment")
local rendererLib = require("@self/render/renderer")
local actionsLib = require("@self/input/actions")
local replication = require("@self/replication/adapters")
local tokensLib = require("@self/tokens/tokens")
local focusLib = require("@self/focus/focus_graph")
local transitionsLib = require("@self/render/transitions")
local rowActions = require("@self/controls/row_actions")
local asyncResources = require("@self/async/resources")
local controlTypes = require("@self/control_types")
export type App = controlTypes.App
export type Controls = controlTypes.Controls
export type ButtonSpec = controlTypes.ButtonSpec
export type ToggleSpec = controlTypes.ToggleSpec
export type ComboBoxSpec = controlTypes.ComboBoxSpec
export type SplitButtonSpec = controlTypes.SplitButtonSpec
export type ChipSpec = controlTypes.ChipSpec
export type AsyncImageSpec = controlTypes.AsyncImageSpec
export type VirtualListSpec<T> = controlTypes.VirtualListSpec<T>
export type VirtualGridSpec<T> = controlTypes.VirtualGridSpec<T>
local themesPackage = require("@self/themes/package")
local themesSnapshot = require("@self/themes/snapshot")
local motionClasses = require("@self/motion/classes")
local motionCurves = require("@self/motion/curves")

-- The core contract types, so a typed helper or an out-of-repo control can name
-- them. `core/contract` is pure types, and they are Compose's own: state is a
-- `Cell`, derivation is a `Formula`, either is a `Readable`, and a lifetime is
-- an `Owner`.
export type Core = coreContract.Core
export type Owner = coreContract.Owner
export type Cell<T> = coreContract.Cell<T>
export type Formula<T> = coreContract.Formula<T>
export type Readable<T> = coreContract.Readable<T>
export type Unsubscribe = coreContract.Unsubscribe
export type ActivationMetadata = blueprint.ActivationMetadata

export type Deprecation = {
	surface: string,
	since: string,
	removeNoEarlierThan: string,
	replacement: string,
	note: string?,
}

-- Declared deprecations: the half of the ledger that is not a blueprint
-- property. Same record shape as `blueprint_schema.deprecations()`.
local DECLARED_DEPRECATIONS: { Deprecation } = {
	{
		surface = "Controls.PopupButton",
		since = "0.11.0",
		removeNoEarlierThan = "0.12.0",
		replacement = 'Controls.Picker { style = "menu" | "navigationLink", ... }',
		note = "the alias remains available on app.controls; Picker owns single-value selection",
	},
	{
		surface = "newResourceProvider(opts.retryAttempts)",
		since = "0.8.0",
		removeNoEarlierThan = "0.9.0",
		replacement = "opts.retry = { count, delaySeconds?, giveUp? }",
		note = "legacy immediate-retry semantics preserved until removal",
	},
	{
		surface = "adaptive.conditions().contentWidth",
		since = "0.8.0",
		removeNoEarlierThan = "0.9.0",
		replacement = "viewportWidth",
		note = "alias; the value never subtracted insets",
	},
	-- The renderer pushes the environment's `reducedMotion` fact into
	-- `adapter.setReducedMotion`; this closure is OR-ed with it, so a harness can
	-- force reduced motion on, never off.
	{
		surface = "screen_target.new(opts.isReducedMotion)",
		since = "0.9.0",
		removeNoEarlierThan = "0.10.0",
		replacement = "adapter.setReducedMotion, pushed by the renderer from the environment",
		note = "still accepted, and now OR-ed with the pushed fact: it can force reduced motion on, "
			.. "never off. `billboard_target.new(opts.isReducedMotion)` forwards it and retires with it",
	},
	-- VirtualList's two extent names from before it had a second axis. Both
	-- still work on a vertical list; passing the old and new name together is
	-- refused at construction, because it is one field.
	{
		surface = "UI.VirtualList(spec.rowHeight)",
		since = "0.9.0",
		removeNoEarlierThan = "0.10.0",
		replacement = "itemExtent",
		note = 'axis-neutral rename; alias still accepted and identical on axis = "y"',
	},
	{
		surface = "UI.VirtualList(spec.viewportHeight)",
		since = "0.9.0",
		removeNoEarlierThan = "0.10.0",
		replacement = "viewportExtent",
		note = 'axis-neutral rename; alias still accepted and identical on axis = "y"',
	},
	{
		surface = "UI.Picker.presentation",
		since = "0.11.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "UI.Picker.style (automatic | menu | segmented | inline | radioGroup | navigationLink)",
		note = "same values, the reference platform's spelling; `radio` reads as `radioGroup`",
	},
}

-- the ledger is the UNION of both halves, in a deterministic order: every
-- schema-generated entry (already sorted by class then prop) followed by the
-- declared list in declaration order. Frozen: it is machine-readable authority,
-- not a scratch table a consumer can edit.
local function buildDeprecations(): { Deprecation }
	local ledger: { Deprecation } = {}
	for _, entry in require("@self/blueprint_schema").deprecations() do
		table.insert(ledger, entry)
	end
	for _, entry in DECLARED_DEPRECATIONS do
		table.insert(ledger, entry)
	end
	return table.freeze(ledger)
end

local Facet = {
	-- semantic version: MAJOR.MINOR.PATCH; pre-1.0 the minor
	-- tracks the completed design phase. Bump here AND in the changelog.
	VERSION = "0.11.0",

	-- The flat, non-overridable exit cap: no exit's teardown defers past this many
	-- seconds of clock time. `src/render/transitions.luau` enforces it; a consumer
	-- ticking a stepped clock past a dismissed surface's teardown reads it here.
	EXIT_CAP_SECONDS = transitionsLib.EXIT_CAP_SECONDS,

	-- Deprecation ledger: schema-generated property deprecations plus the
	-- declared list above. A deprecated surface keeps working for at least one
	-- minor version after `since`. Frozen.
	DEPRECATIONS = buildDeprecations(),

	-- Read-only constructor facts for extension authors and contract tooling.
	schema = table.freeze(table.clone(blueprint.schema)),

	-- environment and rendering seams
	newEnvironment = environment.new,
	renderer = rendererLib,
	-- surface chrome: a pure back+title+trailing bar factory —
	-- `Facet.navBar({ onBack, title, trailing })` -> Blueprint
	navBar = require("@self/present/nav_bar").build,

	-- input pipeline (headless model; the client swaps in roblox_input)
	newActionSystem = actionsLib.newSystem,

	-- reactive input-affordance hint: inputHint(core, env,
	-- action) -> Readable<string> tracking env preferredInput + preferredBinding
	inputHint = require("@self/input/hint").inputHint,

	-- input-contribution seam (docs/extending/new-control.md step 3).
	-- PUBLIC because the control playbook's recipe needs it: a composite
	-- advertises its four-input story by attaching a bundle to its blueprint
	-- root, and before Milestone 0 that recipe told extension authors to import
	-- an unexported library-internal module — a seam the boundary checker
	-- forbids consumers from using.
	contribution = require("@self/input/contribution"),

	valueModel = require("@self/controls/value_model"),

	-- pure Path2D shape math for UI.Path (the native substrate):
	-- rings/arcs/needles as normalized control points, headlessly tested
	pathShapes = require("@self/controls/path_shapes"),

	--[[ THE MARKUP DOOR, for `UI.Text{ rich = true }`.

		`escape(s)` is the one function a consumer needs and the one it must not
		write itself: composing a player name, a server string or any other value
		it did not author into markup without escaping it either paints the value
		as a tag or breaks the parse for the whole label. It escapes the five
		characters the engine's parser reads and nothing else, so calling it on
		text that is already plain is safe.

		IT IS NOT A TEXT FILTER. Whether a player may say a thing at all is the
		game's and the server's decision, through the platform's own filtering;
		this is only the difference between text and markup. ]]
	richText = table.freeze({ escape = require("@self/layout/rich_text").escape }),

	--[[ THE CLOSED-KEY-SET GUARD, so an out-of-repo control can be as strict as an
		in-repo one (constitution §4).

		Twenty-two control modules in `src/` require this, and the extension
		playbook (`docs/extending/new-control.md`) tells an author their control
		must refuse an unknown spec key and name the legal set — while the only
		implementation of that was library-internal and reachable by no public
		route. A rule an author is asked to follow with nothing to follow it WITH
		is a rule that gets skipped, and the strictness the framework promises then
		stops at the repository boundary.

		`assertKnownKeys(where, tbl, known, kind)` + `keySet(names)`. It requires
		nothing, so it is safe from anywhere. ]]
	specGuard = require("@self/spec_guard"),

	-- row actions: pure swipe state verdicts (axis lock, rubber-band, settle)
	-- for row-swipe interaction. No instance, no mount; verdicts are return values.

	-- pure drag-session model + native touch-gesture normalization/arbitration
	-- (corrections addendum §1/§2): framework policy over engine-owned motion
	newDragSession = require("@self/input/drag_session").new,
	-- PUBLIC DRAG/DROP. The blueprint face is
	-- `UI.draggable` / `UI.dropTarget`; these are the pieces underneath, exported
	-- because a control that builds its own rows needs them directly and because
	-- each is independently testable:
	--   interactionTokens  the per-input-class press→drag promotion thresholds —
	--                      the ONE place mouse 6 px / touch 14 px live
	--   newDragVelocity    the rolling 0.1 s release-velocity tracker (injected
	--                      time; read at release BEFORE any state reset)
	--   newAutoscroll      the pure drag-to-edge autoscroll model (band, dwell,
	--                      ramp, clamp) — it answers a delta, it scrolls nothing
	--   newDragRegistry    a surface's live source/target set plus the one
	--                      session every input class drives. The renderer builds
	--                      one per surface automatically; this is for a host that
	--                      owns its own.
	interactionTokens = require("@self/input/interaction_tokens"),
	newDragVelocity = require("@self/input/drag_velocity").new,
	newAutoscroll = require("@self/input/autoscroll").new,
	newDragRegistry = require("@self/input/drag_registry").new,
	touchGestures = require("@self/input/touch_gestures"),
	-- SPATIAL EVENT SEAM — contracts only, no VR support claim. The
	-- optional ray/hit/pose/handedness/phase/target a normalized pointer event
	-- may one day carry, plus the readers a consumer uses to ask. Public because
	-- the compatibility promise is a public one: `pos.x`/`pos.y` keep meaning
	-- what they mean, and `spatial.isFlat(pos)` is true for every event Facet
	-- produces today.
	spatial = require("@self/input/spatial"),
	-- row-actions Task 7: at most one row open per shared list surface. A
	-- VStack/ScrollView list creates its own and shares it across every
	-- wrapped row's `coordinator` spec key; Table's own `rowActions` wiring
	-- (Task 10) does this for its rows automatically.
	newRowActionsCoordinator = rowActions.newCoordinator,
	-- async resources (§10.3): bounded, cancellable, generation-checked
	newResourceProvider = asyncResources.newProvider,

	-- MOTION AUTHORITY: all value motion in one pure,
	-- engine-free place, stepped by an injectable clock — the client binds
	-- `clock:step()` to RunService.PreRender at the adapter edge, the headless
	-- suite steps a scripted one. Feel-carrying call sites cite a motion CLASS
	-- name (`registerClass` for your own); inline `{ dampingRatio, response }`
	-- literals are refused, so a design system has one place to tune. Motion
	-- drives SIGNALS only — it never writes solver geometry and never writes a
	-- native-sheet-owned property.
	motion = {
		newClock = require("@self/motion/clock").new,
		registerClass = motionClasses.registerClass,
		resolveClass = motionClasses.resolve,
		classNames = motionClasses.names,
		isRegisteredClass = motionClasses.isRegistered,
		resetClasses = motionClasses.reset,
		--[[ ...and the CURVE vocabulary, the other half of the dial.
			A class is physics with no authorable duration; a curve is
			`{ duration, style, direction? }` — the shape every design handoff arrives
			in, and the only way to command "over exactly 400 ms" or to make a cooldown
			land ON TIME (a spring approaches its target asymptotically and cannot).
			The registry ships EMPTY on purpose: 400 ms is a decision about one
			surface where a spring's two numbers generalize, so registering a curve IS
			the act of choosing it, once, with a name — and an inline spec table at a
			call site is refused exactly as an inline spring literal is.
			`style` is Roblox's own `Enum.EasingStyle` vocabulary spelled lower-camel,
			and on Roblox the engine's `TweenService:GetValue` IS the evaluator,
			installed by `motion_driver.bind`. ]]
		registerCurve = motionCurves.registerCurve,
		resolveCurve = motionCurves.resolve,
		curveNames = motionCurves.names,
		isRegisteredCurve = motionCurves.isRegistered,
		resetCurves = motionCurves.reset,
		--[[ "Hold a number at what it WAS, then move it to what it IS, on cue, and
			land the truth whatever happens" (2026-08-02). A consumer grew this state
			machine twice in one file and every reported bug across two review rounds
			was in one of the copies — none of them about the number, all of them
			about the shape: what "not yet" means, what order the seed and the flag go
			in, and which paths count as abandoning. `newValueReveal` is that shape,
			once. It owns no clock and no signals; the caller passes its own. ]]
		newValueReveal = require("@self/motion/value_reveal").new,
		--[[ "Show a string as it arrives, never a half-glyph, and never a
			placeholder where a value already is." The text twin of
			`newValueReveal`, and the same shape: it owns no clock and no signals,
			so it composes with whatever model is already streaming the string. ]]
		newTextReveal = require("@self/motion/text_stream").new,
	},

	-- adaptive-layout decisions: the PURE
	-- breakpoint/axis/column functions plus `conditions(env)`, which
	-- returns Readables a screen binds so adaptation never becomes a
	-- device-name branch. Bind `conditions(...).axis` to UI.AdaptiveStack.
	adaptive = require("@self/layout/adaptive"),

	--[[ TEXT MEASUREMENT, made reachable (2026-08-02). `text.measure` is the
		library's own engine — per-font calibration, per-role line height, real
		wrapping, the CJK/emoji full-em path — and `text.fit`/`text.size` answer the
		question every consumer was re-deriving on top of it with a guessed average
		glyph width: "what size makes THIS string fit THIS box?". It was internal to
		the solver, so a presenter had no way to ask, and three private
		approximations of the same 0.62 fallback constant had grown in one game. ]]
	--[[ ...and `facts`/`lineBox`, the answer to "how tall is N lines of this text
		going to be?" (ruled 2026-08-15, docs/plans/variable-item-extents.md).
		Declaring a correct `itemExtent` or a composition floor used to mean
		hand-reproducing the solver's text arithmetic — the `max(typographyScale,
		typographyPaintScale)`, the ADDITIVE `preferredTextOffset`, and the live
		theme's line height for the role. A survey found seven near-duplicates of
		that formula in-repo and exactly one correct. These two are the one
		implementation, and they spend the solver's own seams
		(`text_metrics.reservedSize` / `.lineBoxPx`) rather than a copy of them.
		Reach for `UI.VirtualList` with `itemExtent = "measured"` instead whenever
		the row can measure itself — that removes the prediction rather than making
		it easier. ]]
	text = {
		measure = require("@self/layout/text_metrics").measure,
		fit = require("@self/layout/text_fit").fit,
		size = require("@self/layout/text_fit").size,
		facts = require("@self/layout/text_fit").facts,
		lineBox = require("@self/layout/text_fit").lineBox,
		-- the fallback fraction itself (framework-gaps-phase2 gap 11), so a
		-- CALLER that already holds this table can source it rather than
		-- hand-copying it — RascalRally's HudZoneModel.fitSize used to, as
		-- `GLYPH_EM = 0.62`, under a comment misidentifying it as "Gotham Bold
		-- cap advance" (a number about no font at all, since the fallback is
		-- uniform). `src/measure.luau` publishes the same field for a consumer
		-- that has no `Facet` table to hold in the first place
		AVG_GLYPH_FRACTION = require("@self/layout/text_metrics").AVG_GLYPH_FRACTION,
	},

	-- DECLARED-CONTENT ADAPTIVE COMPOSITION: the PURE half of the
	-- screen-level sibling of AdaptiveStack and ViewThatFits. `UI.Composition` /
	-- `UI.Region` are the declaration face; this is the decision itself —
	-- `resolve(decl, offer, { measure })` answers WHICH arrangement, WHICH form
	-- per region and WHY every richer candidate lost, with no mount, no engine
	-- and no theme, so a whole device matrix is a headless sweep. `dump` is the
	-- diagnostic surface the solve publishes; `normalize` is the one ruling on
	-- what a declaration may say; `floorPx` turns a CONTENT floor ("one line",
	-- "two targets") into pixels against a live theme snapshot.
	composition = require("@self/layout/composition"),

	--[[ PURE LAYOUT GEOMETRY, made reachable (framework-gaps-phase2 gap 33):
		`transformFootprint(w, h, scale, deg)` is the reserved-box math a scaled/
		rotated node's PARENT needs to avoid a spillover (`scale`/`rotation` are
		paint-only, so the solver reserves the unscaled box and the engine draws
		the transformed one) — the formula `docs/reference/api.md`'s `scale` row
		already documents in prose, published here so a consumer computes the
		reservation instead of hand-transcribing the trigonometry (as
		`examples/gallery/scenarios/nested_compositing.luau` used to).

		`anchorPlacement(request)` is the same move for gap 39 (`armStaging`
		"as a declaration rather than a coordinate"): the pure edge/flip/shift/
		tail decision `present/anchored.luau`, the disclosure plate and
		`UI.RowActions`' floating menu already share, published so a consumer can
		DECLARE a placement — "above the source, centred, gapped by N" — instead
		of hand-computing the point, the way RascalRally's `HandDock` staging
		spot used to. ]]
	layout = {
		worldMarkers = require("@self/layout/world_markers").solve,
		hudInsets = require("@self/layout/hud_insets").solve,
		transformFootprint = require("@self/layout/transform_footprint").transformFootprint,
		anchorPlacement = require("@self/layout/anchor_placement").solve,
	},

	-- focus, replication, tokens
	newFocusGraph = focusLib.new,
	replication = replication,
	tokens = tokensLib,

	-- theme packages: the PURE half of the theme system — compile a
	-- declarative package, resolve it to the frozen metric snapshot the solver
	-- and renderer read, and reach Facet Neutral as a derivation base. The
	-- client-side controller (sheet materialization, per-target install, the
	-- swap transaction) lives behind the client entry point, so this module
	-- stays safe for shared/server require graphs (UI-BOUND-001).
	themes = {
		define = themesPackage.define,
		resolve = themesSnapshot.resolve,
		neutral = themesSnapshot.neutral,
		-- the compiled Facet Neutral package: pass it as `base` to start from
		-- the library's own theme and override only what you mean to change
		neutralPackage = themesSnapshot.neutralPackage,
		--[[ THE APP NAMESPACE. One call at app boot reserves the `app.*`
			names your own structural numbers live under — `declareApp{ tileMin = 96 }`
			— and from then on `px = "app.tileMin"` is spellable everywhere
			`px = "iconSizes.large"` is: validated at construction, resolved on every
			package, moved by `metrics.app` when a theme wants a different answer, and
			carried up the ten-foot ladder like any other length. `appMetrics()` reads
			the declaration back, frozen. ]]
		declareApp = themesSnapshot.declareApp,
		appMetrics = themesSnapshot.appMetrics,
		--[[ THE TEN-FOOT METRIC LADDER (director ruling 2026-08-20). The
			environment applies `forDisplay` for you at its `themeMetrics` read, so a
			consumer almost never calls these — they are public because a consumer
			who PREDICTS geometry (rather than resolving a metric name) needs the
			same factor the framework spends, and because `baseOf` is what makes a
			read-hold-write round trip of the metric fact exact. `densityClassOf`
			is the published classification: which numeric metric paths the ladder
			moves, and which it deliberately leaves alone. ]]
		metricScale = themesSnapshot.metricScale,
		forDisplay = themesSnapshot.forDisplay,
		--[[ …and the PAINT half of the same ladder (director ruling 2026-08-21).
			`forDisplay` adapts what the framework MEASURES; this adapts the
			`radii`/`strokes` a paint authority DRAWS, off the same factor. A
			consumer that builds its own render target — rather than taking
			`client.host`'s — is the caller who needs it: hand `screen_target.new`
			the environment's `displaySize` and the target spends this for you. ]]
		paintForDisplay = themesSnapshot.paintForDisplay,
		baseOf = themesSnapshot.baseOf,
		densityClassOf = themesSnapshot.densityClassOf,
		-- the §4 legal-property linter, exported so a materializer or an
		-- authoring tool rules on a property exactly as compilation does
		lintProperty = themesPackage.lintProperty,
		-- the pre-play gate for contributed controls: a control
		-- declares its namespaced needs and asks whether a package covers them
		-- — complete treatment or a useful error, never silence
		checkCoverage = themesPackage.checkCoverage,
		SCHEMA = themesPackage.SCHEMA,
	},
}

-- Requiring Facet remains safe in shared code. Engine services are only resolved
-- when a client explicitly starts an application.
Facet.Compose = require("@self/vendor/compose/core")
function Facet.new(opts: any?): controlTypes.App
	return require("@self/client/application").new(opts)
end

-- The two theme reads a client needs BEFORE a surface exists: the boot `style`
-- for `Facet.new`, and the sheet model `app.installTheme` accepts. Resolved on
-- call, like `Facet.new`, so the shared require graph stays engine-free.
function Facet.themes.styleFor(package: any, themeName: string?, displaySize: string?)
	return require("@self/client/application").styleFor(package, themeName, displaySize)
end
function Facet.themes.sheetModelFor(package: any, displaySize: string?)
	return require("@self/client/application").sheetModelFor(package, displaySize)
end

return Facet
