--!strict
--[[
	COLUMN-MAJOR WRAPPING IS A MODE OF THE ONE GRID ARITHMETIC (2026-08-15).

	`UI.Grid` wrapped row-major only, and that was the blocker `newVirtualGrid`
	named in its `axis = "x"` refusal: the lazy grid's whole design is that the
	mounted band IS a real `UI.Grid`, so the lane formula EXECUTES rather than
	being copied into the control. Without a column-major mode there was nothing
	for a sideways grid's band to be, and hand-rolling one would have been the second
	column arithmetic the design exists to avoid.

	`flow = "column"` is that mode. The solver's flow grid is written once, in
	LANE/FLOW terms — the lane axis is the one the `columns` lanes divide, the flow
	axis is the one the lines advance along — and those two words are bound to
	width/height in exactly two places. So the claim under test is not "column-major
	produces plausible rects", it is stronger and it is checkable:

	  A COLUMN-FLOW GRID IS THE TRANSPOSE OF THE ROW-FLOW GRID IT MIRRORS.

	Transpose the box, transpose every child's declaration, and every rect comes
	back with x and y swapped and w and h swapped — exactly, to the pixel. A second
	arithmetic cannot pass that test by accident; the same one read the other way
	cannot fail it. `tests/grid_measure_arrange.spec.luau` carries the other half,
	the fixed point, for both modes.
]]

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
	env:set("viewportRect", { x = 0, y = 0, w = w or 600, h = h or 600 })
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

local function rectStr(adapter: any, path: string): string
	local r = rectOf(adapter, path)
	if r == nil then
		return "<missing " .. path .. ">"
	end
	return `{r.x},{r.y},{r.w},{r.h}`
end

local function issues(controller: any): string
	local parts = {}
	for _, d in controller.diagnostics() do
		table.insert(parts, `{d.node}: {d.issue}`)
	end
	return table.concat(parts, " | ")
end

local FIXED = function(px: number)
	return { type = "fixed", px = px }
end
local FILL = { type = "fill" }
local SQUARE = { type = "aspect", ratio = 1 }

--[[ THE TRANSPOSE PAIR. Every child is declared once and emitted twice — once as
	itself and once with its two axes exchanged — so the two trees differ in
	nothing but the axis names. A `fill` becomes a `fill` on the other axis; a
	SQUARE aspect is its own transpose (ratio 1 = 1/1), which is why the aspect
	case can be in this pair at all: a 16:9 cell transposes to 9:16 and would be
	testing the ratio algebra rather than the flow. ]]
local SPECIMENS: { { id: string, w: any, h: any } } = {
	{ id = "a", w = FIXED(40), h = FIXED(30) },
	{ id = "b", w = FIXED(90), h = FIXED(20) },
	{ id = "c", w = FIXED(60), h = FIXED(55) },
	{ id = "d", w = FILL, h = FIXED(18) },
	{ id = "e", w = FILL, h = SQUARE },
	{ id = "f", w = FIXED(24), h = FIXED(24) },
	{ id = "g", w = FIXED(70), h = FIXED(12) },
}

local function cells(transposed: boolean): { any }
	local out = {}
	for _, s in SPECIMENS do
		table.insert(
			out,
			UI.Box({
				id = s.id,
				width = if transposed then s.h else s.w,
				height = if transposed then s.w else s.h,
			})
		)
	end
	return out
end

local function gridScreen(flow: string?, boxW: number, boxH: number, extra: any?): any
	local props: any = {
		id = "G",
		columns = 3,
		gap = 8,
		rowGap = 12,
		width = FIXED(boxW),
		height = FIXED(boxH),
		children = cells(flow == "column"),
	}
	if flow ~= nil then
		props.flow = flow
	end
	for k, v in extra or {} do
		props[k] = v
	end
	return UI.Screen({ id = "S", children = { UI.Grid(props) } })
end

describe("UI.Grid column flow — the transpose of the one arithmetic", function()
	it("every cell's rect is the row-flow rect with both axes exchanged", function()
		local rowAdapter = render(gridScreen(nil, 400, 300), 600, 600)
		local colAdapter = render(gridScreen("column", 300, 400), 600, 600)
		for _, s in SPECIMENS do
			local r = rectOf(rowAdapter, "/S/G/" .. s.id)
			local c = rectOf(colAdapter, "/S/G/" .. s.id)
			expect(r).never().toBe(nil)
			expect(c).never().toBe(nil)
			-- x<->y, w<->h. Stated as one string so a failure prints both rects.
			expect(`{s.id} {c.x},{c.y},{c.w},{c.h}`).toBe(`{s.id} {r.y},{r.x},{r.h},{r.w}`)
		end
	end)

	it("...and neither mode files a diagnostic the other does not", function()
		local _, rowController = render(gridScreen(nil, 400, 300), 600, 600)
		local _, colController = render(gridScreen("column", 300, 400), 600, 600)
		expect(issues(colController)).toBe(issues(rowController))
	end)

	--[[ THE EXPLICIT GEOMETRY, so a transpose that is self-consistently WRONG in
		both modes cannot pass the pair above. Three lanes down a 400px height with
		an 8px gap: laneSize = floor((400 - 16) / 3) = 128. Lines advance RIGHTWARD
		by the widest cell in the line plus the 12px rowGap. ]]
	it("lanes run DOWN and lines advance RIGHTWARD, at frozen offsets", function()
		local adapter = render(gridScreen("column", 300, 400), 600, 600)
		-- line 1 = a, b, c at y = 0, 136, 272 and x = 0
		expect(rectStr(adapter, "/S/G/a")).toBe("0,0,30,40")
		expect(rectStr(adapter, "/S/G/b")).toBe("0,136,20,90")
		expect(rectStr(adapter, "/S/G/c")).toBe("0,272,55,60")
		-- line 1's flow extent is its widest cell (c, 55) -> line 2 starts at 67
		expect(rectStr(adapter, "/S/G/d")).toBe("67,0,18,128")
		expect(rectStr(adapter, "/S/G/e")).toBe("67,136,128,128")
		expect(rectStr(adapter, "/S/G/f")).toBe("67,272,24,24")
		-- line 2's flow extent is 128 (d and e both fill/aspect to the lane) -> 207
		expect(rectStr(adapter, "/S/G/g")).toBe("207,0,12,70")
	end)

	it("a `fill` cell takes its LANE, which under column flow is its height", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					flow = "column",
					columns = 2,
					gap = 10,
					width = FIXED(200),
					height = FIXED(210),
					children = {
						UI.Box({ id = "p", width = FIXED(30), height = FILL }),
						UI.Box({ id = "q", width = FIXED(30), height = FIXED(12) }),
					},
				}),
			},
		})
		local adapter = render(screen, 600, 600)
		-- two lanes down 210px with a 10px gap: laneSize = floor((210 - 10) / 2) = 100
		expect(rectStr(adapter, "/S/G/p")).toBe("0,0,30,100")
		expect(rectStr(adapter, "/S/G/q")).toBe("0,110,30,12")
	end)

	--[[ `minColumnWidth` DERIVES THE LANE COUNT FROM THE LANE AXIS, and under column
		flow that axis is the HEIGHT. The name keeps saying "width" because the grid
		has one lane-minimum prop, not two — but the number it is compared against is
		the one the mode chose, which is the whole point of writing the arithmetic in
		lane terms. ]]
	it("minColumnWidth counts lanes down the height under column flow", function()
		local children = {}
		for i = 1, 6 do
			table.insert(children, UI.Box({ id = "m" .. i, width = FIXED(20), height = FIXED(20) }))
		end
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					flow = "column",
					minColumnWidth = 60,
					gap = 0,
					rowGap = 0,
					width = FIXED(400),
					height = FIXED(200),
					children = children,
				}),
			},
		})
		local adapter = render(screen, 600, 600)
		-- 200 / 60 = 3 lanes, so six cells are two lines of three
		expect(rectStr(adapter, "/S/G/m1")).toBe("0,0,20,20")
		expect(rectStr(adapter, "/S/G/m3")).toBe("0,132,20,20")
		expect(rectStr(adapter, "/S/G/m4")).toBe("20,0,20,20")
	end)

	--[[ ADAPT-23 — THE SOLVER TAKES THE SAME CAP THE PREDICTOR DOES.

		`adaptive.columnsFor` is documented as "the SAME arithmetic the solver's Grid
		uses", and it was a second copy of it: the helper now caps the count at three
		metres and the solver would have kept answering eleven, which is a worse
		defect than the one being fixed — a predictor that lies about the grid beside
		it. `gridLaneCount` calls the pure function, and the fact it passes is the
		one the theme snapshot already carries (`density`, resolved from the display
		class), so the two cannot diverge again.

		THE INSTRUMENT IS THE DISPLAY FACT ITSELF, re-pinned by wave TEN-FOOT
		(ADAPT-8/ADAPT-L1, 2026-08-20). It used to be a snapshot resolved with
		`displaySize = "Large"` and NO environment fact — which was the audit's own
		finding one level down: the snapshot's recorded `density` was the only
		channel, so this case passed while every real television, presented through
		`Facet.newPresenter` with no theme controller, measured the NEAR lane count.
		The distance policy is now applied at the environment's metric memo, so the
		fact is what the case drives and the snapshot follows it. The near arm is
		still a real control: the same tree, the same package, one fact different. ]]
	it("ADAPT-23: a ten-foot grid gets FEWER lanes than the same grid at near distance", function()
		local themeSnapshot = require("../src/themes/snapshot")
		local package = themeSnapshot.neutralPackage()
		local function lanesAt(density: string?): number
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			env:set("displaySize", if density == "ten-foot" then "Large" else "Medium")
			env:set("themeMetrics", themeSnapshot.resolve(package, nil, {}))
			local children = {}
			for i = 1, 12 do
				table.insert(children, UI.Box({ id = "c" .. i, width = FIXED(20), height = FIXED(20) }))
			end
			local screen = UI.Screen({
				id = "S",
				children = {
					UI.Grid({
						id = "G",
						minColumnWidth = 160,
						gap = 8,
						rowGap = 8,
						width = FIXED(1920),
						height = FIXED(400),
						children = children,
					}),
				},
			})
			local root = mountLib.mount(core, screen)
			local adapter = fake_target.new()
			local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()
			-- how many cells share the first line: the lane count, read off the paint
			local firstY = rectOf(adapter, "/S/G/c1").y
			local lanes = 0
			for i = 1, 12 do
				if rectOf(adapter, "/S/G/c" .. i).y == firstY then
					lanes += 1
				end
			end
			return lanes
		end
		local near = lanesAt("near")
		local tenFoot = lanesAt("ten-foot")
		expect(near).toBe(11)
		expect(tenFoot).toBe(6)
		-- ...and it is the same answer the PUBLIC predictor gives, which is the
		-- whole point of the two sharing one implementation
		local adaptive = require("../src/layout/adaptive")
		expect(tenFoot).toBe(adaptive.columnsFor(1920, 160, 8, { distanceProfile = "ten-foot" }))
		expect(near).toBe(adaptive.columnsFor(1920, 160, 8))
	end)

	--[[ ...and `minColumnWidth = "intrinsic"` MEASURES the lane axis, which is the
		half a px literal cannot reach: a number is returned before any child is
		measured, so only the intrinsic path can tell "the widest child" from "the
		tallest child". Under column flow it is the tallest, and getting that wrong
		is a different LANE COUNT rather than a different pixel — a whole extra line
		of cells, silently. ]]
	it("minColumnWidth = 'intrinsic' measures the LANE axis, not always the width", function()
		local function intrinsicGrid(flow: string?, transposed: boolean): any
			local kids = {}
			local crosses = { 20, 30, 25, 50, 20, 30 }
			for i, c in crosses do
				table.insert(
					kids,
					UI.Box({
						id = "n" .. i,
						width = if transposed then FIXED(90) else FIXED(c),
						height = if transposed then FIXED(c) else FIXED(90),
					})
				)
			end
			local props: any = {
				id = "G",
				minColumnWidth = "intrinsic",
				gap = 0,
				rowGap = 0,
				width = FIXED(200),
				height = FIXED(200),
				children = kids,
			}
			if flow ~= nil then
				props.flow = flow
			end
			return UI.Screen({ id = "S", children = { UI.Grid(props) } })
		end
		-- column flow: the tallest child is 50, so 200px of height holds FOUR lanes
		-- and six cells are two lines. Measuring the WIDTH instead would find 90 and
		-- give two lanes — three lines, and every cell after the second in the wrong
		-- place.
		local colAdapter = render(intrinsicGrid("column", true), 600, 600)
		expect(rectStr(colAdapter, "/S/G/n1")).toBe("0,0,90,20")
		expect(rectStr(colAdapter, "/S/G/n4")).toBe("0,150,90,50")
		expect(rectStr(colAdapter, "/S/G/n5")).toBe("90,0,90,20")
		-- ...and the row-flow original it transposes
		local rowAdapter = render(intrinsicGrid(nil, false), 600, 600)
		expect(rectStr(rowAdapter, "/S/G/n1")).toBe("0,0,20,90")
		expect(rectStr(rowAdapter, "/S/G/n4")).toBe("150,0,50,90")
		expect(rectStr(rowAdapter, "/S/G/n5")).toBe("0,90,20,90")
	end)

	it("uniform item sizing equalises cells in both modes alike", function()
		local function uniformScreen(flow: string?, boxW: number, boxH: number): any
			return gridScreen(flow, boxW, boxH, { itemSizing = "uniform" })
		end
		local rowAdapter = render(uniformScreen(nil, 400, 300), 600, 600)
		local colAdapter = render(uniformScreen("column", 300, 400), 600, 600)
		for _, s in SPECIMENS do
			local r = rectOf(rowAdapter, "/S/G/" .. s.id)
			local c = rectOf(colAdapter, "/S/G/" .. s.id)
			expect(`{s.id} {c.x},{c.y},{c.w},{c.h}`).toBe(`{s.id} {r.y},{r.x},{r.h},{r.w}`)
		end
	end)

	--[[ A ROW GRID HAS NO FLOW TO CHOOSE. `UI.GridRow` declares its cells in a row
		and column n is a fact about every row at once; "column-major" has no reading
		there that is not a guess, which is this file's standing rule. So the prop is
		reported and the row grid stays what it is, rather than being silently
		reinterpreted. ]]
	it("`flow` on a ROW grid is a diagnostic, not a second layout", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					flow = "column",
					children = {
						UI.GridRow({
							id = "r1",
							children = {
								UI.Box({ id = "c1", width = FIXED(30), height = FIXED(10) }),
								UI.Box({ id = "c2", width = FIXED(40), height = FIXED(10) }),
							},
						}),
						UI.GridRow({
							id = "r2",
							children = {
								UI.Box({ id = "c3", width = FIXED(50), height = FIXED(10) }),
								UI.Box({ id = "c4", width = FIXED(20), height = FIXED(10) }),
							},
						}),
					},
				}),
			},
		})
		local adapter, controller = render(screen, 600, 600)
		expect(string.find(issues(controller), "flow") ~= nil).toBe(true)
		-- and the rows are still rows: r2's cells sit BELOW r1's, in r1's columns
		local c1 = rectOf(adapter, "/S/G/r1/c1")
		local c3 = rectOf(adapter, "/S/G/r2/c3")
		expect(c3.y > c1.y).toBe(true)
		expect(c3.x).toBe(c1.x)
	end)

	--[[ ALIGNMENT TURNS WITH THE MODE, and it is the one part of the transpose that
		a symmetric corpus cannot catch. A cell aligns inside its LANE on one axis and
		inside its LINE on the other; which of those two is `alignH` is the entire
		content of the mode, so a build that read `alignH` as "the lane" in both
		directions would place every short cell against the wrong edge — reachable,
		painted, and wrong in shape. ]]
	it("alignH/alignV turn with the mode: a cell aligns in its LANE and in its LINE", function()
		local function aligned(flow: string?, boxW: number, boxH: number, transposed: boolean): any
			local props: any = {
				id = "G",
				columns = 2,
				gap = 0,
				rowGap = 0,
				width = FIXED(boxW),
				height = FIXED(boxH),
				children = {
					UI.Box({
						id = "s",
						width = if transposed then FIXED(20) else FIXED(40),
						height = if transposed then FIXED(40) else FIXED(20),
						alignH = if transposed then "end" else "center",
						alignV = if transposed then "center" else "end",
					}),
					UI.Box({
						id = "big",
						width = if transposed then FIXED(60) else FIXED(100),
						height = if transposed then FIXED(100) else FIXED(60),
					}),
				},
			}
			if flow ~= nil then
				props.flow = flow
			end
			return UI.Screen({ id = "S", children = { UI.Grid(props) } })
		end
		-- row flow: 2 lanes across 200 -> lane 100, line 60. `s` centres in its 100px
		-- lane (x = 30) and sits at the END of its 60px line (y = 40).
		local rowAdapter = render(aligned(nil, 200, 200, false), 600, 600)
		expect(rectStr(rowAdapter, "/S/G/s")).toBe("30,40,40,20")
		-- column flow: the same two offsets, a quarter turn round
		local colAdapter = render(aligned("column", 200, 200, true), 600, 600)
		expect(rectStr(colAdapter, "/S/G/s")).toBe("40,30,20,40")
	end)

	--[[ ...and so does ASPECT, which follows the LANE because the lane is the axis
		the grid actually fixed. `ratio` is w/h, so row flow reads `h = laneW / ratio`
		and column flow reads `w = laneH * ratio`. A square cell cannot tell those two
		apart, which is why this case is not square. ]]
	it("an aspect cell derives its FLOW extent from the lane, the right way round", function()
		local function aspectGrid(flow: string?, boxW: number, boxH: number, transposed: boolean): any
			local props: any = {
				id = "G",
				columns = 1,
				gap = 0,
				rowGap = 0,
				width = FIXED(boxW),
				height = FIXED(boxH),
				children = {
					UI.Box({
						id = "media",
						width = if transposed then { type = "aspect", ratio = 2 } else FILL,
						height = if transposed then FILL else { type = "aspect", ratio = 2 },
					}),
				},
			}
			if flow ~= nil then
				props.flow = flow
			end
			return UI.Screen({ id = "S", children = { UI.Grid(props) } })
		end
		-- row flow: one 200px lane -> a 2:1 cell is 200 x 100
		expect(rectStr(render(aspectGrid(nil, 200, 300, false), 600, 600), "/S/G/media")).toBe("0,0,200,100")
		-- column flow: one 100px lane DOWN -> the same cell is 200 x 100, and a build
		-- that divided instead of multiplying would paint it 50 wide
		expect(rectStr(render(aspectGrid("column", 300, 100, true), 600, 600), "/S/G/media")).toBe("0,0,200,100")
	end)

	it("an unbounded lane axis yields one lane, in either mode", function()
		-- a column-flow grid inside a sideways ScrollView is offered an unbounded
		-- WIDTH, which is its FLOW axis, so the lanes are still countable; the
		-- unbounded case that matters is the LANE axis, here a vertical scroller
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "SV",
					axis = "y",
					width = FIXED(300),
					height = FIXED(200),
					children = {
						UI.Grid({
							id = "G",
							flow = "column",
							minColumnWidth = 40,
							gap = 0,
							rowGap = 0,
							width = FIXED(300),
							children = {
								UI.Box({ id = "u1", width = FIXED(20), height = FIXED(20) }),
								UI.Box({ id = "u2", width = FIXED(20), height = FIXED(20) }),
							},
						}),
					},
				}),
			},
		})
		local adapter = render(screen, 600, 600)
		-- one lane: the two cells are two LINES, side by side
		local u1 = rectOf(adapter, "/S/SV/G/u1")
		local u2 = rectOf(adapter, "/S/SV/G/u2")
		expect(u2.y).toBe(u1.y)
		expect(u2.x > u1.x).toBe(true)
	end)
end)

return true
