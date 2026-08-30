--!strict
-- Reference proof "Sipworks" — E1 loop pins (reference-app-validation).
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

local Facet = require("../../src")
-- the metric-name vocabulary, read directly: the teardown below asserts that this
-- proof's group really left it
local themeSnapshot = require("../../src/themes/snapshot") :: any
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
		--[[ THE STAMP SEED, and it is a FACT rather than a constant so this file can
			pin BOTH halves. The shipped default is one stamp short of the card
			(`rewards.THRESHOLD - 1`), because the whole point of the played task is
			that a visitor sees the stamp ceremony, the reward and the free pour
			without ten repetitive orders. The accrual arithmetic below — one stamp
			per confirmed order, none for a rejected one — is a claim about the
			SERVICE, not about the seed, so those cases ask for an empty card and
			assert exactly what they always asserted. ]]
		startEarned = (opts or {}).startEarned,
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

--[[ THE NAV, AFTER §6. The shell is `Facet.Controls.TabView` now
	(framework-gaps-phase2 §6, the accessory-slot round): a section's button is a
	SEGMENT of the construct's one strip rather than a `Nav-<section>` Button this
	proof declared three times over. A section is therefore addressed by its INDEX
	in the proof's own `SECTIONS` order — the one part of the nav this file still
	owns — while the path ABOVE the segment is the placement policy's business and
	changes with the home. ]]
local SECTION_ORDER = { "menu", "favorites", "recipes", "stamps" }
local function navTail(section: string): string
	for index, name in SECTION_ORDER do
		if name == section then
			return `/Strip/Indicator/Options/Opt{index}`
		end
	end
	error(`no such section '{section}'`, 2)
end
local function navSection(path: string): string?
	if string.find(path, "/Nav/", 1, true) == nil or string.find(path, "/Strip/", 1, true) == nil then
		return nil
	end
	for index, name in SECTION_ORDER do
		local tail = `/Opt{index}`
		if string.sub(path, -#tail) == tail then
			return name
		end
	end
	return nil
end
local function isNavPath(path: string): boolean
	return navSection(path) ~= nil
end
-- the four homes the construct mounts its strip in, by tail
local RAIL = "/Nav/RailHome/then/Rail"
-- the top band RESERVES the trailing accessory's width (I-6), so the scroller the
-- tabs centre in is the box beside it rather than the whole band
local TOP_BAND = "/Nav/TopHome/then/TopBandCenter/TopBandBox/TopBand"
local BOTTOM_BAND = "/Nav/BottomHome/then/BottomDock/BottomBand"
local COMPACT_BAND = "/Nav/CompactHome/then/CompactDock/CompactBandCenter/CompactBand"

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
		expect(findNode(w, RAIL) ~= nil).toBe(true)
		expect(findNode(w, BOTTOM_BAND) == nil and findNode(w, COMPACT_BAND) == nil).toBe(true)
		expect(findNode(w, TOP_BAND) == nil).toBe(true)

		-- phone portrait: full bottom tab bar in the dock, rail gone
		w.env:set("viewportRect", PHONE)
		w.presenter.refresh()
		expect(findNode(w, RAIL) == nil).toBe(true)
		expect(findNode(w, BOTTOM_BAND) ~= nil).toBe(true)
		expect(findNode(w, "TabsFull") == nil).toBe(true) -- bottom bars speak the SHORT vocabulary
		expect(findNode(w, "/AboveBarSlot/AccessoryWhen/then/Accessory") ~= nil).toBe(true)

		-- phone landscape (roomy width, SHORT height): the same bar, inline
		-- form — and a CENTERED, HUGGING cluster, never a full-width stretch
		w.env:set("viewportRect", { x = 0, y = 0, w = 720, h = 360 })
		w.presenter.refresh()
		local compactPath = findNode(w, COMPACT_BAND .. "/Strip")
		expect(compactPath ~= nil).toBe(true)
		expect(findNode(w, BOTTOM_BAND) == nil).toBe(true)
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
		expect(findNode(w, TOP_BAND) ~= nil).toBe(true)
		expect(findNode(w, BOTTOM_BAND) == nil and findNode(w, COMPACT_BAND) == nil).toBe(true)
		expect(findNode(w, RAIL) == nil).toBe(true)
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
		local content = w.adapter.node(findNode(w, "/Nav/Content"))
		local tabsPath = findNode(w, BOTTOM_BAND .. "/Strip")
		local tabs = if tabsPath ~= nil then w.adapter.node(tabsPath) else nil
		local accessory = w.adapter.node(findNode(w, "/AboveBarSlot/AccessoryWhen/then/Accessory"))
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
			if isNavPath(path) then
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
		local rowPath = findNode(w, TOP_BAND .. "/Strip")
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
		-- an EMPTY card, deliberately: this is the accrual rule, and the shipped
		-- seed (one stamp short) would hide the arithmetic behind the redeem branch
		local w = world({ startEarned = 0 })
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
		-- from an EMPTY card plus ten earned, so `spent`/`unspent` below are the
		-- redemption's own arithmetic and not the seed's
		local w = world({ startEarned = 0 })
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
		expect(find(w, navTail("menu"))).toBeNil()
		expect(find(w, navTail("favorites"))).toBeNil()
		expect(find(w, navTail("stamps"))).toBeNil()
		expect(find(w, navTail("recipes"))).toBeNil()
		for _, path in w.report().focusPaths do
			expect(string.find(path, "/Favorite", 1, true)).toBeNil()
		end
		-- the row itself is still the shared one
		expect(find(w, "/Row-lantern-oolong/Line/Open") ~= nil).toBe(true)
		w.built.dispose()
	end)

	it("the CTA is always pay-shaped in the compact entry, even at ten stamps", function()
		local w = world({ viewport = PHONE, entry = "compact-link", startEarned = 0 })
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
		local w = world({ viewport = PHONE, startEarned = 0 })
		w.built.services.rewards.earn(3)
		step(w, "enterCompact", "copper-chai")
		w.presenter.refresh()
		expect(w.report().entry).toBe("compact-link")
		step(w, "enterFull")
		w.presenter.refresh()
		local r = w.report()
		expect(r.entry).toBe("full")
		expect(r.rewards.earned).toBe(3)
		expect(find(w, navTail("menu")) ~= nil).toBe(true)
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

	--[[ §6 THE POCKET IS A VERB ON A ROOMY SHAPE, and the migration onto
		`newTabView` had to keep it one. The construct writes its own selection
		Signal on activation, as every picker does, so the proof reconciles that
		write back against what `commands.selectSection` ACTUALLY did: Steam Stamps
		presents the rewards card on a wide screen and never swaps the section.
		Driven through the real activation closure, because "the strip set a Signal
		and the app set it back" is exactly the kind of claim a `steps` call cannot
		make. ]]
	it("the Steam Stamps tab PRESENTS the rewards card on a wide screen — it is not a destination", function()
		local w = world()
		expect(w.report().section).toBe("menu")
		local path = findNode(w, navTail("stamps"))
		expect(path ~= nil).toBe(true)
		w.adapter.tap(path :: string, { source = "pointer", pointer = "mouse" })
		w.presenter.refresh()
		-- the card is up...
		expect(w.report().surfaces.rewards).toBe(true)
		-- ...the section never moved, and neither did the strip's own selection
		expect(w.report().section).toBe("menu")
		expect(findNode(w, "/Tab-stamps/then/Body")).toBeNil()
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("...and on a COMPACT shape the same tab is a real destination", function()
		local w = world({ viewport = PHONE })
		local path = findNode(w, navTail("stamps"))
		expect(path ~= nil).toBe(true)
		w.adapter.tap(path :: string, { source = "pointer", pointer = "mouse" })
		w.presenter.refresh()
		expect(w.report().section).toBe("stamps")
		expect(findNode(w, "/Tab-stamps/then/Body") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("every verb in the loop is a real focusable, on every input class", function()
		local w = world()
		-- the shell: four nav stops and a row with its own heart
		expect(find(w, navTail("menu")) ~= nil).toBe(true)
		expect(find(w, navTail("favorites")) ~= nil).toBe(true)
		expect(find(w, navTail("recipes")) ~= nil).toBe(true)
		expect(find(w, navTail("stamps")) ~= nil).toBe(true)
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
				if navSection(path) == section then
					hit = true
				end
			end
			expect(`{section}:{hit}`).toBe(`{section}:true`)
		end
		-- (away) the ring holds MORE than the bar: content stops exist too
		local outside = false
		for path in seen do
			if not isNavPath(path) then
				outside = true
			end
		end
		expect(outside).toBe(true)
		-- (action) activating a tab through the engine's activation path works
		local fav = findNode(w, navTail("favorites"))
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

	--[[ ONE LADDER, NOT ONE NUMBER'S LADDER (ADR-0042).

		This proof owned its structural numbers as literals in
		`content/metrics.luau`, and exactly ONE of them climbed the ten-foot ladder:
		`gatherToggleAt` multiplied the gathered check's column by `metricScale` by
		hand, with a comment saying what it wanted instead — *"a name would be
		better — a dim's `px` takes one and re-resolves it every solve"*. The row
		thumbnail, the tile art, the card, the header art, the panes and the action
		band all stayed where a phone left them, so at three metres a 60px thumbnail
		sat in a row whose every theme-owned neighbour had grown by half.

		They are `app.sip.*` now, so the framework climbs it for all of them at
		once, and the toggle's hand transform is deleted rather than copied
		twenty-four times. ]]
	it("every structural number takes the ten-foot factor, not just the one with a helper", function()
		--[[ MEASURED ON THE PAINTED BOX FIRST, because that is the claim: the
			declaration was already right before this round, and a spec that only
			re-read the declaration would pass on a framework that scaled nothing. The
			list row's art plate is `app.sip.rowArt` on both axes. ]]
		local near = world()
		near.presenter.refresh()
		local nearPlate = findNode(near, "/Art/Plate")
		expect(nearPlate ~= nil).toBe(true)
		local nearBox = near.adapter.node(nearPlate :: string).rect
		expect(nearBox.h).toBe(60)
		near.built.dispose()

		local w = world()
		w.env:set("displaySize", "Large")
		w.env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		w.presenter.refresh()
		local farPlate = findNode(w, "/Art/Plate")
		expect(farPlate ~= nil).toBe(true)
		local farBox = w.adapter.node(farPlate :: string).rect
		expect(farBox.h).toBe(nearBox.h * 1.5)
		expect(farBox.w).toBe(nearBox.w * 1.5)

		local snap: any = w.env:get("themeMetrics"):get()
		local sip = snap.app.sip
		expect(sip.rowArt).toBe(90) -- 60 * 1.5
		expect(sip.tileArt).toBe(144) -- 96
		expect(sip.cardW).toBe(540) -- 360
		expect(sip.ctaBand).toBe(96) -- 64
		expect(sip.gatherToggle).toBe(144) -- 96, the one that already had a helper
		--[[ …and the two that are NOT lengths stay exactly where they are. A count
			of eight wisps is not twelve wisps at three metres, and a travel of 0.16
			of the backdrop's height is not 0.24 of it. The names carry that: the
			ten-foot classification reads every segment of an `app.*` path with the
			same vocabulary `controls.*` spends. ]]
		expect(sip.wispCount).toBe(8)
		expect(sip.wispTravelFraction).toBe(0.16)
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
		expect(findNode(w, TOP_BAND) ~= nil).toBe(true)
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
				if navSection(path) == section then
					hit = true
				end
			end
			expect(`{section}:{hit}`).toBe(`{section}:true`)
		end
		-- (action) ButtonA on the focused tab switches the section
		pad("DPadLeft")
		pad("DPadLeft") -- back to favorites
		expect(navSection(focused()) == "favorites").toBe(true)
		pad("ButtonA")
		expect(w.report().section).toBe("favorites")
		-- (away) DPadDown leaves the bar into the content below
		pad("DPadDown")
		expect(isNavPath(focused())).toBe(false)
		w.built.dispose()
	end)
end)

--[[ BACKDROP-FINDING SWEEP (task POP fix round 1, CRITICAL finding: the
	round-0 gate was never actually run against this reference app — grep
	alone found 11 `canvasGroup = true` sites here, unswept). Drives every
	named section, the blend detail, a botanical tile, the order/guard flow,
	and the rewards overlay, then reads the UNION of every coordinator's own
	`.findings()` (`tests/lib/backdrop_sweep.luau`). ]]
describe("Sipworks — backdrop-finding sweep (task POP)", function()
	it("every section, the blend detail, a botanical tile and the order/rewards overlays are clean", function()
		local backdropSweep = require("../lib/backdrop_sweep")
		local w: any
		local findings = backdropSweep.capture(function()
			w = world()
			for _, name in { "menu", "favorites", "recipes", "stamps" } do
				w.steps.section(w.built, name)
			end
			w.steps.section(w.built, "menu")
			w.steps.open(w.built, "lantern-oolong")
			w.steps.favorite(w.built, "lantern-oolong")
			w.steps.close()
			w.steps.tile(w.built, "oolong")
			w.steps.flip(w.built, "back")
			w.steps.cancelCard()
			w.steps.guard(w.built, "off")
			w.steps.order()
			w.steps.guardOk()
			w.steps.done()
			w.steps.stamps()
			w.steps.leaveStamps()
			w.presenter.refresh()
		end)
		expect(`{#findings} finding(s):\n{backdropSweep.describe(findings)}`).toBe("0 finding(s):\n")
		w.built.dispose()
		Facet.themes.declareApp("sip", nil)
	end)
end)

--[[ ── THE PLAYED TASK ──────────────────────────────────────────────────────────

	"Today's order" (docs/plans/example-games-and-standalones.md, "Sipworks: serve a
	customer and earn a reward"). What is pinned here is the LOOP, not the widgets:
	the seeded start, each step's state transition, the rejection detour that keeps
	every stamp, the completion state, and the reset returning every observable the
	report publishes.

	It is driven through the same commands the on-screen controls call, and the two
	verbs the task adds are driven through `adapter.driveActivate` — the closure the
	engine itself invokes — so "the button does this" is evidence rather than a
	claim about a step function. ]]
describe("Sipworks — the played task: seeded start, the loop, and the reset", function()
	local rewardsService = require("../../examples/reference/p3_sipworks/services/rewards") :: any
	local taskService = require("../../examples/reference/p3_sipworks/services/task") :: any

	-- press the real control, not the step behind it
	local function press(w: any, suffix: string): boolean
		local path = find(w, suffix)
		expect(`{suffix} is focusable: {path ~= nil}`).toBe(`{suffix} is focusable: true`)
		local ok = w.adapter.driveActivate(path :: string)
		w.presenter.refresh()
		return ok
	end

	-- the CTA press plus the counter's own reply window, which is what a player
	-- waits through
	local function placeOrder(w: any)
		step(w, "order")
		advance(w, 1)
	end

	it("the seeded start is ONE stamp short, and the opening screen says so", function()
		local w = world()
		local r = w.report()
		-- the seed itself
		expect(r.task.startEarned).toBe(rewardsService.THRESHOLD - 1)
		expect(r.rewards.earned).toBe(rewardsService.THRESHOLD - 1)
		expect(r.rewards.away).toBe(1)
		expect(r.rewards.canRedeem).toBe(false)
		expect(r.task.phase).toBe("order")
		expect(r.task.served).toBe(false)
		expect(r.task.redeemed).toBe(false)

		-- ...and the opening screen: the goal in one sentence, the progress as a
		-- number, and the next action by name
		expect(nodeTextAt(w, findNode(w, "/TaskStrip/TaskLabel") :: string)).toBe("Today's order")
		expect(nodeTextAt(w, findNode(w, "/TaskStrip/TaskProgress") :: string)).toBe("9 of 10 stamps")
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskGoal") :: string)).toBe(
			"Sipworks is a tea house. Pick a blend, serve it, and take a stamp — ten stamps is a free pour."
		)
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskNext") :: string)).toBe(
			"Choose a blend and place the order."
		)
		expect(nodeTextAt(w, find(w, "/TaskCard/TaskActive/then/TaskBody/TaskAct") :: string)).toBe(
			"Order Amber Harvest"
		)
		-- the completion state is NOT up yet
		expect(find(w, "/TaskCard/TaskDone/then/TaskDoneGroup/TaskDoneBody/TaskReset")).toBeNil()
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("the named first action opens the blend it names, through the row's own path", function()
		local w = world()
		expect(w.report().selectedBlendId).toBeNil()
		expect(press(w, "/TaskAct")).toBe(true)
		expect(w.report().selectedBlendId).toBe(taskService.FIRST_BLEND)
		expect(w.report().section).toBe("menu")
		-- the CTA the task sent the player to is the app's own order verb
		expect(nodeTextAt(w, find(w, "/Cta/Band/OrderCTA") :: string)).toBe("Place order — 49 Credits")
		w.built.dispose()
	end)

	it("a refused order explains itself, keeps every stamp, and the retry is the same verb", function()
		local w = world()
		press(w, "/TaskAct")
		placeOrder(w) -- attempt 1 is the counter's scripted refusal
		local r = w.report()
		expect(r.task.phase).toBe("rejected")
		expect(r.task.refused).toBe(true)
		-- PROGRESS IS UNTOUCHED: that is what "retry without losing progress" means
		expect(r.rewards.earned).toBe(rewardsService.THRESHOLD - 1)
		expect(r.task.stamps).toBe(rewardsService.THRESHOLD - 1)
		expect(r.task.served).toBe(false)
		-- ...and the explanation is on screen at the point of action, not only in
		-- the four-second toast that has already started expiring
		local notice = findNode(w, "/Cta/RejectNotice/then/RejectBox/Reject")
		expect(nodeTextAt(w, notice :: string)).toBe(
			"The counter turned that order away and charged nothing. "
				.. "Your stamps are safe — order again when you're ready."
		)
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskNext") :: string)).toBe(
			nodeTextAt(w, notice :: string)
		)

		-- the retry is the SAME control, and it clears the notice it answers
		placeOrder(w)
		local after = w.report()
		expect(after.task.refused).toBe(false)
		expect(findNode(w, "/Cta/RejectNotice/then/RejectBox/Reject")).toBeNil()
		expect(after.rewards.earned).toBe(rewardsService.THRESHOLD)
		w.built.dispose()
	end)

	it("one accepted order takes the last stamp and the task becomes the free pour", function()
		local w = world()
		press(w, "/TaskAct")
		placeOrder(w) -- refused
		placeOrder(w) -- accepted
		local r = w.report()
		expect(r.task.phase).toBe("redeem")
		expect(r.task.served).toBe(true)
		expect(r.task.stamps).toBe(rewardsService.THRESHOLD)
		expect(r.rewards.canRedeem).toBe(true)
		-- the CARD is what the stamp landed on: the last seal is stamped and fresh
		expect(r.rewards.filled).toBe(rewardsService.THRESHOLD)
		expect(r.rewards.newSlots[1]).toBe(rewardsService.THRESHOLD)
		-- ...and the task now names a DIFFERENT blend, because the step is "choose
		-- another blend and redeem"
		expect(r.task.ctaBlendId).toBe(taskService.FREE_POUR_BLEND)
		expect(r.task.ctaBlendId ~= taskService.FIRST_BLEND).toBe(true)
		step(w, "done")
		expect(nodeTextAt(w, find(w, "/TaskCard/TaskActive/then/TaskBody/TaskAct") :: string)).toBe(
			"Redeem with Mistral Mint"
		)
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskNext") :: string)).toBe(
			"Your card is full. Choose another blend and redeem the free pour."
		)
		w.built.dispose()
	end)

	it("redeeming the free pour ends in an unmistakable completion state with one reset", function()
		local w = world()
		press(w, "/TaskAct")
		placeOrder(w)
		placeOrder(w)
		step(w, "done")
		press(w, "/TaskAct") -- the second blend
		expect(w.report().selectedBlendId).toBe(taskService.FREE_POUR_BLEND)
		placeOrder(w)
		local r = w.report()
		expect(r.task.phase).toBe("done")
		expect(r.task.redeemed).toBe(true)
		expect(r.order.mode).toBe("redeem")
		expect(r.rewards.spent).toBe(rewardsService.REDEEM_COST)

		step(w, "done")
		-- the completion state SAYS what was accomplished, and it replaces the task
		-- rather than standing beside it
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskDone/then/TaskDoneGroup/TaskDoneBody/TaskDoneTitle") :: string)).toBe(
			"A free pour, on the house."
		)
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskDone/then/TaskDoneGroup/TaskDoneBody/TaskDoneCopy") :: string)).toBe(
			"One order filled the stamp card, and all ten stamps went back over the counter for a free pour."
		)
		expect(findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskNext")).toBeNil()
		expect(findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskAct")).toBeNil()
		-- the strip says it too, so the state is legible from every section
		expect(nodeTextAt(w, findNode(w, "/TaskStrip/TaskLabel") :: string)).toBe("A free pour, on the house.")
		-- ONE reset control
		expect(nodeTextAt(w, find(w, "/TaskDoneBody/TaskReset") :: string)).toBe("Serve another customer")
		-- ...and the completion is announced on the feedback bus, on the frame the
		-- order confirmed
		local celebrated = false
		for _, event in r.feedback do
			if event.type == "celebrate" then
				celebrated = true
			end
		end
		expect(celebrated).toBe(true)
		w.built.dispose()
	end)

	it("'Serve another customer' returns EVERY observable to the seeded start", function()
		local w = world()
		local opening = w.built.dump()
		local openingReport = w.report()
		press(w, "/TaskAct")
		placeOrder(w)
		placeOrder(w)
		step(w, "done")
		press(w, "/TaskAct")
		placeOrder(w)
		step(w, "done")
		-- ...and browse a little, so the reset is not only unwinding the loop
		step(w, "favorite", "lantern-oolong")
		step(w, "search", "mint")
		step(w, "section", "favorites")
		expect(w.built.dump()).never().toBe(opening)

		expect(press(w, "/TaskDoneBody/TaskReset")).toBe(true)
		expect(w.built.dump()).toBe(opening)
		local r = w.report()
		expect(r.task.phase).toBe("order")
		expect(r.task.stamps).toBe(rewardsService.THRESHOLD - 1)
		expect(r.rewards.earned).toBe(openingReport.rewards.earned)
		expect(r.rewards.spent).toBe(openingReport.rewards.spent)
		expect(r.order.mode).toBe(openingReport.order.mode)
		expect(r.section).toBe("menu")
		expect(r.search).toBe("")
		expect(#r.favorites).toBe(#openingReport.favorites)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("'What this shows' is collapsed by default and comes AFTER the play task", function()
		local w = world()
		expect(findNode(w, "/TaskCard/TaskShowsWhen/then/TaskShowsGroup/TaskShowsBody")).toBeNil()
		-- ...and it is reachable, after the verb it must not stand in front of
		local order = w.report().focusPaths
		local actAt, showsAt = nil :: number?, nil :: number?
		for index, path in order do
			if string.sub(path, -8) == "/TaskAct" then
				actAt = index
			elseif string.sub(path, -10) == "/TaskShows" then
				showsAt = index
			end
		end
		expect(`act={actAt ~= nil} shows={showsAt ~= nil}`).toBe("act=true shows=true")
		expect((actAt :: number) < (showsAt :: number)).toBe(true)

		expect(press(w, "/TaskShows")).toBe(true)
		local body = findNode(w, "/TaskCard/TaskShowsWhen/then/TaskShowsGroup/TaskShowsBody")
		expect(body ~= nil).toBe(true)
		expect(string.find(nodeTextAt(w, body :: string) :: string, "sidebar", 1, true) ~= nil).toBe(true)
		w.built.dispose()
	end)

	it("the task is placed ON the app: the catalogue and every destination survive it", function()
		local w = world()
		-- the whole menu is still there under the card
		expect(w.report().visible.menu).toBe(#blends.list)
		expect(find(w, "/Row-lantern-oolong/Line/Open") ~= nil).toBe(true)
		-- ...as are search and all four nav destinations
		expect(find(w, "/SearchBar/Search/Field") ~= nil).toBe(true)
		for _, section in SECTION_ORDER do
			expect(`{section}: {find(w, navTail(section)) ~= nil}`).toBe(`{section}: true`)
		end
		-- ...and the task is in every section, so browsing away never loses it
		for _, section in SECTION_ORDER do
			step(w, "section", section)
			expect(`{section} strip: {findNode(w, "/TaskStrip/TaskLabel") ~= nil}`).toBe(`{section} strip: true`)
		end
		w.built.dispose()
	end)

	it("the compact-link entry carries NO task: there is no rewards context to finish it in", function()
		-- spec §11: the deep-link shell has no stamps, no favourites and a
		-- pay-shaped CTA, so a task line promising a free pour would be a dead verb
		local w = world({ viewport = PHONE, entry = "compact-link" })
		expect(findNode(w, "/TaskStrip/TaskLabel")).toBeNil()
		expect(findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskAct")).toBeNil()
		expect(w.report().task.phase).toBe("order")
		w.built.dispose()
	end)

	it("on a landscape phone the strip yields and the CARD still carries the whole task", function()
		-- `isShort` is the one shape where even one line is more than the nav can
		-- spare under the thicker packages (see `views/task.luau`). Yielding is not
		-- losing the task: the card is still the first thing on the page, with the
		-- goal, the progress, the next action and the verb.
		local w = world({ viewport = { x = 0, y = 0, w = 640, h = 320 }, scrollBar = 8 })
		expect(w.built.app.cond.isShort:get()).toBe(true)
		expect(findNode(w, "/TaskStripWhen/then/TaskStrip")).toBeNil()
		expect(findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskGoal") ~= nil).toBe(true)
		expect(nodeTextAt(w, findNode(w, "/TaskCard/TaskActive/then/TaskBody/TaskNext") :: string)).toBe(
			"Choose a blend and place the order."
		)
		expect(find(w, "/TaskCard/TaskActive/then/TaskBody/TaskAct") ~= nil).toBe(true)
		expect(#w.report().diagnostics).toBe(0)
		w.built.dispose()
	end)

	it("the strip costs ONE line box at every preference and in both locales", function()
		for _, locale in { "en", "xa" } do
			for _, offset in { 0, 4, 10, 14 } do
				local w = world({ viewport = { x = 0, y = 0, w = 320, h = 640 }, scrollBar = 8 })
				w.env:set("preferredTextOffset", offset)
				step(w, "locale", locale)
				local strip = w.adapter.node(findNode(w, "/TaskStripWhen/then/TaskStrip") :: string)
				local label = w.adapter.node(findNode(w, "/TaskStrip/TaskLabel") :: string)
				-- the strip is its one line plus its own padding, never a paragraph:
				-- a band that grew with the copy is what pushed the nav's content box
				-- to 4px on this very viewport
				expect(`{locale}+{offset}: {strip.rect.h <= label.rect.h * 2}`).toBe(`{locale}+{offset}: true`)
				expect(`{locale}+{offset} diagnostics: {#w.report().diagnostics}`).toBe(
					`{locale}+{offset} diagnostics: 0`
				)
				w.built.dispose()
			end
		end
	end)
end)

--[[ ── NO PROOF JARGON ON THE PLAYER SURFACE ───────────────────────────────────

	The plan's own line: "Remove test-only jargon and raw counters from the player
	surface unless the number is the lesson." `Sipworks.title` used to read
	"Sipworks (reference proof RA-P3)", which is a stage id in the one field a
	curated standalone place's chrome would paint first. ]]
describe("Sipworks — the player surface names no stage, proof or ledger", function()
	local JARGON = { "proof", "stage", "gate", "ledger", "RA%-P", "clean%-room" }

	it("the module title is the place's name and nothing else", function()
		expect(proof.title).toBe("Sipworks")
	end)

	it("no locale string a player can read carries test vocabulary", function()
		local offenders: { string } = {}
		local function scan(key: string, value: string)
			for _, pattern in JARGON do
				if string.find(string.lower(value), string.lower(pattern)) ~= nil then
					table.insert(offenders, `{key} = {value}`)
				end
			end
		end
		for key, value in strings.byLocale.en do
			if type(value) == "string" then
				scan(key, value)
			else
				for form, text in value do
					scan(`{key}.{form}`, text)
				end
			end
		end
		table.sort(offenders)
		expect(table.concat(offenders, "; ")).toBe("")
	end)
end)

--[[ ── THE STANDALONE AND THE SHOWCASE ARE ONE MODULE ───────────────────────────

	Both `Facet-Ref-Sipworks.rbxl` and the gallery boot the SAME scenario file,
	which resolves the SAME `FacetReference.p3_sipworks` module — there is no
	simplified fork of this app anywhere, and the drift this pins is the one that
	would be invisible until somebody opened the place. Read from source text
	because neither the scenario registry nor a Rojo project can be required
	headlessly. ]]
describe("Sipworks — the standalone place and the showcase scenario import one module", function()
	local fs = require("@lune/fs")

	it("the scenario resolves the reference module and forks nothing", function()
		local source = fs.readFile("examples/gallery/scenarios/ref_sipworks.luau")
		expect(string.find(source, 'FindFirstChild("p3_sipworks")', 1, true) ~= nil).toBe(true)
		expect(string.find(source, "ctx.referenceModules", 1, true) ~= nil).toBe(true)
		-- ...and it names no OTHER proof, which is what a copy-paste fork looks like
		for _, other in { "p1_glade", "p2_cartwheel", "p4_foyer", "p5_wardrobe" } do
			expect(`{other}: {string.find(source, other, 1, true) ~= nil}`).toBe(`{other}: false`)
		end
	end)

	it("the standalone place maps the same two folders the gallery does", function()
		local place = fs.readFile("tools/build_reference_places.sh")
		expect(string.find(place, '"ref_sipworks|Facet-Ref-Sipworks"', 1, true) ~= nil).toBe(true)
		local gallery = fs.readFile("examples/gallery.project.json")
		-- the tail of the mapping only: the place builder writes its project through
		-- a bash heredoc, so its `$path` keys arrive escaped as `\$path`
		for _, mapping in { 'path": "gallery/scenarios"', 'path": "reference"' } do
			expect(`place {mapping}: {string.find(place, mapping, 1, true) ~= nil}`).toBe(`place {mapping}: true`)
			expect(`gallery {mapping}: {string.find(gallery, mapping, 1, true) ~= nil}`).toBe(`gallery {mapping}: true`)
		end
	end)

	it("exactly one directory on disk IS this app", function()
		local hits: { string } = {}
		for _, entry in fs.readDir("examples/reference") do
			if fs.isFile(`examples/reference/{entry}/init.luau`) then
				local source = fs.readFile(`examples/reference/{entry}/init.luau`)
				if string.find(source, "Sipworks.build", 1, true) ~= nil then
					table.insert(hits, entry)
				end
			end
		end
		expect(table.concat(hits, ",")).toBe("p3_sipworks")
	end)
end)

--[[ THE PROOF'S APP NAMESPACE DOES NOT OUTLIVE THIS FILE (ADR-0042).

	`build` declares `app.sip.*` PROCESS-WIDE, and a spec file that walked away
	would leave the group standing for every later file in this one Lune run —
	which makes suite ORDER quietly load-bearing, and a later case's "nobody
	declared this" assertion depend on which file happened to run first. Retiring
	it here is the teardown; asserting it is what stops the teardown from silently
	becoming a no-op. ]]
describe("Sipworks — the declaration does not leak into the rest of the suite", function()
	it("retires its app namespace", function()
		Facet.themes.declareApp("sip", nil)
		expect(Facet.themes.appMetrics()["sip"]).toBe(nil)
		expect(themeSnapshot.isMetricPath("app.sip.rowArt")).toBe(false)
	end)
end)
