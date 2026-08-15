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

	it("a resizable column grows a divider and a locked one refuses — both invisibly, so the readout names them", function()
		local w = world()
		expect(w.adapter.node(`{HEADER}/Head-name/Grip`) ~= nil).toBe(true)
		expect(w.adapter.node(`{HEADER}/Head-team/Grip`) ~= nil).toBe(true)
		expect(w.adapter.node(`{HEADER}/Head-best/Grip`)).toBe(nil)
		-- the fixture's own sentence about the same three facts
		expect(w.built.widths:get()).toBe("Entrant auto · Team auto · Best lap locked")
		w.built.dispose()
	end)
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

	it("SELECTING A COLUMN PAINTS NOTHING, so the hint line is the only thing that says the arrows moved house", function()
		local w = world()
		expect(w.built.hint:get()).toBe("Drag a divider, or Tab to a heading and press Return")
		key(w, "Return")
		expect(w.built.hint:get()).toBe("Entrant has the keys: , and . resize it, ↑/↓ sorts")
		key(w, "Return") -- and the second Activate hands them back
		expect(w.built.hint:get()).toBe("Drag a divider, or Tab to a heading and press Return")
		w.built.dispose()
	end)

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

	THIS SPEC CANNOT SEE THAT. `controller.tapAt` is the FRAMEWORK's hit test and it
	arbitrates on solved rects, not on the adapter's expander instances — it answers
	`Column` at every one of those points. So what is pinned here is the GEOMETRY
	that produces the defect, which is the part a headless run can honestly hold:
	the requested hit rect and the z relationship. If either changes, this reddens
	and the live table above has to be re-measured. ]]
describe("the resize grip's hit floor lands on top of its own header button", function()
	it("asks for 44x44 centred on an 8x28 grip, which eats 26px of the header cell it sits in", function()
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
		-- wins the press. A grip that sorted BELOW its Column button would make the
		-- live table above impossible.
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
