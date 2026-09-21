--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local solver = require("../src/layout/solver")
local harness = require("./lib/harness")
local UI = harness.UI
local function fixed(px: number): any
	return { type = "fixed", px = px }
end
local function fill(minimum: number?, weight: number?): any
	return { type = "fill", weight = weight or 1, min = minimum }
end
local function solve(root: any, w: number, h: number): any
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge" })
end
local function pair(width: number, a: any, b: any, margin: any?): any
	return solve({
		kind = "hstack",
		id = "R",
		width = fill(),
		children = {
			{ kind = "box", id = "a", width = a, height = fixed(10), margin = margin },
			{ kind = "box", id = "b", width = b, height = fixed(10) },
		},
	}, width, 100)
end
describe("fill minimum shares and placement", function()
	it("preserves ample weighted shares and source-index rounding", function()
		local r = pair(241, fill(44, 2), fill(44))
		expect(r.rects.a.rect.w).toBe(161)
		expect(r.rects.b.rect.w).toBe(80)
		expect(#r.diagnostics).toBe(0)
	end)
	it("clamps one short share then redistributes only the remaining room", function()
		local r = pair(100, fill(60), fill(10, 3))
		expect(r.rects.a.rect.w).toBe(60)
		expect(r.rects.b.rect.w).toBe(40)
		expect(#r.diagnostics).toBe(0)
	end)
	it("pays margins outside the floor and reports an impossible offer", function()
		local r = pair(80, fill(44), fill(44), { left = 3, right = 5 })
		expect(r.rects.a.rect.w).toBe(44)
		expect(r.rects.b.rect.w).toBe(44)
		expect(r.rects.b.rect.x).toBe(52)
		expect(#r.diagnostics > 0).toBe(true)
	end)
	it("a content stack reserves its fill children's minima", function()
		local r = solve({
			kind = "vstack",
			id = "R",
			children = {
				{
					kind = "hstack",
					id = "row",
					children = {
						{ kind = "box", id = "a", width = fill(44), height = fixed(10) },
						{ kind = "box", id = "b", width = fill(60), height = fixed(10) },
					},
				},
			},
		}, 200, 100)
		expect(r.rects.row.rect.w).toBe(104)
		expect(r.rects.b.rect.x).toBe(44)
		expect(#r.diagnostics).toBe(0)
	end)
	for _, kind in { "vstack", "zstack", "scroll" } do
		it(kind .. " preserves an above-offer cross floor", function()
			local r = solve({
				kind = kind,
				id = "R",
				axis = "y",
				width = fixed(40),
				height = fixed(80),
				children = {
					{ kind = "box", id = "a", width = fill(60), height = fixed(10) },
				},
			}, 100, 100)
			expect(r.rects.a.rect.w).toBe(60)
			if kind == "scroll" then
				expect(r.rects.R.contentSize.w).toBe(40) -- single-axis canvas deliberately clips its cross axis
				expect(#r.diagnostics).toBe(0)
			else
				expect(#r.diagnostics > 0).toBe(true)
			end
		end)
	end
	it("anchors with the floored extent before positioning", function()
		local r = solve({
			kind = "anchor",
			id = "R",
			width = fixed(40),
			height = fixed(40),
			children = {
				{
					kind = "box",
					id = "a",
					width = fill(60),
					height = fill(50),
					anchor = "bottomRight",
					offsetX = -5,
					offsetY = -3,
				},
			},
		}, 100, 100)
		expect(r.rects.a.rect.w).toBe(60)
		expect(r.rects.a.rect.h).toBe(50)
		expect(r.rects.a.rect.x).toBe(-25)
		expect(r.rects.a.rect.y).toBe(-13)
		expect(#r.diagnostics).toBe(0) -- anchors explicitly permit out-of-parent placement
	end)
	it("a wrapping fill keeps its floor beyond the offered line", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			wrap = true,
			width = fixed(40),
			height = fixed(100),
			children = {
				{ kind = "box", id = "a", width = fill(60), height = fixed(10) },
			},
		}, 100, 100)
		expect(r.rects.a.rect.w).toBe(60)
		expect(#r.diagnostics > 0).toBe(true)
	end)
	for _, minimum in { -1, math.huge, 0 / 0, false } do
		it("refuses invalid fill min " .. tostring(minimum), function()
			expect(pcall(function()
				UI.Box({ width = { type = "fill", min = minimum } })
			end)).toBe(false)
		end)
	end
	it("iteratively clamps three weights without disturbing the remainder", function()
		local children = {}
		for i, d in { fill(0, 8), fill(30), fill(30) } do
			table.insert(children, { kind = "box", id = tostring(i), width = d, height = fixed(10) })
		end
		local r = solve({ kind = "hstack", id = "R", width = fill(), children = children }, 100, 100)
		expect(r.rects["1"].rect.w).toBe(40)
		expect(r.rects["2"].rect.w).toBe(30)
		expect(r.rects["3"].rect.w).toBe(30)
	end)
	it("keeps implicit Spacer bases separate from the other child's clamp", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "spacer", id = "space", minLength = 20 },
				{ kind = "box", id = "a", width = fill(44), height = fixed(10) },
			},
		}, 80, 100)
		expect(r.rects.space.rect.w).toBe(36)
		expect(r.rects.a.rect.w).toBe(44)
		expect(#r.diagnostics).toBe(0)
	end)
	it("rounds a fractional floor up and keeps an exhausted budget finite", function()
		local r = pair(1, fill(44.1), fill(44.1))
		expect(r.rects.a.rect.w).toBe(45)
		expect(r.rects.b.rect.w).toBe(45)
		expect(r.rects.b.rect.x).toBe(45)
		expect(#r.diagnostics > 0).toBe(true)
	end)
	for _, weight in { 0, -1, math.huge, 0 / 0, false } do
		it("refuses invalid minimum-bearing weight " .. tostring(weight), function()
			expect(pcall(function()
				UI.Box({ width = { type = "fill", min = 1, weight = weight } })
			end)).toBe(false)
		end)
	end
	it("refuses a metric whose resolved minimum is negative", function()
		local snapshot = require("../src/themes/snapshot")
		expect(pcall(function()
			snapshot.resolveDim(snapshot.neutral(), { type = "fill", min = "-s" })
		end)).toBe(false)
	end)
	it("unbounded scroll measurement reports finite content plus floor", function()
		local r = solve({
			kind = "scroll",
			id = "R",
			axis = "y",
			width = fixed(100),
			height = fixed(50),
			children = {
				{ kind = "box", id = "a", width = fixed(20), height = fill(80) },
			},
		}, 100, 100)
		expect(r.rects.a.rect.h).toBe(80)
		expect(r.rects.R.contentSize.h).toBe(80)
	end)
	it("auto grid lanes include fill minima", function()
		local r = solve({
			kind = "grid",
			id = "R",
			width = fixed(150),
			gap = 0,
			children = {
				{ kind = "box", id = "a", width = fill(60), height = fixed(10) },
				{ kind = "box", id = "b", width = fill(60), height = fixed(10) },
				{ kind = "box", id = "c", width = fill(60), height = fixed(10) },
			},
		}, 200, 100)
		expect(r.rects.a.rect.w).toBe(75)
		expect(r.rects.b.rect.x).toBe(75)
		expect(r.rects.c.rect.y).toBe(10)
		expect(#r.diagnostics).toBe(0)
	end)
	it("explicit grid lanes stay authored and diagnose their impossible floor", function()
		local r = solve({
			kind = "grid",
			id = "R",
			columns = 2,
			width = fixed(80),
			gap = 0,
			children = {
				{ kind = "box", id = "a", width = fill(60), height = fixed(10) },
				{ kind = "box", id = "b", width = fill(60), height = fixed(10) },
			},
		}, 200, 100)
		expect(r.rects.a.rect.w).toBe(60)
		expect(r.rects.b.rect.x).toBe(40)
		expect(#r.diagnostics > 0).toBe(true)
	end)
	it("paired aspect measurement derives from the fill floor", function()
		local r = solve({
			kind = "vstack",
			id = "R",
			width = fixed(40),
			children = {
				{ kind = "box", id = "a", width = fill(60), height = { type = "aspect", ratio = 2 } },
			},
		}, 200, 100)
		expect(r.rects.a.rect.w).toBe(60)
		expect(r.rects.a.rect.h).toBe(30)
		expect(r.rects.R.rect.h).toBe(30)
	end)
end)

describe("fill floors participate in existing shrink negotiation", function()
	it("shrinks an opted-in 80px sibling to 56 so a 44px fill fits 100", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fixed(100),
			children = {
				{
					kind = "box",
					id = "a",
					width = { type = "minMax", min = 0, preferred = 80 },
					height = fixed(10),
					shrinkWeight = 1,
				},
				{ kind = "box", id = "b", width = fill(44), height = fixed(10) },
			},
		}, 200, 100)
		expect(r.rects.a.rect.w).toBe(56)
		expect(r.rects.b.rect.w).toBe(44)
		expect(r.rects.b.rect.x).toBe(56)
		expect(#r.diagnostics).toBe(0)
	end)
	it("keeps opted-out siblings unchanged and reports a real shortage", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fixed(100),
			children = {
				{ kind = "box", id = "a", width = { type = "minMax", min = 0, preferred = 80 }, height = fixed(10) },
				{ kind = "box", id = "b", width = fill(44), height = fixed(10) },
			},
		}, 200, 100)
		expect(r.rects.a.rect.w).toBe(80)
		expect(r.rects.b.rect.w).toBe(44)
		expect(#r.diagnostics > 0).toBe(true)
	end)
	for _, offer in { 100, 60 } do
		it("preserves the fill floor after exhausted shrink in " .. offer .. "px", function()
			local r = solve({
				kind = "hstack",
				id = "R",
				width = fixed(offer),
				children = {
					{
						kind = "box",
						id = "a",
						width = { type = "minMax", min = 80, preferred = 80 },
						height = fixed(10),
						shrinkWeight = 1,
					},
					{ kind = "box", id = "b", width = fill(44), height = fixed(10) },
				},
			}, 200, 100)
			expect(r.rects.a.rect.w).toBe(math.min(offer, 80))
			expect(r.rects.b.rect.w).toBe(44)
			expect(r.rects.b.rect.x).toBe(80)
			expect(#r.diagnostics).toBe(1)
			expect(string.find(r.diagnostics[1].issue, tostring(124 - offer) .. "px", 1, true) ~= nil).toBe(true)
		end)
	end
	it("matches warm and full public layout across floor, preferred-size and offer changes", function()
		local world = require("./lib/world")
		local function fixture(full)
			local w = world.new({ viewport = { x = 0, y = 0, w = 200, h = 100 } })
			local preferred, minimum, offer = w.Compose.cell(80), w.Compose.cell(44), w.Compose.cell(100)
			w.present(function()
				local U = w.UI
				return U.Screen("S")({
					U.HStack("R")({
						width = function(use)
							return fixed(use(offer))
						end,
						U.Box("A")({
							width = function(use)
								return { type = "minMax", min = 0, preferred = use(preferred) }
							end,
							height = fixed(10),
							shrinkWeight = 1,
						}),
						U.Box("B")({
							width = function(use)
								return fill(use(minimum))
							end,
							height = fixed(10),
						}),
					}),
				})
			end, { incrementalLayout = not full, measureReuse = not full, structuralReuse = not full })
			return w, { preferred, minimum, offer }
		end
		local a, ac = fixture(false)
		local b, bc = fixture(true)
		expect(a.adapter.node("/S/R/A").rect.w).toBe(56)
		for _, drive in { { 80, 44, 100 }, { 100, 60, 100 }, { 72, 30, 100 }, { 72, false, 100 }, { 100, 44, 180 } } do
			for i, value in drive do
				ac[i]:set(if value == false then nil else value)
				bc[i]:set(if value == false then nil else value)
			end
			a.settle()
			b.settle()
			for _, path in { "/S/R", "/S/R/A", "/S/R/B" } do
				expect(a.adapter.node(path).rect).toEqual(b.adapter.node(path).rect)
			end
			expect(a.controller.diagnostics()).toEqual(b.controller.diagnostics())
			expect(#a.controller.diagnostics()).toBe(0)
		end
	end)
end)

describe("Screen preserves normalized fill metrics", function()
	for _, minimum in { "targetSizes.minimum", { "targetSizes.minimum", 20 } } do
		it("normalizes a root minimum of kind " .. type(minimum), function()
			local world = require("./lib/world")
			local w = world.new({
				viewport = { x = 0, y = 0, w = 30, h = 30 },
				overflowGuardOff = "Intentional root floor exceeds viewport.",
			})
			w.present(function()
				return w.UI.Screen("S")({ width = { type = "fill", min = minimum } })
			end)
			expect(w.adapter.node("/S").rect.w).toBe(if type(minimum) == "string" then 44 else 64)
		end)
	end
	for _, invalid in { -1, math.huge, 0 / 0 } do
		it("refuses a nonfinite or negative normalized metric " .. tostring(invalid), function()
			local snapshot = require("../src/themes/snapshot")
			local metrics = table.clone(snapshot.neutral())
			metrics.targetSizes = table.clone(metrics.targetSizes)
			metrics.targetSizes.minimum = invalid
			expect(pcall(function()
				snapshot.resolveDim(metrics, { type = "fill", min = "targetSizes.minimum" })
			end)).toBe(false)
		end)
	end
	it("normalizes string/sum floors and re-resolves cells and theme changes", function()
		local world = require("./lib/world")
		local snapshot = require("../src/themes/snapshot")
		local w = world.new({
			viewport = { x = 0, y = 0, w = 30, h = 30 },
			overflowGuardOff = "The root deliberately declares minima larger than its 30px viewport.",
		})
		local width = w.Compose.cell({ type = "fill", min = "targetSizes.minimum" })
		w.present(function()
			return w.UI.Screen("S")({ width = width, height = { type = "fill", min = { "targetSizes.minimum", 20 } } })
		end)
		expect(w.adapter.node("/S").rect.w).toBe(44)
		expect(w.adapter.node("/S").rect.h).toBe(64)
		local metrics = table.clone(snapshot.neutral())
		metrics.targetSizes = table.clone(metrics.targetSizes)
		metrics.targetSizes.minimum = 60
		w.env:set("themeMetrics", metrics)
		w.settle()
		expect(w.adapter.node("/S").rect.w).toBe(60)
		expect(w.adapter.node("/S").rect.h).toBe(80)
		width:set({ type = "fill", min = { "targetSizes.minimum", 10 } })
		w.settle()
		expect(w.adapter.node("/S").rect.w).toBe(70)
		width:set({ type = "fill" })
		w.settle()
		expect(w.adapter.node("/S").rect.w).toBe(30)
		expect(#w.controller.diagnostics()).toBe(0)
	end)
end)
