--!strict
--[[ THE EXPAND — a stepped-down region discloses its richest form (wave REVEAL).

	`src/layout/composition.luau` decides WHICH form of a region is standing and
	reports whether the player is therefore looking at less than the region has
	(`expandable`, and the `plate` box that would hold the rest). This file is the
	other half: what opens the disclosure, what closes it, and what is left behind
	when it goes.

	WHY IT IS A ROOT LEAF. `UI.Region` synthesizes the affordance, so the thing
	that owns the presentation has to be reachable from `src/blueprint.luau` — and
	`src/present/` requires `blueprint`, so anything under it would be a cycle.
	This module therefore requires NOTHING (the `src/class_contract.luau` shape):
	every blueprint it needs arrives as a BUILDER from the caller, and every
	presenter function arrives through the contribution seam. That is also what
	makes it testable with two table doubles and no mount.

	WHAT IT DOES NOT OWN, and the list is the point:
	  * the PLACEMENT is `presenter.presentAnchored`'s (D1) — edge flip, safe-area
	    clamp, moving-source follow, arrow tail, all shipped;
	  * the DISMISSALS are the presented surface's own. The plate is presented
	    `modal` with a fully transparent catching scrim, which is the Menu's own
	    idiom, and that ONE decision buys three of the four routes the contract
	    asks for: a tap outside dismisses (`outsideTapCancel`), Escape and gamepad
	    B dismiss (the default `cancelPolicy`), and the focus scope is pushed and
	    POPPED — so focus returns to the affordance that opened it without this
	    file holding a path or a restore of its own;
	  * the SIZE is the composition's (`plate.w`), and whether a plate is possible
	    at all is too (`plate.sheet`).

	WHY MODAL, when the brief's fourth dismissal route is "focus loss". A plate
	that does not trap focus strands its own contents: this repository measured it
	on the HUD paint probe, where "a second base surface's focusables are in
	NEITHER surface's traversal ring, in either responder mode", so a keyboard or
	gamepad player could see the disclosed form and never reach a control in it.
	The richest form is exactly the form most likely to HOLD controls. So focus
	loss becomes structural rather than incidental: the scope is the plate's, and
	the fourth route is served by the epoch check below instead.

	THE EPOCH CHECK IS THE ONE ORIGINAL MECHANISM HERE, and it is four lines. A
	plate is anchored to a rect the composition owns. `syncGeometry` runs on every
	solve and every frame (the presenter's own cadence, "asking nothing new of any
	caller"), so the engine re-reads that rect and CLOSES when it has moved,
	resized, or gone. Rotation, a viewport change, a theme-metric change and a
	re-solve that put the region back on its richest form are all the same event
	from the player's side — the thing they opened this against is not there any
	more — and one rule covers every one of them without a single new controller
	API. The alternative, following the source, is what a TOOLTIP wants; a
	disclosure that survives a rotation is a plate pointing at a box that moved.
]]

local region_expand = {}

export type Plate = { w: number, h: number, sheet: boolean }
export type Facts = { expandable: boolean, activeForm: number, plate: Plate? }

export type Config = {
	-- the region's authored id, for the surface name and every diagnostic
	id: string,
	-- the plate's CONTENT at a resolved width: the region's own form 1, wrapped by
	-- the caller (which is the only layer that may build blueprints)
	panelOf: (number) -> any,
	-- the same content as a full-width sheet SCREEN, for the offer where the plate
	-- cannot meet its floor
	sheetOf: () -> any,
	-- an authored handler REPLACES both presentations (`expand = function`)
	handler: (() -> ())?,
}

local function parentPath(path: string): string?
	-- the composition is the region's parent by construction (`UI.Composition`
	-- refuses a child that is not a `UI.Region`), so this is a strip, not a search
	return string.match(path, "^(.*)/[^/]+$")
end

local function rectOfPath(rectOf: any, path: string?): any
	if rectOf == nil or path == nil then
		return nil
	end
	local ok, rect = pcall(rectOf, path)
	return if ok then rect else nil
end

function region_expand.new(config: Config)
	local self = {} :: any
	local regionPath: string? = nil
	local controller: any = nil
	local presentAnchoredFn: any = nil
	local presentModalFn: any = nil
	local dismissFn: any = nil
	local handle: any = nil
	local mode: string? = nil -- "anchored" | "sheet" while open
	-- the rect the plate was opened against; the epoch check compares against it
	local openedAgainst: any = nil
	local teardowns = 0
	-- guards the dismiss we drive ourselves against the one the presenter drives
	local closing = false

	--[[ THE FACTS, READ FROM THE LAST SOLVE rather than recomputed. The renderer
		publishes each `UI.Composition` node's resolution dump, keyed by path; the
		region's own row is in it under the region's path. Nothing here re-derives
		"is this stepped down" — that is the composition's ruling and there is
		exactly one of it. ]]
	local function facts(): Facts?
		if controller == nil or controller.compositionAt == nil or regionPath == nil then
			return nil
		end
		local parent = parentPath(regionPath :: string)
		if parent == nil then
			return nil
		end
		local ok, dump = pcall(controller.compositionAt, parent)
		if not ok or type(dump) ~= "table" then
			return nil
		end
		for _, row in (dump :: any).regions or {} do
			if row.id == regionPath then
				return { expandable = row.expandable == true, activeForm = row.activeForm or 0, plate = row.plate }
			end
		end
		return nil
	end

	local function close(_reason: string?)
		if handle == nil then
			return
		end
		local h = handle
		handle = nil
		mode = nil
		openedAgainst = nil
		teardowns += 1
		if dismissFn ~= nil then
			closing = true
			pcall(dismissFn, h)
			closing = false
		end
	end

	--[[ ONE SET OF PRESENT OPTIONS, and every dismissal route is in it. `modal`
		with `scrim = "none"` is the Menu's idiom: fully transparent, still catching,
		so an outside tap closes the plate and never clicks through to the HUD
		underneath. `cancelPolicy` is left at its default (`dismiss`), which is what
		makes Escape and gamepad ButtonB close it. No `transition` is declared, so
		the plate PLACES rather than travels — which is the reduced-motion answer by
		construction rather than by a branch that only one player ever exercises. ]]
	local function anchoredOpts(): any
		return {
			id = `Expand:{config.id}`,
			modal = true,
			scrim = "none",
			outsideTapCancel = true,
			anchor = {
				source = { path = regionPath },
				edge = "bottom",
				align = "start",
				gap = "s",
				tail = true,
			},
			rootPolicy = "edgeToEdge",
		}
	end

	--[[ OPEN. Returns the presentation it chose, or nil when there was nothing to
		open — and "nothing to open" is a real answer rather than a failure: a
		region that is standing on its richest form has nothing more to show, and a
		plate that opened anyway would be a duplicate of what is already on screen. ]]
	function self.open(): string?
		if config.handler ~= nil then
			pcall(config.handler)
			return "custom"
		end
		if handle ~= nil then
			-- a second activation on an open plate CLOSES it: the affordance is the
			-- same control the player just used, and leaving it inert is how a
			-- disclosure becomes a trap on touch
			close("toggle")
			return nil
		end
		local f = facts()
		if f == nil or not f.expandable or f.plate == nil then
			return nil
		end
		local plate = f.plate :: Plate
		if plate.sheet then
			if presentModalFn == nil then
				return nil
			end
			handle = (presentModalFn :: any)(config.sheetOf(), {
				scrim = "scrim",
				outsideTapCancel = true,
			})
			mode = "sheet"
		else
			if presentAnchoredFn == nil or regionPath == nil then
				return nil
			end
			handle = (presentAnchoredFn :: any)(config.panelOf(plate.w), anchoredOpts())
			mode = "anchored"
		end
		if handle ~= nil then
			openedAgainst = rectOfPath(if controller ~= nil then controller.rectOf else nil, regionPath)
			--[[ EVERY DISMISS PATH, not only the ones this file drives. An outside tap
				is torn down inside the presenter and never comes back through `close`,
				so without this the engine would hold a dead handle and refuse to open
				again — the defect `row_actions` and the Menu each found live and each
				fixed exactly here. ]]
			if handle.onFeedback ~= nil then
				local mine = handle
				handle.onFeedback(function(event: any)
					if type(event) == "table" and event.type == "dismiss" and not closing and handle == mine then
						handle = nil
						mode = nil
						openedAgainst = nil
						teardowns += 1
					end
				end)
			end
		end
		return mode
	end

	function self.close()
		close("caller")
	end

	function self.state(): string
		return mode or "closed"
	end

	-- TEARDOWN, COUNTED. Every route out of the plate increments it exactly once —
	-- the caller's, the affordance's second press, the epoch check's, and the
	-- presenter's own outside-tap — which is what a leak test can assert against.
	function self.teardowns(): number
		return teardowns
	end

	function self.facts(): Facts?
		return facts()
	end

	--[[ THE EPOCH CHECK. Called on every solve and every frame through the
		contribution seam. Two rect reads and no writes while nothing is open. ]]
	function self.sync(rectOf: any, rootNode: any?)
		if rootNode ~= nil and rootNode.path ~= nil then
			regionPath = rootNode.path
		end
		if handle == nil then
			return
		end
		local now = rectOfPath(rectOf, regionPath)
		if now == nil or now.w == nil or now.w <= 0 or now.h <= 0 then
			close("gone")
			return
		end
		local was = openedAgainst
		if was == nil then
			openedAgainst = now
			return
		end
		if now.x ~= was.x or now.y ~= was.y or now.w ~= was.w or now.h ~= was.h then
			close("epoch")
			return
		end
		local f = facts()
		if f ~= nil and not f.expandable then
			-- the region climbed back to its richest form under the plate: what the
			-- plate is showing is now on the screen behind it
			close("richest")
		end
	end

	--[[ THE CONTRIBUTION `UI.Region` attaches to its own node. Three fields, all of
		them the shipped seam: the presenter hands over what a blueprint cannot
		construct, and this file holds no reference back to the presenter object. ]]
	self.contribution = {
		syncGeometry = function(rectOf: any, rootNode: any?)
			self.sync(rectOf, rootNode)
		end,
		bindPresent = function(presentModal: any, dismiss: any, presentAnchored: any)
			presentModalFn = presentModal
			dismissFn = dismiss
			presentAnchoredFn = presentAnchored
		end,
		bindController = function(ctrl: any)
			controller = ctrl
		end,
	}

	return self
end

return region_expand
