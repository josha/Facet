--!strict
-- The ZStack overflow diagnostic must not fire on a `fill` axis
-- (reference-app matrix 2026-08-08, burn-down finding: a fill axis resolves at
-- arrange to exactly the stack's box, but `measure` answers `fill` with
-- CONTENT — so a fill-width page scroller, whose content is what it exists to
-- be taller than, was reported as "overflowing" a box it can never leave, on
-- every screen, and three reference proofs carried `overflow = "clip"` purely
-- to silence it. The 8px width component came from the scroll measure's
-- honest bar reserve meeting the same false comparison.)
--
-- The diagnostic stays LIVE for the axes a child sizes itself on: that is the
-- real overlap signal the device matrix depends on, and the negative controls
-- below pin that the fix did not widen into blindness.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

local function world(build: (any) -> any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	-- the live shape carried the engine bar: keep it so the reserve half of
	-- the false positive (offer + bar on the cross axis) is in the fixture
	(adapter :: any).scrollBarThickness = 8
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local handle = presenter.present(build(Facet.UI), {})
	presenter.refresh()
	return handle
end

describe("zstack overflow diagnostic: fill axes are granted, not measured", function()
	it("a fill-size page scroller taller than the stack is NOT an overflow", function()
		-- the minimized live shape: ZStack > fill scroller > 900px content in
		-- a 300px viewport. Pre-fix: "overflows its zstack by 8x600px".
		local handle = world(function(UI)
			return UI.Screen({
				id = "Root",
				children = {
					UI.ZStack({
						id = "Z",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Page",
								axis = "y",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								children = {
									UI.Box({
										id = "Tall",
										width = { type = "fill", weight = 1 },
										height = { type = "fixed", px = 900 },
									}),
								},
							}),
						},
					}),
				},
			})
		end)
		expect(#handle.controller.diagnostics()).toBe(0)
	end)

	it("NEGATIVE CONTROL: a hug child genuinely bigger than the stack still reports", function()
		local handle = world(function(UI)
			return UI.Screen({
				id = "Root",
				children = {
					UI.ZStack({
						id = "Z",
						width = { type = "fixed", px = 100 },
						height = { type = "fixed", px = 40 },
						children = {
							UI.Box({
								id = "Big",
								width = { type = "fixed", px = 160 },
								height = { type = "fixed", px = 90 },
							}),
						},
					}),
				},
			})
		end)
		local diags = handle.controller.diagnostics()
		expect(#diags >= 1).toBe(true)
		local hit = false
		for _, d in diags do
			if
				string.find(tostring(d.node), "/Big", 1, true) ~= nil
				and string.find(d.issue, "overflows its zstack", 1, true) ~= nil
			then
				hit = true
			end
		end
		expect(hit).toBe(true)
	end)

	it("NEGATIVE CONTROL: a fill-WIDTH child still reports its oversize HEIGHT", function()
		-- the axis gate is per-axis: filling one axis must not hush the other
		local handle = world(function(UI)
			return UI.Screen({
				id = "Root",
				children = {
					UI.ZStack({
						id = "Z",
						width = { type = "fixed", px = 200 },
						height = { type = "fixed", px = 40 },
						children = {
							UI.Box({
								id = "WideTall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 90 },
							}),
						},
					}),
				},
			})
		end)
		local diags = handle.controller.diagnostics()
		local hit = false
		for _, d in diags do
			if
				string.find(tostring(d.node), "/WideTall", 1, true) ~= nil
				and string.find(d.issue, "overflows its zstack", 1, true) ~= nil
			then
				hit = true
			end
		end
		expect(hit).toBe(true)
	end)
end)

return true
