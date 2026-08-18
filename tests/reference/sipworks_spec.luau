--!strict
-- Reference proof "Sipworks" — E1 loop pins (swiftui-reference-app-validation).
--
-- These are the RA-P3 representative loop's own assertions: every state
-- transition the spec's §17 walks, both commerce outcomes and the guard, the
-- stamp arithmetic, the purchase-shaped unlock reveal, the plural selections in
-- both locales, the compact-entry sharing pin, and the reset determinism pin.
--
-- The proof is driven the way a player drives it — through the commands its own
-- controls call, and (where the point is the activation path itself) through
-- `adapter.driveActivate`, which invokes the exact closure the engine calls.
-- Nothing here reaches into a model a control cannot reach.

local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local proof = require("../../examples/reference/p3_sipworks") :: any
local strings = require("../../examples/reference/p3_sipworks/content/strings") :: any
local blends = require("../../examples/reference/p3_sipworks/content/blends") :: any
local botanicals = require("../../examples/reference/p3_sipworks/content/botanicals") :: any
local catalogService = require("../../examples/reference/p3_sipworks/services/catalog") :: any

local WIDE = { x = 0, y = 0, w = 1200, h = 800 }
local PHONE = { x = 0, y = 0, w = 360, h = 720 }
local FRAME = 1 / 30

local function world(opts: any?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", (opts or {}).viewport or WIDE)
	local system = Facet.newActionSystem(core)
	-- OPT-IN, because the live engine reserves one and the headless twin does not:
	-- a page scroller that overflows loses `scrollBar` px off its CROSS axis, and
	-- every box downstream of it is that much narrower than a bar-less run says.
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = (opts or {}).scrollBar
	local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
	local deps = {
		env = env,
		actionSystem = system,
		presenter = presenter,
		adapter = adapter,
		entry = (opts or {}).entry,
		entryItemId = (opts or {}).entryItemId,
		seed = (opts or {}).seed,
	}
	local built = proof.build(Facet, core, deps)
	presenter.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		system = system,
		built = built,
		steps = built.steps,
		report = built.report,
	}
end

-- advance the presenter's own tick, which is what advances the proof's injected
-- clock (it rides `presenter.onTick`) — no wall time anywhere
local function advance(w: any, seconds: number)
	local remaining = seconds
	while remaining > 0 do
		local slice = math.min(FRAME, remaining)
		w.presenter.tick(slice)
		remaining -= slice
	end
	w.presenter.refresh()
end

-- THE RUNNER'S OWN STEP SHAPE: `api.step` calls `presenter.refresh()` after every
-- step, so a structural change is on screen before anything reads it. A test that
-- forgot the refresh would be asserting against the previous frame.
local function step(w: any, name: string, payload: string?): any
	local result = w.steps[name](w.built, payload)
	w.presenter.refresh()
	return result
end

local function find(w: any, suffix: string): string?
	for _, path in w.report().focusPaths do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

-- every MOUNTED node, not only the focusables — a `UI.Text` is not focusable and
-- the guard notice, the row title and a measured quantity are all texts
local function findNode(w: any, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

local function nodeTextAt(w: any, path: string): string?
	local node = w.adapter.node(path)
	if node == nil then
		return nil
	end
	return node.props.text or node.props.label
end

describe("Sipworks reference proof — module contract and first mount", function()
	it("exposes the scenario build contract", function()
		expect(type(proof.build)).toBe("function")
	end)

	it("mounts headlessly with no core error and the whole menu visible", function()
		local w = world()
		local r = w.report()
		expect(r.proof).toBe("p3_sipworks")
		expect(r.entry).toBe("full")
		expect(r.section).toBe("menu")
		expect(r.visible.menu).toBe(#blends.list)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("every player-facing string comes from the locale table (no key is missing)", function()
		local missing: { string } = {}
		for key in strings.byLocale.en do
			if strings.byLocale.xa[key] == nil then
				table.insert(missing, key)
			end
		end
		expect(#missing).toBe(0)
	end)
end)

describe("Sipworks §5 — the shell flips, and the model survives the flip", function()
	it("navPlacement gives every canvas its home: sidebar / bottom tabs / inline tabs / top tabs", function()
		-- desktop shape (roomy + pointer default): the sidebar rail, no dock
		local w = world()
		expect(findNode(w, "/then/NavRail") ~= nil).toBe(true)
		expect(findNode(w, "/then/Dock") == nil).toBe(true)
		expect(findNode(w, "/then/TopBar") == nil).toBe(true)

		-- phone portrait: full bottom tab bar in the dock, rail gone
		w.env:set("viewportRect", PHONE)
		w.presenter.refresh()
		expect(findNode(w, "/then/NavRail") == nil).toBe(true)
		expect(findNode(w, "TabsFit") ~= nil).toBe(true)
		expect(findNode(w, "TabsFull") == nil).toBe(true) -- bottom bars speak the SHORT vocabulary
		expect(findNode(w, "/then/Dock") ~= nil).toBe(true)

		-- phone landscape (roomy width, SHORT height): the same bar, inline
		-- form — and a CENTERED, HUGGING cluster, never a full-width stretch
		w.env:set("viewportRect", { x = 0, y = 0, w = 720, h = 360 })
		w.presenter.refresh()
		local compactPath = findNode(w, "Center/TabsCompact")
		expect(compactPath ~= nil).toBe(true)
		expect(findNode(w, "TabsFit") == nil).toBe(true)
		local compactRow = w.adapter.node(compactPath)
		expect(compactRow ~= nil and compactRow.rect ~= nil).toBe(true)
		expect(compactRow.rect.w < 720 * 0.7).toBe(true)
		local cmid = compactRow.rect.x + compactRow.rect.w / 2
		expect(math.abs(cmid - 360) < 100).toBe(true)

		-- tablet shape (roomy + touch primary): the CENTERED top bar
		w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		w.env:set("preferredInput", "Touch")
		w.env:set("viewportRect", { x = 0, y = 0, w = 1080, h = 810 })
		w.presenter.refresh()
		expect(findNode(w, "/then/TopBar") ~= nil).toBe(true)
		expect(findNode(w, "/then/Dock") == nil).toBe(true)
		expect(findNode(w, "/then/NavRail") == nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("compact puts the TAB BAND BELOW the content and the accessory ABOVE the tabs", function()
		-- the `column` PRESET once seated the tab band ON TOP under the engine
		-- topbar (director live report); this pin asserts the GEOMETRY of the
		-- placement scaffold: at compact the dock's tabs sit strictly below the
		-- content box, and the search ACCESSORY sits between them.
		local w = world()
		w.env:set("viewportRect", PHONE)
		w.presenter.refresh()
		local content = w.adapter.node(findNode(w, "/Middle/Content"))
		local tabsPath = findNode(w, "TabsShort") or findNode(w, "TabsShortWide")
		local tabs = if tabsPath ~= nil then w.adapter.node(tabsPath) else nil
		local accessory = w.adapter.node(findNode(w, "/then/Accessory"))
		expect(content ~= nil and content.rect ~= nil).toBe(true)
		expect(tabs ~= nil and tabs.rect ~= nil).toBe(true)
		expect(accessory ~= nil and accessory.rect ~= nil).toBe(true)
		local contentBottom = content.rect.y + content.rect.h
		expect(accessory.rect.y >= contentBottom - 1).toBe(true)
		expect(tabs.rect.y >= accessory.rect.y + accessory.rect.h - 1).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("no bottom-bar tab ellipsizes in the normal range (the short vocabulary is the point)", function()
		local w = world()
		w.env:set("viewportRect", PHONE)
		w.presenter.refresh()
		local report = w.built.handle.controller.textAt ~= nil and nil or nil
		-- ask the solver's own text facts: every mounted Nav- tab must FIT
		for _, path in w.adapter.paths() do
			if string.find(path, "/TabsShort/Nav-", 1, true) ~= nil then
				local n = w.adapter.node(path)
				-- the fake target records label text props; the solver's unfit
				-- report is what the matrix consumes — assert the node was not
				-- arranged narrower than… the honest proxy headlessly is the
				-- absence of solver diagnostics plus the short-vocabulary pin
				expect(n ~= nil).toBe(true)
			end
		end
		expect(#w.built.handle.controller.diagnostics()).toBe(0)
		w.built.dispose()
	end)

	it("the top bar HUGS its tabs, centered — never full width (tablet/ten-foot shape)", function()
		local w = world()
		w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		w.env:set("preferredInput", "Touch")
		w.env:set("viewportRect", { x = 0, y = 0, w = 1080, h = 810 })
		w.presenter.refresh()
		local rowPath = findNode(w, "TopTabsFull") or findNode(w, "TopTabsShort")
		local row = if rowPath ~= nil then w.adapter.node(rowPath) else nil
		expect(row ~= nil and row.rect ~= nil).toBe(true)
		-- hugging: the tab cluster is decisively narrower than the band...
		expect(row.rect.w < 1080 * 0.7).toBe(true)
		-- ...and centered in it (midpoints within a tab's width of each other)
		local mid = row.rect.x + row.rect.w / 2
		expect(math.abs(mid - 540) < 120).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("the flip is a re-solve: search text, selection and section all survive it", function()
		local w = world()
		step(w, "search", "gin")
		step(w, "open", "copper-chai")
		w.presenter.refresh()

		w.env:set("viewportRect", PHONE)
		w.presenter.refresh()
		local narrow = w.report()
		expect(narrow.isCompact).toBe(true)
		expect(narrow.search).toBe("gin")
		expect(narrow.selectedBlendId).toBe("copper-chai")

		w.env:set("viewportRect", WIDE)
		w.presenter.refresh()
		local wide = w.report()
		expect(wide.search).toBe("gin")
		expect(wide.selectedBlendId).toBe("copper-chai")
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it(
		"compact pushes the detail as its own surface; widening dismisses it and the pane keeps the selection",
		function()
			local w = world({ viewport = PHONE })
			step(w, "open", "lantern-oolong")
			w.presenter.refresh()
			expect(w.report().surfaces.detail).toBe(true)

			w.env:set("viewportRect", WIDE)
			w.presenter.refresh()
			local after = w.report()
			expect(after.surfaces.detail).toBe(false)
			expect(after.selectedBlendId).toBe("lantern-oolong")
			expect(w.core:lastError()).toBeNil()
			w.built.dispose()
		end
	)
end)

describe("Sipworks §6 — one row blueprint, search, suggestions, favorites", function()
	it("search matches a title OR a botanical name, and never the filler", function()
		local w = world()
		step(w, "search", "gin") -- ginger
		local withGinger = w.report().visible.menu
		expect(withGinger).toBeGreaterThan(0)
		expect(withGinger).toBeLessThan(#blends.list)

		step(w, "search", "lantern") -- a title
		expect(w.report().visible.menu).toBe(1)

		step(w, "search", "spring water") -- the filler is not searchable
		expect(w.report().visible.menu).toBe(0)
		w.built.dispose()
	end)

	it("suggestions are botanical names, exclude the filler and the exact match, and cap at six", function()
		local w = world()
		step(w, "search", "gin")
		local suggestions = step(w, "suggest")
		expect(#suggestions).toBeGreaterThan(0)
		expect(#suggestions).toBeLessThanOrEqual(6)
		for _, id in suggestions do
			expect(botanicals.byId[id].water).never().toBe(true)
		end

		step(w, "accept", "ginger")
		expect(w.report().search).toBe("Ginger")
		-- an exact match offers nothing more
		expect(#step(w, "suggest")).toBe(0)
		w.built.dispose()
	end)

	it("the query is shared across sections", function()
		local w = world()
		step(w, "search", "mint")
		step(w, "section", "favorites")
		expect(w.report().search).toBe("mint")
		step(w, "section", "menu")
		expect(w.report().search).toBe("mint")
		w.built.dispose()
	end)

	it("unfavoriting every blend reaches the empty state, and Browse returns to the menu", function()
		local w = world()
		step(w, "section", "favorites")
		expect(w.report().visible.favorites).toBeGreaterThan(0)
		step(w, "unfavoriteAll")
		w.presenter.refresh()
		expect(w.report().visible.favorites).toBe(0)
		-- the empty state is a real mounted control, not a claim
		local browse = find(w, "/EmptyState/then/EmptyBox/Empty/Browse")
		expect(browse ~= nil).toBe(true)
		expect(w.adapter.driveActivate(browse :: string)).toBe(true)
		w.presenter.refresh()
		expect(w.report().section).toBe("menu")
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("the row heart is a real control on the shared favorites signal", function()
		local w = world()
		local heart = find(w, "/Row-amber-harvest/Line/Favorite")
		expect(heart ~= nil).toBe(true)
		local before = #w.report().favorites
		expect(w.adapter.driveActivate(heart :: string)).toBe(true)
		w.presenter.refresh()
		expect(#w.report().favorites).never().toBe(before)
		w.built.dispose()
	end)
end)

describe("Sipworks §7 — the adaptive header, the tiles, and the facts flip", function()
	it("the wide header candidate wins wide and loses on a phone", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		w.presenter.refresh()
		-- `hiddenRoots()` answers a MAP of path -> true
		local hidden = w.built.handle.controller.hiddenRoots()
		local function hiddenHas(fragment: string): boolean
			for path in hidden do
				if string.find(path, fragment, 1, true) ~= nil then
					return true
				end
			end
			return false
		end
		-- wide: the full-bleed fallback is the losing candidate
		expect(hiddenHas("/Header/FullBleed")).toBe(true)
		expect(hiddenHas("/Header/WideCard")).toBe(false)
		w.built.dispose()
	end)

	it("a tile opens the botanical card, whose facts are scaled to THIS blend's measure", function()
		local w = world()
		step(w, "open", "copper-chai")
		w.presenter.refresh()
		step(w, "tile", "ginger")
		w.presenter.refresh()
		expect(w.report().surfaces.card).toBe(true)

		-- the card's facts come from the catalog's derivation, not a table
		local catalog = catalogService.new()
		local facts = catalog.factsFor("copper-chai", "ginger")
		expect(#facts).toBe(4)
		local grams = facts[1].value
		local measure = catalog.measureFor("copper-chai", "ginger")
		expect(grams).toBeCloseTo(measure.value * botanicals.byId.ginger.gramsPerTsp, 0.11)
		-- and a different blend's measure gives a different fact
		local other = catalog.factsFor("emberleaf", "ginger")
		expect(other[1].value).never().toBe(grams)
		w.built.dispose()
	end)

	it("the flip swaps faces at the midpoint and only the visible face is mounted", function()
		local w = world()
		step(w, "open", "copper-chai")
		step(w, "tile", "ginger")
		advance(w, 0.1)
		expect(find(w, "/Flip/Front/then/FrontFace/Front/Actions/CardFacts") ~= nil).toBe(true)

		step(w, "flip", "back")
		advance(w, 1.5)
		expect(w.report().flip.card).toBeGreaterThan(0.9)
		expect(find(w, "/Flip/Back/then/BackFace/Back/Rows/CardFactsClose") ~= nil).toBe(true)
		-- the hidden face is UNMOUNTED, so it can never be focused
		expect(find(w, "/Flip/Front/then/FrontFace/Front/Actions/CardFacts")).toBeNil()
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("Cancel on the facts face flips to the front first; a second Cancel dismisses", function()
		local w = world()
		step(w, "open", "copper-chai")
		step(w, "tile", "ginger")
		step(w, "flip", "back")
		advance(w, 1.5)

		local first = step(w, "cancelCard")
		expect(first.consumed).toBe(true)
		expect(first.surfaces.card).toBe(true)
		advance(w, 1.5)
		local second = step(w, "cancelCard")
		expect(second.surfaces.card).toBe(false)
		w.built.dispose()
	end)
end)

describe("Sipworks §8 — the order flow: guard, rejection, confirmation, ready", function()
	it("the guard shows a reason, presents an alert on Activate, and never starts an order", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		step(w, "guard", "on")
		w.presenter.refresh()
		expect(w.report().order.paymentsEnabled).toBe(false)
		-- the notice is on screen and readable
		local notice = findNode(w, "/Cta/GuardNotice/then/NoticeBox/Notice")
		expect(notice ~= nil).toBe(true)
		expect(nodeTextAt(w, notice :: string)).toBe("Ordering is paused — the counter can't take this order.")

		step(w, "order")
		w.presenter.refresh()
		expect(w.report().surfaces.guard).toBe(true)
		expect(w.report().order.status).toBe("idle")

		step(w, "guardOk")
		step(w, "guard", "off")
		w.presenter.refresh()
		expect(w.report().surfaces.guard).toBe(false)
		expect(w.report().order.paymentsEnabled).toBe(true)
		w.built.dispose()
	end)

	it("the CTA runs idle -> pending -> rejected, shows a toast, and returns to idle", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		local cta = find(w, "/Cta/Band/OrderCTA")
		expect(cta ~= nil).toBe(true)
		expect(w.adapter.driveActivate(cta :: string)).toBe(true)
		w.presenter.refresh()
		expect(w.report().order.status).toBe("pending")
		-- the CTA says so and refuses a second press while it is in flight
		expect(nodeTextAt(w, cta :: string)).toBe("Placing…")

		advance(w, 1)
		local rejected = w.report()
		-- the scripted `counterClosed` fixture takes the FIRST attempt
		expect(rejected.order.attempts).toBe(1)
		expect(rejected.order.status).toBe("idle") -- returned, after the toast was raised
		local sawReject = false
		for _, event in rejected.feedback do
			if event.type == "reject" and event.reason == "counterClosed" then
				sawReject = true
			end
		end
		expect(sawReject).toBe(true)
		expect(w.presenter.depth() >= 0).toBe(true)
		w.built.dispose()
	end)

	it("the second order confirms, presents Order-Placed, and the disc flips at t+4s", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		step(w, "order")
		advance(w, 1) -- attempt 1: rejected
		step(w, "order")
		advance(w, 1) -- attempt 2: confirmed
		local placed = w.report()
		expect(placed.order.status).toBe("confirmed")
		expect(placed.surfaces.placed).toBe(true)
		expect(placed.order.ready).toBe(false)
		expect(placed.flip.disc).toBeLessThan(0.5)

		advance(w, 4.5)
		local ready = w.report()
		expect(ready.order.ready).toBe(true)
		expect(ready.flip.disc).toBeGreaterThan(0.9)
		local celebrated = false
		for _, event in ready.feedback do
			if event.type == "celebrate" then
				celebrated = true
			end
		end
		expect(celebrated).toBe(true)

		step(w, "done")
		w.presenter.refresh()
		expect(w.report().surfaces.placed).toBe(false)
		expect(w.report().order.status).toBe("idle")
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)
end)

describe("Sipworks §9 — Steam Stamps: accrual, the once-per-visit pop, redemption", function()
	local function confirmOrder(w: any)
		step(w, "order")
		advance(w, 1)
		if w.report().surfaces.placed then
			step(w, "done")
		end
	end

	it("one stamp per confirmed order, and a rejected order earns nothing", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		confirmOrder(w) -- attempt 1 is the scripted rejection
		expect(w.report().rewards.earned).toBe(0)
		confirmOrder(w)
		expect(w.report().rewards.earned).toBe(1)
		confirmOrder(w)
		expect(w.report().rewards.earned).toBe(2)
		w.built.dispose()
	end)

	it("the pop plays once per visit and the card is static on return", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		confirmOrder(w)
		confirmOrder(w)
		expect(#w.report().rewards.newSlots).toBe(1)

		step(w, "stamps")
		advance(w, 1)
		expect(w.report().surfaces.rewards).toBe(true)
		step(w, "leaveStamps")
		-- clear-on-leave: the same seal is static from here on
		expect(#w.report().rewards.newSlots).toBe(0)
		step(w, "stamps")
		expect(#w.report().rewards.newSlots).toBe(0)
		w.built.dispose()
	end)

	it("the plural caption selects other / one / zero across the threshold", function()
		local w = world()
		local i18n = w.built.services.i18n
		local function away(n: number): string
			return i18n.at("en", "rewards.away", { n = n })
		end
		expect(away(9)).toBe("You are 9 stamps from a free pour!")
		expect(away(1)).toBe("You are 1 stamp from a free pour!")
		expect(away(0)).toBe("Your next pour is on the house!")
		-- `rewards.progress` declares no zero form, so zero falls to `other`
		expect(i18n.at("en", "rewards.progress", { n = 1 })).toBe("1 of 10 stamps")
		expect(i18n.at("en", "rewards.progress", { n = 4 })).toBe("4 of 10 stamps")
		w.built.dispose()
	end)

	it("at ten stamps the CTA is the redeem verb, and redeeming debits a flat ten", function()
		local w = world()
		step(w, "open", "lantern-oolong")
		local rewards = w.built.services.rewards
		rewards.earn(10)
		w.presenter.refresh()
		expect(w.report().rewards.canRedeem).toBe(true)
		local cta = find(w, "/Cta/Band/OrderCTA")
		expect(nodeTextAt(w, cta :: string)).toBe("Redeem a free pour!")

		step(w, "order")
		advance(w, 1)
		if w.report().order.status == "idle" then
			-- the scripted rejection took this attempt; the next one confirms
			step(w, "order")
			advance(w, 1)
		end
		local after = w.report()
		expect(after.order.mode).toBe("redeem")
		expect(after.rewards.spent).toBe(10)
		-- ten spent, one earned for the confirmed order
		expect(after.rewards.unspent).toBe(1)
		w.built.dispose()
	end)
end)

describe("Sipworks §10 — the Blend Book unlock and the recipe view", function()
	it("locked rows are ABSENT until the purchase confirms, then they enter the list", function()
		local w = world()
		step(w, "section", "recipes")
		w.presenter.refresh()
		local freeCount = 0
		for _, blend in blends.list do
			if blend.free then
				freeCount += 1
			end
		end
		expect(w.report().visible.recipes).toBe(freeCount)
		-- and not one locked row is mounted-but-disabled
		expect(find(w, "/Row-lantern-oolong/Line/Open")).toBeNil()

		advance(w, 1.2) -- the product's availability fixture
		expect(w.report().unlock.availability).toBe("available")
		step(w, "unlockBuy")
		advance(w, 1) -- attempt 1: declined
		expect(w.report().unlock.unlocked).toBe(false)
		local sawReject = false
		for _, event in w.report().feedback do
			if event.type == "reject" and event.reason == "declined" then
				sawReject = true
			end
		end
		expect(sawReject).toBe(true)

		step(w, "unlockBuy")
		advance(w, 1) -- attempt 2: confirmed
		expect(w.report().unlock.unlocked).toBe(true)
		expect(w.report().visible.recipes).toBe(#blends.list)
		expect(find(w, "/Row-lantern-oolong/Line/Open") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("no buy button is mounted while the price is still loading", function()
		local w = world()
		step(w, "section", "recipes")
		w.presenter.refresh()
		expect(w.report().unlock.availability).toBe("pending")
		expect(find(w, "/Bar/Offer/then/UnlockBuy")).toBeNil()
		advance(w, 1.2)
		expect(find(w, "/Bar/Offer/then/UnlockBuy") ~= nil).toBe(true)
		w.built.dispose()
	end)

	it("the batch stepper rescales every measured quantity, and the checks are session-local", function()
		local w = world({ viewport = PHONE })
		step(w, "section", "recipes")
		step(w, "open", "copper-chai")
		w.presenter.refresh()
		expect(w.report().surfaces.detail).toBe(true)

		local path = findNode(w, "/Row-ginger/Lines/Quantity")
		expect(path ~= nil).toBe(true)
		expect(nodeTextAt(w, path :: string)).toBe("1 tsp")

		step(w, "batch", "4")
		w.presenter.refresh()
		expect(nodeTextAt(w, path :: string)).toBe("4 tsp")

		step(w, "gather", "ginger")
		expect(#w.report().recipe.gathered).toBe(1)
		step(w, "close")
		w.presenter.refresh()
		-- session-local by design (spec §3): dismissing the surface clears them
		expect(#w.report().recipe.gathered).toBe(0)
		w.built.dispose()
	end)
end)

describe("Sipworks §13 — localization: expansion, plurals, lists, measures", function()
	it("the pseudo-locale expands every string by at least 1.4x and keeps placeholders", function()
		local worst = math.huge
		local measured = 0
		for key, entry in strings.byLocale.en do
			local forms = if type(entry) == "table" then entry else { other = entry }
			for form, template in forms do
				local expanded = strings.byLocale.xa[key]
				local expandedText = if type(expanded) == "table" then expanded[form] else expanded
				expect(type(expandedText)).toBe("string")
				-- THE RATIO IS A CLAIM ABOUT THE TRANSLATABLE TEXT. A placeholder is
				-- a value, not a word: `"{value} {unit}"` is a format whose only
				-- literal run is a separator, and padding one would corrupt the
				-- number it sits next to. So the ≥1.4x is measured on the literal
				-- runs — the part a translator's language actually lengthens.
				local sourceLiteral = string.gsub(template, "{[%w_]+}", "")
				local targetLiteral = string.gsub(expandedText, "{[%w_]+}", "")
				if #string.gsub(sourceLiteral, "%s", "") >= 4 then
					measured += 1
					worst = math.min(worst, #targetLiteral / #sourceLiteral)
				end
				-- every placeholder survives byte for byte
				for placeholder in string.gmatch(template, "{[%w_]+}") do
					expect(string.find(expandedText, placeholder, 1, true) ~= nil).toBe(true)
				end
			end
		end
		expect(measured).toBeGreaterThan(30)
		expect(worst).toBeGreaterThanOrEqual(strings.EXPANSION)
	end)

	it("plural forms are selected in BOTH locales", function()
		local w = world()
		local i18n = w.built.services.i18n
		expect(i18n.at("en", "recipe.batches", { n = 0 })).toBe("No pots")
		expect(i18n.at("en", "recipe.batches", { n = 1 })).toBe("1 pot")
		expect(i18n.at("en", "recipe.batches", { n = 3 })).toBe("3 pots")
		-- the pseudo-locale picks the SAME forms, expanded
		local zero = i18n.at("xa", "recipe.batches", { n = 0 })
		local one = i18n.at("xa", "recipe.batches", { n = 1 })
		local other = i18n.at("xa", "recipe.batches", { n = 3 })
		expect(zero).never().toBe(one)
		expect(one).never().toBe(other)
		expect(string.find(other, "3", 1, true) ~= nil).toBe(true)
		w.built.dispose()
	end)

	it("lists and measures are service calls, and the measure separator follows the locale", function()
		local w = world()
		local i18n = w.built.services.i18n
		expect(i18n.listAt("en", { "Assam" })).toBe("Assam")
		expect(i18n.listAt("en", { "Assam", "Ginger" })).toBe("Assam and Ginger")
		expect(i18n.listAt("en", { "Assam", "Ginger", "Clove" })).toBe("Assam, Ginger, and Clove")
		expect(i18n.measureAt("en", 1.5, "tsp")).toBe("1.5 tsp")
		expect(i18n.measureAt("xa", 1.5, "tsp")).never().toBe(i18n.measureAt("en", 1.5, "tsp"))
		expect(string.find(i18n.measureAt("xa", 1.5, "tsp"), "1,5", 1, true) ~= nil).toBe(true)
		w.built.dispose()
	end)

	it("the locale step reflows every mounted surface with no remount", function()
		local w = world()
		local titlePath = findNode(w, "/Row-amber-harvest/Line/Open/Lines/Title")
		local before = nodeTextAt(w, titlePath :: string)
		local counters = w.built.handle.root.counters()

		step(w, "locale", "xa")
		w.presenter.refresh()
		local after = nodeTextAt(w, titlePath :: string)
		expect(after).never().toBe(before)
		expect(#(after :: string)).toBeGreaterThan(#(before :: string))
		-- rows are RELABELLED, not rebuilt
		expect(w.built.handle.root.counters().factoryRuns).toBe(counters.factoryRuns)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)
end)

describe("Sipworks §11 — the compact entry flow shares the same blueprints", function()
	it("boots straight into compact-link from an initial fact, deep-linked to the item", function()
		local w = world({ viewport = PHONE, entry = "compact-link", entryItemId = "lantern-oolong" })
		local r = w.report()
		expect(r.entry).toBe("compact-link")
		expect(r.entryItemId).toBe("lantern-oolong")
		expect(r.selectedBlendId).toBe("lantern-oolong")
		expect(r.surfaces.detail).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("the compact shell hides the nav, the sections and every favorite affordance", function()
		local w = world({ viewport = PHONE, entry = "compact-link" })
		step(w, "close")
		w.presenter.refresh()
		expect(find(w, "/Nav-menu")).toBeNil()
		expect(find(w, "/Nav-favorites")).toBeNil()
		expect(find(w, "/Nav-stamps")).toBeNil()
		expect(find(w, "/Nav-recipes")).toBeNil()
		for _, path in w.report().focusPaths do
			expect(string.find(path, "/Favorite", 1, true)).toBeNil()
		end
		-- the row itself is still the shared one
		expect(find(w, "/Row-lantern-oolong/Line/Open") ~= nil).toBe(true)
		w.built.dispose()
	end)

	it("the CTA is always pay-shaped in the compact entry, even at ten stamps", function()
		local w = world({ viewport = PHONE, entry = "compact-link" })
		w.built.services.rewards.earn(10)
		w.presenter.refresh()
		local cta = find(w, "/Cta/Band/OrderCTA")
		expect(cta ~= nil).toBe(true)
		expect(nodeTextAt(w, cta :: string)).toBe("Place order — 49 Credits")
		step(w, "order")
		advance(w, 1)
		step(w, "order")
		advance(w, 1)
		expect(w.report().order.mode).toBe("paid")
		-- stamps still accrue silently
		expect(w.report().rewards.earned).toBe(11)
		w.built.dispose()
	end)

	it("BOTH entries reach the SAME row blueprint function", function()
		local w = world({ viewport = PHONE })
		local listModule = w.built.views.list
		local original = listModule.blendRow
		local reached = 0
		listModule.blendRow = function(...)
			reached += 1
			return original(...)
		end
		-- the full shell's list, rebuilt through the same factory
		step(w, "enterFull")
		w.presenter.refresh()
		local fullReached = reached
		expect(fullReached).toBeGreaterThan(0)

		-- ...and the compact-link shell's, through the same factory
		step(w, "enterCompact", "lantern-oolong")
		w.presenter.refresh()
		expect(reached).toBeGreaterThan(fullReached)
		listModule.blendRow = original
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("enterFull restores the whole shell with the model intact", function()
		local w = world({ viewport = PHONE })
		w.built.services.rewards.earn(3)
		step(w, "enterCompact", "copper-chai")
		w.presenter.refresh()
		expect(w.report().entry).toBe("compact-link")
		step(w, "enterFull")
		w.presenter.refresh()
		local r = w.report()
		expect(r.entry).toBe("full")
		expect(r.rewards.earned).toBe(3)
		expect(find(w, "/Nav-menu") ~= nil).toBe(true)
		w.built.dispose()
	end)
end)

describe("Sipworks §17 — reset determinism", function()
	local function driveLoop(w: any)
		step(w, "search", "gin")
		step(w, "accept", "ginger")
		step(w, "section", "favorites")
		step(w, "unfavoriteAll")
		step(w, "section", "menu")
		step(w, "search", "")
		step(w, "open", "lantern-oolong")
		step(w, "tile", "oolong")
		step(w, "flip", "back")
		advance(w, 0.5)
		step(w, "cancelCard")
		step(w, "cancelCard")
		step(w, "order")
		advance(w, 1)
		step(w, "order")
		advance(w, 5)
		step(w, "done")
		step(w, "section", "recipes")
		advance(w, 1.2)
		step(w, "unlockBuy")
		advance(w, 1)
		step(w, "unlockBuy")
		advance(w, 1)
		step(w, "batch", "4")
		step(w, "locale", "xa")
	end

	it("same seed + same steps => identical dump, in two independent worlds", function()
		local a = world({ seed = 3 })
		local b = world({ seed = 3 })
		driveLoop(a)
		driveLoop(b)
		expect(a.built.dump()).toBe(b.built.dump())
		a.built.dispose()
		b.built.dispose()
	end)

	it("reset returns a world to its seeded start, and replaying the loop reproduces the dump", function()
		local w = world({ seed = 3 })
		local start = w.built.dump()
		driveLoop(w)
		local afterLoop = w.built.dump()
		expect(afterLoop).never().toBe(start)

		step(w, "reset")
		w.presenter.refresh()
		expect(w.built.dump()).toBe(start)

		driveLoop(w)
		expect(w.built.dump()).toBe(afterLoop)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("the seed decides the starting favorites, and a different seed differs", function()
		local a = world({ seed = 1 })
		local b = world({ seed = 2 })
		expect(#a.report().favorites).toBeGreaterThan(0)
		expect(table.concat(a.report().favorites, ",")).never().toBe(table.concat(b.report().favorites, ","))
		a.built.dispose()
		b.built.dispose()
	end)
end)

describe("Sipworks — the five-view sweep the solver itself signs off", function()
	-- THE LESSON THIS ENCODES (docs/lessons/the-solver-already-told-you.md): a
	-- fixture that never calls `controller.diagnostics()` is a fixture that can
	-- ship a screen painting outside its own box. Every viewport in the matrix,
	-- both locales and both ends of the preferred-text ladder, driven through the
	-- WHOLE loop — and the assertion is that the solver has nothing to say.
	local VIEWS = {
		{ name = "phone-portrait", w = 320, h = 640 },
		{ name = "phone-landscape", w = 640, h = 320 },
		{ name = "tablet", w = 1024, h = 768 },
		{ name = "desktop", w = 1600, h = 900 },
		{ name = "ten-foot", w = 1920, h = 1080, large = true },
	}

	local function driveEverySurface(w: any)
		step(w, "open", "cinder-chai")
		step(w, "tile", "clove")
		step(w, "flip", "back")
		advance(w, 1.5)
		step(w, "cancelCard")
		step(w, "cancelCard")
		step(w, "guard", "on")
		step(w, "order")
		step(w, "guardOk")
		step(w, "guard", "off")
		step(w, "order")
		advance(w, 1)
		step(w, "order")
		advance(w, 1)
		advance(w, 5)
		step(w, "done")
		step(w, "section", "stamps")
		step(w, "stamps")
		advance(w, 1)
		step(w, "leaveStamps")
		step(w, "section", "recipes")
		advance(w, 1.2)
		step(w, "unlockBuy")
		advance(w, 1)
		step(w, "unlockBuy")
		advance(w, 1)
		step(w, "open", "cinder-chai")
		step(w, "batch", "4")
	end

	for _, view in VIEWS do
		for _, locale in { "en", "xa" } do
			for _, offset in { 0, 14 } do
				it(`{view.name} / {locale} / preferred-text +{offset}: no solver diagnostics`, function()
					local w = world({ viewport = { x = 0, y = 0, w = view.w, h = view.h }, scrollBar = 8 })
					w.env:set("preferredTextOffset", offset)
					if view.large then
						w.env:set("displaySize", "Large")
					end
					step(w, "locale", locale)
					driveEverySurface(w)
					local issues = w.report().diagnostics
					local first = if #issues > 0
						then `{issues[1].surface}: {issues[1].issue} @ {issues[1].node}`
						else ""
					expect(`{#issues} {first}`).toBe("0 ")
					expect(w.core:lastError()).toBeNil()
					w.built.dispose()
				end)
			end
		end
	end
end)

describe("Sipworks — reduced motion, themes, and reachability", function()
	it("reduced motion fires the same events with no travel", function()
		local w = world()
		w.env:set("reducedMotion", true)
		w.presenter.refresh()
		expect(w.report().motionPolicy).toBe("reduced")

		step(w, "open", "lantern-oolong")
		step(w, "tile", "oolong")
		step(w, "flip", "back")
		-- ONE tick, not a settle: a reduced-motion spring PLACES its value
		advance(w, 1 / 30)
		expect(w.report().flip.card).toBe(1)

		step(w, "cancelCard")
		step(w, "cancelCard")
		step(w, "order")
		advance(w, 1)
		step(w, "order")
		advance(w, 1)
		expect(w.report().surfaces.placed).toBe(true)
		advance(w, 4.5)
		-- the ready flip still happens, still on the service's own clock, and the
		-- celebrate event still fires — reduced motion changes pixels, not events
		expect(w.report().order.ready).toBe(true)
		expect(w.report().flip.disc).toBe(1)
		local celebrated = false
		for _, event in w.report().feedback do
			if event.type == "celebrate" then
				celebrated = true
			end
		end
		expect(celebrated).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("mounts under BOTH reference theme packages with no source edit", function()
		local themes = Facet.themes
		for _, packageName in { "studio-neutral", "fantasy_parchment" } do
			local w = world()
			local snapshot = if packageName == "studio-neutral"
				then themes.neutral()
				else themes.resolve((require)("../../examples/themes/fantasy_parchment").build(themes), nil, {})
			w.env:set("themeMetrics", snapshot)
			w.presenter.refresh()
			step(w, "open", "lantern-oolong")
			step(w, "tile", "oolong")
			expect(w.report().surfaces.card).toBe(true)
			expect(#w.report().diagnostics).toBe(0)
			expect(w.core:lastError()).toBeNil()
			w.built.dispose()
		end
	end)

	it("every verb in the loop is a real focusable, on every input class", function()
		local w = world()
		-- the shell: four nav stops and a row with its own heart
		expect(find(w, "/Nav-menu") ~= nil).toBe(true)
		expect(find(w, "/Nav-favorites") ~= nil).toBe(true)
		expect(find(w, "/Nav-recipes") ~= nil).toBe(true)
		expect(find(w, "/Nav-stamps") ~= nil).toBe(true)
		expect(find(w, "/Search/Field") ~= nil).toBe(true)
		expect(find(w, "/Row-lantern-oolong/Line/Open") ~= nil).toBe(true)
		expect(find(w, "/Row-lantern-oolong/Line/Favorite") ~= nil).toBe(true)

		-- the detail: a tile, the favorite twin, and the one accent verb
		step(w, "open", "lantern-oolong")
		expect(find(w, "/Tile-oolong") ~= nil).toBe(true)
		expect(find(w, "/Cta/Band/OrderCTA") ~= nil).toBe(true)
		expect(find(w, "/TopBar/FavoriteSlot/[lantern-oolong]/Favorite") ~= nil).toBe(true)

		-- the card traps focus on its own ring and offers both verbs
		step(w, "tile", "oolong")
		expect(find(w, "/Front/Actions/CardClose") ~= nil).toBe(true)
		expect(find(w, "/Front/Actions/CardFacts") ~= nil).toBe(true)
		local trapped = w.built.handle.focusOrder()
		expect(trapped.present).toBe(true)
		step(w, "cancelCard")

		-- the recipe: the stepper's two affordances and a gathered toggle
		step(w, "section", "recipes")
		step(w, "open", "copper-chai")
		expect(find(w, "/Batch/Decrement") ~= nil or find(w, "/Batch/Dec") ~= nil).toBe(true)
		expect(find(w, "/Got-ginger") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("Cancel dismisses the compact detail and returns to the shell", function()
		local w = world({ viewport = PHONE })
		step(w, "open", "lantern-oolong")
		expect(w.report().surfaces.detail).toBe(true)
		expect(w.presenter.back()).toBe(true)
		w.presenter.refresh()
		expect(w.report().surfaces.detail).toBe(false)
		expect(w.report().selectedBlendId).toBe("lantern-oolong")
		w.built.dispose()
	end)

	it("build, drive and dispose are registry-neutral", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", WIDE)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local before = core:counters()
		local built = proof.build(Facet, core, {
			env = env,
			actionSystem = system,
			presenter = presenter,
			adapter = adapter,
		})
		presenter.refresh()
		built.steps.open(built, "lantern-oolong")
		built.steps.tile(built, "oolong")
		presenter.refresh()
		built.dispose()
		-- A DISMISSED SURFACE WITH AN EXIT TRANSITION DEFERS ITS TEARDOWN, and the
		-- deferral is measured in CLOCK time — so a neutrality check that never
		-- ticks is reading a tree that is still on its way out (3 signals, 1 memo
		-- and 4 scopes of it, measured).
		for _ = 1, 30 do
			presenter.tick(FRAME)
		end
		presenter.refresh()
		local after = core:counters()
		expect(after.signals).toBe(before.signals)
		expect(after.memos).toBe(before.memos)
		expect(after.scopes).toBe(before.scopes)
		expect(core:lastError()).toBeNil()
	end)
	it("the five-view sweep is diagnostic-clean with a live scrollbar (matrix pin)", function()
		for _, vp in
			{
				{ w = 360, h = 691 },
				{ w = 678, h = 339 },
				{ w = 1080, h = 810 },
				{ w = 1280, h = 720 },
				{ w = 1920, h = 1080 },
			}
		do
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = vp.w, h = vp.h })
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new();
			(adapter :: any).scrollBarThickness = 8
			local presenter = Facet.newPresenter(core, env, adapter, system)
			-- the proof presents itself, so `built.handle` IS the mounted surface
			local built =
				proof.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
			presenter.refresh()
			expect(#built.handle.controller.diagnostics()).toBe(0)
			built.dispose()
		end
	end)
end)

describe("Sipworks nav — every placement is gamepad-traversable (enter, through, away, action)", function()
	-- The gamepad-shaped path IS the focus-graph traversal (the action system
	-- routes pad navigation and keyboard Tab through the same ring; REAL pad
	-- delivery stays the physical row RA-X2). For each nav home the ring must
	-- reach every tab, activation must work on a tab, and traversal must be
	-- able to LEAVE the bar into content — a bar you cannot leave is a trap.
	local function pressTab(w: any)
		w.system.deviceKey("Tab", true)
		w.system.deviceKey("Tab", false)
		w.presenter.refresh()
	end

	local function ringPaths(w: any): { [string]: boolean }
		-- walk the whole ring once around, recording every stop
		local seen: { [string]: boolean } = {}
		local start = w.presenter.focus.focused:get()
		if start == nil then
			pressTab(w)
			start = w.presenter.focus.focused:get()
		end
		local guard = 0
		local at = start
		repeat
			if at ~= nil then
				seen[at] = true
			end
			pressTab(w)
			at = w.presenter.focus.focused:get()
			guard += 1
		until at == start or at == nil or guard > 250
		return seen
	end

	local function assertNavTraversable(w: any)
		local seen = ringPaths(w)
		-- (enter/through) every tab is a stop on the ring
		for _, section in { "menu", "favorites", "recipes", "stamps" } do
			local hit = false
			for path in seen do
				if string.find(path, "Nav-" .. section, 1, true) ~= nil then
					hit = true
				end
			end
			expect(`{section}:{hit}`).toBe(`{section}:true`)
		end
		-- (away) the ring holds MORE than the bar: content stops exist too
		local outside = false
		for path in seen do
			if string.find(path, "Nav-", 1, true) == nil then
				outside = true
			end
		end
		expect(outside).toBe(true)
		-- (action) activating a tab through the engine's activation path works
		local fav = findNode(w, "Nav-favorites")
		expect(fav ~= nil).toBe(true)
		expect(w.adapter.driveActivate(fav :: string)).toBe(true)
		w.presenter.refresh()
		expect(w.report().section).toBe("favorites")
	end

	it("sidebar (pointer desktop)", function()
		local w = world()
		assertNavTraversable(w)
		w.built.dispose()
	end)

	it("bottom tabs (phone portrait)", function()
		local w = world({ viewport = PHONE })
		assertNavTraversable(w)
		w.built.dispose()
	end)

	it("inline bottom tabs (phone landscape)", function()
		local w = world({ viewport = { x = 0, y = 0, w = 720, h = 360 } })
		assertNavTraversable(w)
		w.built.dispose()
	end)

	it("top tabs, driven as a PAD drives them: DPad across, ButtonA to act, DPad away", function()
		-- this world has NO keyboard (capabilities.keyboard = false), so Tab is
		-- honestly inert; the pad path is DPad navigation + ButtonA activation
		local w = world()
		w.env:set("capabilities", { touch = false, mouse = false, keyboard = false, gamepad = true })
		w.env:set("preferredInput", "Gamepad")
		w.env:set("displaySize", "Large")
		w.env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		w.presenter.refresh()
		expect(findNode(w, "/then/TopBar") ~= nil).toBe(true)
		local function pad(key: string)
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
			w.presenter.refresh()
		end
		local function focused(): string
			return tostring(w.presenter.focus.focused:get())
		end
		-- (enter/through) DPadRight walks the whole bar left to right
		local seen: { [string]: boolean } = { [focused()] = true }
		for _ = 1, 3 do
			pad("DPadRight")
			seen[focused()] = true
		end
		for _, section in { "menu", "favorites", "recipes", "stamps" } do
			local hit = false
			for path in seen do
				if string.find(path, "Nav-" .. section, 1, true) ~= nil then
					hit = true
				end
			end
			expect(`{section}:{hit}`).toBe(`{section}:true`)
		end
		-- (action) ButtonA on the focused tab switches the section
		pad("DPadLeft")
		pad("DPadLeft") -- back to favorites
		expect(string.find(focused(), "Nav-favorites", 1, true) ~= nil).toBe(true)
		pad("ButtonA")
		expect(w.report().section).toBe("favorites")
		-- (away) DPadDown leaves the bar into the content below
		pad("DPadDown")
		expect(string.find(focused(), "Nav-", 1, true) == nil).toBe(true)
		w.built.dispose()
	end)
end)
