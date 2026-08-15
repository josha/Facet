--!strict
--[[
	THE HEADER AND ITS RESIZE DIVIDERS — the half of `newTable` that shipped in
	Phase B and had no showcase surface until 2026-08-14.

	`tests/table.spec.luau` already proves the MODEL and the HANDLERS: a grip
	drag previews a guide line and commits on release, an Adjust step is 16px and
	min-clamped, a non-resizable column grows no grip. It does that against
	`fake_target`, which dispatches a pointer event to the path it is HANDED —
	so it is a proof about wiring and structurally cannot be a proof about
	whether a real finger can land on the thing.

	THIS FILE IS THE FIXTURE'S OWN SPEC, and it asks the questions that a
	fixture makes askable and a bare control does not:

	  · IS THE HEADER VISIBLE — a non-zero title box per column, not merely a node
	    at a path. `docs/plans/swiftui-parity-round3-brief.md` records the class:
	    a losing `ViewThatFits` candidate stays mounted with its text intact at
	    0x0, so presence is not visibility.
	  · IS IT REACHABLE WITH NO CONSUMER WIRING. The showcase host presents the
	    fixture with `present = {}` — it hands the presenter no `onActivate`, no
	    `onAdjust`, nothing. Everything below therefore rides the Table's own
	    contribution, which is the only configuration a player is ever in.
	  · DOES THE READOUT MOVE. A resize is a CHANGE and a screenshot cannot hold
	    one, so the fixture's whole argument is a number on screen — and that
	    number only exists because `api.columnWidthOverrides` is a Readable. A
	    pointer drag commits inside the control and fires no consumer callback.
	  · HOW BIG IS THE DIVIDER. Measured, per paradigm, against this repo's own
	    touch-target floor — because the answer is a device finding, not a demo.
	  · DOES IT SURVIVE VIRTUALIZATION. `virtualized` landed on the same control
	    the same week; a committed width has to remount the WINDOWED rows.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local table_control = require("../src/controls/table")
local fake_target = require("../tests/lib/fake_target")
local scenario = require("../examples/gallery/scenarios/table_columns") :: any

local ROOT = "/TableColumns/TablePane/Entrants"
local HEADER = `{ROOT}/Main/Header`

type World = {
	core: any,
	env: any,
	system: any,
	adapter: any,
	pres: any,
	built: any,
}

--[[ THE SHOWCASE HOST'S OWN MOUNT, not a re-implementation of it: the fixture
	branch of `examples/gallery/client/init.client.luau` builds with exactly this
	ctx and presents with exactly `built.present`. Nothing here hands the presenter
	a handler, which is the point — a player gets whatever the Table contributes
	for itself. ]]
local function world(opts: any?): World
	local o: any = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 900, h = 640 })
	if o.preferredInput ~= nil then
		env:set("preferredInput", o.preferredInput)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local built = scenario.build({
		LuauUI = LuauUI,
		core = core,
		env = env,
		actionSystem = system,
		presenter = pres,
		adapter = adapter,
	})
	built.handle = pres.present(built.screen, built.present)
	pres.refresh()
	return { core = core, env = env, system = system, adapter = adapter, pres = pres, built = built }
end

local function headWidth(w: World, columnId: string): number
	return w.adapter.node(`{HEADER}/Head-{columnId}`).rect.w
end

local function key(w: World, code: string)
	w.system.deviceKey(code, true)
	w.system.deviceKey(code, false)
	w.pres.refresh()
end

describe("table_columns fixture: the header is on screen and legible", function()
	it("every column paints a title box with real area — presence is not visibility", function()
		local w = world()
		for _, id in { "name", "team", "best" } do
			local title = w.adapter.node(`{HEADER}/Head-{id}/Title`)
			expect(`{id}:mounted:{title ~= nil}`).toBe(`{id}:mounted:true`)
			expect(`{id}:w>0:{title.rect.w > 0}`).toBe(`{id}:w>0:true`)
			expect(`{id}:h>0:{title.rect.h > 0}`).toBe(`{id}:h>0:true`)
		end
		-- ...and the band sits ABOVE the first row rather than on top of it, which
		-- is the failure a `fixed` header height produced at the largest text
		-- preference (src/controls/table.luau's `minMax` FLOOR note)
		local band = w.adapter.node(`{HEADER}/Head-name`)
		local firstCell = w.adapter.node(`{ROOT}/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name`)
		expect(`clear:{firstCell.rect.y >= band.rect.y + band.rect.h}`).toBe("clear:true")
		w.built.dispose()
	end)

	it(
		"a resizable column grows a divider and a locked one refuses — both invisibly, so the readout names them",
		function()
			local w = world()
			expect(w.adapter.node(`{HEADER}/Head-name/Grip`) ~= nil).toBe(true)
			expect(w.adapter.node(`{HEADER}/Head-team/Grip`) ~= nil).toBe(true)
			expect(w.adapter.node(`{HEADER}/Head-best/Grip`)).toBe(nil)
			-- the fixture's own sentence about the same three facts
			expect(w.built.widths:get()).toBe("Entrant auto · Team auto · Best lap locked")
			w.built.dispose()
		end
	)
end)

describe("table_columns fixture: the three routes all move the same column", function()
	it("a pointer drag on the divider MOVES the column, and the live readout follows the commit", function()
		local w = world()
		local before = headWidth(w, "name")
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		w.adapter.pointerDown(`{HEADER}/Head-name/Grip`, grip.rect.x + grip.rect.w, grip.rect.y + 2)
		w.adapter.pointerMove(grip.rect.x + grip.rect.w - 90, grip.rect.y + 2)
		w.pres.refresh()
		-- a PREVIEW during the drag: the column has not moved yet
		expect(`during:{headWidth(w, "name") == before}`).toBe("during:true")
		w.adapter.pointerUp(grip.rect.x + grip.rect.w - 90, grip.rect.y + 2)
		w.pres.refresh()
		local after = headWidth(w, "name")
		expect(`moved:{after < before}`).toBe("moved:true")
		expect(`delta:{before - after}`).toBe("delta:90")
		-- THE READOUT IS THE DEMO. It only moves because the widths are a Readable;
		-- a pointer drag commits inside the control and calls nothing back.
		expect(w.built.widths:get()).toBe(`Entrant {after}px · Team auto · Best lap locked`)
		w.built.dispose()
	end)

	it("a KEYBOARD reaches it with no consumer wiring: Tab to the heading, Return, then the arrows", function()
		local w = world()
		local before = headWidth(w, "name")
		-- the header handle is a focus stop the Table contributes for itself
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-name/Column`)
		key(w, "Return") -- a device Activate SELECTS the column
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		key(w, "Right")
		expect(`wider:{headWidth(w, "name") - before}`).toBe("wider:16")
		key(w, "Left")
		key(w, "Left")
		expect(`narrower:{headWidth(w, "name") - before}`).toBe("narrower:-16")
		w.built.dispose()
	end)

	it("a GAMEPAD reaches it: the bumper steps the focused heading without selecting anything", function()
		local w = world()
		local before = headWidth(w, "name")
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-name/Column`)
		key(w, "ButtonR1")
		expect(`wider:{headWidth(w, "name") - before}`).toBe("wider:16")
		-- ...and it did NOT need the column selected first, which is the difference
		-- between the bumper route and the stick route
		expect(w.built.table_.api.selectedColumn:get()).toBe(nil)
		key(w, "ButtonL1")
		expect(`back:{headWidth(w, "name") - before}`).toBe("back:0")
		w.built.dispose()
	end)

	it(
		"SELECTING A COLUMN PAINTS NOTHING, so the hint line is the only thing that says the arrows moved house",
		function()
			local w = world()
			expect(w.built.hint:get()).toBe("Drag a divider, or Tab to a heading and press Return")
			key(w, "Return")
			expect(w.built.hint:get()).toBe("Entrant has the keys: , and . resize it, ↑/↓ sorts")
			key(w, "Return") -- and the second Activate hands them back
			expect(w.built.hint:get()).toBe("Drag a divider, or Tab to a heading and press Return")
			w.built.dispose()
		end
	)

	it("a LOCKED column binds no Adjust key at all — the bumper stays the game's", function()
		local w = world()
		-- walk the header group to the column that refuses
		key(w, "Right")
		key(w, "Right")
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-best/Column`)
		local before = `{headWidth(w, "name")}/{headWidth(w, "team")}/{headWidth(w, "best")}`
		-- ONE press, not a press and its inverse: R1 followed by L1 nets to zero and
		-- would pass whether or not the key was bound, which is a check that proves
		-- nothing. This one only passes if nothing moved.
		key(w, "ButtonR1")
		expect(`{headWidth(w, "name")}/{headWidth(w, "team")}/{headWidth(w, "best")}`).toBe(before)
		-- THE POSITIVE CONTROL, same session, same key: on a RESIZABLE heading the
		-- identical bumper does move the column. Without this, "nothing happened" is
		-- equally explained by "no bumper ever arrived".
		key(w, "Left")
		key(w, "Left")
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-name/Column`)
		local nameBefore = headWidth(w, "name")
		key(w, "ButtonR1")
		expect(`control:{headWidth(w, "name") - nameBefore}`).toBe("control:16")
		w.built.dispose()
	end)
end)

describe("table_columns fixture: the scenario contract", function()
	it("its steps drive the DEVICE funnels, and each one moves the model", function()
		local w = world()
		local before = headWidth(w, "name")
		w.built.steps.select()
		w.pres.refresh()
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		w.built.steps.wider()
		w.pres.refresh()
		expect(`wider:{headWidth(w, "name") - before}`).toBe("wider:16")
		w.built.steps.narrower()
		w.built.steps.narrower()
		w.pres.refresh()
		expect(`narrower:{headWidth(w, "name") - before}`).toBe("narrower:-16")
		local report = w.built.report()
		expect(report.selectedColumn).toBe("name")
		expect(report.rows).toBe(28)
		w.built.dispose()
	end)

	it("disposes clean: no node of this fixture survives, and the core reports no error", function()
		local w = world()
		expect(w.adapter.node(`{HEADER}/Head-name`) ~= nil).toBe(true)
		w.built.dispose()
		w.pres.dismiss(w.built.handle)
		w.pres.refresh()
		expect(w.adapter.node(`{HEADER}/Head-name`)).toBe(nil)
		expect(w.core:lastError()).toBeNil()
	end)
end)

--[[ THE DIVIDER'S HIT BOX, per paradigm — a MEASUREMENT, not a demo.

	`gripFor` declares `width = { type = "fixed", px = "s" }`: the theme's small
	spacing step. That is a fine visual hairline and it is the whole target a
	finger has to land on, so the number is worth pinning next to this repo's own
	touch floor rather than left as a token nobody resolved.

	This case does not assert a PASS — it asserts the measured number, so the day
	the token moves (or a paradigm gains its own value) the change is announced
	rather than absorbed. The verdict lives in the mission report and in
	`docs/lessons/`, where a finding belongs. ]]
describe("table_columns: how big the divider actually is", function()
	it("the grip is the theme's small spacing step in every paradigm, touch included", function()
		local measured = {}
		for _, input in { "KeyboardAndMouse", "Touch", "Gamepad" } do
			local w = world({ preferredInput = input })
			local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
			-- THE POSITIVE CONTROL: the ROW box IS paradigm-derived
			-- (`controls.table.rowHeight.touch`), so if the row height does not move
			-- between these three the paradigm never switched and the grip
			-- measurement beside it would prove nothing.
			local row = w.adapter.node(`{ROOT}/Main/Body/Rows/[r1@0]/Row`)
			table.insert(measured, `{input}=grip{grip.rect.w}x{grip.rect.h}/row{row.rect.h}`)
			w.built.dispose()
		end
		--[[ THE FINDING, PINNED AS A NUMBER (2026-08-14).

			The ROW grows for touch — 36px under a pointer, 44px under a finger,
			which is `controls.table.rowHeight.touch` floored at
			`targetSizes.minimum`. That is the positive control, and it fires.

			THE DIVIDER DOES NOT. `gripFor` declares `px = "s"`, a space step, and a
			space step has no paradigm: the resize handle is EIGHT PIXELS WIDE on a
			phone, against the same theme's own 44px touch floor. Five and a half
			times under the floor this project holds every other target to, on the
			one control whose row height exists BECAUSE of that floor.

			Pinned rather than fixed here because the fix is a design call about
			where a touch divider's slop comes from (a wider Grip paints a fat
			hairline; an invisible hit inset does not exist as a Box prop today), and
			`docs/lessons/an-eight-pixel-divider-on-a-forty-four-pixel-finger.md`
			carries it. The day it is fixed this line changes, deliberately. ]]
		expect(table.concat(measured, " ")).toBe(
			"KeyboardAndMouse=grip8x28/row36 Touch=grip8x28/row44 Gamepad=grip8x28/row36"
		)
	end)
end)

--[[ THE 44px HIT FLOOR EXPANDS THE DIVIDER OVER ITS OWN HEADER BUTTON.

	`src/controls/contract.luau` gives Grip `minHitSize = 44`, so the renderer asks
	the adapter for a 44x44 hit rect CENTRED on an 8x28 grip. On the live engine
	that is a real `LuauUIHitExpander` TextButton parented beside the grip at
	`grip.z - 1` — which is still ABOVE the header cell's own `Column` button, and a
	GuiButton sinks `InputBegan` (docs/lessons/a-button-eats-the-swipe-underneath-it).

	MEASURED LIVE, 2026-08-14, LuauUI-Showcase, this fixture, with the control in
	the same session (docs/lessons/a-forty-four-pixel-floor-under-an-eight-pixel-
	divider.md):

	  | click            | inside              | result        |
	  |------------------|---------------------|---------------|
	  | (264, 134)       | name header, over the expander | NOTHING |
	  | (100, 134)       | name header, clear of it       | sort cycles, mark '▲' |

	RULED AND FIXED THE SAME DAY (director, option 1 of the four the lesson listed):
	the expander now runs the grip's own gesture, so the 44x44 IS the drag target the
	floor always claimed; and a press that never travels forwards through
	`controller.tapAt` to the `Column` button underneath, so the band sorts. THE
	GEOMETRY BELOW IS UNCHANGED BY THAT FIX AND STAYS PINNED AT THE SAME NUMBERS —
	the repair was to what the rect DOES, not to where it is. It is still the
	geometry that would make the dead band possible, so if any of the three moves,
	the live table has to be re-measured before the behaviour above can be claimed
	again.

	THIS CASE STILL CANNOT SEE THE BEHAVIOUR. `controller.tapAt` is the FRAMEWORK's
	hit test and it arbitrates on solved rects, not on the adapter's expander
	instances — it answers `Column` at every one of those points, before and after.
	The behaviour is held by "the divider forwards a press it did not turn into a
	drag" (below), by the adapter source anchors in `tests/adaptive.spec.luau`, and
	by the live drive in the lesson. ]]
describe("the resize grip's hit floor lands on top of its own header button", function()
	it("asks for 44x44 centred on an 8x28 grip, which covers 26px of the header cell it sits in", function()
		local w = world()
		local cell = w.adapter.node(`{HEADER}/Head-name`)
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		local column = w.adapter.node(`{HEADER}/Head-name/Column`)
		expect(`grip:{grip.rect.w}x{grip.rect.h}`).toBe("grip:8x28")
		expect(`hit:{grip.hitRect.w}x{grip.hitRect.h}`).toBe("hit:44x44")
		-- how much of the header cell the expanded rect covers, left of the grip
		local eaten = grip.rect.x - grip.hitRect.x
		expect(`eaten:{eaten}`).toBe("eaten:18")
		-- ...and the whole band, grip included, measured from the cell's right edge
		local band = (cell.rect.x + cell.rect.w) - grip.hitRect.x
		expect(`band:{band}`).toBe("band:26")
		-- THE Z RELATIONSHIP IS THE OTHER HALF. The engine paints the expander at
		-- `grip.z - 1`, and the header's own button is lower still, so the expander
		-- wins the press. It is what made the band dead before the ruling, and after
		-- it it is what makes the band a RESIZE target: the expander has to be the
		-- topmost thing under a finger aiming at the divider, or the header button
		-- would take the press and there would be nothing to promote into a drag.
		-- The same number, load-bearing for the opposite reason.
		expect(`above:{grip.z - 1 > column.z}`).toBe("above:true")
		w.built.dispose()
	end)
end)

--[[ RESIZE x VIRTUALIZATION — a combination that is one week old on both sides.

	`virtualized` mounts the body as a full-extent Canvas with absolutely
	positioned windowed rows instead of a flowing stack, and a committed resize
	bumps `widthsVersion`, which is interpolated into every ForEach row key. The
	question is whether the WINDOW remounts at the new width, or whether the rows
	the window happens to hold keep the old one. ]]
describe("column resize on a VIRTUALIZED table", function()
	local function virtualWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local rows = {}
		for i = 1, 2000 do
			table.insert(rows, { id = `r{i}`, n = i })
		end
		local tbl = table_control.build(LuauUI, core, {
			id = "V",
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
					value = function(item: any)
						return `#{item.n}`
					end,
				},
				{
					id = "laps",
					title = "Laps",
					width = { type = "fixed", px = 64 },
					value = function(item: any)
						return tostring(item.n)
					end,
				},
			},
			rows = core:signal(rows),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			header = true,
			virtualized = true,
			selection = "single",
			env = env,
		})
		local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } }), {})
		pres.refresh()
		return adapter, pres, tbl, handle, core
	end

	it("a committed width remounts the WINDOWED rows at the new width, and the window stays bounded", function()
		local adapter, pres, tbl = virtualWorld()
		local before = adapter.node("/S/V/Main/Header/Head-name").rect.w
		local windowBefore = tbl.dump().windowRows
		expect(`bounded:{windowBefore < 40}`).toBe("bounded:true")
		tbl.api.setColumnWidth("name", before - 120)
		pres.refresh()
		expect(adapter.node("/S/V/Main/Header/Head-name").rect.w).toBe(before - 120)
		-- THE ROWS, not just the band: a windowed row is mounted under a key that
		-- carries the widths version, so a stale row would still be at `before`
		local firstCell = adapter.node("/S/V/Main/Body/Canvas/Rows/[r1@1]/Row/Cells/Cell-name")
		expect(`row:{firstCell ~= nil and firstCell.rect.w or -1}`).toBe(`row:{before - 120}`)
		expect(`stillBounded:{tbl.dump().windowRows == windowBefore}`).toBe("stillBounded:true")
	end)

	it("...and it is still 2 000 rows the table never mounted", function()
		local adapter, pres, tbl = virtualWorld()
		tbl.api.setColumnWidth("name", 200)
		pres.refresh()
		expect(tbl.dump().rowCount).toBe(2000)
		expect(`mounted:{tbl.dump().windowRows < 40}`).toBe("mounted:true")
		expect(adapter.node("/S/V/Main/Body/Canvas/Rows/[r1500@1]/Row/Cells/Cell-name")).toBe(nil)
	end)
end)

--[[ A PRESS IN THE 44px BAND THAT NEVER MOVES IS A TAP, AND A TAP BELONGS TO THE
	HEADER UNDERNEATH (director ruling, 2026-08-14 — option 1 of the four in
	`docs/lessons/a-forty-four-pixel-floor-under-an-eight-pixel-divider.md`).

	The lesson measured two symptoms of one mechanism: the grip's `minHitSize = 44`
	expander SANK every press in the trailing 26px of the header cell and forwarded
	nothing (a dead band), while buying the divider no drag target at all (the
	expander is painted BEHIND the grip). The ruled repair gives the expander the
	grip's own gesture — so the 44px band really is the resize target — and makes a
	press the gesture did NOT claim forward on through `controller.tapAt`, which is
	the machinery `row_actions` already uses for exactly this (ruling 6, `aa1e271`).

	THE HALF THIS SPEC CAN HOLD is the control's: whether the grip distinguishes a
	tap from a drag and hands the tap on. The adapter half (the expander running the
	host's `InputBegan`) is engine-only and is asserted at the source anchors in
	`tests/adaptive.spec.luau`, then measured live.

	IT BITES: before the ruling `onPointerUp` committed `setColumnWidth(id, width)`
	unconditionally, so a press-and-release on the divider wrote a phantom width
	override for a column nobody had moved and cycled no sort. ]]
describe("table_columns: the divider forwards a press it did not turn into a drag", function()
	local function tapGrip(w: World, dx: number)
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		local x, y = grip.rect.x + 2, grip.rect.y + 4
		w.adapter.pointerDown(`{HEADER}/Head-name/Grip`, x, y)
		if dx ~= 0 then
			w.adapter.pointerMove(x + dx, y)
		end
		w.adapter.pointerUp(x + dx, y)
		w.pres.refresh()
	end

	it("a press and release with no travel sorts the column and commits NO width", function()
		local w = world()
		expect(w.built.report().sortOrder).toBeNil()
		tapGrip(w, 0)
		-- the tap reached the header cell's own Button, one layer down
		expect(`sorted:{w.built.report().sortOrder.column}`).toBe("sorted:name")
		-- ...and nothing was resized: `auto` is the readout for a column with no
		-- committed override at all
		expect(w.built.widths:get()).toBe("Entrant auto · Team auto · Best lap locked")
		w.built.dispose()
	end)

	it("travel UNDER the pointer promotion gate is still a tap; travel over it is a resize", function()
		local w = world()
		local before = headWidth(w, "name")
		-- 3px on a mouse: under `interaction_tokens.promotionPx("pointer")` = 6
		tapGrip(w, -3)
		expect(`under:{headWidth(w, "name") == before}`).toBe("under:true")
		expect(w.built.widths:get()).toBe("Entrant auto · Team auto · Best lap locked")
		-- the SAME gesture 40px further is the resize it always was — the positive
		-- control, because "nothing moved" is otherwise equally explained by a grip
		-- that stopped receiving presses at all
		tapGrip(w, -40)
		expect(`over:{headWidth(w, "name") - before}`).toBe("over:-40")
		w.built.dispose()
	end)

	it("the guide line does not appear for a press that never becomes a drag", function()
		local w = world()
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		local x, y = grip.rect.x + 2, grip.rect.y + 4
		w.adapter.pointerDown(`{HEADER}/Head-name/Grip`, x, y)
		w.adapter.pointerMove(x - 2, y)
		w.pres.refresh()
		-- a 44px band that flashed a resize guide under every press near a column
		-- edge would be the dead zone's cosmetic twin
		expect(w.adapter.node(`{ROOT}/ResizeWhen/then/ResizeLine`)).toBe(nil)
		w.adapter.pointerMove(x - 30, y)
		w.pres.refresh()
		expect(w.adapter.node(`{ROOT}/ResizeWhen/then/ResizeLine`) ~= nil).toBe(true)
		w.adapter.pointerUp(x - 30, y)
		w.pres.refresh()
		w.built.dispose()
	end)
end)

--[[ THE ARROW KEYS: THE CLAIM THAT WAS RULED, BUILT, MEASURED AND WITHDRAWN.

	`docs/lessons/the-camera-still-owns-the-arrow-keys.md` measured live 2026-08-14:
	Roblox's own default camera binds Left/Right as `RbxCameraKeypress` through
	ContextActionService at priority 2000 and SINKS them, so a selected column's
	Left/Right resize never receives a press. The ruled repair was a sinking
	`InputContext` above the camera, scoped to the selection.

	IT WAS BUILT AND IT DOES NOT WORK, and the measurement is in the second lesson
	round and in `src/controls/table.luau`'s own comment: a ContextActionService
	sink at priority **100** consumed both presses while a LuauUI `InputContext` at
	priority **10000, Sink = true** received nothing. The two priorities are not one
	arbitration space, so no number takes a key back from a CAS binding. What is
	left of the ruling is the RELEASE — which was a live bug in its own right, and
	is the half that ships.

	The engine truth itself is carried by `src/client/gamepad_contention.luau` (the
	module this repo already uses for "a CoreScript binding eats our key") and
	checked in `tests/gamepad_contention.spec.luau`. There is no headless surface
	for CAS at all, which is exactly why it took a live drive to find. ]]
describe("table_columns: a selected column is released the moment focus leaves it", function()
	it("Cancel releases it, and a second Activate releases it", function()
		local w = world()
		key(w, "Return")
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		key(w, "ButtonB")
		expect(w.built.table_.api.selectedColumn:get()).toBeNil()
		key(w, "Return")
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		key(w, "Return")
		expect(w.built.table_.api.selectedColumn:get()).toBeNil()
		w.built.dispose()
	end)

	--[[ THE LEAK, and it was already shipped.

		The presenter routes `focusMoved` only to the contributions whose mounted path
		is a PREFIX of the newly focused one, so focus leaving the Table entirely never
		reached `api.handleFocusMoved` and `releaseColumnOnFocusLeave` never ran. A
		column stayed selected after the ring had gone somewhere else — and a selected
		column swallows EVERY direction (`handleGrabNavigate` returns true for all four
		so the selection cannot be steered off) and answers Cancel. The ring was on
		another control and the arrows still belonged to a table nobody was looking at.

		Driven live in the showcase the same day, on the shipped fix: select Team,
		press Tab twice, and the hint line goes back to idle with the selection
		released. This needs a second control on the screen to move to, which the
		fixture deliberately does not have. ]]
	it("focus leaving the table entirely releases it too, however it left", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 640 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
					value = function(item: any)
						return item.id
					end,
				},
			},
			rows = core:signal({ { id = "r1" } }),
			key = function(item: any)
				return item.id
			end,
			header = true,
			env = env,
		})
		pres.present(
			LuauUI.UI.Screen({
				id = "S",
				children = { tbl.blueprint, LuauUI.UI.Button({ id = "Away", label = "Away", focusable = true }) },
			}),
			{}
		)
		pres.refresh()
		tbl.api.handleActivate("/S/T/Main/Header/Head-name/Column", { source = "action" })
		pres.refresh()
		expect(tbl.api.selectedColumn:get()).toBe("name")
		-- a selected column swallows every direction, so while it is held the ring
		-- cannot be steered off it: that is what makes a leaked selection permanent
		expect(`swallows:{tbl.api.handleGrabNavigate("down")}`).toBe("swallows:true")

		-- the ring goes somewhere this table does not own
		pres.focus.focusOn("/S/Away")
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/Away")
		expect(tbl.api.selectedColumn:get()).toBeNil()
		-- ...and it has stopped answering for a stick that is not its own
		expect(`released:{tbl.api.handleGrabNavigate("down")}`).toBe("released:false")
		tbl.dispose()
	end)
end)
