--!strict
--[[ THE COMPACT CARD PARADIGM (ADAPT-17, director ruling 2026-08-18; audit cells
	B-1/B-7/B-8).

	THE DIRECTOR'S QUESTION, which the adapt audit answered "no, on both halves":
	do cards present as a swipeable single-view carousel on a phone but a multi-up
	rail on medium and large screens? They do now, and this file is what says so —
	from the FACTS THE HOST ALREADY FLOWS, with no per-screen code and no device
	name anywhere in the decision (`src/layout/adaptive.luau`'s standing rule).

	EVERY CASE READS THE CONTROL'S OWN ANSWER (`dump().cardsPerView` / `.snap`),
	never the fixture's arithmetic: a rail wired to a constant would report the
	number that was DERIVED whether or not it was ever used, which is the trap
	`card_rail.luau` already records against its own viewport memo.

	THE LAST BLOCK IS A STRUCTURAL CHECKER, not a case list. It derives the set of
	scrolling collections that can hold a card set from the SOURCE — every control
	whose closed key set accepts `snap` — and fails when one of them has no
	declared compact answer here. A future card surface added without one reddens
	the suite instead of silently shipping the large-screen arrangement, which is
	the whole failure mode ADAPT-1 was about.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local worldLib = require("./lib/world")
local Facet = require("../src") :: any

local CARDS = 40

local function cards(): { any }
	local out: { any } = {}
	for i = 1, CARDS do
		table.insert(out, { id = `c{i}`, name = `Livery {i}` })
	end
	return out
end

type RailOpts = {
	width: number,
	touch: boolean?,
	railExtent: number?,
	cards: any?,
	snap: any?,
	env: any?,
}

-- a card rail wired the way a screen wires one: an axis, the paradigm, and
-- nothing else. No size branch, no per-screen constant.
local function rail(opts: RailOpts)
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = opts.width, h = 844 },
		capabilities = if opts.touch then { touch = true } else { mouse = true, keyboard = true },
		preferredInput = if opts.touch then "Touch" else "KeyboardAndMouse",
	})
	local viewportExtent = w.core:signal(opts.railExtent or opts.width)
	local list = Facet.Controls.VirtualList(w.core, {
		id = "Rail",
		axis = "x",
		rows = w.core:signal(cards()),
		key = function(item: any)
			return item.id
		end,
		itemExtent = "cards",
		cards = opts.cards,
		snap = opts.snap,
		env = opts.env,
		viewportExtent = viewportExtent,
		rowGap = 8,
		cell = function(item: any)
			return Facet.UI.Text({ id = "N", text = item.name, textSize = 14 })
		end,
	})
	return w, list, viewportExtent
end

describe("ADAPT-17: the card rail's paradigm comes from the facts", function()
	it("COMPACT + TOUCH is one card per view, with a peek of the next", function()
		local w, list = rail({ width = 390, touch = true })
		local d = list.dump()
		expect(d.cardsPerView).toBe(1)
		expect(d.snap).toBe("item")
		-- the peek is the affordance that there IS more: the card is narrower than
		-- the rail by a readable margin, and the next one shows past its edge
		expect(d.itemExtent).toBeLessThan(390)
		expect(390 - d.itemExtent).toBeGreaterThanOrEqual(24)
		w.pres.refresh()
	end)

	it("REGULAR and WIDE are multi-up rails, and snap is off unless asked", function()
		for _, width in { 900, 1400 } do
			local _, list = rail({ width = width })
			local d = list.dump()
			expect(`{width}:perView>1 = {tostring(d.cardsPerView > 1)}`).toBe(`{width}:perView>1 = true`)
			expect(`{width}:{d.snap}`).toBe(`{width}:none`)
		end
	end)

	it("the compact rung is TOUCH-PRIMARY, not merely touch-capable (ADAPT-9)", function()
		-- 480px is the width where the two answers differ: two 200px cards fit, and
		-- only the compact TOUCH rung refuses to show them
		local _, touched = rail({ width = 480, touch = true })
		local _, moused = rail({ width = 480 })
		expect(touched.dump().cardsPerView).toBe(1)
		expect(moused.dump().cardsPerView).toBeGreaterThan(1)
	end)

	it("the flip is LIVE: the same control changes paradigm when the space does", function()
		local _, list, extent = rail({ width = 390, touch = true, railExtent = 390 })
		expect(list.dump().cardsPerView).toBe(1)
		expect(list.dump().snap).toBe("item")
		-- a rotation, or a rail that grew inside a container: no remount, no reset
		extent:set(1000)
		expect(list.dump().cardsPerView).toBeGreaterThan(1)
		expect(list.dump().snap).toBe("none")
		extent:set(390)
		expect(list.dump().cardsPerView).toBe(1)
		expect(list.dump().snap).toBe("item")
	end)

	it("AUTHORED cards-per-view wins, at every width", function()
		for _, width in { 390, 1400 } do
			local _, list = rail({ width = width, touch = true, cards = { perView = 3 } })
			expect(`{width}:{list.dump().cardsPerView}`).toBe(`{width}:3`)
		end
	end)

	it("AUTHORED snap wins, in both directions", function()
		local _, off = rail({ width = 390, touch = true, snap = "none" })
		expect(off.dump().cardsPerView).toBe(1)
		expect(off.dump().snap).toBe("none")
		local _, on = rail({ width = 1400, snap = "item" })
		expect(on.dump().cardsPerView).toBeGreaterThan(1)
		expect(on.dump().snap).toBe("item")
	end)

	it("cards.peek and cards.minWidth move the two numbers the facts otherwise pick", function()
		local _, none = rail({ width = 390, touch = true, cards = { peek = 0 } })
		expect(none.dump().itemExtent).toBe(390)
		local _, dense = rail({ width = 900, cards = { minWidth = 120 } })
		local _, sparse = rail({ width = 900, cards = { minWidth = 400 } })
		expect(dense.dump().cardsPerView).toBeGreaterThan(sparse.dump().cardsPerView)
	end)

	it("an adaptive rail with NO environment refuses to construct, naming the fix", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return Facet.Controls.VirtualList(core, {
				id = "Rail",
				axis = "x",
				rows = core:signal(cards()),
				key = function(item: any)
					return item.id
				end,
				itemExtent = "cards",
				viewportExtent = 390,
				cell = function()
					return Facet.UI.Text({ id = "N", text = "x", textSize = 14 })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "environment", 1, true) ~= nil).toBe(true)
	end)

	it("...but a rail that PINS its arrangement asks the environment nothing", function()
		local core = Facet.newCore()
		local list = Facet.Controls.VirtualList(core, {
			id = "Rail",
			axis = "x",
			rows = core:signal(cards()),
			key = function(item: any)
				return item.id
			end,
			itemExtent = "cards",
			cards = { perView = 2 },
			viewportExtent = 408,
			rowGap = 8,
			cell = function()
				return Facet.UI.Text({ id = "N", text = "x", textSize = 14 })
			end,
		})
		expect(list.dump().cardsPerView).toBe(2)
		expect(list.dump().itemExtent).toBe(200)
	end)

	it("`cards` without the paradigm it configures is refused, not ignored", function()
		local w = worldLib.new()
		expect(function()
			Facet.Controls.VirtualList(w.core, {
				id = "Rail",
				axis = "x",
				rows = w.core:signal(cards()),
				key = function(item: any)
					return item.id
				end,
				itemExtent = 132,
				cards = { perView = 2 },
				viewportExtent = 390,
				cell = function()
					return Facet.UI.Text({ id = "N", text = "x", textSize = 14 })
				end,
			})
		end).toThrow()
	end)
end)

-- ===========================================================================
-- the card_rail FIXTURE, unbranched
-- ===========================================================================

describe("ADAPT-17: the shipped card rail switches paradigm with no per-screen code", function()
	local module = require("../examples/gallery/scenarios/card_rail") :: any

	local function fixture(view: any, touch: boolean)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
		if touch then
			env:set("capabilities", { touch = true })
			env:set("preferredInput", "Touch")
		end
		local system = Facet.newActionSystem(core)
		local adapter = (require("./lib/fake_target") :: any).new()
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local built = module.build({
			Facet = Facet,
			core = core,
			env = env,
			actionSystem = system,
			presenter = presenter,
		})
		built.handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return built, adapter
	end

	it("a compact touch phone gets ONE card and a snap; a desktop gets a multi-up rail", function()
		local phone = fixture({ w = 390, h = 844 }, true)
		local desk = fixture({ w = 1232, h = 1067 }, false)
		expect(phone.rail.dump().cardsPerView).toBe(1)
		expect(phone.rail.dump().snap).toBe("item")
		expect(desk.rail.dump().cardsPerView).toBeGreaterThan(1)
		expect(desk.rail.dump().snap).toBe("none")
		phone.dispose()
		desk.dispose()
	end)

	it("the fixture holds NO size branch of its own: the source names no breakpoint", function()
		local source = fs.readFile("examples/gallery/scenarios/card_rail.luau")
		-- the paradigm arrives through the declaration, so the fixture must not
		-- contain a width comparison, a size class, or a hardcoded card width
		expect(string.find(source, "sizeClass", 1, true)).toBeNil()
		expect(string.find(source, "interactionClasses", 1, true)).toBeNil()
		expect(string.find(source, "ITEM_EXTENT", 1, true)).toBeNil()
		expect(string.find(source, 'itemExtent = "cards"', 1, true) ~= nil).toBe(true)
	end)

	it("the card still fits its rail at every emulated width, peek included", function()
		for _, case in
			{
				{ view = { w = 320, h = 640 }, touch = true },
				{ view = { w = 390, h = 844 }, touch = true },
				{ view = { w = 640, h = 320 }, touch = true },
				{ view = { w = 1232, h = 1067 }, touch = false },
			}
		do
			local built = fixture(case.view, case.touch)
			local d = built.rail.dump()
			local perView = d.cardsPerView
			local spent = perView * d.itemExtent + (perView - 1) * d.rowGap
			--[[ THE WIDTH AND THE RAIL IN ONE STRING, so a failure says which viewport
				and by how much rather than "expected false to be true". It used to be
				`expect(s).toBe(s)` over the same interpolation — a label that could not
				fail, which is this repository's own "a check that proves nothing"
				class. The comparison is in the string now. ]]
			expect(`{case.view.w}: card box {spent} fits rail {d.viewportExtent}`).toBe(
				`{case.view.w}: card box {spent} fits rail {math.max(spent, d.viewportExtent)}`
			)
			expect(spent).toBeLessThanOrEqual(d.viewportExtent)
			expect(d.itemExtent).toBeGreaterThan(0)
			built.dispose()
		end
	end)
end)

-- ===========================================================================
-- THE STRUCTURAL COMPLETENESS CHECK
-- ===========================================================================

--[[ EVERY SCROLLING COLLECTION THAT CAN HOLD A CARD SET ANSWERS FOR COMPACT,
	EXPLICITLY. A deliberate refusal is an answer — what is refused is SILENCE,
	because silence is how the large-screen arrangement ships everywhere
	(ADAPT-1's exact failure mode).

	The trigger is derived rather than listed: a control that accepts `snap` is a
	collection whose resting places matter, which is the same thing as being able
	to be a card set. Add one without a row here and this reddens. ]]
local COMPACT_ANSWERS: { [string]: any } = {
	VirtualList = {
		answer = "one card per view with snap, plus a peek, from the facts alone",
		prove = function()
			local _, list = rail({ width = 390, touch = true })
			expect(list.dump().cardsPerView).toBe(1)
			expect(list.dump().snap).toBe("item")
		end,
	},
	VirtualGrid = {
		--[[ A DELIBERATE REFUSAL WITH A ROUTE, and the audit agreed with it (B-4,
			"AUTHORED-ONLY — documented, routed, deliberate"): a lazy grid's lane
			count is `columns`, required at construction, and `minColumnWidth` is
			refused by name pointing at `UI.Grid`. The adaptive card paradigm lives on
			the horizontal LIST, which is the shape a card rail actually is. What this
			row asserts is that the refusal is still there — a grid that quietly
			started guessing its lanes would be a second, disagreeing answer. ]]
		answer = "declared lanes: `columns` is required, and the card paradigm is newVirtualList's",
		prove = function()
			local w = worldLib.new()
			expect(function()
				Facet.Controls.VirtualGrid(w.core, {
					id = "G",
					items = w.core:signal(cards()),
					key = function(item: any)
						return item.id
					end,
					itemExtent = 100,
					viewportExtent = 300,
					cell = function()
						return Facet.UI.Text({ id = "N", text = "x", textSize = 14 })
					end,
				})
			end).toThrow()
		end,
	},
}

describe("ADAPT-17: no card surface may be silent about compact", function()
	local function snapCapableControls(): { string }
		local found: { string } = {}
		for _, name in fs.readDir("src/controls") do
			if not string.match(name, "%.luau$") then
				continue
			end
			local source = fs.readFile("src/controls/" .. name)
			-- the closed key set is where a control declares what it accepts
			if string.find(source, '\n\t"snap",', 1, true) ~= nil then
				local export = string.gsub(string.gsub(" " .. name, "%.luau$", ""), "[ _](%a)", function(c)
					return string.upper(c)
				end)
				table.insert(found, export)
			end
		end
		table.sort(found)
		return found
	end

	it("every control that accepts `snap` has a declared compact answer", function()
		local capable = snapCapableControls()
		expect(#capable).toBeGreaterThan(0)
		for _, name in capable do
			expect(`{name}: {tostring(COMPACT_ANSWERS[name] ~= nil)}`).toBe(`{name}: true`)
			expect(type(COMPACT_ANSWERS[name].answer)).toBe("string")
		end
		-- ...and no row here describes a control that no longer accepts `snap`
		for name in COMPACT_ANSWERS do
			expect(`{name} still scrolls: {tostring(table.find(capable, name) ~= nil)}`).toBe(
				`{name} still scrolls: true`
			)
		end
	end)

	it("every declared compact answer is TRUE of the live control", function()
		for _, entry in COMPACT_ANSWERS do
			entry.prove()
		end
	end)
end)
