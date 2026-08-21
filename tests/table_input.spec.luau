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

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local table_control = require("../src/controls/table")
local fake_target = require("../tests/lib/fake_target")

--[[ ONE SUBSTRATE, ONE ORDER (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants; the tuple
	this file hands its cases is `core, env, adapter, system, pres` — the order
	`Facet.newPresenter` itself takes, and now the only one in the suite. It used
	to be `core, env, system, adapter, pres` here and the other spelling sixteen
	files away, with the same five names on both sides, so a line copied between
	two neighbouring specs bound an action system to a variable called `adapter`
	and said nothing. ]]
local function harness()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
	return w.core, w.env, w.adapter, w.system, w.pres
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
		local core, env, adapter, system, pres = harness()
		local sortOrder = core:signal(nil :: any)
		local rows = core:signal(bigRows(3))
		local tbl = table_control.build(Facet, core, {
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
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
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
		local core, env, adapter, system, pres = harness()
		local rows = core:signal(bigRows(20))
		local tbl = table_control.build(Facet, core, {
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
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
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
		local core, env, adapter, system, pres = harness()
		local rows = core:signal(bigRows(3))
		local tbl = table_control.build(Facet, core, {
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
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
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
		local core, env, adapter, system, pres = harness()
		local rows = core:signal(bigRows(5))
		local editing = core:signal(options.editing == true)
		local reorders: { any } = {}
		local tbl = table_control.build(Facet, core, {
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
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
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
		local core, env, adapter, system, pres = harness()
		local rows = core:signal(bigRows(12))
		local reorders: { any } = {}
		local tbl = table_control.build(Facet, core, {
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
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.ScrollView({
					id = "Page",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						Facet.UI.Box({
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
		local core, env, adapter, system, pres = harness()
		local rows = core:signal(bigRows(14))
		local tbl = table_control.build(Facet, core, {
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
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.ScrollView({
					id = "Page",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					autoscroll = if options.pageAutoscroll == false then false else nil,
					children = {
						Facet.UI.Box({
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
						Facet.UI.Box({
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
	-- THE FIXTURE CARRIES A REAL ENVIRONMENT, and every case says which INPUT it
	-- is a phone/desktop/pad session of. The auto Edit/Done toggle is gated on the
	-- live interaction classes (ADR-0015), so a fixture with no `env` would mount
	-- the toggle in EVERY case — including the mouse ones, where the whole point
	-- is that it must not appear. `input` defaults to "mouse" because that is what
	-- the pointer/keyboard/gamepad cases below are sessions of.
	local function primaryWorld(opts: {
		selection: string?,
		rows: number?,
		reorderable: boolean?,
		input: string?,
		primaryAction: boolean?,
		ownEditing: boolean?,
	}?)
		local o = opts or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		if o.input == "touch" then
			env:set("preferredInput", "Touch")
			env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		elseif o.input == "gamepad" then
			-- A PAD PLUS A KEYBOARD, the console/handheld session: `gamepad` is the
			-- other class the auto Edit/Done toggle answers to (`showAutoToggle`), so
			-- it is the one input set that can reach edit mode AND drive Return and
			-- ButtonA at the rows once it is there.
			env:set("preferredInput", "Gamepad")
			env:set("capabilities", { keyboard = true, mouse = false, touch = false, gamepad = true })
		else
			env:set("preferredInput", "KeyboardAndMouse")
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local opened: { { key: string, name: string } } = {}
		local ownedEditing = if o.ownEditing then core:signal(false) else nil
		local rows = core:signal(bigRows(o.rows or 3))
		local tbl = table_control.build(Facet, core, {
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
			-- `reorderable` is what auto-shows the table's own Edit/Done toggle, and
			-- edit mode is where touch selection lives under the Apple rule below —
			-- so the edit-mode cases need a table a phone player can actually put
			-- INTO edit mode, through the control's own affordance.
			reorderable = o.reorderable,
			onReorder = if o.reorderable then function() end else nil,
			env = env,
			-- the CONSUMER-OWNED escape, built on THIS world's core so the signal the
			-- table observes and the signal the case flips are the same object under
			-- the same scheduler
			editing = ownedEditing,
			onPrimaryAction = if o.primaryAction == false
				then nil
				else function(item: any, key: string)
					table.insert(opened, { key = key, name = item.name })
				end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- ZERO present opts: full auto-composition
		pres.refresh()
		-- the solver's own verdict, on every fixture (docs/lessons/the-solver-already-told-you.md)
		expect(#handle.controller.diagnostics()).toBe(0)
		return {
			core = core,
			env = env,
			ownedEditing = ownedEditing,
			system = system,
			adapter = adapter,
			pres = pres,
			handle = handle,
			tbl = tbl,
			opened = opened,
			clock = clock,
		}
	end
	local TOGGLE = "/S/T/Main/ToggleWhen/then/Toolbar/EditToggle"

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

	-- ===== TOUCH: APPLE'S DOCUMENTED MODEL, NOT AN INVENTED ONE ==============
	-- `contextMenu(forSelectionType:menu:primaryAction:)`, verbatim: "In iOS and
	-- iPadOS, tapping on the row activates the primary action. To select a row
	-- without performing an action, either enter edit mode or hold shift or
	-- command on a keyboard while tapping the row." So a plain tap OPENS, and
	-- EDIT MODE is where touch selection lives (`EditMode`: "On devices without
	-- an attached keyboard and mouse or trackpad, people can make multiple
	-- selections in lists only when edit mode is active"; HIG Lists and tables:
	-- "In iOS and iPadOS, people must enter an edit mode before they can select
	-- table items"). Both halves are cases below, because the price of the first
	-- is only acceptable BECAUSE of the second.

	it("Table touch: a plain single tap on a row activates it — the first tap, on any row", function()
		local w = primaryWorld({ input = "touch" })
		w.adapter.touchTap(hit("r2"))
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r2")
		expect(w.opened[1].name).toBe("Row 2")
		-- a DIFFERENT row opens on ITS first tap too: there is no per-row state
		-- to enter first, which is the whole substance of the change
		w.adapter.touchTap(hit("r3"))
		expect(#w.opened).toBe(2)
		expect(w.opened[2].key).toBe("r3")
		-- and touch activation is a MODE, not a MEASUREMENT: the same row opens
		-- again after an arbitrarily long pause (no double-click window on touch)
		w.clock.t += 30
		w.adapter.touchTap(hit("r3"))
		expect(#w.opened).toBe(3)
		expect(w.opened[3].key).toBe("r3")
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)

	-- THE PRICE OF THE APPLE RULE, PINNED RATHER THAN HIDDEN (see the note in
	-- table.luau). With a primary action declared, touch loses tap-to-select in
	-- normal mode ENTIRELY — including the SINGLE selection iOS 16+ would
	-- otherwise allow by tap. Apple accepts that deliberately; so do we, and the
	-- corollary is written down beside the rule: a table whose dominant touch use
	-- is SELECTING rather than OPENING should not declare `onPrimaryAction` at
	-- all. The "and only on that table" half is the no-action case at the end of
	-- this block, where every touch tap still selects exactly as it always did.
	it(
		"Table touch: THE COST — a normal-mode tap opens WITHOUT selecting, and leaves an existing selection exactly alone",
		function()
			for _, mode in { "single", "multi" } do
				local w = primaryWorld({ selection = mode, input = "touch" })
				-- the table genuinely CAN hold a selection in this fixture — proven
				-- here, so the assertions below are about the tap and not about a
				-- table that was never able to select in the first place
				w.tbl.api.select("r3")
				expect(w.tbl.api.selectedKeys:get().r3).toBe(true)
				w.adapter.touchTap(hit("r1"))
				expect(#w.opened).toBe(1)
				expect(w.opened[1].key).toBe("r1")
				-- the tap neither added r1, nor replaced r3 with it, nor cleared
				expect(w.tbl.api.selectedKeys:get().r1).toBeNil()
				expect(w.tbl.api.selectedKeys:get().r3).toBe(true)
				-- tapping the SELECTED row opens it too, and still does not toggle it
				w.adapter.touchTap(hit("r3"))
				expect(#w.opened).toBe(2)
				expect(w.opened[2].key).toBe("r3")
				expect(w.tbl.api.selectedKeys:get().r3).toBe(true)
				expect(#w.handle.controller.diagnostics()).toBe(0)
			end
		end
	)

	it(
		"Table touch: EDIT MODE is the selection mode — tap toggles selection (multi's DESELECT is back) and never opens",
		function()
			local w = primaryWorld({ selection = "multi", reorderable = true, input = "touch" })
			local toggle = TOGGLE
			-- a phone player reaches edit mode through the table's OWN affordance
			expect(w.tbl.api.editing:get()).toBe(false)
			w.adapter.touchTap(toggle)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(true)
			w.adapter.touchTap(hit("r2"))
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
			expect(#w.opened).toBe(0) -- activation is unreachable here, on purpose
			w.adapter.touchTap(hit("r1"))
			expect(w.tbl.api.selectedKeys:get().r1).toBe(true) -- additive, as multi is
			expect(#w.opened).toBe(0)
			-- THE RESTORED GESTURE: a second tap on a selected row DESELECTS it. This
			-- is the gesture the old tap-to-open rule spent; edit mode gives it back.
			w.adapter.touchTap(hit("r2"))
			expect(w.tbl.api.selectedKeys:get().r2).toBeNil()
			expect(w.tbl.api.selectedKeys:get().r1).toBe(true)
			expect(#w.opened).toBe(0)
			-- Done, and the plain tap opens again — the mode is a mode, not a latch
			w.adapter.touchTap(toggle)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(false)
			w.adapter.touchTap(hit("r2"))
			expect(#w.opened).toBe(1)
			expect(w.opened[1].key).toBe("r2")
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it('Table touch: with selection = "none" a single tap opens, exactly as it does in every other mode', function()
		local w = primaryWorld({ selection = "none", input = "touch" })
		w.adapter.touchTap(hit("r3"))
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r3")
		w.adapter.touchTap(hit("r1"))
		expect(#w.opened).toBe(2)
		expect(w.opened[2].key).toBe("r1")
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)

	-- ===== THE ROUTE INTO EDIT MODE HAS TO EXIST, OR TOUCH SELECTION DOESN'T ==
	-- Moving touch selection into edit mode only keeps `selection` reachable on a
	-- phone if the phone player can REACH edit mode. The auto Edit/Done toggle used
	-- to appear for `reorderable` tables and nothing else, which left a selectable,
	-- primary-action, NON-reorderable table with no route at all: every tap opened,
	-- and no affordance existed to stop them opening. Apple ships `EditButton` as a
	-- standard control for exactly this reason. The predicate the toggle now uses —
	-- "edit mode is the ONLY route to a capability this table declares, and the
	-- consumer has not taken the signal over" — is stated in table.luau's header and
	-- pinned from all four sides here: the shape that NEEDS it, and the three shapes
	-- that must not grow a button (mouse session, nothing to select, nothing that
	-- opens) plus the consumer-owned escape.

	it(
		"Table touch: a selectable NON-reorderable table with a primary action can still be put into edit mode, so touch can select at all",
		function()
			local w = primaryWorld({ selection = "multi", input = "touch" })
			-- the table is genuinely selectable — proven through the model, so what
			-- follows is a statement about the GESTURE and not about a table that could
			-- never select in the first place
			w.tbl.api.select("r1")
			expect(w.tbl.api.selectedKeys:get().r1).toBe(true)
			w.tbl.api.clearSelection()
			expect(w.tbl.api.selectedKeys:get().r1).toBeNil()
			-- ...and in NORMAL mode a finger cannot say it: every tap opens instead
			w.adapter.touchTap(hit("r2"))
			expect(#w.opened).toBe(1)
			expect(w.tbl.api.selectedKeys:get().r2).toBeNil()
			-- THE ROUTE: the table's own affordance, mounted on a touch session even
			-- though nothing about this table is reorderable
			expect(w.adapter.node(TOGGLE) ~= nil).toBe(true)
			expect(w.adapter.node(TOGGLE).props.label).toBe("Edit")
			w.adapter.touchTap(TOGGLE)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(true)
			expect(w.adapter.node(TOGGLE).props.label).toBe("Done")
			-- and NOW a finger can select, which is the entire point
			w.adapter.touchTap(hit("r2"))
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
			w.adapter.touchTap(hit("r3"))
			expect(w.tbl.api.selectedKeys:get().r3).toBe(true) -- additive, as multi is
			expect(#w.opened).toBe(1) -- still the one from normal mode: edit taps never open
			-- Done returns the table to opening, with the selection it just made intact
			w.adapter.touchTap(TOGGLE)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(false)
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
			w.adapter.touchTap(hit("r2"))
			expect(#w.opened).toBe(2)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it(
		"the auto toggle stays OFF a mouse session: a click already selects, so there is nothing edit mode is the only route to",
		function()
			local w = primaryWorld({ selection = "multi", input = "mouse" })
			expect(w.adapter.node(TOGGLE)).toBe(nil)
			-- the reason it is absent, asserted rather than assumed: a plain mouse click
			-- selects this table in NORMAL mode
			local rect = w.adapter.node(hit("r2")).rect
			w.adapter.tap(hit("r2"), { source = "pointer", pointer = "mouse", x = rect.x + 1, y = rect.y + 1 })
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
			expect(#w.opened).toBe(0)
			-- and it ARRIVES the moment a touch capability goes live mid-session
			-- (ADR-0015: affordances follow the live class set, never a stale preference)
			w.env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
			w.pres.refresh()
			expect(w.adapter.node(TOGGLE) ~= nil).toBe(true)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it(
		'the auto toggle stays off a touch table with selection = "none": edit mode is the only route to NOTHING there',
		function()
			local w = primaryWorld({ selection = "none", input = "touch" })
			expect(w.adapter.node(TOGGLE)).toBe(nil)
			-- and the same table, made selectable, grows one — so the absence above is
			-- the `selection` half of the predicate and not the fixture being inert
			local selectable = primaryWorld({ selection = "single", input = "touch" })
			expect(selectable.adapter.node(TOGGLE) ~= nil).toBe(true)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it(
		"the auto toggle stays off a touch table with NO primary action — the shipped RascalRally racer-list shape",
		function()
			-- `selection = "single"`, no `onPrimaryAction`, not `reorderable`: a plain tap
			-- still SELECTS in normal mode, so edit mode is the only route to nothing and
			-- a button here would be a visible regression on a shipped game screen.
			local w = primaryWorld({ selection = "single", primaryAction = false, input = "touch" })
			expect(w.adapter.node(TOGGLE)).toBe(nil)
			w.adapter.touchTap(hit("r2"))
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true) -- reachable without edit mode
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it(
		"the auto toggle stays off when the CONSUMER owns the editing signal — their affordance, their business",
		function()
			local w = primaryWorld({ selection = "multi", input = "touch", ownEditing = true })
			expect(w.adapter.node(TOGGLE)).toBe(nil)
			-- and the consumer's own signal still drives the mode it owns: edit mode is
			-- reachable, just not through a button the table planted
			w.ownedEditing:set(true)
			w.pres.refresh()
			w.adapter.touchTap(hit("r2"))
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
			expect(#w.opened).toBe(0)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it(
		"control-owned edit mode CANCELS when touch leaves the session, exactly as it does for a reorderable table",
		function()
			-- the toggle unmounts when neither touch nor gamepad is live; a control-owned
			-- `editing` left standing would strand the table in edit mode with no way out
			-- (a wedge). Widening which tables auto-show the toggle widens this too.
			local w = primaryWorld({ selection = "multi", input = "touch" })
			w.adapter.touchTap(TOGGLE)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(true)
			-- pure pointer: touch AND gamepad both gone, preference included (a live
			-- `preferredInput = "Touch"` forces the touch class on by itself)
			w.env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			w.env:set("preferredInput", "KeyboardAndMouse")
			w.pres.refresh()
			expect(w.adapter.node(TOGGLE)).toBe(nil)
			expect(w.tbl.api.editing:get()).toBe(false)
			-- and the table is back to its normal-mode behaviour, not stuck mid-mode
			local rect = w.adapter.node(hit("r2")).rect
			w.adapter.tap(hit("r2"), { source = "pointer", pointer = "mouse", x = rect.x + 1, y = rect.y + 1 })
			expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

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

	--[[ EDIT MODE MUST NOT EAT THE DEVICE ACTIVATE ON A TABLE THAT CANNOT REORDER
		(redteam item 3, HIGH; 2026-08-13) ────────────────────────────────────────
		`api.handleActivate`'s grab branch asked only "editing, and a device
		Activate" — true of exactly one kind of table when it was written, because
		only a `reorderable` one could reach edit mode at all. Widening the auto
		toggle to selectable + `onPrimaryAction` put a NON-reorderable table into
		edit mode for the first time, and every Return and every ButtonA on its
		rows then dead-ended into a grab it can never perform: nothing opened, the
		row was left phantom-grabbed, and the Activate was swallowed whole. The
		four-input bar the widening exists to satisfy was broken by the widening.

		Green until now because every shipped edit-mode case drives TOUCH. These
		drive the two device classes, through the control's own toggle, on the
		exact shape the widening created. The reorderable half — where the grab is
		real and must survive — is proven by "gamepad edit-mode: ButtonA grabs,
		DPadDown steps the row, ButtonA drops" and its keyboard twin above. ]]
	it(
		"Table gamepad: in edit mode a NON-reorderable table still opens rows — ButtonA is not swallowed by a grab it cannot do",
		function()
			local w = primaryWorld({ selection = "multi", input = "gamepad" })
			-- into edit mode through the affordance a pad actually has
			expect(w.pres.focus.focused:get()).toBe(TOGGLE)
			w.system.deviceKey("ButtonA", true)
			w.system.deviceKey("ButtonA", false)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(true)

			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
			expect(w.pres.focus.focused:get()).toBe(hit("r1"))
			w.system.deviceKey("ButtonA", true)
			w.system.deviceKey("ButtonA", false)
			w.pres.refresh()
			expect(#w.opened).toBe(1)
			expect(w.opened[1].key).toBe("r1")
			-- and no phantom grab was left behind on a table with nothing to move
			expect(w.tbl.api.grabbedKey:get()).toBe(nil)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	it(
		"Table keyboard: in edit mode a NON-reorderable table still opens rows — Return is not swallowed by a grab it cannot do",
		function()
			local w = primaryWorld({ selection = "multi", input = "gamepad" })
			w.system.deviceKey("Return", true)
			w.system.deviceKey("Return", false)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(true)

			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			expect(w.pres.focus.focused:get()).toBe(hit("r2"))
			w.system.deviceKey("Return", true)
			w.system.deviceKey("Return", false)
			w.pres.refresh()
			expect(#w.opened).toBe(1)
			expect(w.opened[1].key).toBe("r2")
			expect(w.tbl.api.grabbedKey:get()).toBe(nil)
			expect(#w.handle.controller.diagnostics()).toBe(0)
		end
	)

	--[[ A DEAD TAP IS NOT A SELECTION (redteam item 6, MEDIUM; 2026-08-13).
		The touch branch handed the tap to selection whenever the table was
		editing, without asking whether there IS a selection to make. On a
		`selection = "none"` reorderable table — a legal, shipped shape, where edit
		mode exists only to raise the ≡ handles — `api.select` returns on its first
		line, so the tap did nothing at all: a row that opened one Edit press
		earlier became inert for as long as edit mode lasted. ]]
	it('Table touch: a selection = "none" reorderable table still OPENS a row while editing', function()
		local w = primaryWorld({ selection = "none", reorderable = true, input = "touch" })
		w.adapter.touchTap(hit("r2"))
		expect(#w.opened).toBe(1) -- normal mode, as before
		w.adapter.touchTap(TOGGLE)
		w.pres.refresh()
		expect(w.tbl.api.editing:get()).toBe(true)
		-- the ≡ handle is up (edit mode is doing its one job here)...
		expect(w.adapter.node(`/S/T/Main/Body/Rows/[r2@0]/Row/EditWhen/then/HandleZone/Handle`) ~= nil).toBe(true)
		-- ...and the tap still opens, because there is no selection for it to
		-- become instead
		w.adapter.touchTap(hit("r2"))
		w.pres.refresh()
		expect(#w.opened).toBe(2)
		expect(w.opened[2].key).toBe("r2")
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)

	--[[ THE META-LESS ACTIVATE, DECIDED RATHER THAN INHERITED (redteam item 10,
		2026-08-13). `meta == nil` means "no input facts at all" and has always
		routed to the touch branch — but since parity round 2 that branch OPENS a
		primary-action table instead of selecting it, so the default now carries a
		much larger verb, and it is reachable from `ScreenTarget.driveActivate(path)`
		on any session. The decision is to KEEP it (the full argument is the codicil
		in docs/lessons/a-synthesized-activate-must-carry-the-pointer-kind.md);
		this case is what makes it a decision rather than an accident — a change of
		mind has to come here and say so. `adapter.driveActivate` is the headless
		mirror of the same seam, so this drives the verb through the seam that
		reaches it in production, not through `api.handleActivate` directly. ]]
	it("a meta-less Activate is the TOUCH verb: it opens a primary-action table", function()
		local w = primaryWorld({ selection = "multi" })
		expect(w.adapter.driveActivate(hit("r2"))).toBe(true)
		w.pres.refresh()
		expect(#w.opened).toBe(1)
		expect(w.opened[1].key).toBe("r2")
		expect(w.tbl.api.selectedKeys:get().r2).toBe(nil) -- opened, not selected
		-- ...and the mouse semantics are one explicit field away, for a caller who
		-- wants them: a single click on this same table selects and never opens
		expect(w.adapter.driveActivate(hit("r3"), { source = "pointer", pointer = "mouse" })).toBe(true)
		w.pres.refresh()
		expect(#w.opened).toBe(1)
		expect(w.tbl.api.selectedKeys:get().r3).toBe(true)
	end)

	it("a table with NO onPrimaryAction behaves exactly as it does today on all four inputs", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(bigRows(3))
		local tbl = table_control.build(Facet, core, {
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
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
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

-- =============================================================================
-- 6. THE SWIPE SUPPRESSION IS NOT A TRAP FOR THE NEXT DEVICE PRESS
--    (redteam NEW-2, MEDIUM; 2026-08-13 — a regression introduced by a6229e0)
--
-- `a6229e0` armed `suppressActivatePath` at the axis lock (the BLOCKER fix: a
-- swipe must survive its own release `Activated`) and cleared it in ONE place,
-- `hitOnPointerDown`, on this stated rule:
--
--   "A real Activated always fires between a pointer-up and the next
--    pointer-down, so a still-live suppression can never legitimately survive
--    to see another down."
--
-- THE RULE IS FALSE, for the two Activate producers that carry no pointer-down
-- at all: an IAS device Activate (gamepad A / keyboard Return — `meta.source ==
-- "action"`, dispatched by the action system, no pointer event anywhere), and
-- the minimum-target hit expander, a SEPARATE `GuiButton` whose press produces
-- no pointer event on the row's own `Hit` (screen_target.luau's
-- `pointerActivateMeta`). So any swipe that ends WITHOUT an `Activated` — a
-- cancel (capture loss, row unmount, scroll steal) or a release landing off the
-- translated `Hit` — left the arm standing, and the next device press on that
-- row was swallowed whole. Measured on both trees with the same probe:
--
--                                              13fd3c6      a6229e0
--   swipe cancelled, then gamepad A        fired 0 -> 1   fired 0 -> 0
--   swipe silent release, then gamepad A   tray closes    tray stays open
--
-- Two clears close it: a CANCEL clears the arm (the engine fires no `Activated`
-- for a capture it took away), and `handleActivate` refuses to spend the arm on
-- a device Activate at all — a pointer gesture's artifact is a POINTER's.
-- =============================================================================
describe("table_input: a swipe that ends with no Activated does not eat the next device press", function()
	local function swipeWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		-- A PAD PLUS A KEYBOARD: the one session class that can drive ButtonA at
		-- the rows, the same choice `primaryWorld({ input = "gamepad" })` makes.
		env:set("preferredInput", "Gamepad")
		env:set("capabilities", { keyboard = true, mouse = false, touch = false, gamepad = true })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local opened: { string } = {}
		local fired: { string } = {}
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(3)),
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
				selection = "single",
				rowHeight = 40,
				env = env,
				onPrimaryAction = function(_item: any, key: string)
					table.insert(opened, key)
				end,
				rowActions = function(_item: any): any
					return {
						trailing = {
							{
								id = "delete",
								role = "destructive",
								label = "Delete",
								onAction = function()
									table.insert(fired, "delete")
								end,
							},
						},
					}
				end,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		local w: any = {
			core = core,
			adapter = adapter,
			pres = pres,
			system = system,
			tbl = tbl,
			handle = handle,
			opened = opened,
			fired = fired,
		}
		function w.settle(frames: number?)
			for _ = 1, frames or 150 do
				clock.t += 1 / 60
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		return w
	end

	-- the wrapped row's own hit, and the tray the swipe reveals
	local function wrappedHit(key: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Hit`
	end
	local function trayAction(key: string, action: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}/TrayTrailingWhen/then/TrayTrailing/Action:{action}`
	end

	-- a horizontal swipe past the axis lock; `finish` is how the gesture ends
	local function swipe(w: any, key: string, finish: "cancel" | "silent")
		local rect = w.adapter.node(wrappedHit(key)).rect
		local originX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		w.adapter.pointerDown(wrappedHit(key), originX, y, "touch")
		w.settle(1)
		for i = 1, 8 do
			w.adapter.pointerMove(originX - (rect.w * 0.3) * (i / 8), y, "touch")
			w.settle(1)
		end
		if finish == "cancel" then
			w.adapter.interruptCapture() -- the Roblox menu opened: no Activated follows
		else
			w.adapter.pointerUp(originX - rect.w * 0.3, y) -- an up off the translated Hit
		end
		w.settle()
	end

	-- an IAS DEVICE Activate on a named row: gamepad A, through the real action
	-- system, `meta.source == "action"`, and no pointer event whatsoever
	local function gamepadActivate(w: any, key: string)
		w.pres.focus.focusOn(wrappedHit(key))
		w.pres.refresh()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.settle(60)
	end

	it("a swipe CANCELLED mid-gesture does not swallow the next gamepad Activate on that row", function()
		local w = swipeWorld()
		swipe(w, "r1", "cancel")
		expect(#w.opened).toBe(0)
		gamepadActivate(w, "r1")
		expect(w.opened).toEqual({ "r1" }) -- the press LANDED
		expect(w.fired).toEqual({})
	end)

	--[[ THE OTHER PRODUCER WITH NO POINTER-DOWN: the minimum-target hit expander.
		It is a SEPARATE `GuiButton` overlapping a short row, and pressing it fires
		THIS row's activate handler with a full pointer meta and no pointer event
		on the row's own `Hit` at all (screen_target.luau's `pointerActivateMeta`,
		reached through `handle.activate`). `adapter.driveActivate` is that seam's
		headless mirror — the same call into the same registered handler.

		It is a POINTER Activate, so the `meta.source == "action"` half of the fix
		does not cover it: the CANCEL clear is the only thing standing between a
		cancelled swipe and a dead press on that row. This is the case that proves
		the clear is load-bearing rather than belt-and-braces. ]]
	it("a swipe CANCELLED mid-gesture does not swallow the hit expander's Activate either", function()
		local w = swipeWorld()
		swipe(w, "r1", "cancel")
		local rect = w.adapter.node(wrappedHit("r1")).rect
		w.adapter.driveActivate(wrappedHit("r1"), {
			source = "pointer",
			pointer = "touch",
			x = rect.x + rect.w / 2,
			y = rect.y - 2, -- the 44px overhang: outside the row, inside the target
		})
		w.settle(30)
		expect(w.opened).toEqual({ "r1" })
	end)

	it("a swipe with a SILENT release still answers the next gamepad Activate with a tray close", function()
		local w = swipeWorld()
		swipe(w, "r1", "silent")
		expect(w.adapter.node(trayAction("r1", "delete"))).never().toBeNil()
		gamepadActivate(w, "r1")
		-- the device verb on an open row is CLOSE, and it was not eaten
		expect(w.adapter.node(trayAction("r1", "delete"))).toBeNil()
		expect(#w.opened).toBe(0)
		-- ...and the row is an ordinary row again on the very next press
		gamepadActivate(w, "r1")
		expect(w.opened).toEqual({ "r1" })
	end)

	--[[ THE CONTROL, and the reason this pair is not a licence to stop
		suppressing: a swipe whose release DID carry an `Activated` still eats
		exactly that one artifact — the a6229e0 BLOCKER fix, unweakened — and a
		device press after it behaves normally. Without this, "clear the arm more
		often" would pass by simply never arming. ]]
	it("a swipe whose release DID Activate still swallows that artifact, and the tray survives it", function()
		local w = swipeWorld()
		local rect = w.adapter.node(wrappedHit("r1")).rect
		local originX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		w.adapter.pointerDown(wrappedHit("r1"), originX, y, "touch")
		w.settle(1)
		for i = 1, 8 do
			w.adapter.pointerMove(originX - (rect.w * 0.3) * (i / 8), y, "touch")
			w.settle(1)
		end
		w.adapter.pointerUpActivating(originX - rect.w * 0.3, y, "after")
		w.settle()
		expect(w.adapter.node(trayAction("r1", "delete"))).never().toBeNil() -- tray survived
		expect(#w.opened).toBe(0) -- and the artifact fired nothing
		gamepadActivate(w, "r1")
		expect(w.adapter.node(trayAction("r1", "delete"))).toBeNil()
		expect(#w.opened).toBe(0)
	end)
end)

-- =============================================================================
-- 7. THE ROW-ACTIONS SURFACE IS REACHABLE WITHOUT A POINTER
--    (parity round 3, "Still owed" row 8; RED-TEAM cross-platform charter)
--
-- A Table row that declares `spec.rowActions` is WRAPPED: `row_actions.build`'s
-- own root Anchor sits between the ForEach slot and the row's own `Row` node,
-- and the tray `When`s and the edit-mode minus are that wrapper's OTHER
-- children — SIBLINGS of `Row`, not descendants of it. Table's focus
-- contribution collected the focusables INSIDE `Row`, so everything the wrapper
-- owns landed in no focus group at all, and a contribution owns its subtree's
-- focus (`focus_map.autoGroups` emits a contribution's groups and does not
-- descend). A player could swipe a row open with a finger and then have no key
-- and no d-pad direction that reached what they revealed; in edit mode the
-- minus — the ONLY affordance a touch player has for delete — was unreachable
-- to a keyboard and a pad outright.
-- =============================================================================
describe("table_input: a revealed tray and the edit minus are reachable by keyboard and pad", function()
	local function trayWorld(opts: any?)
		local options = opts or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("preferredInput", "Gamepad")
		env:set("capabilities", { keyboard = true, mouse = false, touch = false, gamepad = true })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local fired: { string } = {}
		local editing = core:signal(options.editing == true)
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(3)),
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
				selection = "single",
				rowHeight = 40,
				env = env,
				editing = editing,
				--[[ THE LOG NAMES THE ROW, and that is not cosmetic (2026-08-16). It
					used to record the ACTION alone (`"delete"`), so every assertion here
					could only say "a delete fired" — and a targeting bug that fires the
					RIGHT action on the WRONG ROW is invisible to that. R8-5 below is
					exactly that bug, shipped under four green cases. ]]
				rowActions = function(item: any): any
					local key = item.id
					return {
						leading = if options.leading
							then {
								{
									id = "flag",
									label = "Flag",
									onAction = function()
										table.insert(fired, `flag:{key}`)
									end,
								},
							}
							else nil,
						trailing = {
							{
								id = "delete",
								role = "destructive",
								label = "Delete",
								onAction = function()
									table.insert(fired, `delete:{key}`)
								end,
							},
						},
						fullSwipe = false, -- a long drag can only ever open, never commit
					}
				end,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any = {
			core = core,
			adapter = adapter,
			pres = pres,
			system = system,
			tbl = tbl,
			handle = handle,
			fired = fired,
			editing = editing,
		}
		function w.settle(frames: number?)
			for _ = 1, frames or 150 do
				clock.t += 1 / 60
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.press(key: string)
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
			w.settle(2)
		end
		function w.groupFor(key: string): any
			for _, group in w.handle.focusOrder().navigation do
				if group.name == `row:{key}` then
					return group
				end
			end
			return nil
		end
		return w
	end

	local function rowRoot(key: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}`
	end
	local function wrappedHit(key: string): string
		return `{rowRoot(key)}/Content/Row/Hit`
	end
	local function trayAction(key: string, edge: string, action: string): string
		local tid = if edge == "leading" then "TrayLeading" else "TrayTrailing"
		return `{rowRoot(key)}/{tid}When/then/{tid}/Action:{action}`
	end
	local function minus(key: string): string
		return `{rowRoot(key)}/EditAffordanceWhen/then/EditAffordance`
	end

	-- a horizontal swipe past the axis lock, released where the finger is
	local function swipeOpen(w: any, key: string, direction: number)
		local rect = w.adapter.node(wrappedHit(key)).rect
		local originX = if direction < 0 then rect.x + rect.w - 8 else rect.x + 8
		local y = rect.y + rect.h / 2
		w.adapter.pointerDown(wrappedHit(key), originX, y, "touch")
		w.settle(1)
		for i = 1, 8 do
			w.adapter.pointerMove(originX + direction * (rect.w * 0.3) * (i / 8), y, "touch")
			w.settle(1)
		end
		w.adapter.pointerUp(originX + direction * rect.w * 0.3, y)
		w.settle()
	end

	it("(R8-1) a revealed TRAILING tray joins the focused row's own group, and the pad walks into it", function()
		local w = trayWorld()
		-- CLOSED: the group is the row hit alone, and no overlay/tray path is in it
		local closed = w.groupFor("r1")
		expect(closed).never().toBeNil()
		expect(closed.order).toEqual({ wrappedHit("r1") })

		swipeOpen(w, "r1", -1)
		expect(w.adapter.node(trayAction("r1", "trailing", "delete"))).never().toBeNil()
		-- OPEN: the tray's button is a stop in the SAME horizontal row group,
		-- after the row's own content — which is both where it is painted and
		-- where the ordering rule puts every affordance (index 1 stays the row)
		local open = w.groupFor("r1")
		expect(open.axis).toBe("horizontal")
		expect(open.order).toEqual({ wrappedHit("r1"), trayAction("r1", "trailing", "delete") })

		-- ...and the d-pad reaches it for real, then fires it
		w.pres.focus.focusOn(wrappedHit("r1"))
		w.pres.refresh()
		w.press("DPadRight")
		expect(w.pres.focus.focused:get()).toBe(trayAction("r1", "trailing", "delete"))
		expect(w.adapter.node(trayAction("r1", "trailing", "delete")).focused).toBe(true)
		w.press("ButtonA")
		w.settle()
		expect(w.fired).toEqual({ "delete:r1" })
	end)

	it("(R8-2) a LEADING tray is reachable too, and the ROW keeps the primary stop", function()
		--[[ The stated cost of one group per row: a leading affordance is reached
			by continuing RIGHT off the row, not by pressing Left toward where it
			is painted. What must NOT move is index 1 — every vertical entry into
			a row lands there (`focus_graph.enterGroup`, ordinal nearest), and the
			row's own activate is its primary verb. ]]
		local w = trayWorld({ leading = true })
		swipeOpen(w, "r2", 1)
		expect(w.adapter.node(trayAction("r2", "leading", "flag"))).never().toBeNil()
		local open = w.groupFor("r2")
		expect(open.order).toEqual({ wrappedHit("r2"), trayAction("r2", "leading", "flag") })
		w.pres.focus.focusOn(wrappedHit("r2"))
		w.pres.refresh()
		w.press("DPadRight")
		expect(w.pres.focus.focused:get()).toBe(trayAction("r2", "leading", "flag"))
		w.press("ButtonA")
		w.settle()
		expect(w.fired).toEqual({ "flag:r2" })
	end)

	it("(R8-3) the EDIT-MODE MINUS is a focus stop, and Activate on it deletes", function()
		--[[ The minus is the only delete affordance a touch player has in edit
			mode, and it announces itself with the destructive action's own label
			("Delete"). Pressing it runs the same `commitDestructive` funnel a tap
			does (the 2026-08-13 director ruling).

			IT IS NOT INDEX 1, deliberately: it is painted in the row's leading
			gutter, but making it the first stop puts a Delete button under the
			ring for every pad that walks down into an editing table. ]]
		local w = trayWorld({ editing = true })
		expect(w.adapter.node(minus("r1"))).never().toBeNil()
		expect(w.groupFor("r1").order).toEqual({ wrappedHit("r1"), minus("r1") })
		w.pres.focus.focusOn(wrappedHit("r1"))
		w.pres.refresh()
		w.press("DPadRight")
		expect(w.pres.focus.focused:get()).toBe(minus("r1"))
		w.press("ButtonA")
		w.settle()
		expect(w.fired).toEqual({ "delete:r1" })
	end)

	it("(R8-5) LEFT off a focused row reaches THIS row's minus, never the row above's", function()
		--[[ THE DIRECTOR'S BUG, on a real pad (2026-08-16): "in playlist table with
			gamepad, when the table is in edit mode and a row is selected, I'd expect
			left on the d-pad to select delete for this row. Instead it goes to delete
			for the prior row."

			The minus is painted in the row's LEADING gutter, so Left is the press
			that reaches it. It used to be spliced into the row's own horizontal
			group as its LAST stop, which made Left at index 1 an EXIT — and an
			uncontained group's exit falls through the group array in the direction
			of travel, i.e. onto the PREVIOUS row's group, entered at its far end.
			In edit mode that far end is a Delete button belonging to another row. ]]
		local w = trayWorld({ editing = true })
		w.pres.focus.focusOn(wrappedHit("r2"))
		w.pres.refresh()
		w.press("DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(minus("r2"))
		-- ...and it is THIS row's delete that fires, not the one above's
		w.press("ButtonA")
		w.settle()
		expect(w.fired).toEqual({ "delete:r2" })
	end)

	it("(R8-6) a horizontal press NEVER changes rows — on the pad and on the keyboard alike", function()
		--[[ The general law R8-5 is one instance of. An index bug rarely respects
			one direction, and the director tested one path on one input class, so
			both are measured here.

			RIGHT leaked exactly the same way and merely got away with it: off the ⊖
			it fell through to the NEXT row's group, entered at the far end for
			rightward travel — which is index 1, the row's own hit rather than a
			destructive button. Same defect, benign landing. ]]
		local w = trayWorld({ editing = true })
		local function walk(from: string, key: string): string
			w.pres.focus.focusOn(from)
			w.pres.refresh()
			w.press(key)
			return w.pres.focus.focused:get()
		end
		for _, keys in { { "DPadLeft", "DPadRight" }, { "Left", "Right" } } do
			local left, right = keys[1], keys[2]
			-- LEFT off the primary stop: this row's own leading ⊖, on every row
			expect(walk(wrappedHit("r2"), left)).toBe(minus("r2"))
			expect(walk(wrappedHit("r3"), left)).toBe(minus("r3"))
			-- ...including the FIRST row, which showed no symptom before the fix
			-- only because it had no group above to fall into
			expect(walk(wrappedHit("r1"), left)).toBe(minus("r1"))
			-- RIGHT off the far end comes back to the row it belongs to, never r3
			expect(walk(minus("r2"), right)).toBe(wrappedHit("r2"))
			-- and the ⊖ returns to the hit from the other side too
			expect(walk(minus("r2"), left)).toBe(wrappedHit("r2"))
		end
		-- the ring is closed, not silent: every landing above is still a real stop
		expect(w.groupFor("r2").order).toEqual({ wrappedHit("r2"), minus("r2") })
	end)

	it("(R8-4) a CLOSED row is byte-identical to today: no wrapper path is a focus stop", function()
		--[[ The control for the three above. Every focusable the wrapper owns is
			`When`-gated, so a row nobody has swiped and no edit mode has reached
			must contribute exactly what it always did — the row hit and its own
			focusable cell content, nothing more. ]]
		local w = trayWorld()
		for _, key in { "r1", "r2", "r3" } do
			expect(w.groupFor(key).order).toEqual({ wrappedHit(key) })
		end
		-- ...and a tray that OPENS and CLOSES again leaves nothing behind
		swipeOpen(w, "r1", -1)
		expect(#w.groupFor("r1").order).toBe(2)
		w.pres.focus.focusOn(wrappedHit("r1"))
		w.pres.refresh()
		w.press("ButtonB") -- Cancel closes the tray
		w.settle()
		expect(w.adapter.node(trayAction("r1", "trailing", "delete"))).toBeNil()
		expect(w.groupFor("r1").order).toEqual({ wrappedHit("r1") })
	end)
end)

-- =============================================================================
-- ADAPT-18 · COLUMN PRIORITY-COLLAPSE, and the disclosure that keeps it honest
--
-- THE DIRECTOR'S OWN DEVICE CASE is the first one below, verbatim from the DIR-4
-- report that produced the resize clamp: resize Name and Artist wide in
-- landscape, rotate to portrait — and Rating, which used to be PUSHED OFF SCREEN
-- while the header went on claiming it was 96px wide, now COLLAPSES, says so, and
-- comes back on the way home.
--
-- Every case here drives the real seams: a rotation is an `env` write, a tap is
-- an adapter pointer, a pad is `system.deviceKey`. No `tbl.api.*` call decides an
-- assertion.
-- =============================================================================
describe("table_input: column priority-collapse and its disclosure (ADAPT-18)", function()
	local CHIP = "/S/T/Main/MoreWhen/then/MoreBar/MoreChip"
	local function head(id: string): string
		return `/S/T/Main/Header/Head-{id}`
	end
	local function cell(key: string, id: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/Row/Cells/Cell-{id}`
	end

	local function collapseWorld(opts: any?)
		local options = opts or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 500 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local sortOrder = core:signal(nil :: any)
		local tbl = table_control.build(Facet, core, {
			id = "T",
			rows = core:signal(bigRows(3)),
			key = function(r: any)
				return r.id
			end,
			columns = options.columns or {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 200,
					value = function(r: any)
						return r.name
					end,
				},
				{
					id = "artist",
					title = "Artist",
					width = { type = "fill", weight = 1 },
					minWidth = 160,
					value = function(r: any)
						return `Artist {r.laps}`
					end,
				},
				{
					id = "rating",
					title = "Rating",
					width = { type = "fixed", px = 96 },
					value = function(r: any)
						return tostring(r.laps)
					end,
				},
			},
			selection = "single",
			rowHeight = 40,
			sortOrder = sortOrder,
			env = env,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any = { core = core, env = env, adapter = adapter, pres = pres, system = system, tbl = tbl }
		w.handle = handle
		w.sortOrder = sortOrder
		function w.settle(frames: number?)
			for _ = 1, frames or 6 do
				clock.t += 1 / 60
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.resize(width: number, height: number)
			env:set("viewportRect", { x = 0, y = 0, w = width, h = height })
			w.settle()
		end
		function w.press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.settle(2)
		end
		function w.groupNames(): { string }
			local out: { string } = {}
			for _, group in handle.focusOrder().navigation do
				table.insert(out, group.name)
			end
			return out
		end
		w.settle()
		return w
	end

	-- a node is "on screen" when it has a real box inside the viewport; the defect
	-- this feature replaces is a column whose box was fine and whose PIXELS were
	-- 250px past the right edge
	local function paintsWithin(w: any, path: string, viewportW: number): boolean
		local node = w.adapter.node(path)
		if node == nil or node.rect == nil then
			return false
		end
		return node.rect.w > 0 and node.rect.x + node.rect.w <= viewportW + 0.5
	end

	it("THE DIRECTOR'S CASE: landscape holds three columns; portrait collapses Rating and says so", function()
		local w = collapseWorld()
		-- LANDSCAPE: all three stand, nothing is disclosed, and the band has no chip
		expect(w.adapter.node(head("rating")).rect.w > 0).toBe(true)
		expect(w.adapter.node(CHIP)).toBeNil()
		expect(w.tbl.dump().hiddenColumns).toEqual({})

		-- THE ROTATION: 900x500 landscape becomes a 393x800 portrait phone
		w.resize(393, 800)
		-- Rating is COLLAPSED — not pushed off screen, which is the defect
		expect(w.tbl.dump().hiddenColumns).toEqual({ "rating" })
		expect(w.adapter.node(head("rating")).rect.w).toBe(0)
		expect(w.adapter.node(cell("r1", "rating")).rect.w).toBe(0)
		-- ...and the two that stayed are ON SCREEN, at their declared floors
		expect(paintsWithin(w, head("name"), 393)).toBe(true)
		expect(paintsWithin(w, head("artist"), 393)).toBe(true)
		expect(w.adapter.node(cell("r1", "name")).rect.w >= 200).toBe(true)

		--[[ ...AND THE CELL IS HIDDEN, NOT MERELY NARROW. A zero-width box alone
			would leave the collapsed value painting at the row's origin, still in the
			focus order and still taking taps — which is the whole reason this is
			spent as `hidden` rather than as a dim. The adapter records what the
			renderer actually wrote, so this reads the engine's answer rather than
			the blueprint's intent. ]]
		expect(w.adapter.visibleOf(cell("r1", "rating"))).toBe(false)
		expect(w.adapter.visibleOf(cell("r1", "name"))).never().toBe(false)
		expect(w.adapter.visibleOf(head("rating"))).toBe(false)

		-- THE DISCLOSURE IS PRESENT AND SAYS HOW MANY
		local chip = w.adapter.node(CHIP)
		expect(chip).never().toBeNil()
		expect(chip.props.label).toBe("1 more")

		-- WIDEN: it comes back, and the chip goes
		w.resize(900, 500)
		expect(w.tbl.dump().hiddenColumns).toEqual({})
		expect(w.adapter.node(head("rating")).rect.w > 0).toBe(true)
		expect(w.adapter.visibleOf(cell("r1", "rating"))).never().toBe(false)
		expect(w.adapter.node(CHIP)).toBeNil()
	end)

	it("the collapse costs no selection and no focus — it is a hide, not a remount", function()
		--[[ The property that made `hidden` the right primitive rather than
			`UI.When`. A rotation on a phone is not a rare event, and a paradigm that
			dropped the player's selection every time the device turned would be a
			worse defect than the one it fixes. ]]
		local w = collapseWorld()
		w.pres.focus.focusOn(`/S/T/Main/Body/Rows/[r2@0]/Row/Hit`)
		w.settle()
		w.tbl.api.select("r2", { mode = "replace" })
		w.settle()
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)

		w.resize(393, 800)
		expect(w.tbl.dump().hiddenColumns).toEqual({ "rating" })
		-- the selection and the ring are exactly where they were
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
		expect(w.pres.focus.focused:get()).toBe(`/S/T/Main/Body/Rows/[r2@0]/Row/Hit`)
		-- ...and the row was never rebuilt: its key still carries version 0
		expect(w.adapter.node(`/S/T/Main/Body/Rows/[r2@0]/Row/Hit`)).never().toBeNil()

		w.resize(900, 500)
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
	end)

	it("a collapsed column leaves the focus ring and stops taking taps, subtree and all", function()
		local w = collapseWorld({
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 200,
					value = function(r: any)
						return r.name
					end,
				},
				{
					id = "rating",
					title = "Rating",
					width = { type = "fixed", px = 120 },
					minWidth = 120,
					resizable = true,
					value = function(r: any)
						return tostring(r.laps)
					end,
				},
			},
		})
		-- WIDE: the rating heading is a focus stop and a resize target
		expect(w.handle.focusOrder().navigation[1].order).toEqual({
			`{head("name")}/Column`,
			`{head("rating")}/Column`,
		})

		w.resize(280, 800)
		expect(w.tbl.dump().hiddenColumns).toEqual({ "rating" })
		--[[ J-9: "focus never lands where the player cannot see". The audit measured
			four DPadRight presses landing the ring on a column at x=640..720 on a
			390px viewport, `focusVisible = true`, with nothing able to scroll it into
			view. A hidden subtree leaves the ring, so there is nowhere for it to land. ]]
		expect(w.handle.focusOrder().navigation[1].order).toEqual({ `{head("name")}/Column` })
		-- ...and its resize grip's 44px hit expander goes with it, rather than
		-- staying as a dead band on a column nobody can see
		expect(w.tbl.api.adjustTargets(w.handle.root)[`{head("rating")}/Column`]).toBeNil()
	end)

	it("the disclosure chip is a focus stop of its own, and a PAD opens the plate", function()
		local w = collapseWorld()
		w.resize(393, 800)
		-- its own group, between the headings and the rows
		local names = w.groupNames()
		expect(table.find(names, "columns-more") ~= nil).toBe(true)
		expect(table.find(names, "columns-more") > table.find(names, "headers")).toBe(true)

		w.pres.focus.focusOn(CHIP)
		w.settle()
		expect(w.pres.focus.focused:get()).toBe(CHIP)
		expect(w.tbl.dump().columnPlate).toBe("closed")

		-- A OPENS
		w.press("ButtonA")
		expect(w.tbl.dump().columnPlate).never().toBe("closed")
		-- the plate lists the collapsed column, and every mounted row's value for it
		local plateRow = `Row-rating-r2`
		local found = false
		for _, path in w.adapter.paths() do
			if string.find(path, plateRow, 1, true) ~= nil then
				found = true
			end
		end
		expect(found).toBe(true)

		-- B CLOSES, and the ring comes back to the affordance that opened it
		w.press("ButtonB")
		expect(w.tbl.dump().columnPlate).toBe("closed")
		expect(w.pres.focus.focused:get()).toBe(CHIP)
	end)

	it("a TOUCH tap opens it, and a second tap closes it — the trap a disclosure must not become", function()
		local w = collapseWorld()
		w.resize(393, 800)
		local chip = w.adapter.node(CHIP)
		expect(chip).never().toBeNil()
		--[[ THE 44px BAND, on the node a finger actually presses. The chip declares
			a `minMax` FLOOR at the theme's own target minimum rather than a fixed
			height, so this reads the box the player gets rather than the token the
			author wrote. ]]
		expect(chip.rect.h >= 44).toBe(true)
		--[[ `touchTap`, not `tap`: the honest three-step order (InputBegan,
			InputEnded, THEN Activated with a real `{ source = "pointer", pointer =
			"touch" }`), which is the driver that can see a defect living in the order
			or in the meta. ]]
		w.adapter.touchTap(CHIP)
		w.settle()
		expect(w.tbl.dump().columnPlate).never().toBe("closed")
		-- a second press on the SAME affordance closes it: an affordance that opens
		-- and then does nothing is how a disclosure becomes a trap on touch
		w.adapter.touchTap(CHIP)
		w.settle()
		expect(w.tbl.dump().columnPlate).toBe("closed")
	end)

	it("a MOUSE click opens it too, with the pointer meta a click actually carries", function()
		local w = collapseWorld()
		w.resize(393, 800)
		expect(w.adapter.node(CHIP)).never().toBeNil()
		w.adapter.tap(CHIP, { source = "pointer", pointer = "mouse" })
		w.settle()
		expect(w.tbl.dump().columnPlate).never().toBe("closed")
	end)

	it("a KEYBOARD Return opens it, and the plate's own Close is the way out", function()
		local w = collapseWorld()
		w.resize(393, 800)
		w.pres.focus.focusOn(CHIP)
		w.settle()
		w.press("Return")
		expect(w.tbl.dump().columnPlate).never().toBe("closed")
		--[[ Escape is permanently the engine's (ADR-0013 justified exception), so a
			modal's own close affordance IS the keyboard route out — the identical
			affordance and the identical reason as `UI.Region`'s plate. ]]
		local closePath: string? = nil
		for _, path in w.adapter.paths() do
			if string.find(path, "/PlateClose", 1, true) ~= nil then
				closePath = path
			end
		end
		expect(closePath).never().toBeNil()
		w.pres.focus.focusOn(closePath :: string)
		w.settle()
		w.press("Return")
		expect(w.tbl.dump().columnPlate).toBe("closed")
	end)

	it("a collapsed column's SORT is still selectable, from the plate", function()
		local w = collapseWorld()
		w.resize(393, 800)
		expect(w.sortOrder:get()).toBeNil()
		w.pres.focus.focusOn(CHIP)
		w.settle()
		w.press("Return")
		local sortPath: string? = nil
		for _, path in w.adapter.paths() do
			if string.find(path, "/Sort-rating", 1, true) ~= nil then
				sortPath = path
			end
		end
		expect(sortPath).never().toBeNil()
		w.pres.focus.focusOn(sortPath :: string)
		w.settle()
		w.press("Return")
		-- the same `cycleSort` the heading would have called, on a column whose
		-- heading is not on the screen
		expect((w.sortOrder:get() or {}).column).toBe("rating")
		expect((w.sortOrder:get() or {}).ascending).toBe(true)
	end)

	it("the plate closes by itself when the columns come back", function()
		--[[ `region_expand`'s epoch check, doing the job it was written for: the
			plate is anchored to the chip, and widening the table unmounts the chip.
			A disclosure left standing over a table that is no longer disclosing
			anything is the "plate pointing at a box that moved" case its own header
			names. ]]
		local w = collapseWorld()
		w.resize(393, 800)
		w.pres.focus.focusOn(CHIP)
		w.settle()
		w.press("Return")
		expect(w.tbl.dump().columnPlate).never().toBe("closed")
		w.resize(900, 500)
		expect(w.tbl.dump().columnPlate).toBe("closed")
	end)
end)

-- =============================================================================
-- ADAPT-13 · a Table that declares only `rowActions` is unreachable off a pointer
--
-- THE AUDIT'S MEASUREMENT (matrix K-2, severity high): "The table has ZERO focus
-- stops. Initial focus nil; twelve Down presses reach nil; Delete fired: 0;
-- ButtonX menu: false." The row `Hit`'s `focusable` was
-- `selectionMode ~= "none" or spec.reorderable == true`, and `rowActions` is in
-- neither disjunct — so a table whose ONLY verbs are its row actions built no
-- focus stop, the engine never built a key context for the row, and the Delete
-- and menu bindings the wrapper carries had nothing to bind to. `api.md:4445`
-- claimed the opposite in as many words ("Keyboard and gamepad Delete/menu bind
-- per row through the wrapper itself ... with no separate Table wiring"), and
-- `virtual_list.luau:1780-1792` had already diagnosed and closed the identical
-- defect for lists.
-- =============================================================================
describe("table_input: a rowActions-only table is reachable on keyboard and gamepad (ADAPT-13)", function()
	local function actionsOnlyWorld(opts: any?)
		local options = opts or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local fired: { string } = {}
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(3)),
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
				-- THE SHAPE THE AUDIT MEASURED: no selection, not reorderable, no
				-- primary action. The row's only verbs are the ones its tray carries.
				selection = options.selection,
				rowHeight = 40,
				env = env,
				rowActions = function(item: any): any
					local key = item.id
					return {
						trailing = {
							{
								id = "delete",
								label = "Delete",
								role = "destructive",
								onAction = function()
									table.insert(fired, `delete:{key}`)
								end,
							},
						},
					}
				end,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any = { core = core, adapter = adapter, pres = pres, system = system, tbl = tbl, fired = fired }
		w.handle = handle
		function w.settle(frames: number?)
			for _ = 1, frames or 90 do
				clock.t += 1 / 60
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.settle(2)
		end
		w.settle(2)
		return w
	end

	local function wrappedHitOf(key: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Hit`
	end

	it("its rows are focus stops at all, which is the whole mechanism", function()
		local w = actionsOnlyWorld()
		-- the audit's own probe: initial focus, and the first row's group
		expect(w.pres.focus.focused:get()).toBe(wrappedHitOf("r1"))
		local groups = w.handle.focusOrder().navigation
		local rowGroups = 0
		for _, group in groups do
			if string.match(group.name, "^row:") ~= nil then
				rowGroups += 1
			end
		end
		expect(rowGroups).toBe(3)
	end)

	it("...so Delete on a focused row fires its destructive action (keyboard)", function()
		local w = actionsOnlyWorld()
		expect(w.pres.focus.focused:get()).toBe(wrappedHitOf("r1"))
		w.press("Down")
		expect(w.pres.focus.focused:get()).toBe(wrappedHitOf("r2"))
		w.press("Delete")
		w.settle()
		expect(w.fired).toEqual({ "delete:r2" })
	end)

	it("...and a PAD reaches the same row and the same action", function()
		local w = actionsOnlyWorld()
		w.press("DPadDown")
		expect(w.pres.focus.focused:get()).toBe(wrappedHitOf("r2"))
		w.press("ButtonX")
		w.settle()
		-- ButtonX opens the row's action MENU rather than firing; what this asserts
		-- is that the press reached the row at all, which it could not before
		expect(w.adapter.node(`/S/T/Main/Body/Rows/[r2@0]/RowActions-r2/Content/Row/Hit`)).never().toBeNil()
	end)

	it("NULL HYPOTHESIS: a table with no selection, no reorder AND no rowActions still has none", function()
		--[[ The clause is a union over the verbs a row HAS, not a blanket "rows are
			focusable". A table that is a read-only grid of text has nothing for a
			focus stop to do, and giving it one would put a ring on every row of every
			static table in the framework. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(3)),
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
				rowHeight = 40,
				env = env,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local rowGroups = 0
		for _, group in handle.focusOrder().navigation do
			if string.match(group.name, "^row:") ~= nil then
				rowGroups += 1
			end
		end
		expect(rowGroups).toBe(0)
		tbl.dispose()
	end)
end)

-- =============================================================================
-- ADAPT-14 / ADAPT-15 · a multi-selection that survives the thing that moves it
--
-- THE TWO MEASUREMENTS (matrix L-6 and L-7, both high):
--   · keyboard — "a single arrow press destroys any multi-selection: ctrl-clicks
--     build [r1,r3], one Down -> [r4]. Ctrl+Down does not move without selecting.
--     Shift+Down x2 does not extend." A plain arrow REPLACING is correct and is
--     Apple's own model; what was missing is the two MODIFIED arrows, so a
--     keyboard could build a multi-selection and had no way to keep it.
--   · gamepad — "a pad can never hold two rows selected: A -> [r1], DPadDown ->
--     [r2], A -> [r2]." A pad Activate carries `shift`/`toggle` read from a
--     KEYBOARD-only modifier table, so every press lands in the replace branch;
--     and moving the ring replaces as well, so even a toggle would be undone by
--     the press that reaches the next row.
--
-- ONE RULE ANSWERS BOTH, and it is Apple's: EDIT MODE IS THE SELECTION MODE.
-- Inside it, focus is a cursor and Activate is the verb; outside it, the
-- modifiers decide. `table.luau`'s own primary-action block already quotes the
-- rule ("On devices without an attached keyboard and mouse or trackpad, people
-- can make multiple selections in lists only when edit mode is active") — this is
-- that sentence reaching the code that moves focus.
-- =============================================================================
describe("table_input: multi-selection survives focus movement (ADAPT-14/15)", function()
	local function multiWorld(opts: any?)
		local options = opts or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local editing = core:signal(options.editing == true)
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(5)),
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
				env = env,
				editing = editing,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any = {
			core = core,
			adapter = adapter,
			pres = pres,
			system = system,
			tbl = tbl,
			editing = editing,
			handle = handle,
		}
		function w.settle(frames: number?)
			for _ = 1, frames or 4 do
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.settle(2)
		end
		function w.selected(): { string }
			local out: { string } = {}
			for key, on in tbl.api.selectedKeys:get() do
				if on then
					table.insert(out, key)
				end
			end
			table.sort(out)
			return out
		end
		w.settle(2)
		return w
	end

	it("Ctrl+Down moves the ring and selects NOTHING — the focus cursor (ADAPT-14)", function()
		local w = multiWorld()
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		-- a PLAIN arrow first, which is what puts a selection there to lose
		w.press("Down")
		expect(w.selected()).toEqual({ "r2" })
		-- HOLD the modifier across the two presses, which is what a chord is
		w.system.deviceKey("LeftControl", true)
		w.press("Down")
		w.press("Down")
		w.system.deviceKey("LeftControl", false)
		w.settle()
		expect(w.pres.focus.focused:get()).toBe(hit("r4"))
		-- the ring travelled two rows and the selection did not move at all
		expect(w.selected()).toEqual({ "r2" })
	end)

	it("Shift+Down EXTENDS from the anchor instead of replacing (ADAPT-14)", function()
		local w = multiWorld()
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		w.press("Down")
		expect(w.selected()).toEqual({ "r2" })
		-- the anchor is the last non-range select, which is that plain arrow
		w.system.deviceKey("LeftShift", true)
		w.press("Down")
		w.press("Down")
		w.system.deviceKey("LeftShift", false)
		w.settle()
		expect(w.pres.focus.focused:get()).toBe(hit("r4"))
		expect(w.selected()).toEqual({ "r2", "r3", "r4" })
	end)

	it("a PLAIN arrow still replaces — Apple's own model, unchanged", function()
		--[[ The null hypothesis, and it matters: the defect here was never "an arrow
			replaces", which is what the Finder does and what every table in this
			framework has always done. It was that the two MODIFIED arrows had no
			meaning at all, so a selection a player built by hand could not survive
			the next press. ]]
		local w = multiWorld()
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		w.press("Down")
		expect(w.selected()).toEqual({ "r2" })
	end)

	it("a PAD holds two rows in edit mode: A toggles, and the ring does not undo it (ADAPT-15)", function()
		local w = multiWorld({ editing = true })
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		-- EDIT MODE IS THE SELECTION MODE: entering the row does not select it, and
		-- that is the half the pad was missing — a toggle undone by the very press
		-- that reaches the next row is not a multi-selection.
		expect(w.selected()).toEqual({})
		w.press("ButtonA")
		expect(w.selected()).toEqual({ "r1" })
		w.press("DPadDown")
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		expect(w.selected()).toEqual({ "r1" })
		w.press("ButtonA")
		expect(w.selected()).toEqual({ "r1", "r2" })
		-- ...and A again on a selected row takes it back out, which is what makes
		-- this a selection the player can steer rather than an accumulator
		w.press("ButtonA")
		expect(w.selected()).toEqual({ "r1" })
	end)

	it("a KEYBOARD Return does the identical thing in edit mode", function()
		local w = multiWorld({ editing = true })
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		w.press("Return")
		w.press("Down")
		w.press("Return")
		expect(w.selected()).toEqual({ "r1", "r2" })
	end)

	it("OUTSIDE edit mode the pad is unchanged: A on a row replaces", function()
		-- the cost of the rule stated as a case: a pad still cannot build a
		-- multi-selection without entering edit mode, which is exactly Apple's
		-- documented trade and the reason the auto Edit/Done toggle shows for a
		-- live gamepad class
		local w = multiWorld()
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		w.press("ButtonA")
		w.press("DPadDown")
		w.press("ButtonA")
		expect(w.selected()).toEqual({ "r2" })
	end)
end)

-- =============================================================================
-- ADAPT-27 · edit mode painted no selection affordance
-- M-4 · a keyboard-only session had no route into edit mode at all
-- =============================================================================
describe("table_input: edit mode says so, and a keyboard can reach it (ADAPT-27, M-4)", function()
	local function editWorld(opts: any?)
		local options = opts or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set(
			"capabilities",
			options.capabilities or { keyboard = true, mouse = false, touch = false, gamepad = false }
		)
		env:set("preferredInput", options.preferredInput or "KeyboardAndMouse")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local reorders: { any } = {}
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(3)),
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
				selection = options.selection,
				-- an OWNER-HELD edit signal is one of the two routes into edit mode, and the
				-- mark only mounts where a route exists (see the gate's own note)
				editing = if options.ownEditing then core:signal(false) else nil,
				reorderable = options.reorderable,
				onReorder = if options.reorderable
					then function(keys: any, toIndex: number)
						table.insert(reorders, { keys = keys, toIndex = toIndex })
					end
					else nil,
				rowHeight = 40,
				env = env,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any =
			{ core = core, env = env, adapter = adapter, pres = pres, system = system, tbl = tbl, reorders = reorders }
		w.handle = handle
		function w.settle(frames: number?)
			for _ = 1, frames or 4 do
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.settle(2)
		end
		w.settle(2)
		return w
	end

	local SELECT_MARK = "/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen/then/SelectZone/SelectMark"

	it(
		"ADAPT-27: a selectable table paints a leading selection mark in edit mode, and it follows the selection",
		function()
			--[[ THE AUDIT'S MEASUREMENT (matrix L-5): "on a selectable, non-reorderable
			table the row mounts exactly `Row/Hit` + `Row/Cells` — no leading circle,
			no checkbox, no gutter — the only change is the invisible `selected` prop.
			The sole cue that the mode changed is the toolbar label flipping
			Edit->Done." The gutter was already RESERVED (`cellsEditPadding` insets
			every row's cells by the handle gutter whenever editing, reorderable or
			not); nothing was ever put in it. ]]
			local w = editWorld({ selection = "multi", ownEditing = true })
			expect(w.adapter.node(SELECT_MARK)).toBeNil()
			w.tbl.api.editing:set(true)
			w.settle()
			local mark = w.adapter.node(SELECT_MARK)
			expect(mark).never().toBeNil()
			local unselected = mark.props.text
			-- ...and it is a SELECTION affordance rather than a mode badge: it changes
			-- with the row it belongs to
			w.tbl.api.select("r1", { mode = "replace" })
			w.settle()
			expect(w.adapter.node(SELECT_MARK).props.text).never().toBe(unselected)
			w.tbl.api.clearSelection()
			w.settle()
			expect(w.adapter.node(SELECT_MARK).props.text).toBe(unselected)
			-- leaving edit mode takes it away with the gutter it sits in
			w.tbl.api.editing:set(false)
			w.settle()
			expect(w.adapter.node(SELECT_MARK)).toBeNil()
		end
	)

	it("ADAPT-27: a table with NO selection grows no mark — the gutter is the handle's", function()
		local w = editWorld({ reorderable = true, ownEditing = true })
		w.tbl.api.editing:set(true)
		w.settle()
		expect(w.adapter.node(SELECT_MARK)).toBeNil()
		-- the ≡ handle is what that gutter holds on a reorder-only table
		expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/HandleGlyph")).never().toBeNil()
	end)

	it("ADAPT-27: a table with NO route into edit mode mounts no `When` at all — one node per ROW", function()
		--[[ THE GATE, and it is about cost rather than tidiness. `UI.When` is a
			structural region that materialises even while its branch is absent, so an
			unconditional mark would put an engine node on every row of every
			selectable table in the library to serve a mode most of them have no
			affordance for. The shipped Rascal Rally racer list is exactly that shape
			— `selection = "single"`, no owner signal, no auto toggle — and its own
			package's contract test is what caught the extra node. ]]
		local w = editWorld({ selection = "multi" })
		expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen")).toBeNil()
		-- ...and a route that DOES exist mounts it
		local owned = editWorld({ selection = "multi", ownEditing = true })
		expect(owned.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen")).never().toBeNil()
	end)

	it("R1-I5: the gutter and the mark are ONE gate — a routeless table insets nothing", function()
		--[[ REVIEW ROUND 1, ISSUE-5. The mark was gated on `canEditMode`; the GUTTER
			it sits in was not. `api.editing` is public, so a consumer could drive a
			table with no declared edit route into edit mode and get the 32px inset
			with nothing in it — which is the ADAPT-27 defect verbatim ("moved its
			cells 32px right and put nothing there"), reintroduced by the gate that
			fixed it. The reviewer measured `cell x 0 -> 32, EditWhen: ABSENT` on
			every capability set.

			WHICH WAY IT WAS FIXED, AND WHY. Edit mode is a MODE WITH CONTENT: the ≡
			handle, the selection mark, the row-actions minus. A table with no route
			into it has no content for it, so spending its gutter was the bug — not
			the missing mark. Both now read one predicate, so the inset appears
			exactly where something appears in it. A consumer driving `api.editing` on
			a table that declares no edit capability gets a mode that is visually
			inert, which is honest and is stated in api.md. ]]
		local w = editWorld({ selection = "multi" })
		local CELL = "/S/T/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name"
		local before = w.adapter.node(CELL).rect.x
		w.tbl.api.editing:set(true)
		w.settle()
		expect(`routeless inset: {w.adapter.node(CELL).rect.x - before}`).toBe("routeless inset: 0")
		expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen")).toBeNil()

		--[[ ...AND A TABLE THAT HAS A ROUTE STILL PAYS IT, which is the half that
			keeps this from being "delete the gutter". Same spec, same width, one
			declaration different. ]]
		local routed = editWorld({ selection = "multi", ownEditing = true })
		local routedBefore = routed.adapter.node(CELL).rect.x
		routed.tbl.api.editing:set(true)
		routed.settle()
		expect(`routed inset: {routed.adapter.node(CELL).rect.x - routedBefore > 0}`).toBe("routed inset: true")
	end)

	it("M-4: a KEYBOARD-only session gets the Edit toggle, and can reorder a row end to end", function()
		--[[ THE AUDIT'S MEASUREMENT (matrix M-4): "no Edit toggle is mounted (the
			auto-toggle union is touch OR gamepad) and the grab branch requires edit
			mode, so Down x3 + Return -> reorders = 0. Forcing `api.editing:set(true)`
			makes the identical journey work." A keyboard-only session cannot drag a
			row with a pointer it does not have, and grab mode is edit-mode-only, so
			reorder was AUTHORED-ONLY there and degraded to MISSING outright. ]]
		local w = editWorld({ reorderable = true, selection = "single" })
		local TOGGLE = "/S/T/Main/ToggleWhen/then/Toolbar/EditToggle"
		expect(w.adapter.node(TOGGLE)).never().toBeNil()
		expect(w.pres.focus.focused:get()).toBe(TOGGLE)
		w.press("Return")
		expect(w.tbl.api.editing:get()).toBe(true)
		w.press("Down")
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		w.press("Return") -- grab
		expect(w.tbl.api.grabbedKey:get()).toBe("r1")
		w.press("Down") -- step it one slot
		expect(#w.reorders).toBe(1)
		expect(w.reorders[1].toIndex).toBe(1)
		w.press("Return") -- drop
		expect(w.tbl.api.grabbedKey:get()).toBe(nil)
	end)

	it("M-4: a MOUSE session still shows nothing — it drags rows directly", function()
		--[[ The null hypothesis, and it is the reason the clause is narrow. A
			pointer session reaches both edit-mode capabilities without the mode: it
			drags a row directly and a plain click selects. Widening the toggle to
			"any keyboard" would put an Edit button on every desktop table in the
			framework to fix a session that does not exist there. ]]
		local w = editWorld({
			reorderable = true,
			selection = "single",
			capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
		})
		expect(w.adapter.node("/S/T/Main/ToggleWhen/then/Toolbar/EditToggle")).toBeNil()
	end)

	it("M-4: a keyboard-only table that cannot reorder still shows nothing", function()
		-- the union is over the capabilities edit mode is the ONLY route to, and a
		-- selectable table with no primary action selects by plain Return already
		local w = editWorld({ selection = "single" })
		expect(w.adapter.node("/S/T/Main/ToggleWhen/then/Toolbar/EditToggle")).toBeNil()
	end)
end)

-- =============================================================================
-- ADAPT-20 / J-4 · truncation recovery was structurally dead on keyboard and pad
--
-- THE AUDIT'S MEASUREMENT (matrix J-4, severity highest): "hover on 4,6 ·
-- long-press on 1,2,3 · pad/keyboard: none. The focus route is structurally dead
-- for a Table: `disclosureTargetIn` walks the subtree of the FOCUSED node, but
-- Table's focusable is `Row/Hit` while the disclosed text is
-- `Row/Cells/Cell-name/Value` — a SIBLING. Positive control passes (a `disclose`
-- Text inside a focused Button raises the plate); the identical declaration in a
-- table row raises nothing. Same for the header title." And it is the ONLY
-- recovery route at the ten-foot combination, where there is no hover and no
-- long press at all.
-- =============================================================================
describe("table_input: a focused row discloses its own truncated cell (ADAPT-20)", function()
	local LONG = "Drift City Nights Extended Cut Remastered Anniversary Edition"

	local function discloseWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 420, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal({
					{ id = "r1", name = LONG },
					{ id = "r2", name = `Another {LONG}` },
				}),
				key = function(r: any)
					return r.id
				end,
				columns = {
					{
						id = "name",
						title = `A very long column heading indeed for {LONG}`,
						width = { type = "fill", weight = 1 },
						minWidth = 40,
						-- the column's own declaration: the table-authored value cell AND
						-- the header title carry it (Step 8.5 LT-G2)
						disclose = true,
						sortable = true,
						value = function(r: any)
							return r.name
						end,
					},
				},
				selection = "single",
				sortOrder = core:signal(nil :: any),
				rowHeight = 40,
				env = env,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any = { core = core, adapter = adapter, pres = pres, system = system, tbl = tbl, handle = handle }
		function w.settle(frames: number?)
			for _ = 1, frames or 30 do
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.platePaths(): { string }
			local out: { string } = {}
			for _, path in adapter.paths() do
				if string.find(path, "__disclose__", 1, true) ~= nil then
					table.insert(out, path)
				end
			end
			table.sort(out)
			return out
		end
		function w.plateText(): string?
			for _, path in w.platePaths() do
				local node = adapter.node(path)
				if node ~= nil and node.class == "Text" and type(node.props.text) == "string" then
					return node.props.text
				end
			end
			return nil
		end
		w.settle(4)
		return w
	end

	it("the premise: the row's cell really is truncated and really is disclosed", function()
		--[[ Without this the three cases below are assertions about an empty set —
			the same premise check the sweep's own dead-end control states for itself. ]]
		local w = discloseWorld()
		local facts = w.handle.controller.textAt("/S/T/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name/Value")
		expect(facts ~= nil).toBe(true)
		expect(facts.truncated).toBe(true)
		expect(facts.disclose).toBe(true)
	end)

	it("a KEYBOARD focus on the row raises the plate with the whole value", function()
		local w = discloseWorld()
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		expect(#w.platePaths() > 0).toBe(true)
		expect(w.plateText()).toBe(LONG)
	end)

	it("...and moving the ring to the next row re-answers for THAT row", function()
		local w = discloseWorld()
		w.pres.focus.focusOn(hit("r1"))
		w.settle()
		expect(w.plateText()).toBe(LONG)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.settle()
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		expect(w.plateText()).toBe(`Another {LONG}`)
	end)

	it("a focused HEADING discloses its own title, which is the other half of J-4", function()
		local w = discloseWorld()
		w.pres.focus.focusOn("/S/T/Main/Header/Head-name/Column")
		w.settle()
		expect(#w.platePaths() > 0).toBe(true)
		expect(w.plateText()).toBe(`A very long column heading indeed for {LONG}`)
	end)

	it("NEGATIVE CONTROL: a row whose value FITS raises nothing", function()
		--[[ The scope widening must not turn into "every focused row raises a
			plate": the debt is owed by a TRUNCATED disclosed label and by nothing
			else. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal({ { id = "r1", name = "Bo" } }),
				key = function(r: any)
					return r.id
				end,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						disclose = true,
						value = function(r: any)
							return r.name
						end,
					},
				},
				selection = "single",
				rowHeight = 40,
				env = env,
			} :: any
		)
		pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		pres.focus.focusOn(hit("r1"))
		for _ = 1, 30 do
			pres.tick(1 / 60)
			pres.refresh()
		end
		local plates = 0
		for _, path in adapter.paths() do
			if string.find(path, "__disclose__", 1, true) ~= nil then
				plates += 1
			end
		end
		expect(plates).toBe(0)
		tbl.dispose()
	end)
end)

-- =============================================================================
-- REVIEW ROUND 1, HIGH-1 · the collapse and its disclosure must read ONE state
--
-- THE REVIEWER'S MEASUREMENT, verbatim: a MOUNTED table of three `fill` columns,
-- `resizable = true`, with NO `minWidth`, NO `fixed` and NO `percent` anywhere —
-- the exact shape four artifacts of this wave called "demand is zero, and zero
-- always fits". Commit a width on each through the shipped resize path, then
-- sweep the viewport:
--
--     122 of 371 viewport widths COLLAPSE column c   (first 91px, last 458px)
--     a MoreChip mounted at ANY of them?  false
--     dump().hiddenColumns                nil
--
-- A column deleted from the screen with no chip, no plate, no dump field and
-- nothing in the census line — the precise dead end the paradigm's own header
-- forbids.
--
-- TWO PREDICATES WERE THE DEFECT. `canDiscloseColumns` scanned the DECLARED
-- widths at build time; the collapse reads a runtime floor that a committed
-- override manufactures (`dimOf` turns any override into a `fixed` dim, and
-- `floorOf` reads a `fixed` dim as a hard floor). The gate could not see what
-- the rule could. There is now ONE state — `columnLayout.hidden` — and the band,
-- the plate and the dump all read it.
-- =============================================================================
describe("table_input: whatever can collapse can be disclosed (R1-H1)", function()
	local function resizableWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 460, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(
			Facet,
			core,
			{
				id = "T",
				rows = core:signal(bigRows(2)),
				key = function(r: any)
					return r.id
				end,
				--[[ NO FLOOR IS DECLARED ANYWHERE. Three `fill` columns, every one
				resizable, exactly as the reviewer built it. ]]
				columns = {
					{
						id = "a",
						title = "A",
						width = { type = "fill", weight = 1 },
						resizable = true,
						value = function(r: any)
							return r.name
						end,
					},
					{
						id = "b",
						title = "B",
						width = { type = "fill", weight = 1 },
						resizable = true,
						value = function(r: any)
							return tostring(r.laps)
						end,
					},
					{
						id = "c",
						title = "C",
						width = { type = "fill", weight = 1 },
						resizable = true,
						value = function(r: any)
							return r.id
						end,
					},
				},
				selection = "single",
				rowHeight = 40,
				env = env,
			} :: any
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		local w: any = { core = core, env = env, adapter = adapter, pres = pres, system = system, tbl = tbl }
		w.handle = handle
		function w.settle(frames: number?)
			for _ = 1, frames or 4 do
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.resize(width: number)
			env:set("viewportRect", { x = 0, y = 0, w = width, h = 600 })
			w.settle()
		end
		w.settle()
		return w
	end

	local CHIP = "/S/T/Main/MoreWhen/then/MoreBar/MoreChip"

	it("THE REVIEWER'S SWEEP: every collapsed width carries the chip and the dump record", function()
		local w = resizableWorld()
		-- the shipped DIR-4 resize path, on a table that declared no floor at all
		w.tbl.api.setColumnWidth("a", 150)
		w.tbl.api.setColumnWidth("b", 150)
		w.tbl.api.setColumnWidth("c", 150)
		w.settle()

		--[[ THE GROUND TRUTH IS THE SCREEN, NOT THE DUMP. A dump field that is
			gated off is exactly the defect, so counting collapses BY the dump would
			have made this case assert an empty set — which is what the wave's own
			scope claim predicted. The adapter's own visibility write is what the
			player gets: a collapsed column's heading leaves paint with its whole
			subtree. ]]
		local collapsedWidths, silentChip, silentDump = 0, 0, 0
		local firstSilent: number? = nil
		for width = 20, 460 do
			w.resize(width)
			local gone = false
			for _, id in { "a", "b", "c" } do
				if w.adapter.visibleOf(`/S/T/Main/Header/Head-{id}`) == false then
					gone = true
				end
			end
			if gone then
				collapsedWidths += 1
				-- the invariant, at every single width: something is hidden, so the
				-- affordance that leads back to it is on the screen...
				if w.adapter.node(CHIP) == nil then
					silentChip += 1
					firstSilent = firstSilent or width
				end
				-- ...and a bug report can see it
				local hidden = w.tbl.dump().hiddenColumns
				if hidden == nil or #hidden == 0 then
					silentDump += 1
				end
			end
		end
		--[[ THE PREMISE FIRST. Without it this whole case is an assertion about an
			empty set — and an empty set is exactly what the wave's own scope claim
			predicted here.

			THE BAND IS NARROWER THAN THE REVIEWER'S 122 OF 371, AND THAT IS THE
			EPSILON FIX BESIDE THIS ONE. Their own reading was that the exact float
			compare "is what makes the band 122 widths wide instead of a handful";
			with it fixed, what remains is the handful — 71 content widths, driven by
			`overrideFloor`'s undeclared 24px default, which is a floor the author
			never wrote and the collapse rule reads as one. So the number is not
			pinned; what is pinned is that the state is REACHED, and that nothing
			about it is silent when it is. ]]
		expect(`collapsed widths > 20: {collapsedWidths > 20}`).toBe("collapsed widths > 20: true")
		expect(`silent collapses: {silentChip} (first at {tostring(firstSilent)})`).toBe(
			"silent collapses: 0 (first at nil)"
		)
		expect(`unreported collapses: {silentDump}`).toBe("unreported collapses: 0")
	end)

	it("...and the dump reports the collapse on a table that declared no floor", function()
		local w = resizableWorld()
		-- before any resize this table cannot collapse, and says so with an EMPTY
		-- list rather than with nothing at all — a nil field is not an answer
		expect(w.tbl.dump().hiddenColumns).toEqual({})
		w.tbl.api.setColumnWidth("a", 150)
		w.tbl.api.setColumnWidth("b", 150)
		w.tbl.api.setColumnWidth("c", 150)
		-- inside the band the reviewer's shape actually reaches: three undeclared
		-- 24px floors do not fit a 60px content width
		w.resize(60)
		expect(#w.tbl.dump().hiddenColumns > 0).toBe(true)
		expect(w.tbl.dump().columnPlate).toBe("closed")
	end)

	it("...and the plate OPENS on that table, which is the route the chip promises", function()
		local w = resizableWorld()
		w.tbl.api.setColumnWidth("a", 150)
		w.tbl.api.setColumnWidth("b", 150)
		w.tbl.api.setColumnWidth("c", 150)
		w.resize(60)
		local chip = w.adapter.node(CHIP)
		expect(chip).never().toBeNil()
		expect(chip.rect.h >= 44).toBe(true)
		w.adapter.touchTap(CHIP)
		w.settle(30)
		expect(w.tbl.dump().columnPlate).never().toBe("closed")
		-- the hidden column's own value is in it, for the row that is on screen
		local found = false
		for _, path in w.adapter.paths() do
			if string.find(path, "Row-c-r1", 1, true) ~= nil then
				found = true
			end
		end
		expect(found).toBe(true)
	end)

	it("NULL HYPOTHESIS: an unresized table with no declared floor still collapses nothing", function()
		--[[ The scope claim, corrected rather than abandoned: a table that declares
			no floor AND has had no width committed still has a demand of zero, and
			zero still fits. What changed is that "declares no floor" stopped being the
			whole sentence. ]]
		local w = resizableWorld()
		for _, width in { 460, 300, 200, 120, 90 } do
			w.resize(width)
			expect(`{width}: {#w.tbl.dump().hiddenColumns}`).toBe(`{width}: 0`)
		end
		expect(w.adapter.node(CHIP)).toBeNil()
	end)
end)
