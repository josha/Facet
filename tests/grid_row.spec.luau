--!strict
--[[
	THE ROW GRID (docs/plans/swiftui-parity-round2.md §2.2).

	`UI.Grid` was one uniform FLOW grid: children wrap row-major into a column
	count and every column is the same width, `colW = (innerW - gap x (cols - 1))
	/ cols`. SwiftUI's `Grid`/`GridRow` pair is a different layout — each row
	declares its cells in order and COLUMN n IS AS WIDE AS THE WIDEST NATURAL CELL
	IN COLUMN n ACROSS EVERY ROW — and this stage adds it under the same name,
	selected by the children rather than by a mode prop.

	THE HARD CONSTRAINT IS THE FIRST DESCRIBE, NOT THE LAST. Every existing caller
	keeps the flow grid to the pixel; Rascal Rally's two live `UI.Grid` call sites
	(`ResultsScreen.luau:2495, :2546`) are pinned on the consumer side as well
	(`games/RascalRally/code/tests/luauui_grid_row_contract.spec.luau`). The frozen
	table below is this side of that pin: it is the SAME shape the flow grid laid
	out before `GridRow` existed, and the numbers were read off the pre-change
	build.

	WHAT EACH CASE WOULD CATCH, since a table of rects proves nothing on its own:

	  · "column n is the widest cell in column n"    -> a grid that kept one shared
	    width, i.e. row mode wired to the flow arithmetic.
	  · "a span widens no column"                    -> the naive reading, where a
	    3-column title stretches column 1 under every row beneath it.
	  · "a mix is refused"                           -> the coin-flip: a tree with
	    three rows and one loose cell silently picking a reading.
	  · "a GridRow outside a Grid says so"           -> a row that quietly laid
	    itself out with columns nobody derived.

	EVERY MOUNTED FIXTURE CALLS `controller.diagnostics()` and asserts the whole
	string (docs/lessons/the-solver-already-told-you.md): a fixture that does not
	ask the solver what it thought is not evidence.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")
local UI = require("../src/blueprint")
local schema = require("../src/blueprint_schema")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local LuauUI = require("../src") :: any

local function fixed(px: number): any
	return { type = "fixed", px = px }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

local function solve(root: any, w: number, h: number): any
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge" })
end

local function cell(id: string, w: number, h: number, extra: { [string]: any }?): any
	local node: any = { kind = "box", id = id, width = fixed(w), height = fixed(h) }
	for k, v in extra or {} do
		node[k] = v
	end
	return node
end

local function row(id: string, cells: { any }): any
	return { kind = "gridrow", id = id, children = cells }
end

-- "<x>,<y> <w>x<h>" for one rect, so a failure prints the whole box rather than
-- one axis of it
local function box(result: any, id: string): string
	local r = result.rects[id]
	if r == nil then
		return `{id}: MISSING`
	end
	return `{id}: {r.rect.x},{r.rect.y} {r.rect.w}x{r.rect.h}`
end

local function issues(result: any): string
	local parts = {}
	for _, d in result.diagnostics do
		table.insert(parts, `{d.node}: {d.issue}`)
	end
	return table.concat(parts, " | ")
end

describe("the flow grid is exactly what it was", function()
	-- THE PIN. These numbers were read off the build BEFORE row mode existed. A
	-- grid with no `gridrow` child must not be able to tell that `GridRow` shipped.
	local function flowGrid(): any
		return {
			kind = "grid",
			id = "G",
			width = fill(),
			columns = 3,
			gap = 10,
			children = {
				cell("c1", 40, 20),
				cell("c2", 60, 30),
				cell("c3", 80, 20),
				cell("c4", 50, 25),
			},
		}
	end

	it("a three-column flow grid places and sizes its cells exactly as before", function()
		local r = solve(flowGrid(), 320, 200)
		-- colW = floor((320 - 10 x 2) / 3) = 100; cells keep content size and sit at
		-- the column origin; row 2 starts after the tallest cell in row 1
		expect(box(r, "c1")).toBe("c1: 0,0 40x20")
		expect(box(r, "c2")).toBe("c2: 110,0 60x30")
		expect(box(r, "c3")).toBe("c3: 220,0 80x20")
		expect(box(r, "c4")).toBe("c4: 0,40 50x25")
		expect(issues(r)).toBe("")
	end)

	it("...and an `intrinsic` + `uniform` flow grid — the Rascal Rally shape — is unmoved", function()
		-- the declaration at ResultsScreen.luau:2495 (`Seats`), with plate-shaped
		-- children standing in for the seat rows
		local r = solve({
			kind = "grid",
			id = "Seats",
			width = fill(),
			minColumnWidth = "intrinsic",
			itemSizing = "uniform",
			gap = 4,
			rowGap = 4,
			children = { cell("s1", 120, 30), cell("s2", 140, 30), cell("s3", 100, 30) },
		}, 320, 200)
		-- intrinsic minimum = 140 (the widest child) -> floor((320+4)/(140+4)) = 2
		-- columns; uniform hands every cell the max measured size (140x30)
		expect(box(r, "s1")).toBe("s1: 0,0 140x30")
		expect(box(r, "s2")).toBe("s2: 162,0 140x30")
		expect(box(r, "s3")).toBe("s3: 0,34 140x30")
		expect(issues(r)).toBe("")
	end)
end)

describe("row mode: the columns come from every row at once", function()
	it("column n is as wide as the widest natural cell in column n", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			gap = 10,
			children = {
				row("r1", { cell("a", 60, 20), cell("b", 40, 20) }),
				row("r2", { cell("c", 30, 20), cell("d", 90, 20) }),
			},
		}, 300, 200)
		-- column 1 = max(60, 30) = 60; column 2 = max(40, 90) = 90. THE FLOW GRID
		-- WOULD GIVE BOTH COLUMNS (300 - 10) / 2 = 145, which is the number this
		-- case exists to be different from.
		expect(box(r, "a")).toBe("a: 0,0 60x20")
		expect(box(r, "b")).toBe("b: 70,0 40x20")
		expect(box(r, "c")).toBe("c: 0,30 30x20")
		expect(box(r, "d")).toBe("d: 70,30 90x20")
		expect(issues(r)).toBe("")
	end)

	it("the grid REPORTS the columns it derived, so a hug parent reserves the right box", function()
		-- no width dim on the grid: it hugs, and what it hugs to is the columns plus
		-- the gap between them (60 + 10 + 90 = 160) by the height of its two rows
		-- plus the row gap (20 + 10 + 20 = 50)
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			children = {
				{
					kind = "grid",
					id = "G",
					gap = 10,
					children = {
						row("r1", { cell("a", 60, 20), cell("b", 40, 20) }),
						row("r2", { cell("c", 30, 20), cell("d", 90, 20) }),
					},
				},
			},
		}, 300, 200)
		expect(box(r, "G")).toBe("G: 0,0 160x50")
		expect(issues(r)).toBe("")
	end)

	it("`rowGap` is the row pitch here too, and a row is as tall as its tallest cell", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			gap = 10,
			rowGap = 25,
			children = {
				row("r1", { cell("a", 40, 12), cell("b", 40, 44) }),
				row("r2", { cell("c", 40, 18), cell("d", 40, 18) }),
			},
		}, 300, 300)
		expect(box(r, "r1")).toBe("r1: 0,0 300x44")
		expect(box(r, "r2")).toBe("r2: 0,69 300x18")
		expect(issues(r)).toBe("")
	end)

	it("a `fill` cell takes its whole column; a content cell aligns inside it", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			gap = 10,
			children = {
				row("r1", { cell("wide", 100, 20), cell("filler", 10, 20, { width = fill() }) }),
				row("r2", { cell("narrow", 20, 20, { alignH = "end" }), cell("plain", 70, 20) }),
			},
		}, 300, 200)
		-- column 1 = 100 (the `fill` cell contributes its measured content, 0, and a
		-- `fill` cell in column 2 makes column 2 = max(0, 70) = 70)
		expect(box(r, "wide")).toBe("wide: 0,0 100x20")
		expect(box(r, "filler")).toBe("filler: 110,0 70x20")
		expect(box(r, "narrow")).toBe("narrow: 80,30 20x20")
		expect(box(r, "plain")).toBe("plain: 110,30 70x20")
		expect(issues(r)).toBe("")
	end)
end)

describe("row mode: a span covers columns, and widens none of them", function()
	it("a spanning cell contributes to NO single column's maximum", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			gap = 10,
			children = {
				row("r1", { cell("title", 200, 20, { gridSpan = 2 }) }),
				row("r2", { cell("b", 50, 20), cell("c", 40, 20) }),
			},
		}, 300, 200)
		-- columns come from row 2 alone: 50 and 40. The title is fitted to
		-- 50 + 10 + 40 = 100 — NOT allowed to push column 1 out to 200, which is
		-- SwiftUI's rule and the reason this case exists.
		expect(box(r, "title")).toBe("title: 0,0 100x20")
		expect(box(r, "b")).toBe("b: 0,30 50x20")
		expect(box(r, "c")).toBe("c: 60,30 40x20")
		expect(issues(r)).toBe("")
	end)

	it("a span covers the gaps between the columns it crosses, not just their widths", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			gap = 12,
			children = {
				row("r1", { cell("head", 400, 20, { gridSpan = 3, width = fill() }) }),
				row("r2", { cell("x", 30, 20), cell("y", 30, 20), cell("z", 30, 20) }),
			},
		}, 300, 200)
		-- three 30px columns and two 12px gaps: the spanned cell is 30x3 + 12x2 = 114
		expect(box(r, "head")).toBe("head: 0,0 114x20")
		expect(box(r, "z")).toBe("z: 84,32 30x20")
		expect(issues(r)).toBe("")
	end)

	it("a partial span still leaves the columns it did not cover to their own cells", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			gap = 10,
			children = {
				row("r1", { cell("pair", 999, 20, { gridSpan = 2, width = fill() }), cell("tail", 25, 20) }),
				row("r2", { cell("p", 40, 20), cell("q", 60, 20), cell("r", 25, 20) }),
			},
		}, 300, 200)
		-- columns 40 / 60 / 25; `pair` covers 1-2 (40 + 10 + 60 = 110) and `tail`
		-- lands in column 3, which it shares with `r`
		expect(box(r, "pair")).toBe("pair: 0,0 110x20")
		expect(box(r, "tail")).toBe("tail: 120,0 25x20")
		expect(box(r, "r")).toBe("r: 120,30 25x20")
		expect(issues(r)).toBe("")
	end)
end)

describe("row mode never paints outside the box it was given", function()
	it("columns wider than the grid are reduced proportionally rather than overflowing", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fixed(200),
			gap = 10,
			children = {
				row("r1", { cell("a", 200, 20), cell("b", 100, 20) }),
			},
		}, 400, 200)
		-- naturals 200 + 100 = 300 against 200 - 10 = 190 available: scale 190/300,
		-- floored per column -> 126 and 63, which fits with the gap
		expect(box(r, "a")).toBe("a: 0,0 126x20")
		expect(box(r, "b")).toBe("b: 136,0 63x20")
		expect(issues(r)).toBe("")
	end)
end)

describe("the two authoring errors row mode can produce", function()
	it("a MIX of rows and loose cells is refused, and the grid keeps the flow reading", function()
		local r = solve({
			kind = "grid",
			id = "G",
			width = fill(),
			columns = 2,
			gap = 10,
			children = {
				row("r1", { cell("a", 60, 20) }),
				cell("loose", 40, 20),
			},
		}, 300, 200)
		expect(string.find(issues(r), "children are a MIX of UI.GridRow rows and loose cells", 1, true) ~= nil).toBe(
			true
		)
		-- ...and the geometry is the FLOW grid's: two columns of (300 - 10) / 2 = 145,
		-- the row treated as one ordinary cell. Nothing silently reflows while the
		-- author reads the message.
		expect(box(r, "r1")).toBe("r1: 0,0 60x20")
		expect(box(r, "loose")).toBe("loose: 155,0 40x20")
	end)

	it("a GridRow outside a Grid names the fix instead of inventing columns", function()
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			children = { row("stray", { cell("a", 60, 20), cell("b", 40, 20) }) },
		}, 300, 200)
		expect(string.find(issues(r), "UI.GridRow outside a UI.Grid", 1, true) ~= nil).toBe(true)
		-- side by side, which is what its measure reported, so the box is the box
		expect(box(r, "a")).toBe("a: 0,0 60x20")
		expect(box(r, "b")).toBe("b: 60,0 40x20")
	end)
end)

describe("GridRow through the public authoring surface", function()
	local function render(screen: any, w: number, h: number): (any, any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter, controller
	end

	it("`UI.Grid` of `UI.GridRow`s lays out through mount + render with no diagnostics", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				children = {
					UI.Grid({
						id = "G",
						gap = 10,
						width = fill(),
						children = {
							UI.GridRow({
								id = "R1",
								children = {
									UI.Box({ id = "A", width = fixed(60), height = fixed(20) }),
									UI.Box({ id = "B", width = fixed(40), height = fixed(20) }),
								},
							}),
							UI.GridRow({
								id = "R2",
								children = {
									UI.Box({ id = "C", width = fixed(30), height = fixed(20) }),
									UI.Box({ id = "D", width = fixed(90), height = fixed(20) }),
								},
							}),
						},
					}),
				},
			}),
			300,
			200
		)
		local function rect(path: string): string
			local node = adapter.node(path)
			if node == nil then
				return `{path}: MISSING`
			end
			return `{node.rect.x},{node.rect.y} {node.rect.w}x{node.rect.h}`
		end
		expect(rect("/S/G/R1/A")).toBe("0,0 60x20")
		expect(rect("/S/G/R1/B")).toBe("70,0 40x20")
		expect(rect("/S/G/R2/D")).toBe("70,30 90x20")
		local findings = {}
		for _, d in controller.diagnostics() do
			table.insert(findings, `{d.node}: {d.issue}`)
		end
		expect(table.concat(findings, " | ")).toBe("")
	end)

	it("`gridSpan` reaches the solver from a blueprint prop", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				children = {
					UI.Grid({
						id = "G",
						gap = 10,
						width = fill(),
						children = {
							UI.GridRow({
								id = "R1",
								children = { UI.Box({ id = "T", gridSpan = 2, width = fill(), height = fixed(20) }) },
							}),
							UI.GridRow({
								id = "R2",
								children = {
									UI.Box({ id = "P", width = fixed(50), height = fixed(20) }),
									UI.Box({ id = "Q", width = fixed(40), height = fixed(20) }),
								},
							}),
						},
					}),
				},
			}),
			300,
			200
		)
		local node = adapter.node("/S/G/R1/T")
		expect(`T {node.rect.w}`).toBe("T 100")
		expect(#controller.diagnostics()).toBe(0)
	end)

	it("a GridRow refuses the box properties its grid owns, and names the fix", function()
		-- ACCEPTED-AND-IGNORED IS THE FAILURE THIS SCHEMA EXISTS TO REMOVE. A width
		-- on a row would be a second authority against the grid that derives the
		-- columns; a padding would inset one row's cells out of the columns every
		-- other row aligns to.
		for _, key in { "width", "height", "padding", "margin", "align", "gap" } do
			local ok, err = pcall(function()
				return (UI :: any).GridRow({ id = "R", [key] = fixed(10) })
			end)
			expect(`{key} accepted={ok}`).toBe(`{key} accepted=false`)
			expect(string.find(tostring(err), "GridRow", 1, true) ~= nil).toBe(true)
		end
	end)

	it("a row grid navigates as a GRID on a D-pad, from its declared rows", function()
		-- THE ROWS ARE DECLARED HERE, SO THEY ARE READ RATHER THAN INFERRED. The
		-- flow grid's focus derivation slices the focusables by its `columns` prop,
		-- and a row grid has none — so the same code read a 2x2 board as ONE row four
		-- cells wide, and Down went nowhere. `emitGridGroups` now uses the `GridRow`
		-- children when the Grid has them (`src/present/focus_map.luau`).
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local pres = LuauUI.newPresenter(core, env, fake_target.new(), system)
		local function rowOf(n: number): any
			return LuauUI.UI.GridRow({
				id = `R{n}`,
				children = {
					LuauUI.UI.Button({ id = `b{n}1`, label = `b{n}1` }),
					LuauUI.UI.Button({ id = `b{n}2`, label = `b{n}2` }),
				},
			})
		end
		pres.present(LuauUI.UI.Screen({
			id = "S",
			children = { LuauUI.UI.Grid({ id = "G", gap = 8, children = { rowOf(1), rowOf(2) } }) },
		}))
		pres.refresh()
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		expect(pres.focus.focused:get()).toBe("/S/G/R1/b11")
		press("DPadRight")
		expect(pres.focus.focused:get()).toBe("/S/G/R1/b12")
		-- ...and DOWN crosses to the second ROW, keeping the column. Without the
		-- declared-row derivation this stayed on b12 forever.
		press("DPadDown")
		expect(pres.focus.focused:get()).toBe("/S/G/R2/b22")
		press("DPadLeft")
		expect(pres.focus.focused:get()).toBe("/S/G/R2/b21")
		press("DPadUp")
		expect(pres.focus.focused:get()).toBe("/S/G/R1/b11")
	end)

	it("`gridSpan` is a SHARED box prop, so any cell can carry it", function()
		local shared: { [string]: boolean } = {}
		for _, name in schema.sharedPropNames() do
			shared[name] = true
		end
		expect(shared.gridSpan).toBe(true)
		for _, class in { "Text", "Box", "Image", "Button", "VStack" } do
			local spec = schema.forClass(class) :: any
			expect(`{class}.gridSpan={spec.props.gridSpan ~= nil}`).toBe(`{class}.gridSpan=true`)
		end
	end)
end)
