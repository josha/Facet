--!strict
-- Facet public entry point (design Â§5): the game-agnostic, engine-free
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
--[[ THE NINETEEN COMPOSITE CONTROLS (ADR-0037). Named locals rather than inline
	`require(...)` expressions, because `Facet.Controls` below has to name each
	module twice — once for the closure that calls it and once for the spec type
	that closure declares — and a namespace whose entries are typed `any` would
	give the author the completion list and take the argument checking away.

	FIFTEEN OF THEM ARE HERE AND FOUR ARE NOT, AND THE LINE BETWEEN THEM IS A
	MEASURED ONE (wave T15, director's memory ruling 2026-08-21).

	Requiring the whole framework retains ~2.76 MB of Lua heap (low-mode median
	2,763 KB), and deferring all nineteen composite controls would give back
	**860 KB [762..860]** of it — a game that never builds a Table pays for one
	anyway. The obvious repair is to move each `require` into the closure that
	needs it, with `require`'s own cache as the memoizer, so a control compiles at
	its first construction and never before. (An EARLIER version of this comment
	claimed 831 KB. That figure was subset arithmetic — each control charged for
	the shared graph this file loads regardless — and it was retracted with the
	rest of §7; the numbers here are the A/B on this file.)

	IT ONLY WORKS FOR FOUR OF THEM, AND THE REASON IS A LANGUAGE FACT THIS
	REPOSITORY NOW HAS AN INSTRUMENT FOR. A module's EXPORTED TYPES enter scope
	only through a direct `local M = require(...)` binding. Every deferral
	spelling loses them — measured with the pinned analyzer, all four of
	`type M = typeof(require(x))`, `local M = (nil :: any) :: typeof(require(x))`,
	`local M: typeof(require(x)) = (nil :: any)` and
	`local M = if false then require(x) else (nil :: any)` answer
	`TypeError: Unknown type 'M.Spec'`. So for the fifteen entries that declare a
	real `Spec`, deferring the require means widening the parameter to `any`,
	which is precisely the argument checking ADR-0037 exists to have bought.

	The four below already take `spec: any` — `Chip`, `VirtualList`, `VirtualGrid`
	and `AsyncImage` were never given a published spec type — so they need nothing
	from their module at load, and deferring them costs no type at all. Measured
	over repeated separate-process rounds paired by index (and independently
	re-reproduced at review): 2,763 KB eager against 2,535 KB with these
	four deferred, i.e. **228 KB [131..313]**, and `tools/check_types.py` pins the
	set BOTH WAYS: an entry that loses its spec type fails, and an entry that
	GAINS one fails too — which is the day the require below has to come back to
	the top of this file, or the fifteen spec types have to move to a module that
	costs nothing to load. That is the remaining **632 KB** and it is not a change
	to this file.

	`Facet.preload()` at the bottom force-loads all four for a game that would
	rather pay at the loading screen. ]]
local tableControl = require("@self/controls/table")
local popupButton = require("@self/controls/popup_button")
local menuControl = require("@self/controls/menu")
local calloutControl = require("@self/controls/callout")
local stepperControl = require("@self/controls/stepper")
local sliderControl = require("@self/controls/slider")
local ratingControl = require("@self/controls/rating")
local progressView = require("@self/controls/progress_view")
local labelControl = require("@self/controls/label")
local pickerControl = require("@self/controls/picker")
local tabView = require("@self/controls/tab_view")
local disclosureGroup = require("@self/controls/disclosure_group")
local textInput = require("@self/controls/text_input")
local rowActions = require("@self/controls/row_actions")
local levelPicker = require("@self/controls/level_picker")
local asyncResources = require("@self/async/resources")
local themesPackage = require("@self/themes/package")
local themesSnapshot = require("@self/themes/snapshot")
local motionClasses = require("@self/motion/classes")
local motionCurves = require("@self/motion/curves")

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
	--[[ THE TWO EXTENT NAMES VirtualList RENAMED WHEN IT GAINED A SECOND AXIS
		(docs/plans/parity-round2.md §2.3). Both still WORK — that is what
		these rows say — and a caller passing the old spelling on a vertical list
		needs no edit at all. They are deprecated rather than kept because a
		`rowHeight` on `axis = "x"` names a height that is really a width, and the
		alias would have to lie to somebody. Passing the new name and the old one
		together is refused at construction: it is one field. ]]
	{
		surface = "newVirtualList(spec.rowHeight)",
		since = "0.9.0",
		removeNoEarlierThan = "0.10.0",
		replacement = "itemExtent",
		note = 'axis-neutral rename; alias still accepted and identical on axis = "y"',
	},
	--[[ THE ONLY ROUTE TO REDUCED MOTION, UNTIL IT WAS NOT (device-bug round
		2026-08-12, C1; registered here by the Milestone-1 review, C3). Reduced
		motion now arrives on its own — the renderer pushes the environment's
		`reducedMotion` fact into `adapter.setReducedMotion` at attach and on every
		change — so nothing has to pass this closure any more, and no production
		caller ever did, which is why the setting reached nothing at all.

		It KEEPS WORKING and is deprecated rather than removed (ADR-0011): it is
		public, `billboard_target` forwards it, and a harness that wants to FORCE
		reduced motion regardless of the environment still has a use for it. Its
		meaning narrowed in that same change — it is an OR with the pushed fact, so
		returning `false` no longer overrides a player who asked for less motion —
		and a narrowing that is documented in prose but absent from the ledger is
		invisible to every machine-readable upgrade check ADR-0011 exists for. ]]
	{
		surface = "screen_target.new(opts.isReducedMotion)",
		since = "0.9.0",
		removeNoEarlierThan = "0.10.0",
		replacement = "adapter.setReducedMotion, pushed by the renderer from the environment",
		note = "still accepted, and now OR-ed with the pushed fact: it can force reduced motion on, "
			.. "never off. `billboard_target.new(opts.isReducedMotion)` forwards it and retires with it",
	},
	{
		surface = "newVirtualList(spec.viewportHeight)",
		since = "0.9.0",
		removeNoEarlierThan = "0.10.0",
		replacement = "viewportExtent",
		note = 'axis-neutral rename; alias still accepted and identical on axis = "y"',
	},
	--[[ THE NINETEEN OLD-FORM COMPOSITE BUILDERS (ADR-0037). Each still works and
		still dispatches to the same builder — `Facet.Controls.<Name>` is a closure
		over this library, not a reimplementation — so a caller that never edits is
		never broken. What these rows add is the NOTICE: the removal cannot come
		before 0.12.0, and every one of them names the exact replacement call, which
		is what makes `tools/check_call_shape_drift.py` a rule rather than a taste.

		The eleven infrastructure constructors (`newCore`, `newPresenter`,
		`newActionSystem`, …) are deliberately ABSENT from this list: they take no
		library argument, their creation and ownership IS the important fact, and the
		ADR leaves them where they are. ]]
	{
		surface = "newTable",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Table(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newSlider",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Slider(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newStepper",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Stepper(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newPicker",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Picker(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newPopupButton",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.PopupButton(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newMenu",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Menu(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newTabView",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.TabView(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newLabel",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Label(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newChip",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Chip(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newRating",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Rating(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newTextInput",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.TextInput(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newProgressView",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.ProgressView(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newLevelPicker",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.LevelPicker(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newDisclosureGroup",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.DisclosureGroup(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newVirtualList",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.VirtualList(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newVirtualGrid",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.VirtualGrid(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newRowActions",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.RowActions(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newCallout",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.Callout(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
	},
	{
		surface = "newAsyncImage",
		since = "0.10.0",
		removeNoEarlierThan = "0.12.0",
		replacement = "Facet.Controls.AsyncImage(core, spec)",
		note = "same builder, same spec table; the namespace closes over the library "
			.. "so the redundant first argument disappears",
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

--[[ COMPOSITE CONTROLS, WITHOUT THE LIBRARY'S NAME TWICE (ADR-0037).

	`Facet.Controls.Table(core, spec)` made every author write `Facet` twice: the
	first argument is the library handing itself to its own builder — boilerplate
	that teaches nothing and that autocomplete cannot explain. This namespace
	closes over the library once, so the redundant argument disappears and
	`Facet.Controls.` completes to exactly the nineteen composites instead of the
	forty-four mixed entries `Facet.` offers (nineteen controls and eleven
	infrastructure constructors shared one top level).

	WHY A NAMESPACE AND NOT `Facet.newTable(core, spec)`. The flat repair buys the
	same authoring win at the same migration cost, but the same symbol would then
	have two live arities during migration and the only way to keep old callers
	working is sniffing whether argument 1 is the library — the "magic argument"
	class the API constitution bans. New symbols overload nothing, so the old form
	stays intact, unwarped, and mechanically detectable
	(`tools/check_call_shape_drift.py`).

	`library` is assigned immediately below the `Facet` literal. It is the same
	table these builders were always handed; a local rather than a parameter only
	because a closure cannot capture a local declared after it.
]]
local library: any = nil

local Controls = table.freeze({
	Table = function(core: any, spec: tableControl.Spec)
		return tableControl.build(library, core, spec)
	end,
	Slider = function(core: any, spec: sliderControl.Spec)
		return sliderControl.build(library, core, spec)
	end,
	Stepper = function(core: any, spec: stepperControl.Spec)
		return stepperControl.build(library, core, spec)
	end,
	Picker = function(core: any, spec: pickerControl.Spec)
		return pickerControl.build(library, core, spec)
	end,
	PopupButton = function(core: any, spec: popupButton.Spec)
		return popupButton.build(library, core, spec)
	end,
	Menu = function(core: any, spec: menuControl.Spec)
		return menuControl.build(library, core, spec)
	end,
	TabView = function(core: any, spec: tabView.Spec)
		return tabView.build(library, core, spec)
	end,
	Label = function(core: any, spec: labelControl.Spec)
		return labelControl.build(library, core, spec)
	end,
	-- DEFERRED (see the block header): this entry declares no spec type, so the
	-- module is not needed until a Chip is actually built.
	Chip = function(core: any, spec: any)
		return require("@self/controls/chip").build(library, core, spec)
	end,
	Rating = function(core: any, spec: ratingControl.Spec)
		return ratingControl.build(library, core, spec)
	end,
	TextInput = function(core: any, spec: textInput.Spec)
		return textInput.build(library, core, spec)
	end,
	ProgressView = function(core: any, spec: progressView.Spec)
		return progressView.build(library, core, spec)
	end,
	LevelPicker = function(core: any, spec: levelPicker.Spec)
		return levelPicker.build(library, core, spec)
	end,
	DisclosureGroup = function(core: any, spec: disclosureGroup.Spec)
		return disclosureGroup.build(library, core, spec)
	end,
	-- DEFERRED (see the block header): this entry declares no spec type, so the
	-- module is not needed until a VirtualList is actually built.
	VirtualList = function(core: any, spec: any)
		return require("@self/controls/virtual_list").build(library, core, spec)
	end,
	-- DEFERRED (see the block header): this entry declares no spec type, so the
	-- module is not needed until a VirtualGrid is actually built.
	VirtualGrid = function(core: any, spec: any)
		return require("@self/controls/virtual_grid").build(library, core, spec)
	end,
	RowActions = function(core: any, spec: rowActions.Spec)
		return rowActions.build(library, core, spec)
	end,
	Callout = function(core: any, spec: calloutControl.Spec)
		return calloutControl.build(library, core, spec)
	end,
	-- DEFERRED (see the block header): this entry declares no spec type, so the
	-- module is not needed until an AsyncImage is actually built.
	AsyncImage = function(core: any, spec: any)
		return require("@self/controls/async_image").build(library, core, spec)
	end,
})

local Facet = {
	-- semantic version (ADR-0011): MAJOR.MINOR.PATCH; pre-1.0 the minor
	-- tracks the completed design phase. Bump here AND in the ADR.
	VERSION = "0.10.0",

	--[[ the composite-control namespace (ADR-0037). `Facet.Controls.Table(core,
		spec)`; the nineteen `new<Control>` builders below keep working and are
		declared in DEPRECATIONS with `Facet.Controls.<Name>` as the replacement. ]]
	Controls = Controls,

	--[[ FORCE-LOAD EVERY DEFERRED MODULE, FOR THE LOADING-SCREEN MOMENT
		(wave T15). Four composites compile at their first construction rather
		than at `require` (see the Controls block header) — 228 KB [131..313] of Lua
		heap a game that builds none never pays. A game that would rather pay it while a
		loading screen is up, instead of on the frame a player first opens a list,
		calls this once and is done.

		It is deliberately not clever: `require`'s own cache is the memoizer, so
		calling it twice costs a table lookup, and calling it never is the
		supported default. Returns the number of modules it loaded so a caller can
		log the cost rather than guess at it. ]]
	preload = function(): number
		--[[ Written out rather than looped: Luau's require-by-string takes a
			LITERAL, so a path in a loop variable is not requirable. Four lines is
			also the honest length of this — the count below is the number of
			deferred modules, and if a fifth is ever deferred both halves move
			together in one edit. ]]
		local _chip = require("@self/controls/chip")
		local _list = require("@self/controls/virtual_list")
		local _grid = require("@self/controls/virtual_grid")
		local _image = require("@self/controls/async_image")
		return 4
	end,

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
	newVirtualList = function(lib: any, core: any, spec: any)
		return require("@self/controls/virtual_list").build(lib, core, spec)
	end,
	-- the LAZY grid (parity §4.2.2): windows by LINE OF CELLS on the same
	-- running-offset index `newVirtualList` uses, and mounts a real `UI.Grid` as
	-- its band, so there is one column arithmetic in the framework and not two
	newVirtualGrid = function(lib: any, core: any, spec: any)
		return require("@self/controls/virtual_grid").build(lib, core, spec)
	end,

	newPopupButton = popupButton.build,
	-- ...and its sibling that is NOT a value picker: a menu of VERBS, attachable
	-- to any blueprint, presented on the D1 anchored seam. It is what closes
	-- the context-menu construct — primary activate, right-click, touch long-press, a gamepad
	-- button and the keyboard context key all open the same list.
	newMenu = menuControl.build,
	-- ...and the APP-PUSHED coach mark (D3b): a plate with an arrow tail that the
	-- app raises from eligibility rules, not a tooltip the player pulls (that is
	-- `help`, a prop). It never blocks, at most one is ever on screen, and its
	-- persistence is the CALLER'S — it reads a "has this been seen" Readable and
	-- reports back once when it should be retired.
	newCallout = calloutControl.build,
	-- value-control family: Stepper and Slider
	-- are different affordances over ONE shared value model, so bounds, stepping,
	-- rounding, formatting and semantic value text cannot disagree at the edges.
	newStepper = stepperControl.build,
	newSlider = sliderControl.build,
	-- ...and the small discrete one: a run of glyphs that reads as ONE value and
	-- takes ONE focus stop, instead of the N buttons every app writes by hand
	newRating = ratingControl.build,
	-- display controls
	newProgressView = progressView.build,
	newLabel = labelControl.build,
	newPicker = pickerControl.build,
	-- ...and the construct that COMPOSES that strip: a tab bar plus the pages
	-- behind it, placed by `adaptive.navPlacement` (navigation-and-menus D5)
	newTabView = tabView.build,
	newDisclosureGroup = disclosureGroup.build,
	valueModel = require("@self/controls/value_model"),
	newTextInput = textInput.build,

	-- pure Path2D shape math for UI.Path (the native substrate):
	-- rings/arcs/needles as normalized control points, headlessly tested
	pathShapes = require("@self/controls/path_shapes"),

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

	-- async image over the resource provider
	newAsyncImage = function(lib: any, core: any, spec: any)
		return require("@self/controls/async_image").build(lib, core, spec)
	end,
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
	-- what they mean, and `spatial.isFlat(pos)` is true for every event Facet
	-- produces today.
	spatial = require("@self/input/spatial"),
	newChip = function(lib: any, core: any, spec: any)
		return require("@self/controls/chip").build(lib, core, spec)
	end,
	newRowActions = rowActions.build,
	-- row-actions Task 7: at most one row open per shared list surface. A
	-- VStack/ScrollView list creates its own and shares it across every
	-- wrapped row's `coordinator` spec key; Table's own `rowActions` wiring
	-- (Task 10) does this for its rows automatically.
	newRowActionsCoordinator = rowActions.newCoordinator,
	newLevelPicker = levelPicker.build,
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
		--[[ ...and the CURVE vocabulary (ADR-0033), the other half of the dial.
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
	},

	-- adaptive-layout decisions: the PURE
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
	--[[ ...and `facts`/`lineBox`, the answer to "how tall is N lines of this text
		going to be?" (ruled 2026-08-15, docs/plans/variable-item-extents.md).
		Declaring a correct `itemExtent` or a composition floor used to mean
		hand-reproducing the solver's text arithmetic — the `max(typographyScale,
		typographyPaintScale)`, the ADDITIVE `preferredTextOffset`, and the live
		theme's line height for the role. A survey found seven near-duplicates of
		that formula in-repo and exactly one correct. These two are the one
		implementation, and they spend the solver's own seams
		(`text_metrics.reservedSize` / `.lineBoxPx`) rather than a copy of them.
		Reach for `newVirtualList { itemExtent = "measured" }` instead whenever the
		row can measure itself — that removes the prediction rather than making it
		easier. ]]
	text = {
		measure = require("@self/layout/text_metrics").measure,
		fit = require("@self/layout/text_fit").fit,
		size = require("@self/layout/text_fit").size,
		facts = require("@self/layout/text_fit").facts,
		lineBox = require("@self/layout/text_fit").lineBox,
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
		-- the pre-play gate for contributed controls (ADR-0019 §1): a control
		-- declares its namespaced needs and asks whether a package covers them
		-- — complete treatment or a useful error, never silence
		checkCoverage = themesPackage.checkCoverage,
		SCHEMA = themesPackage.SCHEMA,
	},
}

--[[ ADR-0037: the `Controls` closures were built above the literal (a closure
	cannot capture a local declared after it), so the library they hand to each
	builder is bound here — the same table `Facet.new<Control>(Facet, …)` passes. ]]
library = Facet

return Facet
