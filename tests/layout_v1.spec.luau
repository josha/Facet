--!strict
-- P1.2 solver v1 completion tests (UI-LAYOUT-002): ZStack, Grid (fixed +
-- adaptive), Anchor, minMax/aspect dims, margins, cross-axis alignment,
-- aspect-on-both-axes diagnostic.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")

local function fixed(px: number): solver.Dim
	return { type = "fixed", px = px }
end
local function fill(weight: number?): solver.Dim
	return { type = "fill", weight = weight or 1 }
end
local EDGE = { rootPolicy = "edgeToEdge" }

describe("layout v1: zstack", function()
	it("overlays children with per-child alignment", function()
		local root: solver.Node = {
			kind = "zstack",
			id = "z",
			width = fixed(200),
			height = fixed(100),
			children = {
				{ kind = "box", id = "bg", width = fixed(200), height = fixed(100) },
				{ kind = "box", id = "badge", width = fixed(20), height = fixed(20), alignH = "end", alignV = "start" },
				{
					kind = "box",
					id = "centered",
					width = fixed(50),
					height = fixed(30),
					alignH = "center",
					alignV = "center",
				},
			},
		}
		local r = solver.solve(root, { w = 400, h = 400 }, EDGE)
		expect(r.rects.badge.rect.x).toBe(180)
		expect(r.rects.badge.rect.y).toBe(0)
		expect(r.rects.centered.rect.x).toBe(75)
		expect(r.rects.centered.rect.y).toBe(35)
	end)
end)

describe("layout v1: grid", function()
	it("fixed columns flow row-major with row heights from the tallest cell", function()
		local children = {}
		for i = 1, 5 do
			table.insert(
				children,
				{ kind = "box", id = `c{i}`, width = fixed(40), height = fixed(if i == 2 then 60 else 30) } :: solver.Node
			)
		end
		local root: solver.Node = {
			kind = "grid",
			id = "g",
			width = fixed(210),
			height = fixed(300),
			columns = 3,
			gap = 6,
			children = children,
		}
		local r = solver.solve(root, { w = 400, h = 400 }, EDGE)
		-- colW = (210 - 12) / 3 = 66
		expect(r.rects.c1.rect.x).toBe(0)
		expect(r.rects.c2.rect.x).toBe(72)
		expect(r.rects.c4.rect.y).toBe(66) -- row height 60 + gap 6
		expect(r.rects.c4.rect.x).toBe(0)
		expect(r.rects.c5.rect.x).toBe(72)
	end)

	it("adaptive columns derive the count from minColumnWidth", function()
		local children = {}
		for i = 1, 4 do
			table.insert(children, { kind = "box", id = `a{i}`, width = fixed(50), height = fixed(20) } :: solver.Node)
		end
		local root: solver.Node = {
			kind = "grid",
			id = "g",
			width = fixed(320),
			height = fixed(100),
			minColumnWidth = 100,
			gap = 10,
			children = children,
		}
		local r = solver.solve(root, { w = 400, h = 400 }, EDGE)
		-- (320+10)/(100+10) = 3 columns
		expect(r.rects.a4.rect.y > r.rects.a3.rect.y).toBe(true)
		expect(r.rects.a1.rect.y).toBe(r.rects.a3.rect.y)
	end)
end)

describe("layout v1: anchor", function()
	it("anchors HUD children to parent corners/edges with offsets", function()
		local root: solver.Node = {
			kind = "anchor",
			id = "hud",
			width = fill(1),
			height = fill(1),
			children = {
				{
					kind = "box",
					id = "minimap",
					width = fixed(80),
					height = fixed(80),
					anchor = "topRight",
					offsetX = -10,
					offsetY = 10,
				},
				{ kind = "box", id = "speed", width = fixed(100), height = fixed(40), anchor = "bottom" },
			},
		}
		local r = solver.solve(root, { w = 800, h = 600 }, EDGE)
		expect(r.rects.minimap.rect.x).toBe(800 - 80 - 10)
		expect(r.rects.minimap.rect.y).toBe(10)
		expect(r.rects.speed.rect.x).toBe(350)
		expect(r.rects.speed.rect.y).toBe(560)
	end)
end)

describe("layout v1: dims", function()
	it("minMax clamps content into its band", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "v",
			children = {
				{
					kind = "box",
					id = "clampedUp",
					width = { type = "minMax", min = 120, max = 300 },
					height = fixed(10),
				},
				{
					kind = "text",
					id = "clampedDown",
					width = { type = "minMax", min = 0, max = 60 },
					text = "a very long line of text that wants more",
					textSize = 16,
				},
			},
		}
		local r = solver.solve(root, { w = 400, h = 400 }, EDGE)
		expect(r.rects.clampedUp.rect.w).toBe(120) -- content 0 raised to min
		expect(r.rects.clampedDown.rect.w).toBe(60) -- content capped at max
	end)

	it("aspect derives one axis from the other", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "v",
			children = {
				{ kind = "box", id = "wide", width = fixed(160), height = { type = "aspect", ratio = 16 / 9 } },
				{ kind = "box", id = "tall", width = { type = "aspect", ratio = 0.5 }, height = fixed(100) },
			},
		}
		local r = solver.solve(root, { w = 400, h = 400 }, EDGE)
		expect(r.rects.wide.rect.h).toBe(90)
		expect(r.rects.tall.rect.w).toBe(50)
	end)

	it("aspect on both axes is a diagnostic, not silence", function()
		local root: solver.Node = {
			kind = "box",
			id = "bad",
			width = { type = "aspect", ratio = 1 },
			height = { type = "aspect", ratio = 1 },
		}
		local r = solver.solve(root, { w = 100, h = 100 }, EDGE)
		expect(#r.diagnostics >= 1).toBe(true)
		expect(r.diagnostics[1].node).toBe("bad")
	end)
end)

describe("layout v1: margins and alignment", function()
	it("margins add outer space in stacks; align centers on the cross axis", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "v",
			width = fixed(200),
			height = fixed(200),
			children = {
				{ kind = "box", id = "m", width = fixed(50), height = fixed(20), margin = 10 },
				{ kind = "box", id = "centered", width = fixed(50), height = fixed(20), align = "center" },
				{ kind = "box", id = "stretched", width = fixed(10), height = fixed(20), align = "stretch" },
			},
		}
		local r = solver.solve(root, { w = 400, h = 400 }, EDGE)
		expect(r.rects.m.rect.x).toBe(10)
		expect(r.rects.m.rect.y).toBe(10)
		expect(r.rects.centered.rect.y).toBe(40) -- 10+20+10 margin block
		expect(r.rects.centered.rect.x).toBe(75)
		expect(r.rects.stretched.rect.w).toBe(200)
	end)
end)

describe("UI.Grid blueprint (architecture verifier F3: §10.1 v1 control)", function()
	it("UI.Grid mounts and renders through the solver's grid kind", function()
		local Facet = require("../src") :: any
		local mountLib = require("../src/mount")
		local rendererLib = require("../src/render/renderer")
		local fake_target = require("./lib/fake_target")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local adapter = fake_target.new()
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Grid({
					id = "G",
					columns = 2,
					gap = 4,
					children = {
						Facet.UI.Box({ id = "A", height = { type = "fixed", px = 30 } }),
						Facet.UI.Box({ id = "B", height = { type = "fixed", px = 30 } }),
						Facet.UI.Box({ id = "C", height = { type = "fixed", px = 30 } }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		local a = adapter.node("/S/G/A").rect
		local b = adapter.node("/S/G/B").rect
		local c = adapter.node("/S/G/C").rect
		expect(a.y).toBe(b.y) -- same row
		expect(b.x > a.x).toBeTruthy() -- second column
		expect(c.y > a.y).toBeTruthy() -- second row
		expect(c.x).toBe(a.x) -- first column again
		root.dispose()
	end)
end)
