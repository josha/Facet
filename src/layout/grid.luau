--!strict
--[[ grid — UI.Grid's WHOLE arithmetic, both layouts and both passes.

	Public interface, four entry points and one type:

	  `grid.measure(deps, ctx, node, innerMaxW, innerMaxH, gap) -> (w, h)`
	      the content extent of a `grid` node, padding EXCLUDED on both sides of
	      the call (the solver removes it before and adds it after, exactly as it
	      does for every other container).
	  `grid.measureRow(deps, ctx, node, innerMaxW, innerMaxH) -> (w, h)`
	      the same for a bare `gridrow` node — one row measured on its own.
	  `grid.arrange(deps, ctx, node, innerX, innerY, innerW, innerH, gap, place,
	      alignOffset, out)`
	  `grid.arrangeRow(deps, ctx, node, innerX, innerY, innerW, innerH, place,
	      alignOffset, out)`
	      the placement halves of the same two.

	`grid.Deps` is what it needs from the solver. It depends on nothing else — no
	require of its own, no state, no module-level mutable local at all.

	WHY IT IS ITS OWN FILE. `src/layout/solver.luau` was 194,222 characters, 5,778
	from the 200,000-char `Script.Source` write cap that stops a module live-syncing
	into an open Studio session — silently, so a live check against it then tests
	the built place rather than the edits (`tools/check_source_size.py`,
	`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`). This seam was
	NAMED BY THE MISSION THAT GREW THE FILE, in `02b9df1`: "the grid is now a
	coherent ~9k unit (`gridFlowPlan`, `gridColumnPlan`, both measure and arrange
	branches). The next grid change should extract it to `src/layout/grid.luau` the
	way `shrink.luau` was extracted, not squeeze."

	IT IS COHERENT BECAUSE IT IS WRITTEN IN LANE/FLOW WORDS. The flow grid's two
	axes are the LANE axis and the FLOW axis, and they bind to width/height in
	exactly TWO places: `innerLane`/`innerFlow` in `gridFlowPlan`, and the
	placement in `grid.arrange`. Those two bindings are the reason the arrange
	branch moved WITH the plan instead of staying behind: a file that owned the
	lane arithmetic while a sibling owned the lane-to-x/y translation would be one
	edit away from the transpose disagreeing with itself, and `flow = "column"` is
	an exact transpose of `flow = "row"` or it is nothing
	(`tests/grid_column_flow.spec.luau`).

	MEASURE AND ARRANGE SHARE ONE PLAN, AND THAT IS THE WHOLE CONSTRAINT ON
	TOUCHING THIS FILE. This library's recurring defect — fixed four separate times
	— is a container that measured one shape and arranged another, so both passes
	call ONE function (`gridFlowPlan` / `gridColumnPlan`) and read its answer;
	there is no second copy and no per-pass branch. The `ctx.gridPlan` cache is
	determinism and cost, NOT the guarantee: clearing it before arrange reddens
	nothing, because the single-owner FUNCTION is what makes the two passes unable
	to disagree. So the property to preserve across this seam is one OWNER, not one
	cache — `tests/grid_measure_arrange.spec.luau` states it as a fixed point
	(measure, arrange, measure again, same answer) and `grid_column_flow.spec`
	carries the transposed twin of every such case.

	WHAT IT NEEDS FROM THE SOLVER, and why it arrives in two different ways.

	`Deps` (below) carries the three things the MEASURE side needs — `measure`,
	`dim`, `sides`. The solver builds it ONCE, at module scope, and threads it as
	an explicit argument rather than letting this module capture anything, which is
	the shape `shrink.luau` set: the module holds no state and two solves can never
	see different helpers. One wrinkle `shrink` did not have — the solver's
	`measure` is one of its three FORWARD DECLARATIONS (declared near the top,
	assigned ~1,500 lines below, because the memo and its body are mutually
	recursive), so a load-time record cannot hold it BY VALUE; it holds a two-line
	forwarder that reads the local at call time. That is the same read `contentSize`
	makes, not new machinery.

	`place` (the solver's recursive `arrange`) and `alignOffset` arrive as ORDINARY
	ARGUMENTS at the two arrange call sites instead, and deliberately so: both are
	declared BELOW the point where `Deps` is built, so a forwarder for them written
	up there would resolve as a nil GLOBAL and die inside a protected boundary —
	`docs/lessons/a-helper-declared-below-its-caller-is-a-global.md`, which cost a
	mission an hour during the grid work itself. Forward-declaring them to fix that
	would ADD a mutable module local to the solver, which is the opposite of what
	this split is for. Passed at the call site they are in genuine lexical scope,
	and the compiler proves it.
]]

local adaptive = require("./adaptive")
local num = require("../num")
-- bound at module scope: `solver.luau` records that a per-call allocation on
-- the measure path is a bench regression this repository has already paid for
local roundPx = num.roundPx

local grid = {}

-- What the plan needs from the solver, passed at every call. Typed `any` for the
-- node/ctx arguments on purpose: the solver requires THIS module, so importing
-- `solver.Node`/`Ctx` back would be a require cycle, and re-declaring either
-- schema here is the copy-goes-stale failure this seam exists to avoid — the same
-- ruling `shrink.Deps` carries.
export type Deps = {
	measure: (ctx: any, node: any, maxW: number, maxH: number) -> (number, number),
	dim: (node: any, axis: string) -> any,
	sides: (margin: any) -> (number, number, number, number),
}

-- the solver's recursive `arrange`, and its cross-axis alignment helper. See the
-- header for why these two are arguments and not `Deps` fields.
export type Place = (ctx: any, node: any, rect: any, out: { [string]: any }) -> ()
export type AlignOffset = (align: string?, avail: number, size: number) -> number

-- INTRINSIC COLUMNS (director round 9, 2026-07-26). `minColumnWidth` used to be
-- a literal, which is a guess about a FONT: the gallery's theme picker asked for
-- 132 device px, and under classic-desktop (13 px BuilderSans) that is far too
-- wide while under sci-fi (14 px Michroma, a display face) it is far too narrow
-- — so the same picker over-wrapped in one theme and under-wrapped in the other,
-- and long names clipped against a fixed row height.
--
-- `minColumnWidth = "intrinsic"` asks for the number the solver already has: the
-- widest child's own measured width under the ACTIVE theme's font and metrics.
-- It is recomputed on every solve, so a theme swap re-lays the grid out with no
-- author involvement. A `fill`-width child cannot express an intrinsic minimum
-- (it measures to whatever it is offered), so those are skipped; a grid of only
-- fill children has no minimum to take and falls back to one lane, which since
-- the single-lane case below is the only shape that still lands there.
local INTRINSIC = "intrinsic"
--[[ ...AND IT IS ALSO THE DEFAULT (audit Part 2 cell B-1, 2026-08-21).

	A `UI.Grid` that declared neither `columns` nor `minColumnWidth` used to get ONE
	LANE at every width from a 390px phone to a 1920px television — "a column of
	cards down the left edge", measured at all six combos. That is this library's
	systemic defect shape one primitive over: an adaptive rule that is exported,
	correct and unit-tested, and off unless the author names it (`0 of 35` shipped
	`UI.Grid` call sites reached lanes reactively).

	The default is now `"intrinsic"` — the route `docs/guide/05-styling.md` already
	teaches — rather than a lane count or a device-pixel guess. That choice is what
	keeps the fix from adding anything to the framework:

	  * NO NEW NUMBER. A minimum in px is a claim about a font; the widest child's
	    own measured extent is a fact the solve already has, so a theme swap
	    re-lanes the grid with no author involved.
	  * ONE ARITHMETIC, still. The default reaches `adaptive.columnsFor` through
	    exactly the line the declared route reaches it through, so the ten-foot cap
	    rides along for free and a television gets FEWER lanes than a desktop
	    (measured: 5 against 9) instead of the one lane it used to share with a
	    phone.
	  * THE FALLBACK IS UNCHANGED. A grid of only `fill` children still has no
	    intrinsic minimum to take, and still gets one lane.

	AUTHORED ALWAYS WINS, both keys and both directions: `columns` short-circuits
	`gridLaneCount` before this is asked at all, and a declared `minColumnWidth`
	is returned above without measuring anything.
]]
-- `isCol` is the flow grid's ONE axis switch (see `gridFlowPlan`): the lane axis is
-- the width under `flow = "row"` and the height under `flow = "column"`, so the
-- intrinsic minimum is measured on whichever one the mode chose. The prop keeps the
-- name `minColumnWidth` in both modes because a grid has one lane minimum, not two.
local function gridLaneMin(deps: Deps, ctx: any, node: any, isCol: boolean): number?
	local declared = node.minColumnWidth
	if type(declared) == "number" then
		return declared
	end
	if declared ~= nil and declared ~= INTRINSIC then
		return nil
	end
	local widest = 0
	for _, child in node.children or {} do
		if deps.dim(child, if isCol then "h" else "w").type == "fill" then
			continue
		end
		-- LANE-axis margins only: this is an intrinsic LANE extent
		local mt, mr, mb, ml = deps.sides(child.margin)
		local w, h = deps.measure(ctx, child, math.huge, math.huge)
		local own = if isCol then h + mt + mb else w + ml + mr
		widest = math.max(widest, own)
	end
	return if widest > 0 then widest else nil
end

-- UNIFORM ITEM SIZING (director ruling, 2026-07-26). `itemSizing = "uniform"`
-- measures every child in the column it will occupy, takes the MAX measured size
-- across ALL of them, and hands that back as every cell's size — so a set of
-- ragged, variable-width chips becomes a clean grid of equal plates and a wide
-- display face grows all of them together on the next solve.
--
-- OPT-IN, and `natural` is the default framework-wide: content sizing is what
-- every existing grid was authored against, and a layout that silently equalised
-- its cells would move geometry nobody asked to move.
--
-- Both passes call this, so measure and arrange cannot disagree about the row
-- height (a grid that measured ragged rows and arranged uniform ones is exactly
-- the class of defect this round spent its time on).
-- THE ROW GAP IS ITS OWN AXIS (director finding 14, measured live 2026-07-26).
--
-- A grid's `gap` was doing two jobs whose consequences are not comparable. The
-- COLUMN pitch is `innerW / cols` — a gap change moves the cells inside a
-- column, and (through `minColumnWidth`) can re-column the whole grid, which in
-- the theme picker is a director ruling. The ROW pitch IS the gap. So the
-- picker's grid ran with rows 4 px apart and columns 78 px apart and read
-- cramped, and there was no way to open the rows without risking the columns.
--
-- `rowGap` defaults to `gap`, so every grid in the library, the examples and the
-- fixtures is byte-unchanged and no baseline moves; a caller that wants air
-- between rows says so in one word and the column arithmetic never sees it.
-- HOW MANY LANES THIS GRID GETS, decided once (Step 5.5 cleanup ledger C-04).
-- Measure and arrange both need it and used to derive it separately; a grid whose
-- two passes disagree is this library's documented recurring defect class, so the
-- arithmetic gets one owner rather than two copies that happen to match today.
-- An unbounded offer (`math.huge`, only reachable from measure) yields one lane:
-- a lane count derived from an infinite extent is not a number anyone can use.
-- `inner` is the LANE axis's inner extent, which the mode picks (`gridFlowPlan`).
local function gridLaneCount(ctx: any, node: any, inner: number, gap: number, minCol: number?): number
	if node.columns ~= nil then
		return node.columns :: number
	end
	if minCol ~= nil and inner ~= math.huge then
		--[[ ONE IMPLEMENTATION OF THE LANE COUNT, and now it is literally one.
			`adaptive.columnsFor` has always been documented as "the SAME
			arithmetic the solver's Grid uses" and was a second copy of it, which is
			how the two came to disagree about distance: the helper and the solver
			both ignored the ten-foot density cap that `sizeClass`/`heightClass`
			apply, so the framework's own adaptive-grid route gave a TELEVISION more
			columns than a desktop. The cap lives in the pure function; this passes
			the fact the theme snapshot already carries (`density`, resolved from the
			display class), so predictor and solver cannot diverge again. ]]
		local density = if type(ctx.metrics) == "table" then (ctx.metrics :: any).density else nil
		return adaptive.columnsFor(inner, minCol, gap, {
			distanceProfile = if density == "ten-foot" then "ten-foot" else nil,
		})
	end
	return 1
end

local function gridRowGap(node: any): number
	local declared = (node :: any).rowGap
	if type(declared) == "number" then
		return declared
	end
	return node.gap or 0
end

local UNIFORM = "uniform"
-- ...in LANE/FLOW terms too: `laneSize` is the lane the cell will sit in and
-- `flowLimit` is the free axis, whichever pair of w/h those are in this mode.
local function gridUniformCell(
	deps: Deps,
	ctx: any,
	node: any,
	laneSize: number,
	flowLimit: number,
	isCol: boolean
): (number?, number?)
	if node.itemSizing ~= UNIFORM then
		return nil, nil
	end
	local uLane, uFlow = 0, 0
	for _, child in node.children or {} do
		local w, h =
			deps.measure(ctx, child, if isCol then flowLimit else laneSize, if isCol then laneSize else flowLimit)
		local ownLane = if isCol then h else w
		local ownFlow = if isCol then w else h
		uLane = math.max(uLane, if laneSize == math.huge then ownLane else math.min(ownLane, laneSize))
		uFlow = math.max(uFlow, ownFlow)
	end
	return uLane, uFlow
end

--[[ ===== THE FLOW GRID'S PLAN — ONE ARITHMETIC, TWO AXES ====================

	A flow grid has exactly two axes and neither of them is "x" or "y":

	  the LANE axis   the one the `columns` lanes are divided across
	  the FLOW axis   the one the lines advance along

	`flow = "row"` — the default, and every grid that shipped before 2026-08-15 —
	puts the lanes across the WIDTH and advances DOWN. `flow = "column"` transposes
	both, and that is the whole of column-major wrapping. Everything here is written
	once in lane/flow words, and those words are bound to width/height in exactly
	two places: `innerLane`/`innerFlow` below, and `grid.arrange`'s placement.
	So a column-major grid is NOT a second column arithmetic beside the row-major
	one — it is the same one read the other way, which `tests/grid_column_flow.spec`
	states as an exact transpose (same box turned on its side, same children with
	their axes exchanged, every rect back with x/y and w/h swapped).

	WHY THAT MATTERS BEYOND TIDINESS. `newVirtualGrid`'s design decision is that the
	mounted band IS a real `UI.Grid`, so the lane formula EXECUTES rather than being
	copied into the control where it would agree today and drift tomorrow. Without a
	column-major mode a sideways grid had no band to be, which is exactly what that
	control's `axis = "x"` refusal said (`src/controls/virtual_grid.luau`).

	THE PLAN IS THE ONE THING BOTH PASSES READ. Measure and arrange used to run two
	similar loops that agreed by sharing three helpers; this library's recurring
	defect — fixed four separate times — is a container that measured one shape and
	arranged another, so they now share the answer itself, cached on the context and
	keyed by the box exactly as the row grid's plan and the flow-wrap partition are.

	It carries two extents per cell because the two passes legitimately want
	different ones, and that difference is documented rather than duplicated:

	  `lane`   the extent the cell is PAINTED at inside its lane (arrange)
	  `share`  the extent it contributes to the grid's own report (measure)

	They differ in exactly one case — a naturally-sized, non-`fill` cell, where the
	report is the LANE (the column is the honest width: `columns = N` means "N equal
	lanes across what I was given" and a small cell aligns inside its lane) while
	the paint is the cell. Under `uniform` sizing the report is the CELL, because a
	uniform grid draws the max measured cell and no wider — the 2026-07-26 director
	round that found a full-width phone card holding a 130px column of chips.
]]
local COLUMN_FLOW = "column"
local function gridIsColumn(node: any): boolean
	return (node :: any).flow == COLUMN_FLOW
end

local function gridFlowPlan(deps: Deps, ctx: any, node: any, innerW: number, innerH: number, gap: number): any
	local key = `{innerW}|{innerH}|{gap}`
	local cached = ctx.gridPlan[node.id]
	if cached ~= nil and cached.key == key then
		return cached.value
	end
	local isCol = gridIsColumn(node)
	local innerLane = if isCol then innerH else innerW
	local innerFlow = if isCol then innerW else innerH
	local minLane = gridLaneMin(deps, ctx, node, isCol)
	local lanes = gridLaneCount(ctx, node, innerLane, gap, minLane)
	-- THE LANE EXTENT, FLOORED, AND BOTH PASSES READ THIS ONE NUMBER. The clamp
	-- keeps a gap/lane combination wider than the container from going negative
	-- (phase-4 layout fuzz, seed 206612356). Measure used to sum the UNROUNDED
	-- share while arrange painted the floored one, so a grid offered a width that
	-- did not divide evenly reported up to `lanes - 1` px more than it drew — the
	-- same fixed-point failure `grid_measure_arrange.spec` exists for, one rounding
	-- smaller. Sharing the plan is what makes that class unreachable rather than
	-- fixed again.
	local laneSize = if innerLane == math.huge
		then math.huge
		else math.max(0, math.floor((innerLane - gap * (lanes - 1)) / lanes))
	local uLane, uFlow = gridUniformCell(deps, ctx, node, laneSize, innerFlow, isCol)
	local children = node.children or {}
	local rowGap = gridRowGap(node)
	local cells: { any } = {}
	local lines: { any } = {}
	local flowTotal, laneMax = 0, 0
	local first = 1
	while first <= #children do
		local last = math.min(first + lanes - 1, #children)
		local lineFlow = 0
		local laneUsed = 0
		for j = first, last do
			local child = children[j]
			local w, h =
				deps.measure(ctx, child, if isCol then innerFlow else laneSize, if isCol then laneSize else innerFlow)
			local ownLane = if isCol then h else w
			local ownFlow = if isCol then w else h
			local isFill = deps.dim(child, if isCol then "h" else "w").type == "fill"
			local painted = if laneSize == math.huge
				then ownLane
				elseif isFill then laneSize
				elseif uLane ~= nil then math.min(uLane :: number, laneSize)
				else math.min(ownLane, laneSize)
			-- see the header: the report follows the CELL under uniform sizing and
			-- the LANE under natural sizing
			local share = if laneSize == math.huge
				then painted
				elseif uLane ~= nil and not isFill then painted
				else laneSize
			cells[j] = { lane = painted, flow = 0, ownFlow = ownFlow }
			-- gaps go BETWEEN cells: the last cell in a line ends the line whether it
			-- fills the last lane or not. A trailing gap here is a report the arrange
			-- never paints, which re-widened the lane on the next measure and grew
			-- every aspect-sized cell by 2px (the "2px overflow" half of 2026-08-08).
			laneUsed += share + (if j == last then 0 else gap)
			lineFlow = math.max(lineFlow, if uFlow ~= nil then uFlow :: number else ownFlow)
		end
		-- ...and the cell's FLOW extent, which cannot be known until the line is:
		-- a `fill` cell takes the line, a uniform one takes the uniform cell, and
		-- everything else keeps its content extent and ALIGNS inside the line.
		for j = first, last do
			local child = children[j]
			local cell = cells[j]
			local flowDim = deps.dim(child, if isCol then "w" else "h")
			local painted = if flowDim.type == "fill"
				then lineFlow
				elseif uFlow ~= nil then math.min(uFlow :: number, lineFlow)
				else math.min(cell.ownFlow, lineFlow)
			-- ASPECT FOLLOWS THE LANE, which is the axis the grid actually fixed
			-- (the same reason the stack arrange derives it from the resolved main
			-- extent: a `fill` sibling has no measure-time size). `ratio` is w/h, so
			-- the row-flow reading is `h = laneW / ratio` and the column-flow one is
			-- `w = laneH * ratio` — one statement, both modes.
			if flowDim.type == "aspect" and cell.lane > 0 then
				local ratio = flowDim.ratio :: number
				painted = if isCol then roundPx(cell.lane * ratio) else roundPx(cell.lane / ratio)
			end
			cell.flow = painted
		end
		table.insert(lines, { first = first, last = last, flow = lineFlow })
		flowTotal += lineFlow + (if last == #children then 0 else rowGap)
		laneMax = math.max(laneMax, laneUsed)
		first = last + 1
	end
	-- THE EXTENT A GRID REPORTS MUST RE-DERIVE ITS OWN LANE COUNT (found 2026-08-08,
	-- `grid_measure_arrange.spec`). The lane count above comes from the OFFER via
	-- `minColumnWidth`; `laneMax` is what the CELLS occupy, which under `uniform`
	-- sizing can be narrower than that minimum. A hug parent then hands the report
	-- straight back as the arrange offer, and the grid re-lanes against an extent it
	-- published itself — a 148px minimum with 144px cards measured nine columns /
	-- one row at a 1400px offer, then arranged three columns / two rows at the 608px
	-- it had just reported, and the section it sat in overflowed by exactly the extra
	-- row (200px).
	--
	-- So the report is floored at the extent the chosen lanes need. It never exceeds
	-- the offer (`gridLaneCount` floors `lanes` against exactly this quantity), it is
	-- the extent a `minColumnWidth` author already declared, and it makes measure a
	-- FIXED POINT: offering the reported extent back yields the same lane count, the
	-- same lines and the same cross extent.
	--
	-- Only the offer-derived count needs it. An explicit `columns = N` does not
	-- depend on the offer at all, and natural sizing already reports the lane extent
	-- itself — both reproduce their own report unchanged.
	local laneReport = laneMax
	if node.columns == nil and minLane ~= nil and innerLane ~= math.huge then
		local used = math.min(lanes, #children)
		if used > 0 then
			laneReport = math.max(laneReport, used * (minLane + gap) - gap)
		end
	end
	local value = {
		isCol = isCol,
		lanes = lanes,
		laneSize = laneSize,
		rowGap = rowGap,
		lines = lines,
		cells = cells,
		laneReport = laneReport,
		flowTotal = flowTotal,
	}
	ctx.gridPlan[node.id] = { key = key, value = value }
	return value
end

--[[ ===== A LINE TAKES THE GRID'S OWN FLOW EXTENT (device report 2026-08-16) ==

	*"three of the five demo rows are blank."* `newLevelPicker`'s default `bar`
	segment is a run of tinted `UI.Box` marks in a uniform grid, each declaring
	`fill` on BOTH axes. Every mark solved to `12x0` — the lane's width, and NO
	HEIGHT — inside a grid that had itself been arranged 44px tall, so the whole
	run painted nothing. The glyph and image segments were fine, and that is the
	tell: their marks have content on the flow axis, so the line had something to
	be derived FROM.

	THE MECHANISM. The plan above derives a line's flow extent from its cells'
	CONTENT and from nothing else (`lineFlow = max(uFlow or ownFlow)`), and a
	`fill` cell then takes that line. A line whose every cell fills has no content
	anywhere in it, so the line is zero and every cell in it is zero — while the
	grid's OWN flow extent, the number its parent had already imposed, never
	reached the line at all. Every other container in this library resolves a
	`fill` against its own resolved extent, which is exactly what `resolveAxis`
	means by "fill resolves at arrange"; the grid was the one that resolved it
	against its content. CSS states the same rule for the same shape:
	`align-content: stretch` (the default) stretches auto-sized rows to fill a
	container whose block size is DEFINITE.

	SO THIS IS ARRANGE-ONLY, and that is the load-bearing half. Measure is
	untouched: a `fill` cell still contributes its CONTENT to the grid's report,
	exactly as it does under every other parent, so no reported extent moves and
	no hug parent grows. The spare space this hands out is the space the grid was
	GIVEN over what it ASKED for — which only exists once somebody has imposed an
	extent on it, i.e. at arrange. Nothing here writes to the cached plan, for the
	same reason: measure reads that object.

	EVENLY, ACROSS THE LINES THAT ASKED. A stack splits its leftover by the fill
	children's `weight`; a LINE has no weight to read, because a line is many
	children and their weights are declared against the lane axis. An even split
	with the remainder going to the earliest lines is the only reading that is not
	a guess, and it is exact in the one-line case every run of marks actually is.
	A line with no `fill` cell does not grow at all — the same rule a stack
	applies to a content-sized child sitting beside a `fill` one.

	`docs/lessons/a-fill-of-nothing-is-nothing.md` carries the measurement, the
	HStack it was compared against, and why seventeen mutations of a DECLARATION
	could not reach a defect in the other axis of a rect. ]]
local function gridFlowStretch(deps: Deps, node: any, plan: any, innerFlow: number): { [number]: number }?
	-- an unbounded offer imposes nothing, so there is no spare space to hand out
	-- (this is `axisAbsorbs`'s `limit ~= math.huge` condition, one layer down)
	if innerFlow == math.huge then
		return nil
	end
	local spare = innerFlow - plan.flowTotal
	if spare <= 0 then
		return nil
	end
	local children = node.children or {}
	local flowAxis = if plan.isCol then "w" else "h"
	local asked: { number } = {}
	for index, line in plan.lines do
		for j = line.first, line.last do
			if deps.dim(children[j], flowAxis).type == "fill" then
				table.insert(asked, index)
				break
			end
		end
	end
	if #asked == 0 then
		return nil
	end
	local share = math.floor(spare / #asked)
	local remainder = spare - share * #asked
	local grown: { [number]: number } = {}
	for at, index in asked do
		grown[index] = plan.lines[index].flow + share + (if at <= remainder then 1 else 0)
	end
	return grown
end

--[[ ===== THE ROW GRID (docs/plans/parity-round2.md §2.2) =============

	`UI.Grid` is, and stays, a uniform FLOW grid: children wrap row-major into a
	column count and every column is the same width. Everything above this block
	is that grid, and every existing caller keeps it to the pixel.

	A Grid whose children are all `gridrow` nodes is a different layout with the
	same name — the `Grid`/`GridRow` pair. Each row declares its cells in
	order, and COLUMN n IS AS WIDE AS THE WIDEST NATURAL CELL IN COLUMN n ACROSS
	EVERY ROW. That is the whole difference and it is why row mode needs a second
	pass: the flow grid can size a column from the offer alone, this one cannot
	know column 1's width until it has measured column 1 in every row.

	WHICH MODE IS DECIDED BY THE CHILDREN, NEVER BY A PROP. A grid with no
	`gridrow` child is the flow grid; a grid whose children are all `gridrow` is a
	row grid; a MIX is an authoring error, because there is no reading of "three
	rows and a loose cell" that is not a guess, and a screen laid out by a guess is
	the defect this file exists to prevent. The mix keeps the FLOW reading — the
	one the tree had before `GridRow` existed, so nothing silently reflows — and
	says so in the diagnostics.

	A SPAN CANNOT WIDEN A COLUMN ON ITS OWN. A cell declaring
	`gridSpan = n` is left out of every column maximum and is then fitted to the
	columns it covers plus the gaps between them, so a wide title across three
	columns does not stretch column 1 under every row beneath it.
]]

local function isRowNode(child: any): boolean
	return child.kind == "gridrow"
end

-- "flow" | "row" | "mixed" — read off the children, once per call site.
local function gridMode(node: any): string
	local rows, others = 0, 0
	for _, child in node.children or {} do
		if isRowNode(child) then
			rows += 1
		else
			others += 1
		end
	end
	if rows == 0 then
		return "flow"
	end
	return if others == 0 then "row" else "mixed"
end

local function spanOf(cell: any): number
	local declared = cell.gridSpan
	if type(declared) ~= "number" or declared ~= declared then
		return 1
	end
	return math.max(1, math.floor(declared))
end

-- the width a cell covering `span` columns from column `first` (1-based) gets:
-- the columns themselves PLUS the gaps between them, which is what makes a spanned
-- cell line up with the right edge of its last column instead of falling a gap short
local function spannedWidth(widths: { number }, first: number, span: number, gap: number): number
	local total = 0
	for i = first, math.min(first + span - 1, #widths) do
		total += widths[i]
	end
	return total + gap * (math.min(span, #widths - first + 1) - 1)
end

-- COLUMN WIDTHS, DECIDED ONCE PER GRID PER BOX. Cached on the context and keyed by
-- the box, exactly as the composition resolution is and for the same reason: measure
-- and arrange must not derive different columns for the same grid.
local function gridColumnPlan(deps: Deps, ctx: any, node: any, innerW: number, innerH: number, gap: number): any
	local key = `{innerW}|{innerH}|{gap}`
	local cached = ctx.gridPlan[node.id]
	if cached ~= nil and cached.key == key then
		return cached.value
	end
	local widths: { number } = {}
	local cols = 0
	-- ADAPT-L8: does ANY cell declare a rigid px width? A column whose natural came
	-- from CONTENT reflows honestly when it is narrowed — the audit's cell B-5
	-- measured exactly that and called it RIGHT — so only a declared `fixed` is a
	-- promise the squeeze below can break. Collected in the loop that already
	-- visits every cell, so it costs a comparison and no second walk.
	local anyRigid = false
	for _, row in node.children or {} do
		local column = 1
		for _, cell in row.children or {} do
			local span = spanOf(cell)
			if span == 1 then
				-- horizontal margins only: this is a COLUMN width
				local _, mr, _, ml = deps.sides(cell.margin)
				local w = deps.measure(ctx, cell, innerW, innerH)
				widths[column] = math.max(widths[column] or 0, w + ml + mr)
				if deps.dim(cell, "w").type == "fixed" then
					anyRigid = true
				end
			end
			column += span
		end
		cols = math.max(cols, column - 1)
	end
	-- a column every row spanned over has no natural width of its own; it is a real
	-- column (the cells after it are still in the columns they declared) and it is
	-- zero wide
	for i = 1, cols do
		widths[i] = widths[i] or 0
	end
	-- NATURAL COLUMNS NEVER PAINT OUTSIDE THE BOX THEY WERE GIVEN. The flow grid
	-- cannot overflow — its column width is derived from the offer — and a row grid
	-- whose naturals do not fit would, so the columns are reduced proportionally to
	-- the width actually available. It is the same clamp the flow grid's own
	-- `math.max(0, ...)` makes, one level up: the grid reports and paints a box it
	-- fits inside, and the cells keep their relative widths.
	--
	-- ...AND IT SAYS SO NOW (audit Part 2 cell B-4, 2026-08-21). The
	-- clamp is right; the SILENCE was not. Three cells each declaring
	-- `width = fixed(200)` came out 101px wide at 320 with ZERO findings, while the
	-- `UI.HStack` twin at the same widths files a named finding every time — two
	-- containers in one primitive family with opposite failure modes, and the audit
	-- called the silent one the worse of the two in both directions. A declared
	-- fixed width that is not what gets drawn is exactly the class this library
	-- files findings for.
	--
	-- THE PLAN CARRIES THE NUMBER rather than the arrange branch recomputing it:
	-- this function is the ONE owner measure and arrange both read, so a second
	-- copy of the arithmetic in the reporting path is the drift this file's whole
	-- design exists to make unreachable. Arrange visits the grid once, which is
	-- what makes "report it there" one message per solve.
	local avail = innerW - gap * math.max(0, cols - 1)
	local squeeze: { natural: number, room: number, by: number }? = nil
	if innerW ~= math.huge and cols > 0 then
		local total = 0
		for i = 1, cols do
			total += widths[i]
		end
		if total > avail and total > 0 then
			local scale = math.max(0, avail) / total
			for i = 1, cols do
				widths[i] = math.floor(widths[i] * scale)
			end
			if anyRigid then
				squeeze = { natural = total, room = math.max(0, avail), by = total - math.max(0, avail) }
			end
		end
	end
	local value = { widths = widths, cols = cols, gap = gap, squeeze = squeeze }
	ctx.gridPlan[node.id] = { key = key, value = value }
	return value
end

-- one row's height: its tallest cell measured at the width its columns give it.
-- `fill`-height cells contribute nothing (they take whatever the row turns out to
-- be), exactly as a `fill` cell does in the flow grid.
local function gridRowHeight(deps: Deps, ctx: any, row: any, plan: any, limitH: number): number
	local widths, gap = plan.widths, plan.gap
	local rowH = 0
	local column = 1
	for _, cell in row.children or {} do
		local span = spanOf(cell)
		local cellW = spannedWidth(widths, column, span, gap)
		local mt, _, mb, _ = deps.sides(cell.margin)
		local hDim = deps.dim(cell, "h")
		if hDim.type == "fill" then
			column += span
			continue
		end
		local _, h = deps.measure(ctx, cell, cellW, limitH)
		if hDim.type == "aspect" and cellW > 0 then
			h = roundPx(cellW / (hDim.ratio :: number))
		end
		rowH = math.max(rowH, h + mt + mb)
		column += span
	end
	return rowH
end

-- ===== THE MEASURE HALF ======================================================
-- Both entry points return the CONTENT extent, padding excluded: the solver has
-- already taken it off `innerMaxW`/`innerMaxH` and adds it back to the answer, so
-- the padding arithmetic stays in one place there for every container alike.

-- ONE ROW OF A ROW GRID, measured on its own (§2.2). The grid never asks — it
-- measures the CELLS, because the columns are a fact about every row at once —
-- so this is the answer for a `UI.GridRow` that is not inside a `UI.Grid` at
-- all, which the arrange branch diagnoses. Natural row: cells side by side.
function grid.measureRow(deps: Deps, ctx: any, node: any, innerMaxW: number, innerMaxH: number): (number, number)
	local w, h = 0, 0
	for _, cell in node.children or {} do
		local mt, mr, mb, ml = deps.sides(cell.margin)
		local cw, ch = deps.measure(ctx, cell, innerMaxW, innerMaxH)
		w += cw + ml + mr
		h = math.max(h, ch + mt + mb)
	end
	return w, h
end

function grid.measure(
	deps: Deps,
	ctx: any,
	node: any,
	innerMaxW: number,
	innerMaxH: number,
	gap: number
): (number, number)
	if gridMode(node) == "row" then
		local rows = node.children or {}
		local rowGap = gridRowGap(node)
		local plan = gridColumnPlan(deps, ctx, node, innerMaxW, innerMaxH, gap)
		local totalW = 0
		for i = 1, plan.cols do
			totalW += plan.widths[i]
		end
		totalW += gap * math.max(0, plan.cols - 1)
		local totalH = 0
		for i, row in rows do
			totalH += gridRowHeight(deps, ctx, row, plan, innerMaxH)
			if i < #rows then
				totalH += rowGap
			end
		end
		return totalW, totalH
	end

	-- THE WHOLE MEASURE IS THE PLAN, in both flow directions: it owns the lane
	-- count, the lane extent, the line partition and every cell's two extents, so
	-- there is nothing left here but naming which of its two axes is width and
	-- which is height. `grid.arrange` names them once more, and nowhere else does.
	local plan = gridFlowPlan(deps, ctx, node, innerMaxW, innerMaxH, gap)
	if plan.isCol then
		return plan.flowTotal, plan.laneReport
	end
	return plan.laneReport, plan.flowTotal
end

-- ===== THE ARRANGE HALF ======================================================

function grid.arrangeRow(
	deps: Deps,
	ctx: any,
	node: any,
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	place: Place,
	alignOffset: AlignOffset,
	out: { [string]: any }
)
	-- the plan its grid handed down, one line before it arranged this row
	local plan = ctx.gridRowPlan[node.id]
	if plan == nil then
		-- A `UI.GridRow` OUTSIDE A `UI.Grid` HAS NO COLUMNS TO SIT IN, and there
		-- is no honest default: the columns are a fact about the grid's OTHER
		-- rows, which do not exist here. It lays its cells out side by side —
		-- what the measure branch above reported, so the box is the box — and
		-- says what to do about it.
		if ctx.hiddenDepth == 0 then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = "UI.GridRow outside a UI.Grid — its cells have no columns to line up in, so they "
					.. "are laid side by side. Put the row inside a UI.Grid (that is the node that "
					.. "derives the columns from every row), or use a UI.HStack if a plain row is what "
					.. "you meant",
			})
		end
		local x = innerX
		for _, cell in node.children or {} do
			local mt, mr, mb, ml = deps.sides(cell.margin)
			local w, h = deps.measure(ctx, cell, innerW, innerH)
			place(ctx, cell, { x = x + ml, y = innerY + mt, w = w, h = h }, out)
			x += w + ml + mr
			local _ = mb
		end
		return
	end
	local widths, colGap = plan.widths, plan.gap
	local x = innerX
	local column = 1
	for _, cell in node.children or {} do
		local span = spanOf(cell)
		local slotW = spannedWidth(widths, column, span, colGap)
		local mt, mr, mb, ml = deps.sides(cell.margin)
		local availW = math.max(0, slotW - ml - mr)
		local availH = math.max(0, innerH - mt - mb)
		local w, h = deps.measure(ctx, cell, availW, availH)
		-- the same cell rules the flow grid uses: a `fill` axis takes its slot,
		-- anything else keeps its content size and ALIGNS inside it
		local cellW = if deps.dim(cell, "w").type == "fill" then availW else math.min(w, availW)
		local cellH = if deps.dim(cell, "h").type == "fill" then availH else math.min(h, availH)
		local hDimCell = deps.dim(cell, "h")
		if hDimCell.type == "aspect" and cellW > 0 then
			cellH = math.min(availH, roundPx(cellW / (hDimCell.ratio :: number)))
		end
		place(ctx, cell, {
			x = x + ml + alignOffset(cell.alignH, availW, cellW),
			y = innerY + mt + alignOffset(cell.alignV, availH, cellH),
			w = cellW,
			h = cellH,
		}, out)
		x += slotW + colGap
		column += span
	end
end

function grid.arrange(
	deps: Deps,
	ctx: any,
	node: any,
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	gap: number,
	place: Place,
	alignOffset: AlignOffset,
	out: { [string]: any }
)
	local mode = gridMode(node)
	if mode == "mixed" and ctx.hiddenDepth == 0 then
		-- A MIX IS AN AUTHORING ERROR, NOT A LAYOUT (§2.2). Reported once per
		-- solve — arrange visits this node exactly once — and the grid keeps the
		-- FLOW reading it had before `GridRow` existed, so a tree that acquires a
		-- stray row does not silently reflow while the author reads the message.
		table.insert(ctx.diagnostics, {
			node = node.id,
			issue = "a UI.Grid's children are a MIX of UI.GridRow rows and loose cells — there is no "
				.. "reading of that which is not a guess, so this grid stays the row-major flow grid "
				.. "it was. Make every child a UI.GridRow (row mode: column n is the widest cell in "
				.. "column n across all rows), or none of them (flow mode: one shared column width)",
		})
	end
	if mode == "row" then
		if gridIsColumn(node) and ctx.hiddenDepth == 0 then
			-- A ROW GRID HAS NO FLOW TO CHOOSE, and `flow = "column"` has no
			-- reading here that is not a guess: `UI.GridRow` declares its cells in a
			-- row, and column n is a fact about EVERY row at once. Turning that a
			-- quarter turn would have to decide whether a row becomes a column or
			-- stays a row and gets re-read, which is two layouts under one word.
			-- Same rule and same shape as the mixed-children diagnostic above: the
			-- prop is reported rather than accepted-and-ignored (constitution §4),
			-- and the row grid stays exactly what it is.
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = 'flow = "column" is refused on a ROW grid (its children are UI.GridRow rows) and this '
					.. "grid stays row-major. Column-major wrapping is a property of the FLOW grid, where a "
					.. "line is just the next `columns` cells; a row grid's columns are derived from every "
					.. "row at once and have no transposed reading. Drop the rows, or drop the flow",
			})
		end
		local rows = node.children or {}
		local rowGap = gridRowGap(node)
		local plan = gridColumnPlan(deps, ctx, node, innerW, innerH, gap)
		-- ADAPT-L8: the columns gave, and a declared width that is not what gets
		-- drawn is not something to find out from a screenshot. The number comes
		-- off the plan (see `gridColumnPlan`), so there is no second arithmetic
		-- here to drift from the one that did the squeezing.
		if plan.squeeze ~= nil and ctx.hiddenDepth == 0 then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"this row grid squeezed its columns by %dpx to fit: their natural widths total %dpx "
						.. "against %dpx of room, so a cell that declared a fixed width is NOT drawn at it "
						.. "(give the grid room, wrap it in a ScrollView, or declare fewer columns)",
					plan.squeeze.by,
					plan.squeeze.natural,
					plan.squeeze.room
				),
			})
		end
		local y = innerY
		for _, row in rows do
			local rowH = gridRowHeight(deps, ctx, row, plan, innerH)
			-- THE ROW IS HANDED THE COLUMNS, it does not re-derive them. Its own
			-- cells cannot see the other rows, and a row that guessed its columns
			-- from its own cells is precisely the measure-versus-arrange
			-- disagreement this library keeps fixing.
			ctx.gridRowPlan[row.id] = plan
			place(ctx, row, { x = innerX, y = y, w = innerW, h = rowH }, out)
			y += rowH + rowGap
		end
		return
	end
	--[[ THE FLOW GRID PLACES WHAT THE PLAN ALREADY DECIDED. Every extent here
		came out of `gridFlowPlan`, which measure also called and which the ctx
		cached against this exact box — so the two passes cannot disagree about the
		lanes, the lines or a single cell. This branch's only remaining job is the
		second and last binding of LANE/FLOW to x/y: under `flow = "row"` the lane
		runs across x and the lines advance down y, under `flow = "column"` both
		turn a quarter turn. `alignH`/`alignV` turn with them, because a cell
		aligns inside its LANE on one axis and inside its LINE on the other, and
		which of those is horizontal is the mode's whole content. ]]
	local children = node.children or {}
	local plan = gridFlowPlan(deps, ctx, node, innerW, innerH, gap)
	local isCol, laneSize = plan.isCol, plan.laneSize
	-- the spare flow extent this grid was GIVEN over what it asked for, handed to
	-- the lines whose cells said `fill` (see gridFlowStretch): arrange-only, and
	-- nil whenever there is nothing spare or nobody asked
	local grown = gridFlowStretch(deps, node, plan, if isCol then innerW else innerH)
	local flowCursor = if isCol then innerX else innerY
	for index, line in plan.lines do
		local lineFlow = if grown ~= nil then grown[index] or line.flow else line.flow
		for j = line.first, line.last do
			local child = children[j]
			local cell = plan.cells[j]
			-- a `fill` cell IS its line, at whatever the line ended up being; every
			-- other cell keeps the extent the plan measured and ALIGNS inside it
			local cellFlow = if lineFlow ~= line.flow
					and deps.dim(child, if isCol then "w" else "h").type == "fill"
				then lineFlow
				else cell.flow
			local laneAlign = if isCol then child.alignV else child.alignH
			local flowAlign = if isCol then child.alignH else child.alignV
			local lanePos = (j - line.first) * (laneSize + gap) + alignOffset(laneAlign, laneSize, cell.lane)
			local flowPos = flowCursor + alignOffset(flowAlign, lineFlow, cellFlow)
			place(ctx, child, {
				x = if isCol then flowPos else innerX + lanePos,
				y = if isCol then innerY + lanePos else flowPos,
				w = if isCol then cellFlow else cell.lane,
				h = if isCol then cell.lane else cellFlow,
			}, out)
		end
		flowCursor += lineFlow + plan.rowGap
	end
end

return grid
