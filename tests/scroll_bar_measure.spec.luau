--!strict
-- A hug ScrollView must MEASURE the bar its own arrange will RESERVE
-- (matrix row 2026-08-08, ref_wardrobe compact-phone-portrait: every category
-- chip overflowed its box by exactly the engine scrollbar's 8px). The arrange
-- pass reserves `scrollBarReserve` off the cross axis whenever the scroll axis
-- overflows — so a scroller whose own cross size HUGS content reported a size
-- at which it cannot reproduce itself: the parent granted content-height, the
-- arrange subtracted the bar, and every child was 8px too tall for the box.
-- Same fixed-point family as the Grid measure fix (grid_measure_arrange.spec).
--
-- The headless twin is deliberately opted in per-world here: the fake target
-- publishes no scrollBarThickness by default, which is WHY no headless sweep
-- ever saw this class — recorded in the stage's framework-fixes ledger.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

local function world(withBar: boolean, build: (any) -> any)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	if withBar then
		(adapter :: any).scrollBarThickness = 8
	end
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local handle = presenter.present(build(LuauUI.UI, core), {})
	presenter.refresh()
	return core, adapter, presenter, handle
end

local function chipRow(UI: any): any
	local chips: { any } = {}
	for i = 1, 9 do
		-- the REAL trigger shape from the live matrix row: a ZStack chip (button
		-- + a paint overlay). Leaf children slip past the overflow detector;
		-- container children are what the live defect clipped.
		chips[#chips + 1] = UI.ZStack({
			id = "C" .. i,
			children = {
				UI.Button({ id = "B", label = "Chip " .. i }),
				UI.Box({
					id = "U",
					height = { type = "fixed", px = 3 },
					width = { type = "fill", weight = 1 },
					alignV = "end",
					surface = "accent",
				}),
			},
		})
	end
	return UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "Col",
				gap = "s",
				children = {
					UI.ScrollView({
						id = "Shelf",
						axis = "x",
						gap = "s",
						width = { type = "fill", weight = 1 },
						children = chips,
					}),
					UI.Text({ id = "Below", text = "below the shelf" }),
				},
			}),
		},
	})
end

describe("ScrollView measure includes the bar its arrange reserves", function()
	it("an overflowing hug x-shelf reports zero diagnostics with a live bar", function()
		local core, _, _, handle = world(true, chipRow)
		local diags = handle.controller.diagnostics()
		expect(#diags).toBe(0)
		expect(core:lastError()).toBeNil()
	end)

	it("the shelf's box is tall enough for a full control PLUS the bar", function()
		local _, _, _, handle = world(true, chipRow)
		local shelf = handle.controller.rectOf("/S/Col/Shelf")
		local chip = handle.controller.rectOf("/S/Col/Shelf/C1")
		expect(shelf ~= nil and chip ~= nil).toBe(true)
		expect(shelf.h >= chip.h + 8).toBe(true)
	end)

	it("without a bar (fallback adapters) nothing changes", function()
		local _, _, _, handle = world(false, chipRow)
		local diags = handle.controller.diagnostics()
		expect(#diags).toBe(0)
		local shelf = handle.controller.rectOf("/S/Col/Shelf")
		local chip = handle.controller.rectOf("/S/Col/Shelf/C1")
		expect(shelf.h).toBe(chip.h)
	end)

	it("a shelf whose content FITS reserves nothing", function()
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Col",
						gap = "s",
						children = {
							UI.ScrollView({
								id = "Shelf",
								axis = "x",
								gap = "s",
								width = { type = "fill", weight = 1 },
								children = { UI.Button({ id = "C1", label = "One" }) },
							}),
						},
					}),
				},
			})
		end)
		local shelf = handle.controller.rectOf("/S/Col/Shelf")
		local chip = handle.controller.rectOf("/S/Col/Shelf/C1")
		expect(shelf.h).toBe(chip.h)
	end)

	it("the vertical mirror: an overflowing hug-width y-scroller widens by the bar", function()
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			local rows: { any } = {}
			for i = 1, 30 do
				rows[#rows + 1] = UI.Button({ id = "R" .. i, label = "Row " .. i })
			end
			return UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						gap = "s",
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "List",
								height = { type = "fill", weight = 1 },
								gap = "s",
								children = rows,
							}),
							UI.Text({ id = "Beside", text = "beside" }),
						},
					}),
				},
			})
		end)
		local diags = handle.controller.diagnostics()
		expect(#diags).toBe(0)
		local list = handle.controller.rectOf("/S/Row/List")
		local row = handle.controller.rectOf("/S/Row/List/R1")
		expect(list.w >= row.w + 8).toBe(true)
	end)
end)
