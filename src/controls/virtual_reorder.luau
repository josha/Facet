--!strict
--[[ VirtualList's REORDER, DROP-TARGET and AUTOSCROLL block, lifted out of
	`virtual_list.luau` verbatim (2026-08-15, the 200,000-char Source-write cap —
	`tools/check_source_size.py`).

	WHAT IS HERE: the window-space → canvas-offset arithmetic every drag question
	is answered in (`hostScreenRect`, `canvasOffsetFor`, `slotBoundary`,
	`insertSlotAt`), the insertion hairline's presentation write (`writeDropLine`),
	the reorder commits (`commitReorderAt`, `commitReorderFromPointer`), the
	slide-to-new-slot motion, the per-row `UI.draggable` drop-target contract
	(`rowAccepts`/`rowOnDrop`), and the edge-autoscroll wiring around
	`input/autoscroll.luau`.

	WHY IT COULD LEAVE, which is the test every extraction in this file family had
	to pass (`tools/check_source_size.py`'s header): NOTHING in this block writes a
	mutable upvalue of `virtual_list.build` except `lastIndexByKey`, which it also
	declares and nobody else reads — so that state left with the code. The three
	host locals it READS are reassigned (`boundController`/`boundScrollPath` by the
	native-scroll seam, `mountedScrollPath` by the focus-group derivation), so they
	arrive as the two accessors `controller()` and `hostPath()` rather than as
	values — the `screen_paint`-inside-`screen_target` precedent. Everything else
	it needs (`spec`, the index memos, `mainOf`/`vec`, `registry`, `maxTop`) is
	never reassigned and is passed by value or by reference.

	CONSTRUCTION ORDER IS PART OF THE CONTRACT: `new()` is called from exactly the
	line the block used to occupy, so the `indexByKey` observer it registers under
	`reorderable` still lands between the caches/selection observer above it and
	the hosted-row-actions section below it.

	DEPENDS ON: `../input/autoscroll`, `../row_capability`. Consumed only by
	`./virtual_list.luau`, which rebinds every export to a local of its original
	name so no call site inside that file changed. ]]

local autoscrollLib = require("../input/autoscroll")
local rowCapability = require("../row_capability")

local virtual_reorder = {}

export type Deps = {
	core: any,
	listScope: any,
	spec: any,
	id: string,
	isX: boolean,
	-- `virtual_list`'s own REORDER_KIND, passed rather than redeclared: the file
	-- that BUILDS the drag payload and the file that matches it must never hold
	-- two spellings of the same constant
	reorderKind: string,
	-- the axis seam: `mainOf(point)` reads the point's component on the scroll
	-- axis, `vec(px)` builds the {x,y} that carries `px` on it
	mainOf: (any) -> any,
	vec: (number) -> { x: number, y: number },
	-- the two REASSIGNED host facts, as accessors (see the header)
	controller: () -> any,
	hostPath: () -> string?,
	clampedTop: any,
	indexByKey: any,
	layoutNow: () -> any,
	mountedRowPath: (string) -> string?,
	registry: () -> any,
	maxTop: () -> number,
	autoscrollState: any,
	motionClock: any,
	reorderMotion: any,
	reorderable: boolean,
	rowsAreTargets: boolean,
}

function virtual_reorder.new(deps: Deps)
	local core = deps.core
	local listScope = deps.listScope
	local spec = deps.spec
	local id = deps.id
	local isX = deps.isX
	local mainOf = deps.mainOf
	local vec = deps.vec
	local controller = deps.controller
	local hostPath = deps.hostPath
	local clampedTop = deps.clampedTop
	local indexByKey = deps.indexByKey
	local layoutNow = deps.layoutNow
	local mountedRowPath = deps.mountedRowPath
	local registry = deps.registry
	local maxTop = deps.maxTop
	local autoscrollState = deps.autoscrollState
	local motionClock = deps.motionClock
	local reorderMotion = deps.reorderMotion
	local reorderable = deps.reorderable
	local rowsAreTargets = deps.rowsAreTargets
	local REORDER_KIND = deps.reorderKind

	-- window-space pointer -> canvas offset. The solver arranges rows in the host's
	-- own space and the engine shifts them by CanvasPosition, so the drop slot is
	-- only correct if the live scroll offset is added back (the same correction
	-- Table's reorder makes).
	-- the host's rect in WINDOW space. A pointer always arrives in window space,
	-- and a list nested inside another scrolled panel solves in ITS host's space,
	-- so anything comparing the two has to ask for the shifted rect.
	local function hostScreenRect(): any
		local ctrl = controller()
		local path = hostPath()
		if ctrl == nil or path == nil then
			return nil
		end
		local read = if type(ctrl.screenRectOf) == "function" then ctrl.screenRectOf else ctrl.rectOf
		if type(read) ~= "function" then
			return nil
		end
		return read(path)
	end

	-- a pointer point (window space) -> the CANVAS offset along the scroll axis.
	-- `pointerMain` is the pointer's component on that axis: its y on a vertical
	-- list, its x on a horizontal one — the caller reads it through `mainOf`, so
	-- the two never disagree about which coordinate the rect is being compared to.
	local function canvasOffsetFor(pointerMain: number): number?
		local rect = hostScreenRect()
		if type(rect) ~= "table" then
			return nil
		end
		return pointerMain - mainOf(rect) + clampedTop:get()
	end

	-- the canvas offset the insertion LINE is drawn at for a 0-based slot: the
	-- middle of the gutter above it, so the hairline reads as "between these two
	-- rows" rather than as a lid on the lower one. Clamped into the content extent
	-- so the first and last boundaries stay inside the canvas the host clips to.
	-- At rowGap 0 this is `slot * itemExtent`, clamped exactly as before.
	local function slotBoundary(slot: number): number
		return layoutNow().boundaryOffset(slot)
	end

	-- the insertion slot for a canvas offset: the number of whole SLOTS before it,
	-- using each slot's MIDPOINT so the line snaps to the nearer boundary. Returns
	-- the 0-based insertion slot and its canvas boundary offset.
	local function insertSlotAt(canvasY: number): (number, number)
		local slot = layoutNow().slotAt(canvasY)
		return slot, slotBoundary(slot)
	end

	-- the drop line rides the PRESENTATION channel, not layout: it is mounted
	-- once at canvas offset 0 and translated along the scroll axis, so a 60 Hz
	-- drag costs one presentation write per move instead of a re-solve per move.
	-- Parked far BEFORE the canvas origin when idle (the scroll host clips it)
	-- rather than unmounted, so there is no structural churn on every pickup.
	local DROP_LINE_PARK = -10000
	local function writeDropLine(y: number?)
		local ctrl = controller()
		local host = hostPath()
		if ctrl == nil or host == nil or type(ctrl.setPresentationTransform) ~= "function" then
			return
		end
		ctrl.setPresentationTransform(host .. "/Canvas/DropLine", vec(if y ~= nil then y else DROP_LINE_PARK))
	end

	-- ===== reorder ===========================================================
	local function indexOfKey(key: string): number?
		return (indexByKey:get() :: { [string]: number })[key]
	end

	--[[ HOISTED (parity round 3): this used to sit ~110 lines further down, and
		the per-row capability gates in `commitReorderAt` and `toggleGrab` need
		it. A local declared LATER in the file is NOT an upvalue — it binds a nil
		global and calls it. Later locals are not upvalues, and this repository has
		now been bitten by that five times. It depends only on `indexOfKey` and `spec`,
		both already in scope here. ]]
	local function itemForKey(key: string): any?
		local index = indexOfKey(key)
		if index == nil then
			return nil
		end
		return (spec.rows:get() :: { any })[index]
	end

	-- move `key` so it occupies 1-based index `to` in the resulting order. A
	-- no-op is SUPPRESSED: a drop that reproduces the current order must not emit
	-- a mutation nobody asked for (the mutation lifecycle applies — a reorder is
	-- a request, and pending never means success).
	local function commitReorderAt(key: string, to: number?)
		if spec.onReorder == nil or to == nil then
			return
		end
		-- THE FUNNEL. Every drop — pointer, gamepad grab, cross-container —
		-- lands here, so a pinned row is refused once rather than at each
		-- gesture's own entry point.
		if not rowCapability.allows(spec.rowMovable, itemForKey(key)) then
			return
		end
		local from = indexOfKey(key)
		if from == nil then
			return
		end
		local count = #(spec.rows:get() :: { any })
		local index = math.clamp(to, 1, math.max(1, count))
		if index == from then
			return
		end
		spec.onReorder(key, index)
	end

	-- POINTER commit: the insertion LINE decides, so the LEADING half of a row
	-- (its top on a vertical list, its left on a horizontal one) means "before it"
	-- and the trailing half means "after it". Removing the dragged row first
	-- shifts every later slot up by one, which is the whole of the
	-- full-list-slot → resulting-index conversion.
	local function commitReorderFromPointer(key: string, pointerMain: number)
		local canvasY = canvasOffsetFor(pointerMain)
		if canvasY == nil then
			return
		end
		local slot = (insertSlotAt(canvasY))
		local from = indexOfKey(key)
		if from == nil then
			return
		end
		commitReorderAt(key, slot - (if from <= slot then 1 else 0) + 1)
	end

	-- ===== reorder motion (finding F6) =======================================
	-- Rows SLIDE to their new slots; they never cross-fade. The layout offset
	-- jumps to the new slot immediately (the data is the truth), and the visual
	-- catch-up is a presentation transform springing from the old delta to zero —
	-- so the animation never re-solves and never fights the windowing math. The
	-- spring per row is RETARGETED, never recreated, so a re-sort landing on a
	-- row that is still sliding reverses smoothly.
	local slideValues: { [string]: any } = {}
	local slideUnsubs: { [string]: () -> () } = {}
	local lastIndexByKey: { [string]: number } = {}
	local function disposeSlide(key: string)
		local unsub = slideUnsubs[key]
		if unsub ~= nil then
			unsub()
			slideUnsubs[key] = nil
		end
		local value = slideValues[key]
		if value ~= nil then
			value:dispose()
			slideValues[key] = nil
		end
	end
	local function slideRow(key: string, fromDelta: number)
		if motionClock == nil or reorderMotion == "instant" or fromDelta == 0 then
			return
		end
		local value = slideValues[key]
		if value == nil then
			value = motionClock:spring(fromDelta, reorderMotion)
			slideValues[key] = value
			slideUnsubs[key] = core:observe(value, function()
				local ctrl = controller()
				local path = mountedRowPath(key)
				if ctrl == nil or path == nil or type(ctrl.setPresentationTransform) ~= "function" then
					return
				end
				ctrl.setPresentationTransform(path, vec(value:get()))
			end)
		else
			-- keep the value where it is and re-aim: interruptibility is the whole
			-- point of a persistent spring
			value:setVelocity(value:getVelocity())
		end
		value:setTarget(0)
	end
	if reorderable then
		listScope:own(core:observe(indexByKey, function(map: { [string]: number })
			-- the slide is the distance between the two SLOTS, gutter included. On a
			-- uniform list that is `(previous - index) * pitch` exactly as it was; on a
			-- variable one the slots are different sizes, so it is the difference of
			-- their offsets — the one place a pitch multiply would have been silently
			-- wrong rather than merely approximate.
			local ix = layoutNow()
			for key, index in map do
				local previous = lastIndexByKey[key]
				if previous ~= nil and previous ~= index then
					slideRow(key, ix.offsetOf(previous) - ix.offsetOf(index))
				end
			end
			for key in lastIndexByKey do
				if map[key] == nil then
					disposeSlide(key)
				end
			end
			lastIndexByKey = table.clone(map)
		end))
	end

	-- ===== drop targets ======================================================
	local function rowTargetOpts(key: string): any
		local item = itemForKey(key)
		if item == nil or spec.rowDropTarget == nil then
			return nil
		end
		return spec.rowDropTarget(item)
	end

	local function rowAccepts(key: string): (payload: any) -> (boolean, string?)
		return function(payload: any): (boolean, string?)
			-- an internal row move is legal on any row of THIS list (every slot is
			-- a legal insertion point); a foreign list's move is not
			if type(payload) == "table" and payload.kind == REORDER_KIND then
				return payload.list == id and spec.onReorder ~= nil, "FOREIGN_LIST"
			end
			local opts = rowTargetOpts(key)
			if opts ~= nil and type(opts.accepts) == "function" then
				return opts.accepts(payload)
			end
			return spec.dropSurface == true, "NOT_A_DROP_SURFACE"
		end
	end

	local function rowOnDrop(key: string): (payload: any, info: any) -> ()
		return function(payload: any, info: any)
			if type(payload) == "table" and payload.kind == REORDER_KIND and payload.list == id then
				-- POINTER: the release point decides the insertion line (a target
				-- id alone cannot say "which half of the row").
				-- ARMED: the target row IS the answer — the lifted row takes its
				-- place, which is what "commit on this row" means with no pointer
				-- to read a half from.
				-- the release point's component on THIS list's scroll axis: the
				-- registry publishes both (`pointerX`/`pointerY`), so a horizontal
				-- list reads the one its slots are measured along.
				local releaseMain = if info ~= nil then (if isX then info.pointerX else info.pointerY) else nil
				if info ~= nil and info.mode == "pointer" and releaseMain ~= nil then
					commitReorderFromPointer(payload.key, releaseMain)
				else
					commitReorderAt(payload.key, indexOfKey(key))
				end
				return
			end
			local opts = rowTargetOpts(key)
			if opts ~= nil and type(opts.onDrop) == "function" then
				local item = itemForKey(key)
				opts.onDrop(payload, {
					key = key,
					item = item,
					index = indexOfKey(key),
					targetId = info and info.targetId,
					source = info and info.source,
					mode = info and info.mode,
				})
			end
		end
	end

	-- ===== autoscroll ================================================
	local autoscrollEnabled = if spec.autoscroll ~= nil then spec.autoscroll ~= false else rowsAreTargets
	local autoscrollModel = if autoscrollEnabled
		then autoscrollLib.new(if type(spec.autoscroll) == "table" then spec.autoscroll else nil)
		else nil

	--[[ THE MODEL IS 1-D AND STAYS 1-D. `input/autoscroll.luau` owns the
		band/dwell/ramp/clamp policy along ONE axis and answers a signed delta; it
		is not axis-aware and deliberately is not made so. A horizontal host feeds
		it TRANSPOSED numbers instead — the identical move the renderer's own
		scroll-chain autoscroll makes for an `axis = "x"` host
		(`render/renderer.luau`, "the model is written for the scroll axis as a 1-D
		problem"). One policy, two wirings, no second dwell machine.

		The BAND NAME is translated on the way out for exactly the reason this
		whole change exists: the model answers "top"/"bottom" because that is the
		vocabulary it was written in, and a horizontal list publishing "top" on
		`list.autoscroll` would be a lying name in a Signal a consumer paints a
		chevron from. "left"/"right" is the spelling the renderer already accepts
		for a horizontal host, so the two agree. ]]
	local function autoscrollPoint(point: any): any
		if point == nil or not isX then
			return point
		end
		return { x = point.y, y = point.x }
	end
	local function autoscrollRect(rect: any): any
		if rect == nil or not isX then
			return rect
		end
		return { x = rect.y, y = rect.x, w = rect.h, h = rect.w }
	end
	local function autoscrollBand(): string?
		local band = autoscrollModel :: any
		band = if band ~= nil then band:band() else nil
		if band == nil or not isX then
			return band
		end
		return if band == "top" then "left" else "right"
	end

	-- Drive this once per frame while the surface is alive (the client's
	-- PreRender shim, alongside `clock:step`). Returns the step, or nil when the
	-- list is not autoscrolling.
	local function stepAutoscroll(now: number): any
		if autoscrollModel == nil then
			return nil
		end
		local reg = registry()
		local host = hostPath()
		local ctrl = controller()
		-- NON-POINTER SCHEMES HAVE NO AUTOSCROLL PATH: focus-follows-navigation
		-- already scrolls the host, and a second dwell/band mechanism aimed at a
		-- focus ring would answer the same question twice.
		if reg == nil or ctrl == nil or host == nil or not reg.isActive() or reg.mode() ~= "pointer" then
			autoscrollModel:reset()
			if autoscrollState:get().state ~= "idle" then
				autoscrollState:set({ state = "idle", band = nil })
			end
			return nil
		end
		local hostRect = hostScreenRect()
		local step = autoscrollModel:step({
			now = now,
			pointerPos = autoscrollPoint(reg.pointerPosition()),
			hostRect = autoscrollRect(hostRect),
			canvasPos = clampedTop:get(),
			maxScroll = maxTop(),
		})
		if step.delta ~= 0 then
			ctrl.scrollTo(host, vec(clampedTop:get() + step.delta))
			-- THE FRAME-ACCURATE RE-RESOLVE (the correctness core): the rects
			-- the session hit-tests against are the solver's, shifted by the LIVE
			-- scroll offset — so re-running the hover immediately after the write,
			-- in this same frame, is enough. A tick-based re-resolve lags about two
			-- rows at the top speed.
			reg.refreshTargets()
		end
		local current = autoscrollState:get()
		local band = autoscrollBand()
		if current.state ~= step.state or current.band ~= band then
			autoscrollState:set({ state = step.state, band = band })
		end
		return step
	end

	return {
		DROP_LINE_PARK = DROP_LINE_PARK,
		canvasOffsetFor = canvasOffsetFor,
		disposeSlide = disposeSlide,
		indexOfKey = indexOfKey,
		insertSlotAt = insertSlotAt,
		itemForKey = itemForKey,
		rowAccepts = rowAccepts,
		rowOnDrop = rowOnDrop,
		slideValues = slideValues,
		slotBoundary = slotBoundary,
		stepAutoscroll = stepAutoscroll,
		writeDropLine = writeDropLine,
	}
end

return virtual_reorder
