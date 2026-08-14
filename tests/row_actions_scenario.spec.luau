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
local function makeWorld(envSetup: ((any) -> ())?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 700 })
	if envSetup ~= nil then
		envSetup(env)
	end
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
			{
				"mode",
				"open",
				"close",
				"commit",
				"editing",
				"keyDeleteList",
				"menuList",
				"bindScroll",
				"list",
				-- the two non-pointer routes (parity round 3, owed rows 8 and 9)
				"keyDeleteVList",
				"menuVList",
				"padMinusTable",
			}
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

	--[[ THE DELETION'S RE-FLOW IS ANIMATED (device bug round 2026-08-12, finding
		C8a's third part: "...and the next row doesn't animate vertically smoothly").

		Nothing animated the rows BELOW a deleted one — they teleported up by one row
		height on the commit frame. The fix is the ordinary SwiftUI pattern and it is
		the SCREEN's, not the composite's: this fixture commits its deletion inside
		`presenter.withAnimation("container", ...)` (`animateReflow` in
		examples/gallery/scenarios/row_actions.luau), because the screen is what has
		the presenter and what knows the data changed.

		`presenter.animationRecordCount()` is the shipped proof seam for exactly this
		(presenter.luau: "DIAGNOSTICS, not features") — how many paths currently carry
		a `withAnimation` record. It is nonzero only WHILE the flight is alive, so
		this drives frame by frame to the removal instead of settling first.

		IT ALSO PROVES THE CALL DID NOT THROW. `withAnimation` has three refusals —
		nesting, an open core transaction, and a call made during a core commit —
		and the deletion is fired from inside a spring's settle callback which
		`row_actions` runs under `pcall`, so any of them would be SILENT here. A
		record count above zero is only reachable PAST all three, which is what makes
		it evidence that this path is legal.

		THAT REASONING IS SPECIFIC TO THIS CASE. It does not carry to the
		reduced-motion twin below, where zero records is the correct answer and
		therefore says nothing about whether the call raised; that case watches the
		seam directly instead (red-team T4). ]]
	it("the deletion's re-flow animates: withAnimation records are live at the removal", function()
		local world = makeWorld()
		local before = #step(world, "list").list
		world.built.steps.commit(world.built, "m2:trailing")
		local records = 0
		local removedAt: number? = nil
		for i = 1, 400 do
			world.tick(1 / 60)
			if removedAt == nil and #world.built.steps.list().list < before then
				removedAt = i
				records = world.presenter.animationRecordCount()
				break
			end
		end
		expect(removedAt).never().toBeNil()
		expect(records).toBeGreaterThan(0)
		teardown(world)
	end)

	--[[ ...and the deliberate reduced-motion branch. `withAnimation` installs NO
		records at all under it (presenter.luau: "One honest line of code beats a
		clever claim"), so the negative control is not "fewer records" — it is zero,
		with the deletion itself completely unaffected.

		BUT A COUNT OF ZERO IS TWO DIFFERENT OUTCOMES (red-team T4, 2026-08-13), and
		it used to be the only thing this case looked at:

		  · "installed nothing" — the intended reduced-motion branch; or
		  · "silently refused" — `withAnimation` raised (a nesting refusal, a
		    transaction/commit refusal) and the scenario's `pcall(action.onAction)`
		    swallowed it. Zero records, deletion still lands, case green.

		The sibling case above CAN lean on the record count for this, because a
		nonzero count is only reachable past the raise. Here it proves nothing at all
		— and it does not even prove the call HAPPENED, which is the third way to get
		a zero. So this case watches the seam directly: a recording wrapper over the
		presenter method the scenario actually calls (`ctx.presenter` IS this table;
		`animateReflow` in examples/gallery/scenarios/row_actions.luau re-reads the
		field at call time). One call, no raise, zero records — three separate facts. ]]
	it("under reduced motion the same deletion installs no records, is CALLED, and does not refuse", function()
		local world = makeWorld(function(env)
			env:set("reducedMotion", true)
		end)
		-- the spy, installed before the commit that triggers the deletion
		local realWithAnimation = world.presenter.withAnimation
		local calls = 0
		local raised: string? = nil
		world.presenter.withAnimation = function(class: any, fn: () -> ())
			calls += 1
			local ok, err = pcall(realWithAnimation, class, fn)
			if not ok then
				raised = tostring(err)
			end
		end
		local before = #step(world, "list").list
		world.built.steps.commit(world.built, "m2:trailing")
		local removedAt: number? = nil
		local records = -1
		for i = 1, 400 do
			world.tick(1 / 60)
			if removedAt == nil and #world.built.steps.list().list < before then
				removedAt = i
				records = world.presenter.animationRecordCount()
				break
			end
		end
		world.presenter.withAnimation = realWithAnimation
		expect(removedAt).never().toBeNil()
		-- (1) the deletion really did route through the animated seam — a zero
		-- record count is otherwise also what "nobody called it" looks like
		expect(calls).toBeGreaterThan(0)
		-- (2) it RETURNED. The message is carried into the failure because a silent
		-- refusal is exactly the thing this case exists to distinguish, and knowing
		-- WHICH refusal is most of the diagnosis.
		expect(`reduced-motion withAnimation raised: {raised or "no"}`).toBe("reduced-motion withAnimation raised: no")
		-- (3) ...and installed nothing, which is the branch itself
		expect(records).toBe(0)
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

	--[[ RULING 6, ON THE SHIPPED SHOWCASE. This scenario's row content IS a
		full-width `UI.Button` ("mark read"), which is exactly the shape the live
		Studio measurement of 2026-08-13 found un-swipeable: the engine delivers
		`InputBegan` to the topmost interactive object only, so the button sank every
		press and the hit Grip painted behind it received nothing. The showcase's own
		mail list could not be swiped AT ALL on a device — nothing here could see it,
		because `fake_target` delivers to the path a test names.

		With the Grip on top, both verbs work from the same surface: a drag swipes,
		and a tap still marks read. This is the gap's showcase demo, and it did not
		need building — it was already shipping, broken. ]]
	it("RULING 6: the mail row's content is a Button, and the row still swipes AND still taps", function()
		local world = makeWorld()
		local row = "/MailActions/ListWhen/then/List/Rows/RowsForEach/[m1]/m1"
		local grip = `{row}/Content/Hit`
		local content = `{row}/Content/Row`
		expect(`content is a Button: {world.adapter.node(content) ~= nil}`).toBe("content is a Button: true")
		-- the Grip is painted ABOVE that button — the half the engine reads
		expect(`grip on top: {world.adapter.node(grip).z > world.adapter.node(content).z}`).toBe("grip on top: true")

		-- SWIPE: a drag landing on the Grip over the button opens the tray
		local rect = world.adapter.node(grip).rect
		local originX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		world.adapter.pointerDown(grip, originX, y, "touch")
		world.tick(0.01)
		for i = 1, 8 do
			world.adapter.pointerMove(originX - rect.w * 0.3 * (i / 8), y, "touch")
			world.tick(1 / 60)
		end
		world.adapter.pointerUp(originX - rect.w * 0.3, y)
		world.settle(150)
		expect(world.built.report().listRowDumps.m1.phase).never().toBe("closed")

		-- TAP: and the button underneath is still reachable through the same Grip.
		-- `markRead` retires the unread dot, which is the row's own visible proof.
		local fresh = makeWorld()
		local dot = `{row}/Content/Row/DotWhen/then/Dot`
		expect(`unread before: {fresh.adapter.node(dot) ~= nil}`).toBe("unread before: true")
		local r2 = fresh.adapter.node(`{row}/Content/Hit`).rect
		local tx, ty = r2.x + r2.w / 2, r2.y + r2.h / 2
		fresh.adapter.pointerDown(`{row}/Content/Hit`, tx, ty, "touch")
		fresh.tick(1 / 60)
		fresh.adapter.pointerUp(tx, ty)
		fresh.settle(30)
		expect(`unread after the forwarded tap: {fresh.adapter.node(dot) ~= nil}`).toBe(
			"unread after the forwarded tap: false"
		)
		expect(fresh.core:lastError()).toBeNil()
		teardown(fresh)
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

	-- THE SECOND VERB, IN THE SURFACE A PLAYER REACHES (parity round 2 §3.4).
	-- `newTable.onPrimaryAction` is a public API this round added, and the
	-- standing obligation is that a gallery scenario exercises it headlessly.
	-- This is the scenario that carries it, and this is that exercise: the same
	-- device-true tap path the tray tests above use, on the same surface, with
	-- the tray gestures proved untouched by it.
	it("the table surface's onPrimaryAction opens a row on a double-click, and one click only selects", function()
		local world = tableWorld()
		local rowHit =
			"/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m1@0]/RowActions-m1/Content/Row/Hit"
		local rect = world.adapter.node(rowHit).rect
		local function click()
			world.adapter.tap(rowHit, {
				source = "pointer",
				pointer = "mouse",
				x = rect.x + 10,
				y = rect.y + rect.h / 2,
			})
			world.presenter.refresh()
		end
		expect(world.built.report().tableOpenedKey).toBe(nil)
		click()
		expect(world.built.report().tableOpenedKey).toBe(nil) -- selection only
		world.tick(1 / 60) -- well inside the 500 ms double-click window
		click()
		expect(world.built.report().tableOpenedKey).toBe("m1")
		expect(world.core:lastError()).toBeNil()
		expect(#world.handle.controller.diagnostics()).toBe(0)
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

	it("THE PAD REACHES THE EDIT-MODE MINUS on the showcase surface, and it deletes the row", function()
		--[[ The showcase half of parity round 3's owed row 8. The minus lives in
			the row-actions WRAPPER — a sibling of the row's own node, not a
			descendant — so until the focus contribution learned to walk the
			wrapper it was in no focus group at all: on this very surface, a
			keyboard or a pad had NO route to the only delete affordance edit mode
			offers. The step refuses (`ok = false`, naming where the ring landed)
			if the pad does not reach it, so this cannot pass vacuously. ]]
		local world = tableWorld()
		local before = world.built.report().tableIds
		local result = step(world, "padMinusTable", "m2")
		expect(result.ok).toBe(true)
		expect(result.focused).toBe(
			"/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m2@0]/RowActions-m2/EditAffordanceWhen/then/EditAffordance"
		)
		local after = world.built.report().tableIds
		expect(#after).toBe(#before - 1)
		for _, id in after do
			expect(id).never().toBe("m2")
		end
		expect(world.core:lastError()).toBeNil()
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

	--[[ THE TOUCH REVEAL, ON THE SHAPE THE DIRECTOR REPORTED ─────────────────
		Director device round 2026-08-13, finding 2: "on iOS with touch you can
		swipe a row (either side) to get the edit controls even if the table
		isn't in edit mode — we lost that."

		Every swipe case in this file above drives `"mouse"`. That was enough
		while the touch model was the pointer model, and it stopped being enough
		in parity round 2, which gave the ACTIVATE path an early `return true`
		whenever a primary action is declared and the table is not editing. A
		swipe is a POINTER-phase gesture and an activate is a separate dispatch,
		so the two should not meet — but "should not" is a story, and the shape
		the report describes (touch + primary action + not editing) had no case.

		So this drives the real finger sequence on the real scenario surface,
		both edges, and asserts the three things that have to be simultaneously
		true: the tray reveals, edit mode is NOT a prerequisite and does not turn
		itself on, and the primary action does NOT fire on a swipe.

		AND IT DRIVES THE RELEASE ACTIVATE (redteam BLOCKER, 2026-08-13). As first
		shipped, every swipe here ended at `pointerUp` — and the engine does not.
		A row `Hit` is a real `GuiButton`, so the same gesture that swipes it ends
		with that button's `Activated`, on either side of `InputEnded`. Without it
		"the primary action did NOT fire" was satisfied by its own starting value:
		the check could not fail, and the defect it was written to close was live
		underneath it (an "after" Activated CLOSED the tray in the frame it
		appeared; a "before" one opened the row the swipe was meant to offer
		actions for). Both orders are driven below, on both edges and both pointer
		kinds — sixteen releases, none of them silent.
	]]
	local RA_ROW_HIT =
		"/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m1@0]/RowActions-m1/Content/Row/Hit"
	local function raTrayPath(edge: string, action: string): string
		local band = if edge == "leading" then "TrayLeading" else "TrayTrailing"
		return `/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m1@0]/RowActions-m1/{band}When/then/{band}/Action:{action}`
	end
	--[[ ONE swipe helper for this surface, and the ONLY way this file swipes a
		Table row. `activate` is the order the engine's own `Activated` lands in
		relative to `InputEnded` — never omitted, because a release that delivers
		nothing is not a release any engine performs. ]]
	local function swipeRow(world: any, dxFraction: number, pointerType: string, activate: "before" | "after")
		local rect = world.adapter.node(RA_ROW_HIT).rect
		local startX = if dxFraction < 0 then rect.x + rect.w - 8 else rect.x + 8
		local y = rect.y + rect.h / 2
		local dx = rect.w * dxFraction
		world.adapter.pointerDown(RA_ROW_HIT, startX, y, pointerType)
		for i = 1, 8 do
			world.adapter.pointerMove(startX + dx * (i / 8), y, pointerType)
		end
		world.presenter.refresh()
		world.adapter.pointerUpActivating(startX + dx, y, activate)
		world.settle(120)
	end
	--[[ The four instances of the ONE case, with their titles written out in
		full rather than interpolated: the conformance registry's input-proof rule
		(b) looks for a declared proof case VERBATIM in a registered spec, and a
		title assembled at runtime is not in the file for it to find. ]]
	local RELEASE_ACTIVATE_CASES = {
		{
			pointerType = "touch",
			activate = "after" :: "after" | "before",
			title = "RowActions touch: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (after)",
		},
		{
			pointerType = "touch",
			activate = "before" :: "after" | "before",
			title = "RowActions touch: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (before)",
		},
		{
			pointerType = "mouse",
			activate = "after" :: "after" | "before",
			title = "RowActions mouse: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (after)",
		},
		{
			pointerType = "mouse",
			activate = "before" :: "after" | "before",
			title = "RowActions mouse: a swipe reveals the tray on a table NOT in edit mode and survives its release Activate (before)",
		},
	}
	for _, case in RELEASE_ACTIVATE_CASES do
		local pointerType, activate = case.pointerType, case.activate
		it(case.title, function()
			-- TRAILING (Apple's default edge)
			local world = tableWorld()
			-- the preconditions this case is ABOUT, asserted rather than assumed
			expect(world.built.report().tableEditing).toBe(false)
			expect(world.built.report().tableOpenedKey).toBe(nil)
			expect(world.adapter.node(raTrayPath("trailing", "delete"))).toBe(nil)

			swipeRow(world, -0.3, pointerType, activate)
			expect(world.adapter.node(raTrayPath("trailing", "delete")) ~= nil).toBe(true)
			expect(world.built.report().tableEditing).toBe(false) -- never a prerequisite, never turned on
			expect(world.built.report().tableOpenedKey).toBe(nil) -- a swipe is not a tap
			expect(world.built.report().tableIds[1]).toBe("m1") -- and not a reorder either
			--[[ ...AND IT IS NOT A SELECTION EITHER, which is the assertion that
				makes the MOUSE cases bite (redteam NEW-3, 2026-08-13). The four
				verdicts above are what a TOUCH Activate would have disturbed: on
				touch, this table's `onPrimaryAction` opens the row, so `after`
				closed the tray and `before` set `tableOpenedKey`. A MOUSE
				`Activated` does neither — a single click REPLACE-SELECTS the row —
				and nothing here was looking at selection, so `RowActions mouse:
				... (before)` was vacuous for its own combination: every one of its
				assertions held against unfixed source (measured: selection went
				`{"m1"}` unfixed, `{}` fixed, with the other four verdicts identical
				either way). A swipe selects nothing on ANY pointer kind, so this
				belongs on all four cases and only reads as redundant on two. ]]
			expect(world.built.report().tableSelectedKeys).toEqual({})
			expect(world.core:lastError()).toBeNil()
			expect(#world.handle.controller.diagnostics()).toBe(0)
			teardown(world)

			-- LEADING — "either side", in the director's words. A FRESH world,
			-- not a second swipe on the one above: swiping the other way out of
			-- an already-open tray is the CLOSE gesture, which would have passed
			-- this case for entirely the wrong reason.
			local lead = tableWorld()
			expect(lead.adapter.node(raTrayPath("leading", "read"))).toBe(nil)
			swipeRow(lead, 0.3, pointerType, activate)
			expect(lead.adapter.node(raTrayPath("leading", "read")) ~= nil).toBe(true)
			expect(lead.built.report().tableEditing).toBe(false)
			expect(lead.built.report().tableOpenedKey).toBe(nil)
			expect(lead.built.report().tableIds[1]).toBe("m1")
			expect(lead.built.report().tableSelectedKeys).toEqual({})
			expect(lead.core:lastError()).toBeNil()
			expect(#lead.handle.controller.diagnostics()).toBe(0)
			teardown(lead)
		end)
	end

	--[[ THE OTHER HALF OF THE SAME RULE: the suppression is ONE activate wide.
		A swipe swallows its own release artifact and nothing else — the tap that
		follows it is a genuine tap and must reach the control (iOS: it closes the
		open tray). A suppression that outlived its gesture would look exactly like
		the fix from every angle this file otherwise checks. ]]
	--[[ ...AND A GESTURE THAT PRODUCES NO ACTIVATE AT ALL LEAVES NOTHING ARMED.
		A release landing off the button is a real engine outcome and it is the one
		case the "swallow exactly one Activate" arm cannot clear itself — the next
		press is what clears it (`hitOnPointerDown`, mirroring `virtual_list.luau`'s
		own hosted dispatcher). Without that clear the swipe would eat the NEXT
		tap instead of its own artifact, and every other case in this file would
		still pass. `pointerUp` with no order is exactly that silent release. ]]
	it("RowActions: a swipe whose release produces no Activate does not swallow the NEXT tap", function()
		local world = tableWorld()
		local rect = world.adapter.node(RA_ROW_HIT).rect
		local startX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		local dx = rect.w * -0.3
		world.adapter.pointerDown(RA_ROW_HIT, startX, y, "touch")
		for i = 1, 8 do
			world.adapter.pointerMove(startX + dx * (i / 8), y, "touch")
		end
		world.presenter.refresh()
		world.adapter.pointerUp(startX + dx, y) -- released OFF the button: no Activated
		world.settle(120)
		expect(world.adapter.node(raTrayPath("trailing", "delete")) ~= nil).toBe(true)

		world.adapter.touchTap(RA_ROW_HIT)
		world.settle(120)
		expect(world.adapter.node(raTrayPath("trailing", "delete"))).toBe(nil) -- the tap was heard
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("RowActions: the swallowed activate is the swipe's OWN — the next tap still closes the tray", function()
		local world = tableWorld()
		swipeRow(world, -0.3, "touch", "after")
		expect(world.adapter.node(raTrayPath("trailing", "delete")) ~= nil).toBe(true)

		world.adapter.touchTap(RA_ROW_HIT)
		world.settle(120)
		expect(world.adapter.node(raTrayPath("trailing", "delete"))).toBe(nil) -- closed by the tap
		expect(world.built.report().tableOpenedKey).toBe(nil) -- and the close consumed it
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

	it("KEYBOARD DELETE on a row nobody has swiped removes it, building exactly one engine", function()
		--[[ The showcase half of parity round 3's owed row 9. On this surface a
			hosted row's engine — and with it the whole Delete/menu key surface —
			used to exist only after a pointer swipe, so a keyboard-only or
			pad-only player could not act on a row at all. The list now stands in
			for the engine and materialises it on the press: `engineCount` goes
			0 -> 1 for the row the ring was on, and no other. (The step reads that
			count at the press; by the time the commit's collapse has settled the
			row is out of the data and the list has dropped its engine with it —
			which is the retention policy working, not the count being wrong.) ]]
		local world = vlistWorld()
		expect(world.built.steps.vlistDebug(world.built).engineCount).toBe(0)
		local before = world.built.report().vlistIds
		local result = step(world, "keyDeleteVList", "m3")
		expect(result.ok).toBe(true)
		expect(result.hosted.engineCount).toBe(1) -- built BY the press
		local after = world.built.report().vlistIds
		expect(#after).toBe(#before - 1)
		for _, id in after do
			expect(id).never().toBe("m3")
		end
		expect(world.built.steps.vlistDebug(world.built).engineCount).toBe(0) -- and dropped with the row
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("GAMEPAD ButtonX on an unswiped row opens its action menu (the pad's route to Flag/Mark Read)", function()
		local world = vlistWorld()
		local result = step(world, "menuVList", "m2")
		expect(result.ok).toBe(true)
		local menuNodes = 0
		for _, path in world.adapter.paths() do
			if string.find(path, "RowActionsMenu", 1, true) ~= nil then
				menuNodes += 1
			end
		end
		expect(menuNodes > 0).toBe(true)
		expect(result.hosted.engineCount).toBe(1)
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
		-- ...WITH the fixture's own `present` opts (C2, 2026-08-12). This used to
		-- read `present(built.screen)`, faithfully mirroring a host that dropped
		-- the second argument — so the mirror was as wrong as the thing it
		-- mirrored. The host now forwards it (init.client.luau, fixture branch),
		-- and the delivery itself is pinned in gallery_demo_picker.spec.
		built.handle = presenter.present(built.screen, built.present)
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

-- ===== B5: the chrome gives way, not the list ==============================
--
-- Device report 2026-08-12 (`IMG_3689`, docs/plans/device-bug-round-2026-08-12.md
-- finding B5): on a landscape phone, in the showcase, the mail table was ENTIRELY
-- BELOW THE FOLD and nothing scrolled — the picker chip strip took 120px off the
-- top and this screen's own `title`-sized heading, mode bar and Edit toolbar took
-- the rest, leaving the table 27px and then 0. A `fill` pane absorbs that squeeze
-- silently, which is why it survived every portrait capture and every count-based
-- assertion.
--
-- The generic instrument for the class is `tests/overflow_sweep.spec.luau`, which
-- fails on the solver's own main-axis diagnostic for every showcase surface at
-- seven viewports. It is not enough on its own HERE: a pane squeezed to 20px does
-- not overflow, it just cannot be used. So this pins the outcome the report was
-- actually about — on a short landscape the list is on screen with room to read,
-- and the heading is the thing that went.
describe("row_actions scenario: a short landscape spends its height on the list (B5)", function()
	local SHOWCASE_TOP = 120 -- demo_picker.barReservation(58, nil, 8) — the strip the picker reserves

	local function shortLandscape(mode: string): any
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 640, h = 320 })
		env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
		env:set("preferredInput", "Touch")
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		local built = scenario.build({
			LuauUI = LuauUI,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			actionSystem = system,
			record = function() end,
			flags = {},
			geometry = function()
				return {}
			end,
		})
		built.handle = presenter.present(built.screen, built.present)
		-- the hosted list publishes its window from its own solved pane, so the
		-- settled frame is the one a player sees (same bounded settle the sweep uses)
		for _ = 1, 3 do
			presenter.refresh()
		end
		built.steps.mode(built, mode)
		for _ = 1, 3 do
			presenter.refresh()
		end
		return { core = core, adapter = adapter, presenter = presenter, built = built }
	end

	it("✓ the heading is dropped on a short viewport and kept on a tall one", function()
		local short = shortLandscape("list")
		expect(short.adapter.node("/MailActions/HeadingWhen/then/Title")).toBe(nil)
		short.presenter.dismiss(short.built.handle)

		local world = makeWorld() -- 400x700: not short
		expect(world.adapter.node("/MailActions/HeadingWhen/then/Title") ~= nil).toBe(true)
		teardown(world)
	end)

	-- the FIRST MAIL ROW on each surface. "Entirely below the fold and completely
	-- unreachable" is a claim about this node, so this is what the case asserts —
	-- not a pixel budget, which would only be the same magic constant the fixture
	-- just stopped carrying.
	local SURFACES = {
		{
			mode = "list",
			body = "/MailActions/ListWhen/then/List",
			row = "/MailActions/ListWhen/then/List/Rows/RowsForEach/[m1]/m1",
		},
		{
			mode = "table",
			body = "/MailActions/TableWhen/then/TablePane/MailTable",
			row = "/MailActions/TableWhen/then/TablePane/MailTable/Main/Body/Rows/[m1@0]/RowActions-m1/Content/Row",
		},
		{
			mode = "vlist",
			body = "/MailActions/VListWhen/then/VListPane/VList",
			row = "/MailActions/VListWhen/then/VListPane/VList/Canvas/W/[m1]/Row",
		},
	}

	for _, surface in SURFACES do
		it(`✓ {surface.mode}: the first mail row is on screen, and nothing overflows`, function()
			local w = shortLandscape(surface.mode)
			local screen = w.adapter.node("/MailActions")
			local body = w.adapter.node(surface.body)
			local row = w.adapter.node(surface.row)
			expect(body ~= nil).toBe(true)
			if row == nil then
				error(`{surface.mode}: no mail row is mounted at all inside a {screen.rect.h}px screen (B5)`, 0)
			end
			-- THE ROW IS INSIDE THE SCREEN, top and bottom. IMG_3689 had the table
			-- header alone at the very bottom edge and every row below it.
			local screenBottom = screen.rect.y + screen.rect.h
			if row.rect.y < screen.rect.y or row.rect.y + row.rect.h > screenBottom then
				error(
					`{surface.mode}: the first mail row solved to {row.rect.y}..{row.rect.y + row.rect.h} `
						.. `outside the {screen.rect.y}..{screenBottom} screen — below the fold (B5)`,
					0
				)
			end
			-- ...and the list body itself is a quarter of the screen or better: a
			-- screen whose whole subject is a list does not spend three quarters of a
			-- landscape phone on its own chrome. 27px of 591 was the device report.
			if body.rect.h * 4 < screen.rect.h then
				error(
					`{surface.mode}: the list solved to {body.rect.h}px inside a {screen.rect.h}px screen — `
						.. `under a quarter of it (B5: the chrome ate the content)`,
					0
				)
			end
			-- ...and the screen still says nothing overflows, so the height it got
			-- was given to it rather than painted past its box
			expect(#w.built.handle.controller.diagnostics()).toBe(0)
			expect(w.core:lastError()).toBeNil()
			w.presenter.dismiss(w.built.handle)
		end)
	end
end)
