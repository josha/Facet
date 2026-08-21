--!strict
-- Table paradigm axis: bare-Table column-resize Adjust (matrix §B-Table kb/gamepad
-- GAP, UI-PARADIGM-001) and hot-switch transition semantics (matrix §C,
-- UI-PARADIGM-002). Every behavior runs through the REAL device path — the
-- presenter's zero-opt auto-composition, deviceKey/deviceAxis, the adapter pointer
-- seam, and env capability flips — never a direct api.* call for the assertion.
--
--   1. bare-Table column resize on keyboard (Comma/Period) + gamepad (L1/R1),
--      focus-gated: no Adjust key is bound while focus sits off the grip, so a
--      non-modal Table never shadows gameplay bumpers; the grip is reachable
--      through the auto "headers" navigation group.
--   2. §C in-flight class-flip rows: pointer-drag CANCEL on pointer loss,
--      gamepad-grab CANCEL (order reverts) on gamepad loss, touch edit-mode
--      wedge reset to pure pointer, plus the CARRY rows.

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

-- =============================================================================
-- 1. BARE-TABLE COLUMN RESIZE via keyboard + gamepad Adjust (UI-PARADIGM-001)
-- =============================================================================
describe("paradigm_table: bare-Table column resize via keyboard/gamepad Adjust", function()
	local GRIP = "/S/T/Main/Header/Head-name/Grip" -- pointer drag target only
	local LAPS_HEAD_HANDLE = "/S/T/Main/Header/Head-laps/Column"
	local NAME_SORT = "/S/T/Main/Header/Head-name/Column"
	local NAME_HEAD = "/S/T/Main/Header/Head-name"

	local function resizeWorld()
		local core, _, adapter, system, pres = harness()
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
					title = "Name",
					width = { type = "fixed", px = 200 },
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
			sortOrder = sortOrder,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- ZERO opts: full auto-composition
		pres.refresh()
		return { system = system, adapter = adapter, pres = pres, handle = handle, tbl = tbl }
	end

	it("the headers group walks ONE stop per column (the column handle)", function()
		-- director 2026-07-29: the 4px divider is no longer a focus stop, so Right
		-- walks column-to-column instead of column -> its own divider.
		local w = resizeWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(LAPS_HEAD_HANDLE)
	end)

	it("no Adjust key is bound while focus sits off a RESIZABLE column (no bumper shadow)", function()
		-- every column has a handle now, so the guarantee is about the column being
		-- resizable, not about a divider existing: `laps` is fixed-width, so its
		-- header binds nothing
		local w = resizeWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT) -- the resizable column
		expect(#w.handle.actions.adjust.bindings > 0).toBe(true)
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(LAPS_HEAD_HANDLE)
		expect(#w.handle.actions.adjust.bindings).toBe(0)
		w.system.deviceKey("DPadLeft", true)
		w.system.deviceKey("DPadLeft", false)
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		expect(#w.handle.actions.adjust.bindings > 0).toBe(true)
	end)

	it("keyboard Comma/Period on the focused grip resize the column by the step", function()
		local w = resizeWorld()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(200)
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("Period", true) -- '.' increments one step (+16)
		w.system.deviceKey("Period", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(216)
		w.system.deviceKey("Comma", true) -- ',' decrements one step (-16)
		w.system.deviceKey("Comma", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(200)
	end)

	it("gamepad ButtonL1/ButtonR1 on the focused grip resize the column", function()
		local w = resizeWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		w.system.deviceKey("ButtonR1", true) -- R1 increments
		w.system.deviceKey("ButtonR1", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(216)
		w.system.deviceKey("ButtonL1", true) -- L1 decrements
		w.system.deviceKey("ButtonL1", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(200)
	end)

	-- ---- COLUMN SELECTION (director 2026-07-29) ---------------------------
	-- "focusable header, A selects the column and left/right resizes seems
	-- cleaner?" — it is, and it also gives column-wide verbs somewhere to live.
	it("A selects the focused column, then Left/Right resizes it", function()
		local w = resizeWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		expect(w.tbl.api.selectedColumn:get()).toBeNil()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(200)

		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedColumn:get()).toBe("name")

		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(216)
		-- ...and focus did NOT walk to the next column: the selection owns the stick
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)

		w.system.deviceKey("DPadLeft", true)
		w.system.deviceKey("DPadLeft", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(200)

		-- A again releases it, and Right walks columns once more
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedColumn:get()).toBeNil()
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(LAPS_HEAD_HANDLE)
	end)

	it("keyboard drives the same model: Return selects, arrows resize, Cancel releases", function()
		local w = resizeWorld()
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.tbl.api.selectedColumn:get()).toBe("name")
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(216)
		w.system.deviceKey("ButtonB", true) -- Cancel
		w.system.deviceKey("ButtonB", false)
		expect(w.tbl.api.selectedColumn:get()).toBeNil()
	end)

	it("a selected column cannot be left behind: moving focus off it releases it", function()
		local w = resizeWorld()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedColumn:get()).toBe("name")
		-- DPadDown leaves the headers group entirely (the selection swallows the
		-- stick, so this is the framework's own focus move, not a nav step)
		w.tbl.api.handleFocusMoved("/S/T/Main/Body/Rows/[r1@0]/Row/Hit")
		expect(w.tbl.api.selectedColumn:get()).toBeNil()
	end)

	it("resize clamps to the column minWidth", function()
		local w = resizeWorld()
		expect(w.pres.focus.focused:get()).toBe(NAME_SORT)
		-- drive well past the minimum (200 -> 80 is 8 steps; do 12)
		for _ = 1, 12 do
			w.system.deviceKey("Comma", true)
			w.system.deviceKey("Comma", false)
		end
		w.pres.refresh()
		expect(w.adapter.node(NAME_HEAD).rect.w).toBe(80)
	end)
end)

-- =============================================================================
-- 2. HOT-SWITCH in-flight transition semantics (matrix §C, UI-PARADIGM-002)
-- =============================================================================
describe("paradigm_table: hot-switch in-flight transitions (§C)", function()
	-- a REAL reorder consumer: applies the post-removal splice so a move/step
	-- mutates the data, and the revert on cancel is observable.
	local function reorderConsumer(rows: any, log: { any }): (any) -> ()
		return function(spec: any)
			spec.onReorder = function(keys: { string }, toIndex: number)
				table.insert(log, { keys = keys, toIndex = toIndex })
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
			end
		end
	end

	local function order(rows: any): { string }
		local out = {}
		for _, item in rows:get() do
			table.insert(out, item.id)
		end
		return out
	end

	local function hit(key: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/Row/Hit`
	end

	-- build a reorderable table with an explicit capability set + preferredInput.
	-- editing: nil => control-owned; a signal => owner-held.
	local function flipWorld(opts: any)
		local core, env, adapter, system, pres = harness()
		env:set("capabilities", opts.capabilities)
		env:set("preferredInput", opts.preferredInput or "Gamepad")
		local rows = core:signal(bigRows(opts.n or 4))
		local log: { any } = {}
		-- editingOwned => an OWNER-held signal (no auto Edit/Done toggle, so focus
		-- lands directly on r1 for the device-driven grab tests)
		local editing = if opts.editingOwned then core:signal(true) else opts.editing
		local spec: any = {
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
			selection = opts.selection or "single",
			rowHeight = 40,
			reorderable = true,
			editing = editing,
			env = env,
		}
		reorderConsumer(rows, log)(spec)
		local tbl = table_control.build(Facet, core, spec)
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen) -- zero opts
		pres.refresh()
		return {
			core = core,
			env = env,
			system = system,
			adapter = adapter,
			pres = pres,
			tbl = tbl,
			rows = rows,
			log = log,
			handle = handle,
			editing = editing,
		}
	end

	-- ---- CANCEL: pointer drag mid-flight, pointer capability goes away -------
	it("pointer drag mid-flight + pointer capability lost => CANCEL, revert, no reorder", function()
		local w = flipWorld({
			capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
			preferredInput = "KeyboardAndMouse",
		})
		local rowRect = w.adapter.node(hit("r1")).rect
		-- start a MOUSE row drag and cross the threshold (rows stay in place; a
		-- ghost + drop line come up)
		w.adapter.pointerDown(hit("r1"), rowRect.x + 10, rowRect.y + 5, "mouse")
		w.adapter.pointerMove(rowRect.x + 10, rowRect.y + 80, "mouse")
		w.pres.refresh()
		expect(w.adapter.node("/S/T/GhostWhen/then/DragGhost") ~= nil).toBe(true)
		-- the mouse is yanked mid-drag: no InputEnded can arrive
		w.env:set("capabilities", { keyboard = true, mouse = false, touch = true, gamepad = false })
		w.env:set("preferredInput", "Touch")
		w.pres.refresh()
		-- CANCEL: ghost/drop preview gone, and a late pointerUp commits nothing
		expect(w.adapter.node("/S/T/GhostWhen/then/DragGhost")).toBe(nil)
		w.adapter.pointerUp(rowRect.x + 10, rowRect.y + 80, "mouse")
		w.pres.refresh()
		expect(#w.log).toBe(0)
		expect(order(w.rows)).toEqual({ "r1", "r2", "r3", "r4" })
	end)

	-- ---- CANCEL: gamepad grab mid-grab, gamepad+touch go away ----------------
	it("gamepad grab mid-grab + gamepad capability lost => CANCEL, order reverts, grab cleared", function()
		local w = flipWorld({
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			preferredInput = "Gamepad",
			editingOwned = true, -- owner-held edit-mode: focus lands on r1
			n = 4,
		})
		-- focus a row, grab it, step it down once
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		w.system.deviceKey("ButtonA", true) -- grab r1
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.grabbedKey:get()).toBe("r1")
		w.system.deviceKey("DPadDown", true) -- step r1 below r2
		w.system.deviceKey("DPadDown", false)
		expect(order(w.rows)).toEqual({ "r2", "r1", "r3", "r4" })
		-- the pad disconnects mid-grab (touch not live either): no drop can arrive
		w.env:set("capabilities", { keyboard = false, mouse = true, touch = false, gamepad = false })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.pres.refresh()
		-- CANCEL: grab cleared AND the list order reverts to pre-grab
		expect(w.tbl.api.grabbedKey:get()).toBeNil()
		expect(order(w.rows)).toEqual({ "r1", "r2", "r3", "r4" })
	end)

	-- ---- CANCEL(reset): touch edit-mode, ALL of touch+gamepad leave ----------
	it(
		"control-owned edit-mode + all of touch/gamepad leave (pure pointer) => toggle unmounts AND editing resets (no wedge)",
		function()
			local w = flipWorld({
				capabilities = { keyboard = true, mouse = true, touch = true, gamepad = false },
				preferredInput = "Touch",
				editing = nil, -- control-owned editing signal
			})
			local togglePath = "/S/T/Main/ToggleWhen/then/Toolbar/EditToggle"
			expect(w.adapter.node(togglePath) ~= nil).toBe(true)
			-- enter edit mode: grips (≡ handles) mount
			w.tbl.api.handleActivate(togglePath, nil)
			w.pres.refresh()
			expect(w.tbl.api.editing:get()).toBe(true)
			expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle") ~= nil).toBe(true)
			-- go pure pointer: touch AND gamepad both gone
			w.env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			w.env:set("preferredInput", "KeyboardAndMouse")
			w.pres.refresh()
			-- the auto Edit/Done toggle unmounts (ADR-0015)…
			expect(w.adapter.node(togglePath)).toBe(nil)
			-- …AND the control-owned editing signal resets, so grips do not linger
			-- with no way to exit (the wedge this fixes)
			expect(w.tbl.api.editing:get()).toBe(false)
			expect(w.adapter.node("/S/T/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle")).toBe(nil)
		end
	)

	it("an OWNER-held editing signal is NOT reset by the control on a pure-pointer flip", function()
		local editing = nil
		local core, env, adapter, system, pres = harness()
		env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
		env:set("preferredInput", "Touch")
		local ownerEditing = core:signal(true)
		editing = ownerEditing
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
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "single",
			rowHeight = 40,
			reorderable = true,
			editing = ownerEditing,
			env = env,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		pres.present(screen)
		pres.refresh()
		env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
		env:set("preferredInput", "KeyboardAndMouse")
		pres.refresh()
		-- the owner's signal is the owner's business: never reset by the control
		expect(ownerEditing:get()).toBe(true)
		local _ = { system, adapter, editing }
	end)

	-- ---- CARRY rows ----------------------------------------------------------
	it("CARRY: edit-mode persists while gamepad stays live after touch leaves", function()
		local w = flipWorld({
			capabilities = { keyboard = false, mouse = false, touch = true, gamepad = true },
			preferredInput = "Touch",
			editing = nil,
		})
		local togglePath = "/S/T/Main/ToggleWhen/then/Toolbar/EditToggle"
		w.tbl.api.handleActivate(togglePath, nil)
		w.pres.refresh()
		expect(w.tbl.api.editing:get()).toBe(true)
		-- touch leaves, gamepad stays live
		w.env:set("capabilities", { keyboard = false, mouse = false, touch = false, gamepad = true })
		w.pres.refresh()
		expect(w.tbl.api.editing:get()).toBe(true) -- edit-mode CARRIES
		expect(w.adapter.node(togglePath) ~= nil).toBe(true) -- toggle still shown (gamepad)
	end)

	it("CARRY: a grabbed row keeps following Navigate when a pointer arrives (gamepad stays live)", function()
		local w = flipWorld({
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			preferredInput = "Gamepad",
			editingOwned = true, -- owner-held edit-mode: focus lands on r1
			n = 4,
		})
		expect(w.pres.focus.focused:get()).toBe(hit("r1"))
		w.system.deviceKey("ButtonA", true) -- grab r1
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.grabbedKey:get()).toBe("r1")
		-- a mouse arrives mid-grab; gamepad stays live
		w.env:set("capabilities", { keyboard = false, mouse = true, touch = false, gamepad = true })
		w.pres.refresh()
		expect(w.tbl.api.grabbedKey:get()).toBe("r1") -- grab CARRIES
		-- the grabbed row still follows Navigate
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(order(w.rows)).toEqual({ "r2", "r1", "r3", "r4" })
	end)

	it("CARRY: native scroll position survives a class flip", function()
		local w = flipWorld({
			capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
			preferredInput = "Touch",
			editing = nil,
			n = 20,
		})
		-- the body is a native ScrollingFrame: the ENGINE owns the offset. Wire the
		-- CanvasPosition mirror and drive an engine scroll (a touch fling), then flip.
		w.tbl.api.bindNativeScroll(w.handle.controller)
		w.adapter.driveScroll("/S/T/Main/Body", { x = 0, y = 120 })
		expect(w.adapter.node("/S/T/Main/Body").scrollPosition.y).toBe(120)
		-- flip classes: a keyboard + gamepad dock onto the handheld
		w.env:set("capabilities", { keyboard = true, mouse = false, touch = true, gamepad = true })
		w.pres.refresh()
		-- the engine-owned scroll position is untouched by the class flip (CARRY):
		-- no framework code resets CanvasPosition on a live-set change
		expect(w.adapter.node("/S/T/Main/Body").scrollPosition.y).toBe(120)
	end)
end)

-- =============================================================================
-- REGRESSION (live Studio drive 2026-07-21): a REORDERABLE table whose
-- selection is "none" still needs focusable rows — otherwise the only
-- focusable is the auto Edit/Done toggle, Navigate has nowhere to go (the
-- gamepad user is stranded on the toggle), and grab-mode reorder has no row
-- to grab: UI-PARADIGM-001 violated for the whole gamepad/keyboard class.
-- =============================================================================
describe("paradigm_table: reorderable + selection-none keeps rows reachable (live-drive regression)", function()
	local function noneWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(bigRows(3))
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
			env = env,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		pres.present(screen) -- zero opts
		pres.refresh()
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		return { pres = pres, press = press, tbl = tbl, reorders = reorders }
	end

	it("DPadDown leaves the auto Edit/Done toggle and reaches a row", function()
		local w = noneWorld()
		expect(w.pres.focus.focused:get()).toBe("/S/T/Main/ToggleWhen/then/Toolbar/EditToggle")
		w.press("DPadDown")
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe("/S/T/Main/Body/Rows/[r1@0]/Row/Hit")
	end)

	it("gamepad grab-mode reorders end to end with selection none", function()
		local w = noneWorld()
		w.tbl.api.editing:set(true)
		w.pres.refresh()
		w.press("DPadDown") -- toggle -> r1
		w.pres.refresh()
		w.press("ButtonA") -- grab r1
		w.press("DPadDown") -- step it one slot down
		w.pres.refresh()
		expect(#w.reorders).toBe(1)
		expect(w.reorders[1].keys[1]).toBe("r1")
	end)

	it("a selection-none NON-reorderable table keeps rows out of the ring (unchanged)", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(bigRows(2))
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
			env = env,
		})
		local screen = Facet.UI.Screen({
			id = "S",
			children = { tbl.blueprint, Facet.UI.Button({ id = "After", label = "After" }) },
		})
		pres.present(screen)
		pres.refresh()
		-- nothing in the table is focusable; entry focus goes to the button
		expect(pres.focus.focused:get()).toBe("/S/After")
	end)
end)

-- =============================================================================
-- Verifier finding RT-F2 (reactive-runtime review, 2026-07-21): a class flip
-- that fires the hot-switch observers followed by dispose must be
-- registry-neutral (the flip path allocates nothing it does not release).
-- =============================================================================
describe("paradigm_table: class-flip-then-dispose is registry-neutral", function()
	it("grab, rip the classes away (cancel fires), dispose: counters at baseline", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

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
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "none",
			rowHeight = 40,
			reorderable = true,
			env = env,
			onReorder = function() end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		tbl.api.editing:set(true)
		pres.refresh()
		press("DPadDown") -- toggle -> r1
		pres.refresh()
		press("ButtonA") -- grab
		-- mid-grab: gamepad AND keyboard leave -> grab-cancel observer fires
		env:set("capabilities", { keyboard = false, mouse = true, touch = false, gamepad = false })
		pres.refresh()
		pres.dismiss(handle)
		tbl.dispose()
		rows:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)

-- =============================================================================
-- 3. THE ROW BOX: PARADIGM-ADAPTIVE HEIGHT + THE CELL LINE CAP
--
-- Device report 2026-07-27 (a physical phone, Glossy Touch and Pixel Quest, the showcase's
-- playlist): a `rowHeight = 48` row with an UNCAPPED text cell. "Drift City
-- Nights" wrapped to three lines in the width a phone leaves the name column,
-- measured 54px, and painted through the rows either side of it. It did not
-- reproduce in the emulator, because turning two lines into three takes only a
-- few pixels of extra text width — which is the point: a fixed row with no line
-- cap has no slack, so ANY difference between emulator and device is damage.
--
-- Plus the director's standing ask from the same report: "we likely want taller
-- table cells on mobile for touch targeting. that seems like the paradigm
-- adaptation facet should handle."
-- =============================================================================
describe("paradigm_table: the row box adapts, and cells can never outgrow it", function()
	local LONG = "Drift City Nights Extended Club Mix"

	-- one narrow table, solved for real, reporting the row rect and the rect of
	-- the name cell's own text — the two numbers the defect was about
	local function solveRow(opts: any): any
		local core, env, adapter, system, pres = harness()
		env:set("viewportRect", { x = 0, y = 0, w = 393, h = 852 })
		local touch = opts.touch == true
		env:set("capabilities", { keyboard = not touch, mouse = not touch, touch = touch, gamepad = false })
		env:set("preferredInput", if touch then "Touch" else "KeyboardAndMouse")
		env:set("preferredTextOffset", opts.textOffset or 0)
		if opts.package ~= nil then
			-- the metric half of a package install, exactly as the theme picker
			-- commits it (ADR-0019 §7) — which is what makes a themed row solvable
			-- headlessly at all
			local pkg = require(`../examples/themes/{opts.package}`).build(Facet.themes)
			env:set("themeMetrics", Facet.themes.resolve(pkg, nil, {}))
		end
		local rows = core:signal({ { id = "drift", name = LONG } })
		local tbl = table_control.build(Facet, core, {
			id = "T",
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(i)
						return i.name
					end,
				},
				-- the two fixed columns that squeeze the name column on a phone
				{
					id = "len",
					title = "Length",
					width = { type = "fixed", px = 70 },
					value = function()
						return "3:07"
					end,
				},
				{
					id = "rate",
					title = "Rating",
					width = { type = "fixed", px = 144 },
					value = function()
						return "***"
					end,
				},
			},
			rows = rows,
			key = function(i)
				return i.id
			end,
			scrolls = false,
			header = true,
			rowHeight = opts.rowHeight,
			env = env,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", padding = 16, children = { tbl.blueprint } }))
		local rectOf = handle.controller.rectOf
		local base = "/S/T/Main/Body/Rows/[drift@0]/Row"
		local out = {
			row = rectOf(base),
			-- THE CELL, NOT JUST THE ROW (O-25). A row that is tall enough while its
			-- cell is not is exactly the defect: the cells spend the theme's
			-- `chromeInsets.selection` out of the row, so `text <= row` is satisfied
			-- by a cell nobody measured. Asserting the cell is what makes the check
			-- bite (mutation-proved 2026-08-14: with the art term removed from the
			-- derived height, `text <= row` still passed and `text <= cell` failed).
			cell = rectOf(base .. "/Cells/Cell-name"),
			text = rectOf(base .. "/Cells/Cell-name/Value"),
		}
		pres.dismiss(handle)
		tbl.dispose()
		rows:dispose()
		return out
	end

	it("a touch session gets a taller row than a pointer session, with no screen asking", function()
		local pointer = solveRow({ touch = false })
		local touch = solveRow({ touch = true })
		expect(touch.row.h > pointer.row.h).toBe(true)
		-- ...and the touch row clears the target floor the rest of the framework uses
		expect(touch.row.h >= 44).toBe(true)
	end)

	it("a raised text preference GROWS the row instead of spilling out of it", function()
		local plain = solveRow({ touch = true, textOffset = 0 })
		local large = solveRow({ touch = true, textOffset = 6 })
		local largest = solveRow({ touch = true, textOffset = 14 })
		expect(large.row.h > plain.row.h).toBe(true)
		expect(largest.row.h > large.row.h).toBe(true)
		for _, r in { plain, large, largest } do
			expect(r.text.h <= r.row.h).toBe(true)
		end
	end)

	it("a cell's text never exceeds its row — the device defect, at every text size", function()
		for _, touch in { false, true } do
			for _, offset in { 0, 6, 10, 14 } do
				local r = solveRow({ touch = touch, textOffset = offset })
				if r.text.h > r.row.h then
					error(
						`cell text {r.text.h}px overflowed a {r.row.h}px row (touch={tostring(touch)}, offset={offset})`
					)
				end
			end
		end
	end)

	it("a PINNED rowHeight still wins — and its cells are capped to it, not to the derived row", function()
		-- the shape the playlist example shipped with, at the shipped text size
		local pinned = solveRow({ touch = true, rowHeight = 48 })
		expect(pinned.row.h).toBe(48)
		-- shorter than the row the framework would have derived for touch+Largest,
		-- which is the point: the pin wins and the CAP moves instead
		local squeezed = solveRow({ touch = true, textOffset = 14, rowHeight = 48 })
		expect(squeezed.row.h).toBe(48)
		expect(squeezed.text.h <= 48).toBe(true)
		-- a per-item function is honoured the same way, cap and all
		local fn = solveRow({
			touch = true,
			rowHeight = function()
				return 34
			end,
		})
		expect(fn.row.h).toBe(34)
		expect(fn.text.h <= 34).toBe(true)
	end)

	--[[ O-25, measured 2026-08-14 by the overflow sweep's theme axis.

		THE ROW'S OWN ART IS ROOM THE CELLS NEVER GET. A row is a full-bleed hit
		Button whose painted card is a DIFFERENT node from its cells, so the cells
		spend `chromeInsets.selection` as their own padding (`ROW_ART` in
		src/controls/table.luau) — while the height the row was derived at counted
		only its text and its `rowPadding`. Under Pixel Quest, which carves 16px on
		all four sides, that left a 48px row handing its cells 16px for a 20px line:
		4px of text outside its own cell, in every row, on every viewport, AT THE
		DEFAULT TEXT PREFERENCE. Studio Neutral and Classic Desktop reserve nothing,
		which is exactly why every check in this repo was silent on it.

		The two cases below are the same question from both ends: the derived row
		must GROW by the art, and the flat packages must not move by a pixel.
	]]
	it("a package that carves a border GROWS the row — the cell never pays for the frame", function()
		for _, package in { "pixel_quest", "glossy_touch", "fantasy_ornate", "compact_pointer" } do
			for _, touch in { false, true } do
				for _, offset in { 0, 4, 10, 14 } do
					local r = solveRow({ touch = touch, textOffset = offset, package = package })
					if r.text.h > r.cell.h then
						error(
							`under {package}, cell text {r.text.h}px overflowed a {r.cell.h}px CELL `
								.. `in a {r.row.h}px row (touch={tostring(touch)}, offset={offset})`
						)
					end
				end
			end
		end
	end)

	it("...and a FLAT package's rows are byte-identical to the untethered ones", function()
		-- the other half of the fix's claim: `chromeInsets.selection` is zero for
		-- every flat package, so the art term is zero and nothing moves
		for _, package in { "classic_desktop", "scifi_hud" } do
			for _, touch in { false, true } do
				local themed = solveRow({ touch = touch, package = package })
				-- a flat package reserves nothing, so the cell IS the row and the
				-- art term is zero — the arithmetic reduces to what it always was
				expect(themed.cell.h).toBe(themed.row.h)
				expect(themed.text.h <= themed.cell.h).toBe(true)
			end
		end
	end)

	it("a pin below ONE LINE of its own text is raised to it, never drawn through", function()
		-- 34px was fine at the shipped size and is not at Largest: one line of 29px
		-- cell text is 35px tall, and the cap floors at one line because a limit is
		-- not an eraser. So the row takes the line rather than the line taking the row.
		local r = solveRow({ touch = true, textOffset = 14, rowHeight = 34 })
		expect(r.row.h > 34).toBe(true)
		expect(r.text.h <= r.row.h).toBe(true)
	end)
end)

-- =============================================================================
-- 4. A SURFACE-LEVEL onGeometry DOES NOT SWITCH OFF THE CONTROLS ON THAT SURFACE
--
-- `opts.onGeometry` used to WIN OUTRIGHT and skip every contribution's own
-- `syncGeometry` — so a screen that merely asked where one of its nodes landed
-- silently disabled the Table's keyboard/gamepad scroll-into-view, and any
-- TextInput's keep-visible, on that surface. The parity reference had it written
-- down as a footgun; the showcase chrome then needed exactly that callback to
-- measure its own chip row. Geometry is a notification, not a routing decision,
-- so both are fed now.
-- =============================================================================
describe("paradigm_table: a surface onGeometry is additive, not an override", function()
	local contribution = require("../src/input/contribution")

	-- a minimal control: one node carrying a contribution whose ONLY job is to
	-- record that the presenter fed it. Deliberately not the Table itself — the
	-- claim is about the presenter's seam, and a bare bundle asserts it directly.
	local function world(withOnGeometry: boolean): any
		local core, _, _, _, pres = harness()
		local fed = { count = 0 }
		local surface = { count = 0 }
		local node = contribution.attach(
			Facet.UI.Box({ id = "Probe", width = { type = "fixed", px = 10 }, height = { type = "fixed", px = 10 } }),
			{
				syncGeometry = function()
					fed.count += 1
				end,
			}
		)
		local opts: any = {}
		if withOnGeometry then
			opts.onGeometry = function()
				surface.count += 1
			end
		end
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { node } }), opts)
		pres.refresh()
		return { pres = pres, handle = handle, fed = fed, surface = surface }
	end

	it("a contribution is fed with no surface hook (today's behaviour, unchanged)", function()
		local w = world(false)
		expect(w.fed.count > 0).toBe(true)
		expect(w.surface.count).toBe(0)
		w.pres.dismiss(w.handle)
	end)

	it("...and is STILL fed when the surface asks for geometry of its own", function()
		local w = world(true)
		expect(w.surface.count > 0).toBe(true) -- the surface got its feed...
		expect(w.fed.count > 0).toBe(true) -- ...and the control on it kept its own
		w.pres.dismiss(w.handle)
	end)
end)

-- =============================================================================
-- 5. A `themeMetrics` SNAPSHOT WITHOUT THE DERIVED ROW KEYS FALLS BACK (§8.2)
--
-- The row box reads `controls.table.rowHeight` / `.rowLines` / `.rowPadding`,
-- which `snapshot.resolve` DERIVES — so every package compiled through the public
-- path answers them. A metrics table assembled some other way (an older stored
-- snapshot, a hand-built one in a consumer's test) has the family and not those
-- keys, and §8.2's rule is that the seam reading a fact must not be the thing
-- that breaks when the fact is wrong. It falls back to neutral, exactly as the
-- presenter's `metricsNow` does.
--
-- SCOPE, stated honestly: this is the Table's own guard. A metrics fact broken
-- MORE than this (no `type` roles at all) still takes the renderer down at its
-- own read — a wider gap than this change owns, and not one it introduces.
-- =============================================================================
describe("paradigm_table: a metrics snapshot missing the derived row keys falls back", function()
	local themeSnapshot = require("../src/themes/snapshot")

	local function without(keys: { string }): any
		local base = themeSnapshot.neutral()
		local copy: any = {}
		for k, v in base do
			copy[k] = v
		end
		local controls: any = {}
		for k, v in base.controls do
			controls[k] = v
		end
		local family: any = {}
		for k, v in base.controls.table do
			family[k] = v
		end
		for _, k in keys do
			family[k] = nil
		end
		controls.table = family
		copy.controls = controls
		return copy
	end

	local CASES = {
		{ label = "no rowHeight", metrics = without({ "rowHeight" }) },
		{ label = "no rowLines", metrics = without({ "rowLines" }) },
		{ label = "no rowPadding", metrics = without({ "rowPadding" }) },
		{ label = "none of the three", metrics = without({ "rowHeight", "rowLines", "rowPadding" }) },
	}

	it("still solves a real row, at neutral's own derived height", function()
		local expected: number? = nil
		for _, case in CASES do
			local core, env, _, _, pres = harness()
			env:set("themeMetrics", case.metrics)
			local rows = core:signal({ { id = "a", name = "Neon Straightaway" } })
			local tbl = table_control.build(Facet, core, {
				id = "T",
				rows = rows,
				key = function(i: any)
					return i.id
				end,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(i: any)
							return i.name
						end,
					},
				},
				scrolls = false,
				env = env,
			})
			local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
			local r = handle.controller.rectOf("/S/T/Main/Body/Rows/[a@0]/Row")
			if r == nil or r.h <= 0 then
				error(`{case.label}: no solved row`)
			end
			-- every broken shape lands on the SAME height: the neutral fallback,
			-- not some half-resolved number
			expected = expected or r.h
			expect(r.h).toBe(expected)
			pres.dismiss(handle)
			tbl.dispose()
			rows:dispose()
		end
	end)

	it("a NaN typography scale or text offset does not produce a NaN row", function()
		local core, env, _, _, pres = harness()
		env:set("preferredTextSize", 0 / 0)
		env:set("preferredTextOffset", 0 / 0)
		local rows = core:signal({ { id = "a", name = "Neon Straightaway" } })
		local tbl = table_control.build(Facet, core, {
			id = "T",
			rows = rows,
			key = function(i: any)
				return i.id
			end,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(i: any)
						return i.name
					end,
				},
			},
			scrolls = false,
			env = env,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		local r = handle.controller.rectOf("/S/T/Main/Body/Rows/[a@0]/Row")
		expect(r ~= nil).toBe(true)
		expect(r.h == r.h).toBe(true) -- not NaN
		expect(r.h > 0).toBe(true)
		pres.dismiss(handle)
		tbl.dispose()
		rows:dispose()
	end)
end)
