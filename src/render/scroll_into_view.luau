--!strict
--[[ THE SCROLL-INTO-VIEW FAMILY, lifted out of `render/renderer.luau` on
	2026-09-03 because `tools/lune/verify/data/source-cap-ledger.md`'s renderer row named
	this block, by name, as the next seam owed before this file's next edit of any
	size — and wicked-fast T8 (the recycled-instance style-prop fix) is that edit.
	THE ARGUMENT IS NOT REPEATED HERE: read that row and
	`tests/scroll_into_view_seam.spec.luau` for the executable contract.

	WHAT IS HERE. `controller.scrollToVisible` (A-SV1/A-SV2) — the shared keep-visible
	substrate every control that must bring a focused, selected or newly-revealed
	descendant into view asks for instead of carrying its own scroll arithmetic — and
	`controller.scrollHostFor`, the ONE answer for "which ScrollView carries this node,
	and everything an edge autoscroll needs to steer it" that `autoscroll_bridge.luau`'s
	own header cites as the argument for exposing the pair rather than tempting three
	separate internals out through the API. `controller.scrollPosition` and
	`controller.scrollTo` — the two methods both of these call — stay in the renderer:
	they are the framework's one scroll READ and its one scroll WRITE, shared with
	`render/autoscroll_bridge.luau` (which reads and writes them the identical way, a
	few hundred lines below this module's own call site), so moving them into either
	seam alone would have made the other reach sideways into it.

	IT WRITES NOTHING OF ITS HOST'S. Both functions are pure reads over the solved
	geometry plus calls into `controller.scrollPosition`/`controller.scrollTo`
	— which is a WRITE, but an encapsulated one this module never touches directly, the
	same way `layout/stack.luau` writes nothing of the solver's own state while calling
	`place`. Six names cross, all by reference and none of them reassigned:
	`adapter` (`attach`'s own parameter), the three by-reference tables the renderer
	keeps writing to (`lastRects`, `lastScrollRegions`, `scrollHostOf`), the `local
	function screenRectOf` declared once near the top of `attach`, and — the one this
	family needed that no earlier renderer seam did — `controller` itself, for its
	`scrollPosition`/`scrollTo` pair, exactly the field `autoscroll_bridge.luau`'s own
	`Ctx` already carries for the same reason. Passing the whole table costs nothing
	extra: both methods are already assigned onto it by the time either function here
	is ever CALLED (`renderer.attach` runs to completion, including the assignments a
	few hundred lines below this module's construction site, before any surface can
	reach `controller.scrollToVisible` at all), so the Deps record needs no
	call-argument workaround the way `stack.luau`'s `place` or `premeasure_round.luau`'s
	`solveAndApply` do.

	`../layout/solver` is required directly for `keepVisibleOffset` — the ONE
	implementation of the minimum-distance rule this module's whole reason for
	existing is to share — the same move `premeasure_round.luau` made for
	`layout/text_metrics`: a leaf both files already required, so the require graph
	gains no edge that was not already there twice over. ]]
local solver = require("../layout/solver")

local scroll_into_view = {}

-- What the family needs from the renderer, handed over once at `attach` time. A
-- by-reference table crosses as a field; `controller` is the renderer's own public
-- surface, read here only for `scrollPosition`/`scrollTo`, both of which are bound
-- onto it before this module's functions can ever be called.
export type Deps = {
	-- the engine adapter; `setScrollPosition` being absent is the clip-only fallback
	-- that makes `scrollToVisible` a no-op with nothing else to check
	adapter: any,
	-- the renderer's public surface, for `scrollPosition`/`scrollTo` — the framework's
	-- one scroll read and its one scroll write, shared with `autoscroll_bridge.luau`
	controller: any,
	-- path -> the last solve's rect, in the host's own coordinate space
	lastRects: { [string]: any },
	-- path -> the last solve's scroll region (axis, content extents), by HOST path
	lastScrollRegions: { [string]: any },
	-- path -> nearest ScrollView ancestor, threaded down `structuralSync`'s live-path
	-- walk so neither function here re-walks the tree to find it
	scrollHostOf: { [string]: string },
	-- path -> the painted rect in screen space, re-read per query
	screenRectOf: (path: string, relativeTo: string?) -> any,
	-- path -> the sum of its COORDINATE-SPACE host chain (Plan C, C1), walked over
	-- `lastRects` — which is the map both rects `scrollToVisible` subtracts came
	-- from, so the origin must come from it too. `render/rect_reads.hostOriginOf`.
	hostOriginOf: (path: string) -> (number, number),
}

export type ScrollIntoView = {
	scrollToVisible: (path: string, localRect: any?) -> boolean,
	scrollHostFor: (path: string, includeSelf: boolean?) -> any,
}

function scroll_into_view.new(deps: Deps): ScrollIntoView
	local adapter = deps.adapter
	local controller = deps.controller
	local lastRects = deps.lastRects
	local lastScrollRegions = deps.lastScrollRegions
	local scrollHostOf = deps.scrollHostOf
	local screenRectOf = deps.screenRectOf
	local hostOriginOf = deps.hostOriginOf

	-- scroll-to-visible (A-SV1): THE shared keep-visible substrate. Every
	-- control that must bring a focused, selected, or newly-revealed descendant
	-- into view asks for it here instead of carrying its own scroll arithmetic,
	-- so the minimum-distance rule, the clamp, and the axis handling exist once.
	-- Returns true when it actually moved any containing scroll host.
	local function scrollToVisible(path: string, localRect: any?): boolean
		if adapter.setScrollPosition == nil then
			return false -- clip-only fallback adapter: nothing to scroll
		end
		-- the nearest ScrollView ANCESTOR (never `path` itself). `structuralSync`'s
		-- `livePaths` walk already threads that host down the tree and records it
		-- here — its own comment says it exists so this is not "computed on demand
		-- instead", which is exactly what a second full-tree walk here was doing
		-- (Step 5.5 cleanup ledger C-03). Absent from the map means not yet
		-- structurally synced, and such a path has no `lastRects` entry either, so
		-- both spellings refuse it.
		local hostPath: string? = scrollHostOf[path]
		if hostPath == nil then
			return false
		end
		local targetRect = lastRects[path]
		if targetRect == nil then
			return false
		end
		-- Stored rects may be relative to different coordinate-space hosts. Bring
		-- both into the solved absolute space before comparing their canvas spans.
		local tox, toy = hostOriginOf(path)
		local targetX, targetY = targetRect.x + tox, targetRect.y + toy
		local width, height = targetRect.w, targetRect.h
		if localRect ~= nil then
			targetX += localRect.x
			targetY += localRect.y
			width, height = localRect.w, localRect.h
		end
		local moved, guard = false, 0
		while hostPath ~= nil and guard < 32 do
			local hostRect, region = lastRects[hostPath], lastScrollRegions[hostPath]
			if hostRect == nil or region == nil then
				break
			end
			local hox, hoy = hostOriginOf(hostPath)
			local current = controller.scrollPosition(hostPath) or { x = 0, y = 0 }
			-- The same minimum-distance rule handles each scrollable axis. Inner
			-- offsets have already been removed from the target's canvas span.
			local function wantedOn(isX: boolean): number?
				local offset = if isX then current.x else current.y
				local band = if isX then hostRect.w else hostRect.h
				local extent = if isX then region.contentW else region.contentH
				local top = if isX then targetX - hostRect.x - hox else targetY - hostRect.y - hoy
				return solver.keepVisibleOffset(top, if isX then width else height, offset, band, extent)
			end
			local wantX = if region.axis ~= "y" then wantedOn(true) else nil
			local wantY = if region.axis ~= "x" then wantedOn(false) else nil
			if wantX ~= nil or wantY ~= nil then
				current = {
					x = if wantX ~= nil then wantX else current.x,
					y = if wantY ~= nil then wantY else current.y,
				}
				controller.scrollTo(hostPath, current)
				moved = true
			end
			-- Revealing a rail child is insufficient when the rail itself is clipped
			-- by a scrolling page. Walk the existing ancestor chain, carrying the
			-- actual inner offsets so an outer host reveals the same painted target.
			current = controller.scrollPosition(hostPath) or current
			targetX -= current.x
			targetY -= current.y
			hostPath = scrollHostOf[hostPath]
			guard += 1
		end
		return moved
	end

	-- THE SCROLL HOST THAT CARRIES A NODE, with everything an edge autoscroll
	-- needs to steer it, in ONE answer (Table's reorder autoscroll, 2026-07-29).
	--
	-- A control cannot work this out for itself. The host may be its own scroller
	-- (a viewport Table's Body) or an ANCESTOR it does not own — a block Table
	-- inside a scrolling page is the shipped shape, and there the thing that has
	-- to move belongs to the consumer's screen, not to the control. The nearest
	-- ScrollView ancestor is already threaded down `structuralSync`'s live-path
	-- walk for `screenRectOf`, and the canvas extent is already recorded per host
	-- for the region push, so this exposes the pair rather than tempting three
	-- separate internals out through the API (the same argument `scrollToVisible`
	-- makes for the keep-visible arithmetic).
	--
	-- `rect` is in WINDOW space, because the caller compares it against a POINTER.
	-- Pass `includeSelf` for a node that may BE the host.
	local function scrollHostFor(path: string, includeSelf: boolean?): any
		local hostPath: string? = if includeSelf == true and lastScrollRegions[path] ~= nil
			then path
			else scrollHostOf[path]
		if hostPath == nil then
			return nil
		end
		local region = lastScrollRegions[hostPath]
		local rect = screenRectOf(hostPath)
		if region == nil or rect == nil then
			return nil
		end
		local isX = region.axis == "x"
		local offset = controller.scrollPosition(hostPath) or { x = 0, y = 0 }
		local band = if isX then rect.w else rect.h
		local extent = if isX then region.contentW else region.contentH
		return {
			path = hostPath,
			rect = rect,
			axis = if isX then "x" else "y",
			offset = if isX then offset.x else offset.y,
			-- clamped the way the engine clamps CanvasPosition: nothing to scroll
			-- reports 0, which is what makes an autoscroll model INERT rather than
			-- arming against a canvas that cannot move
			maxScroll = math.max(0, extent - band),
		}
	end

	return {
		scrollToVisible = scrollToVisible,
		scrollHostFor = scrollHostFor,
	}
end

return scroll_into_view
