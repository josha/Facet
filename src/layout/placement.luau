--!strict
--[[ placement — THE ARRANGE PASS'S PURE ARITHMETIC.

	Public interface, one table and four functions, every one of them a pure
	function on numbers:

	  `placement.ANCHOR_FACTORS`   the nine anchor names as (fx, fy) pairs.
	  `placement.offsetPx(value, extent)`        an offset in pixels.
	  `placement.offsetFill(available, offset, factor)`
	                               the extent a `fill` anchor child may take once
	                               its own offset is paid for.
	  `placement.alignOffset(align, avail, size)`  cross-axis alignment.
	  `placement.distributionOf(mode, slack, count) -> (lead, step)`
	                               main-axis distribution.

	It depends on `../num` for `roundPx` and on nothing else — no ctx, no node, no
	solver local, no state, no module-level mutable local at all. Nothing here
	reads the solve; that is why it could leave without taking an argument with it,
	the same test `./placement_audit` passed one round earlier.

	WHY IT IS ITS OWN FILE. `tools/lune/verify/data/source-cap-ledger.md`'s solver row names
	this block by name as the seam BEHIND `flowPartition`/`flowPlan`, and its
	trigger is a STATE rather than a number: the extraction PRECEDES the round's
	own changes rather than accompanying them, which is what `renderer.luau`,
	`presenter.luau` and `table.luau` each learned the hard way one file over.

	`alignOffset` ALREADY TRAVELLED as an ordinary argument — `grid.arrange` and
	`grid.arrangeRow` have taken it as a parameter since the grid split, because it
	is declared BELOW them in the solver and a closure naming it there would
	resolve the nil GLOBAL. That is the standing proof this block reads nothing of
	its host: one of its five names has been crossing a module boundary by value
	for two rounds already.
]]

local num = require("../num")
local roundPx = num.roundPx

local placement = {}

placement.ANCHOR_FACTORS = {
	topLeft = { 0, 0 },
	top = { 0.5, 0 },
	topRight = { 1, 0 },
	left = { 0, 0.5 },
	center = { 0.5, 0.5 },
	right = { 1, 0.5 },
	bottomLeft = { 0, 1 },
	bottom = { 0.5, 1 },
	bottomRight = { 1, 1 },
} :: { [string]: { number } }

-- offsetPx(value, extent): an offset in pixels. A number passes through; the
-- `{ scale, offset }` form is a FRACTION OF THE PARENT'S INNER EXTENT plus a px
-- adjustment — the shape a marker overlay needs,
-- because a minimap dot's position is a share of the map and not a pixel count.
-- Rounded, because every other placement in the solver is: a marker on a
-- half-pixel is a marker the engine antialiases into a smudge.
function placement.offsetPx(value: any, extent: number): number
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "table" then
		return 0
	end
	local scale = if type(value.scale) == "number" then value.scale else 0
	local offset = if type(value.offset) == "number" then value.offset else 0
	return roundPx(scale * extent + offset)
end

-- The extent a `fill` anchor child may take once its own offset is paid for.
-- A module-level function, not a closure: the solver is perf-pinned, and this
-- used to be a closure allocated per anchor child per solve.
function placement.offsetFill(available: number, offset: number, factor: number): number
	if offset == 0 then
		return available
	end
	local facing = if offset > 0 then 1 - factor else factor
	if facing <= 0 then
		return available -- anchored to the edge it is being pushed past
	end
	return math.max(0, available - math.abs(offset) / facing)
end

function placement.alignOffset(align: string?, avail: number, size: number): number
	if align == "center" then
		return math.floor((avail - size) / 2)
	elseif align == "end" then
		return avail - size
	end
	return 0
end

-- MAIN-AXIS DISTRIBUTION (§2.6). Returns (lead, step): the pixels before the
-- first child, and the pixels added to every gap between children. Both 0 for
-- `"start"`, which is why the default is byte-identical to the hard-anchored
-- cursor that branch always had.
--
-- One child is not a special case in the arithmetic, and the answers it falls out
-- with are CSS's: `spaceBetween` pins it at the start (there is no gap to fill),
-- `spaceAround` and `spaceEvenly` centre it.
function placement.distributionOf(mode: string, slack: number, count: number): (number, number)
	if slack <= 0 or count <= 0 then
		return 0, 0
	elseif mode == "center" then
		return slack / 2, 0
	elseif mode == "end" then
		return slack, 0
	elseif mode == "spaceBetween" then
		return 0, if count > 1 then slack / (count - 1) else 0
	elseif mode == "spaceAround" then
		return slack / count / 2, slack / count
	elseif mode == "spaceEvenly" then
		return slack / (count + 1), slack / (count + 1)
	end
	return 0, 0
end

-- THE INNER (CONTENT) BOX, ONE COPY (Plan C, T2). `arrange` derives
-- it at the padding block and the translate lane needs the identical four numbers
-- to place a host the way the solver would have; the `math.max(0, …)` clamp is
-- exactly the kind of detail a second hand-written copy loses.
function placement.innerBox(
	x: number,
	y: number,
	w: number,
	h: number,
	pt: number,
	pr: number,
	pb: number,
	pl: number
): (number, number, number, number)
	return x + pl, y + pt, math.max(0, w - pl - pr), math.max(0, h - pt - pb)
end

-- THE CORNER-ANCHOR PLACEMENT, ONE COPY (Plan C, T2). The solver's anchor branch
-- and the translate lane (`render/translate_lane`) both place a child from the
-- same eleven inputs, and a second hand-written copy is how the two would start
-- disagreeing by a rounding. `unknownAnchor` reports a factor lookup miss so the
-- caller files the diagnostic the solver always filed; the placement falls back
-- to `topLeft` exactly as it did.
--
-- fill children stretch to the anchor (content layers under overlays) MINUS THE
-- ROOM THEIR OWN OFFSET COSTS THEM (director round 10, found live 2026-07-26). A
-- `fill` child used to take the WHOLE anchor box and then get displaced by
-- `offsetX`/`offsetY`, so it hung off the far edge by exactly the offset —
-- silently, because nothing clips an anchor. The gallery's chrome column is this
-- shape: `anchor = "topLeft"` + `height = fill` + `offsetY = <CoreGui topbar
-- inset>`, so its bottom ran off the phone by the topbar's height and the last row
-- of whatever it held was unreachable. Studio Neutral never showed it because its
-- content stopped well short of the lost strip; a taller theme's did not.
--
-- How much to give back: the child sits at (inner - size) * f + offset. Staying
-- inside the far edge needs `offset <= (inner - size) * (1 - f)`, and inside the
-- near edge needs `(inner - size) * f + offset >= 0`. Solve for the size and the
-- shrink is |offset| over the factor facing the way the offset pushes — so a
-- centred child gives back TWICE its offset (it loses room at both ends) and an
-- edge-anchored one gives back exactly it.
--
-- Pushing a child OUT past the very edge it is anchored to (right anchor,
-- positive offsetX) is deliberate — an off-screen drawer, a peeking tab — and no
-- width can bring it back, so that case is left alone.
--
-- resolved ONCE, before either use: a fractional offset is a share of this
-- anchor's inner box, and the fill give-back below and the placement itself have
-- to spend the same number.
function placement.anchorPlace(
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	w: number,
	h: number,
	wFill: boolean,
	hFill: boolean,
	anchor: string?,
	offsetX: any,
	offsetY: any
): (number, number, number, number, boolean)
	local f = placement.ANCHOR_FACTORS[anchor or "topLeft"]
	local unknown = f == nil
	if unknown then
		f = placement.ANCHOR_FACTORS.topLeft
	end
	local ox = placement.offsetPx(offsetX, innerW)
	local oy = placement.offsetPx(offsetY, innerH)
	if wFill then
		w = placement.offsetFill(innerW, ox, f[1])
	end
	if hFill then
		h = placement.offsetFill(innerH, oy, f[2])
	end
	local x = innerX + roundPx((innerW - w) * f[1]) + ox
	local y = innerY + roundPx((innerH - h) * f[2]) + oy
	return x, y, w, h, unknown
end

return placement
