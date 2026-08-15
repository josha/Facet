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

--[[ ── THE GUTTER IS PUBLISHED, ON THE SIDE IT WAS TAKEN FROM ──────────────────

	A host's own descendants never need this number — the reservation already
	narrowed the box they were measured in. The node that needs it is the one
	OUTSIDE the subtree that must still line up across the boundary: a Table's
	header is a sibling of its scrolling body and drifted by exactly the reserve
	until it started paying it too (director report 2026-08-14, and the follow-up
	correction "the scroll bar issue should apply to both horizontal and vertical
	ones" — which is why the side is published rather than assumed).

	`newTable` is the only consumer today and its body always scrolls Y, so the X
	half would ship untested on the strength of a `then/else`. This is the case
	that measures it: the SAME reserve, the SAME overflow, reported on `bottom`
	because the shelf scrolls sideways.

	MUTATION-PROVEN 2026-08-14: swapping the solver's two branches (publishing
	`right` for an X host) fails the shelf case; dropping the `spentReserve > 0`
	guard fails the "reserves nothing" case. ]]
describe("the bar gutter a host spent is published for its SIBLINGS to pay", function()
	it("an X shelf reports it on `bottom` — the side an X scroller reserves from", function()
		local _, _, _, handle = world(true, chipRow)
		local inset = handle.controller.scrollBarInsetOf("/S/Col/Shelf")
		expect(`x:{inset ~= nil and `{inset.right}/{inset.bottom}` or "nil"}`).toBe("x:0/8")
	end)

	it("a Y list reports it on `right`", function()
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			local rows: { any } = {}
			for i = 1, 30 do
				rows[#rows + 1] = UI.Button({ id = "R" .. i, label = "Row " .. i })
			end
			return UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "List",
						height = { type = "fill", weight = 1 },
						gap = "s",
						children = rows,
					}),
				},
			})
		end)
		local inset = handle.controller.scrollBarInsetOf("/S/List")
		expect(`y:{inset ~= nil and `{inset.right}/{inset.bottom}` or "nil"}`).toBe("y:8/0")
	end)

	it("a host whose content FITS reserves nothing, and publishes nothing", function()
		-- the conditionality is the whole reason this is published rather than
		-- re-derived from `adapter.scrollBarThickness`: a sibling cannot know
		-- whether THIS host's content overflowed
		local _, _, _, handle = world(true, function(UI: any, _core: any)
			return UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Shelf",
						axis = "x",
						width = { type = "fill", weight = 1 },
						children = { UI.Button({ id = "C1", label = "One" }) },
					}),
				},
			})
		end)
		expect(handle.controller.scrollBarInsetOf("/S/Shelf")).toBeNil()
	end)

	it("...and a fallback adapter with no bar publishes nothing either", function()
		local _, _, _, handle = world(false, chipRow)
		expect(handle.controller.scrollBarInsetOf("/S/Col/Shelf")).toBeNil()
	end)

	it("an unmounted host stops answering", function()
		-- `lastBarInsets` is renderer state keyed by path; a path that leaves the
		-- tree and comes back as something else must not inherit the old gutter
		local _, _, presenter, handle = world(true, chipRow)
		expect(handle.controller.scrollBarInsetOf("/S/Col/Shelf")).never().toBeNil()
		presenter.dismiss(handle)
		presenter.refresh()
		expect(handle.controller.scrollBarInsetOf("/S/Col/Shelf")).toBeNil()
	end)
end)
