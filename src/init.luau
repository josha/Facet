--!strict
-- LuauUI public entry point (design Â§5): the game-agnostic, engine-free
-- surface. Client-only modules (ScreenTarget, roblox_env, roblox_input) are
-- NOT exported here â client entry points require them from @self/client/*
-- directly, keeping this module safe for shared/server require graphs
-- (UI-BOUND-001; enforced by tools/lune/check_boundary).
-- Library-internal requires stay RELATIVE/@self so the same source runs
-- headless under lune and mounted under Rojo.

local coreContract = require("@self/core/contract")
local customCore = require("@self/core/custom")
local blueprint = require("@self/blueprint")
local mountLib = require("@self/mount")
local environment = require("@self/env/environment")
local rendererLib = require("@self/render/renderer")
local presenterLib = require("@self/present/presenter")
local actionsLib = require("@self/input/actions")
local replication = require("@self/replication/adapters")
local tokensLib = require("@self/tokens/tokens")
local focusLib = require("@self/focus/focus_graph")
local tableControl = require("@self/controls/table")
local virtualList = require("@self/controls/virtual_list")
local asyncResources = require("@self/async/resources")
local themesPackage = require("@self/themes/package")
local themesSnapshot = require("@self/themes/snapshot")
local motionClasses = require("@self/motion/classes")

-- THE CORE CONTRACT TYPES, REACHABLE (F-28). `src/core/contract.luau` is pure
-- types and no code, and until now nothing re-exported it from the public entry
-- — so an author writing a typed helper (`function build(core: ???, …)`) had no
-- name to write and no way to import one, and the library's own boundaries said
-- `core: any` 35 times. These are erased at runtime (the module returns nil),
-- and it requires nothing, so the entry point stays safe for shared/server
-- require graphs (UI-BOUND-001).
export type Core = coreContract.Core
export type Scope = coreContract.Scope
export type Signal<T> = coreContract.Signal<T>
export type Memo<T> = coreContract.Memo<T>
export type Readable<T> = coreContract.Readable<T>
export type Unsubscribe = coreContract.Unsubscribe

export type Deprecation = {
	surface: string,
	since: string,
	removeNoEarlierThan: string,
	replacement: string,
	note: string?,
}

-- DECLARED deprecations (ADR-0011): the half of the ledger that is not a
-- blueprint PROPERTY. `blueprint_schema.deprecations()` can only speak about
-- props, so an opts field or a derived condition had nowhere to be declared and
-- the machinery simply did not know about it. Both halves are the same record
-- shape, so every consumer of DEPRECATIONS reads one list.
local DECLARED_DEPRECATIONS: { Deprecation } = {
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

local LuauUI = {
	-- semantic version (ADR-0011): MAJOR.MINOR.PATCH; pre-1.0 the minor
	-- tracks the completed design phase. Bump here AND in the ADR.
	VERSION = "0.9.0",

	-- deprecation ledger (ADR-0011): { surface, since, removeNoEarlierThan,
	-- replacement, note? } per entry; a deprecated surface keeps working for
	-- at least one minor version after `since`. Schema-generated property
	-- deprecations plus the declared list above — complete, machine-readable,
	-- and frozen.
	DEPRECATIONS = buildDeprecations(),

	-- reactive foundation (ADR-0002: custom core)
	newCore = customCore.new,

	-- declarative blueprints (UI.Screen / VStack / Text / Button / ...)
	UI = blueprint,

	-- mounting, environment, rendering, presentation
	mount = mountLib.mount,
	newEnvironment = environment.new,
	renderer = rendererLib,
	newPresenter = presenterLib.new,

	-- input pipeline (headless model; the client swaps in roblox_input)
	newActionSystem = actionsLib.newSystem,

	-- reactive input-affordance hint (ADR-0013 WP-4): inputHint(core, env,
	-- action) -> Readable<string> tracking env preferredInput + preferredBinding
	inputHint = require("@self/input/hint").inputHint,

	-- input-contribution seam (ADR-0013; docs/extending/new-control.md step 3).
	-- PUBLIC because the control playbook's recipe needs it: a composite
	-- advertises its four-input story by attaching a bundle to its blueprint
	-- root, and before Milestone 0 that recipe told extension authors to import
	-- an unexported library-internal module — a seam the boundary checker
	-- forbids consumers from using.
	contribution = require("@self/input/contribution"),

	-- composite controls (ADR-0007; VirtualList §10.5 first release)
	newTable = tableControl.build,
	newVirtualList = virtualList.build,

	newPopupButton = require("@self/controls/popup_button").build,
	-- value-control family (swiftui-parity-next investment 4): Stepper and Slider
	-- are different affordances over ONE shared value model, so bounds, stepping,
	-- rounding, formatting and semantic value text cannot disagree at the edges.
	newStepper = require("@self/controls/stepper").build,
	newSlider = require("@self/controls/slider").build,
	-- ...and the small discrete one: a run of glyphs that reads as ONE value and
	-- takes ONE focus stop, instead of the N buttons every app writes by hand
	newRating = require("@self/controls/rating").build,
	-- display controls (swiftui-parity-next investment 7)
	newProgressView = require("@self/controls/progress_view").build,
	newLabel = require("@self/controls/label").build,
	newPicker = require("@self/controls/picker").build,
	newDisclosureGroup = require("@self/controls/disclosure_group").build,
	valueModel = require("@self/controls/value_model"),
	newTextInput = require("@self/controls/text_input").build,

	-- pure Path2D shape math for UI.Path (native-substrate NS-A7):
	-- rings/arcs/needles as normalized control points, headlessly tested
	pathShapes = require("@self/controls/path_shapes"),

	-- row actions: pure swipe state verdicts (axis lock, rubber-band, settle)
	-- for row-swipe interaction. No instance, no mount; verdicts are return values.

	-- async image over the resource provider (native-substrate NS-A14)
	newAsyncImage = require("@self/controls/async_image").build,
	-- pure drag-session model + native touch-gesture normalization/arbitration
	-- (corrections addendum §1/§2): framework policy over engine-owned motion
	newDragSession = require("@self/input/drag_session").new,
	-- PUBLIC DRAG/DROP (ADR-0022 Decision 5). The blueprint face is
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
	-- SPATIAL EVENT SEAM (ADR-0021) — contracts only, no VR support claim. The
	-- optional ray/hit/pose/handedness/phase/target a normalized pointer event
	-- may one day carry, plus the readers a consumer uses to ask. Public because
	-- the compatibility promise is a public one: `pos.x`/`pos.y` keep meaning
	-- what they mean, and `spatial.isFlat(pos)` is true for every event LuauUI
	-- produces today.
	spatial = require("@self/input/spatial"),
	newChip = require("@self/controls/chip").build,
	newRowActions = require("@self/controls/row_actions").build,
	-- row-actions Task 7: at most one row open per shared list surface. A
	-- VStack/ScrollView list creates its own and shares it across every
	-- wrapped row's `coordinator` spec key; Table's own `rowActions` wiring
	-- (Task 10) does this for its rows automatically.
	newRowActionsCoordinator = require("@self/controls/row_actions").newCoordinator,
	-- async resources (§10.3): bounded, cancellable, generation-checked
	newResourceProvider = asyncResources.newProvider,

	-- MOTION AUTHORITY (ADR-0022 Decision 1): all value motion in one pure,
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
		--[[ "Hold a number at what it WAS, then move it to what it IS, on cue, and
			land the truth whatever happens" (2026-08-02). A consumer grew this state
			machine twice in one file and every reported bug across two review rounds
			was in one of the copies — none of them about the number, all of them
			about the shape: what "not yet" means, what order the seed and the flag go
			in, and which paths count as abandoning. `newValueReveal` is that shape,
			once. It owns no clock and no signals; the caller passes its own. ]]
		newValueReveal = require("@self/motion/value_reveal").new,
	},

	-- adaptive-layout decisions (swiftui-parity-next investment 5): the PURE
	-- breakpoint/axis/column functions plus `conditions(core, env)`, which
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
	text = {
		measure = require("@self/layout/text_metrics").measure,
		fit = require("@self/layout/text_fit").fit,
		size = require("@self/layout/text_fit").size,
	},

	-- DECLARED-CONTENT ADAPTIVE COMPOSITION (ADR-0023): the PURE half of the
	-- screen-level sibling of AdaptiveStack and ViewThatFits. `UI.Composition` /
	-- `UI.Region` are the declaration face; this is the decision itself —
	-- `resolve(decl, offer, { measure })` answers WHICH arrangement, WHICH form
	-- per region and WHY every richer candidate lost, with no mount, no engine
	-- and no theme, so a whole device matrix is a headless sweep. `dump` is the
	-- diagnostic surface the solve publishes; `normalize` is the one ruling on
	-- what a declaration may say; `floorPx` turns a CONTENT floor ("one line",
	-- "two targets") into pixels against a live theme snapshot.
	composition = require("@self/layout/composition"),

	-- focus, replication, tokens
	newFocusGraph = focusLib.new,
	replication = replication,
	tokens = tokensLib,

	-- theme packages (ADR-0019): the PURE half of the theme system — compile a
	-- declarative package, resolve it to the frozen metric snapshot the solver
	-- and renderer read, and reach Studio Neutral as a derivation base. The
	-- client-side controller (sheet materialization, per-target install, the
	-- swap transaction) lives behind the client entry point, so this module
	-- stays safe for shared/server require graphs (UI-BOUND-001).
	themes = {
		define = themesPackage.define,
		resolve = themesSnapshot.resolve,
		neutral = themesSnapshot.neutral,
		-- the compiled Studio Neutral package: pass it as `base` to start from
		-- the library's own theme and override only what you mean to change
		neutralPackage = themesSnapshot.neutralPackage,
		-- the §4 legal-property linter, exported so a materializer or an
		-- authoring tool rules on a property exactly as compilation does
		lintProperty = themesPackage.lintProperty,
		-- the pre-play gate for contributed controls (ADR-0019 §1): a control
		-- declares its namespaced needs and asks whether a package covers them
		-- — complete treatment or a useful error, never silence
		checkCoverage = themesPackage.checkCoverage,
		SCHEMA = themesPackage.SCHEMA,
	},
}

return LuauUI
