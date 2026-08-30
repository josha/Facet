--!strict
-- Auto input-wiring tests (ui_todo §0). Proves the presenter
-- AUTO-COMPOSES a mounted control's four-input story from the input-contribution
-- bundles the composites attach to their root nodes — with NO consumer present()
-- wiring. Every interaction goes through the REAL device paths (adapter.tap for
-- pointer/touch, system.deviceKey for keyboard/gamepad), never a direct callback.
-- The back-compat rule is spot-checked too: any consumer-passed opt overrides its
-- auto counterpart, per-opt.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local text_input = require("../src/controls/text_input")
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

-- ===========================================================================
describe("auto-input: Button props.onActivate fires on every input, no consumer wiring", function()
	local BTN = "/S/Go"
	local function buttonWorld()
		local core, _, adapter, system, pres = harness()
		local hits: { any } = {}
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Button({
					id = "Go",
					label = "Go",
					onActivate = function(path, meta)
						table.insert(hits, { path = path, meta = meta })
					end,
				}),
			},
		})
		local handle = pres.present(screen) -- ZERO present opts
		pres.refresh()
		return { core = core, system = system, adapter = adapter, pres = pres, hits = hits, handle = handle }
	end

	it("pointer tap activates the Button through its onActivate prop", function()
		local w = buttonWorld()
		w.adapter.tap(BTN)
		expect(#w.hits).toBe(1)
		expect(w.hits[1].path).toBe(BTN)
	end)

	it("keyboard Return activates the focused Button", function()
		local w = buttonWorld()
		expect(w.pres.focus.focused:get()).toBe(BTN) -- auto-focused first focusable
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(#w.hits).toBe(1)
		expect(w.hits[1].meta.source).toBe("action")
	end)

	it("gamepad ButtonA activates the focused Button", function()
		local w = buttonWorld()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(#w.hits).toBe(1)
	end)

	it("Button touch: a finger tap activates through the auto dispatch", function()
		local w = buttonWorld()
		-- a real finger tap: the engine's Activated meta carries pointer = "touch"
		-- (ScreenTarget builds it from a Touch UserInputType — screen_target.luau
		-- L561-563); mirror that meta exactly. A plain adapter.tap(path) passes
		-- meta = nil, which the framework treats as mouse — so the touch-typed
		-- distinction here is genuine: the seam sees meta.pointer == "touch".
		w.adapter.tap(BTN, { source = "pointer", pointer = "touch" })
		expect(#w.hits).toBe(1)
		expect(w.hits[1].path).toBe(BTN)
		expect(w.hits[1].meta.pointer).toBe("touch")
	end)
end)

-- ===========================================================================
describe("auto-input: Toggle auto-flips its bound value (contract §10.2)", function()
	local TOG = "/S/Mute"
	local function toggleWorld()
		local core, _, adapter, system, pres = harness()
		local value = core:signal(false)
		local screen = Facet.UI.Screen({
			id = "S",
			children = { Facet.UI.Toggle({ id = "Mute", label = "Mute", value = value }) },
		})
		local handle = pres.present(screen) -- ZERO present opts
		pres.refresh()
		return { core = core, system = system, adapter = adapter, pres = pres, value = value, handle = handle }
	end

	it("pointer tap flips the value", function()
		local w = toggleWorld()
		expect(w.value:get()).toBe(false)
		w.adapter.tap(TOG)
		expect(w.value:get()).toBe(true)
		w.adapter.tap(TOG)
		expect(w.value:get()).toBe(false)
	end)

	it("focused Activate (Return) flips the value", function()
		local w = toggleWorld()
		expect(w.pres.focus.focused:get()).toBe(TOG)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.value:get()).toBe(true)
	end)

	it("Toggle touch: a finger tap flips the value", function()
		local w = toggleWorld()
		expect(w.value:get()).toBe(false)
		-- touch-typed activation: the engine's Activated meta on a Touch input
		-- carries pointer = "touch" (screen_target.luau L561-563), distinct from
		-- the mouse path (meta = nil / pointer = "mouse"). Same flip either way,
		-- but the seam genuinely sees a touch pointer here.
		w.adapter.tap(TOG, { source = "pointer", pointer = "touch" })
		expect(w.value:get()).toBe(true)
		w.adapter.tap(TOG, { source = "pointer", pointer = "touch" })
		expect(w.value:get()).toBe(false)
	end)

	it("Toggle gamepad: ButtonA on the focused Toggle flips the value", function()
		local w = toggleWorld()
		expect(w.pres.focus.focused:get()).toBe(TOG) -- auto-focused sole focusable
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.value:get()).toBe(true)
	end)
end)

-- ===========================================================================
-- The headline case: a Table + a TextInput on one screen, presented with ZERO
-- nav/activate/geometry/keep-visible opts — reproducing example 02's hand-wired
-- behavior with none of the wiring.
describe("auto-input: Table + TextInput on one screen, zero present opts", function()
	local FIELD = "/S/Filter/Field"
	local function rowHit(key: string): string
		return `/S/Rows/Main/Body/Rows/[{key}@0]/Row/Hit`
	end

	local function world(opts: any?)
		local options = opts or {}
		local core, env, adapter, system, pres = harness()
		local fieldValue = core:signal("")
		local ti = text_input.build(Facet, core, {
			id = "Filter",
			value = fieldValue,
			env = env,
			-- NOTE: no actionSystem injected — the presenter must bind it (auto)
		})
		local rows = core:signal({
			{ id = "a", name = "Alpha" },
			{ id = "b", name = "Beta" },
			{ id = "c", name = "Gamma" },
		})
		local editing = core:signal(options.editing == true)
		local reorders: { any } = {}
		local tbl = table_control.build(Facet, core, {
			id = "Rows",
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
			editing = editing,
			onReorder = function(block: any, slot: any)
				table.insert(reorders, { block = block, slot = slot })
			end,
			env = env,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { ti.blueprint, tbl.blueprint } })
		local presOpts = options.present -- may be nil (zero opts)
		local handle = pres.present(screen, presOpts)
		pres.refresh()
		return {
			core = core,
			env = env,
			system = system,
			adapter = adapter,
			pres = pres,
			ti = ti,
			tbl = tbl,
			rows = rows,
			editing = editing,
			reorders = reorders,
			handle = handle,
			fieldValue = fieldValue,
		}
	end

	it("initial focus lands on the field (auto-merged groups, field first)", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(FIELD)
	end)

	it("D-pad navigates field -> rows and back (auto-merged focus groups)", function()
		local w = world()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("a"))
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("b"))
		-- back up to the field: row b -> row a -> field
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		expect(w.pres.focus.focused:get()).toBe(FIELD)
	end)

	it("gamepad A selects the focused row (auto contribution dispatch)", function()
		local w = world() -- editing off: A selects
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false) -- focus row a
		expect(w.pres.focus.focused:get()).toBe(rowHit("a"))
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.selectedKeys:get().a).toBe(true)
	end)

	it("grab mode moves a row via auto navigateIntercept (A grabs, D-pad steps)", function()
		local w = world({ editing = true })
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false) -- focus row a
		expect(w.pres.focus.focused:get()).toBe(rowHit("a"))
		-- A grabs the focused row (editing mode + action source)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.tbl.api.grabbedKey:get()).toBe("a")
		-- D-pad down now MOVES the grabbed row instead of focus (navigateIntercept)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(#w.reorders).toBe(1)
		expect(w.reorders[1].block[1]).toBe("a")
		expect(w.reorders[1].slot).toBe(1) -- moved one slot down
	end)

	it("typing in the field does not navigate (auto bindActionSystem sink)", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(FIELD)
		-- A enters edit mode on the field (contribution dispatch -> handleActivate)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.ti.api.editing:get()).toBe(true)
		-- D-pad down must be swallowed by the field's edit-mode sink, not navigate
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(FIELD) -- focus did NOT move to a row
	end)

	it("field geometry + keep-visible engage automatically (auto syncGeometry + keepVisibleOffset)", function()
		local w = world()
		-- enter editing so the keep-visible policy is active
		w.adapter.tap(FIELD)
		expect(w.ti.api.editing:get()).toBe(true)
		local rect = w.handle.controller.rectOf(FIELD)
		expect(rect ~= nil).toBe(true)
		-- keyboard rises to overlap the field's lower edge
		local keyboardTop = rect.y + rect.h - 20
		w.env:set("keyboardOcclusionRect", { x = 0, y = keyboardTop, w = 800, h = 600 - keyboardTop })
		-- the control publishes a positive offset (proves syncGeometry fed the rect)
		expect(w.ti.api.keepVisibleOffset:get()).toBeGreaterThan(0)
		-- and the presenter applied it to the screen root (proves auto keepVisibleOffset)
		expect(w.adapter.node("/S").props.transform ~= nil).toBe(true)
		expect(w.adapter.node("/S").props.transform.y).toBeLessThan(0)
	end)
end)

-- ===========================================================================
describe("auto-input: per-opt override (consumer opt beats its auto counterpart)", function()
	it("an explicit opts.onActivate suppresses auto activate dispatch entirely", function()
		local core, _, adapter, _, pres = harness()
		local propHits = 0
		local optHits: { any } = {}
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Button({
					id = "Go",
					label = "Go",
					onActivate = function()
						propHits += 1 -- must NOT fire when opts.onActivate is present
					end,
				}),
			},
		})
		pres.present(screen, {
			onActivate = function(path)
				table.insert(optHits, path)
			end,
		})
		pres.refresh()
		adapter.tap("/S/Go")
		expect(#optHits).toBe(1)
		expect(optHits[1]).toBe("/S/Go")
		expect(propHits).toBe(0) -- the prop path was fully suppressed by the opt
	end)

	it("navigationGroups=false forces the legacy flat ring (auto grouping suppressed)", function()
		-- a resizable Table's header grip is only reachable through the FLAT ring
		-- (its buildFocusGroups omits the grip); forcing flat proves the override.
		local core, env, adapter, system, pres = harness()
		local rows = core:signal({ { id = "a", name = "Alpha" }, { id = "b", name = "Beta" } })
		local tbl = table_control.build(Facet, core, {
			id = "Racers",
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
					value = function(r: any)
						return r.name
					end,
					resizable = true,
				},
			},
			selection = "single",
			rowHeight = 40,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		pres.present(screen, { navigationGroups = false })
		pres.refresh()
		-- the flat ring is TREE order, and the column handle is a header: it leads
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		for _ = 1, 2 do
			system.deviceKey("Down", true)
			system.deviceKey("Down", false)
		end
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Body/Rows/[b@0]/Row/Hit")
		local _ = env
		local _ = adapter
	end)
end)

-- ===========================================================================
describe("auto-input: refresh re-derives auto groups after structural change", function()
	it("a row added after present becomes reachable through the auto groups", function()
		local core, env, adapter, system, pres = harness()
		local rows = core:signal({ { id = "a", name = "Alpha" }, { id = "b", name = "Beta" } })
		local tbl = table_control.build(Facet, core, {
			id = "Rows",
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
			editing = core:signal(false),
			reorderable = true,
			onReorder = function() end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		pres.present(screen) -- zero opts
		pres.refresh()
		-- add a third row
		rows:set({
			{ id = "a", name = "Alpha" },
			{ id = "b", name = "Beta" },
			{ id = "c", name = "Gamma" },
		})
		pres.refresh() -- auto groups re-derived here
		-- navigate to the last row: a -> b -> c
		expect(pres.focus.focused:get()).toBe("/S/Rows/Main/Body/Rows/[a@0]/Row/Hit")
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		expect(pres.focus.focused:get()).toBe("/S/Rows/Main/Body/Rows/[c@0]/Row/Hit")
		local _ = env
		local _ = adapter
	end)
end)

-- ===========================================================================
describe("auto-input: registry neutrality of the contribution seam", function()
	it("build/mount/present/interact/dispose returns every registry to baseline", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local fieldValue = core:signal("")
		local ti = text_input.build(Facet, core, { id = "Filter", value = fieldValue, env = env })
		local rows = core:signal({ { id = "a", name = "Alpha" }, { id = "b", name = "Beta" } })
		local editing = core:signal(false)
		local tbl = table_control.build(Facet, core, {
			id = "Rows",
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
			editing = editing,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { ti.blueprint, tbl.blueprint } })
		local handle = pres.present(screen) -- zero opts: full auto-composition
		pres.refresh()

		-- exercise the auto paths: navigate, activate-to-edit, occlude, type
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		adapter.focusText("/S/Filter/Field")
		adapter.typeText("/S/Filter/Field", "ab")
		env:set("keyboardOcclusionRect", { x = 0, y = 0, w = 800, h = 600 })

		pres.dismiss(handle)
		ti.dispose()
		tbl.dispose()
		fieldValue:dispose()
		rows:dispose()
		editing:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)
