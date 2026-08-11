--!strict
-- Table control Phase A tests (ADR-0007): column alignment via shared dims,
-- variable row heights, headerless mode, selection single/multi through the
-- activate path + keyboard focus, custom cells with live nested controls,
-- the resize MODEL (setColumnWidth), dump determinism, churn neutrality.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local LuauUI = require("../src")
local table_control = require("../src/controls/table")
local snapshot = require("../src/themes/snapshot")
local fake_target = require("../tests/lib/fake_target")

local RACERS = {
	{ id = "razz", name = "Razz Raccoon", laps = 3 },
	{ id = "bolt", name = "Bunny Bolt", laps = 3 },
	{ id = "josh", name = "Josh", laps = 2 },
}

local function hasColumnCells(columns: { any }): boolean
	for _, column in columns do
		if column.cell ~= nil or column.value ~= nil then
			return true
		end
	end
	return false
end

local function world(spec: any)
	local core = spec.core or LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	-- Task 10: `spec.now` is an OPTIONAL scripted clock (row_actions_input.
	-- spec.luau's own `pointerWorld` pattern) — every existing caller omits
	-- it and gets the unchanged default (`presenterOpts.now or os.clock`,
	-- presenter.luau). A row-actions gesture test needs one: without it,
	-- `nowFn` is REAL wall-clock time, and `drag_velocity`'s tracker divides
	-- a real position delta by a near-zero REAL-time delta between two
	-- synchronous pushes — an explosive, nondeterministic "velocity" that
	-- seeds the release spring with garbage (a live-found repro building
	-- this task: a huge bogus overshoot before decaying back to whatever it
	-- decayed to). Reorder's own drag math never reads velocity at all,
	-- which is why no table.spec.luau test needed this before row_actions
	-- rode the same harness.
	local pres = LuauUI.newPresenter(core, env, adapter, system, if spec.now then { now = spec.now } else nil)
	local rows = core:signal(spec.rowsOverride or RACERS)
	local tbl = table_control.build(LuauUI, core, {
		id = "Racers",
		columns = spec.columns or {
			{ id = "name", title = "Racer", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
			{ id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
		},
		rows = rows,
		key = function(item)
			return item.id
		end,
		cellFor = if spec.cellFor ~= nil
				or spec.noCellFor
				or (spec.columns and hasColumnCells(spec.columns))
			then spec.cellFor
			else function(columnId, item)
				return LuauUI.UI.Text({
					id = "Value",
					text = if columnId == "name" then item.name else tostring(item.laps),
					textSize = 16,
				})
			end,
		rowHeight = spec.rowHeight or 40,
		header = spec.header,
		selection = spec.selection or "single",
		rowGap = spec.rowGap,
		sortOrder = spec.sortOrder,
		reorderable = spec.reorderable,
		onReorder = spec.onReorder,
		dragLabel = spec.dragLabel,
		editing = spec.editing,
		rowActions = spec.rowActions,
		-- AN ENV BY DEFAULT (director round 12, 2026-07-27). The auto Edit/Done
		-- toggle is a TOUCH affordance — "mouse users scroll with the wheel and
		-- drag directly, so they never need edit mode" — but a table with NO env
		-- cannot know the input class, so it shows the toggle unconditionally.
		-- These specs drive mouse drags at hard-coded coordinates, so they were
		-- silently exercising a configuration that does not exist on a real
		-- pointer device, and the toolbar row the toggle now occupies moved every
		-- one of those coordinates. Passing the env makes them what they claim to
		-- be: pointer tests, on a pointer. `passEnv = false` opts back out.
		env = if spec.passEnv == false then nil else env,
		height = spec.height,
	})
	local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
	local handle = pres.present(screen, {
		-- this legacy harness drives the table's FLAT-ring story (grip in the
		-- ring, wrap-around, shift+Navigate reorder); it opts out of the
		-- ADR-0013 auto-grouping the Table contribution now advertises so its
		-- flat-ring assertions stay unchanged (grouped nav omits the header grip
		-- and routes reorder through grab mode instead of shift+Navigate).
		navigationGroups = false,
		onActivate = function(path, meta)
			tbl.api.handleActivate(path, meta)
		end,
		onAdjust = function(path, dir, rectOf)
			tbl.api.handleAdjust(path, dir, rectOf)
		end,
		onReorderNav = function(path, dir)
			return tbl.api.handleReorderNav(path, dir)
		end,
		onFocusNav = function(path)
			tbl.api.handleFocusMoved(path)
		end,
	})
	pres.refresh()
	return core, adapter, pres, tbl, rows, handle, system, env
end

-- Phase B: the table root is an Anchor (overlay host for resize/drop guides)
-- with the content under /Main — paths carry that segment
local function rowHitPath(version: number, key: string): string
	return `/S/Racers/Main/Body/Rows/[{key}@{version}]/Row/Hit`
end
local function cellPath(version: number, key: string, columnId: string): string
	return `/S/Racers/Main/Body/Rows/[{key}@{version}]/Row/Cells/Cell-{columnId}`
end

describe("Table: layout", function()
	it("columns align across header and every row (fill + fixed)", function()
		local _, adapter, _, tbl = world({})
		local headerName = adapter.node("/S/Racers/Main/Header/Head-name").rect
		local headerLaps = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		expect(headerLaps.w).toBe(64)
		for _, racer in RACERS do
			local nameCell = adapter.node(cellPath(0, racer.id, "name")).rect
			local lapsCell = adapter.node(cellPath(0, racer.id, "laps")).rect
			expect(nameCell.x).toBe(headerName.x)
			expect(nameCell.w).toBe(headerName.w)
			expect(lapsCell.x).toBe(headerLaps.x)
			expect(lapsCell.w).toBe(64)
		end
	end)

	it("variable row heights position rows correctly", function()
		local _, adapter = world({
			rowHeight = function(item)
				return if item.id == "josh" then 72 else 40
			end,
			header = false,
		})
		local razz = adapter.node(rowHitPath(0, "razz")).rect
		local bolt = adapter.node(rowHitPath(0, "bolt")).rect
		local josh = adapter.node(rowHitPath(0, "josh")).rect
		expect(razz.h).toBe(40)
		expect(josh.h).toBe(72)
		expect(bolt.y).toBe(razz.y + 40)
		expect(josh.y).toBe(bolt.y + 40)
	end)

	it("headerless mode renders no header row (the racer-list shape)", function()
		local _, adapter = world({ header = false })
		expect(adapter.node("/S/Racers/Main/Header")).toBe(nil)
		expect(adapter.node(rowHitPath(0, "razz")) ~= nil).toBe(true)
	end)
end)

describe("Table: selection", function()
	it("single: activate selects exactly one; selection survives without remount", function()
		local _, adapter, pres, tbl, _, handle, system = world({ selection = "single" })
		local runsBefore = handle.root.counters().factoryRuns
		adapter.tap(rowHitPath(0, "bolt"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(adapter.node(rowHitPath(0, "bolt")).props.selected).toBe(true)
		adapter.tap(rowHitPath(0, "josh"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(nil) -- single: replaced
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		expect(adapter.node(rowHitPath(0, "bolt")).props.selected).toBe(false)
		expect(handle.root.counters().factoryRuns).toBe(runsBefore) -- state-driven
	end)

	it("multi: activates toggle additively (tap idiom)", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"))
		adapter.tap(rowHitPath(0, "josh"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		adapter.tap(rowHitPath(0, "razz")) -- toggle off
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("keyboard: focus walks row hits and Activate selects", function()
		local _, _, pres, tbl, _, _, system = world({ selection = "single" })
		-- THE COLUMN HANDLE LEADS (director 2026-07-29): a resizable column's header
		-- is its single focus stop, and the header precedes the rows.
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz"))
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
	end)
end)

describe("Table: custom cells and resize model", function()
	it("custom cells host live nested controls (director: results list w/ custom cell)", function()
		local core, adapter, pres, tbl = world({
			header = false,
			cellFor = function(columnId, item)
				if columnId == "name" then
					return LuauUI.UI.Toggle({ id = "Fav", label = item.name, value = false })
				end
				return LuauUI.UI.Text({ id = "Value", text = tostring(item.laps), textSize = 16 })
			end,
		})
		local favPath = cellPath(0, "razz", "name") .. "/Fav"
		expect(adapter.node(favPath) ~= nil).toBe(true)
		expect(adapter.node(favPath).props.label).toBe("Razz Raccoon")
		-- the nested control keeps its own tap handler (renders above the hit)
		expect(adapter.node(favPath).onActivate ~= nil).toBe(true)
	end)

	it("setColumnWidth commits a new width to every row and the header", function()
		local _, adapter, pres, tbl = world({})
		tbl.api.setColumnWidth("name", 200)
		pres.refresh()
		-- version bumped: rows remounted under @1 keys
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(200)
		expect(adapter.node(cellPath(1, "bolt", "name")).rect.w).toBe(200)
		expect(adapter.node(rowHitPath(0, "razz"))).toBe(nil) -- old rows gone
		-- non-resizable columns refuse
		tbl.api.setColumnWidth("laps", 200)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "laps")).rect.w).toBe(64)
	end)

	it("remounted rows keep hits painted beneath cell content (deterministic z-order)", function()
		-- the flat sibling render relies on paint order; creation order is NOT
		-- deterministic across a structural sync, so z-order must be assigned
		-- explicitly from the tree walk (live-found defect, 2026-07-19)
		local _, adapter, pres, tbl = world({})
		tbl.api.setColumnWidth("name", 200)
		pres.refresh()
		for _, key in { "razz", "bolt", "josh" } do
			local hit = adapter.node(rowHitPath(1, key))
			local value = adapter.node(cellPath(1, key, "name") .. "/Value")
			expect(hit.z ~= nil).toBe(true)
			expect(value.z ~= nil).toBe(true)
			expect(hit.z < value.z).toBe(true)
		end
	end)

	it("removed rows are pruned from the selection and anchor", function()
		local _, adapter, pres, tbl, rows = world({ selection = "multi", header = false })
		adapter.tap(rowHitPath(0, "razz"))
		adapter.tap(rowHitPath(0, "josh"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		rows:set({ RACERS[2] }) -- only bolt survives
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(nil)
	end)

	it("table ids containing Lua pattern magic still route rows and grips", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local rows = core:signal(RACERS)
		local tbl = table_control.build(LuauUI, core, {
			id = "results-list", -- '-' is pattern magic
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
				},
			},
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return LuauUI.UI.Text({ id = "Value", text = item.name, textSize = 16 })
			end,
			rowHeight = 40,
			selection = "single",
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } })
		pres.present(screen, {
			onActivate = function(path, meta)
				tbl.api.handleActivate(path, meta)
			end,
			onAdjust = function(path, dir, rectOf)
				tbl.api.handleAdjust(path, dir, rectOf)
			end,
		})
		pres.refresh()
		adapter.tap("/S/results-list/Main/Body/Rows/[razz@0]/Row/Hit")
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		tbl.dispose()
	end)

	it("row churn + dispose are registry-neutral and dumps deterministic", function()
		local core, adapter, pres, tbl, rows, handle = world({ header = false })
		local d1 = serde.encode("json", handle.root.dump(), true)
		expect(d1).toBe(serde.encode("json", handle.root.dump(), true))
		local baseline = core:counters()
		for i = 1, 10 do
			rows:set({ RACERS[1], RACERS[2], RACERS[3], { id = `extra{i}`, name = "X", laps = 0 } })
			pres.refresh()
			rows:set(RACERS)
			pres.refresh()
		end
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
	end)

	-- CTRL-08a (api-architecture-consistency F-25). Every `.dump()` in this file
	-- was `handle.root.dump()` — the MOUNT tree — so the CONTROL's own dump, the
	-- largest one in the library, was never exercised at all and its schema
	-- string appeared nowhere in the repo.
	it("the CONTROL dump is deterministic and carries its schema string", function()
		local _, adapter, pres, tbl = world({})
		expect(tbl.dump().schema).toBe("luauui-table-dump/1")
		local d1 = serde.encode("json", tbl.dump(), true)
		expect(d1).toBe(serde.encode("json", tbl.dump(), true))
		-- ...and it stays deterministic after live interaction moved the state
		adapter.tap(rowHitPath(0, "razz"))
		pres.refresh()
		local d2 = serde.encode("json", tbl.dump(), true)
		expect(d2).toBe(serde.encode("json", tbl.dump(), true))
		expect(d2 ~= d1).toBe(true)
	end)

	-- the live interaction state a bug report actually needs (playbook §2.5).
	-- VirtualList's dump carried all of its equivalents; Table's carried none.
	it("the control dump carries the live interaction state a bug report needs", function()
		local core, adapter, pres, tbl = world({ selection = "multi", editing = nil })
		local d = tbl.dump()
		expect(type(d.selectedKeys)).toBe("table")
		expect(#d.selectedKeys).toBe(0)
		expect(d.grabbedKey).toBeNil()
		expect(d.editing).toBe(false)
		expect(d.scrollTop).toBe(0)
		adapter.tap(rowHitPath(0, "razz"))
		pres.refresh()
		expect(tbl.dump().selectedKeys).toEqual({ "razz" })
		local _ = core
	end)

	-- `selectedKeys` is a SET inside the control, and a set's iteration order is
	-- not the insertion order and not stable across processes — so an unsorted
	-- array would make the largest control's dump non-deterministic the moment a
	-- second row was selected, which is exactly the promise the dump makes.
	it("the dump's selectedKeys are SORTED, so a multi-selection stays deterministic", function()
		local wide = {}
		for _, key in { "zeta", "alpha", "mango", "delta", "kilo", "bravo", "yankee", "echo" } do
			table.insert(wide, { id = key, name = key, laps = 1 })
		end
		local _, _, _, tbl = world({ selection = "multi", rowsOverride = wide })
		for _, key in { "zeta", "mango", "kilo", "bravo", "yankee", "echo", "alpha", "delta" } do
			tbl.api.select(key, { mode = "toggle" })
		end
		expect(tbl.dump().selectedKeys).toEqual({
			"alpha",
			"bravo",
			"delta",
			"echo",
			"kilo",
			"mango",
			"yankee",
			"zeta",
		})
	end)
end)

describe("Table: SwiftUI-shaped columns (director round 5)", function()
	it("per-column alignment positions cell content; vertical center is the default", function()
		local _, adapter = world({
			header = false,
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				-- numeric column, SwiftUI-style trailing alignment
				{ id = "laps", title = "Laps", width = 64, alignment = { h = "trailing" } },
			},
		})
		local lapsCell = adapter.node(cellPath(0, "razz", "laps"))
		local lapsText = adapter.node(cellPath(0, "razz", "laps") .. "/Value")
		-- trailing: content hugs the cell's right inset (cellPadding 8)
		expect(lapsText.rect.x + lapsText.rect.w).toBe(lapsCell.rect.x + lapsCell.rect.w - 8)
		-- vertical center stays the default
		local topGap = lapsText.rect.y - lapsCell.rect.y
		local bottomGap = (lapsCell.rect.y + lapsCell.rect.h) - (lapsText.rect.y + lapsText.rect.h)
		expect(math.abs(topGap - bottomGap) <= 1).toBe(true)
		-- leading (default) column content keeps the left inset
		local nameText = adapter.node(cellPath(0, "razz", "name") .. "/Value")
		expect(nameText.rect.x).toBe(adapter.node(cellPath(0, "razz", "name")).rect.x + 8)
	end)

	-- api-architecture-consistency F-27: `column.alignment` was honoured on the
	-- CELLS and ignored by the header title, so a trailing-aligned numeric column
	-- showed a left-aligned heading over right-aligned numbers — a
	-- partially-honoured property, which is worse than an unsupported one.
	it("the header title honours the column alignment, exactly like the column's cells", function()
		local _, adapter = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = 64, alignment = { h = "trailing" } },
			},
		})
		local lapsHead = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		local lapsTitle = adapter.node("/S/Racers/Main/Header/Head-laps/Title")
		-- the title's text box is inset by the same cellPadding the cells use...
		expect(lapsTitle.rect.x).toBe(lapsHead.x + 8)
		expect(lapsTitle.rect.x + lapsTitle.rect.w).toBe(lapsHead.x + lapsHead.w - 8)
		-- ...and the glyphs sit at the TRAILING edge of it, over their column
		expect(lapsTitle.props.textAlign).toBe("end")

		-- the leading default is unchanged: box and glyphs both start at the inset
		local nameHead = adapter.node("/S/Racers/Main/Header/Head-name").rect
		local nameTitle = adapter.node("/S/Racers/Main/Header/Head-name/Title")
		expect(nameTitle.rect.x).toBe(nameHead.x + 8)
		expect(nameTitle.props.textAlign).toBe("start")
	end)

	-- the sort mark lives at the trailing edge of the same header ZStack, so a
	-- trailing title is the one that can collide with it. It must not.
	it("a trailing title on a SORTABLE column clears the sort mark", function()
		local core = LuauUI.newCore()
		local sortOrder = core:signal({ column = "laps", ascending = true })
		local _, adapter = world({
			core = core,
			sortOrder = sortOrder,
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{
					id = "laps",
					title = "Laps",
					width = 120,
					alignment = { h = "trailing" },
					sortable = true,
				},
			},
		})
		local head = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		local title = adapter.node("/S/Racers/Main/Header/Head-laps/Title").rect
		local mark = adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").rect
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").props.text).toBe("▲")
		-- the trailing inset is the THEME's mark reserve (controls.table.
		-- sortMarkMargin = 14), not the 8px cell inset — the cell inset left the
		-- two 1px apart under Studio Neutral's 11px mark
		expect((head.x + head.w) - (title.x + title.w)).toBe(14)
		expect(title.x + title.w < mark.x).toBe(true)
		-- and a NON-sortable trailing column keeps the plain cell inset, so the
		-- reserve is paid only where there is something to clear
		local _, adapter2 = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = 120, alignment = { h = "trailing" } },
			},
		})
		local head2 = adapter2.node("/S/Racers/Main/Header/Head-laps").rect
		local title2 = adapter2.node("/S/Racers/Main/Header/Head-laps/Title").rect
		expect((head2.x + head2.w) - (title2.x + title2.w)).toBe(8)
	end)

	it("a centered column centers its header title too", function()
		local _, adapter = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = 64, alignment = { h = "center" } },
			},
		})
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/Title").props.textAlign).toBe("center")
	end)

	it("columns own their cells: `value` renders a default Text, `cell` renders custom", function()
		local _, adapter = world({
			header = false,
			cellFor = nil, -- no global fallback: columns carry their content
			columns = {
				{
					id = "name",
					width = { type = "fill", weight = 1 },
					cell = function(item)
						return LuauUI.UI.Text({ id = "Custom", text = item.name, textSize = 15 })
					end,
				},
				{
					id = "laps",
					width = 64,
					value = function(item)
						return tostring(item.laps)
					end,
				},
			},
		})
		expect(adapter.node(cellPath(0, "razz", "name") .. "/Custom").props.text).toBe("Razz Raccoon")
		expect(adapter.node(cellPath(0, "razz", "laps") .. "/Value").props.text).toBe("3")
	end)

	it("width sugar: a number is fixed px; {min, ideal, max} is a minMax band", function()
		local _, adapter = world({
			header = false,
			columns = {
				{ id = "name", width = { type = "fill", weight = 1 } },
				{ id = "laps", width = { min = 50, ideal = 80, max = 100 } },
			},
		})
		expect(adapter.node(cellPath(0, "razz", "laps")).rect.w).toBe(80)
	end)

	it("partial width sugar defaults the band's preferred ({min} alone is valid)", function()
		local _, adapter = world({
			header = false,
			columns = {
				{ id = "name", width = { type = "fill", weight = 1 } },
				{ id = "laps", width = { min = 50 } },
			},
		})
		expect(adapter.node(cellPath(0, "razz", "laps")).rect.w).toBe(50)
	end)

	it("a content-less column asserts AT BUILD, even with zero rows; ids must be path-safe", function()
		local core = LuauUI.newCore()
		local okEmpty = pcall(function()
			table_control.build(LuauUI, core, {
				id = "Bare",
				columns = { { id = "name", width = { type = "fill", weight = 1 } } },
				rows = core:signal({}),
				key = function(item)
					return item.id
				end,
				rowHeight = 40,
			})
		end)
		expect(okEmpty).toBe(false)
		local okSlash = pcall(function()
			table_control.build(LuauUI, core, {
				id = "Slashy",
				columns = {
					{
						id = "a/b",
						width = { type = "fill", weight = 1 },
						cell = function()
							return LuauUI.UI.Text({ id = "X", text = "", textSize = 12 })
						end,
					},
				},
				rows = core:signal({}),
				key = function(item)
					return item.id
				end,
				rowHeight = 40,
			})
		end)
		expect(okSlash).toBe(false)
	end)

	it("value() results are coerced to text (a raw number never reaches the Text prop)", function()
		local _, adapter = world({
			header = false,
			columns = {
				{
					id = "name",
					width = { type = "fill", weight = 1 },
					cell = function(item)
						return LuauUI.UI.Text({ id = "Custom", text = item.name, textSize = 15 })
					end,
				},
				{
					id = "laps",
					width = 64,
					value = function(item)
						return item.laps :: any -- a raw number, not a string
					end,
				},
			},
		})
		expect(adapter.node(cellPath(0, "razz", "laps") .. "/Value").props.text).toBe("3")
	end)

	it("header taps cycle the owner-held sortOrder; the table never sorts the data", function()
		local core = LuauUI.newCore()
		local sortOrder = core:signal(nil :: any)
		local _, adapter, pres, tbl, rows = world({
			core = core,
			sortOrder = sortOrder,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					-- a `cell` column WITHOUT sortable=true stays out of sorting
					cell = function(item)
						return LuauUI.UI.Text({ id = "Custom", text = item.name, textSize = 16 })
					end,
				},
				{
					id = "laps",
					title = "Laps",
					width = 64,
					value = function(item)
						return tostring(item.laps)
					end,
				},
			},
		})
		local sortHit = "/S/Racers/Main/Header/Head-laps/Column"
		expect(adapter.node(sortHit) ~= nil).toBe(true)
		local razzYBefore = adapter.node(rowHitPath(0, "razz")).rect.y
		adapter.tap(sortHit, { pointer = "mouse" })
		pres.refresh()
		expect(sortOrder:get().column).toBe("laps")
		expect(sortOrder:get().ascending).toBe(true)
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").props.text).toBe("▲")
		adapter.tap(sortHit, { pointer = "mouse" })
		pres.refresh()
		expect(sortOrder:get().ascending).toBe(false)
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").props.text).toBe("▼")
		-- SwiftUI semantics: the DATA OWNER applies the sort — rows untouched
		expect(adapter.node(rowHitPath(0, "razz")).rect.y).toBe(razzYBefore)
		-- non-sortable columns expose no sort hit
		expect(adapter.node("/S/Racers/Main/Header/Head-name/Column")).toBe(nil)
		-- INVERTED (ui_todo §0; artifacts/input-adaptation-audit/wp-b-composites.md
		-- header-sort keyboard/gamepad = MISSING): this line USED to assert the
		-- sort hit stayed OUT of the focus ring (focus == razz), encoding the
		-- pre-§0 "sort is pointer-only" design. §0 overruled that — every
		-- interactive surface needs a focus + Activate story on every input — so
		-- the sort hit is now focusable. In this legacy FLAT-ring harness
		-- (navigationGroups=false) it is the first focusable in document order
		-- (header precedes the body), so initial focus lands on it. The grouped
		-- "headers" NavigationGroup path is proven device-true in table_input.spec.
		expect(pres.focus.focused:get()).toBe(sortHit)
	end)
end)

describe("Table: row gaps (director round 4 — cards must not touch)", function()
	it("rowGap spaces the cards and the drop indicator lands mid-gap", function()
		local reorders: { any } = {}
		local _, adapter, pres = world({
			header = false,
			rowGap = 4,
			reorderable = true,
			onReorder = function(keys, toIndex)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
		})
		-- rows at 40px + 4px gaps: razz 0, bolt 44, josh 88
		expect(adapter.node(rowHitPath(0, "razz")).rect.y).toBe(0)
		expect(adapter.node(rowHitPath(0, "bolt")).rect.y).toBe(44)
		expect(adapter.node(rowHitPath(0, "josh")).rect.y).toBe(88)
		-- drag razz below bolt's midpoint (44+20=64): slot 2 full-list,
		-- indicator centered in the gap after bolt (44+40+2 = 86)
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 70)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(86)
		adapter.pointerUp(100, 70)
		expect(reorders[1].keys[1]).toBe("razz")
		expect(reorders[1].toIndex).toBe(1)
	end)
end)

describe("Table: row drag-and-drop (Phase B)", function()
	local function dragWorld()
		local reorders: { any } = {}
		local core, adapter, pres, tbl, rows, handle, system = world({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		return reorders, adapter, pres, tbl, rows, system, core
	end

	it("a drag shows ghost + indicator with the row IN PLACE; drop converts to post-removal slots", function()
		-- director 2026-07-20 round 2: do NOT remove the row while dragging
		-- (the table jump read badly) — the ghost chip + drop line carry the
		-- "picked up" read; the row stays until the drop commits
		local reorders, adapter, pres, _, _, _, core = dragWorld()
		local baseline = core:counters()
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 24) -- below the drag threshold
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
		adapter.pointerMove(100, 90)
		pres.refresh()
		-- the origin row STAYS in the flow
		expect(adapter.node(razzPath) ~= nil).toBe(true)
		expect(adapter.node(rowHitPath(0, "bolt")).rect.y).toBe(40)
		-- ghost + indicator present; y=90 sits past razz(20) and bolt(60) mids
		-- single-row drag: exactly one chip, label on the front chip
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1/Label").props.text).toBe("Razz Raccoon")
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip2")).toBe(nil)
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(80)
		adapter.pointerUp(100, 90)
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
		-- full-list slot 2 converts to post-removal slot 1 (bolt, razz, josh)
		expect(reorders[1].toIndex).toBe(1)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
		pres.refresh()
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
	end)

	it("dragging a selected row drags the WHOLE selection as a block (director example)", function()
		-- rows r1..r5; select r1, r3, r5; drag on r3; drop after current r2
		-- -> onReorder({r1, r3, r5}, 1): remaining 2,4 with the block after 2
		-- -> consumer order 2,1,3,5,4
		local reorders: { any } = {}
		local five = {
			{ id = "r1", name = "One", laps = 1 },
			{ id = "r2", name = "Two", laps = 2 },
			{ id = "r3", name = "Three", laps = 3 },
			{ id = "r4", name = "Four", laps = 4 },
			{ id = "r5", name = "Five", laps = 5 },
		}
		local _, adapter, pres, tbl = world({
			header = false,
			selection = "multi",
			rowsOverride = five,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local function hit(key: string): string
			return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
		end
		adapter.tap(hit("r1"), { pointer = "mouse" })
		adapter.tap(hit("r3"), { pointer = "mouse", toggle = true })
		adapter.tap(hit("r5"), { pointer = "mouse", toggle = true })
		pres.refresh()
		-- drag on r3 (selected): the whole selection lifts together
		adapter.pointerDown(hit("r3"), 100, 100) -- r3 spans 80..120
		adapter.pointerMove(100, 70) -- between r2's mid (60) and r3's (100)
		pres.refresh()
		-- ghost shows a chip STACK: up to 3 chips offset (0,0)/(2,2)/(4,4),
		-- front chip carries the label (no "+N" text)
		local chip1 = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1")
		local chip2 = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip2")
		local chip3 = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip3")
		expect(chip1 ~= nil and chip2 ~= nil and chip3 ~= nil).toBe(true)
		-- chips carry the outlined "chip" surface so the stack reads cleanly
		expect(chip1.props.surface).toBe("chip")
		expect(chip3.props.surface).toBe("chip")
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1/Label").props.text).toBe("Three")
		expect(chip2.rect.x).toBe(chip1.rect.x + 2)
		expect(chip2.rect.y).toBe(chip1.rect.y + 2)
		expect(chip3.rect.x).toBe(chip1.rect.x + 4)
		expect(chip3.rect.y).toBe(chip1.rect.y + 4)
		-- the FRONT chip paints on top (deterministic z: later walk = higher z)
		expect(chip1.z > chip2.z and chip2.z > chip3.z).toBe(true)
		adapter.pointerUp(100, 70)
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(3)
		expect(reorders[1].keys[1]).toBe("r1") -- document order, not click order
		expect(reorders[1].keys[2]).toBe("r3")
		expect(reorders[1].keys[3]).toBe("r5")
		expect(reorders[1].toIndex).toBe(1) -- one remaining row (r2) above
	end)

	it("a five-row group still shows at most three chips", function()
		local reorders: { any } = {}
		local five = {
			{ id = "r1", name = "One", laps = 1 },
			{ id = "r2", name = "Two", laps = 2 },
			{ id = "r3", name = "Three", laps = 3 },
			{ id = "r4", name = "Four", laps = 4 },
			{ id = "r5", name = "Five", laps = 5 },
		}
		local _, adapter, pres, tbl = world({
			header = false,
			selection = "multi",
			rowsOverride = five,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local function hit(key: string): string
			return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
		end
		for _, key in { "r1", "r2", "r3", "r4", "r5" } do
			adapter.tap(hit(key), { pointer = "mouse", toggle = true })
		end
		pres.refresh()
		adapter.pointerDown(hit("r3"), 100, 100)
		adapter.pointerMove(100, 130)
		pres.refresh()
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip3") ~= nil).toBe(true)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip4")).toBe(nil)
		adapter.pointerUp(900, 130) -- off-table: abort
	end)

	it("dragging an UNSELECTED row drags only that row", function()
		local reorders, adapter, pres, tbl = dragWorld()
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse" }) -- select josh
		pres.refresh()
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20) -- drag razz (unselected)
		adapter.pointerMove(100, 90)
		pres.refresh()
		adapter.pointerUp(100, 90)
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
		expect(tbl.api.selectedKeys:get().josh).toBe(true) -- selection untouched
	end)

	it("a group drop that reproduces the current order commits nothing", function()
		local reorders, adapter, pres, tbl = dragWorld()
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse" })
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse", toggle = true })
		pres.refresh()
		-- dragging the razz+bolt block to the very top is a no-op
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 10)
		pres.refresh()
		adapter.pointerUp(100, 10)
		pres.refresh()
		expect(#reorders).toBe(0)
	end)

	it("dropping a row back onto itself commits nothing", function()
		local reorders, adapter, pres = dragWorld()
		adapter.pointerDown(rowHitPath(0, "bolt"), 100, 60)
		adapter.pointerMove(100, 70) -- past the threshold, still within bolt
		pres.refresh()
		adapter.pointerUp(100, 70)
		pres.refresh()
		expect(#reorders).toBe(0)
	end)

	it("a system interrupt (Roblox menu opened) aborts the drag cleanly", function()
		-- director 2026-07-20: Esc opens the CoreGui menu mid-drag and the
		-- drag state got stuck. Escape is engine-reserved (D1) so it cannot
		-- be intercepted — instead ANY pointer capture aborts when the menu
		-- opens (adapter-level, all draggables)
		local reorders, adapter, pres, tbl = dragWorld()
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true)
		adapter.interruptCapture() -- the menu opened
		pres.refresh()
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
		expect(#reorders).toBe(0)
		-- and the table is fully usable afterwards
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse" })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
	end)

	it("an invalid drop (outside the table) commits nothing", function()
		local reorders, adapter, pres = dragWorld()
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		expect(adapter.node(razzPath) ~= nil).toBe(true) -- row stays put
		adapter.pointerUp(900, 90) -- released outside the table root
		pres.refresh()
		expect(#reorders).toBe(0)
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
	end)

	it("one-step downward drag reports the post-removal insertion slot", function()
		-- full-list mids: razz 20, bolt 60, josh 100; y=115 -> full slot 3 ->
		-- dragged bolt (0-based 1) sits above it -> post-removal slot 2
		local reorders, adapter, pres = dragWorld()
		adapter.pointerDown(rowHitPath(0, "bolt"), 100, 60)
		adapter.pointerMove(100, 115)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(120)
		adapter.pointerUp(100, 115)
		expect(reorders[1].keys[1]).toBe("bolt")
		expect(reorders[1].toIndex).toBe(2)
	end)

	it("keyboard: shift+Navigate moves the focused row without moving focus", function()
		local reorders, adapter, pres, tbl, rows, system = dragWorld()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz"))
		system.deviceKey("LeftShift", true)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		system.deviceKey("LeftShift", false)
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
		expect(reorders[1].toIndex).toBe(1) -- down one: post-removal slot = i
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz"))
		-- plain Navigate still walks focus
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
	end)

	it("an impossible shift+Navigate reorder moves NOTHING — not the row, not focus", function()
		-- verifier 2026-07-20 F1: shift+Up on the top row used to fall through
		-- the failed reorder into navigate(), which now WRAPS — teleporting
		-- focus to the bottom. Shift+arrow means "move the row", never focus.
		local reorders, adapter, pres, tbl, rows, system = dragWorld()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz")) -- top row
		system.deviceKey("LeftShift", true)
		system.deviceKey("Up", true)
		system.deviceKey("Up", false)
		system.deviceKey("LeftShift", false)
		expect(#reorders).toBe(0)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz")) -- unmoved
	end)

	it("dismissing the screen mid-drag tears the capture down", function()
		-- verifier 2026-07-20 F4: destroyRoot must always end the capture
		local reorders: { any } = {}
		local core, adapter, pres, tbl, rows, handle = world({
			header = false,
			reorderable = true,
			onReorder = function(key: string, toIndex: number)
				table.insert(reorders, { key = key, toIndex = toIndex })
			end,
		})
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		pres.dismiss(handle) -- destroys the root mid-drag
		adapter.pointerUp(100, 90) -- must route nowhere
		expect(#reorders).toBe(0)
	end)

	it("non-reorderable tables ignore row drags entirely", function()
		local _, adapter, pres, tbl = world({ header = false })
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
	end)
end)

describe("Table: Apple-model focus and selection (director round 2)", function()
	it("clicking a row moves keyboard focus there", function()
		local _, adapter, pres, tbl = world({ selection = "single" })
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse" })
		pres.refresh()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
		-- navigation continues from the clicked row
		local _, _, _, _, _, _, system = nil, nil, nil, nil, nil, nil, nil
	end)

	it("arrow navigation moves the SELECTION with focus (Apple table model)", function()
		local _, adapter, pres, tbl, _, _, system = world({ selection = "single" })
		system.deviceKey("Down", true) -- off the column handle onto razz
		system.deviceKey("Down", false)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
		expect(tbl.api.selectedKeys:get().bolt).toBe(true) -- selection followed
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(nil) -- replaced
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("arrow-selection anchors the range: arrow to a later row, shift-click an earlier one", function()
		local _, adapter, pres, tbl, _, _, system = world({ selection = "multi" })
		system.deviceKey("Down", true) -- off the column handle onto razz
		system.deviceKey("Down", false)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false) -- josh selected + anchored by arrows
		pres.refresh()
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse", shift = true })
		pres.refresh()
		-- reverse range: prior row up to the anchor
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("shift-clicking from a later row to a prior one range-selects (reversed)", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse" }) -- anchor = josh
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse", shift = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)
end)

describe("Table: modifier selection semantics (Phase B)", function()
	it("plain mouse click replaces a multi selection", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"))
		adapter.tap(rowHitPath(0, "bolt"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse" })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().bolt).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("ctrl/cmd-click toggles rows in and out of a multi selection", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse" })
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse", toggle = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse", toggle = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("shift-click extends a contiguous range from the anchor", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse" }) -- anchor
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse", shift = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true) -- between anchor and target
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		-- a new shift-click re-ranges from the SAME anchor
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse", shift = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(nil)
	end)

	it("keyboard Activate honors held modifiers from the action system", function()
		-- Apple model: arrows already REPLACE the selection as focus moves
		-- (anchor follows), so keyboard ranges collapse to the focused row —
		-- range extension is pointer territory (shift+arrows = reorder).
		-- The seam to pin: held modifiers reach handleActivate for Return.
		local _, _, pres, tbl, _, _, system = world({ selection = "multi" })
		system.deviceKey("Down", true) -- off the column handle onto razz
		system.deviceKey("Down", false)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false) -- plain: replace-select razz
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		system.deviceKey("LeftControl", true)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false) -- ctrl: toggle razz back off
		system.deviceKey("LeftControl", false)
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
	end)

	it("touch taps keep the additive-toggle idiom (no modifier keys on device)", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"), { pointer = "touch" })
		adapter.tap(rowHitPath(0, "josh"), { pointer = "touch" })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)
end)

describe("Table: column resize interaction (Phase B)", function()
	it("resizable columns render a cursor-hinted grip; fixed columns do not", function()
		local _, adapter = world({})
		local grip = adapter.node("/S/Racers/Main/Header/Head-name/Grip")
		expect(grip ~= nil).toBe(true)
		expect(grip.props.cursorHint).toBe("colResize")
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/Grip")).toBe(nil)
	end)

	it("grip drag previews a guide line and commits the width on release", function()
		local _, adapter, pres = world({})
		local gripPath = "/S/Racers/Main/Header/Head-name/Grip"
		local cellRect = adapter.node("/S/Racers/Main/Header/Head-name").rect
		expect(cellRect.w).toBe(736) -- fill column: 800 viewport - 64 fixed
		adapter.pointerDown(gripPath, cellRect.x + cellRect.w, 10)
		adapter.pointerMove(cellRect.x + cellRect.w - 100, 12)
		pres.refresh()
		local line = adapter.node("/S/Racers/ResizeWhen/then/ResizeLine")
		expect(line ~= nil).toBe(true)
		expect(line.rect.x).toBe(636) -- guide sits at the dragged boundary
		-- preview only: rows still mounted under @0 keys until release
		expect(adapter.node(cellPath(0, "razz", "name")) ~= nil).toBe(true)
		adapter.pointerUp(cellRect.x + cellRect.w - 100, 12)
		pres.refresh()
		expect(adapter.node("/S/Racers/ResizeWhen/then/ResizeLine")).toBe(nil)
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(636)
		expect(adapter.node("/S/Racers/Main/Header/Head-name").rect.w).toBe(636)
	end)

	it("focus cycles through the column handle and the rows, and wraps around", function()
		-- hand-test finding 2026-07-20: focus used to reach the resize GRIP (a thin
		-- sliver) and appear lost. The grip is no longer a focus stop at all — the
		-- column's header is (director 2026-07-29) — and it LEADS rather than
		-- trails, because a header precedes its rows.
		local _, _, pres, _, _, _, system = world({})
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		for _ = 1, 3 do
			system.deviceKey("Down", true)
			system.deviceKey("Down", false)
		end
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "josh"))
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column") -- wrapped
		system.deviceKey("Up", true)
		system.deviceKey("Up", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "josh")) -- and back
	end)

	it("cells inset content from the left and center it vertically; headers read at full contrast", function()
		-- hand-test findings 2026-07-20: header text was unreadable (secondary
		-- tint over the world) and cell content sat flush at the cell origin
		local _, adapter = world({})
		local cellNode = adapter.node(cellPath(0, "razz", "name"))
		local value = adapter.node(cellPath(0, "razz", "name") .. "/Value")
		expect(value.rect.x).toBe(cellNode.rect.x + 8) -- default cellPadding
		-- vertically centered within the row (± rounding)
		local topGap = value.rect.y - cellNode.rect.y
		local bottomGap = (cellNode.rect.y + cellNode.rect.h) - (value.rect.y + value.rect.h)
		expect(math.abs(topGap - bottomGap) <= 1).toBe(true)
		expect(topGap > 0).toBe(true)
		-- header title: no dim role, inset like the cells
		local title = adapter.node("/S/Racers/Main/Header/Head-name/Title")
		expect(title.props.role).toBe(nil)
		expect(title.rect.x).toBe(adapter.node("/S/Racers/Main/Header/Head-name").rect.x + 8)
	end)

	it("gamepad/keyboard: a focused column handle resizes its column via the Adjust action", function()
		local _, adapter, pres, tbl, _, _, system = world({})
		-- the column handle leads the ring; Adjust binds only while it holds focus
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		-- keyboard Left: one 16px step narrower, committed through the model
		system.deviceKey("Left", true)
		system.deviceKey("Left", false)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(720)
		expect(adapter.node("/S/Racers/Main/Header/Head-name").rect.w).toBe(720)
		-- gamepad bumper: another step (the virtual cursor ignores MouseIcon,
		-- so this focus+bumper path IS the gamepad resize affordance)
		system.deviceKey("ButtonL1", true)
		system.deviceKey("ButtonL1", false)
		pres.refresh()
		expect(adapter.node(cellPath(2, "razz", "name")).rect.w).toBe(704)
	end)

	it("grip drag clamps to the column minWidth", function()
		local _, adapter, pres = world({})
		local gripPath = "/S/Racers/Main/Header/Head-name/Grip"
		local cellRect = adapter.node("/S/Racers/Main/Header/Head-name").rect
		adapter.pointerDown(gripPath, cellRect.x + cellRect.w, 10)
		adapter.pointerMove(cellRect.x + 10, 12) -- far past the minimum
		pres.refresh()
		adapter.pointerUp(cellRect.x + 10, 12)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(80) -- minWidth
	end)
end)

describe("Table: capture ownership (playlist place defect 2026-07-20)", function()
	it("a second pointer-down on ANOTHER row mid-drag cannot steal the capture; the drop still commits", function()
		-- live-found: dragging across rows fired InputBegan on the row being
		-- crossed, which silently killed the original capture (no cancel
		-- reason), leaving a stuck ghost and no reorder. A live capture OWNS
		-- the pointer until it ends.
		local reorders: { any } = {}
		local _, adapter, pres = world({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 60) -- past the threshold: drag is live
		pres.refresh()
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost") ~= nil).toBe(true)
		-- the pointer crosses ANOTHER row's hit zone: the engine can deliver a
		-- fresh began there — it must be IGNORED while a capture is live
		adapter.pointerDown(rowHitPath(0, "bolt"), 100, 62)
		adapter.pointerMove(100, 90)
		adapter.pointerUp(100, 90)
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz") -- the ORIGINAL drag committed
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
	end)
end)

describe("Table: touch scroll vs edit-mode reorder (director design 2026-07-20)", function()
	local function bigRows(n: number): { any }
		local out = {}
		for i = 1, n do
			table.insert(out, { id = `r{i}`, name = `Row {i}`, laps = i })
		end
		return out
	end
	local function scrollWorld(extra: any?)
		local reorders: { any } = {}
		local spec = {
			header = false,
			rowsOverride = bigRows(20),
			rowHeight = 40,
			height = { type = "fixed", px = 200 }, -- 5 visible of 20
			reorderable = true,
			selection = "none",
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
		}
		for k, v in (extra or {}) :: any do
			spec[k] = v
		end
		local core, adapter, pres, tbl, rows, handle, system, env = world(spec)
		return reorders, adapter, pres, tbl, core, env
	end
	local function hit(key: string): string
		return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
	end

	it("a touch drag on the row body defers to the native scroll and never reorders", function()
		local reorders, adapter, pres = scrollWorld()
		-- a one-finger touch on the row body DECLINES the pointer capture so the
		-- native ScrollingFrame owns the pan-scroll (native §4); it never starts a
		-- reorder and never lifts a ghost.
		local start = adapter.node(hit("r2")).rect
		adapter.pointerDown(hit("r2"), 100, start.y + 10, "touch")
		adapter.pointerMove(100, start.y - 50, "touch") -- finger moves UP 60
		pres.refresh()
		adapter.pointerUp(100, start.y - 50, "touch")
		pres.refresh()
		expect(#reorders).toBe(0)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
	end)

	it("the body is a native scroll region: it declares the full content canvas and clips", function()
		local _, adapter = scrollWorld()
		local body = adapter.node("/S/Racers/Main/Body")
		-- the body is a native ScrollingFrame: it clips partial rows and declares
		-- its solved content extent as the scroll canvas (native-substrate NS-A2)
		expect(body.props.clipChildren).toBe(true)
		expect(body.scrollRegion ~= nil).toBe(true)
		expect(body.scrollRegion.axis).toBe("y")
		-- 20 rows x 40px = 800 (the FULL content height, engine wheel-scrolls it)
		expect(body.scrollRegion.contentH).toBe(800)
	end)

	it("rows sit at absolute canvas offsets (the engine translates by CanvasPosition)", function()
		local _, adapter = scrollWorld()
		-- rows flow at their NATURAL document positions inside the scroll host —
		-- no hand-rolled -scrollOffset; a scroll moves CanvasPosition, not the rects
		local body = adapter.node("/S/Racers/Main/Body")
		expect(adapter.node(hit("r1")).rect.y).toBe(body.rect.y)
		expect(adapter.node(hit("r8")).rect.y).toBe(body.rect.y + 7 * 40)
	end)

	it("edit mode shows a LEADING ≡ glyph and insets the cells into a gutter", function()
		local _, adapter, pres, tbl = scrollWorld()
		local cellBefore = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect.x
		tbl.api.editing:set(true)
		pres.refresh()
		local glyph = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/HandleGlyph")
		expect(glyph ~= nil).toBe(true)
		expect(glyph.props.text).toBe("≡")
		-- the handle gutter is LEADING: cells shift right to clear it
		local cellAfter = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect.x
		expect(cellAfter).toBe(cellBefore + 32)
		tbl.api.editing:set(false)
		pres.refresh()
		expect(adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect.x).toBe(cellBefore)
	end)

	it("the ≡ handle clears the row CARD, not just the row rect (skinned themes)", function()
		-- Director report 2026-07-28, defect 4: "pixel quest playlist table drag
		-- icon overflows row on the left in edit mode."
		--
		-- Measured live under Pixel Quest: the row rect began at x=16 and the row's
		-- card art (`LuauUIChromeL1`) at x=28 — a 12px carved border. Every other
		-- element of the row pays that inset: the cells through `cellsEditPadding`,
		-- the header through its own explicit padding. The handle zone did not, so
		-- it sat at the raw row x and the ≡ drew 12px OUTSIDE the card it belongs
		-- to.
		--
		-- The inset is read as a theme METRIC, so this is one assertion over every
		-- package: zero under a flat one (nothing moves) and exactly the carved
		-- border under a skinned one.
		local packages = {
			{ name = "flat", pkg = nil },
			{ name = "pixel_quest", pkg = (require)("../examples/themes/pixel_quest").build(LuauUI.themes) },
			{ name = "fantasy_ornate", pkg = (require)("../examples/themes/fantasy_ornate").build(LuauUI.themes) },
			{ name = "glossy_touch", pkg = (require)("../examples/themes/glossy_touch").build(LuauUI.themes) },
		}
		for _, config in packages do
			local _, adapter, pres, tbl, _, env = scrollWorld()
			local inset = 0
			if config.pkg ~= nil then
				local snap = snapshot.resolve(config.pkg, nil, {})
				env:set("themeMetrics", snap)
				inset = snap.chromeInsets.selection.left
			end
			tbl.api.editing:set(true)
			pres.refresh()
			local row = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row").rect
			local zone = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone").rect
			expect(`{config.name}: zone starts at +{zone.x - row.x}, card at +{inset}`).toBe(
				`{config.name}: zone starts at +{inset}, card at +{inset}`
			)
			-- ...and the cells clear the handle AND the card, not one instead of
			-- the other: the gutter used to REPLACE the art inset rather than stack
			-- on it, so under a skinned package the first cell was under-inset too
			local cell = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect
			expect(`{config.name}: cell at +{cell.x - row.x}`).toBe(`{config.name}: cell at +{inset + 32}`)
		end
	end)

	it("engine double-dispatch: the row body DECLINES gutter touches so the handle wins either order", function()
		-- the engine fires InputBegan on EVERY element under the point; if the
		-- row hit receives it before the grip, the old ownership rule locked
		-- the gesture as a pan and the handle drag never started (live-found:
		-- edit-mode drop did not reorder)
		local reorders, adapter, pres, tbl = scrollWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		local handlePath = "/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle"
		local handleRect = adapter.node(handlePath).rect
		-- engine order A: hit first, then grip — the hit must decline
		adapter.pointerDown(hit("r1"), handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		adapter.pointerUp(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("r1")
		-- and a touch OUTSIDE the gutter also defers to the native scroll (the row
		-- hit declines every touch now; only the ≡ handle reorders on touch)
		local rowRect = adapter.node(hit("r2")).rect
		adapter.pointerDown(hit("r2"), rowRect.x + 200, rowRect.y + 5, "touch")
		adapter.pointerMove(rowRect.x + 200, rowRect.y - 55, "touch")
		pres.refresh()
		adapter.pointerUp(rowRect.x + 200, rowRect.y - 55, "touch")
		expect(#reorders).toBe(1) -- unchanged: a body touch never reorders
	end)

	it("mobile multi-reorder: tap-select rows, then a handle drag moves the WHOLE selection", function()
		local reorders, adapter, pres, tbl = scrollWorld({ selection = "multi" })
		tbl.api.editing:set(true)
		pres.refresh()
		-- tap-select r1 and r3 (touch taps = zero-length pans + Activated)
		tbl.api.handleActivate(hit("r1"), nil)
		tbl.api.handleActivate(hit("r3"), nil)
		pres.refresh()
		local handlePath = "/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle"
		local handleRect = adapter.node(handlePath).rect
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, handleRect.y + 175, "touch")
		pres.refresh()
		adapter.pointerUp(handleRect.x + 5, handleRect.y + 175, "touch")
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(2) -- the selected BLOCK moved
		expect(reorders[1].keys[1]).toBe("r1")
		expect(reorders[1].keys[2]).toBe("r3")
	end)

	it("edit mode grows a trailing handle per row; a TOUCH drag on the handle reorders", function()
		local reorders, adapter, pres, tbl = scrollWorld()
		local handlePath = "/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle"
		expect(adapter.node(handlePath)).toBe(nil) -- not editing yet
		tbl.api.editing:set(true)
		pres.refresh()
		expect(adapter.node(handlePath) ~= nil).toBe(true)
		local handleRect = adapter.node(handlePath).rect
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		adapter.pointerUp(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("r1")
	end)

	it("a touch drag on the row body while editing defers to native scroll (handle-only reorder)", function()
		local reorders, adapter, pres, tbl = scrollWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		-- while editing, a touch on the row BODY still declines to the native
		-- scroll — only the ≡ handle reorders on touch (native §4)
		local start = adapter.node(hit("r2")).rect
		adapter.pointerDown(hit("r2"), 100, start.y + 10, "touch")
		adapter.pointerMove(100, start.y - 50, "touch")
		pres.refresh()
		adapter.pointerUp(100, start.y - 50, "touch")
		pres.refresh()
		expect(#reorders).toBe(0)
	end)

	it("a MOUSE drag on the row body still reorders directly (desktop idiom)", function()
		local reorders, adapter, pres = scrollWorld()
		local start = adapter.node(hit("r1")).rect
		adapter.pointerDown(hit("r1"), 100, start.y + 5, "mouse")
		adapter.pointerMove(100, start.y + 75, "mouse")
		pres.refresh()
		adapter.pointerUp(100, start.y + 75, "mouse")
		pres.refresh()
		expect(#reorders).toBe(1)
	end)

	it("auto Edit/Done toggle: shown for touch input, hidden for mouse, toggles the handles", function()
		local _, adapter, pres, tbl, _, env = scrollWorld({ header = true, passEnv = true })
		local togglePath = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"
		-- env defaults to KeyboardAndMouse: no toggle
		expect(adapter.node(togglePath)).toBe(nil)
		env:set("preferredInput", "Touch")
		pres.refresh()
		expect(adapter.node(togglePath) ~= nil).toBe(true)
		expect(adapter.node(togglePath).props.label).toBe("Edit")
		tbl.api.handleActivate(togglePath, nil)
		pres.refresh()
		expect(adapter.node(togglePath).props.label).toBe("Done")
		expect(adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle") ~= nil).toBe(true)
	end)

	-- REGRESSION (director live repro 2026-07-21, example 02): a physical
	-- gamepad session where UserInputService.PreferredInput never leaves
	-- KeyboardAndMouse (mouse was the last-used device — e.g. clicking Play)
	-- must STILL surface the Edit affordance. Affordances derive from the LIVE
	-- capability set + preferredInput, never preferredInput alone (ADR-0015).
	it(
		"auto Edit/Done toggle: shown when a gamepad capability is live even though preferredInput stays KeyboardAndMouse",
		function()
			local _, adapter, pres, _, _, env = scrollWorld({ header = true, passEnv = true })
			local togglePath = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"
			expect(adapter.node(togglePath)).toBe(nil)
			-- the pad connects mid-session; preferredInput does NOT flip
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
			pres.refresh()
			expect(adapter.node(togglePath) ~= nil).toBe(true)
			-- the pad disconnects again: back to a pure mouse world, toggle leaves
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			pres.refresh()
			expect(adapter.node(togglePath)).toBe(nil)
		end
	)

	it(
		"auto Edit/Done toggle: a live touch capability shows it under a KeyboardAndMouse preferredInput (hybrid handheld)",
		function()
			local _, adapter, pres, _, _, env = scrollWorld({ header = true, passEnv = true })
			local togglePath = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"
			env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
			pres.refresh()
			expect(adapter.node(togglePath) ~= nil).toBe(true)
		end
	)
end)

describe("Table: gamepad support (director 2026-07-20 — every input, every control)", function()
	local function bigRows(n: number): { any }
		local out = {}
		for i = 1, n do
			table.insert(out, { id = `r{i}`, name = `Row {i}`, laps = i })
		end
		return out
	end
	local function padWorld(extra: any?)
		local reorders: { any } = {}
		local rowsRef: any = nil
		local spec = {
			header = false,
			rowsOverride = bigRows(5),
			rowHeight = 40,
			reorderable = true,
			selection = "multi",
			passEnv = true,
			-- a REAL consumer: record AND apply the post-removal splice
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
				local movingSet: { [string]: boolean } = {}
				for _, key in keys do
					movingSet[key] = true
				end
				local moving, staying = {}, {}
				for _, item in rowsRef:get() do
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
				rowsRef:set(out)
			end,
		}
		for k, v in (extra or {}) :: any do
			spec[k] = v
		end
		local core, adapter, pres, tbl, rows, handle, system, env = world(spec)
		rowsRef = rows
		return reorders, adapter, pres, tbl, rows, handle, env, core
	end
	local function hit(key: string): string
		return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
	end

	it("buildFocusGroups maps the toggle plus one horizontal group per row, in document order", function()
		local _, _, pres, tbl, _, handle, env = padWorld()
		env:set("preferredInput", "Gamepad")
		pres.refresh()
		local groups = tbl.api.buildFocusGroups(handle.root.node)
		expect(#groups).toBe(6) -- Edit toggle + 5 rows
		expect(string.find(groups[1].order[1], "EditToggle") ~= nil).toBe(true)
		expect(groups[2].axis).toBe("horizontal")
		expect(groups[2].order[1]).toBe(hit("r1"))
		expect(groups[6].order[1]).toBe(hit("r5"))
		-- without the toggle mounted (mouse env), only the row groups remain
		env:set("preferredInput", "KeyboardAndMouse")
		pres.refresh()
		expect(#tbl.api.buildFocusGroups(handle.root.node)).toBe(5)
	end)

	it("A-button (action) grab: grab, d-pad step-move, drop; focus path survives; visuals show grabbed", function()
		local reorders, adapter, pres, tbl, rows = padWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		-- gamepad activate = action source
		tbl.api.handleActivate(hit("r2"), { source = "action" })
		expect(tbl.api.grabbedKey:get()).toBe("r2")
		pres.refresh()
		expect(adapter.node(hit("r2")).props.selected).toBe(true) -- grabbed visual
		-- d-pad down: the grabbed row moves one slot; the move is CONSUMED
		expect(tbl.api.handleGrabNavigate("down")).toBe(true)
		local order = {}
		for _, item in rows:get() do
			table.insert(order, item.id)
		end
		expect(order[2]).toBe("r3") -- r2 stepped below r3
		expect(order[3]).toBe("r2")
		expect(tbl.api.handleGrabNavigate("up")).toBe(true)
		local back = {}
		for _, item in rows:get() do
			table.insert(back, item.id)
		end
		expect(back[2]).toBe("r2") -- stepped back
		-- drop with A again
		tbl.api.handleActivate(hit("r2"), { source = "action" })
		expect(tbl.api.grabbedKey:get()).toBeNil()
		expect(tbl.api.handleGrabNavigate("down")).toBe(false) -- nothing grabbed
		-- grab is edit-mode only: leaving edit clears it
		tbl.api.handleActivate(hit("r2"), { source = "action" })
		expect(tbl.api.grabbedKey:get()).toBe("r2")
		tbl.api.editing:set(false)
		expect(tbl.api.grabbedKey:get()).toBeNil()
		local _ = reorders
	end)

	it("focus moves anywhere INSIDE a row (stars included) re-select that row (Apple model)", function()
		local _, adapter, pres, tbl = padWorld()
		pres.refresh()
		tbl.api.handleActivate(hit("r1"), { pointer = "mouse" })
		pres.refresh()
		expect(adapter.node(hit("r1")).props.selected).toBe(true)
		-- focus lands on a cell DESCENDANT of r2 (not the hit): selection follows
		tbl.api.handleFocusMoved("/S/Racers/Main/Body/Rows/[r2@0]/Row/Cells/Cell-name/Value")
		pres.refresh()
		expect(adapter.node(hit("r2")).props.selected).toBe(true)
		expect(adapter.node(hit("r1")).props.selected).toBe(false) -- replace-select
		-- non-row paths (the Edit toggle) leave selection untouched
		tbl.api.handleFocusMoved("/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle")
		pres.refresh()
		expect(adapter.node(hit("r2")).props.selected).toBe(true)
	end)

	it("a grabbed SELECTED row steps the whole selection block", function()
		local _, _, pres, tbl, rows = padWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		-- pointer taps still select in edit mode (mouse/touch meta)
		tbl.api.handleActivate(hit("r1"), { pointer = "mouse" })
		tbl.api.handleActivate(hit("r3"), { pointer = "mouse", toggle = true })
		tbl.api.handleActivate(hit("r1"), { source = "action" }) -- grab r1 (selected)
		expect(tbl.api.grabbedKey:get()).toBe("r1")
		expect(tbl.api.handleGrabNavigate("down")).toBe(true)
		local order = {}
		for _, item in rows:get() do
			table.insert(order, item.id)
		end
		-- block {r1,r3} inserted after r2: r2, r1, r3, r4, r5
		expect(order[1]).toBe("r2")
		expect(order[2]).toBe("r1")
		expect(order[3]).toBe("r3")
	end)
end)

-- ===========================================================================
-- THE ROW'S ART RESERVES ROOM AND THE CELLS HONOUR IT
-- (director round 10, found live 2026-07-26 on a phone)
--
-- A row is a full-bleed hit Button with the cell stack as its SIBLING — it has
-- to be, because a Button's content may hold no focusable and a rating cell is
-- five of them. That shape is fine for input and was wrong for paint: the
-- renderer adds a slot's `chromeInsets` to the padding of the node that CARRIES
-- the slot, and that node (the hit button) has no children, so the reservation
-- was inert. Cells then laid out against the row's raw rect while the theme
-- painted its selection card INSIDE that rect, so under Glossy Touch, Pixel
-- Quest and Compact Pointer the first cell's text started outside the card it
-- was meant to sit in, and Compact's last column ran off the other end.
-- ===========================================================================
describe("table rows sit inside the theme's own selection card", function()
	local themes = LuauUI.themes

	local function cellXUnder(pkgModule: any?): (number, number)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local rows = core:signal(RACERS)
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			columns = {
				{ id = "name", title = "Name", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
			},
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(columnId, item)
				return LuauUI.UI.Text({
					id = "Value",
					text = if columnId == "name" then item.name else tostring(item.laps),
					textSize = 16,
				})
			end,
			rowHeight = 48,
			header = true,
			selection = "multi",
		})
		pres.present(LuauUI.UI.Screen({ id = "S", padding = 16, children = { tbl.blueprint } }))
		pres.refresh()
		if pkgModule ~= nil then
			env:set("themeMetrics", themes.resolve(pkgModule, nil, {}))
			pres.refresh()
		end
		return adapter.node("/S/T/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name").rect.x,
			adapter.node("/S/T/Main/Header/Head-name").rect.x
	end

	it("a flat package does not move a single pixel", function()
		local cell, head = cellXUnder(nil)
		expect(cell).toBe(16) -- the screen's own padding, and nothing else
		expect(head).toBe(16)
	end)

	it("a skinning package insets the cells by what its card reserves PLUS its glow gutter", function()
		-- Two gutters at two nesting levels, and the rows pay both (2026-07-27):
		-- the rows' viewport is a clipping ScrollView, so it insets its content by
		-- the package's `chromeBleed` or the shadow is cut at its edge; then each
		-- row's own card reserves its carved border inside that. A package with no
		-- shadow has bleed 0 and this is exactly the old assertion.
		for _, name in { "glossy_touch", "pixel_quest", "compact_pointer" } do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local snap = themes.resolve(pkg, nil, {})
			local reserve = snap.chromeInsets.selection.left
			local bleed = if type(snap.chromeBleed) == "number" then snap.chromeBleed else 0
			expect(reserve > 0).toBe(true) -- these three DO carve a border
			local cell = cellXUnder(pkg)
			expect(cell).toBe(16 + bleed + reserve)
		end
	end)

	it("the header tracks the rows, so the columns never come apart", function()
		for _, name in { "glossy_touch", "pixel_quest", "compact_pointer" } do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local cell, head = cellXUnder(pkg)
			expect(head).toBe(cell)
		end
	end)
end)

-- ===========================================================================
-- WHO OWNS THE SCROLLING (director report 2026-07-27, the playlist example in
-- landscape: "just the table scrolls. really the whole view should scroll, as
-- it's unusable having just the table scroll").
--
-- A table's body is a viewport by default and that is right when the table IS
-- the screen. It is wrong when the table is one block on a page: the title,
-- filter and hint above it took 45-55% of a short landscape viewport and the
-- ONLY thing that could move was the rows, inside whatever was left.
-- ===========================================================================
describe("Table: `scrolls = false` makes it a block for a scrolling host", function()
	local function blockWorld(scrolls: boolean?, w: number, h: number)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local rows = core:signal(RACERS)
		local tbl = table_control.build(LuauUI, core, {
			id = "Racers",
			env = env,
			scrolls = scrolls,
			rowHeight = 48,
			header = true,
			columns = { { id = "name", title = "Racer", width = { type = "fill", weight = 1 } } },
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return LuauUI.UI.Text({ id = "Value", text = item.name, textSize = 15 })
			end,
		})
		pres.present(LuauUI.UI.Screen({
			id = "S",
			padding = 8,
			children = {
				LuauUI.UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						LuauUI.UI.Text({ id = "Title", text = "Racers", textSize = 24 }),
						tbl.blueprint,
					},
				}),
			},
		}))
		pres.refresh()
		return adapter
	end

	local function scrollers(adapter: any): { string }
		local out = {}
		for _, path in adapter.paths() do
			local n = adapter.node(path)
			if n ~= nil and n.scrollRegion ~= nil then
				table.insert(out, path)
			end
		end
		return out
	end

	it("as a BLOCK there is exactly ONE scroller, and it is the host's page", function()
		-- nesting a scroller inside a scrolling page makes a vertical drag over the
		-- rows ambiguous, and the inner one always wins — which is the defect
		local found = scrollers(blockWorld(false, 844, 390))
		expect(#found).toBe(1)
		expect(found[1]).toBe("/S/Page")
	end)

	it("...and the page's canvas carries the WHOLE view, header included", function()
		-- 160px tall: shorter than this fixture's three 48px rows plus a header and
		-- a title, which is the landscape case the report came from
		local adapter = blockWorld(false, 844, 160)
		local page = adapter.node("/S/Page")
		-- more content than box = the page is what scrolls, and the title above the
		-- table scrolls away with the rows
		expect(page.scrollRegion.contentH > page.rect.h).toBe(true)
		expect(adapter.node("/S/Page/Title") ~= nil).toBe(true)
	end)

	it("every row is laid out rather than clipped to a window", function()
		local adapter = blockWorld(false, 844, 390)
		for _, racer in RACERS do
			expect(adapter.node(`/S/Page/Racers/Main/Body/Rows/[{racer.id}@0]/Row`) ~= nil).toBe(true)
		end
	end)

	it("the DEFAULT is unchanged: the table still owns its own viewport", function()
		local found = scrollers(blockWorld(nil, 844, 390))
		local hasBody = false
		for _, p in found do
			if string.find(p, "/Racers/Main/Body", 1, true) ~= nil then
				hasBody = true
			end
		end
		expect(hasBody).toBe(true)
	end)
end)

describe("Table column disclosure (Step 8.5 LT-G2)", function()
	-- the default `value` cell and the header title are Texts the TABLE authors;
	-- a column's `disclose = true` is the consumer's only way to declare their
	-- identity strings disclosable (a custom `cell` declares its own)
	local LONG = "Maximiliana-Wilhelmina Rennfahrerin-Steuerbord III"

	local function discloseWorld(disclose: boolean?)
		return world({
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fixed", px = 120 },
					value = function(item: any)
						return if item.id == "razz" then LONG else item.name
					end,
					disclose = disclose,
				},
				{
					id = "laps",
					title = "Laps",
					width = { type = "fixed", px = 64 },
					value = function(item: any)
						return tostring(item.laps)
					end,
				},
			},
			header = true,
		})
	end

	it("a disclosing column stamps disclose on its value cells AND its header title", function()
		-- construction-only props never reach the adapter; the solve's textFacts
		-- are the observable channel (the same one the presenter's plate reads)
		local _, _, _, _, _, handle = discloseWorld(true)
		local cell = handle.controller.textAt("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name/Value")
		expect(cell ~= nil).toBe(true)
		expect((cell :: any).disclose).toBe(true)
		expect((cell :: any).truncated).toBe(true) -- the LONG fixture really is cut
		local title = handle.controller.textAt("/S/Racers/Main/Header/Head-name/Title")
		expect(title ~= nil).toBe(true)
		expect((title :: any).disclose).toBe(true)
	end)

	it("...and an ordinary column stamps nothing — the default is byte-identical", function()
		local _, _, _, _, _, handle = discloseWorld(nil)
		local cell = handle.controller.textAt("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name/Value")
		expect((cell :: any).disclose ~= true).toBe(true)
		local laps = handle.controller.textAt("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-laps/Value")
		expect((laps :: any).disclose ~= true).toBe(true)
	end)

	it("engaging the truncated disclosing cell presents its FULL value through the presenter", function()
		local _, adapter, pres = discloseWorld(true)
		pres._discloseLongPress("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name/Value")
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.text).toBe(LONG)
		pres._discloseLongPress(nil)
		expect(pres.disclosure().present).toBe(false)
	end)
end)

describe("Table column boundary is strict (architecture review F-4)", function()
	local function build(column: any)
		return table_control.build(LuauUI, LuauUI.newCore(), {
			id = "T",
			columns = { column },
			rows = LuauUI.newCore():signal({}),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
		})
	end

	it(
		"an unknown column key is refused, naming the column — a disclose typo cannot silently drop the guarantee",
		function()
			local ok, err = pcall(function()
				return build({
					id = "name",
					width = { type = "fixed", px = 100 },
					value = function()
						return "x"
					end,
					disclos = true,
				})
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "disclos") ~= nil).toBe(true)
		end
	)

	it("a non-boolean disclose is refused with the type it got", function()
		local ok, err = pcall(function()
			return build({
				id = "name",
				width = { type = "fixed", px = 100 },
				value = function()
					return "x"
				end,
				disclose = "yes",
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "boolean") ~= nil).toBe(true)
	end)
end)

-- ============================================================================
-- `rowGap` TAKES A THEME METRIC NAME (example-quality-pass, 2026-08-06).
--
-- `cellPadding` has accepted "a number or a theme metric name" since it shipped,
-- because it is only ever handed to a blueprint prop. `rowGap` is ALSO read in
-- Luau — the cumulative row tops, the content extent and the drop slot — so a
-- metric name reached `cum += height + rowGap` and threw "attempt to perform
-- arithmetic on number and string". Found by pointing the playlist example at
-- `controls.table.rowGap` instead of the literal 2 it had been carrying.
--
-- The default is unchanged (0): this widens what the option ACCEPTS, and moves
-- nothing for a caller that passes a number or nothing at all.
-- ============================================================================
describe("Table.rowGap: a number or a theme metric name", function()
	local function gapBetweenFirstTwoRows(rowGap: any): number
		local _, adapter = world({ rowGap = rowGap, header = false })
		local first = adapter.node(rowHitPath(0, RACERS[1].id)).rect
		local second = adapter.node(rowHitPath(0, RACERS[2].id)).rect
		return second.y - (first.y + first.h)
	end

	it("a number behaves exactly as it always has", function()
		expect(gapBetweenFirstTwoRows(6)).toBe(6)
		expect(gapBetweenFirstTwoRows(nil)).toBe(0)
	end)

	it("a SPACING STEP resolves to the theme's own step, not to a crash", function()
		local neutral = snapshot.resolve(LuauUI.themes.neutralPackage(), nil, {})
		local expected = snapshot.resolveNumber(neutral, "s")
		expect(type(expected)).toBe("number")
		expect(gapBetweenFirstTwoRows("s")).toBe(expected)
	end)

	it("a DOTTED METRIC PATH resolves too — the spelling the playlist example uses", function()
		local neutral = snapshot.resolve(LuauUI.themes.neutralPackage(), nil, {})
		local expected = snapshot.resolveNumber(neutral, "controls.table.rowGap")
		expect(type(expected)).toBe("number")
		expect(expected > 0).toBe(true)
		expect(gapBetweenFirstTwoRows("controls.table.rowGap")).toBe(expected)
	end)

	it("the DROP SLOT arithmetic uses the resolved pixels, not the name", function()
		-- this is the seam that threw: `insertSlotAt` walks cumulative row tops
		-- and divides the gap in half to centre the drop indicator
		local core, adapter, pres = world({ rowGap = "controls.table.rowGap", reorderable = true, header = false })
		pres.refresh()
		expect(adapter.node(rowHitPath(0, RACERS[2].id)) ~= nil).toBe(true)
		expect(core:lastError()).toBeNil()
	end)

	it("a name that resolves to NOTHING is refused at the authoring boundary, naming it", function()
		-- better than the arithmetic quietly reading 0: the blueprint's `metric`
		-- check owns this ruling and it fires before anything is measured
		local ok, err = pcall(function()
			return gapBetweenFirstTwoRows("controls.table.noSuchMetric")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "noSuchMetric", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "names no theme metric", 1, true) ~= nil).toBe(true)
	end)
end)

-- =============================================================================
-- THE TABLE'S OWN CHROME STACKS — AT EVERY TEXT PREFERENCE (EQ-6 / LT-F3)
--
-- Device report 2026-08-06, compact phone portrait AND landscape, both reference
-- packages, Largest text: "the edit button overlaps the heading". The header
-- band was a FIXED `controls.table.headerHeight` box (28px). At the Largest
-- preference a ONE-LINE column title measures 34px, so the title painted 6px out
-- of its own ZStack — over the toolbar row above it and the first row below.
--
-- The solver had been reporting it the whole time: `Head-<id>/Title` filed
-- "overflows its zstack by 0x6px ... give the box room — a `minMax` FLOOR rather
-- than a fixed CAP". Nothing FAILED on it, so nobody read it. That is the whole
-- lesson of docs/lessons/the-solver-already-told-you.md, and it is why the first
-- assertion here is the diagnostics list itself.
--
-- The director's framing is the fix: "if height is the issue why can't we make
-- the whole table have more height as text size increases". It can, and now it
-- does — the band floors at the token and grows to the line it must hold, so the
-- header pushes the body down instead of drawing through its neighbours.
--
-- Swept with the auto Edit toggle UP (reorderable + touch + no owner editing
-- signal), because the toolbar is the neighbour the header hit.
-- =============================================================================
describe("Table: toolbar, header and body stack at every text preference", function()
	local PREFERENCES = { 0, 4, 10, 14 }

	-- one real table, solved on a compact phone with the auto toolbar showing;
	-- returns the three band rects plus the solver's own verdict
	local function solveChrome(offset: number, viewport: any): any
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", viewport)
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		env:set("preferredInput", "Touch")
		env:set("preferredTextOffset", offset)
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)

		local rows = core:signal({ { id = "a", name = "Drift City Nights" }, { id = "b", name = "Neon Overpass" } })
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(i: any)
						return i.name
					end,
				},
				{
					id = "rate",
					title = "Rating",
					width = { type = "fixed", px = 120 },
					value = function()
						return "***"
					end,
				},
			},
			rows = rows,
			key = function(i: any)
				return i.id
			end,
			scrolls = false,
			header = true,
			reorderable = true,
			onReorder = function() end,
			env = env,
		})
		local handle = pres.present(LuauUI.UI.Screen({ id = "S", padding = 16, children = { tbl.blueprint } }))
		local rectOf = handle.controller.rectOf
		local out = {
			toolbar = rectOf("/S/T/Main/ToggleWhen/then/Toolbar"),
			toggle = rectOf("/S/T/Main/ToggleWhen/then/Toolbar/EditToggle"),
			header = rectOf("/S/T/Main/Header"),
			headName = rectOf("/S/T/Main/Header/Head-name"),
			-- the PAINTED heading, not the band that holds it: the band stacked
			-- correctly all along, and the title drew out of it
			titleName = rectOf("/S/T/Main/Header/Head-name/Title"),
			titleRate = rectOf("/S/T/Main/Header/Head-rate/Title"),
			body = rectOf("/S/T/Main/Body"),
			diagnostics = handle.controller.diagnostics(),
		}
		pres.dismiss(handle)
		tbl.dispose()
		rows:dispose()
		return out
	end

	local VIEWPORTS = {
		{ id = "compact-portrait", rect = { x = 0, y = 0, w = 393, h = 852 } },
		{ id = "compact-landscape", rect = { x = 0, y = 0, w = 852, h = 393 } },
	}

	it("the solver files NO overflow anywhere in the table's chrome, at any preference", function()
		for _, viewport in VIEWPORTS do
			for _, offset in PREFERENCES do
				local r = solveChrome(offset, viewport.rect)
				local found = r.diagnostics or {}
				if #found > 0 then
					local lines = {}
					for _, entry in found :: any do
						table.insert(lines, `  {tostring((entry :: any).node)} :: {tostring((entry :: any).issue)}`)
					end
					error(
						`{viewport.id} @+{offset}: the solver filed {#found} finding(s) against the table's own `
							.. `chrome:\n{table.concat(lines, "\n")}`,
						0
					)
				end
			end
		end
	end)

	it("the toolbar, the header and the body never overlap — the reported defect", function()
		for _, viewport in VIEWPORTS do
			for _, offset in PREFERENCES do
				local r = solveChrome(offset, viewport.rect)
				expect(r.toolbar ~= nil).toBe(true)
				expect(r.header ~= nil).toBe(true)
				expect(r.body ~= nil).toBe(true)
				-- THE PAINTED PAIR, not the two bands. The bands stacked correctly
				-- even while the defect was live — it was the heading TEXT that
				-- drew up out of its band and into the toolbar, so the assertion
				-- has to name the two rects the director actually saw collide.
				local bottomOfToolbar = r.toggle.y + r.toggle.h
				for id, title in { name = r.titleName, rate = r.titleRate } do
					expect(title ~= nil).toBe(true)
					if title.y < bottomOfToolbar then
						error(
							`{viewport.id} @+{offset}: the '{id}' heading (y={title.y} h={title.h}) is painted `
								.. `INSIDE the Edit toggle (y={r.toggle.y} h={r.toggle.h}, bottom={bottomOfToolbar}) `
								.. `— the two overlap by {bottomOfToolbar - title.y}px`,
							0
						)
					end
					if title.y + title.h > r.body.y then
						error(
							`{viewport.id} @+{offset}: the '{id}' heading (y={title.y} h={title.h}) is painted `
								.. `into the first row (body y={r.body.y})`,
							0
						)
					end
				end
				if r.header.y + r.header.h > r.body.y then
					error(
						`{viewport.id} @+{offset}: the header (y={r.header.y} h={r.header.h}) paints into `
							.. `the body (y={r.body.y})`,
						0
					)
				end
			end
		end
	end)

	it("the header band GROWS with the preference instead of holding its token", function()
		local viewport = VIEWPORTS[1].rect
		local plain = solveChrome(0, viewport)
		local largest = solveChrome(14, viewport)
		-- the token is the FLOOR: unchanged at the shipped size...
		expect(plain.header.h).toBe(28)
		-- ...and taller when the text it must hold is taller. Without this the
		-- title overflowed by exactly the difference.
		expect(largest.header.h > plain.header.h).toBe(true)
		-- and the whole table is taller for it, which is the point: the bands
		-- move down together rather than one drawing through another
		expect(largest.body.y > plain.body.y).toBe(true)
	end)
end)

-- ============================================================================
-- Task 10: `spec.rowActions` — Table integration (docs/plans/row-actions-
-- implementation.md). A wrapped row mounts at `.../[key@v]/RowActions-<key>/...`
-- (row_actions.build's own root `id = "RowActions-<rowKey>"`, one `Content` ZStack
-- inside it, THIS row's own blueprint — Hit/Cells/EditWhen, unchanged —
-- mounted inside THAT); an unwrapped row (nil `rowActions`, or the callback
-- returns nil for that item) stays exactly `.../[key@v]/Row/...`, byte-
-- identical to every table before this task (the PERF directive: zero new
-- nodes, zero new subscriptions per row when unused).
describe("Table: row actions (Task 10)", function()
	-- row_actions.build's own root `id = "RowActions-<rowKey>"` (table.luau) —
	-- UNIQUE per row, not the literal "RowActions": two instances sharing one
	-- id corrupted each other's in-flight gesture state (see
	-- `derowActionsPath`'s own comment in table.luau for the live-found repro
	-- this test suite caught it with).
	local function rowActionsRoot(version: number, key: string): string
		return `/S/Racers/Main/Body/Rows/[{key}@{version}]/RowActions-{key}`
	end
	local function wrappedRowHitPath(version: number, key: string): string
		return `{rowActionsRoot(version, key)}/Content/Row/Hit`
	end
	local function trayButtonPath(version: number, key: string, edge: "leading" | "trailing", actionId: string): string
		local tid = if edge == "leading" then "TrayLeading" else "TrayTrailing"
		return `{rowActionsRoot(version, key)}/{tid}When/then/{tid}/Action:{actionId}`
	end
	local function editAffordancePath(version: number, key: string): string
		return `{rowActionsRoot(version, key)}/EditAffordanceWhen/then/EditAffordance`
	end
	local function deleteAction(fired: { string }?, opts: any?): any
		opts = opts or {}
		return {
			id = opts.id or "delete",
			role = opts.role or "destructive",
			label = opts.label or "Delete",
			onAction = function()
				if fired ~= nil then
					table.insert(fired, "fired")
				end
			end,
		}
	end

	-- a SCRIPTED clock (row_actions_input.spec.luau's own `pointerWorld`
	-- pattern) — see `world`'s own comment on `spec.now` for why any test
	-- that drives a real drag-velocity-seeded gesture needs one. `tick`
	-- pairs `pres.tick` (springs) with `pres.refresh()` (syncGeometry — the
	-- ONLY pass that measures a just-revealed tray's live button widths;
	-- pointerWorld's own comment: skipping it leaves `leadingWidth`/
	-- `trailingWidth` frozen at 0 forever).
	local function raWorld(spec: any)
		local clockTime = 0
		spec.now = function()
			return clockTime
		end
		local core, adapter, pres, tbl, rows, handle, system, env = world(spec)
		local function tick(dt: number)
			clockTime += dt
			pres.tick(dt)
			pres.refresh()
		end
		local function settle(frames: number?)
			for _ = 1, frames or 90 do
				tick(1 / 60)
			end
		end
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			tbl = tbl,
			rows = rows,
			handle = handle,
			system = system,
			env = env,
			tick = tick,
			settle = settle,
		}
	end

	it("wraps only rows whose callback returns actions; nil rows get no RowActions node", function()
		local _, adapter = world({
			header = false,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		expect(adapter.node(rowActionsRoot(0, "razz")) ~= nil).toBe(true)
		expect(adapter.node(wrappedRowHitPath(0, "razz")) ~= nil).toBe(true)
		-- unwrapped rows are byte-identical to an ordinary table: no RowActions
		-- node at all, `Row` sits directly under the ForEach slot
		expect(adapter.node(rowActionsRoot(0, "bolt"))).toBe(nil)
		expect(adapter.node(rowHitPath(0, "bolt")) ~= nil).toBe(true)
	end)

	it("unknown keys inside the returned action table error at build, naming the offending row", function()
		local ok, err = pcall(function()
			world({
				header = false,
				rowActions = function(item)
					if item.id == "razz" then
						return { trailing = { deleteAction() }, bogus = true }
					end
					return nil
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "bogus") ~= nil).toBe(true)
		expect(string.find(tostring(err), "razz") ~= nil).toBe(true)
	end)

	it("swiping row B open closes row A (one shared coordinator through Table)", function()
		local w = raWorld({
			header = false,
			rowActions = function(_item)
				-- fullSwipe = false: any drag distance can only ever snap OPEN,
				-- never commit — isolates the coordinator's claim/release from
				-- the commit sequence entirely.
				return { trailing = { deleteAction() }, fullSwipe = false }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local boltHit = wrappedRowHitPath(0, "bolt")
		local razzClosedX = w.adapter.node(razzHit).rect.x
		local boltClosedX = w.adapter.node(boltHit).rect.x

		local function openVia(hitPath: string, y: number)
			w.adapter.pointerDown(hitPath, 100, y, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(60, y) -- past the 8px axis lock, horizontal
			w.tick(1.0) -- calm gap: velocity's contribution is negligible
			w.adapter.pointerMove(-200, y) -- huge leftward drag (well past any tray)
			w.tick(1 / 60)
			w.adapter.pointerUp(-200, y)
			w.settle()
		end

		openVia(razzHit, 20)
		expect(w.adapter.node(razzHit).rect.x < razzClosedX).toBe(true) -- razz open

		openVia(boltHit, 60)
		expect(w.adapter.node(boltHit).rect.x < boltClosedX).toBe(true) -- bolt now open
		-- razz closed AS A RESULT of bolt's claim through the shared coordinator
		-- (bolt's own gesture never touched razz directly)
		expect(w.adapter.node(razzHit).rect.x).toBe(razzClosedX)
	end)

	it("mouse vertical drag on a reorderable + wrapped row still reorders", function()
		local reorders: { any } = {}
		local w = raWorld({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			rowActions = function(_item)
				return { trailing = { deleteAction() } }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		w.adapter.pointerDown(razzHit, 100, 20)
		w.adapter.pointerMove(100, 90) -- purely vertical, well past the reorder threshold
		w.pres.refresh()
		expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true) -- reorder engaged
		w.adapter.pointerUp(100, 90)
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
	end)

	it("mouse horizontal drag on the same reorderable + wrapped row reveals actions instead of reordering", function()
		local reorders: { any } = {}
		local w = raWorld({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			rowActions = function(_item)
				return { trailing = { deleteAction() }, fullSwipe = false }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local closedX = w.adapter.node(razzHit).rect.x
		w.adapter.pointerDown(razzHit, 100, 20)
		w.tick(0.01)
		w.adapter.pointerMove(60, 20) -- purely horizontal, past the axis lock
		w.tick(1.0)
		w.adapter.pointerMove(-100, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(-100, 20)
		w.settle()
		expect(#reorders).toBe(0) -- reorder never engaged
		expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- content slid: tray revealed
		expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
	end)

	-- REDTEAM ITEM 10 (MEDIUM; spec: docs/plans/row-actions.md:136). The
	-- reorder ≡ handle ALWAYS starts a reorder, unconditionally, regardless
	-- of the row's own tray state — a handle-zone press used to leave an
	-- already-open tray stranded, sliding along with (or detached from) a
	-- row being dragged out from under it. Fixed at `handleDragHandlers`'s
	-- own `onPointerDown` in table.luau (the same `rowActionsByKey` lookup
	-- the row-tap handler already uses).
	it(
		"starting a reorder-handle drag on a row whose tray is open closes the tray FIRST, before reorder proceeds",
		function()
			local core = LuauUI.newCore()
			local editingSignal = core:signal(true) -- edit mode: the ≡ handle is mounted
			local w = raWorld({
				core = core,
				header = false,
				reorderable = true,
				editing = editingSignal,
				onReorder = function() end,
				rowActions = function(_item)
					return { trailing = { deleteAction() }, fullSwipe = false }
				end,
			})
			local razzHit = wrappedRowHitPath(0, "razz")
			local closedX = w.adapter.node(razzHit).rect.x

			-- open the tray via an ordinary horizontal drag on the row's own Hit
			w.adapter.pointerDown(razzHit, 100, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			w.adapter.pointerMove(-200, 20)
			w.tick(1 / 60)
			w.adapter.pointerUp(-200, 20)
			w.settle()
			expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- open

			-- grab the ≡ handle: the tray's CLOSE is triggered the instant the
			-- press lands (before any move, before reorder itself even
			-- begins) — `_close()` retargets the same reveal spring the
			-- gesture itself rides, so the pixel position animates back over
			-- subsequent frames rather than snapping; settle to observe it.
			local handlePath = `{rowActionsRoot(0, "razz")}/Content/Row/EditWhen/then/HandleZone/Handle`
			w.adapter.pointerDown(handlePath, 100, 20, "mouse")
			w.settle()
			expect(w.adapter.node(razzHit).rect.x).toBe(closedX)

			-- and reorder itself still proceeds normally afterward — the fix
			-- only closes the tray, it does not eat or defer the handle press
			w.adapter.pointerMove(100, 90)
			w.pres.refresh()
			expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true) -- reorder engaged
			w.adapter.pointerUp(100, 90)
		end
	)

	it("editing signal shows the minus on rows with a destructive action", function()
		local core = LuauUI.newCore()
		local editingSignal = core:signal(false)
		local _, adapter, pres = world({
			core = core,
			header = false,
			editing = editingSignal,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		expect(adapter.node(editAffordancePath(0, "razz"))).toBe(nil) -- not editing yet
		editingSignal:set(true)
		pres.refresh()
		expect(adapter.node(editAffordancePath(0, "razz")) ~= nil).toBe(true)
	end)

	it("rows removed from spec.rows dispose their wrapper (no leak)", function()
		local core = LuauUI.newCore()
		local _, adapter, pres, _tbl, rows = world({
			core = core,
			header = false,
			rowsOverride = { RACERS[1] }, -- razz only; nothing wrapped yet
			rowActions = function(item)
				if item.id == "bolt" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		local baseline = core:counters()
		rows:set({ RACERS[1], RACERS[2] }) -- add bolt: wraps
		pres.refresh()
		expect(adapter.node(rowActionsRoot(0, "bolt")) ~= nil).toBe(true)
		rows:set({ RACERS[1] }) -- remove bolt: wrapper must dispose
		pres.refresh()
		expect(adapter.node(rowActionsRoot(0, "bolt"))).toBe(nil)
		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	it("a data refresh mid-gesture cancels: onAction never fires for a key removed mid-commit", function()
		local fired: { string } = {}
		local w = raWorld({
			header = false,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction(fired) } }
				end
				return nil
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local rowW = w.adapter.node(razzHit).rect.w
		w.adapter.pointerDown(razzHit, 100, 20)
		w.tick(0.01)
		w.adapter.pointerMove(60, 20)
		w.tick(1.0)
		local releaseX = 100 - rowW * 0.9 -- past the 60% full-swipe commit threshold
		w.adapter.pointerMove(releaseX, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(releaseX, 20)
		-- a couple of frames into the slide-off — comfortably before onArrive
		w.tick(1 / 60)
		w.tick(1 / 60)
		expect(#fired).toBe(0)
		-- mid-flight data refresh: razz's key vanishes from the data entirely
		w.rows:set({ RACERS[2], RACERS[3] })
		w.pres.refresh()
		w.settle()
		expect(#fired).toBe(0) -- never fires for the replaced/vanished key
	end)

	it("Delete key on a focused row deletes via the row's destructive action", function()
		local fired: { string } = {}
		local core = LuauUI.newCore()
		local _, adapter, pres, _tbl, _rows, _handle, system = world({
			core = core,
			header = false,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction(fired) } }
				end
				return nil
			end,
		})
		pres.focus.focusOn(wrappedRowHitPath(0, "razz"))
		system.deviceKey("Delete", true)
		system.deviceKey("Delete", false)
		pres.refresh()
		-- TWO sequential springs settle here (slide-off, then the height
		-- collapse — row_actions.luau's own `doCommitAction` chain), each up
		-- to ~90 frames on its own (row_actions.spec.luau's own
		-- SETTLE_FRAMES convention) — a wide fill-column row (this table's
		-- own 800px viewport) slides the FULL row width off-screen, so 90
		-- frames alone (enough for ONE spring) left the second stranded
		-- mid-flight. Paired with `pres.refresh()` throughout (syncGeometry
		-- has to keep running for `currentRowHeight()`'s own live read).
		for _ = 1, 240 do
			pres.tick(1 / 60)
			pres.refresh()
		end
		expect(#fired).toBe(1)
	end)

	it(
		"iOS tap-to-close: a tap on a row's own content while ITS tray is open closes it — no select, no activate",
		function()
			local w = raWorld({
				header = false,
				selection = "single",
				rowActions = function(item)
					if item.id == "razz" then
						return { trailing = { deleteAction() }, fullSwipe = false }
					end
					return nil
				end,
			})
			local razzHit = wrappedRowHitPath(0, "razz")
			local closedX = w.adapter.node(razzHit).rect.x
			w.adapter.pointerDown(razzHit, 100, 20)
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			w.adapter.pointerMove(-200, 20)
			w.tick(1 / 60)
			w.adapter.pointerUp(-200, 20)
			w.settle()
			expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- confirmed open

			w.adapter.tap(razzHit) -- a genuine tap/Activate on the row's own content
			w.pres.refresh()
			expect(w.tbl.api.selectedKeys:get().razz).toBe(nil) -- no select
			w.settle()
			expect(w.adapter.node(razzHit).rect.x).toBe(closedX) -- tray closed
		end
	)

	it(
		"a committed delete shrinks the row's own box and moves following rows up, THEN fires onAction and lets the owner remove it via keyed diff",
		function()
			local fired: { string } = {}
			local w = raWorld({
				header = false,
				rowActions = function(item)
					if item.id == "razz" then
						return { trailing = { deleteAction(fired) } }
					end
					return nil
				end,
			})
			local razzHit = wrappedRowHitPath(0, "razz")
			local razzOuter = rowActionsRoot(0, "razz")
			local boltYBefore = w.adapter.node(rowHitPath(0, "bolt")).rect.y
			local razzHeightBefore = w.adapter.node(razzOuter).rect.h
			expect(razzHeightBefore > 0).toBe(true)

			local rowW = w.adapter.node(razzHit).rect.w
			w.adapter.pointerDown(razzHit, 100, 20)
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			local releaseX = 100 - rowW * 0.9
			w.adapter.pointerMove(releaseX, 20)
			w.tick(1 / 60)
			w.adapter.pointerUp(releaseX, 20)

			-- comfortably PAST the slide-off (a full -rowWidth flight across
			-- this 800px fill-column row takes ~70 frames on its own) and
			-- into the height collapse that follows it, well before either
			-- spring fully settles (a live-measured trace building this test:
			-- the slide sits at 40px — untouched — through frame ~65, then
			-- the collapse spring visibly shrinks it every frame from ~75
			-- onward).
			for _ = 1, 100 do
				w.tick(1 / 60)
			end
			expect(#fired).toBe(0) -- still animating: never fires early
			local shrinkingHeight = w.adapter.node(razzOuter).rect.h
			expect(shrinkingHeight < razzHeightBefore).toBe(true) -- the row's OWN box shrank
			expect(w.adapter.node(rowHitPath(0, "bolt")).rect.y < boltYBefore).toBe(true) -- bolt already moved up

			-- run to completion: TWO sequential springs here (slide-off, then
			-- the height collapse), each up to ~90 frames alone against this
			-- wide fill-column row — see the Delete-key test's own comment
			-- for the same arithmetic.
			w.settle(240)
			expect(#fired).toBe(1) -- fires exactly once, after the animation

			-- the owner's data mutation removes the row via keyed diff — NOT the
			-- composite itself; row_actions only ever animates and reports
			w.rows:set({ RACERS[2], RACERS[3] })
			w.pres.refresh()
			expect(w.adapter.node(razzHit)).toBe(nil)
			expect(w.adapter.node(rowHitPath(0, "bolt")) ~= nil).toBe(true)
		end
	)

	it("edit mode shows BOTH the row_actions minus and Table's own reorder handle at once", function()
		local core = LuauUI.newCore()
		local editingSignal = core:signal(true) -- start in edit mode
		local _, adapter = world({
			core = core,
			header = false,
			reorderable = true,
			editing = editingSignal,
			onReorder = function() end,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		expect(adapter.node(editAffordancePath(0, "razz")) ~= nil).toBe(true) -- the minus
		expect(adapter.node(`{rowActionsRoot(0, "razz")}/Content/Row/EditWhen/then/HandleZone/Handle`) ~= nil).toBe(
			true
		) -- Table's own reorder handle, still there
	end)
end)
