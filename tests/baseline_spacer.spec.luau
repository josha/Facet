--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local UI = require("../src/blueprint")
local solver = require("../src/layout/solver")
local fixed = function(px: number)
	return { type = "fixed", px = px }
end
local function solve(children: any, align: string?, width: number?, wrap: boolean?)
	return solver.solve({
		id = "root",
		kind = "vstack",
		children = {
			{
				id = "row",
				kind = if wrap then "hwrap" else "hstack",
				align = align,
				width = fixed(width or 200),
				children = children,
			},
		},
	}, { w = width or 200, h = 300 }, { rootPolicy = "edgeToEdge" })
end
local function text(id: string, size: number, value: string?)
	return { id = id, kind = "text", text = value or "Hello", textSize = size, lineHeight = 1.2 }
end
describe("text baselines and spacer minimums", function()
	it("accepts the additive public vocabulary", function()
		expect(UI.HStack({ align = "firstTextBaseline", children = {} }).class).toBe("HStack")
		expect(UI.Text({ text = "Hello", lineAlign = "lastTextBaseline" }).class).toBe("Text")
		expect(UI.Spacer({ minLength = "m" }).class).toBe("Spacer")
	end)
	it("aligns first baselines of unequal type sizes and reserves both sides", function()
		local r = solve({ text("small", 10), text("large", 20) }, "firstTextBaseline")
		expect(r.rects.small.rect.y + 9).toBe(r.rects.large.rect.y + 18)
		expect(r.rects.row.rect.h).toBe(24)
	end)
	it("aligns last baselines of multiline text", function()
		local r = solve({ text("small", 10), text("large", 20, "Hello\nWorld") }, "lastTextBaseline")
		expect(r.rects.small.rect.y + 9).toBe(r.rects.large.rect.y + 42)
		expect(r.rects.row.rect.h).toBe(48)
	end)
	it("reserves spacer minima before dividing the surplus", function()
		local r = solve(
			{ { id = "a", kind = "spacer", minLength = 40 }, { id = "b", kind = "spacer", minLength = 10 } },
			nil,
			100
		)
		expect(r.rects.a.rect.w).toBe(65)
		expect(r.rects.b.rect.w).toBe(35)
	end)
	it("keeps minimums on deficit and reports overflow", function()
		local r = solve(
			{ { id = "a", kind = "spacer", minLength = 40 }, { id = "b", kind = "spacer", minLength = 10 } },
			nil,
			30
		)
		expect(r.rects.a.rect.w).toBe(40)
		expect(r.rects.b.rect.w).toBe(10)
		expect(#r.diagnostics > 0).toBe(true)
	end)
end)

describe("baseline composition and compatibility", function()
	it("uses a non-text child's bottom edge and expands the row below it", function()
		local r = solve(
			{ { id = "icon", kind = "box", width = fixed(30), height = fixed(40) }, text("label", 20) },
			"firstTextBaseline"
		)
		expect(r.rects.icon.rect.y + 40).toBe(r.rects.label.rect.y + 18)
		expect(r.rects.row.rect.h).toBe(46)
	end)
	it("forwards nested first and last text guides with padding and gaps", function()
		for _, align in { "firstTextBaseline", "lastTextBaseline" } do
			local r = solve({
				{
					id = "column",
					kind = "vstack",
					padding = { top = 3, bottom = 2 },
					gap = 5,
					children = { text("one", 10), text("two", 20) },
				},
				text("peer", 10),
			}, align)
			local target = if align == "firstTextBaseline" then r.rects.one.rect.y + 9 else r.rects.two.rect.y + 18
			expect(r.rects.peer.rect.y + 9).toBe(target)
			expect(r.rects.row.rect.h >= r.rects.column.rect.h).toBe(true)
		end
	end)
	it("aligns wrapped rows independently and accounts for each row's descent", function()
		local children = { text("one", 10), text("two", 20), text("three", 10), text("four", 20) }
		for _, child in children do
			child.width = fixed(40)
		end
		local r = solve(children, "firstTextBaseline", 80, true)
		expect(r.rects.one.rect.y + 9).toBe(r.rects.two.rect.y + 18)
		expect(r.rects.three.rect.y + 9).toBe(r.rects.four.rect.y + 18)
		expect(r.rects.three.rect.y - r.rects.one.rect.y).toBe(24)
		expect(r.rects.row.rect.h).toBe(48)
	end)
	it("honors per-child overrides and mixed first/last groups", function()
		local a, b, c = text("a", 10), text("b", 20), text("c", 10)
		c.lineAlign = "end"
		local r = solve({ a, b, c }, "firstTextBaseline")
		expect(r.rects.a.rect.y + 9).toBe(r.rects.b.rect.y + 18)
		expect(r.rects.c.rect.y + r.rects.c.rect.h).toBe(r.rects.row.rect.y + r.rects.row.rect.h)
	end)
	it("preserves explicit spacer dimensions and diagnoses a wrong baseline axis", function()
		local r = solve(
			{ { id = "a", kind = "spacer", minLength = 80, width = fixed(7) }, { id = "b", kind = "spacer" } },
			nil,
			100
		)
		expect(r.rects.a.rect.w).toBe(7)
		expect(r.rects.b.rect.w).toBe(93)
		local v = solver.solve(
			{ id = "v", kind = "vstack", align = "firstTextBaseline", children = { text("t", 10) } },
			{ w = 100, h = 100 }
		)
		expect(#v.diagnostics > 0).toBe(true)
	end)
	it("rejects invalid spacer floors at the public boundary", function()
		for _, value in { -1, math.huge, 0 / 0, "not.a.metric" } do
			local ok = pcall(function()
				UI.Spacer({ minLength = value })
			end)
			expect(ok).toBe(false)
		end
	end)
end)

local Facet = require("../src") :: any
local lt = require("./lib/large_text")
local snapshot = require("../src/themes/snapshot")
describe("baseline and spacer live reactive bindings", function()
	it("re-solves signal and theme changes without replacing mounted nodes", function()
		local w = lt.world({ input = "desktop" })
		local align = w.core:signal("firstTextBaseline")
		local floor = w.core:signal("m")
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "R",
					align = align,
					width = fixed(240),
					children = {
						UI.Text({ id = "A", text = "Small", textSize = "caption" }),
						UI.Spacer({ id = "Gap", minLength = floor }),
						UI.Text({ id = "B", text = "Large\nTitle", textSize = "title" }),
					},
				}),
			},
		}))
		local function node(id: string): any
			for path, entry in w.adapter.liveNodes() do
				if path:sub(-#id - 1) == "/" .. id then
					return entry
				end
			end
			error("missing " .. id)
		end
		local before = node("A")
		local function rect(id: string): any
			return node(id).rect
		end
		local firstY = rect("A").y
		align:set("lastTextBaseline")
		w.pres.refresh()
		expect(rect("A").y > firstY).toBe(true)
		floor:set(100)
		w.pres.refresh()
		expect(rect("Gap").w >= 100).toBe(true)
		local metrics = snapshot.resolve(
			snapshot.neutralPackage(),
			nil,
			{},
			{ ["type.caption.baseline"] = 0.5, ["type.title.baseline"] = 0.95, ["type.title.lineHeight"] = 1.5 }
		)
		w.env:set("themeMetrics", metrics)
		w.env:set("preferredTextOffset", 10)
		w.pres.refresh()
		expect(node("A")).toBe(before)
		expect(rect("A").y > firstY).toBe(true)
		w.pres.dismiss(w.handle)
		w.pres.refresh()
		expect(next(w.adapter.liveNodes())).toBe(nil)
	end)
end)

local coreFactory = require("../src/core/custom")
local envFactory = require("../src/env/environment")
local mountLib = require("../src/mount")
local renderer = require("../src/render/renderer")
local fake = require("./lib/fake_target")
local function differentialArm(incremental: boolean): any
	local core = coreFactory.new()
	local env = envFactory.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 260, h = 400 })
	local align = core:signal("start")
	local peerAlign = core:signal("start")
	local size = core:signal(10)
	local floor = core:signal(12)
	local axis = core:signal("x")
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "R",
					axis = axis,
					width = fixed(240),
					children = {
						UI.VStack({
							id = "Nested",
							lineAlign = align,
							children = { UI.Text({ id = "A", text = "first\nsecond", textSize = size }) },
						}),
						UI.Text({ id = "B", text = "Peer", textSize = 24, lineAlign = peerAlign }),
						UI.Spacer({ id = "Gap", minLength = floor }),
					},
				}),
			},
		})
	)
	local target = fake.new()
	local controller = renderer.attach(core, root, env, target, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = incremental,
		layoutNodeReuse = incremental,
	})
	controller.initialRender()
	return {
		core = core,
		env = env,
		root = root,
		target = target,
		controller = controller,
		align = align,
		peerAlign = peerAlign,
		size = size,
		floor = floor,
		axis = axis,
	}
end
local function geometry(w: any): string
	local rows = {}
	for id, entry in w.target.liveNodes() do
		local r = entry.rect
		if r then
			table.insert(rows, `{id}:{r.x},{r.y},{r.w},{r.h}`)
		end
	end
	table.sort(rows)
	return table.concat(rows, ";")
end
describe("baseline incremental differential", function()
	it("matches uncached geometry through child alignment, type, spacer, and adaptive axis changes", function()
		local a, b = differentialArm(true), differentialArm(false)
		for _, change in
			{
				{ "peerAlign", "lastTextBaseline" },
				{ "align", "lastTextBaseline" },
				{ "size", 20 },
				{ "floor", 60 },
				{ "align", "firstTextBaseline" },
				{ "size", 12 },
				{ "axis", "y" },
				{ "axis", "x" },
				{ "floor", 0 },
				{ "align", "start" },
				{ "peerAlign", "start" },
				{ "size", 18 },
				{ "peerAlign", "firstTextBaseline" },
			}
		do
			a[change[1]]:set(change[2])
			b[change[1]]:set(change[2])
			a.controller.refresh()
			b.controller.refresh()
			expect(geometry(a)).toBe(geometry(b))
		end
		a.controller.dispose()
		b.controller.dispose()
		a.root.dispose()
		b.root.dispose()
	end)
	it("reports a spacer minimum shadowed by an explicit dimension, including axis changes", function()
		local w = lt.world()
		local axis = w.core:signal("x")
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "Row",
					axis = axis,
					children = { UI.Spacer({ id = "Gap", minLength = 10, width = fixed(5) }) },
				}),
			},
		}))
		local function conflict(): boolean
			for _, d in w.controller.diagnostics() do
				if d.issue:find("Spacer.minLength", 1, true) then
					return true
				end
			end
			return false
		end
		expect(conflict()).toBe(true)
		axis:set("y")
		w.pres.refresh()
		expect(conflict()).toBe(false)
		w.pres.dismiss(w.handle)
	end)
	it("uses retained hidden text but excludes losing candidate subtrees", function()
		local hidden = text("hidden", 20)
		hidden.hidden = true
		local retained = solve(
			{ { id = "nested", kind = "vstack", children = { hidden, text("shown", 10) } }, text("peer", 10) },
			"firstTextBaseline"
		)
		expect(retained.rects.peer.rect.y + 9).toBe(retained.rects.hidden.rect.y + 18)
		local candidate = {
			id = "choice",
			kind = "fits",
			width = fixed(50),
			height = fixed(50),
			children = {
				{ id = "wide", kind = "vstack", width = fixed(500), children = { text("loser", 40) } },
				{ id = "narrow", kind = "vstack", children = { text("winner", 10) } },
			},
		}
		local r = solve({ candidate, text("peer", 20) }, "firstTextBaseline")
		expect(r.rects.peer.rect.y + 18).toBe(r.rects.winner.rect.y + 9)
	end)
end)

describe("theme baseline metrics", function()
	it("validates calibrated ratios and propagates them through derived roles", function()
		for _, ratio in { 0, 0.65, 1, -0.1, 1.1, math.huge, 0 / 0 } do
			local pkg, report = Facet.themes.define({
				base = snapshot.neutralPackage(),
				identity = {
					id = "baseline-test",
					displayName = "Baseline",
					schemaVersion = Facet.themes.SCHEMA,
					version = "0.1.0",
				},
				metrics = { typography = { body = { baseline = ratio } } },
			})
			local valid = ratio == ratio and ratio >= 0 and ratio <= 1
			expect(report.ok).toBe(valid)
			if valid then
				local metrics = snapshot.resolve(pkg, nil, {})
				expect(metrics.type.body.baseline).toBe(ratio)
				expect(metrics.type.strong.baseline).toBe(ratio)
			end
		end
	end)
	it("uses each theme's size, leading and baseline in the same measured row", function()
		for _, theme in lt.THEMES do
			local base = theme.metrics or snapshot.neutral()
			local metrics = table.clone(base)
			metrics.type = table.clone(base.type)
			metrics.type.caption = table.clone(base.type.caption)
			metrics.type.title = table.clone(base.type.title)
			metrics.type.caption.baseline = 0.65
			metrics.type.title.baseline = 0.95
			local a, b = text("a", 10), text("b", 20)
			a.textSize = "caption"
			a.lineHeight = nil
			b.textSize = "title"
			b.lineHeight = nil
			local r = solver.solve({
				id = "root",
				kind = "vstack",
				children = {
					{ id = "row", kind = "hstack", align = "firstTextBaseline", children = { a, b } },
				},
			}, { w = 300, h = 200 }, { metrics = metrics, rootPolicy = "edgeToEdge" })
			local function guide(id: string, role: any): number
				return r.rects[id].rect.y + role.size * ((role.lineHeight - 1) / 2 + role.baseline)
			end
			expect(math.abs(guide("a", metrics.type.caption) - guide("b", metrics.type.title)) <= 1).toBe(true)
		end
	end)
end)

describe("baseline and spacer bounded edges", function()
	it("keeps empty rows finite and wrapping spacers reserve only their floor", function()
		local empty = solve({}, "firstTextBaseline")
		expect(empty.rects.row.rect.h).toBe(0)
		local r =
			solve({ { id = "gap", kind = "spacer", minLength = 15 }, text("label", 10) }, "lastTextBaseline", 100, true)
		expect(r.rects.gap.rect.w).toBe(15)
		local blank = text("blank", 10, "")
		local z = solve({ blank, text("peer", 20) }, "firstTextBaseline")
		expect(z.rects.blank.rect.y == z.rects.blank.rect.y).toBe(true)
	end)
	it("uses measured wrapped height after a fill allocation", function()
		local a = text("wrap", 20, "alpha beta gamma delta epsilon")
		a.width = { type = "fill", weight = 1 }
		local r = solve({ a, text("label", 10) }, "lastTextBaseline", 120)
		local tf = r.rects.wrap.textFacts
		expect(tf.lines > 1).toBe(true)
		expect(math.abs((r.rects.wrap.rect.y + 18 + (tf.lines - 1) * 24) - (r.rects.label.rect.y + 9)) <= 1).toBe(true)
		expect(r.rects.row.rect.h >= r.rects.wrap.rect.h).toBe(true)
	end)
end)
