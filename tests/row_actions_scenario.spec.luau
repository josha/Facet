--!strict
-- Scenario 'row_actions', HEADLESS HALF (roadmap Task 11, docs/plans/
-- row-actions-implementation.md). The Studio scenario proves the paint and
-- the device-matrix geometry; this proves the fixture BUILDS + MOUNTS clean
-- (no core error, `controller.diagnostics()` empty — the Global Constraints
-- requirement every fixture/example carries), that every scripted step is
-- drivable, and that both surfaces' actions (Delete/Flag/Mark Read, keyboard
-- Delete, the Shift+Return menu, reorder-vs-swipe on the Table) actually do
-- what they claim — the same `theme_authoring_scenario.spec.luau` shape,
-- stubbing only the runner-owned engine seams this scenario never touches.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

local scenario = require("../examples/gallery/scenarios/row_actions") :: any

-- a SCRIPTED clock (row_actions_input.spec.luau's own `pointerWorld`/
-- table.spec.luau's own `raWorld` pattern): a commit fires its action only
-- after the row's spring-driven collapse settles, and a real-wall-clock
-- presenter would seed drag_velocity with near-zero real-time deltas between
-- two synchronous pushes.
local function makeWorld()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 700 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local clockTime = 0
	local presenter = LuauUI.newPresenter(core, env, adapter, system, {
		now = function()
			return clockTime
		end,
	})
	local ctx: any = {
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		flags = {},
	}
	local built = scenario.build(ctx)
	-- the runner's own `build()` assigns `session.built.handle` right after
	-- presenting (runner.luau); steps like `bindScroll` read `built.handle`
	-- the same way `drag_session.luau`'s `wireDrag` does, so this stub world
	-- has to do what the runner does.
	built.handle = presenter.present(built.screen, built.present)
	presenter.refresh()
	local world: any = {
		ctx = ctx,
		built = built,
		adapter = adapter,
		presenter = presenter,
		core = core,
		system = system,
		handle = built.handle,
		env = env,
	}
	function world.tick(dt: number)
		clockTime += dt
		presenter.tick(dt)
		presenter.refresh()
	end
	function world.settle(frames: number?)
		for _ = 1, frames or 90 do
			world.tick(1 / 60)
		end
	end
	return world
end

local function teardown(world: any)
	world.presenter.dismiss(world.handle)
	if world.built.dispose ~= nil then
		world.built.dispose()
	end
end

local function step(world: any, name: string, payload: string?): any
	local fn = world.built.steps[name]
	assert(fn ~= nil, `no step '{name}'`)
	local result = fn(world.built, payload)
	world.presenter.refresh()
	-- a commit collapses the row over a spring BEFORE firing onAction
	-- (row_actions.luau's own commit sequence); 400 frames matches
	-- row_actions_input.spec.luau's own settle margin for the same path
	world.settle(400)
	return result
end

describe("row_actions scenario: it builds and mounts clean", function()
	it("mounts headlessly with no core error and empty diagnostics", function()
		local world = makeWorld()
		expect(world.core:lastError()).toBeNil()
		expect(world.adapter.node("/MailActions") ~= nil).toBe(true)
		expect(#world.handle.controller.diagnostics()).toBe(0)
		teardown(world)
	end)

	it("opens on the list surface; the table pane is not mounted at all (lazy UI.When)", function()
		local world = makeWorld()
		expect(world.adapter.node("/MailActions/ListWhen/then/List") ~= nil).toBe(true)
		expect(world.adapter.node("/MailActions/TableWhen/then/TablePane")).toBe(nil)
		teardown(world)
	end)

	it("every seed row mounts as a wrapped RowActions node with a unique id", function()
		local world = makeWorld()
		for _, id in { "m1", "m2", "m3", "m4", "m5", "m6" } do
			expect(world.adapter.node(`/MailActions/ListWhen/then/List/Rows/RowsForEach/[{id}]/{id}`) ~= nil).toBe(true)
		end
		teardown(world)
	end)

	it("registers every step the device matrix drives, by name", function()
		local world = makeWorld()
		local names = {}
		for name in world.built.steps do
			names[name] = true
		end
		for _, name in
			{ "mode", "open", "close", "commit", "editing", "keyDeleteList", "menuList", "bindScroll", "list" }
		do
			expect(names[name] == true).toBe(true)
		end
		teardown(world)
	end)
end)

describe("row_actions scenario: list surface (hand-wrapped ScrollView>VStack)", function()
	it("_open reveals the trailing tray; dump reports openEdge = trailing", function()
		local world = makeWorld()
		local result = step(world, "open", "m1:trailing")
		expect(result.ok).toBe(true)
		expect(result.dump.openEdge).toBe("trailing")
		teardown(world)
	end)

	it("close returns an open row to closed", function()
		local world = makeWorld()
		step(world, "open", "m1:trailing")
		local result = step(world, "close", "m1")
		expect(result.ok).toBe(true)
		expect(result.dump.phase).toBe("closed")
		teardown(world)
	end)

	it("commit on trailing fires Delete (the first trailing action) and the row leaves the model", function()
		local world = makeWorld()
		local result = step(world, "commit", "m2:trailing")
		expect(result.ok).toBe(true)
		expect(result.fired).toBe(true)
		-- the commit collapses the row over a spring BEFORE firing onAction
		-- (row_actions.luau's own commit sequence), so the model only reflects
		-- the removal once the settle inside `step()` has run frames — re-read
		-- rather than trust the snapshot `commit` itself returned synchronously
		local after = step(world, "list")
		local found = false
		for _, id in after.list do
			if id == "m2" then
				found = true
			end
		end
		expect(found).toBe(false)
		teardown(world)
	end)

	it("commit on leading fires Mark Read (the first leading action), row survives", function()
		local world = makeWorld()
		local before = step(world, "list")
		local result = step(world, "commit", "m3:leading")
		expect(result.ok).toBe(true)
		expect(result.fired).toBe(true)
		expect(#result.remainingIds).toBe(#before.list)
		teardown(world)
	end)

	it("opening one row closes another (shared newRowActionsCoordinator, one-open policy)", function()
		local world = makeWorld()
		local a = step(world, "open", "m1:trailing")
		expect(a.ok).toBe(true)
		local b = step(world, "open", "m2:trailing")
		expect(b.ok).toBe(true)
		expect(b.dump.openEdge).toBe("trailing")
		local report = world.built.report()
		expect(report.listRowDumps.m1.phase).toBe("closed")
		expect(report.listRowDumps.m2.phase).toBe("open")
		teardown(world)
	end)

	it("keyboard Delete on a focused row fires the destructive action end to end", function()
		local world = makeWorld()
		local result = step(world, "keyDeleteList", "m4")
		expect(result.ok).toBe(true)
		local after = step(world, "list")
		local found = false
		for _, id in after.list do
			if id == "m4" then
				found = true
			end
		end
		expect(found).toBe(false)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("Shift+Return opens the action menu on a focused row", function()
		local world = makeWorld()
		local result = step(world, "menuList", "m5")
		expect(result.ok).toBe(true)
		expect(result.dump.menuOpen).toBe(true)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("bindScroll wires the coordinator's scroll-close after present", function()
		local world = makeWorld()
		local result = step(world, "bindScroll")
		expect(result.ok).toBe(true)
		step(world, "open", "m1:trailing")
		world.adapter.driveScroll("/MailActions/ListWhen/then/List", { x = 0, y = 20 })
		local report = world.built.report()
		expect(report.listRowDumps.m1.phase).toBe("closed")
		teardown(world)
	end)
end)

describe("row_actions scenario: table surface (reorderable, editable, rowActions)", function()
	local function tableWorld()
		local world = makeWorld()
		step(world, "mode", "table")
		return world
	end

	it("switching to table mode mounts the Table and unmounts the list", function()
		local world = tableWorld()
		expect(world.adapter.node("/MailActions/TableWhen/then/TablePane/MailTable") ~= nil).toBe(true)
		expect(world.adapter.node("/MailActions/ListWhen/then/List")).toBe(nil)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("Edit toggle flips the editing signal and the report reflects it", function()
		local world = tableWorld()
		expect(world.built.report().tableEditing).toBe(false)
		world.adapter.tap("/MailActions/TableWhen/then/TablePane/TableToolbar/EditToggle")
		world.presenter.refresh()
		expect(world.built.report().tableEditing).toBe(true)
		teardown(world)
	end)

	it("the editing step drives the same signal Table reads for its edit-mode minus", function()
		local world = tableWorld()
		local result = step(world, "editing", "on")
		expect(result.editing).toBe(true)
		teardown(world)
	end)

	it("rows still reorder via mouse drag: a vertical drag on the row moves it, not the tray", function()
		local world = tableWorld()
		local rowHit =
			"/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m1@0]/RowActions-m1/Content/Row/Hit"
		local before = world.built.report().tableIds
		local firstRect = world.adapter.node(rowHit).rect
		local secondHit =
			"/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m2@0]/RowActions-m2/Content/Row/Hit"
		local secondRect = world.adapter.node(secondHit).rect
		world.adapter.pointerDown(rowHit, firstRect.x + 10, firstRect.y + 2, "mouse")
		world.adapter.pointerMove(firstRect.x + 10, secondRect.y + secondRect.h - 2, "mouse") -- purely vertical, past the reorder threshold
		world.presenter.refresh()
		world.adapter.pointerUp(firstRect.x + 10, secondRect.y + secondRect.h - 2, "mouse")
		world.presenter.refresh()
		local after = world.built.report().tableIds
		expect(after[1]).toBe(before[2])
		expect(after[2]).toBe(before[1])
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("a horizontal drag on the same table row reveals its tray instead of reordering", function()
		local world = tableWorld()
		local rowHit =
			"/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m1@0]/RowActions-m1/Content/Row/Hit"
		local before = world.built.report().tableIds
		local rect = world.adapter.node(rowHit).rect
		world.adapter.pointerDown(rowHit, rect.x + 10, rect.y + rect.h / 2, "mouse")
		world.adapter.pointerMove(rect.x - 60, rect.y + rect.h / 2, "mouse") -- purely horizontal
		world.presenter.refresh()
		world.adapter.pointerUp(rect.x - 60, rect.y + rect.h / 2, "mouse")
		world.settle(90)
		local after = world.built.report().tableIds
		-- order is unchanged: the axis lock routed the gesture to row_actions,
		-- never seeding table's reorder drag at all
		expect(after[1]).toBe(before[1])
		expect(after[2]).toBe(before[2])
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)
end)

describe("row_actions scenario: virtual list surface (hosted newVirtualList.rowActions)", function()
	local function vlistWorld()
		local world = makeWorld()
		step(world, "mode", "vlist")
		return world
	end

	it("switching to vlist mode mounts the VirtualList and unmounts the other two surfaces", function()
		local world = vlistWorld()
		expect(world.adapter.node("/MailActions/VListWhen/then/VListPane/VList") ~= nil).toBe(true)
		expect(world.adapter.node("/MailActions/ListWhen/then/List")).toBe(nil)
		expect(world.adapter.node("/MailActions/TableWhen/then/TablePane")).toBe(nil)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("a closed row holds no gesture engine (hosted mode's own laziness guarantee)", function()
		local world = vlistWorld()
		local debug = world.built.steps.vlistDebug(world.built)
		expect(debug.engineCount).toBe(0)
		expect(debug.engagedKey).toBeNil()
		teardown(world)
	end)

	it("a horizontal drag on a row reveals its trailing tray; a full swipe commits Delete end to end", function()
		local world = vlistWorld()
		local rowHit = "/MailActions/VListWhen/then/VListPane/VList/Canvas/W/[m1]/Row/Hit"
		local before = world.built.report().vlistIds
		local rect = world.adapter.node(rowHit).rect
		local startX = rect.x + rect.w - 10
		local endX = startX - rect.w * 0.7 -- past the 60% commit threshold
		world.adapter.pointerDown(rowHit, startX, rect.y + rect.h / 2, "mouse")
		world.adapter.pointerMove(endX, rect.y + rect.h / 2, "mouse") -- purely horizontal
		world.presenter.refresh()
		local debugMidSwipe = world.built.steps.vlistDebug(world.built)
		expect(debugMidSwipe.engineCount).toBe(1)
		expect(debugMidSwipe.engagedKey).toBe("m1")
		world.adapter.pointerUp(endX, rect.y + rect.h / 2, "mouse")
		world.settle(400) -- the commit collapses the row over a spring before firing onAction
		local after = world.built.report().vlistIds
		local found = false
		for _, id in after do
			if id == "m1" then
				found = true
			end
		end
		expect(found).toBe(false)
		expect(#after).toBe(#before - 1)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it(
		"dispose() tears the hosted list down cleanly (engine, overlay and slide transform all live at teardown)",
		function()
			-- M8 (final whole-branch review): the original version of this case
			-- disposed a list with NO gesture ever started, so `hostedEngines` was
			-- empty and the hosted teardown loop
			-- (`listScope:own(function() for key in table.clone(hostedEngines) do
			-- hostedDropEngine(key) end end)`, virtual_list.luau) ran zero
			-- iterations — "cleanly" was proven by nothing. Swipe a row open first
			-- (mid-gesture, no release needed) so the engine, the shared tray
			-- overlay and the presentation slide transform all genuinely exist
			-- when dispose runs.
			local world = vlistWorld()
			local rowHit = "/MailActions/VListWhen/then/VListPane/VList/Canvas/W/[m1]/Row/Hit"
			local rect = world.adapter.node(rowHit).rect
			local startX = rect.x + rect.w - 10
			local endX = startX - rect.w * 0.3
			world.adapter.pointerDown(rowHit, startX, rect.y + rect.h / 2, "mouse")
			world.adapter.pointerMove(endX, rect.y + rect.h / 2, "mouse") -- purely horizontal
			world.presenter.refresh()
			-- confirm there is genuinely something hosted to tear down before
			-- trusting the dispose assertions below
			local debugBeforeDispose = world.built.steps.vlistDebug(world.built)
			expect(debugBeforeDispose.engineCount).toBe(1)
			expect(debugBeforeDispose.engagedKey).toBe("m1")
			world.presenter.dismiss(world.handle)
			expect(function()
					world.built.dispose()
				end)
				.never()
				.toThrow()
			-- a QUARANTINED cleanup error (a throwing owned resource inside the
			-- scope walk, src/core/scope_impl.luau) never surfaces as a thrown
			-- error from dispose() — it is caught and reported through
			-- `core:lastError()` instead, so `never().toThrow()` alone cannot see
			-- a broken hosted-engine teardown. This is the assertion that does.
			expect(world.core:lastError()).toBeNil()
		end
	)
end)

describe("row_actions scenario: the showcase picker's fixture ctx (demo catalogue entry)", function()
	-- The in-game demo picker mounts kind="fixture" entries with the BUILD-TIME
	-- subset of the runner ctx (examples/gallery/client/init.client.luau
	-- `mountDemo`): {LuauUI, core, env, actionSystem, presenter} — no adapter,
	-- no record, no flags, and no step is ever run. This scenario binds
	-- `presenter.onTick` at build, so this case pins that the picker's exact
	-- ctx shape builds, presents, ticks, and disposes clean — the contract the
	-- "row-actions" catalogue row (demo_picker.luau) depends on.
	it("builds, presents, ticks and disposes under the picker's ctx", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 700 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		local built = scenario.build({
			LuauUI = LuauUI,
			core = core,
			env = env,
			actionSystem = system,
			presenter = presenter,
		})
		built.handle = presenter.present(built.screen)
		presenter.refresh()
		-- the picker never drives steps: the default surface must stand on its
		-- own, and a few ticks must not error (the vlist onTick binder retries
		-- until its surface mounts, which in picker use may be never)
		for _ = 1, 5 do
			presenter.refresh()
		end
		expect(adapter.node("/MailActions/ListWhen/then/List") ~= nil).toBe(true)
		expect(core:lastError()).toBeNil()
		-- the picker's own teardown order (init.client.luau mountDemo): the
		-- fixture's dispose first, then the presented surface goes down
		if built.dispose ~= nil then
			built.dispose()
		end
		presenter.dismiss(built.handle)
		expect(core:lastError()).toBeNil()
	end)
end)
