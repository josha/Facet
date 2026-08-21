--!strict
-- The PUBLIC drag/drop declaration channel (ADR-0022 Decision 5).
-- `UI.draggable(bp, …)` and `UI.dropTarget(bp, …)` are blueprint
-- modifiers like `UI.corners` — they return a new frozen blueprint carrying a
-- validated declaration, and the renderer wires the acquisition when the node
-- mounts.
--
-- WHY `meta` AND NOT A PROP: the same argument `contribution.luau` makes.
-- Public props are validated against `blueprint_schema` and an unknown key is a
-- hard error, so a framework channel that rode the public prop bag would have
-- to be whitelisted into every class's schema (teaching authors keys they must
-- never set by hand) or be exempted by a special case that reopens the exact
-- hole strict validation closes. `mount.luau` already copies `meta` verbatim
-- onto the mounted node and nothing in layout, render or dump reads it, so a
-- declaration reaches the renderer without touching authoring.
--
-- WHY VALIDATION LIVES HERE AND NOT AT THE WIRING SITE: an `accepts` that is
-- not a function, or a `dropTarget` with no `onDrop`, is an authoring mistake
-- whose symptom (a drop that silently does nothing) appears frames later and
-- three modules away. Refusing at declaration time names the fix at the line
-- that wrote it.

local motionClasses = require("../motion/classes")

local drag_contract = {}

-- the reserved metadata keys the declarations ride under `bp.meta`
local SOURCE_PROP = "dragSource"
local TARGET_PROP = "dropTarget"
drag_contract.SOURCE_PROP = SOURCE_PROP
drag_contract.TARGET_PROP = TARGET_PROP

export type SourceSpec = {
	-- the thing being moved. A function is called once at pickup with the
	-- source path, which is how one authored row template gives every mounted
	-- row its own payload without a closure per row.
	payload: any,
	-- motion class for the return flight and the pickup scale (default "object")
	dragMotion: string?,
	-- the ghost. Nil = the presenter's default ghost of the source.
	proxy: (() -> any)?,
	-- what the proxy does on a LEGAL drop: "destroy" (default) or "flyToTarget"
	-- (an `object`-class flight chasing the live target, `land` on arrival)
	onCommitProxy: string?,
	-- ARMED-MODE GHOST PARKING (row SF-D14). By default the armed ghost RIDES
	-- THE AIM: `armTo` springs it onto the target being aimed at, which is what
	-- makes a keyboard/pad pickup visibly different from no pickup at all.
	-- Declare this and it springs ONCE to the window-space point this returns
	-- and STAYS there while the aim moves — a fixed staging spot, with the aim
	-- carried by the target's own paint. The aim, the verdict and the commit
	-- flight are untouched either way (`onCommitProxy = "flyToTarget"` still
	-- chases the live target rect). Returning nil for a frame keeps the current
	-- parking spot rather than snapping the ghost anywhere.
	armStaging: (() -> { x: number, y: number }?)?,
	-- where the ghost rides relative to the pointer: "center" (default — the
	-- RascalRally-ratified feel, the card centered under the finger) or
	-- "preserve" (keep the grab-point offset; for large surfaces where a
	-- snap-to-center would visibly jump)
	grabAnchor: string?,
	-- a TAP on this source IS the pickup (director round six — the touch
	-- paradigm's answer to arm-on-A): the renderer arms an "armed"-mode session
	-- instead of dispatching Activate, so tap-a-card / scroll-freely /
	-- tap-a-row works one-thumbed on mobile. Action-source activates (gamepad
	-- A, Return) keep flowing to onActivate — the armed paradigm already owns
	-- them. Default false: what a tap MEANS is the consumer's call.
	armOnTap: boolean?,
	-- ACQUISITION, refusable WITHOUT disabling the control (row SF-D6). A
	-- `Bound<boolean>`: while it reads false this source arms nothing and promotes
	-- nothing, while the node stays enabled, hit-testable and activatable — which
	-- is what a control that must EXPLAIN why it cannot be picked up needs
	-- (a sponsor card blocked by cost or by a mode guard: "disabled stays
	-- inspectable"). `enabled = false` on the node itself still refuses
	-- acquisition too, and it additionally kills the tap.
	enabled: any?,
	--[[ THIS NODE IS RECYCLED: its disappearance is not its REMOVAL.

		One event — "the source's node stopped being mounted" — carries two
		opposite meanings, and only the thing that unmounted it can tell them
		apart:

		  · a VIRTUALIZED list scrolled the row out of its window, or a re-sort
		    moved it out. The row is still in the data and the drag must continue —
		    that is what edge autoscroll and keep-visible exist to serve.
		  · a SURFACE TORE DOWN (a `When` flipped, a pose changed). The source is
		    gone from the world, and a session left standing paints its ghost over
		    whatever is underneath, refuses every new pickup, and stays committable
		    onto anything that remounts beneath it.

		Liveness cannot separate them: when Rascal Rally's director table minimises,
		the HUD root is still mounted, so "some ancestor survived" is true of BOTH.

		So the declaration sits where the knowledge is. Default FALSE — a source
		that vanishes ends its drag, which is right for anything hand-authored.
		`VirtualList` sets it true on its own rows, because recycling is precisely
		what it does. (Director report 2026-08-04: a card held while the director
		view was dismissed stayed picked up outside it and could not be reached.) ]]
	recycled: boolean?,
	-- TOUCH ONLY: decline the pointer capture so a native scroll host under this
	-- node keeps the pan. A row inside a `ScrollView` sets this (fighting the
	-- engine's momentum scroll is never winnable); a card lying on a screen does
	-- not. Pointer/pen acquisition is unaffected either way.
	declineTouch: boolean?,
	-- per-input-class promotion overrides ({ pointer = 8, touch = 16 }); absent
	-- keys fall through to the shared interaction tokens
	promotionPx: { [string]: number }?,
}

export type TargetSpec = {
	-- the game's legality predicate. Returns `(legal, reason?)`; the reason code
	-- flows back out through the `reject` event, so a refusal is never silent.
	-- Absent = accepts every payload.
	accepts: ((payload: any) -> (boolean, string?))?,
	onDrop: (payload: any, info: any) -> (),
	onEnter: ((payload: any) -> ())?,
	onLeave: ((payload: any) -> ())?,
}

local COMMIT_PROXY = { destroy = true, flyToTarget = true }
local GRAB_ANCHOR = { center = true, preserve = true }

local function requireFunction(value: any, what: string)
	if value ~= nil and type(value) ~= "function" then
		error(`Facet drag: {what} must be a function (got {typeof(value)})`, 0)
	end
end

function drag_contract.source(spec: SourceSpec): SourceSpec
	if type(spec) ~= "table" then
		error("Facet drag: UI.draggable needs a table — UI.draggable(bp, { payload = … })", 0)
	end
	if spec.payload == nil then
		error(
			"Facet drag: UI.draggable needs a `payload`. It is the only thing a drop target is handed, so a "
				.. "draggable with none can never be accepted or refused by a legality predicate.",
			0
		)
	end
	requireFunction(spec.proxy, "UI.draggable's `proxy`")
	requireFunction(spec.armStaging, "UI.draggable's `armStaging`")
	if spec.dragMotion ~= nil then
		-- resolve NOW: an unknown class name discovered at pickup time is a
		-- crash in the middle of a gesture, and `resolve` already answers with
		-- the did-you-mean and the registered list
		motionClasses.resolve(spec.dragMotion)
	end
	if spec.onCommitProxy ~= nil and COMMIT_PROXY[spec.onCommitProxy] ~= true then
		error(
			`Facet drag: UI.draggable's onCommitProxy must be "destroy" or "flyToTarget" (got '{tostring(
				spec.onCommitProxy
			)}')`,
			0
		)
	end
	if spec.enabled ~= nil and type(spec.enabled) ~= "boolean" then
		local readable = type(spec.enabled) == "table" and type((spec.enabled :: any).get) == "function"
		if not readable then
			error(
				"Facet drag: UI.draggable's `enabled` must be a boolean or a Readable<boolean> — it gates "
					.. "ACQUISITION only, so a blocked source can still be tapped and explain itself.",
				0
			)
		end
	end
	if spec.grabAnchor ~= nil and GRAB_ANCHOR[spec.grabAnchor] ~= true then
		error(
			`Facet drag: UI.draggable's grabAnchor must be "center" or "preserve" (got '{tostring(spec.grabAnchor)}')`,
			0
		)
	end
	return table.freeze({
		payload = spec.payload,
		dragMotion = spec.dragMotion or "object",
		proxy = spec.proxy,
		armStaging = spec.armStaging,
		onCommitProxy = spec.onCommitProxy or "destroy",
		grabAnchor = spec.grabAnchor or "center",
		armOnTap = spec.armOnTap == true,
		declineTouch = spec.declineTouch == true,
		recycled = spec.recycled == true,
		enabled = spec.enabled,
		promotionPx = if spec.promotionPx ~= nil then table.freeze(table.clone(spec.promotionPx)) else nil,
	}) :: any
end

function drag_contract.target(spec: TargetSpec): TargetSpec
	if type(spec) ~= "table" then
		error("Facet drag: UI.dropTarget needs a table — UI.dropTarget(bp, { onDrop = … })", 0)
	end
	if type(spec.onDrop) ~= "function" then
		error(
			"Facet drag: UI.dropTarget needs an `onDrop(payload, info)` — a target that accepts nothing is a gap",
			0
		)
	end
	requireFunction(spec.accepts, "UI.dropTarget's `accepts`")
	requireFunction(spec.onEnter, "UI.dropTarget's `onEnter`")
	requireFunction(spec.onLeave, "UI.dropTarget's `onLeave`")
	return table.freeze({
		accepts = spec.accepts,
		onDrop = spec.onDrop,
		onEnter = spec.onEnter,
		onLeave = spec.onLeave,
	}) :: any
end

-- A STRUCTURAL NODE CANNOT CARRY A DECLARATION (api-architecture-consistency
-- F-18 / ledger BP-F15). `When` / `ForEach` / `ErrorBoundary` mount as regions,
-- never as an instance, and the renderer registers a drag source inside the
-- per-instance branch of `ensureTree` — which a structural node never reaches.
-- So `UI.draggable(UI.When{ … }, …)` was accepted and INERT, which is a
-- plausible mistake (wrapping a conditional card) with no symptom at all. Every
-- other modifier is gated by the schema; these two gate themselves.
local STRUCTURAL_CLASSES: { [string]: boolean } = { When = true, ForEach = true, ErrorBoundary = true }
local MODIFIER_FOR_KEY: { [string]: string } = { [SOURCE_PROP] = "UI.draggable", [TARGET_PROP] = "UI.dropTarget" }

-- write a declaration onto a blueprint's metadata channel, returning a NEW
-- frozen blueprint (blueprints are immutable)
function drag_contract.attach(bp: any, key: string, decl: any): any
	if type(bp) ~= "table" or type(bp.class) ~= "string" then
		error(`Facet drag: {key} must be applied to a blueprint`, 0)
	end
	if STRUCTURAL_CLASSES[bp.class] then
		local modifier = MODIFIER_FOR_KEY[key] or key
		error(
			`Facet drag: {modifier} cannot be applied to a UI.{bp.class} — a structural region mounts no `
				.. `instance of its own, so the declaration would be accepted and never wired to anything. `
				.. `Fix: wrap the RENDERED node instead — put {modifier} on the blueprint the region returns, `
				.. `or on a UI.Box/UI.VStack around the UI.{bp.class}.`,
			0
		)
	end
	local meta = if type(bp.meta) == "table" then table.clone(bp.meta) else {}
	meta[key] = decl
	return table.freeze({
		class = bp.class,
		id = bp.id,
		props = bp.props,
		children = bp.children,
		meta = table.freeze(meta),
	}) :: any
end

-- read a declaration off a MOUNTED node. Type-guarded like `contribution.read`:
-- a consumer smuggling a non-table under the reserved key reads as "no
-- declaration" rather than faulting the renderer.
local function readMeta(node: any, key: string): any?
	local meta = node.meta
	if type(meta) ~= "table" then
		return nil
	end
	local value = meta[key]
	if type(value) ~= "table" then
		return nil
	end
	return value
end

function drag_contract.readSource(node: any): SourceSpec?
	return readMeta(node, SOURCE_PROP)
end

function drag_contract.readTarget(node: any): TargetSpec?
	return readMeta(node, TARGET_PROP)
end

return drag_contract
