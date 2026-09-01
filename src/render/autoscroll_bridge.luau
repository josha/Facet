--!strict
--[[ DRAG-TO-EDGE AUTOSCROLL: the half of the renderer's DRAG BRIDGE that reads no
	mutable upvalue of its host.

	WHY IT IS ITS OWN FILE. Roblox refuses a `Script.Source` assignment at 200,000
	characters or more, and every LIVE path is a write — Rojo's Studio plugin,
	`execute_luau`, any plugin — so a module over the cap silently stops syncing into
	an open Studio session and a live check against it then tests the code baked into
	the place rather than the edits on disk. `tools/lune/verify/data/source-cap-ledger.md`
	names the DRAG BRIDGE (`dragRegistry`/`attachDetector`/`autoscrollOptsFor`/
	`scrollChainAt`) as the seam `render/renderer.luau` owes before its next change of
	any size. This is that seam's ONE-WAY half, taken first for the reason every split
	in this repository is judged by: does the block read or write a mutable upvalue of
	its host?

	  · the two reassigned scalars it touches — `pointerDrag` and `autoscrollClock` —
	    are DECLARED HERE and read nowhere else, so the state left with the code
	    (the `present/catchers.luau` precedent);
	  · the nine names that cross (`Ctx` below) are each declared exactly once by the
	    renderer and NEVER reassigned — four by-reference tables, two module requires,
	    one `local function`, the `controller` table and `adapter`, which is a
	    parameter of `renderer.attach`. A reassigned local cannot be shared by
	    reference at all, which is why that is the test and not a proxy for it.

	`tests/autoscroll_bridge_seam.spec.luau` mechanises both claims over the live
	sources. The REGISTRY half of the drag bridge (`dragRegistry`/`attachDetector`,
	whose `dragRegistryInstance` is read from a dozen places in the host) stays where
	it is: it needs the shared-record move `controls/table.luau` set the precedent for,
	and that is a different commit from this one.

	Public interface:
	  autoscroll_bridge.new(ctx) -> { setPointerDrag, stepAutoscroll }

	Both are rebound onto the renderer's `controller` under their existing public
	names — `controls/table.luau` publishes a row drag through `setPointerDrag` and
	`present/presenter.luau` drives `stepAutoscroll` per frame — so nothing about the
	public surface moved.
]]

local autoscroll_bridge = {}

export type Ctx = {
	-- the engine adapter; `setScrollPosition` being absent is what makes an
	-- autoscroll frame a no-op on a target that cannot scroll
	adapter: any,
	-- `input/autoscroll`: the per-host dwell model and its band chooser
	autoscrollLib: any,
	-- path -> live model. Shared BY REFERENCE with the renderer, which clears it
	-- when a scroll host leaves the tree.
	autoscrollModels: { [string]: any },
	-- the renderer's public surface, for `scrollPosition`/`scrollTo`. The two
	-- methods below are bound back onto it by the caller.
	controller: any,
	-- path -> adapter handle: a region whose host is not mounted is not in the chain
	handles: { [string]: any },
	-- the last solve's scroll regions (axis, content extents), by path
	lastScrollRegions: { [string]: any },
	-- `src/rect`, for `containsClosed`
	rectLib: any,
	-- path -> the painted rect in screen space, re-read per query
	screenRectOf: (path: string, relativeTo: string?) -> any,
	-- path -> the authored `autoscroll` prop (`false` opts out, a table configures)
	scrollAutoscroll: { [string]: any },
}

function autoscroll_bridge.new(ctx: Ctx): any
	local adapter = ctx.adapter
	local autoscrollLib = ctx.autoscrollLib
	local autoscrollModels = ctx.autoscrollModels
	local controller = ctx.controller
	local handles = ctx.handles
	local lastScrollRegions = ctx.lastScrollRegions
	local rectLib = ctx.rectLib
	local screenRectOf = ctx.screenRectOf
	local scrollAutoscroll = ctx.scrollAutoscroll

	-- ===== drag-to-edge autoscroll (device report 2026-07-29) ==============
	-- "I moved my finger to the bottom of the scroll view and held it, and it
	-- didn't auto-scroll."
	--
	-- THE POLICY LIVES ON THE SCROLLER (director ruling, same day). A drag says
	-- only WHERE the pointer is; every ScrollView decides for itself whether that
	-- point is at an edge it can still move along. That is what makes it work for
	-- a Table, an HStack of cards, or a mix, with no per-control copy — and it is
	-- the only arrangement that can answer the NESTED case, because "which
	-- scroller should move" is a question about the chain of scrollers under the
	-- point, not about the thing being dragged.
	--
	-- THE CHAIN RULE, innermost outward: take the ScrollViews whose PAINTED rect
	-- contains the drag point, nearest first. The first one that (a) has the point
	-- inside one of its own edge bands and (b) can still travel that way wins.
	-- A host already pinned at that end is transparent — the gesture falls
	-- through to its parent, which is what lets a short inner list hand a drag off
	-- to the page once its own tail is reached. Every host that is not the winner
	-- is reset, so a chain can never have two models armed at once.
	local pointerDrag: any = nil
	local autoscrollClock = 0

	-- a live pointer drag, published by whoever owns it (Table's reorder, the
	-- public drag registry). `nil` retracts it. `refresh` is called after a scroll
	-- lands so the owner can re-resolve its verdict in the SAME frame.
	local function setPointerDrag(info: any)
		if info == nil then
			pointerDrag = nil
			for _, model in autoscrollModels do
				model:reset()
			end
			return
		end
		pointerDrag = info
	end

	-- the ScrollView chain under a point, innermost first
	local function scrollChainAt(x: number, y: number): { string }
		local chain: { string } = {}
		for path, region in lastScrollRegions do
			if region ~= nil and handles[path] ~= nil then
				local rect = screenRectOf(path)
				if rect ~= nil and rectLib.containsClosed(rect, x, y) then
					table.insert(chain, path)
				end
			end
		end
		-- deepest path first: a descendant's path is strictly longer than its
		-- ancestor's (paths are "/a/b/c"), so length orders the chain without a
		-- second tree walk. Ties are unrelated subtrees, which cannot both contain
		-- the point unless they overlap; `sort` is stable enough for that case
		-- because either answer is equally correct.
		table.sort(chain, function(a, b)
			return #a > #b
		end)
		return chain
	end

	-- `autoscroll` prop -> model options, or nil when this host opts out
	local function autoscrollOptsFor(path: string): any
		local declared = scrollAutoscroll[path]
		if declared == false then
			return nil
		end
		return if type(declared) == "table" then declared else {}
	end

	-- one autoscroll frame for the whole surface. Returns the host it moved (nil
	-- when nothing did) so a caller can assert on it.
	local function stepAutoscroll(dt: number?): any
		autoscrollClock += math.max(dt or 0, 0)
		local drag = pointerDrag
		if drag == nil or type(drag.pos) ~= "table" or adapter.setScrollPosition == nil then
			for _, model in autoscrollModels do
				model:reset()
			end
			return nil
		end
		local chain = scrollChainAt(drag.pos.x, drag.pos.y)
		local winner: string? = nil
		local winnerStep: any = nil
		for _, path in chain do
			if winner ~= nil then
				break
			end
			local opts = autoscrollOptsFor(path)
			local region = lastScrollRegions[path]
			local rect = screenRectOf(path)
			if opts ~= nil and region ~= nil and rect ~= nil then
				local isX = region.axis == "x"
				local band = if isX then rect.w else rect.h
				local extent = if isX then region.contentW else region.contentH
				local maxScroll = math.max(0, extent - band)
				local current = controller.scrollPosition(path) or { x = 0, y = 0 }
				local offset = if isX then current.x else current.y
				local model = autoscrollModels[path]
				if model == nil then
					-- the band follows the HOST's shape, not the screen's: a short
					-- wide inner list and the tall page around it do not want the
					-- same reach (autoscroll.bandForViewport owns that choice).
					local resolved = table.clone(opts)
					if resolved.bandH == nil then
						resolved.bandH = autoscrollLib.bandForViewport(rect.w, rect.h)
					end
					model = autoscrollLib.new(resolved)
					autoscrollModels[path] = model
				end
				-- the model is written for the scroll axis as a 1-D problem, so an
				-- x-axis host is fed its own axis's numbers
				local step = model:step({
					now = autoscrollClock,
					pointerPos = if isX then { x = drag.pos.y, y = drag.pos.x } else drag.pos,
					hostRect = if isX then { x = rect.y, y = rect.x, w = rect.h, h = rect.w } else rect,
					canvasPos = offset,
					maxScroll = maxScroll,
				})
				-- CAN THIS HOST STILL TRAVEL THE WAY THE POINTER IS ASKING? The model
				-- deliberately stays ARMED at the end of its canvas (its rule 5, so
				-- pulling back and pushing in again does not re-pay the dwell) — but
				-- for a CHAIN that would mean a list pinned at its tail silently
				-- swallowing the gesture forever. A host that cannot move in the
				-- direction of the band it owns is transparent: it disarms and the
				-- drag falls through to its parent, which is what lets a short inner
				-- list hand off to the page (director, 2026-07-29).
				local bandName = model:band()
				local canTravel = if bandName == "top" or bandName == "left"
					then offset > 0
					elseif bandName == "bottom" or bandName == "right" then offset < maxScroll
					else false
				if step.state ~= "idle" and canTravel then
					winner = path
					winnerStep = step
					if step.delta ~= 0 then
						controller.scrollTo(path, {
							x = if isX then offset + step.delta else current.x,
							y = if isX then current.y else offset + step.delta,
						})
						if type(drag.refresh) == "function" then
							drag.refresh()
						end
					end
				else
					model:reset()
				end
			end
		end
		-- every host that did not win is disarmed, so no second model keeps a
		-- dwell timer running behind the one the player is actually steering
		for path, model in autoscrollModels do
			if path ~= winner then
				model:reset()
			end
		end
		if winner == nil then
			return nil
		end
		return { path = winner, state = winnerStep.state, delta = winnerStep.delta }
	end

	return {
		setPointerDrag = setPointerDrag,
		stepAutoscroll = stepAutoscroll,
	}
end

return autoscroll_bridge
