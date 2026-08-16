--!strict
--[[ ANCHORED PLACEMENT — the pure decision behind every surface that points at
	something (navigation-and-menus brief §2 D1).

	`UI.Anchor` gives nine fixed corners inside a PARENT and never clamps: pushing
	a child off the edge is deliberately allowed (solver.luau's "an off-screen
	drawer, a peeking tab"). A popover, a menu, a coach mark and a disclosure
	plate all want the other thing — a box placed against the SCREEN RECT OF
	ANOTHER VIEW, kept inside the safe area, with an arrow that still points at
	the thing it came from. This module is that arithmetic and nothing else.

	PURE, AND DELIBERATELY SO. Plain numbers and strings in, a plain table out:
	no env, no signals, no theme, no engine, no mounted tree. That is this
	codebase's standing shape for a decision function — `popup_button
	.resolvePresentation(optionCount, sizeClass, touchLive)` is the same idea —
	and it is what lets three different callers share ONE answer:

	  * `src/present/anchored.luau`   the presented anchored surface (D1)
	  * `src/present/presenter.luau`  the full-value disclosure plate, whose
	                                  `clampDisclosure` was the first hand-rolled
	                                  copy of these rules
	  * `src/controls/row_actions.luau` the row's floating action menu, whose
	                                  `computeMenuAnchor` was the second

	THE FOUR RULES, in the order they are applied:

	  1. PLACE on the preferred edge, `gap` px off the source.
	  2. FLIP to the opposite edge when the preferred placement crosses the safe
	     box AND the opposite one lies wholly inside it. Both halves are
	     load-bearing: row_actions' own ruling (2026-08-13, ruling 4) is that it
	     "never flips into a worse place — a menu too tall for the space above
	     stays below (partly clipped is better than partly clipped AND upside
	     down)". A flip that lands somewhere worse is a regression, not a fix.
	  3. SHIFT along the edge until the surface is inside the safe box, and
	     report how far it moved. `shift` is signed and in px, because the tail
	     rule and every diagnostic want to know.
	  4. TAIL: centre it on the SOURCE's own centre, keep it clear of the
	     surface's rounded corners, and SUPPRESS it when the clamped position is
	     no longer over the source. An arrow pointing at nothing is worse than no
	     arrow.

	WHAT `overflow` DECIDES — what happens when the surface fits on NEITHER edge:
	  * "clamp" (default) — pull it back inside the safe box on the placement
	    axis. Correct for a plate or a callout: a surface under a notch or behind
	    the home indicator is unreadable (presenter.luau's `safeBox` comment).
	  * "keep" — leave it where the preferred edge put it, partly outside. This
	    is row_actions' ruling: "a clamp lets the menu cover its own trigger", and
	    a menu that hides the row it belongs to is worse than one that is clipped.
	Neither is right for both, so the caller says which, once, in its own source.

	WRITING DIRECTION. `leading`/`trailing` resolve to `left`/`right`. LuauUI has
	no RTL fact today (`src/present/text_reveal.luau` records the same absence for
	the same reason); when one lands, `resolveEdge` below is the one place that
	changes, which is why the vocabulary is directional at the boundary and
	absolute inside.
]]

local anchor_placement = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Size = { w: number, h: number }

export type Request = {
	-- the source view's rect in WINDOW space. `controller.screenRectOf(path)` is
	-- the API that answers this — it corrects for accumulated nested-scroll
	-- offset AND for a live presentation shift, which `rectOf` does not.
	source: Rect,
	-- the surface's own solved size (a solve output; measure first, place second)
	size: Size,
	-- the box the surface may occupy, in WINDOW space: the viewport less the
	-- per-edge MAXIMUM of the two inset facts. `presenter.safeBox()` is it.
	safe: Rect,
	edge: string?, -- "top" | "bottom" | "leading" | "trailing" (default "bottom")
	align: string?, -- "start" | "center" | "end" (default "center")
	gap: number?, -- distance from the source's edge, default 0
	-- the tail's extent ALONG the edge (its painted width for a top/bottom
	-- placement, its painted height for a side one). 0 or absent = no tail.
	tail: number?,
	-- how far the surface's own corners reach, so the tail never grows out of a
	-- rounded one: usually the panel's corner RADIUS. Half the tail's own width is
	-- added to this here, so a caller passes the radius and nothing else.
	tailInset: number?,
	overflow: string?, -- "clamp" (default) | "keep"
}

export type Placement = {
	x: number,
	y: number,
	w: number,
	h: number,
	edge: string, -- the RESOLVED edge: "top" | "bottom" | "left" | "right"
	flipped: boolean,
	shift: number, -- signed px moved along the edge away from the aligned position
	fits: boolean, -- is the final rect wholly inside the safe box?
	tailX: number?, -- the tail's CENTRE, window space, on the shared border
	tailY: number?,
	tailSuppressed: boolean,
}

local EDGES: { [string]: boolean } = table.freeze({ top = true, bottom = true, leading = true, trailing = true })
local ALIGNS: { [string]: boolean } = table.freeze({ start = true, center = true, ["end"] = true })
local OVERFLOWS: { [string]: boolean } = table.freeze({ clamp = true, keep = true })
local OPPOSITE: { [string]: string } = table.freeze({ top = "bottom", bottom = "top", left = "right", right = "left" })

anchor_placement.EDGES = EDGES
anchor_placement.ALIGNS = ALIGNS
anchor_placement.OVERFLOWS = OVERFLOWS

local function names(set: { [string]: boolean }): string
	local out: { string } = {}
	for name in set do
		table.insert(out, name)
	end
	table.sort(out)
	return table.concat(out, ", ")
end

-- Validation is a PUBLIC function because the anchored surface wants to refuse a
-- typo at `presentAnchored` time — the frame the author is looking at — rather
-- than on whatever later frame the first solve happens to run.
function anchor_placement.assertEdge(edge: any, where: string)
	if edge ~= nil and EDGES[edge] ~= true then
		error(`LuauUI {where}: unknown anchor edge '{tostring(edge)}'. Known: {names(EDGES)}.`, 0)
	end
end

function anchor_placement.assertAlign(align: any, where: string)
	if align ~= nil and ALIGNS[align] ~= true then
		error(`LuauUI {where}: unknown anchor align '{tostring(align)}'. Known: {names(ALIGNS)}.`, 0)
	end
end

function anchor_placement.assertOverflow(overflow: any, where: string)
	if overflow ~= nil and OVERFLOWS[overflow] ~= true then
		error(`LuauUI {where}: unknown anchor overflow '{tostring(overflow)}'. Known: {names(OVERFLOWS)}.`, 0)
	end
end

-- "leading"/"trailing" -> "left"/"right"; "top"/"bottom" pass through
function anchor_placement.resolveEdge(edge: string): string
	if edge == "leading" then
		return "left"
	elseif edge == "trailing" then
		return "right"
	end
	return edge
end

function anchor_placement.opposite(edge: string): string
	return OPPOSITE[edge] or edge
end

function anchor_placement.solve(req: Request): Placement
	local where = "anchor_placement.solve"
	anchor_placement.assertEdge(req.edge, where)
	anchor_placement.assertAlign(req.align, where)
	anchor_placement.assertOverflow(req.overflow, where)

	local source = req.source
	local size = req.size
	local safe = req.safe
	local gap = req.gap or 0
	local tail = math.max(req.tail or 0, 0)
	local tailInset = math.max(req.tailInset or 0, 0)
	local align = req.align or "center"
	local overflow = req.overflow or "clamp"
	local preferred = anchor_placement.resolveEdge(req.edge or "bottom")

	-- ---- 1. the two candidate placements on the placement axis --------------
	local function mainFor(edge: string): number
		if edge == "bottom" then
			return source.y + source.h + gap
		elseif edge == "top" then
			return source.y - gap - size.h
		elseif edge == "right" then
			return source.x + source.w + gap
		end
		return source.x - gap - size.w -- left
	end

	local function isVertical(edge: string): boolean
		return edge == "top" or edge == "bottom"
	end

	local function mainFits(edge: string): boolean
		local m = mainFor(edge)
		if isVertical(edge) then
			return m >= safe.y and m + size.h <= safe.y + safe.h
		end
		return m >= safe.x and m + size.w <= safe.x + safe.w
	end

	-- ---- 2. the flip, and the rule that it never lands somewhere worse ------
	local resolved = preferred
	local flipped = false
	if not mainFits(preferred) then
		local other = anchor_placement.opposite(preferred)
		if mainFits(other) then
			resolved = other
			flipped = true
		end
	end

	local vertical = isVertical(resolved)
	local edgePosition = mainFor(resolved)
	local main = edgePosition
	local mainExtent = if vertical then size.h else size.w
	local mainLow = if vertical then safe.y else safe.x
	local mainHigh = mainLow + (if vertical then safe.h else safe.w) - mainExtent
	if overflow == "clamp" then
		-- `math.max` rather than a guard, and the SAME expression the along-edge
		-- clamp below uses: a surface bigger than the safe box on this axis has no
		-- legal range at all, and pinning it to the leading inset shows its head
		-- rather than leaving it wherever the preferred edge put it — which for a
		-- tall panel under a low source is entirely off the bottom of the screen.
		main = math.clamp(main, mainLow, math.max(mainLow, mainHigh))
	end

	-- ---- 3. the along-edge alignment, then the shift that keeps it inside ---
	local alongExtent = if vertical then size.w else size.h
	local sourceLow = if vertical then source.x else source.y
	local sourceExtent = if vertical then source.w else source.h
	local aligned: number
	if align == "start" then
		aligned = sourceLow
	elseif align == "end" then
		aligned = sourceLow + sourceExtent - alongExtent
	else
		aligned = sourceLow + sourceExtent / 2 - alongExtent / 2
	end
	local alongLow = if vertical then safe.x else safe.y
	local alongHigh = alongLow + (if vertical then safe.w else safe.h) - alongExtent
	-- a surface WIDER than the safe box has no legal range at all; pin it to the
	-- leading inset rather than letting a reversed clamp centre it off-screen
	local along = math.clamp(aligned, alongLow, math.max(alongLow, alongHigh))
	local shift = along - aligned

	local rect: Rect = if vertical
		then { x = along, y = main, w = size.w, h = size.h }
		else { x = main, y = along, w = size.w, h = size.h }

	local fits = rect.x >= safe.x
		and rect.y >= safe.y
		and rect.x + rect.w <= safe.x + safe.w
		and rect.y + rect.h <= safe.y + safe.h

	-- ---- 4. the tail ------------------------------------------------------
	local tailX: number? = nil
	local tailY: number? = nil
	local tailSuppressed = true
	if tail > 0 then
		local half = tail / 2
		local keepLow = along + tailInset + half
		local keepHigh = along + alongExtent - tailInset - half
		if keepHigh >= keepLow then
			local centre = math.clamp(sourceLow + sourceExtent / 2, keepLow, keepHigh)
			-- THE SUPPRESSION RULE, in two halves. The tail is only allowed to exist
			-- while it is still over the source AND still on the border it shares
			-- with it:
			--   * ALONG the edge — a surface shifted far enough ends up with its
			--     nearest legal tail position past the source entirely, and an arrow
			--     pointing at empty screen is a lie about where the panel came from;
			--   * ACROSS it — `overflow = "clamp"` can pull a surface that fits
			--     nowhere off the edge it was placed on, and a wedge left on the
			--     panel's border there is an arrow with a gap under it, pointing from
			--     somewhere the panel is not.
			tailSuppressed = main ~= edgePosition or centre < sourceLow or centre > sourceLow + sourceExtent
			if vertical then
				tailX = centre
				tailY = if resolved == "bottom" then rect.y else rect.y + rect.h
			else
				tailX = if resolved == "right" then rect.x else rect.x + rect.w
				tailY = centre
			end
		end
	end

	return {
		x = rect.x,
		y = rect.y,
		w = rect.w,
		h = rect.h,
		edge = resolved,
		flipped = flipped,
		shift = shift,
		fits = fits,
		tailX = tailX,
		tailY = tailY,
		tailSuppressed = tailSuppressed,
	}
end

return anchor_placement
