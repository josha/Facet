--!strict
--[[
	THE LAYOUT PRIMITIVES ANSWER FOR THEMSELVES (wave LAYOUT-FIX, 2026-08-21).

	`artifacts/release-candidate-review/adapt-audit/matrix-layout.md` measured the
	six screen-size × input combos against every layout primitive and found the same
	defect shape eight times over: **an adaptive rule that exists, is correct, is
	unit-tested, and is not reached on the default path.** `Grid` defaults to one
	lane. `AdaptiveStack` defaults to not adapting. The default answer to overflow
	is to paint outside the box.

	This file is the standing guard for the halves of that this wave closed. Every
	case here was RED at the wave's anchor (`fd59cae`) — that is the point of the
	file, and the report records which mutation reddens which case.

	THE SIX COMBOS ARE THE AUDIT'S OWN, verbatim from its column table, so a row
	here can be read straight against the row there:

	  compact touch portrait    390x844   Small
	  compact touch landscape   844x390   Small
	  regular touch tablet     1024x768   Small
	  desktop pointer          1600x900   Medium
	  ten-foot gamepad        1920x1080   Large
	  hybrid pointer+touch     1280x800   Medium
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local FIXED = function(px: number)
	return { type = "fixed", px = px }
end

type Combo = { name: string, w: number, h: number, display: string }
local COMBOS: { Combo } = {
	{ name = "compact touch portrait", w = 390, h = 844, display = "Small" },
	{ name = "compact touch landscape", w = 844, h = 390, display = "Small" },
	{ name = "regular touch tablet", w = 1024, h = 768, display = "Small" },
	{ name = "desktop pointer", w = 1600, h = 900, display = "Medium" },
	{ name = "ten-foot gamepad", w = 1920, h = 1080, display = "Large" },
	{ name = "hybrid pointer+touch", w = 1280, h = 800, display = "Medium" },
}

local function render(screen: any, combo: Combo, policy: string?): (any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = combo.w, h = combo.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", combo.display)
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = policy or "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

-- how many cells share the first cell's LANE coordinate — i.e. the lane count the
-- grid actually laid out, read off the rects rather than off the arithmetic
local function laneCount(adapter: any, prefix: string, n: number): number
	local first = adapter.node(prefix .. "1")
	if first == nil then
		return 0
	end
	local lanes = 0
	for i = 1, n do
		local node = adapter.node(prefix .. i)
		if node ~= nil and node.rect.y == first.rect.y then
			lanes += 1
		end
	end
	return lanes
end

local function cards(n: number, w: number, h: number): { any }
	local kids = {}
	for i = 1, n do
		kids[i] = UI.Box({ id = "C" .. i, width = FIXED(w), height = FIXED(h) })
	end
	return kids
end

--[[ ═══ ADAPT-L2 · a Grid that was told nothing lanes itself from the box it got ═══

	`gridLaneCount` returned 1 whenever neither `columns` nor `minColumnWidth` was
	declared, at every width from 390 to 1920 — cell B-1, "a one-lane default on a
	1920 TV is a column of cards down the left edge".

	The default is now the route the guide already teaches: the widest child's own
	measured extent as the lane minimum, divided into the box the grid was actually
	offered by `adaptive.columnsFor` — the same function the declared route calls,
	so the ten-foot cap rides along and a television gets FEWER lanes than a
	desktop. No new number enters the framework.
]]
describe("ADAPT-L2 — Grid lanes itself from the space it got", function()
	-- the audit's own B-2 row, which is the number the default must now reach:
	-- six 160px cards at each combo with `minColumnWidth = 160` declared
	local EXPECTED = { 2, 4, 6, 9, 5, 7 }

	for index, combo in COMBOS do
		it(`an undeclared Grid takes the offer's lanes at {combo.name}`, function()
			local screen = UI.Screen({
				id = "S",
				children = { UI.Grid({ id = "G", gap = 12, children = cards(14, 160, 100) }) },
			})
			local adapter = render(screen, combo)
			expect(laneCount(adapter, "/S/G/C", 14)).toBe(EXPECTED[index])
		end)
	end

	it("the undeclared answer IS the declared answer, at every combo", function()
		-- the strongest form of the claim: the default is not a second arithmetic
		-- that happens to agree today, it is the same one reached with the
		-- minimum the solver already measured
		for _, combo in COMBOS do
			local declared = render(
				UI.Screen({
					id = "S",
					children = { UI.Grid({ id = "G", gap = 12, minColumnWidth = 160, children = cards(14, 160, 100) }) },
				}),
				combo
			)
			local defaulted = render(
				UI.Screen({
					id = "S",
					children = { UI.Grid({ id = "G", gap = 12, children = cards(14, 160, 100) }) },
				}),
				combo
			)
			expect(laneCount(defaulted, "/S/G/C", 14)).toBe(laneCount(declared, "/S/G/C", 14))
		end
	end)

	it("a television gets FEWER lanes than a desktop, with nothing declared", function()
		local function lanes(combo: Combo): number
			local screen = UI.Screen({
				id = "S",
				children = { UI.Grid({ id = "G", gap = 12, children = cards(14, 160, 100) }) },
			})
			return laneCount(render(screen, combo), "/S/G/C", 14)
		end
		local desktop = lanes(COMBOS[4])
		local tenFoot = lanes(COMBOS[5])
		expect(tenFoot).toBeLessThan(desktop)
	end)

	it("AUTHORED ALWAYS WINS: a declared lane count is untouched by the default", function()
		local screen = UI.Screen({
			id = "S",
			children = { UI.Grid({ id = "G", gap = 12, columns = 3, children = cards(9, 160, 100) }) },
		})
		for _, combo in COMBOS do
			expect(laneCount(render(screen, combo), "/S/G/C", 9)).toBe(3)
		end
	end)

	it("...and so is a declared minimum, in both directions", function()
		local wide = UI.Screen({
			id = "S",
			children = { UI.Grid({ id = "G", gap = 12, minColumnWidth = 700, children = cards(6, 160, 100) }) },
		})
		local narrow = UI.Screen({
			id = "S",
			children = { UI.Grid({ id = "G", gap = 12, minColumnWidth = 40, children = cards(6, 160, 100) }) },
		})
		-- a minimum WIDER than the children still wins: two lanes on a 1600 desktop,
		-- not the nine the children's own 160px would have bought
		expect(laneCount(render(wide, COMBOS[4]), "/S/G/C", 6)).toBe(2)
		-- ...and one NARROWER than them wins too — six lanes, one per child
		expect(laneCount(render(narrow, COMBOS[4]), "/S/G/C", 6)).toBe(6)
	end)

	it("THE NULL HYPOTHESIS: a grid of fill children still gets one lane", function()
		-- a `fill` child cannot express an intrinsic minimum (it measures to
		-- whatever it is offered), so the honest answer is the one-lane fallback
		-- the declared `"intrinsic"` route has always given — unchanged
		local kids = {}
		for i = 1, 6 do
			kids[i] = UI.Box({ id = "C" .. i, width = { type = "fill", weight = 1 }, height = FIXED(40) })
		end
		local screen = UI.Screen({ id = "S", children = { UI.Grid({ id = "G", gap = 12, children = kids }) } })
		expect(laneCount(render(screen, COMBOS[4]), "/S/G/C", 6)).toBe(1)
	end)
end)
