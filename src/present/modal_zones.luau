--!strict
-- MODAL OUTSIDE-TAP GEOMETRY: the two-zone test (modal-dismissal spec).
-- Extracted from `presenter.luau` 2026-08-06.
--
-- WHY IT LIVES HERE. `presenter.luau` had grown to 200 609 characters — past the
-- 200 000 at which Roblox refuses a script-driven `Source` assignment — and 78% of it
-- is a single closure (`presenter.new`) whose parts all share upvalues. This block was
-- never inside that closure: it is pure, takes everything it needs as arguments, and
-- holds no state. Moving it is a FILE MOVE, not a refactor, and the bodies below are
-- byte-identical to what they were in `presenter.luau` — including their comments,
-- which are where this behaviour's reasoning is recorded.
--
-- The exports are listed at the BOTTOM rather than written as `function M.x`, so that
-- every internal call site keeps calling a plain local and no line of the moved code
-- had to change.

-- ONE borrowed symbol: Zone A's focus-hit test asks whether a node is focusable, and
-- that vocabulary belongs to the focus map. No cycle — `focus_map` requires only the
-- input contribution module.
local focusMap = require("./focus_map")
local FOCUSABLE = focusMap.FOCUSABLE

-- ===== modal outside-tap: two-zone geometry (modal-dismissal spec) ==========
-- Zone A ("no dismiss") is the modal's PAINTED region, never its blueprint-path
-- envelope: an invisible/transparent container that geometrically covers the
-- screen contributes NOTHING (defusing the "fill root swallows every tap"
-- footgun), while a VISIBLE fullscreen panel correctly has no outside. A node is
-- "painted" iff it carries a `surface` fill OR is a content-bearing leaf.
local CONTENT_PAINTED: { [string]: boolean } =
	{ Text = true, Button = true, Toggle = true, TextField = true, Image = true }
-- forgiveness ring = space.l (≈ half the hit floor) and the effective hit floor
-- itself (targetSizes.minimum). Roles, not literals — the boundary mirror of the
-- target-forgiveness logic (spec §3.2).

local function pointInRect(x: number, y: number, r: any): boolean
	return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function inflate(r: any, m: number): any
	return { x = r.x - m, y = r.y - m, w = r.w + 2 * m, h = r.h + 2 * m }
end

-- inflate a rect symmetrically so each axis reaches at least `floor` (the 44px
-- effective hit rect of an edge button that may be smaller than its target)
local function inflateToFloor(r: any, floor: number): any
	local dw = math.max(0, floor - r.w)
	local dh = math.max(0, floor - r.h)
	return { x = r.x - dw / 2, y = r.y - dh / 2, w = r.w + dw, h = r.h + dh }
end

-- is (x,y) inside `subtreeRoot`'s Zone A? = ( outermost painted panel bbox ⊕ 24 )
-- ∪ ( each focusable's 44px hit rect ). Reads SOLVED rects (rectOf), replacing
-- the pure path-prefix test for the dismiss decision. Returns false when nothing
-- is painted (a wholly-invisible surface has no Zone A, so every tap is Zone B).
-- Scoped to any subtree so both a modal (whole root) and a transient popup (its
-- contribution subtree) share one geometry (ADR-0014 two-zone model).
local function zoneAContains(rectOf: (string) -> any, subtreeRoot: any, x: number, y: number, metrics: any): boolean
	local forgiveMargin: number = metrics.space.l
	local hitFloor: number = metrics.targetSizes.minimum
	local bbox: any = nil
	local focusHit = false
	local function consider(node: any)
		local props = node.props
		local painted = (props ~= nil and props.surface ~= nil) or CONTENT_PAINTED[node.class] == true
		if painted then
			local r = rectOf(node.path)
			if r ~= nil then
				if bbox == nil then
					bbox = { x = r.x, y = r.y, w = r.w, h = r.h }
				else
					local bx2 = math.max(bbox.x + bbox.w, r.x + r.w)
					local by2 = math.max(bbox.y + bbox.h, r.y + r.h)
					bbox.x = math.min(bbox.x, r.x)
					bbox.y = math.min(bbox.y, r.y)
					bbox.w = bx2 - bbox.x
					bbox.h = by2 - bbox.y
				end
				if FOCUSABLE[node.class] and not (props ~= nil and props.focusable == false) then
					if pointInRect(x, y, inflateToFloor(r, hitFloor)) then
						focusHit = true
					end
				end
			end
		end
		for _, child in node.children or {} do
			consider(child)
		end
	end
	if subtreeRoot ~= nil then
		consider(subtreeRoot)
	end
	if focusHit then
		return true
	end
	return bbox ~= nil and pointInRect(x, y, inflate(bbox, forgiveMargin))
end

local function modalInZoneA(handle: any, x: number, y: number, metrics: any): boolean
	return zoneAContains(handle.controller.rectOf, handle.root.node, x, y, metrics)
end

return {
	pointInRect = pointInRect,
	inflate = inflate,
	inflateToFloor = inflateToFloor,
	zoneAContains = zoneAContains,
	modalInZoneA = modalInZoneA,
}
