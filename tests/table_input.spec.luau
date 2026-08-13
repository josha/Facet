--!strict
-- Table cross-input WIRING tests (ui_todo §0; ADR-0013;
-- artifacts/input-adaptation-audit/wp-b-composites.md + matrix.md §1b).
--
-- These prove the DEVICE PATH end-to-end: every interaction runs through the
-- presenter's AUTO-COMPOSITION (zero present() opts) and the real adapter/action
-- seams — adapter.pointerDown/Move/Up (pointer + touch) and system.deviceKey
-- (keyboard = Down/Up/Return, gamepad = DPad*/ButtonA). No direct tbl.api.* call
-- drives an assertion here; the api-direct tests in tests/table.spec.luau keep
-- covering the logic layer, while THESE close the audit's "honest coverage" gaps:
--   1. header-sort keyboard/gamepad  (was MISSING — now the leading "headers"
--      NavigationGroup + focus/Activate cycles sortOrder)
--   2. body scroll-into-view keyboard/gamepad (was MISSING — focus that leaves
--      the clip band scrolls the body)
--   3. touch column-resize (was untested — grip drag on a TOUCH pointer)
--   4. device-true gamepad/keyboard row-select and grab-reorder (previously only
--      proven via tbl.api.* direct calls — now through deviceKey → presenter)

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local table_control = require("../src/controls/table")
local fake_target = require("../tests/lib/fake_target")

local function harness()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	return core, env, system, adapter, pres
end

local function bigRows(n: number): { any }
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, name = `Row {i}`, laps = i })
	end
	return out
end

local function hit(key: string): string
	return `/S/T/Main/Body/Rows/[{key}@0]/Row/Hit`
end

-- =============================================================================
-- 1. HEADER-SORT on keyboard + gamepad (was MISSING per the audit)
-- =============================================================================
describe("table_input: header-sort via keyboard and gamepad (auto headers group)", function()
	local NAME_SORT = "/S/T/Main/Header/Head-name/Column"
	local LAPS_SORT = "/S/T/Main/Header/Head-laps/Column"

	local function sortWorld()
		local core, env, system, adapter, pres = harness()
		local sortOrder = core:signal(nil :: any)
		local rows = core:signal(bigRows(3))
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
				{
					id = "laps",
					title = "Laps",
					width = 64,
					value = function(r: any)
						return tostring(r.laps)
					end,
				},
			},
			selection = "single",
			rowHeight = 40,
			sortOrder = sortOrder,
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- ZERO present opts: full auto-composition
		pres.refresh()
		return { system = system, adapter = adapter, pres = pres, sortOrder = sortOrder, handle = handle, tbl = tbl }
	end

	it("initial focus lands on the leading headers group (first sortable column)", function()
		local w = sortWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
	end)

	it("gamepad ButtonA SELECTS the column; the stick then acts on it (sort on Up/Down)", function()
		-- director 2026-07-29. A device Activate can no longer mean "sort", because
		-- a stick had nowhere to put "resize this" — so Activate selects the column
		-- and the stick acts on the selection: Left/Right resizes, Up/Down sorts.
		-- A POINTER tap still sorts directly (that convention is older than this
		-- table); see the mouse test in table.spec.
		local w = sortWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedColumn:get()).toBe("name")
		expect(w.sortOrder:get()).toBeNil() -- selecting is not sorting
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.sortOrder:get().column).toBe("name")
		expect(w.sortOrder:get().ascending).toBe(true)
		-- again on the SAME column flips ascending (SwiftUI cycle)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.sortOrder:get().ascending).toBe(false)
		-- ...and Activate again releases the column
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedColumn:get()).toBeNil()
	end)

	it("gamepad DPadLeft/DPadRight walk between sortable headers (horizontal group)", function()
		local w = sortWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(LAPS_SORT)
		-- select the second column and sort it: new column -> ascending
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.sortOrder:get().column).toBe("laps")
		expect(w.sortOrder:get().ascending).toBe(true)
		-- release it, then walking resumes
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.system.deviceKey("DPadLeft", true)
		w.system.deviceKey("DPadLeft", false)
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
	end)

	it("gamepad DPadDown exits headers to the rows; DPadUp re-enters the headers", function()
		local w = sortWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
	end)

	it("keyboard Right/Return drive the header sort identically to the gamepad", function()
		local w = sortWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(LAPS_SORT)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.tbl.api.selectedColumn:get()).toBe("laps")
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.sortOrder:get().column).toBe("laps")
		expect(w.sortOrder:get().ascending).toBe(true)
	end)
end)

-- =============================================================================
-- 2. BODY SCROLL-INTO-VIEW on keyboard + gamepad (was MISSING per the audit)
-- =============================================================================
describe("table_input: body scroll-into-view on keyboard/gamepad focus moves", function()
	local function scrollWorld()
		local core, env, system, adapter, pres = harness()
		local rows = core:signal(bigRows(20))
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "single",
			rowHeight = 40,
			height = { type = "fixed", px = 200 }, -- 5 rows of 20 visible
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- zero opts
		pres.refresh()
		-- wire the engine CanvasPosition mirror so keep-visible can scrollTo and
		-- the fake target echoes it back (native-substrate NS-A2)
		tbl.api.bindNativeScroll(handle.controller)
		return { system = system, adapter = adapter, pres = pres, handle = handle, tbl = tbl }
	end
	local function bodyRect(adapter: any): any
		return adapter.node("/S/T/Main/Body").rect
	end
	-- the engine CanvasPosition the framework wrote (the keep-visible target)
	local function canvasY(adapter: any): number
		return adapter.node("/S/T/Main/Body").scrollPosition.y
	end

	it("gamepad DPadDown past the clip band scrolls the focused row into view", function()
		local w = scrollWorld()
		local body = bodyRect(w.adapter)
		-- rows 1..5 fit; focus starts on r1, fully visible, no scroll yet
		expect(w.adapter.node(hit("r1")).rect.y).toBe(body.y)
		expect(canvasY(w.adapter)).toBe(0)
		-- step down to r6 (the first row past the band)
		for _ = 1, 5 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
		end
		expect(w.pres.focus.focused:get()).toBe(hit("r6"))
		w.pres.refresh()
		-- keep-visible wrote a programmatic CanvasPosition through the native seam:
		-- r6 (canvas bottom 6*40) minus the body viewport height. Row RECTS stay at
		-- their absolute canvas offsets (the engine translates by CanvasPosition).
		expect(canvasY(w.adapter)).toBe(6 * 40 - body.h)
		expect(w.adapter.node(hit("r1")).rect.y).toBe(body.y)
		expect(w.adapter.node(hit("r6")).rect.y).toBe(body.y + 5 * 40)
	end)

	it("keyboard Down/Up scrolls both directions; scrolling back up reveals r1 again", function()
		local w = scrollWorld()
		local body = bodyRect(w.adapter)
		for _ = 1, 8 do -- drive well past the band (to r9)
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
		end
		expect(w.pres.focus.focused:get()).toBe(hit("r9"))
		w.pres.refresh()
		-- r9 (canvas bottom 9*40) into the body viewport => that minus body.h
		expect(canvasY(w.adapter)).toBe(9 * 40 - body.h)
		-- walk back up to r1: the body must scroll DOWN (CanvasPosition -> 0)
		for _ = 1, 8 do
			w.system.deviceKey("Up", true)
			w.system.deviceKey("Up", false)
		end
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		w.pres.refresh()
		expect(canvasY(w.adapter)).toBe(0) -- back at the top
	end)

	it("navigating within the visible band never scrolls (minimal scroll)", function()
		local w = scrollWorld()
		-- r1 -> r4, all inside the 5-row band: no keep-visible scroll issued
		for _ = 1, 3 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
		end
		expect(w.pres.focus.focused:get()).toBe(hit("r4"))
		w.pres.refresh()
		expect(canvasY(w.adapter)).toBe(0) -- CanvasPosition untouched
	end)
end)

-- =============================================================================
-- 3. TOUCH column-resize through the pointer seam (was untested per the audit)
-- =============================================================================
describe("table_input: touch column-resize through the grip pointer seam", function()
	local function resizeWorld()
		local core, env, system, adapter, pres = harness()
		local rows = core:signal(bigRows(3))
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
					value = function(r: any)
						return r.name
					end,
				},
				{
					id = "laps",
					title = "Laps",
					width = 64,
					value = function(r: any)
						return tostring(r.laps)
					end,
				},
			},
			selection = "single",
			rowHeight = 40,
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- zero opts (grip drag is framework-automatic)
		pres.refresh()
		return { adapter = adapter, pres = pres, handle = handle }
	end
	local GRIP = "/S/T/Main/Header/Head-name/Grip"

	it("a TOUCH drag on the grip previews and commits the new column width", function()
		local w = resizeWorld()
		local cell = w.adapter.node("/S/T/Main/Header/Head-name").rect
		expect(cell.w).toBe(736) -- 800 viewport - 64 fixed
		-- Table treats grip drags as reorder-exempt on ANY pointer (ui_todo §3):
		-- the SAME seam the mouse test uses, driven with a "touch" pointer.
		w.adapter.pointerDown(GRIP, cell.x + cell.w, 10, "touch")
		w.adapter.pointerMove(cell.x + cell.w - 100, 12, "touch")
		w.pres.refresh()
		local line = w.adapter.node("/S/T/ResizeWhen/then/ResizeLine")
		expect(line ~= nil).toBe(true)
		expect(line.rect.x).toBe(636) -- guide sits at the dragged boundary
		w.adapter.pointerUp(cell.x + cell.w - 100, 12, "touch")
		w.pres.refresh()
		expect(w.adapter.node("/S/T/ResizeWhen/then/ResizeLine")).toBe(nil)
		expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@1]/Row/Cells/Cell-name").rect.w).toBe(636)
		expect(w.adapter.node("/S/T/Main/Header/Head-name").rect.w).toBe(636)
	end)

	it("a TOUCH grip drag clamps to the column minWidth", function()
		local w = resizeWorld()
		local cell = w.adapter.node("/S/T/Main/Header/Head-name").rect
		w.adapter.pointerDown(GRIP, cell.x + cell.w, 10, "touch")
		w.adapter.pointerMove(cell.x + 10, 12, "touch") -- far past the minimum
		w.pres.refresh()
		w.adapter.pointerUp(cell.x + 10, 12, "touch")
		w.pres.refresh()
		expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@1]/Row/Cells/Cell-name").rect.w).toBe(80)
	end)
end)

-- =============================================================================
-- 4. DEVICE-TRUE gamepad + keyboard row-select and grab-reorder (audit honesty:
--    prove the WIRING through deviceKey, not tbl.api.* directly)
-- =============================================================================
describe("table_input: device-true gamepad/keyboard row-select and grab-reorder", function()
	-- a REAL consumer: applies the post-removal splice so a step MOVES the data
	local function reorderWorld(opts: any?)
		local options = opts or {}
		local core, env, system, adapter, pres = harness()
		local rows = core:signal(bigRows(5))
		local editing = core:signal(options.editing == true)
		local reorders: { any } = {}
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = options.selection or "single",
			rowHeight = 40,
			reorderable = true,
			editing = editing,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
				local movingSet: { [string]: boolean } = {}
				for _, key in keys do
					movingSet[key] = true
				end
				local moving, staying = {}, {}
				for _, item in rows:get() do
					table.insert(if movingSet[item.id] then moving else staying, item)
				end
				local out = {}
				for i = 1, toIndex do
					table.insert(out, staying[i])
				end
				for _, item in moving do
					table.insert(out, item)
				end
				for i = toIndex + 1, #staying do
					table.insert(out, staying[i])
				end
				rows:set(out)
			end,
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- zero opts
		pres.refresh()
		return {
			system = system,
			adapter = adapter,
			pres = pres,
			tbl = tbl,
			rows = rows,
			editing = editing,
			reorders = reorders,
			handle = handle,
		}
	end
	local function order(rows: any): { string }
		local out = {}
		for _, item in rows:get() do
			table.insert(out, item.id)
		end
		return out
	end

	it("gamepad ButtonA selects the focused row (through presenter Activate dispatch)", function()
		local w = reorderWorld() -- editing off
		-- initial focus is on r1 but nothing is selected yet (pushScope does not
		-- run selection-follows-focus); ButtonA proves the Activate->select path
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		expect(w.tbl.api.selectedKeys:get().r1).toBeNil()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedKeys:get().r1).toBe(true)
	end)

	it("gamepad DPadDown/DPadUp navigate rows and selection follows focus", function()
		local w = reorderWorld()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true) -- Apple model: follows
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.tbl.api.selectedKeys:get().r2).toBeNil() -- replaced
		expect(w.tbl.api.selectedKeys:get().r3).toBe(true)
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
	end)

	it("keyboard Down + Return select the focused row", function()
		local w = reorderWorld()
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
	end)

	it("gamepad edit-mode: ButtonA grabs, DPadDown steps the row, ButtonA drops", function()
		local w = reorderWorld({ editing = true })
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		-- ButtonA in edit mode GRABS the focused row (action-source Activate)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.grabbedKey:get()).toBe("r1")
		-- DPadDown now MOVES the grabbed row (navigateIntercept eats the nav)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(#w.reorders).toBe(1)
		expect(order(w.rows)[1]).toBe("r2") -- r1 stepped below r2
		expect(order(w.rows)[2]).toBe("r1")
		-- focus stays on the grabbed row (row paths are key-based)
		w.pres.refresh()
		expect(w.tbl.api.grabbedKey:get()).toBe("r1")
		-- another DPadDown steps again
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(#w.reorders).toBe(2)
		expect(order(w.rows)[3]).toBe("r1")
		-- ButtonA DROPS: the grab clears and DPad returns to plain navigation
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.grabbedKey:get()).toBeNil()
	end)

	it("keyboard edit-mode grab is input-agnostic: Return grabs, Down steps, Return drops", function()
		local w = reorderWorld({ editing = true })
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.tbl.api.grabbedKey:get()).toBe("r1")
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(#w.reorders).toBe(1)
		expect(order(w.rows)[1]).toBe("r2")
		expect(order(w.rows)[2]).toBe("r1")
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.tbl.api.grabbedKey:get()).toBeNil()
	end)
end)

-- =============================================================================
-- 5. A BLOCK TABLE INSIDE A SCROLLING PAGE (device report 2026-07-28, iPhone 15
--    Pro, gallery example 02 under Pixel Quest: "when I pick up a row it doesn't
--    always appear under my finger — the picked up chip moves up as I scroll
--    down").
--
--    The shipped example makes the PAGE the scroller and the table a BLOCK
--    (`scrolls = false`), so every pointer→table mapping in the reorder drag has
--    to survive the page canvas moving underneath it. A pointer always arrives in
--    WINDOW space; a solved rect inside a scroll host is CANVAS space. Mixing the
--    two — or snapshotting one of them at pointer-down and reusing it for the
--    whole drag — makes the ghost drift by exactly the page's scroll offset.
-- =============================================================================
describe("table_input: reorder drag inside a scrolling PAGE (block table)", function()
	local PAGE = "/S/Page"
	local ROOT = "/S/Page/T"
	local GHOST = "/S/Page/T/GhostWhen/then/DragGhost"
	local DROP = "/S/Page/T/DropWhen/then/DropLine"

	local function handlePath(key: string): string
		return `{ROOT}/Main/Body/Rows/[{key}@0]/Row/EditWhen/then/HandleZone/Handle`
	end

	-- the example's shape: Screen > ScrollView(Page) > [tall header block, table]
	local function pageWorld()
		local core, env, system, adapter, pres = harness()
		local rows = core:signal(bigRows(12))
		local reorders: { any } = {}
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "none",
			rowHeight = 40,
			reorderable = true,
			-- a BLOCK: the page above owns the scrolling (examples/gallery 02)
			scrolls = false,
			editing = core:signal(true),
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.ScrollView({
					id = "Page",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						LuauUI.UI.Box({
							id = "Header",
							width = { type = "fill", weight = 1 },
							height = { type = "fixed", px = 200 },
						}),
						tbl.blueprint,
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		return {
			adapter = adapter,
			pres = pres,
			handle = handle,
			rows = rows,
			reorders = reorders,
			env = env,
			system = system,
			core = core,
		}
	end

	-- a VIEWPORT table (its Body is its own ScrollingFrame) inside a scrolling
	-- page: exactly the director's case — "a table that's not at full height
	-- within another scroll view". Two scrollers, one inside the other.
	local PAGE2 = "/S/Page"
	local INNER = "/S/Page/T/Main/Body"
	local function nestedHandle(key: string): string
		return `{INNER}/Rows/[{key}@0]/Row/EditWhen/then/HandleZone/Handle`
	end
	local function nestedWorld(opts: any?)
		local options = opts or {}
		local core, env, system, adapter, pres = harness()
		local rows = core:signal(bigRows(14))
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "none",
			rowHeight = 40,
			reorderable = true,
			-- shorter than the page, and it owns a scroller of its own
			height = { type = "fixed", px = 240 },
			editing = core:signal(true),
			onReorder = function() end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.ScrollView({
					id = "Page",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					autoscroll = if options.pageAutoscroll == false then false else nil,
					children = {
						LuauUI.UI.Box({
							id = "Filler",
							width = { type = "fill", weight = 1 },
							-- pushes the table down so its BOTTOM EDGE sits inside the
							-- page's own bottom band: that overlap is the only place the
							-- chain question is real, because a point at the inner
							-- list's edge but mid-page is not at the page's edge at all
							-- and the page is right to stay still.
							height = { type = "fixed", px = options.fillerPx or 360 },
						}),
						tbl.blueprint,
						LuauUI.UI.Box({
							id = "PageTail",
							width = { type = "fill", weight = 1 },
							height = { type = "fixed", px = 600 },
						}),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		return { adapter = adapter, pres = pres, handle = handle, rows = rows, env = env, system = system }
	end

	-- where a node is actually PAINTED: the solved rect shifted by every scroll
	-- host above it (the renderer's own window-space lookup)
	local function paintedY(w: any, path: string): number
		return w.handle.controller.screenRectOf(path).y
	end

	it("the ghost chip stays under the pointer while the PAGE scrolls mid-drag", function()
		local w = pageWorld()
		-- the page really can scroll: content (200 + header + 12 rows) > viewport
		local region = w.adapter.scrollRegionOf(PAGE)
		expect(region ~= nil and region.contentH > 600).toBe(true)

		local grip = w.adapter.node(handlePath("r1")).rect
		local px, py = grip.x + 4, grip.y + 10
		w.adapter.pointerDown(handlePath("r1"), px, py, "touch")
		w.adapter.pointerMove(px, py + 60, "touch") -- past the drag threshold
		w.pres.refresh()
		expect(w.adapter.node(GHOST) ~= nil).toBe(true)
		local before = paintedY(w, GHOST)

		-- THE FINGER DOES NOT MOVE, the page does: on a real ScrollingFrame the
		-- same touch that drags the handle also pans the ancestor canvas.
		w.adapter.driveScroll(PAGE, { x = 0, y = 120 })
		w.pres.refresh()
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()

		-- the chip is painted where the finger is, not 120px above it
		expect(paintedY(w, GHOST)).toBe(before)
	end)

	it("the drop line snaps to the nearest PAINTED row boundary after a PAGE scroll", function()
		-- the line legitimately MOVES when the page scrolls (the pointer is over a
		-- different boundary now), so the invariant is the snap itself: a boundary
		-- is chosen by row MIDPOINT, so the drawn line is never more than half a row
		-- from the finger. Before the fix it sat a whole page-scroll away.
		local w = pageWorld()
		local grip = w.adapter.node(handlePath("r1")).rect
		local px, py = grip.x + 4, grip.y + 10
		w.adapter.pointerDown(handlePath("r1"), px, py, "touch")
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()
		expect(math.abs(paintedY(w, DROP) - (py + 60)) <= 20).toBe(true)

		w.adapter.driveScroll(PAGE, { x = 0, y = 120 })
		w.pres.refresh()
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()
		expect(math.abs(paintedY(w, DROP) - (py + 60)) <= 20).toBe(true)
	end)

	it("the drag overlay does not change the PAGE's scroll canvas (device report: tiny scrollbar)", function()
		-- device report 2026-07-29: "the scrollbar size looks very small [while
		-- dragging]; when I'm not drag and dropping it looks correct." A drop line
		-- and a ghost chip are OVERLAY — they must not enlarge the page they float
		-- over, or the native scrollbar thumb (view/canvas) shrinks and the player
		-- can scroll past the end of their own content.
		--
		-- The SCROLL AXIS is what this pins, because that is the thumb the report
		-- is about and the axis the canvas is written for. The cross axis is NOT
		-- clean: an Anchor measures its children ignoring their offsets, so a
		-- fixed-size overlay WIDER than the table's own intrinsic content (a table
		-- whose columns are all `fill` measures narrow) does widen the canvas.
		-- Recorded rather than asserted — it needs a layout answer about whether an
		-- offset child should size its Anchor at all, which is bigger than this fix.
		local w = pageWorld()
		local before = w.adapter.scrollRegionOf(PAGE)
		expect(before ~= nil).toBe(true)

		local grip = w.adapter.node(handlePath("r1")).rect
		local px, py = grip.x + 4, grip.y + 10
		w.adapter.pointerDown(handlePath("r1"), px, py, "touch")
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()
		expect(w.adapter.node(GHOST) ~= nil).toBe(true)
		local during = w.adapter.scrollRegionOf(PAGE)
		expect(during.contentH).toBe(before.contentH)

		-- ...and it stays put once the page has scrolled under the live drag, which
		-- is when the ghost's offset inside the table grows
		w.adapter.driveScroll(PAGE, { x = 0, y = 120 })
		w.pres.refresh()
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()
		local scrolled = w.adapter.scrollRegionOf(PAGE)
		expect(scrolled.contentH).toBe(before.contentH)

		w.adapter.pointerUp(px, py + 60, "touch")
		w.pres.refresh()
		expect(w.adapter.scrollRegionOf(PAGE).contentH).toBe(before.contentH)
	end)

	-- ---- edge autoscroll (device report 2026-07-29) ------------------------
	-- "I moved my finger to the bottom of the scroll view and held it, and it
	-- didn't auto-scroll." A block Table cannot reach the rows below the fold
	-- during a drag unless the PAGE it sits in scrolls for it — and the page is
	-- not the table's own scroller, so the table has to find the host that
	-- actually carries it.
	it("holding the drag in the PAGE's bottom edge band autoscrolls the page", function()
		local w = pageWorld()
		local page = w.adapter.node(PAGE).rect
		local grip = w.adapter.node(handlePath("r1")).rect
		local px, py = grip.x + 4, grip.y + 10
		w.adapter.pointerDown(handlePath("r1"), px, py, "touch")
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()
		expect(w.adapter.node(GHOST) ~= nil).toBe(true)
		expect((w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y).toBe(0)

		-- park the finger deep in the bottom band and let frames pass
		local deep = page.y + page.h - 8
		w.adapter.pointerMove(px, deep, "touch")
		w.pres.refresh()
		-- DWELL first: 300ms of presence before anything moves (a flick past the
		-- edge on the way somewhere else must never scroll)
		w.pres.tick(0.1)
		w.pres.tick(0.1)
		expect((w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y).toBe(0)
		for _ = 1, 12 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		local scrolled = (w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y
		expect(scrolled > 0).toBe(true)

		-- the drop verdict follows the scroll IN THE SAME FRAME: the ghost is still
		-- painted under the parked finger, not left behind by the canvas it moved
		expect(w.handle.controller.screenRectOf(GHOST).y).toBe(deep - 13)

		-- ...and it stops the moment the finger leaves the band
		w.adapter.pointerMove(px, page.y + 40, "touch")
		w.pres.refresh()
		for _ = 1, 10 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		local settled = (w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y
		for _ = 1, 10 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		expect((w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y).toBe(settled)
		w.adapter.pointerUp(px, page.y + 40, "touch")
		w.pres.refresh()
	end)

	it("no drag, no autoscroll: a finger resting in the band with nothing picked up never scrolls", function()
		local w = pageWorld()
		local page = w.adapter.node(PAGE).rect
		for _ = 1, 20 do
			w.pres.tick(0.05)
		end
		expect((w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y).toBe(0)
	end)

	it("autoscroll releases with the drop (no runaway scroll after the finger lifts)", function()
		local w = pageWorld()
		local page = w.adapter.node(PAGE).rect
		local grip = w.adapter.node(handlePath("r1")).rect
		local px, py = grip.x + 4, grip.y + 10
		w.adapter.pointerDown(handlePath("r1"), px, py, "touch")
		w.adapter.pointerMove(px, py + 60, "touch")
		w.adapter.pointerMove(px, page.y + page.h - 8, "touch")
		w.pres.refresh()
		for _ = 1, 14 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		expect((w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y > 0).toBe(true)
		w.adapter.pointerUp(px, page.y + page.h - 8, "touch")
		w.pres.refresh()
		local atDrop = (w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y
		for _ = 1, 20 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		expect((w.adapter.scrollPositionOf(PAGE) or { y = 0 }).y).toBe(atDrop)
	end)

	-- ---- NESTED scrollers (director, 2026-07-29) --------------------------
	-- "a table that's not at full height within another scroll view. we should pay
	-- attention to which scrollview we're near an edge of and scroll if
	-- appropriate." The chain rule is innermost-first with fall-through: the inner
	-- list moves while it still can, and hands the drag to the page once its own
	-- tail is reached.
	it("a drag at a NESTED list's bottom edge scrolls the INNER list, not the page", function()
		local w = nestedWorld()
		local body = w.adapter.node(INNER).rect
		expect(w.adapter.scrollRegionOf(INNER) ~= nil).toBe(true)
		local grip = w.adapter.node(nestedHandle("r1")).rect
		local px = grip.x + 4
		w.adapter.pointerDown(nestedHandle("r1"), px, grip.y + 8, "touch")
		w.adapter.pointerMove(px, grip.y + 40, "touch")
		w.pres.refresh()
		-- park inside the INNER list's bottom band (well clear of the page's own)
		w.adapter.pointerMove(px, body.y + body.h - 6, "touch")
		w.pres.refresh()
		for _ = 1, 14 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		expect((w.adapter.scrollPositionOf(INNER) or { y = 0 }).y > 0).toBe(true)
		-- INNERMOST WINS while it can still travel: the point is inside BOTH bands
		-- here (the table sits at the page's bottom edge), and the page stayed put
		expect((w.adapter.scrollPositionOf(PAGE2) or { y = 0 }).y).toBe(0)
		w.adapter.pointerUp(px, body.y + body.h - 6, "touch")
		w.pres.refresh()
	end)

	it("an inner list already at its end hands the drag OUT to the page (bands overlap)", function()
		local w = nestedWorld()
		local body = w.adapter.node(INNER).rect
		-- pin the inner list at its tail before the drag starts
		local region = w.adapter.scrollRegionOf(INNER)
		w.adapter.driveScroll(INNER, { x = 0, y = region.contentH })
		w.pres.refresh()
		local innerAtEnd = (w.adapter.scrollPositionOf(INNER) or { y = 0 }).y
		expect(innerAtEnd > 0).toBe(true)

		local grip = w.adapter.node(nestedHandle("r1")).rect
		local px = grip.x + 4
		w.adapter.pointerDown(nestedHandle("r1"), px, grip.y + 8, "touch")
		w.adapter.pointerMove(px, grip.y + 40, "touch")
		w.pres.refresh()
		w.adapter.pointerMove(px, body.y + body.h - 6, "touch")
		w.pres.refresh()
		for _ = 1, 16 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		-- the inner one cannot move, so the PAGE takes the gesture
		expect((w.adapter.scrollPositionOf(INNER) or { y = 0 }).y).toBe(innerAtEnd)
		expect((w.adapter.scrollPositionOf(PAGE2) or { y = 0 }).y > 0).toBe(true)
		w.adapter.pointerUp(px, body.y + body.h - 6, "touch")
		w.pres.refresh()
	end)

	it("autoscroll=false opts a scroller out for good: the chain skips it entirely", function()
		-- the PAGE opts out, so an inner list pinned at its tail has nowhere to
		-- hand the drag on to and NOTHING moves — the opt-out is a real refusal,
		-- not a lower priority
		local w = nestedWorld({ pageAutoscroll = false })
		local body = w.adapter.node(INNER).rect
		local region = w.adapter.scrollRegionOf(INNER)
		w.adapter.driveScroll(INNER, { x = 0, y = region.contentH })
		w.pres.refresh()
		local innerAtEnd = (w.adapter.scrollPositionOf(INNER) or { y = 0 }).y
		local grip = w.adapter.node(nestedHandle("r1")).rect
		local px = grip.x + 4
		w.adapter.pointerDown(nestedHandle("r1"), px, grip.y + 8, "touch")
		w.adapter.pointerMove(px, grip.y + 40, "touch")
		w.adapter.pointerMove(px, body.y + body.h - 6, "touch")
		w.pres.refresh()
		for _ = 1, 16 do
			w.pres.tick(0.05)
			w.pres.refresh()
		end
		expect((w.adapter.scrollPositionOf(PAGE2) or { y = 0 }).y).toBe(0)
		expect((w.adapter.scrollPositionOf(INNER) or { y = 0 }).y).toBe(innerAtEnd)
		w.adapter.pointerUp(px, body.y + body.h - 6, "touch")
		w.pres.refresh()
	end)

	it("a drop after a PAGE scroll commits the slot the pointer is actually over", function()
		local w = pageWorld()
		local grip = w.adapter.node(handlePath("r1")).rect
		local px, py = grip.x + 4, grip.y + 10
		w.adapter.pointerDown(handlePath("r1"), px, py, "touch")
		w.adapter.pointerMove(px, py + 60, "touch")
		w.pres.refresh()
		-- unscrolled, this drop lands r1 after r2 (post-removal slot 1)
		w.adapter.pointerUp(px, py + 60, "touch")
		w.pres.refresh()
		local unscrolled = w.reorders[1].toIndex

		-- same gesture, same window coordinates, but the page scrolled first: the
		-- pointer is over a DIFFERENT row now, and the commit must follow the paint
		local w2 = pageWorld()
		w2.adapter.driveScroll(PAGE, { x = 0, y = 120 })
		w2.pres.refresh()
		local grip2 = w2.adapter.node(handlePath("r1")).rect
		-- window y of r1's handle after the page moved up by 120
		local sy = w2.handle.controller.screenRectOf(handlePath("r1")).y + 10
		w2.adapter.pointerDown(handlePath("r1"), grip2.x + 4, sy, "touch")
		w2.adapter.pointerMove(grip2.x + 4, sy + 60, "touch")
		w2.pres.refresh()
		w2.adapter.pointerUp(grip2.x + 4, sy + 60, "touch")
		w2.pres.refresh()
		expect(#w2.reorders).toBe(1)
		expect(w2.reorders[1].toIndex).toBe(unscrolled)
	end)
end)

-- =============================================================================
-- 5. onPrimaryAction — THE FOUR-INPUT PROOF (parity round 2 §3.4)
--
-- "Open this row" is the verb that is NOT selection, and every input has to be
-- able to say it. Each case here drives the DEVICE seam (adapter.tap /
-- adapter.touchTap / system.deviceKey) through the presenter's zero-opt auto
-- composition — never `tbl.api.handleActivate` — so what is proven is the path a
-- player's finger, mouse, key and stick actually take.
--
-- The clock is SCRIPTED (`now`), because the pointer gesture is a MEASUREMENT:
-- with os.clock, two `adapter.tap` calls in a spec are microseconds apart and
-- the double-click window is satisfied by the test's own speed rather than by
-- the code under test. The slow-pair case below only bites with a scripted one.
-- =============================================================================
describe("table_input: onPrimaryAction across pointer, touch, keyboard and gamepad", function()
	local function primaryWorld(opts: { selection: string?, rows: number? }?)
		local o = opts or {}
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local pres = LuauUI.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local opened: { { key: string, name: string } } = {}
		local rows = core:signal(bigRows(o.rows or 3))
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = o.selection or "single",
			rowHeight = 40,
			onPrimaryAction = function(item: any, key: string)
				table.insert(opened, { key = key, name = item.name })
			end,
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- ZERO present opts: full auto-composition
		pres.refresh()
		-- the solver's own verdict, on every fixture (docs/lessons/the-solver-already-told-you.md)
		expect(#handle.controller.diagnostics()).toBe(0)
		return {
			core = core,
			system = system,
			adapter = adapter,
			pres = pres,
			handle = handle,
			tbl = tbl,
			opened = opened,
			clock = clock,
		}
	end

	local function mouseTap(w: any, key: string)
		local rect = w.adapter.node(hit(key)).rect
		w.adapter.tap(hit(key), {
			source = "pointer",
			pointer = "mouse",
			x = rect.x + rect.w / 2,
			y = rect.y + rect.h / 2,
		})
	end

	it("Table pointer: a double-click on a row fires onPrimaryAction once, and a single click never does", function()
		local w = primaryWorld()
		mouseTap(w, "r2")
		expect(#w.opened).toBe(0) -- one click selects and nothing else
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
		w.clock.t += 0.2 -- inside the 500 ms window
		mouseTap(w, "r2")
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r2")
		expect(w.opened[1].name).toBe("Row 2")
		-- and the row is still selected: opening is not a selection verb
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
	end)

	it("Table pointer: two clicks SLOWER than the window are two single clicks, not an open", function()
		local w = primaryWorld()
		mouseTap(w, "r2")
		w.clock.t += 0.6 -- past 500 ms
		mouseTap(w, "r2")
		expect(#w.opened).toBe(0)
		-- a third click inside the window of the SECOND one does open it: the
		-- pair is re-formed rather than lost
		w.clock.t += 0.1
		mouseTap(w, "r2")
		expect(#w.opened).toBe(1)
	end)

	it("Table pointer: two fast clicks on DIFFERENT rows are not a double-click", function()
		local w = primaryWorld()
		mouseTap(w, "r1")
		w.clock.t += 0.05
		mouseTap(w, "r2")
		expect(#w.opened).toBe(0)
	end)

	it("Table pointer: a modified click is a SELECTION gesture and never opens", function()
		local w = primaryWorld({ selection = "multi" })
		local function modTap(key: string, mods: any)
			local rect = w.adapter.node(hit(key)).rect
			local meta: any = { source = "pointer", pointer = "mouse", x = rect.x + 1, y = rect.y + 1 }
			for k, v in mods do
				meta[k] = v
			end
			w.adapter.tap(hit(key), meta)
		end
		modTap("r2", { toggle = true })
		w.clock.t += 0.05
		modTap("r2", { toggle = true })
		expect(#w.opened).toBe(0)
		modTap("r3", { shift = true })
		w.clock.t += 0.05
		modTap("r3", { shift = true })
		expect(#w.opened).toBe(0)
	end)

	it("Table touch: the first tap selects and the SECOND tap on the same (selected) row opens it", function()
		local w = primaryWorld()
		w.adapter.touchTap(hit("r2"))
		expect(#w.opened).toBe(0)
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
		-- an arbitrarily long pause: this is a mode, not a measurement
		w.clock.t += 30
		w.adapter.touchTap(hit("r2"))
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r2")
		-- the row it opened is STILL selected — a second tap in `multi` would
		-- otherwise deselect exactly the row it just opened
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
	end)

	it("Table touch: a tap on a row that is NOT yet selected only selects it — every input's first tap is a selection", function()
		local w = primaryWorld({ selection = "multi" })
		w.adapter.touchTap(hit("r1"))
		w.adapter.touchTap(hit("r2"))
		expect(#w.opened).toBe(0) -- two additive selections, nothing opened
		expect(w.tbl.api.selectedKeys:get().r1).toBe(true)
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
		-- and now the already-selected row opens, without disturbing either
		w.adapter.touchTap(hit("r2"))
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r2")
		expect(w.tbl.api.selectedKeys:get().r1).toBe(true)
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
	end)

	-- THE PRICE OF THE TOUCH RULE, PINNED RATHER THAN HIDDEN (see the divergence
	-- note in table.luau). In `multi`, a tap on a selected row USED TO be the
	-- deselect gesture. Declaring `onPrimaryAction` spends that gesture on
	-- opening — for that table only, and only because its author declared that
	-- its rows open. This test exists so the trade is a decision on the record
	-- rather than a surprise in a bug report.
	it("Table touch: declaring onPrimaryAction spends multi's tap-to-DESELECT gesture, and only on that table", function()
		local withAction = primaryWorld({ selection = "multi" })
		withAction.adapter.touchTap(hit("r1"))
		withAction.adapter.touchTap(hit("r1"))
		expect(withAction.tbl.api.selectedKeys:get().r1).toBe(true) -- opened, not deselected
		expect(#withAction.opened).toBe(1)
		-- the consumer-side escape is unchanged and still exact
		withAction.tbl.api.clearSelection()
		expect(withAction.tbl.api.selectedKeys:get().r1).toBe(nil)
	end)

	it('Table touch: with selection = "none" a single tap opens, because there is no selected state to reach', function()
		local w = primaryWorld({ selection = "none" })
		w.adapter.touchTap(hit("r3"))
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r3")
		w.adapter.touchTap(hit("r1"))
		expect(#w.opened).toBe(2)
		expect(w.opened[2].key).toBe("r1")
	end)

	it("Table keyboard: Return on the focused row fires onPrimaryAction for THAT row", function()
		local w = primaryWorld()
		w.system.deviceKey("Down", true) -- focus r1 -> r2
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		expect(#w.opened).toBe(0) -- moving focus selects; it never opens
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r2")
		expect(w.opened[1].name).toBe("Row 2")
	end)

	it("Table gamepad: ButtonA on the focused row fires onPrimaryAction for THAT row", function()
		local w = primaryWorld()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(hit("r3"))
		expect(#w.opened).toBe(0)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r3")
	end)

	it("a table with NO onPrimaryAction behaves exactly as it does today on all four inputs", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local rows = core:signal(bigRows(3))
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			rows = rows,
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "multi",
			rowHeight = 40,
		})
		local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		-- touch: tap toggles ON, tap again toggles OFF (the Phase A idiom, intact)
		adapter.touchTap(hit("r2"))
		expect(tbl.api.selectedKeys:get().r2).toBe(true)
		adapter.touchTap(hit("r2"))
		expect(tbl.api.selectedKeys:get().r2).toBe(nil)
		-- keyboard/gamepad Activate still just replaces the selection: focus lands
		-- on r3 and Return re-selects exactly it, leaving r2 behind
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(hit("r3"))
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(tbl.api.selectedKeys:get().r3).toBe(true)
		expect(tbl.api.selectedKeys:get().r2).toBe(nil)
	end)
end)
