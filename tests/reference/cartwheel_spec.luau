--!strict
-- Reference proof "Cartwheel" — E1 loop pins (reference-app-validation).
--
-- WHAT THIS FILE IS FOR. The proof's whole representative loop (RA-P2) has to be
-- drivable headlessly through the public controller/presenter API, and every
-- state it can reach — success, rejection, interruption, empty, reset — has to be
-- reachable through on-screen controls alone. These cases drive it that way: they
-- tap real nodes and call the same actions the buttons call, never a private
-- shortcut, so a case passing means a player could have done it.
--
-- The pins the package brief names, in order: every status transition, countdown
-- persistence across screen swaps, both purchase outcomes, gate/lock states,
-- sort/search derivations, arrival insertion order, reset determinism (same seed
-- + same steps => identical dump), and the fallback plate when no stage host.
local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../../src")
-- the metric-name vocabulary, read directly: the teardown below asserts that this
-- proof's group really left it
local themeSnapshot = require("../../src/themes/snapshot") :: any
local fake_target = require("../lib/fake_target")
local standard_icons = require("../../src/themes/standard_icons")

local proof = require("../../examples/reference/p2_cartwheel") :: any
local art = require("../../examples/reference/p2_cartwheel/content/art")
local data = require("../../examples/reference/p2_cartwheel/content/data")
local strings = require("../../examples/reference/p2_cartwheel/content/strings")

-- ---- the harness ------------------------------------------------------------
-- The same wiring a client bootstrap uses, minus the Roblox-only adapters. The
-- proof PRESENTS ITSELF (it needs its own controller for the stage seam), so the
-- harness never presents a second time — it only drives.

type World = { core: any, env: any, adapter: any, presenter: any, system: any, built: any }

local function makeWorld(opts: any?): World
	local options: any = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.width or 1200, h = options.height or 800 })
	if options.reducedMotion then
		env:set("reducedMotion", true)
	end
	if options.locale ~= nil then
		env:set("locale", options.locale)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	if options.noStageHost then
		-- an adapter WITHOUT the optional stage seam. `controller.stageHost`
		-- answers nil for one, which is the capability-absent world the proof's
		-- fallback plate exists for.
		adapter.stageHost = nil
	end
	local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
	local built = proof.build(Facet, core, {
		env = env,
		actionSystem = system,
		presenter = presenter,
		adapter = adapter,
		seed = options.seed,
		locale = options.locale,
	})
	presenter.refresh()
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system, built = built }
end

--[[ …AND THE PROOF'S APP NAMESPACE GOES WITH IT (ADR-0042). `build` declares
	`app.cartwheel.*` process-wide, and a spec that walked away would leave the
	group standing for every later file in this one Lune process — which makes
	suite ORDER quietly load-bearing, and a later case's "nobody declared this"
	assertion depend on which file ran first. Retiring it here means every case in
	this file declares its own, and nothing outside it inherits one. ]]
local function closeWorld(world: World)
	world.built.dispose()
	Facet.themes.declareApp("cartwheel", nil)
end

-- a deterministic string form of a report: keys sorted, so two runs of the same
-- steps are comparable as TEXT and a difference names itself
local function stable(value: any): string
	local kind = type(value)
	if kind ~= "table" then
		return if kind == "number" then string.format("%.6g", value) else tostring(value)
	end
	-- the keys are kept as they ARE and only SORTED by name: stringifying them
	-- first and indexing with the string reads every array element as nil, which
	-- makes two different arrays of the same length compare equal (found by a
	-- sort test that could not fail, 2026-08-08)
	local keys: { any } = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: any, b: any): boolean
		return tostring(a) < tostring(b)
	end)
	local parts: { string } = {}
	for _, key in keys do
		table.insert(parts, tostring(key) .. "=" .. stable((value :: any)[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function idsOf(rows: { any }): { number }
	local out: { number } = {}
	for _, row in rows do
		table.insert(out, row.id)
	end
	return out
end

describe("Cartwheel reference proof — module contract", function()
	it("exposes the scenario build contract", function()
		expect(type(proof.build)).toBe("function")
	end)

	it("mounts headlessly, presents itself, and leaves the core error-free", function()
		local world = makeWorld()
		expect(world.built.handle ~= nil).toBe(true)
		expect(world.adapter.node(world.built.paths.screen) ~= nil).toBe(true)
		expect(world.core:lastError()).toBeNil()
		closeWorld(world)
	end)

	it("declares its stage content against the Stage node's own path", function()
		local world = makeWorld()
		local content = world.built.stageContent[world.built.paths.stage]
		expect(content ~= nil).toBe(true)
		-- camera and lighting are KEYED tables (the seam refuses array form);
		-- part vectors are arrays
		expect(type(content.camera.position.x)).toBe("number")
		expect(type(content.camera.lookAt.y)).toBe("number")
		expect(type(content.lighting.ambient.r)).toBe("number")
		expect(#content.parts > 0).toBe(true)
		expect(#content.parts[1].size).toBe(3)
		expect(#content.parts[1].cframe.pos).toBe(3)
		closeWorld(world)
	end)

	it("borrows only art the framework actually ships (ids pinned)", function()
		for name, mark in art.marks :: any do
			local entry = (standard_icons.ART :: any)[mark.iconName]
			expect(entry ~= nil).toBe(true)
			expect(mark.image).toBe(entry.contentId)
			expect(type(name)).toBe("string")
		end
	end)
end)

describe("Cartwheel — the shell", function()
	it("opens on The Cart with the nav lane showing and no pushed detail", function()
		local world = makeWorld()
		local shell = world.built.screens.shell.dump()
		expect(shell.section).toBe("cart")
		expect(shell.openBrew).toBe(0)
		expect(shell.navVisible).toBe(true)
		expect(shell.detailVisible).toBe(true)
		expect(world.adapter.node(world.built.paths.cart) ~= nil).toBe(true)
		closeWorld(world)
	end)

	it("a sidebar row selects its section — through the row, not the signal", function()
		local world = makeWorld()
		world.adapter.tap(world.built.paths.sidebarFull .. "/Row_brews")
		world.presenter.refresh()
		expect(world.built.screens.shell.dump().section).toBe("brews")
		expect(world.adapter.node(world.built.paths.brews) ~= nil).toBe(true)
		closeWorld(world)
	end)

	it("SELECTION RESETS PUSHED DETAIL: a sidebar change lands on the section root", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "101")
		expect(world.built.screens.shell.dump().openBrew).toBe(101)
		world.adapter.tap(world.built.paths.sidebarFull .. "/Row_cart")
		world.presenter.refresh()
		local shell = world.built.screens.shell.dump()
		expect(shell.section).toBe("cart")
		expect(shell.openBrew).toBe(0)
		closeWorld(world)
	end)

	it("compact stacks: picking a section empties the nav lane, Back pops one level", function()
		local world = makeWorld({ width = 420 })
		expect(world.built.screens.shell.dump().compact).toBe(true)
		expect(world.built.screens.shell.dump().detailVisible).toBe(false)
		world.built.steps.section(world.built, "brews")
		local pushed = world.built.screens.shell.dump()
		expect(pushed.navVisible).toBe(false)
		expect(pushed.detailVisible).toBe(true)
		expect(pushed.header).toBe(true)
		-- depth 2: a brew detail pops before the section does
		world.built.steps.open_brew(world.built, "101")
		expect(world.built.steps.back(world.built).consumed).toBe(true)
		expect(world.built.screens.shell.dump().openBrew).toBe(0)
		expect(world.built.steps.back(world.built).consumed).toBe(true)
		expect(world.built.screens.shell.dump().navVisible).toBe(true)
		-- ...and at the root Cancel is a no-op, never a dismissal
		expect(world.built.steps.back(world.built).consumed).toBe(false)
		closeWorld(world)
	end)
end)

describe("Cartwheel — every section mounts", function()
	it("visits all nine and leaves the core error-free, in both locales", function()
		local sections = {
			{ "cart", "cart" },
			{ "brews", "brews" },
			{ "chatter", "chatter" },
			{ "ledger", "ledger" },
			{ "potions", "potions" },
			{ "workbench", "workbench" },
			{ "topfive", "topfive" },
			{ "plaza:gullsgate", "plaza" },
			{ "plaza:emberfall", "plaza" },
		}
		for _, locale in { "en", "xa" } do
			local world = makeWorld({ locale = locale })
			for _, entry in sections do
				world.built.steps.section(world.built, entry[1])
				expect(world.adapter.node((world.built.paths :: any)[entry[2]]) ~= nil).toBe(true)
				expect(world.core:lastError()).toBeNil()
			end
			closeWorld(world)
		end
	end)
end)

describe("Cartwheel — brews: modes, search, sort", function()
	it("regular mounts the table; compact mounts the sectioned list", function()
		local wide = makeWorld()
		wide.built.steps.section(wide.built, "brews")
		expect(wide.adapter.node(wide.built.paths.brews .. "/Body/TableWhen/then/TableHost/BrewTable") ~= nil).toBe(
			true
		)
		expect(wide.adapter.node(wide.built.paths.brews .. "/Body/ListWhen/then/ListHost/List")).toBe(nil)
		closeWorld(wide)

		local narrow = makeWorld({ width = 420 })
		narrow.built.steps.section(narrow.built, "brews")
		expect(narrow.adapter.node(narrow.built.paths.brews .. "/Body/ListWhen/then/ListHost/List") ~= nil).toBe(true)
		expect(narrow.adapter.node(narrow.built.paths.brews .. "/Body/TableWhen/then/TableHost/BrewTable")).toBe(nil)
		closeWorld(narrow)
	end)

	it("the DEFAULT SORT is Status ascending, ties Placed descending", function()
		local world = makeWorld()
		local dump = world.built.steps.sort ~= nil and world.built.screens.brews.dump()
		expect(dump.sort.column).toBe("status")
		expect(dump.sort.ascending).toBe(true)
		local rows = world.built.screens.brews.rows:get() :: any
		-- every New brew precedes every Ready one...
		local lastNew, firstReady = 0, math.huge
		for index, brew in rows do
			if brew.status == "new" then
				lastNew = math.max(lastNew, index)
			elseif brew.status == "ready" then
				firstReady = math.min(firstReady, index)
			end
		end
		expect(lastNew < firstReady).toBe(true)
		-- ...and inside a status group the newest placement comes first
		expect(rows[1].placedAt >= rows[2].placedAt).toBe(true)
		closeWorld(world)
	end)

	it("sorting by a column cycles it and re-derives the order", function()
		local world = makeWorld()
		local before = idsOf(world.built.screens.brews.rows:get() :: any)
		local ascending = world.built.steps.sort(world.built, "bottles")
		expect(ascending.sort.column).toBe("bottles")
		expect(ascending.sort.ascending).toBe(true)
		local rows = world.built.screens.brews.rows:get() :: any
		expect(rows[1].bottles <= rows[#rows].bottles).toBe(true)
		local descending = world.built.steps.sort(world.built, "bottles")
		expect(descending.sort.ascending).toBe(false)
		local flipped = world.built.screens.brews.rows:get() :: any
		expect(flipped[1].bottles >= flipped[#flipped].bottles).toBe(true)
		expect(#before > 0).toBe(true)
		closeWorld(world)
	end)

	it("search matches the brew number, its potions AND their ingredients", function()
		local world = makeWorld()
		local all = #(world.built.screens.brews.rows:get() :: any)
		local byNumber = world.built.steps.search(world.built, "101")
		expect(byNumber.rows).toBe(1)
		expect(byNumber.first).toBe(101)

		-- a potion name filters to the brews that carry it, and never to none
		local target = world.built.services.orders.byId(101)
		local potion = data.potionById(target.items[1].potion)
		local byPotion = world.built.steps.search(world.built, potion.name)
		expect(byPotion.rows > 0).toBe(true)
		expect(byPotion.rows < all).toBe(true)

		-- an ingredient of that potion reaches it too (the reference searched the
		-- id alone; spec §6 completes it)
		local ingredient = data.ingredientById(potion.base)
		local byIngredient = world.built.steps.search(world.built, ingredient.name)
		expect(byIngredient.rows > 0).toBe(true)

		local cleared = world.built.steps.search(world.built, "")
		expect(cleared.rows).toBe(all)
		closeWorld(world)
	end)

	it("the sectioned list omits empty status groups and heads the rest", function()
		local world = makeWorld({ width = 420 })
		world.built.steps.section(world.built, "brews")
		local entries = world.built.screens.brews.listEntries:get() :: any
		local headings: { string } = {}
		for _, entry in entries do
			if entry.kind == "heading" then
				table.insert(headings, entry.status)
			end
		end
		-- the seeded backlog is New + Ready only, so Brewing and Done have no
		-- heading at all until something enters them
		expect(#headings).toBe(2)
		expect(headings[1]).toBe("new")
		expect(headings[2]).toBe("ready")
		closeWorld(world)
	end)

	it("BULK COMPLETE EXISTS IN LIST MODE TOO (the reference's table-only gap)", function()
		local world = makeWorld({ width = 420 })
		world.built.steps.section(world.built, "brews")
		world.built.screens.brews.selectionMode:set(true)
		world.built.screens.brews.listSelected:set({ ["101"] = true, ["102"] = true })
		local result = world.built.steps.collect_selected(world.built)
		expect(#result.collected).toBe(2)
		expect(world.built.services.orders.statusOf(101)).toBe("done")
		expect(world.built.services.orders.statusOf(102)).toBe("done")
		-- the celebration opens for the FIRST of the batch
		expect(result.celebration.open).toBe(true)
		expect(result.celebration.brew).toBe(101)
		closeWorld(world)
	end)

	it("an empty search says so rather than showing an empty page", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "brews")
		local none = world.built.steps.search(world.built, "zzzz-no-such-brew")
		expect(none.rows).toBe(0)
		expect(none.entries).toBe(0)
		local empty = world.built.paths.brews .. "/Body/EmptyWhen/then/Empty"
		expect(world.adapter.node(empty) ~= nil).toBe(true)
		expect(world.adapter.node(empty).props.text).toBe("No brews match that search.")
		expect(world.core:lastError()).toBeNil()
		closeWorld(world)
	end)

	it("Cancel exits selection mode before it pops navigation", function()
		local world = makeWorld({ width = 420 })
		world.built.steps.section(world.built, "brews")
		world.built.screens.brews.selectionMode:set(true)
		expect(world.built.steps.back(world.built).consumed).toBe(true)
		expect(world.built.screens.brews.dump().selectionMode).toBe(false)
		-- the section is still pushed: Cancel consumed the mode, not the level
		expect(world.built.screens.shell.dump().detailVisible).toBe(true)
		closeWorld(world)
	end)
end)

describe("Cartwheel — the status machine", function()
	it("New -> Brewing -> Done through the one primary control", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "101")
		expect(world.built.screens.brewDetail.dump().status).toBe("new")

		local brewing = world.built.steps.advance_status(world.built)
		expect(brewing.status).toBe("brewing")
		expect(brewing.remaining ~= nil).toBe(true)

		local done = world.built.steps.advance_status(world.built)
		expect(done.status).toBe("done")
		expect(done.remaining).toBeNil()
		closeWorld(world)
	end)

	it("a seeded Ready brew collects straight to Done", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "110")
		expect(world.built.screens.brewDetail.dump().status).toBe("ready")
		expect(world.built.steps.advance_status(world.built).status).toBe("done")
		closeWorld(world)
	end)

	it("collecting an already-collected brew is REJECTED, with copy, and reverts", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "110")
		world.built.steps.advance_status(world.built)
		expect(world.built.services.orders.statusOf(110)).toBe("done")

		-- the optimistic write lands, the decision refuses it, and the revert puts
		-- the record back where it was
		world.built.app.actions.collectBrews({ 110 })
		expect(world.built.commands.status("brew:110"):get()).toBe("pending")
		world.built.steps.advance(world.built, "0.3")
		expect(world.built.commands.status("brew:110"):get()).toBe("rejected")
		expect(world.built.commands.reason("brew:110"):get()).toBe("Brew already collected")
		expect(world.built.services.orders.statusOf(110)).toBe("done")

		local log = world.built.commands.dump()
		expect(log[#log].ok).toBe(false)
		expect(log[#log].reason).toBe("reject.collected")
		closeWorld(world)
	end)

	it("the command's pending state is REAL: the control disables while it runs", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "101")
		world.built.app.actions.startBrew(101)
		expect(world.built.screens.brewDetail.dump().pending).toBe(true)
		world.built.steps.advance(world.built, "0.3")
		expect(world.built.screens.brewDetail.dump().pending).toBe(false)
		expect(world.built.screens.brewDetail.dump().status).toBe("brewing")
		closeWorld(world)
	end)

	it("THE COUNTDOWN SURVIVES NAVIGATION (the service owns the fact, not the view)", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "101")
		world.built.steps.advance_status(world.built)
		world.built.steps.advance(world.built, "10")
		local before = world.built.screens.brewDetail.dump()
		expect(before.status).toBe("brewing")
		expect(before.remaining).toBeLessThan(51)

		-- leave the screen entirely (the detail unmounts) and come back
		world.built.steps.section(world.built, "cart")
		expect(world.adapter.node(world.built.paths.brewDetail)).toBe(nil)
		world.built.steps.advance(world.built, "5")
		world.built.steps.open_brew(world.built, "101")
		local after = world.built.screens.brewDetail.dump()
		expect(after.status).toBe("brewing")
		expect(after.remaining).toBeLessThan(before.remaining)
		expect(after.remaining).toBeCloseTo(before.remaining - 5, 0.6)
		closeWorld(world)
	end)

	it("at zero the countdown says Ready to finish and the status does NOT advance", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "101")
		world.built.steps.advance_status(world.built)
		world.built.steps.advance(world.built, "60")
		local dump = world.built.screens.brewDetail.dump()
		expect(dump.remaining).toBe(0)
		expect(dump.status).toBe("brewing")
		expect(dump.countdown).toBe("Ready to finish")
		closeWorld(world)
	end)

	it("the countdown wears ONE time form: a depleting M:SS", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "101")
		world.built.steps.advance_status(world.built)
		world.built.steps.advance(world.built, "9.7")
		expect(world.built.screens.brewDetail.dump().countdown).toBe("0:50 left")
		closeWorld(world)
	end)
end)

describe("Cartwheel — Cancel is really wired (the contribution, not the function)", function()
	it("ButtonB pops one compact level and is a NO-OP at the root", function()
		local world = makeWorld({ width = 420 })
		world.built.steps.section(world.built, "brews")
		expect(world.built.screens.shell.dump().detailVisible).toBe(true)

		-- the gamepad verb, through the action system the presenter binds
		world.system.deviceKey("ButtonB", true)
		world.system.deviceKey("ButtonB", false)
		world.presenter.refresh()
		expect(world.built.screens.shell.dump().navVisible).toBe(true)

		-- at the root there is nothing to pop, and `cancelPolicy = "none"` means
		-- the surface must not dismiss itself either
		world.system.deviceKey("ButtonB", true)
		world.system.deviceKey("ButtonB", false)
		world.presenter.refresh()
		expect(world.adapter.node(world.built.paths.screen) ~= nil).toBe(true)
		expect(world.presenter.depth() > 0).toBe(true)
		closeWorld(world)
	end)
end)

describe("Cartwheel — a rejection is never silent", function()
	it("presents a toast carrying the specific reason", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "110")
		world.built.steps.advance_status(world.built)
		world.built.steps.dismiss_celebration(world.built)
		world.built.app.actions.collectBrews({ 110 })
		world.built.steps.advance(world.built, "0.3")

		local toastText: string? = nil
		for _, path in world.adapter.paths() do
			if string.find(path, "CartwheelToast", 1, true) ~= nil and string.sub(path, -4) == "Body" then
				toastText = world.adapter.node(path).props.text
			end
		end
		expect(toastText).toBe("Brew already collected")
		closeWorld(world)
	end)
end)

describe("Cartwheel — the completion celebration", function()
	it("opens on the confirming frame and closes on Done", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "110")
		expect(world.built.screens.celebration.dump().open).toBe(false)
		world.built.steps.advance_status(world.built)
		local open = world.built.screens.celebration.dump()
		expect(open.open).toBe(true)
		expect(open.brew).toBe(110)
		-- the modal is a real presented surface with its own trap
		expect(world.adapter.node("/CartwheelCelebration/Group/Card/Done") ~= nil).toBe(true)
		world.built.steps.dismiss_celebration(world.built)
		expect(world.built.screens.celebration.dump().open).toBe(false)
		closeWorld(world)
	end)

	it("the scripted beats run in order and a mid-sequence dismissal interrupts", function()
		local world = makeWorld()
		world.built.steps.open_brew(world.built, "110")
		world.built.steps.advance_status(world.built)
		expect(world.built.screens.celebration.dump().cork).toBe(false)
		-- beat 0.75: the cork enters
		world.presenter.tick(0.8)
		expect(world.built.screens.celebration.dump().cork).toBe(true)
		-- dismissing mid-timeline runs the remaining terminals rather than
		-- leaving the sequence half-painted
		world.built.steps.dismiss_celebration(world.built)
		expect(world.built.screens.celebration.dump().open).toBe(false)
		expect(world.core:lastError()).toBeNil()
		closeWorld(world)
	end)

	it("a celebrate event reaches the feedback bus", function()
		local world = makeWorld()
		local seen: { string } = {}
		local unsubscribe = world.presenter.onFeedback(function(event: any)
			table.insert(seen, event.type)
		end)
		world.built.steps.open_brew(world.built, "110")
		world.built.steps.advance_status(world.built)
		world.presenter.tick(2)
		unsubscribe()
		local sawCelebrate, sawCommit = false, false
		for _, kind in seen do
			sawCelebrate = sawCelebrate or kind == "celebrate"
			sawCommit = sawCommit or kind == "commit"
		end
		expect(sawCommit).toBe(true)
		expect(sawCelebrate).toBe(true)
		closeWorld(world)
	end)
end)

describe("Cartwheel — scripted arrivals", function()
	it("arrive in id order at seeded intervals and then stop", function()
		local world = makeWorld()
		expect(world.built.services.orders.dump().count).toBe(24)
		world.built.steps.advance(world.built, "10")
		local early = world.built.services.orders.dump()
		expect(#early.arrivals > 0).toBe(true)
		-- INSERTION ORDER: strictly ascending, one per scheduled interval
		for index = 2, #early.arrivals do
			expect(early.arrivals[index]).toBe(early.arrivals[index - 1] + 1)
		end
		expect(early.arrivals[1]).toBe(125)

		-- and the newest is at the FRONT of the list the dashboard reads
		local rows = world.built.services.orders.brews:get() :: any
		expect(rows[1].id).toBe(early.arrivals[#early.arrivals])

		-- twenty, then the cart goes quiet
		world.built.steps.advance(world.built, "500")
		local late = world.built.services.orders.dump()
		expect(#late.arrivals).toBe(20)
		expect(late.arrivalsRemaining).toBe(0)
		expect(late.count).toBe(44)
		world.built.steps.advance(world.built, "500")
		expect(#world.built.services.orders.dump().arrivals).toBe(20)
		closeWorld(world)
	end)

	it("the seeded intervals are inside the declared 3-8 s band", function()
		local world = makeWorld()
		local times = world.built.services.orders.arrivalTimes
		expect(#times).toBe(20)
		local previous = 0
		for _, at in times do
			local gap = at - previous
			expect(gap).toBeGreaterThanOrEqual(3)
			expect(gap).toBeLessThanOrEqual(8)
			previous = at
		end
		closeWorld(world)
	end)
end)

describe("Cartwheel — the dashboard reacts to an arrival", function()
	it("keys the newest brew into the hero slot and re-aims the tally", function()
		local world = makeWorld()
		local hero = world.built.paths.cart .. "/Page/CardGrid/Recent/RecentBrews/HeroTiles/Hero/HeroSlot/HeroRow"
		expect(world.adapter.node(hero .. "/[124]/Tile124") ~= nil).toBe(true)

		world.built.steps.advance(world.built, "10")
		local newest = (world.built.services.orders.brews:get() :: any)[1]
		expect(newest.id > 124).toBe(true)
		world.presenter.refresh()
		-- the keyed row for the arrival is mounted, and the one it replaced is on
		-- its way out rather than being rebuilt in place
		expect(world.adapter.node(hero .. "/[" .. tostring(newest.id) .. "]/Tile" .. tostring(newest.id)) ~= nil).toBe(
			true
		)
		-- the tally counter is aimed at the newest brew's bottle count
		expect(world.built.screens.dashboard.tally:getTarget()).toBe(newest.bottles)
		closeWorld(world)
	end)
end)

--[[ THE TALLY'S NUDGE IS A DECLARATION, NOT A PER-FRAME WRITE (purity audit
	DELETE §5, 2026-08-21).

	`scale` is a documented reactive prop on every rendered class
	(`blueprint_schema.luau`), and this footer was driving it with a
	`setPresentationTransform` call on EVERY tick — including the resting frames,
	where it wrote `nil` over and over. The neighbouring `celebration.luau` genuinely
	has to go imperative, because a TRANSLATION has no declarative twin yet; that
	established idiom then propagated onto a case that never needed it, and this
	corpus is what a reader copies from.

	BOTH DIRECTIONS: the app must make NO imperative transform write for that path,
	AND the nudge must still be painted — "no writes" is also what a dead pulse
	produces. ]]
describe("Cartwheel — the tally's pulse is declared, not written per frame", function()
	it("drives no imperative transform for the footer, and still paints the nudge", function()
		local world = makeWorld()
		local footer = world.built.screens.dashboard.footerPath

		-- SPY on the one seam the imperative form used. `app.controller()` hands
		-- back a stable table, so a wrapper here sees every call the app makes.
		local controller = world.built.handle.controller
		local writes = 0
		local realWrite = controller.setPresentationTransform
		controller.setPresentationTransform = function(path: string, value: any)
			if path == footer then
				writes += 1
			end
			return realWrite(path, value)
		end

		world.built.steps.advance(world.built, "10")
		world.presenter.refresh()
		local peak = 1
		local last = 1
		for _ = 1, 60 do
			world.presenter.tick(1 / 60)
			world.presenter.refresh()
			local node = world.adapter.node(footer)
			local transform = if node ~= nil then node.props.transform else nil
			local scale = if type(transform) == "table" and type(transform.scale) == "number"
				then transform.scale
				else 1
			peak = math.max(peak, scale)
			last = scale
		end
		expect(`imperative transform writes on the footer: {writes}`).toBe(
			"imperative transform writes on the footer: 0"
		)
		-- ...and the nudge is REAL: the declared scale rises above rest while the
		-- arrival's spring is running, and comes back to exactly 1 once it settles
		expect(`the nudge peaked above rest: {peak > 1.01}`).toBe("the nudge peaked above rest: true")
		expect(`and settled back to rest: {last == 1}`).toBe("and settled back to rest: true")
		closeWorld(world)
	end)
end)

--[[ ADAPT-1 — THE RUNG THAT HAD NEVER FIRED, IN A SHIPPED APP.

	The audit's census: all five `PopupButton` call sites in this repository wired
	`sizeClass` and none wired `interactionClasses`, so `touchLive` was false
	forever and `menu_recipe`'s first rule — touch means a bottom SHEET, the
	reference platform's own default — never ran anywhere. This screen now wires
	NEITHER fact, and gets both from the surface it is standing on.

	Both halves are asserted, because only the pair is evidence: a thumb gets the
	sheet, and a mouse on the identical screen does not (ADAPT-9's rule — a hybrid
	follows its PRIMARY class, so having touch is not enough).

	WHAT THE POINTER ANSWER ACTUALLY IS, measured rather than assumed: three
	options with room resolve `inline` — rows in place, no floating panel at all —
	because `menu_recipe`'s own rule is "`optionCount <= 3` and not compact ->
	inline". The first draft of this case asserted `menu` and failed for the right
	reason. What matters to the finding is that the pointer answer is NOT the sheet
	and that it changes when the primary class does. ]]
describe("Cartwheel — the unwired popup adapts to the surface (ADAPT-1)", function()
	it("a touch phone resolves the SHEET; a desktop pointer never does", function()
		local phone = makeWorld({ width = 390, height = 844 })
		phone.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		phone.env:set("preferredInput", "Touch")
		phone.presenter.refresh()
		phone.built.steps.section(phone.built, "potions")
		expect(phone.built.screens.gallery.dump().sortPresentation).toBe("sheet")
		closeWorld(phone)

		local desktop = makeWorld({ width = 1440, height = 900 })
		desktop.built.steps.section(desktop.built, "potions")
		expect(desktop.built.screens.gallery.dump().sortPresentation).toBe("inline")
		closeWorld(desktop)
	end)

	it("the same device, one input class later: the idiom follows the thumb", function()
		local hybrid = makeWorld({ width = 1024, height = 768 })
		hybrid.env:set("capabilities", { touch = true, mouse = true, keyboard = true, gamepad = false })
		hybrid.env:set("preferredInput", "KeyboardAndMouse")
		hybrid.presenter.refresh()
		hybrid.built.steps.section(hybrid.built, "potions")
		-- a mouse still wins outright, touchscreen or not (ADAPT-9)
		expect(hybrid.built.screens.gallery.dump().sortPresentation).toBe("inline")
		hybrid.env:set("preferredInput", "Touch")
		hybrid.presenter.refresh()
		expect(hybrid.built.screens.gallery.dump().sortPresentation).toBe("sheet")
		closeWorld(hybrid)
	end)
end)

describe("Cartwheel — gallery and workbench", function()
	it("the composite sort re-derives the order per key", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "potions")
		local popularity = world.built.steps.gallery_sort(world.built, "popularity")
		local byName = world.built.steps.gallery_sort(world.built, "name")
		local byAttribute = world.built.steps.gallery_sort(world.built, "attribute")
		expect(stable(popularity.order) ~= stable(byName.order)).toBe(true)
		expect(stable(byAttribute.order) ~= stable(byName.order)).toBe(true)
		-- Name is alphabetical, and that is checkable rather than merely different
		local names: { string } = {}
		for _, id in byName.order do
			table.insert(names, (data.potionById(id) :: any).name)
		end
		for index = 2, #names do
			expect(names[index - 1] <= names[index]).toBe(true)
		end
		closeWorld(world)
	end)

	it("grid and table are two forms of ONE selection", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "potions")
		expect(world.adapter.node(world.built.paths.potions .. "/GridWhen/then/GridHost/GridScroll/Tiles") ~= nil).toBe(
			true
		)
		world.built.steps.gallery_layout(world.built, "list")
		expect(world.adapter.node(world.built.paths.potions .. "/TableWhen/then/TableHost/PotionTable") ~= nil).toBe(
			true
		)
		-- the losing form RETIRES rather than vanishing: it stays mounted, painting
		-- its exit, until the transition completes on the presenter's clock
		world.built.steps.advance(world.built, "0.6")
		expect(world.adapter.node(world.built.paths.potions .. "/GridWhen/then/GridHost/GridScroll/Tiles")).toBe(nil)
		closeWorld(world)
	end)

	it("a gallery cell opens the Workbench on that potion", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "potions")
		world.adapter.tap(
			world.built.paths.potions .. "/GridWhen/then/GridHost/GridScroll/Tiles/Cells/[moonwell]/Cell_moonwell"
		)
		world.presenter.refresh()
		expect(world.built.screens.shell.dump().section).toBe("workbench")
		expect(world.built.screens.workbench.dump().potion).toBe("moonwell")
		closeWorld(world)
	end)

	it("an edit moves the attributes and the preview on the same frame — no Save", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "workbench")
		local preview = world.built.paths.workbench .. "/Bench/Preview/Preview/Layers"
		local before = world.built.screens.workbench.dump()
		expect(before.potion).toBe("scratch")
		expect(before.essence).toBe("none")
		expect(world.adapter.node(preview .. "/EssenceWhen/then/Essence")).toBe(nil)

		-- driven through the picker's OWN select verb, which is what a tap does
		local after = world.built.steps.bench_pick(world.built, "essence:thornhoney")
		expect(after.essence).toBe("thornhoney")
		expect(world.adapter.node(preview .. "/EssenceWhen/then/Essence") ~= nil).toBe(true)

		-- the attributes are DERIVED, so the sum moved with no save anywhere
		local expected = data.attributesOf("springwater", "thornhoney", nil)
		expect(stable(after.attributes)).toBe(stable(expected))
		expect(before.strongest ~= after.strongest or stable(before.attributes) ~= stable(after.attributes)).toBe(true)

		-- ...and "None" takes the layer back off
		local cleared = world.built.steps.bench_pick(world.built, "essence:none")
		expect(cleared.essence).toBe("none")
		expect(world.adapter.node(preview .. "/EssenceWhen/then/Essence")).toBe(nil)
		closeWorld(world)
	end)

	it("an edit survives leaving the Workbench and coming back", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "workbench")
		world.built.steps.bench_pick(world.built, "base:emberoil")
		world.built.steps.section(world.built, "cart")
		world.built.steps.section(world.built, "workbench")
		expect(world.built.screens.workbench.dump().base).toBe("emberoil")
		closeWorld(world)
	end)
end)

describe("Cartwheel — entitlement, gate and lock", function()
	it("BOTH purchase outcomes are reachable: the first declines, the second confirms", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "ledger")
		local first = world.built.steps.purchase(world.built, "ledger")
		expect(first.entitlement.fullLedger).toBe(false)
		expect(world.built.commands.reason("purchase:ledger"):get()).toBe("Purchase declined — nothing was charged")
		local second = world.built.steps.purchase(world.built, "ledger")
		expect(second.entitlement.fullLedger).toBe(true)
		closeWorld(world)
	end)

	it("a gated timeframe is LOCKED while unentitled: the paths are not mounted", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "ledger")
		local plot = world.built.paths.ledger .. "/Chart/PlotHost/Plot"
		expect(world.adapter.node(plot .. "/SeriesWhen/then/Series/Series1") ~= nil).toBe(true)
		expect(world.adapter.node(plot .. "/LockWhen/then/Lock/Scrim")).toBe(nil)

		local locked = world.built.steps.ledger_timeframe(world.built, "month")
		expect(locked.locked).toBe(true)
		-- the series are ABSENT, not faded: Path has no per-path transparency
		expect(world.adapter.node(plot .. "/SeriesWhen/then/Series/Series1")).toBe(nil)
		-- ...while the axes, the legend and the lock chip stay
		expect(world.adapter.node(plot .. "/Grid/Grid0") ~= nil).toBe(true)
		expect(world.adapter.node(plot .. "/LockWhen/then/Lock/Scrim") ~= nil).toBe(true)
		expect(world.adapter.node(plot .. "/LockWhen/then/Lock/Badge") ~= nil).toBe(true)

		-- unlocking restores them with no remount of the screen
		world.built.steps.purchase(world.built, "ledger")
		world.built.steps.purchase(world.built, "ledger")
		expect(world.built.screens.ledger.dump().locked).toBe(false)
		expect(world.adapter.node(plot .. "/SeriesWhen/then/Series/Series1") ~= nil).toBe(true)
		closeWorld(world)
	end)

	it("the upsell has two states and disappears once entitled", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "ledger")
		expect(world.built.screens.ledger.dump().upsell).toBe("expanded")
		world.built.screens.ledger.upsellCollapsed:set(true)
		world.presenter.refresh()
		expect(world.built.screens.ledger.dump().upsell).toBe("row")
		expect(world.adapter.node(world.built.paths.ledger .. "/Upsell/RowWhen/then/RowHost/Row/Unlock") ~= nil).toBe(
			true
		)
		world.built.steps.purchase(world.built, "ledger")
		world.built.steps.purchase(world.built, "ledger")
		expect(world.built.screens.ledger.dump().upsell).toBe("none")
		closeWorld(world)
	end)

	it("the feed gate flips the whole section on one entitlement fact", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "chatter")
		expect(world.built.screens.chatter.dump().subscribed).toBe(false)
		expect(world.adapter.node(world.built.paths.chatter .. "/Feed/MarketingWhen/then/Marketing") ~= nil).toBe(true)
		expect(world.adapter.node(world.built.paths.chatter .. "/Feed/HighlightWhen/then/Highlighted")).toBe(nil)

		world.built.steps.purchase(world.built, "chatter")
		world.built.steps.purchase(world.built, "chatter")
		world.presenter.refresh()
		expect(world.built.screens.chatter.dump().subscribed).toBe(true)
		expect(world.adapter.node(world.built.paths.chatter .. "/Feed/MarketingWhen/then/Marketing")).toBe(nil)
		expect(world.adapter.node(world.built.paths.chatter .. "/Feed/HighlightWhen/then/Highlighted") ~= nil).toBe(
			true
		)
		closeWorld(world)
	end)
end)

describe("Cartwheel — the Guild Card (Variant B, unmasked)", function()
	it("ships the UNMASKED variant with its disclosure caption, and says so on screen", function()
		local world = makeWorld()
		world.built.steps.guild_open(world.built)
		expect(world.built.screens.signup.dump().open).toBe(true)
		-- no masked-entry API exists at v0.9.x, so the caption is the contract
		expect(world.built.screens.signup.dump().watchwordMasked).toBe(false)
		expect(world.adapter.node("/CartwheelGuildCard/Card/Visible") ~= nil).toBe(true)
		expect(world.adapter.node("/CartwheelGuildCard/Card/Visible").props.text).toBe(
			"Heads up — your watchword is visible as you type."
		)
		-- and the exercise states its own status
		expect(world.adapter.node("/CartwheelGuildCard/Card/Note").props.text).toBe(
			"A UI exercise — Roblox identity is ambient; nothing is stored."
		)
		closeWorld(world)
	end)

	it("is validation-gated and rejects a taken name at the field", function()
		local world = makeWorld()
		world.built.steps.guild_open(world.built)
		expect(world.built.screens.signup.dump().canSubmit).toBe(false)
		local taken = world.built.steps.guild_submit(world.built, "gullsgate")
		expect(taken.signedIn).toBe(false)
		expect(taken.error).toBe("That guild name is taken")
		local ok = world.built.steps.guild_submit(world.built, "emberwick")
		expect(ok.signedIn).toBe(true)
		expect(ok.guild).toBe("emberwick")
		expect(ok.open).toBe(false)
		closeWorld(world)
	end)
end)

describe("Cartwheel — signing out asks first", function()
	it("opens a confirm modal and only then drops the fact", function()
		local world = makeWorld()
		world.built.steps.guild_open(world.built)
		world.built.steps.guild_submit(world.built, "emberwick")
		expect(world.built.services.identity.signedIn:get()).toBe(true)

		-- the sidebar row now opens the confirm rather than the form
		world.built.steps.guild_open(world.built)
		expect(world.adapter.node("/CartwheelSignOut/Card/Toolbar/SignOut") ~= nil).toBe(true)
		expect(world.built.services.identity.signedIn:get()).toBe(true)
		world.adapter.tap("/CartwheelSignOut/Card/Toolbar/SignOut")
		world.presenter.refresh()
		expect(world.built.services.identity.signedIn:get()).toBe(false)
		closeWorld(world)
	end)
end)

describe("Cartwheel — the Plaza stage and its fallback", function()
	it("uses the host when the adapter has the seam, and paints no plate", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "plaza:willowmere")
		world.built.steps.advance(world.built, "0.1")
		expect(world.built.screens.plaza.dump().stage).toBe("present")
		expect(world.adapter.node(world.built.paths.stage) ~= nil).toBe(true)
		expect(world.adapter.node(world.built.paths.plaza .. "/Hero/FallbackWhen/then/Fallback")).toBe(nil)
		closeWorld(world)
	end)

	it("can open straight on a plaza, so the runner's one-shot stage content lands", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 800 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local built = proof.build(Facet, core, {
			env = env,
			actionSystem = system,
			presenter = presenter,
			adapter = adapter,
			section = "plaza:emberfall",
		})
		presenter.refresh()
		-- the Stage is mounted on the FIRST frame, which is when the scenario
		-- runner asks for its host
		expect(adapter.node(built.paths.stage) ~= nil).toBe(true)
		expect(built.handle.controller.stageHost(built.paths.stage) ~= nil).toBe(true)
		expect(built.screens.plaza.dump().plaza).toBe("emberfall")
		built.dispose()
	end)

	it("PAINTS THE DECLARED FALLBACK PLATE when stageHost answers nil", function()
		local world = makeWorld({ noStageHost = true })
		world.built.steps.section(world.built, "plaza:willowmere")
		world.built.steps.advance(world.built, "0.1")
		expect(world.built.screens.plaza.dump().stage).toBe("absent")
		-- the reserved box is still there (the layout is identical in both worlds)
		expect(world.adapter.node(world.built.paths.stage) ~= nil).toBe(true)
		-- ...and the plate that explains it is mounted, with its sentence
		local plate = world.built.paths.plaza .. "/Hero/FallbackWhen/then/Fallback"
		expect(world.adapter.node(plate) ~= nil).toBe(true)
		expect(world.adapter.node(plate .. "/Note").props.text).toBe("Live view unavailable on this device.")
		expect(world.adapter.node(plate .. "/KeyArt") ~= nil).toBe(true)
		closeWorld(world)
	end)

	it("the proof drives the orbit through the PUBLIC handle, and parks it when motion is reduced", function()
		local world = makeWorld()
		world.built.steps.section(world.built, "plaza:willowmere")
		world.built.steps.advance(world.built, "0.1")
		local host = world.built.handle.controller.stageHost(world.built.paths.stage)
		expect(host ~= nil).toBe(true)
		local before = #host.calls
		world.built.steps.advance(world.built, "4")
		world.built.steps.advance(world.built, "4")
		expect(#host.calls > before).toBe(true)
		local last = host.calls[#host.calls]
		local previous = host.calls[#host.calls - 1]
		expect(last.method).toBe("setCamera")
		-- the camera actually MOVED (an orbit that never re-aims is a still)
		expect(last.spec.position.x ~= previous.spec.position.x).toBe(true)
		closeWorld(world)

		-- reduced motion: one declared framing, and then it stops writing
		local still = makeWorld({ reducedMotion = true })
		still.built.steps.section(still.built, "plaza:willowmere")
		still.built.steps.advance(still.built, "0.1")
		local parked = still.built.handle.controller.stageHost(still.built.paths.stage)
		local settled = #parked.calls
		still.built.steps.advance(still.built, "8")
		expect(#parked.calls).toBe(settled)
		closeWorld(still)
	end)

	it("the recommendation is the first plaza with no damp spell", function()
		local world = makeWorld()
		local ambient = world.built.services.ambient
		local recommended = ambient.recommendedPlaza()
		expect(ambient.hasDampSpell(recommended.id)).toBe(false)
		for _, plaza in data.plazas :: any do
			if plaza.id == recommended.id then
				break
			end
			expect(ambient.hasDampSpell(plaza.id)).toBe(true)
		end
		closeWorld(world)
	end)
end)

describe("Cartwheel — the loop closes: charts reflect the change", function()
	it("a collected brew's bottles reach StatsService, Top Five and the Ledger", function()
		local world = makeWorld()
		local before = world.built.screens.topfive.dump().total
		world.built.steps.open_brew(world.built, "110")
		local brew = world.built.services.orders.byId(110)
		world.built.steps.advance_status(world.built)
		local after = world.built.screens.topfive.dump().total
		expect(after).toBe(before + brew.bottles)
		expect(world.built.services.stats.dump().collected).toBe(brew.bottles)
		closeWorld(world)
	end)
end)

describe("Cartwheel — the solver's own verdict", function()
	-- THE LESSON THIS ENCODES (docs/lessons/the-solver-already-told-you.md): the
	-- layout diagnostics are a fixture's job to READ. A screen that overflows,
	-- clips or falls back tells the solver so on every solve, and a proof that
	-- never asks ships the defect a human finds in a screenshot.
	local VIEWPORTS = {
		{ name = "phone portrait", w = 390, h = 844 },
		{ name = "phone landscape", w = 733, h = 313 },
		{ name = "tablet", w = 1024, h = 768 },
		{ name = "desktop", w = 1440, h = 900 },
		{ name = "ten-foot", w = 1920, h = 1080, large = true },
	}
	local SECTIONS = {
		"cart",
		"brews",
		"chatter",
		"ledger",
		"potions",
		"workbench",
		"topfive",
		"plaza:willowmere",
	}

	it("reports NO layout diagnostics on any real viewport, in any section", function()
		for _, viewport in VIEWPORTS do
			for _, section in SECTIONS do
				local core = Facet.newCore()
				local env = Facet.newEnvironment(core)
				env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
				if viewport.large then
					env:set("displaySize", "Large")
				end
				local system = Facet.newActionSystem(core)
				local adapter = fake_target.new();
				-- UNDER THE BAR THE LIVE ENGINE ACTUALLY RESERVES. The headless twin
				-- defaults to none, so a bar-less sweep measures every page scroller
				-- 8px wider than the screen will, and reports clean on rows that
				-- overflow in Studio.
				(adapter :: any).scrollBarThickness = 8
				local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
				local built = proof.build(Facet, core, {
					env = env,
					actionSystem = system,
					presenter = presenter,
					adapter = adapter,
					section = section,
				})
				presenter.refresh()
				local diagnostics = built.handle.controller.diagnostics()
				if #diagnostics > 0 then
					error(
						`{viewport.name} / {section}: {#diagnostics} solver diagnostic(s), first = `
							.. `{diagnostics[1].node} — {diagnostics[1].issue}`,
						2
					)
				end
				expect(#diagnostics).toBe(0)
				built.dispose()
			end
		end
	end)

	it("...and none on the pushed detail, the celebration, or the sign-up form either", function()
		for _, viewport in VIEWPORTS do
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
			if viewport.large then
				env:set("displaySize", "Large")
			end
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new();
			(adapter :: any).scrollBarThickness = 8
			local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
			local built = proof.build(Facet, core, {
				env = env,
				actionSystem = system,
				presenter = presenter,
				adapter = adapter,
				section = "brews",
			})
			presenter.refresh()
			built.steps.open_brew(built, "110")
			expect(#built.handle.controller.diagnostics()).toBe(0)
			built.steps.advance_status(built)
			expect(#built.handle.controller.diagnostics()).toBe(0)
			built.steps.dismiss_celebration(built)
			built.steps.guild_open(built)
			expect(#built.handle.controller.diagnostics()).toBe(0)
			built.dispose()
		end
	end)

	--[[ THE LADDER IS APPLIED TO ALL OF IT, OR IT IS NOT APPLIED (ADR-0042).

		This proof used to own its seven structural numbers as literals in
		`content/metrics.luau`, with a hand `metricScale` multiply on ONE of them —
		so at three metres the tile minimum grew to 144 while the chart band, the
		hero band and the preview box stayed exactly where a phone left them. A
		fixed px number holding content that is not fixed is
		`docs/lessons/facet-fixed-px-heights.md`'s class; a fixed px number holding
		content that IS scaling is the same class read across the distance axis,
		and a hand-rolled ladder is one somebody has to remember to climb.

		They are theme metrics now (`app.cartwheel.*`), so the framework climbs it:
		every one of them takes the same factor, from the same place, with no
		arithmetic in this proof at all. Measured off the PAINTED boxes rather than
		off the declaration, because the declaration is what was already right. ]]
	it("every structural band takes the ten-foot factor, not just the one that was remembered", function()
		local near = makeWorld({ width = 1440, height = 900 })
		near.built.steps.section(near.built, "ledger")
		near.presenter.refresh()
		local nearPlot = near.adapter.node(near.built.paths.ledger .. "/Chart/PlotHost/Plot")
		expect(nearPlot ~= nil).toBe(true)

		local far = makeWorld({ width = 1920, height = 1080 })
		far.env:set("displaySize", "Large")
		far.built.steps.section(far.built, "ledger")
		far.presenter.refresh()
		local farPlot = far.adapter.node(far.built.paths.ledger .. "/Chart/PlotHost/Plot")
		expect(farPlot ~= nil).toBe(true)
		expect(farPlot.rect.h).toBe(nearPlot.rect.h * 1.5)

		-- ...and the same factor reaches the declaration side, which is what makes
		-- the four numbers ONE decision instead of four remembered ones
		local snap: any = far.env:get("themeMetrics"):get()
		expect(snap.app.cartwheel.chartH).toBe(240)
		expect(snap.app.cartwheel.heroH).toBe(180)
		expect(snap.app.cartwheel.previewMin).toBe(300)
		expect(snap.app.cartwheel.tileMin).toBe(144)
		expect(snap.app.cartwheel.cardMin).toBe(420)
		closeWorld(near)
		closeWorld(far)
	end)

	it(
		"below every shipping device the shell falls back to the column, and SAYS the minimum it could not meet",
		function()
			-- 320x640 is narrower than any row in the device matrix. The declared
			-- `detailMin` cannot be met there, so the composition resolves its declared
			-- fallback and reports the rule it broke — which is the framework working,
			-- not a screen breaking.
			local world = makeWorld({ width = 320, height = 640 })
			-- with a section pushed the DETAIL lane is the one that has to fit, and
			-- 320 is under its declared minimum
			world.built.steps.section(world.built, "cart")
			local resolution = world.built.handle.controller.compositionAt(world.built.paths.shell)
			expect(resolution.arrangement).toBe("column")
			expect(resolution.fallback).toBe(true)
			expect(world.adapter.node(world.built.paths.cart) ~= nil).toBe(true)
			local diagnostics = world.built.handle.controller.diagnostics()
			expect(#diagnostics).toBe(1)
			expect(string.find(diagnostics[1].issue, "360px minimum", 1, true) ~= nil).toBe(true)
			closeWorld(world)
		end
	)

	it("mounts under BOTH reference theme packages with no source edit", function()
		local themes = Facet.themes
		for _, packageName in { "studio-neutral", "fantasy_parchment" } do
			local world = makeWorld()
			local snapshot = if packageName == "studio-neutral"
				then themes.neutral()
				else themes.resolve((require)("../../examples/themes/fantasy_parchment").build(themes), nil, {})
			world.env:set("themeMetrics", snapshot)
			world.presenter.refresh()
			world.built.steps.section(world.built, "brews")
			world.built.steps.open_brew(world.built, "101")
			world.built.steps.advance_status(world.built)
			expect(world.built.screens.brewDetail.dump().status).toBe("brewing")
			expect(#world.built.handle.controller.diagnostics()).toBe(0)
			expect(world.core:lastError()).toBeNil()
			closeWorld(world)
		end
	end)
end)

describe("Cartwheel — determinism and lifecycle", function()
	it("SAME SEED + SAME STEPS => IDENTICAL REPORT", function()
		local function run(): string
			local world = makeWorld({ seed = 4242 })
			world.built.steps.section(world.built, "brews")
			world.built.steps.search(world.built, "1")
			world.built.steps.sort(world.built, "bottles")
			world.built.steps.open_brew(world.built, "101")
			world.built.steps.advance_status(world.built)
			world.built.steps.advance(world.built, "12.5")
			world.built.steps.advance_status(world.built)
			world.built.steps.dismiss_celebration(world.built)
			world.built.steps.purchase(world.built, "ledger")
			world.built.steps.purchase(world.built, "ledger")
			world.built.steps.gallery_sort(world.built, "attribute")
			world.built.steps.advance(world.built, "40")
			local text = stable(world.built.report())
			closeWorld(world)
			return text
		end
		local first = run()
		local second = run()
		expect(#first > 500).toBe(true)
		expect(first).toBe(second)
	end)

	it("a different seed produces a different world (the seed is really injected)", function()
		local a = makeWorld({ seed = 1 })
		local b = makeWorld({ seed = 2 })
		-- the SEEDED content, not the shape: both worlds have 24 brews and the
		-- same ids by construction, so the pin is what the seed actually decides
		expect(stable(a.built.services.orders.arrivalTimes) ~= stable(b.built.services.orders.arrivalTimes)).toBe(true)
		expect(stable(a.built.services.orders.byId(101).items) ~= stable(b.built.services.orders.byId(101).items)).toBe(
			true
		)
		expect(stable(a.built.services.stats.dump()) ~= stable(b.built.services.stats.dump())).toBe(true)
		closeWorld(a)
		closeWorld(b)
	end)

	it("build + drive + dispose is registry-neutral", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 800 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local deps = { env = env, actionSystem = system, presenter = presenter, adapter = adapter }

		local baseline: any = nil
		for cycle = 1, 3 do
			local built = proof.build(Facet, core, deps)
			presenter.refresh()
			built.steps.section(built, "brews")
			built.steps.open_brew(built, "101")
			built.steps.advance_status(built)
			built.dispose()
			local counters = core:counters()
			if cycle == 1 then
				baseline = counters
			else
				expect(counters.memos).toBe(baseline.memos)
				expect(counters.signals).toBe(baseline.signals)
				expect(counters.scopes).toBe(baseline.scopes)
				expect(counters.observers).toBe(baseline.observers)
			end
		end
		expect(core:lastError()).toBeNil()
	end)
end)

describe("Cartwheel — strings and the pseudo-locale", function()
	it("every `xa` string is at least 1.4x its English source", function()
		local en = strings.locales.en
		local xa = strings.locales.xa
		local count = 0
		for key, value in en do
			count += 1
			local expanded = xa[key]
			expect(expanded ~= nil).toBe(true)
			expect(#expanded >= math.ceil(#value * strings.EXPANSION)).toBe(true)
		end
		expect(count > 100).toBe(true)
	end)

	it("the pseudo-locale keeps every {placeholder} intact", function()
		for key, value in strings.locales.en do
			for name in string.gmatch(value, "{(%w+)}") do
				expect(string.find(strings.locales.xa[key], "{" .. name .. "}", 1, true) ~= nil).toBe(true)
			end
		end
	end)

	it("the locale fact reaches the screens", function()
		local world = makeWorld({ locale = "xa-pseudo" })
		expect(world.built.report().locale).toBe("xa")
		expect(world.built.strings.t("nav.brews")).toBe(strings.locales.xa["nav.brews"])
		closeWorld(world)
	end)
end)

describe("Cartwheel — reduced motion", function()
	it("mounts and drives identically with motion reduced", function()
		local world = makeWorld({ reducedMotion = true })
		world.built.steps.open_brew(world.built, "110")
		world.built.steps.advance_status(world.built)
		-- the same events, the same states: the celebration still opens and the
		-- beats still fire, instantly
		expect(world.built.screens.celebration.dump().open).toBe(true)
		expect(world.built.screens.celebration.dump().cork).toBe(true)
		expect(world.core:lastError()).toBeNil()
		closeWorld(world)
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

describe("Cartwheel — the rows that WRAP (parity round 3)", function()
	-- WHY THESE CASES EXIST, AND WHY THEY ASSERT RECTS RATHER THAN PRESENCE.
	-- Four rows here used to be hand-built approximations of a ragged flow: three
	-- were `Grid{ minColumnWidth = "intrinsic", itemSizing = "uniform" }` (uniform
	-- columns wearing a cloud's clothes) and one was a three-rung `ViewThatFits`
	-- ladder that DROPPED chips to fit. `HStack{ wrap = true }` replaced all four.
	--
	-- A presence assertion cannot guard any of that. The ladder mounted its losers
	-- at a ZERO RECT, so "a node named Charge carries this text" was satisfied by a
	-- node the player could not see — the same way `06_tile_game`'s readouts moved
	-- off their published paths past a green suite. So every case below reads
	-- `screenRectOf` and insists on a NON-ZERO rect at a NAMED path.
	local function worldAt(w: number, h: number, section: string)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).scrollBarThickness = 8
		local presenter = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local built = proof.build(Facet, core, {
			env = env,
			actionSystem = system,
			presenter = presenter,
			adapter = adapter,
			section = section,
		})
		presenter.refresh()
		return built, adapter
	end

	-- every path whose tail matches, with its solved rect — the fixture's own view
	-- of what the player can actually see
	local function rectsUnder(built: any, adapter: any, needle: string): { [string]: any }
		local out: { [string]: any } = {}
		for _, path in adapter.paths() do
			if string.find(path, needle, 1, true) ~= nil then
				out[path] = built.handle.controller.screenRectOf(path)
			end
		end
		return out
	end

	local function countKeys(map: { [string]: any }): number
		local n = 0
		for _ in map do
			n += 1
		end
		return n
	end

	it("THE PLAZA SUMMARY IS ONE ROW: each chip at ONE path, none at a zero rect", function()
		local built, adapter = worldAt(1440, 900, "plaza:willowmere")
		-- the ladder's rungs are GONE. Before this change `Charge` existed three
		-- times (`Summary/Full`, `Summary/Two`, `Summary/One`) and the last two were
		-- measured at 8x0 on every viewport this section is reachable on.
		expect(countKeys(rectsUnder(built, adapter, "Summary/Full"))).toBe(0)
		expect(countKeys(rectsUnder(built, adapter, "Summary/Two"))).toBe(0)
		expect(countKeys(rectsUnder(built, adapter, "Summary/One"))).toBe(0)

		local widths: { number } = {}
		for _, id in { "Charge", "Popular", "Trending" } do
			local found = rectsUnder(built, adapter, "Pitch/Summary/" .. id)
			-- EXACTLY ONE path per chip: a second one is the duplication defect back
			expect(countKeys(found)).toBe(1)
			for path, rect in found do
				expect(rect ~= nil).toBe(true)
				if rect.w <= 0 or rect.h <= 0 then
					error(`{path} solved to {rect.w}x{rect.h} — a chip nobody can see`, 2)
				end
				table.insert(widths, rect.w)
			end
		end
		-- RAGGED, not uniform: a grid would have handed all three the widest width
		expect(widths[1] ~= widths[2] or widths[2] ~= widths[3]).toBe(true)
		built.dispose()
	end)

	it("THE TAG CLOUD IS RAGGED AND MULTI-LINE, where a uniform grid gave one width", function()
		local built, adapter = worldAt(1440, 900, "cart")
		local found = rectsUnder(built, adapter, "ChatterCard/Cloud/Tag")
		expect(countKeys(found) >= 12).toBe(true)

		local widths: { [number]: boolean } = {}
		local lines: { [number]: boolean } = {}
		for path, rect in found do
			expect(rect ~= nil).toBe(true)
			if rect.w <= 0 or rect.h <= 0 then
				error(`{path} solved to {rect.w}x{rect.h}`, 2)
			end
			widths[rect.w] = true
			lines[rect.y] = true
		end
		-- THE WHOLE POINT. `Grid{ intrinsic, uniform }` measured every one of these
		-- sixteen tags at 135x23 — one width, because a uniform column takes the
		-- widest child's measure. A flow gives each tag its own.
		local distinctWidths = countKeys(widths :: any)
		if distinctWidths < 4 then
			error(
				`the cloud has only {distinctWidths} distinct chip width(s) — that is a uniform grid, not a flow`,
				2
			)
		end
		-- and it really WRAPPED: more than one line of chips
		expect(countKeys(lines :: any) > 1).toBe(true)
		built.dispose()
	end)

	it("A POST'S TAGS AND THE CHART LEGEND KEEP THEIR OWN WIDTHS", function()
		-- both were uniform grids too: a post's two tags came out the same width as
		-- each other (105/105, 113/113, 83/83 ... across the six seeded posts) and
		-- the three legend chips all took the widest plaza name's width
		local built, adapter = worldAt(1440, 900, "chatter")
		local raggedPosts = 0
		for index = 1, 6 do
			local pair = rectsUnder(built, adapter, `Post_c{index}/Body/Tags/Tag`)
			expect(countKeys(pair)).toBe(2)
			local seen: { number } = {}
			for path, rect in pair do
				if rect == nil or rect.w <= 0 or rect.h <= 0 then
					error(`{path} is not visible`, 2)
				end
				table.insert(seen, rect.w)
			end
			if seen[1] ~= seen[2] then
				raggedPosts += 1
			end
		end
		-- a uniform grid would make this zero
		expect(raggedPosts >= 4).toBe(true)
		built.dispose()

		local ledger, ledgerAdapter = worldAt(1440, 900, "ledger")
		local legend = rectsUnder(ledger, ledgerAdapter, "PlotHost/Legend/Legend")
		expect(countKeys(legend)).toBe(3)
		local sameLine: { [number]: boolean } = {}
		local legendWidths: { [number]: boolean } = {}
		for path, rect in legend do
			if rect == nil or rect.w <= 0 or rect.h <= 0 then
				error(`{path} is not visible`, 2)
			end
			sameLine[rect.y] = true
			legendWidths[rect.w] = true
		end
		-- three ragged chips fit on ONE line; three uniform ones needed two rows and
		-- left a dead cell
		expect(countKeys(sameLine :: any)).toBe(1)
		expect(countKeys(legendWidths :: any) > 1).toBe(true)
		ledger.dispose()
	end)
end)

--[[ THE PROOF'S APP NAMESPACE DOES NOT OUTLIVE THIS FILE (ADR-0042).

	`build` declares `app.cartwheel.*` PROCESS-WIDE, and a spec file that walked away
	would leave the group standing for every later file in this one Lune run —
	which makes suite ORDER quietly load-bearing, and a later case's "nobody
	declared this" assertion depend on which file happened to run first. Retiring
	it here is the teardown; asserting it is what stops the teardown from silently
	becoming a no-op. ]]
describe("Cartwheel — the declaration does not leak into the rest of the suite", function()
	it("retires its app namespace", function()
		Facet.themes.declareApp("cartwheel", nil)
		expect(Facet.themes.appMetrics()["cartwheel"]).toBe(nil)
		expect(themeSnapshot.isMetricPath("app.cartwheel.tileMin")).toBe(false)
	end)
end)
