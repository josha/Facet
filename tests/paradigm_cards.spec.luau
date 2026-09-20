--!strict
local harness = require("./lib/harness")
--[[ THE CARD PARADIGM: one card and a peek on a compact touch phone, a multi-up
	rail on medium and large screens — from the FACTS THE HOST ALREADY FLOWS, with
	no per-screen code and no device name anywhere in the decision
	(`src/layout/adaptive.luau`'s standing rule).

	The policy is `adaptive.cardsPerView` / `adaptive.cardPeek`, asserted directly,
	and the shipped card rail is asserted through what it paints.

	...AND THE CONTROL ITSELF, MOUNTED. `itemExtent = "cards"` still ships
	(`src/controls/virtual_list.luau`, the `cards` option and the `cardRail`
	arrangement), so the policy cases above are not a substitute for a rail that
	was actually built: every case in the second block below reads the CONTROL'S
	OWN ANSWER (`dump().cardsPerView` / `.snap` / `.itemExtent`), never the
	fixture's arithmetic — a rail wired to a constant would report the number that
	was DERIVED whether or not it was ever used, which is the trap
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
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local worldLib = require("./lib/harness_world")
local adaptive = Facet.adaptive

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
-- nothing else. No size branch, no per-screen constant. Built through the same
-- composite constructor an application reaches on `app.controls`.
local function rail(opts: RailOpts)
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = opts.width, h = 844 },
		capabilities = if opts.touch then { touch = true } else { mouse = true, keyboard = true },
		preferredInput = if opts.touch then "Touch" else "KeyboardAndMouse",
	})
	local viewportExtent = Compose.cell(opts.railExtent or opts.width)
	local list = harness.Controls.VirtualList(w.core, {
		id = "Rail",
		axis = "x",
		rows = Compose.cell(cards()),
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
			return harness.UI.Text({ id = "N", text = item.name, textSize = 14 })
		end,
	})
	return w, list, viewportExtent
end

describe("ADAPT-17: the card paradigm comes from the facts", function()
	it("COMPACT + TOUCH is one card per view, with a peek of the next", function()
		expect(adaptive.cardsPerView(390, { touchPrimary = true })).toBe(1)
		local peek = adaptive.cardPeek(390, 1)
		expect(peek >= adaptive.CARD_PEEK.min and peek <= adaptive.CARD_PEEK.max).toBe(true)
	end)

	it("REGULAR and WIDE are multi-up rails, and a multi-up rail spends no peek", function()
		local regular = adaptive.cardsPerView(800, { touchPrimary = true })
		local wide = adaptive.cardsPerView(1400, {})
		expect(regular).toBeGreaterThan(1)
		expect(wide).toBeGreaterThan(regular)
		expect(adaptive.cardPeek(1400, wide)).toBe(0)
	end)

	it("the compact rung is TOUCH-PRIMARY, not merely touch-capable (ADAPT-9)", function()
		expect(adaptive.cardsPerView(430, { touchPrimary = false })).toBeGreaterThan(1)
		expect(adaptive.cardsPerView(430, { touchPrimary = true })).toBe(1)
	end)

	it("distance gets fewer, larger cards at the same width", function()
		local near = adaptive.cardsPerView(1920, {})
		local far = adaptive.cardsPerView(1920, { distanceProfile = "ten-foot" })
		expect(far).toBeLessThan(near)
	end)

	it("minWidth and gap move the lane count the facts otherwise pick", function()
		expect(adaptive.cardsPerView(1200, { minWidth = 500 })).toBe(2)
		expect(adaptive.cardsPerView(1200, { minWidth = 100 })).toBeGreaterThan(adaptive.cardsPerView(1200, {}))
	end)
end)

describe("ADAPT-17: the card rail's paradigm comes from the facts, MOUNTED", function()
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

	it("the compact rung is TOUCH-PRIMARY, not merely touch-capable, on the live control", function()
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
		local core = harness.newCore()
		local ok, err = pcall(function()
			return harness.Controls.VirtualList(core, {
				id = "Rail",
				axis = "x",
				rows = Compose.cell(cards()),
				key = function(item: any)
					return item.id
				end,
				itemExtent = "cards",
				viewportExtent = 390,
				cell = function()
					return harness.UI.Text({ id = "N", text = "x", textSize = 14 })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "environment", 1, true) ~= nil).toBe(true)
	end)

	it("...but a rail that PINS its arrangement asks the environment nothing", function()
		local core = harness.newCore()
		local list = harness.Controls.VirtualList(core, {
			id = "Rail",
			axis = "x",
			rows = Compose.cell(cards()),
			key = function(item: any)
				return item.id
			end,
			itemExtent = "cards",
			cards = { perView = 2 },
			viewportExtent = 390,
			cell = function()
				return harness.UI.Text({ id = "N", text = "x", textSize = 14 })
			end,
		})
		expect(list.dump().cardsPerView).toBe(2)
	end)
end)

describe("ADAPT-17: the shipped card rail switches paradigm with no per-screen code", function()
	local module = require("../examples/gallery/scenarios/card_rail") :: any

	local function fixture(view: any, touch: boolean)
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
		if touch then
			env:set("capabilities", { touch = true })
			env:set("preferredInput", "Touch")
		end
		local system = Facet.newActionSystem(core)
		local adapter = (require("./lib/fake_target") :: any).new()
		local presenter = harness.newPresenter(core, env, adapter, system)
		local built = module.build({
			Facet = Facet,
			UI = (harness.libraryOf(core)),
			Compose = Facet.Compose,
			core = core,
			env = env,
			actionSystem = system,
			presenter = presenter,
		})
		built.handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return built, adapter
	end

	local RAIL = "/CardRail/Page/RailPane/Rail"
	-- how many whole cards the painted rail holds, and what is left over
	local function arrangement(built: any, adapter: any): (number, number)
		local railWidth = adapter.node(RAIL).rect.w
		local extent, gap = built.itemExtent(), built.cardGap
		local perView = math.floor((railWidth + gap) / (extent + gap))
		return perView, railWidth - (perView * extent + (perView - 1) * gap)
	end

	it("a compact touch phone gets ONE card; a desktop gets a multi-up rail", function()
		local phone, phoneAdapter = fixture({ w = 390, h = 844 }, true)
		local desk, deskAdapter = fixture({ w = 1232, h = 1067 }, false)
		expect((arrangement(phone, phoneAdapter))).toBe(1)
		expect((arrangement(desk, deskAdapter))).toBeGreaterThan(1)
		phone.dispose()
		desk.dispose()
	end)

	it("the fixture holds NO size branch of its own: the source names no breakpoint", function()
		local source = fs.readFile("examples/gallery/scenarios/card_rail.luau")
		-- the paradigm arrives through the policy, so the fixture must not contain
		-- a width comparison, a size class, or a hardcoded card width
		expect(string.find(source, "sizeClass", 1, true)).toBeNil()
		expect(string.find(source, "ITEM_EXTENT", 1, true)).toBeNil()
		expect(string.find(source, "adaptive.cardsPerView", 1, true) ~= nil).toBe(true)
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
			local built, adapter = fixture(case.view, case.touch)
			local perView, left = arrangement(built, adapter)
			expect(`{case.view.w}: {perView} cards leave a peek: {left > 0}`).toBe(
				`{case.view.w}: {perView} cards leave a peek: true`
			)
			expect(perView).toBeGreaterThan(0)
			expect(built.itemExtent()).toBeGreaterThan(0)
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
		answer = "declared lanes: `columns` is required, and the card paradigm is VirtualList's",
		prove = function()
			local w = worldLib.new()
			expect(function()
				harness.Controls.VirtualGrid(w.core, {
					id = "G",
					items = Compose.cell(cards()),
					key = function(item: any)
						return item.id
					end,
					itemExtent = 100,
					viewportExtent = 300,
					cell = function()
						return harness.UI.Text({ id = "N", text = "x", textSize = 14 })
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
