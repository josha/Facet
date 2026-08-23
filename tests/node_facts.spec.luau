--!strict
-- NODE-SCOPED FACTS (framework-gaps-phase2 W3-C, "node-fact trio" — items 15,
-- 37, 40). One seam answers all three: a node reporting a fact ABOUT ITSELF
-- (its own live mounted path, its rect relative to another node, its current
-- position in a list's data order) rather than a caller reconstructing the
-- fact by hand from a lower-level primitive.
--
--   15  `controller.mountedPathOf(declaredPath)` — resolves an author's
--       DECLARED id chain to its LIVE mounted path across a `UI.When`
--       ancestor's injected `/then` segment, replacing the dead
--       `adapter.paths()` substring-scan `p5_wardrobe/init.luau` carried.
--   37  `controller.screenRectOf(path, relativeTo)` — a node's rect
--       translated into another node's origin in one call, replacing the
--       root-relative-then-subtract arithmetic RascalRally's `StoryFlow.luau`
--       had three copies of.
--   40  `list.positionOf(key)` — a `VirtualList` row's current 1-based index,
--       exposing the already-live `indexByKey` window fact publicly.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local paths = require("../src/paths")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local virtual_list = require("../src/controls/virtual_list")
local Facet = require("../src") :: any

-- ===== 15a: the pure string arithmetic ======================================

describe("paths.stripThenSegments (gap 15)", function()
	it("removes a single /then segment a UI.When branch injects", function()
		expect(paths.stripThenSegments("/S/PaneZ/then/Pane")).toBe("/S/PaneZ/Pane")
	end)

	it("removes every /then segment across nested Whens", function()
		expect(paths.stripThenSegments("/S/then/A/then/B")).toBe("/S/A/B")
	end)

	it("a path with no /then segment is unchanged", function()
		expect(paths.stripThenSegments("/S/PaneZ/Pane")).toBe("/S/PaneZ/Pane")
	end)

	it("a root-level /then is removed too", function()
		expect(paths.stripThenSegments("/then/S")).toBe("/S")
	end)
end)

-- ===== 15b + 37: a live surface, node-relative facts ========================

local function mountWhenPane()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local on = core:signal(true)
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		children = {
			UI.When({
				id = "PaneZ",
				condition = on,
				thenView = function()
					return UI.Box({
						id = "Pane",
						margin = { top = 30, left = 20 },
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 40 },
					})
				end,
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, root, adapter, controller
end

describe("controller.mountedPathOf (gap 15)", function()
	it("resolves a node's DECLARED path to its LIVE path across a UI.When prefix", function()
		local _, root, _, controller = mountWhenPane()
		expect(controller.mountedPathOf("/S/PaneZ/Pane")).toBe("/S/PaneZ/then/Pane")
		controller.dispose()
		root.dispose()
	end)

	it("a path already live at the literal string resolves to itself", function()
		local _, root, _, controller = mountWhenPane()
		expect(controller.mountedPathOf("/S/PaneZ/then/Pane")).toBe("/S/PaneZ/then/Pane")
		controller.dispose()
		root.dispose()
	end)

	it("an unmounted declared path answers nil, not a false substring match", function()
		local _, root, _, controller = mountWhenPane()
		expect(controller.mountedPathOf("/S/PaneZ/Ghost")).toBe(nil)
		-- "/S/PaneZ/Pane" is a real live suffix of "/S/PaneZ/then/Pane"; a
		-- DIFFERENT declared chain that merely shares characters must not match
		expect(controller.mountedPathOf("/S/PaneZ/Pan")).toBe(nil)
		controller.dispose()
		root.dispose()
	end)
end)

describe("controller.screenRectOf relativeTo (gap 37)", function()
	local function mountLayerCard()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			padding = { top = 12, left = 8, right = 0, bottom = 0 },
			children = {
				UI.ZStack({
					id = "Layer",
					width = { type = "fixed", px = 300 },
					height = { type = "fixed", px = 300 },
					children = {
						UI.Box({
							id = "Card",
							margin = { top = 30, left = 20 },
							width = { type = "fixed", px = 50 },
							height = { type = "fixed", px = 40 },
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return core, root, adapter, controller
	end

	it("equals the manual root-relative-then-subtract arithmetic it replaces", function()
		local _, root, _, controller = mountLayerCard()
		local card = controller.screenRectOf("/S/Layer/Card")
		local layer = controller.screenRectOf("/S/Layer")
		local relative = controller.screenRectOf("/S/Layer/Card", "/S/Layer")
		expect(relative ~= nil).toBe(true)
		expect(relative.x).toBe(card.x - layer.x)
		expect(relative.y).toBe(card.y - layer.y)
		expect(relative.w).toBe(card.w)
		expect(relative.h).toBe(card.h)
		-- and it is genuinely NOT window space: Layer itself is not at the origin
		expect(layer.x ~= 0 or layer.y ~= 0).toBe(true)
		controller.dispose()
		root.dispose()
	end)

	it("a node relative to itself is {0,0,w,h}", function()
		local _, root, _, controller = mountLayerCard()
		local relative = controller.screenRectOf("/S/Layer/Card", "/S/Layer/Card")
		expect(relative.x).toBe(0)
		expect(relative.y).toBe(0)
		controller.dispose()
		root.dispose()
	end)

	it("answers nil when either side is not live, never a partial rect", function()
		local _, root, _, controller = mountLayerCard()
		expect(controller.screenRectOf("/S/Layer/Card", "/S/Ghost")).toBe(nil)
		expect(controller.screenRectOf("/S/Ghost", "/S/Layer")).toBe(nil)
		controller.dispose()
		root.dispose()
	end)

	it("the one-argument form is unaffected (no regression)", function()
		local _, root, _, controller = mountLayerCard()
		local absolute = controller.screenRectOf("/S/Layer/Card")
		expect(absolute ~= nil).toBe(true)
		expect(absolute.w).toBe(50)
		controller.dispose()
		root.dispose()
	end)
end)

-- ===== 40: VirtualList.positionOf ===========================================

describe("VirtualList.positionOf (gap 40)", function()
	local function mountList(rows: { any })
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local rowsSignal = core:signal(rows)
		local list = virtual_list.build(Facet, core, {
			id = "List",
			rows = rowsSignal,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 200,
			cell = function(item: any)
				return UI.Text({ id = "Label", text = item.id, textSize = 14 })
			end,
		})
		local screen = UI.Screen({ id = "S", padding = 0, children = { list.blueprint } })
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return core, root, controller, list, rowsSignal
	end

	it("answers a key's current 1-based index in the data order", function()
		local _, root, controller, list = mountList({
			{ id = "a" },
			{ id = "b" },
			{ id = "c" },
		})
		expect(list.positionOf("a")).toBe(1)
		expect(list.positionOf("b")).toBe(2)
		expect(list.positionOf("c")).toBe(3)
		expect(list.positionOf("missing")).toBe(nil)
		controller.dispose()
		root.dispose()
	end)

	it("tracks a live reorder of the data, not a construction-time snapshot", function()
		local _, root, controller, list, rowsSignal = mountList({
			{ id = "a" },
			{ id = "b" },
		})
		expect(list.positionOf("b")).toBe(2)
		rowsSignal:set({ { id = "b" }, { id = "a" } })
		controller.refresh()
		expect(list.positionOf("b")).toBe(1)
		expect(list.positionOf("a")).toBe(2)
		controller.dispose()
		root.dispose()
	end)
end)
