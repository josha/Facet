--!strict
--[[
	A GRID MUST MEASURE THE LAYOUT IT ARRANGES (reproduced 2026-08-08).

	The report: a `UI.Grid` of content Buttons inside a content-sized VStack made
	`controller.diagnostics()` say "content overflows this vstack by 200px". The
	grid told its parent it needed 184px of height and then painted 384px.

	THE MECHANISM IS A FIXED POINT THE MEASURE DID NOT HAVE. A grid's column count
	is derived from the width it is OFFERED (`minColumnWidth`), its column width is
	that offer divided by the count, and its cell heights follow the column width.
	Its measured WIDTH, though, is the width its CELLS occupy — which is narrower
	than the offer. A hug parent hands that narrower number straight back as the
	arrange offer, so the grid re-columns against a width it reported itself:

	  measure(1400) -> 9 columns, 4 cells in one row, reports 608 x 184
	  arrange( 608) -> 3 columns, two rows                        384   -> +200px

	Two distinct ways the reported width failed to reproduce itself, both fixed:

	  · a partial last row added a TRAILING gap the arrange never paints, so the
	    report was one gap wider than the paint (the `aspect` cell case: the extra
	    8px widened the column by 2px and every cell grew 2px taller — the "2px"
	    half of the same report);
	  · a `uniform` grid reports its CELL widths, which can be narrower than the
	    `minColumnWidth` the column count was derived from — so re-offering the
	    report dropped a column and added a whole row (the 200px half).

	The claim under test is one sentence: THE SIZE A GRID REPORTS IS A SIZE AT
	WHICH IT REPRODUCES THAT REPORT. Everything below is that sentence at a
	different offer, plus a frozen table proving the fill-parented grids that every
	example and control actually ships did not move.
]]

local fs = require("@lune/fs")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local function render(screen: any, w: number?, h: number?): (any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 1400, h = h or 900 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

local function rectOf(adapter: any, path: string): any
	local node = adapter.node(path)
	return if node ~= nil then node.rect else nil
end

local function issues(controller: any): string
	local parts = {}
	for _, d in controller.diagnostics() do
		table.insert(parts, `{d.node}: {d.issue}`)
	end
	return table.concat(parts, " | ")
end

-- the reported case: a card = a Button WITH CHILDREN, i.e. layout kind "hstack",
-- whose height comes from stacked content rather than from a label metric
local function card(i: number, thumb: any): any
	return UI.Button({
		id = "b" .. i,
		label = "Item " .. i,
		children = {
			UI.VStack({
				id = "Col",
				gap = "xs",
				align = "stretch",
				children = {
					thumb,
					UI.Text({ id = "Name", text = "Item name " .. i, textSize = "label", lineLimit = 1 }),
					UI.Text({ id = "Cap", text = "Creator", textSize = "caption", role = "secondary" }),
				},
			}),
		},
	})
end

local FIXED_THUMB = function()
	return UI.Box({
		id = "Th",
		width = { type = "fixed", px = 120 },
		height = { type = "fixed", px = 120 },
		surface = "raised",
	})
end
local ASPECT_THUMB = function()
	return UI.Box({
		id = "Th",
		width = { type = "fill" },
		height = { type = "aspect", ratio = 1 },
		surface = "raised",
	})
end

-- the reported screen: a CONTENT-SIZED section stack (no width declared on the
-- VStack, so it hugs its widest child) with a heading above the grid
local function section(itemSizing: string, thumb: () -> any): any
	return UI.Screen({
		id = "G2",
		children = {
			UI.VStack({
				id = "Sec",
				gap = "s",
				children = {
					UI.Text({ id = "H", text = "Header", textSize = "heading" }),
					UI.Grid({
						id = "Grid",
						minColumnWidth = 148,
						itemSizing = itemSizing :: any,
						gap = "s",
						rowGap = "m",
						children = { card(1, thumb()), card(2, thumb()), card(3, thumb()), card(4, thumb()) },
					}),
				},
			}),
		},
	})
end

-- the grid's own box must cover every cell it arranged: the bottom of the last
-- row, and the right edge of the widest one. This is the measure/arrange
-- agreement stated in rects rather than in the diagnostic that reports it.
local function assertCoversItsCells(adapter: any, gridPath: string, ids: { string })
	local grid = rectOf(adapter, gridPath)
	expect(grid).never().toBe(nil)
	local bottom, right = grid.y, grid.x
	for _, id in ids do
		local cell = rectOf(adapter, gridPath .. "/" .. id)
		expect(cell).never().toBe(nil)
		bottom = math.max(bottom, cell.y + cell.h)
		right = math.max(right, cell.x + cell.w)
	end
	expect(grid.y + grid.h >= bottom).toBe(true)
	expect(grid.x + grid.w >= right).toBe(true)
end

describe("grid measure/arrange agreement", function()
	it("a grid of content buttons in a hug stack reports no overflow (fixed thumb)", function()
		local adapter, controller = render(section("uniform", FIXED_THUMB))
		expect(issues(controller)).toBe("")
		assertCoversItsCells(adapter, "/G2/Sec/Grid", { "b1", "b2", "b3", "b4" })
	end)

	it("...and with an aspect cell, whose height follows the column width", function()
		local adapter, controller = render(section("uniform", ASPECT_THUMB))
		expect(issues(controller)).toBe("")
		assertCoversItsCells(adapter, "/G2/Sec/Grid", { "b1", "b2", "b3", "b4" })
	end)

	it("...and under natural item sizing, both cell shapes", function()
		local adapterA, controllerA = render(section("natural", FIXED_THUMB))
		expect(issues(controllerA)).toBe("")
		assertCoversItsCells(adapterA, "/G2/Sec/Grid", { "b1", "b2", "b3", "b4" })
		local adapterB, controllerB = render(section("natural", ASPECT_THUMB))
		expect(issues(controllerB)).toBe("")
		assertCoversItsCells(adapterB, "/G2/Sec/Grid", { "b1", "b2", "b3", "b4" })
	end)

	it("the hug stack is as tall as the grid it holds", function()
		local adapter = render(section("uniform", FIXED_THUMB))
		local sec = rectOf(adapter, "/G2/Sec")
		local grid = rectOf(adapter, "/G2/Sec/Grid")
		local head = rectOf(adapter, "/G2/Sec/H")
		-- the section's box must reach the grid's bottom edge; before the fix the
		-- grid painted 200px past it
		expect(sec.y + sec.h >= grid.y + grid.h).toBe(true)
		expect(grid.y >= head.y + head.h).toBe(true)
	end)

	it("one row of four cells stays one row of four cells", function()
		local adapter = render(section("uniform", FIXED_THUMB))
		local ys = {}
		for i = 1, 4 do
			ys[i] = rectOf(adapter, "/G2/Sec/Grid/b" .. i).y
		end
		-- the offer (1400px) fits nine 148px columns; four cards are one row, and
		-- the grid must not re-column itself into two rows against its own report
		expect(ys[2]).toBe(ys[1])
		expect(ys[3]).toBe(ys[1])
		expect(ys[4]).toBe(ys[1])
	end)

	-- EXISTING BEHAVIOUR, FROZEN. An explicit `columns = N` does not derive its
	-- count from the offer, so nothing here may move: these six rects were taken
	-- from the solver BEFORE the fix and are asserted byte-for-byte after it.
	-- Mixed plain content on purpose — two fixed boxes, two texts, one `fill` cell,
	-- and a PARTIAL last row, which is the shape the trailing-gap half touches.
	it("a grid of plain boxes and texts keeps byte-identical rects", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					columns = 3,
					gap = "s",
					rowGap = "m",
					children = {
						UI.Box({ id = "x1", width = { type = "fixed", px = 40 }, height = { type = "fixed", px = 30 } }),
						UI.Box({ id = "x2", width = { type = "fixed", px = 60 }, height = { type = "fixed", px = 20 } }),
						UI.Text({ id = "x3", text = "Three" }),
						UI.Text({ id = "x4", text = "Four" }),
						UI.Box({ id = "x5", width = { type = "fill" }, height = { type = "fixed", px = 12 } }),
					},
				}),
			},
		})
		local adapter = render(screen, 400, 600)
		local frozen: { [string]: { number } } = {
			["/S/G"] = { 0, 0, 400, 66 },
			["/S/G/x1"] = { 0, 0, 40, 30 },
			["/S/G/x2"] = { 136, 0, 60, 20 },
			["/S/G/x3"] = { 272, 0, 50, 20 },
			["/S/G/x4"] = { 0, 46, 40, 20 },
			["/S/G/x5"] = { 136, 46, 128, 12 },
		}
		for path, want in frozen do
			local r = rectOf(adapter, path)
			expect(r).never().toBe(nil)
			expect(`{r.x},{r.y},{r.w},{r.h}`).toBe(`{want[1]},{want[2]},{want[3]},{want[4]}`)
		end
	end)

	-- THE SIMPLEST SHAPE THAT WAS BROKEN, with no Buttons and no aspect anywhere:
	-- three short labels, `minColumnWidth = 120`, `uniform`. Before the fix this
	-- grid measured 166px wide (three 50px labels and their gaps) and one row 20px
	-- tall, then arranged at 166px — where 120px columns leave room for ONE — and
	-- stacked the three labels vertically at y = 0, 28, 56, running 56px out of a
	-- box it had told its parent was 20px tall. The pins below are the fixed point.
	it("a uniform minColumnWidth grid stays in the columns it measured", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					minColumnWidth = 120,
					itemSizing = "uniform",
					gap = "s",
					children = {
						UI.Text({ id = "c1", text = "One" }),
						UI.Text({ id = "c2", text = "Two" }),
						UI.Text({ id = "c3", text = "Three" }),
					},
				}),
			},
		})
		local adapter = render(screen, 400, 600)
		-- 376 = three 120px columns and two 8px gaps: the width the author's own
		-- minimum asks for, and the width at which this grid re-derives 3 columns
		local frozen: { [string]: { number } } = {
			["/S/G"] = { 0, 0, 376, 20 },
			["/S/G/c1"] = { 0, 0, 50, 20 },
			["/S/G/c2"] = { 128, 0, 50, 20 },
			["/S/G/c3"] = { 256, 0, 50, 20 },
		}
		for path, want in frozen do
			local r = rectOf(adapter, path)
			expect(r).never().toBe(nil)
			expect(`{r.x},{r.y},{r.w},{r.h}`).toBe(`{want[1]},{want[2]},{want[3]},{want[4]}`)
		end
		assertCoversItsCells(adapter, "/S/G", { "c1", "c2", "c3" })
	end)
end)

--[[ THE SAME SENTENCE FOR COLUMN-MAJOR WRAPPING (`flow = "column"`, 2026-08-15).

	The fixed point is not inherited for free by a new mode. It is the property that
	broke twice above, both times because the extent a grid REPORTS on its lane axis
	is not the extent it was OFFERED — and under column flow the lane axis is the
	HEIGHT, so every one of those failures has a transposed twin that no row-flow
	test can see. The mode is a mode of the one arithmetic (`gridFlowPlan`), which is
	the reason to expect it holds; that is exactly why it is asserted rather than
	assumed.

	Stated directly this time: MEASURE IT, ARRANGE IT, MEASURE AGAIN. Render once and
	read the box the grid chose for itself, then render the identical tree with that
	box nailed on as a literal — the offer the grid published — and require every
	cell to land on the same pixel. A grid whose report cannot survive being handed
	back is the 200px overflow at the top of this file. ]]

local function reoffer(build: (box: any?) -> any, ids: { string }, gridPath: string)
	-- pass 1: the grid sizes itself inside the viewport and reports a box
	local first = render(build(nil), 1400, 900)
	local reported = rectOf(first, gridPath)
	expect(reported).never().toBe(nil)
	-- pass 2: that box, offered back as a literal
	local second =
		render(build({ w = { type = "fixed", px = reported.w }, h = { type = "fixed", px = reported.h } }), 1400, 900)
	local again = rectOf(second, gridPath)
	expect(`{again.w}x{again.h}`).toBe(`{reported.w}x{reported.h}`)
	for _, id in ids do
		local a = rectOf(first, gridPath .. "/" .. id)
		local b = rectOf(second, gridPath .. "/" .. id)
		expect(a).never().toBe(nil)
		expect(b).never().toBe(nil)
		-- relative to the grid's own origin: pass 2 may sit elsewhere on screen
		expect(`{id} {b.x - again.x},{b.y - again.y},{b.w},{b.h}`).toBe(
			`{id} {a.x - reported.x},{a.y - reported.y},{a.w},{a.h}`
		)
	end
end

local function tiles(): { any }
	local out = {}
	for i = 1, 7 do
		table.insert(
			out,
			UI.Box({
				id = "t" .. i,
				width = { type = "fixed", px = 30 + i * 9 },
				height = { type = "fixed", px = 70 - i * 5 },
			})
		)
	end
	return out
end

local function reofferable(flow: string?, itemSizing: string, lane: any): (box: any?) -> any
	return function(box: any?)
		local grid: any = {
			id = "G",
			itemSizing = itemSizing :: any,
			gap = 9,
			rowGap = 13,
			children = tiles(),
		}
		if flow ~= nil then
			grid.flow = flow
		end
		for k, v in lane do
			grid[k] = v
		end
		if box ~= nil then
			grid.width = box.w
			grid.height = box.h
		end
		-- a HUG stack, so pass 1's grid is measured against the viewport and then
		-- arranged inside whatever it reported — the substitution that broke twice
		return UI.Screen({ id = "S", children = { UI.VStack({ id = "Sec", children = { UI.Grid(grid) } }) } })
	end
end

local TILE_IDS = { "t1", "t2", "t3", "t4", "t5", "t6", "t7" }

describe("grid measure/arrange agreement — column flow", function()
	it("a column-flow grid reproduces its own reported box (explicit lanes)", function()
		reoffer(reofferable("column", "natural", { columns = 3 }), TILE_IDS, "/S/Sec/G")
	end)

	it("...with uniform cells, where the report is the CELL and not the lane", function()
		reoffer(reofferable("column", "uniform", { columns = 3 }), TILE_IDS, "/S/Sec/G")
	end)

	-- the offer-derived lane count is the half that actually broke: the count comes
	-- from the offer, the report comes from the cells, and re-offering the report has
	-- to yield the same count. Under column flow the offer in question is the HEIGHT.
	it("...and with the lane count derived from minColumnWidth against the HEIGHT", function()
		reoffer(reofferable("column", "uniform", { minColumnWidth = 90 }), TILE_IDS, "/S/Sec/G")
	end)

	it("...and the row-flow control does the same, on the same corpus", function()
		reoffer(reofferable(nil, "natural", { columns = 3 }), TILE_IDS, "/S/Sec/G")
		reoffer(reofferable(nil, "uniform", { columns = 3 }), TILE_IDS, "/S/Sec/G")
		reoffer(reofferable(nil, "uniform", { minColumnWidth = 90 }), TILE_IDS, "/S/Sec/G")
	end)

	-- and the diagnostic surface, which is how the original defect was REPORTED
	-- rather than how it was found: a grid that paints outside the box it measured
	-- makes its parent complain, in either flow direction
	it("neither flow direction files an overflow on a hug parent", function()
		local _, colController = render(reofferable("column", "uniform", { minColumnWidth = 90 })(nil), 1400, 900)
		expect(issues(colController)).toBe("")
		local _, rowController = render(reofferable(nil, "uniform", { minColumnWidth = 90 })(nil), 1400, 900)
		expect(issues(rowController)).toBe("")
	end)
end)

--[[ ===== ONE OWNER, NOT ONE CACHE (the 200k split, 2026-08-15) ===============

	Everything above is BEHAVIOURAL and it is the real proof; this block guards the
	structural property those cases rest on, because the grid's arithmetic left
	`src/layout/solver.luau` for `src/layout/grid.luau` when the solver came within
	5,778 characters of the `Script.Source` write cap (tools/check_source_size.py).

	WHY A STRUCTURAL PIN IS THE RIGHT INSTRUMENT HERE, and what it is NOT for. The
	fixed point above holds because measure and arrange call the SAME function —
	not because a cache makes them agree. That was measured: clearing
	`ctx.gridPlan` before arrange reddens nothing at all, so the cache is
	determinism and cost, and the single OWNER is the guarantee. A behavioural case
	therefore cannot see the failure this pin exists for — two copies that agree
	today pass every case above and drift on the next edit, which is exactly how
	this library's four "measured one shape, arranged another" defects happened.

	It is DIRECTIONAL: re-inlining either plan into the solver, or adding a second
	definition anywhere, reddens it.
]]
describe("the grid's plan has ONE owner, and both passes read it", function()
	local gridSource = fs.readFile("src/layout/grid.luau")
	local solverSource = fs.readFile("src/layout/solver.luau")

	local function count(haystack: string, needle: string): number
		local n = 0
		local from = 1
		while true do
			local at = string.find(haystack, needle, from, true)
			if at == nil then
				break
			end
			n += 1
			from = (at :: number) + 1
		end
		return n
	end

	it("each plan is defined exactly once, and in `src/layout/grid.luau`", function()
		for _, plan in { "gridFlowPlan", "gridColumnPlan" } do
			expect(`{plan} defined in grid.luau: {count(gridSource, `local function {plan}(`)}`).toBe(
				`{plan} defined in grid.luau: 1`
			)
			expect(`{plan} defined in solver.luau: {count(solverSource, `local function {plan}(`)}`).toBe(
				`{plan} defined in solver.luau: 0`
			)
		end
	end)

	it("the solver keeps no grid arithmetic of its own — it only holds the cache's home", function()
		-- `ctx.gridPlan` / `ctx.gridRowPlan` are declared on the solver's Ctx type and
		-- initialised by `solve`, which is what scopes them to one solve; every READ
		-- and every WRITE is in the module that owns the plan.
		expect(
			`solver indexes the plan caches: {count(solverSource, "ctx.gridPlan[") + count(
				solverSource,
				"ctx.gridRowPlan["
			)}`
		).toBe("solver indexes the plan caches: 0")
		expect(
			`grid indexes the plan caches: {count(gridSource, "ctx.gridPlan[") > 0 and count(
				gridSource,
				"ctx.gridRowPlan["
			) > 0}`
		).toBe("grid indexes the plan caches: true")
	end)

	it("`grid.measure` and `grid.arrange` both call the SAME flow plan", function()
		-- split the module at its two public entry points and look inside each half,
		-- so the case says "both passes go through the owner" rather than counting
		-- call sites and hoping they are the two that matter
		local measureAt = string.find(gridSource, "function grid.measure(", 1, true)
		local arrangeAt = string.find(gridSource, "function grid.arrange(", 1, true)
		expect(`both entry points found: {measureAt ~= nil and arrangeAt ~= nil}`).toBe("both entry points found: true")
		local measureBody = string.sub(gridSource, measureAt :: number, arrangeAt :: number)
		local arrangeBody = string.sub(gridSource, arrangeAt :: number)
		expect(`measure calls gridFlowPlan: {string.find(measureBody, "gridFlowPlan(", 1, true) ~= nil}`).toBe(
			"measure calls gridFlowPlan: true"
		)
		expect(`arrange calls gridFlowPlan: {string.find(arrangeBody, "gridFlowPlan(", 1, true) ~= nil}`).toBe(
			"arrange calls gridFlowPlan: true"
		)
		-- ...and the row grid's columns, the other plan, on the same rule
		expect(`measure calls gridColumnPlan: {string.find(measureBody, "gridColumnPlan(", 1, true) ~= nil}`).toBe(
			"measure calls gridColumnPlan: true"
		)
		expect(`arrange calls gridColumnPlan: {string.find(arrangeBody, "gridColumnPlan(", 1, true) ~= nil}`).toBe(
			"arrange calls gridColumnPlan: true"
		)
	end)

	it("the grid module holds no state: no mutable module-level local at all", function()
		-- the test that decided this seam (tools/check_source_size.py): does the block
		-- read or WRITE a mutable upvalue of the file it is leaving? The grid wrote
		-- none, and it must not acquire one here — a module-level `local` assigned
		-- later is both shared state across solves and the nil-global trap
		-- (docs/lessons/later-locals-are-not-upvalues.md).
		local declared: { [string]: boolean } = {}
		local written: { string } = {}
		for line in string.gmatch(gridSource, "[^\n]+") do
			local name = string.match(line, "^local ([A-Za-z_][A-Za-z0-9_]*)")
				or string.match(line, "^local function ([A-Za-z_][A-Za-z0-9_]*)")
			if name ~= nil then
				declared[name] = true
			end
			local assigned = string.match(line, "^([A-Za-z_][A-Za-z0-9_]*)%s*=[^=]")
			if assigned ~= nil and declared[assigned] then
				table.insert(written, assigned)
			end
		end
		expect(`mutable module locals in grid.luau: {table.concat(written, ", ")}`).toBe(
			"mutable module locals in grid.luau: "
		)
	end)
end)

return true
