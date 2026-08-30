--!strict
-- Named benchmark scenario registry (design §14.3). Each scenario:
--   { name: string, requirement: string, setup: () -> any,
--     run: (state: any) -> (), teardown: ((state: any) -> ())? }
-- run() is one iteration; the runner handles warmup/sampling/percentiles.
-- Phase 0 contents: the foundation bake-off — the same three workloads
-- (HUD binding storm, settings open/close churn, keyed collection mutation)
-- on each core candidate. Numbers feed the rubric's update-cost/allocation
-- axes (headless trend data; device authoritative per §14.3).
--
-- THE ARMS ARE `custom` (the core Facet ships) AND `imperative` (the retained
-- recompute-all baseline, `bench/cores/imperative.luau`). The baseline lives
-- beside this file rather than in `src/` because it is a development fixture:
-- the model builder maps `src/`, so anything under it would ship. A comparison
-- between two cores is only honest while both run the identical workload, which
-- is why the loop below builds every scenario once per arm.

local factories = {
	custom = require("../src/core/custom"),
	imperative = require("./cores/imperative"),
}

export type Scenario = {
	name: string,
	requirement: string,
	setup: () -> any,
	run: (state: any) -> (),
	teardown: ((state: any) -> ())?,
}

local scenarios: { Scenario } = {}

for coreName, factory in factories :: { [string]: any } do
	-- 1. live HUD binding storm: 100 independent writes through a 3-deep
	-- memo chain with a render observer (worst-case unbatched updates)
	table.insert(scenarios, {
		name = `hud-binding-storm-{coreName}`,
		requirement = "UI-PERF-001",
		setup = function()
			local core = factory.new()
			local speed = core:signal(0)
			local rounded = core:memo(function(use)
				return math.floor(use(speed))
			end)
			local label = core:memo(function(use)
				return `{use(rounded)} sps`
			end)
			local renders = 0
			core:observe(label, function()
				renders += 1
			end)
			return { core = core, speed = speed, n = 0 }
		end,
		run = function(state)
			state.n += 1
			local base = state.n * 100
			for i = 1, 100 do
				state.speed:set(base + i)
			end
		end,
	})

	-- 2. settings open/close churn: full mount(scope+graph+observer)/unmount
	table.insert(scenarios, {
		name = `settings-churn-{coreName}`,
		requirement = "UI-LIFE-002",
		setup = function()
			return { core = factory.new() }
		end,
		run = function(state)
			local core = state.core
			local scope = core:scope("row")
			local draft = scope:own(core:signal(false))
			local status = scope:own(core:signal("idle"))
			local label = scope:own(core:memo(function(use)
				return `music: {use(draft) and "on" or "off"} ({use(status)})`
			end))
			scope:own(core:observe(label, function() end))
			draft:set(true)
			status:set("confirmed")
			scope:dispose()
		end,
	})

	-- 3. keyed collection mutation: 50 keyed item scopes; one move + one
	-- add/remove per iteration (ForEach-at-core-scale)
	table.insert(scenarios, {
		name = `collection-mutation-{coreName}`,
		requirement = "UI-RUNTIME-002",
		setup = function()
			local core = factory.new()
			local root = core:scope("collection")
			local items: { [string]: any } = {}
			local function apply(keys: { string })
				local wanted: { [string]: boolean } = {}
				for _, k in keys do
					wanted[k] = true
				end
				for k, item in items do
					if not wanted[k] then
						item:dispose()
						items[k] = nil
					end
				end
				for _, k in keys do
					if items[k] == nil then
						local itemScope = root:child(k)
						itemScope:own(core:signal(k))
						items[k] = itemScope
					end
				end
			end
			local keys = {}
			for i = 1, 50 do
				table.insert(keys, `item-{i}`)
			end
			apply(keys)
			return { core = core, apply = apply, keys = keys, n = 50 }
		end,
		run = function(state)
			-- move: rotate first to last; churn: replace one key
			local keys = state.keys
			table.insert(keys, table.remove(keys, 1) :: string)
			state.n += 1
			keys[#keys] = `item-{state.n}`
			state.apply(keys)
		end,
	})
	-- 4. sparse update under load: 200 independent signal->memo->observer
	-- chains alive; ONE signal written per iteration. Separates O(affected)
	-- cores from O(all-live-derivations) recompute-all (the honest
	-- "update cost" axis for the rubric).
	table.insert(scenarios, {
		name = `sparse-update-under-load-{coreName}`,
		requirement = "UI-PERF-001",
		setup = function()
			local core = factory.new()
			local signals = {}
			for i = 1, 200 do
				local s = core:signal(i)
				local m = core:memo(function(use)
					return use(s) * 2
				end)
				core:observe(m, function() end)
				table.insert(signals, s)
			end
			return { core = core, signals = signals, n = 0 }
		end,
		run = function(state)
			state.n += 1
			state.signals[1]:set(1000 + state.n)
		end,
	})
end

-- Phase 1: full mounted-slice update storm (blueprint -> mount -> render ->
-- fake adapter), the production-shaped hot path
local Facet = require("../src")
local fake_target = require("../tests/lib/fake_target")
table.insert(scenarios, {
	name = "mounted-slice-update-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local speed = core:signal(0)
		local label = core:memo(function(use)
			return `{use(speed)} sps`
		end)
		pres.present(Facet.UI.Screen({
			id = "Hud",
			children = {
				Facet.UI.Text({ id = "Speed", text = label, textSize = 18 }),
				Facet.UI.Button({ id = "Boost", label = "Boost" }),
			},
		}))
		return { core = core, pres = pres, speed = speed, n = 0 }
	end,
	run = function(state)
		state.n += 1
		local base = state.n * 50
		for i = 1, 50 do
			state.speed:set(base + i)
		end
		state.pres.refresh()
	end,
})

-- Table (ADR-0007): row churn + committed resize on the composite control
local table_control = require("../src/controls/table")
table.insert(scenarios, {
	name = "table-mutation",
	requirement = "UI-PERF-001",
	setup = function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal({})
		local items = {}
		for i = 1, 8 do
			table.insert(items, { id = `r{i}`, name = `Racer {i}` })
		end
		rows:set(items)
		local tbl = table_control.build(Facet, core, {
			id = "Bench",
			columns = {
				{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
				{ id = "n", width = { type = "fixed", px = 48 } },
			},
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(columnId, item)
				return Facet.UI.Text({ id = "V", text = item.name, textSize = 14 })
			end,
			rowHeight = 40,
			header = false,
			selection = "multi",
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		return { core = core, pres = pres, rows = rows, tbl = tbl, items = items, n = 8 }
	end,
	run = function(state)
		-- one row replaced + one selection toggle + refresh (the hot loop)
		state.n += 1
		local items = table.clone(state.items)
		items[((state.n - 1) % 8) + 1] = { id = `r{state.n}`, name = `Racer {state.n}` }
		state.items = items
		state.rows:set(items)
		state.tbl.api.select(`r{state.n}`)
		state.pres.refresh()
	end,
})

-- Table Phase B (ADR-0008): a full grip drag gesture — pointer down, eight
-- preview moves (arrange-only re-solves of the guide line), release commit
table.insert(scenarios, {
	name = "table-resize-drag",
	requirement = "UI-PERF-001",
	setup = function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local items = {}
		for i = 1, 8 do
			table.insert(items, { id = `r{i}`, name = `Racer {i}` })
		end
		local rows = core:signal(items)
		local tbl = table_control.build(Facet, core, {
			id = "Bench",
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
				},
				{ id = "n", title = "N", width = { type = "fixed", px = 48 } },
			},
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return Facet.UI.Text({ id = "V", text = item.name, textSize = 14 })
			end,
			rowHeight = 40,
			header = true,
			selection = "none",
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		return { pres = pres, adapter = adapter, n = 0 }
	end,
	run = function(state)
		state.n += 1
		local gripPath = "/S/Bench/Main/Header/Head-name/Grip"
		-- alternate direction so committed widths oscillate instead of pinning
		local dir = if state.n % 2 == 0 then 1 else -1
		state.adapter.pointerDown(gripPath, 600, 10)
		for i = 1, 8 do
			state.adapter.pointerMove(600 + dir * i * 5, 10)
			state.pres.refresh()
		end
		state.adapter.pointerUp(600 + dir * 40, 10)
		state.pres.refresh()
	end,
})

-- BillboardTarget canvas (ADR-0009): a nameplate on a 300x96 pixel canvas —
-- the world-UI hot path is many small canvases taking frequent text updates
table.insert(scenarios, {
	name = "billboard-nameplate-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 96 })
		local adapter = fake_target.new()
		local health = core:signal("100")
		local root = Facet.mount(
			core,
			Facet.UI.Screen({
				id = "Nameplate",
				padding = 8,
				gap = 4,
				children = {
					Facet.UI.Text({ id = "Name", text = "Racer", textSize = 18 }),
					Facet.UI.Text({ id = "Health", text = health, textSize = 14 }),
				},
			})
		)
		local controller = Facet.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		return { controller = controller, health = health, n = 0 }
	end,
	run = function(state)
		state.n += 1
		for i = 1, 50 do
			state.health:set(tostring((state.n * 50 + i) % 100))
		end
		state.controller.refresh()
	end,
})

-- TextInput (§17 Phase 5): a typing storm — N graphemes per iteration driven
-- through the REAL adapter text seam (focusText + typeText, exactly what the
-- engine TextBox adapter feeds back). The point of the value model is that a
-- keystroke is paint/semantic writes, never a remount: the scenario asserts the
-- field's factory-run counter never moves. It reverts (cancel) each iteration
-- so the value stays bounded and the workload is deterministic.
local text_input_control = require("../src/controls/text_input")
table.insert(scenarios, {
	name = "textinput-typing-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local value = core:signal("")
		local control = text_input_control.build(Facet, core, {
			id = "Storm",
			value = value,
			placeholder = "type",
			maxLength = 64,
			env = env,
			actionSystem = system,
			onChange = function() end,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }), {
			sinkNavigation = true,
			onActivate = function(path, meta)
				control.api.handleActivate(path, meta)
			end,
			onGeometry = function(rectOf)
				control.api.syncGeometry(rectOf)
			end,
			keepVisibleOffset = control.api.keepVisibleOffset,
		})
		pres.refresh()
		return {
			pres = pres,
			adapter = adapter,
			handle = handle,
			field = "/S/Storm/Field",
			baselineRuns = handle.root.counters().factoryRuns,
		}
	end,
	run = function(state)
		state.adapter.tap(state.field) -- enter editing
		state.adapter.focusText(state.field) -- engine focus: seed the buffer
		state.adapter.typeText(state.field, "The quick brown fox 0123") -- 24 graphemes
		state.pres.refresh()
		assert(
			state.handle.root.counters().factoryRuns == state.baselineRuns,
			"textinput-typing-storm: the field remounted during typing (factoryRuns moved)"
		)
		state.adapter.cancelText(state.field) -- revert to "" and end editing
		state.pres.refresh()
	end,
})

-- ===========================================================================
-- THE YARDSTICK (verifier PG-3 follow-up, 2026-07-28)
-- ===========================================================================
-- Every other scene is measured in wall-clock milliseconds against numbers
-- frozen on one machine, at one moment, under one load. That is not a stable
-- instrument on a developer laptop: the SAME source measured 1.29x with the
-- machine quiet, 1.40x mid gate-batch and 1.54x with Roblox Studio open, and a
-- gate went red for none of those reasons. Raising the factor would only trade
-- false alarms for a real 2x slipping through.
--
-- So the runner divides every scene by THIS one, measured in the SAME run on
-- the SAME machine, and compares the ratio instead of the milliseconds. A slow
-- day makes both numbers rise together and the ratio holds still.
--
-- Requirements this workload has to meet, and why:
--   * NO Facet code. It must move when the machine moves and never when the
--     library changes, or it would mask the very regressions it exists to
--     expose. Nothing here requires anything from src/.
--   * Above REGRESSION_FLOOR_MS (0.05ms) by a comfortable margin, so it is not
--     itself dominated by scheduler jitter — a noisy divisor would inject noise
--     into all 12 scenes at once.
--   * Deterministic and allocation-light: fixed trip counts, one reused table,
--     no os.clock/os.time, no randomness, no growth across iterations.
--   * A mix of float arithmetic, integer/modulo work and table read-modify-write
--     — roughly the instruction blend the real scenes lean on, so it tracks the
--     machine the way they do rather than measuring one narrow unit.
table.insert(scenarios, {
	name = "zz-yardstick-cpu",
	requirement = "UI-PERF-001",
	setup = function()
		-- allocated once, reused every iteration: the yardstick measures CPU,
		-- not the allocator, and must not drift as the heap fills
		return { buf = table.create(256, 0) }
	end,
	run = function(state)
		local buf = state.buf
		local acc = 0.0
		-- REPS is sized so one iteration lands around 0.2ms — comfortably above
		-- REGRESSION_FLOOR_MS (0.05) and in the same order of magnitude as the
		-- gated scenes. At 256 inner steps alone it measured 0.0010ms, which is
		-- pure scheduler jitter and would have made the divisor noisier than the
		-- scenes it divides.
		for _ = 1, 200 do
			for i = 1, 256 do
				-- float work
				acc += (i * 1.000173) / 3.7
				-- integer + branch work
				local m = i % 7
				if m == 0 then
					acc -= 0.5
				elseif m == 3 then
					acc += 0.25
				end
				-- table read-modify-write over a fixed span
				buf[i] = buf[i] * 0.5 + acc
			end
			-- keep acc bounded so it never reaches inf and change the arithmetic
			-- into a different exponent range each pass
			acc = acc % 1000000
		end
		-- keep the loop from being optimised away, without allocating
		buf[1] = if acc > 0 then 1.0 else -1.0
	end,
})

-- An allocation-heavy variant was trialled as the divisor and REJECTED: under a
-- 20-spinner load on 14 cores it responded 2.10x against a median gated-scene
-- response of 2.37x, while this pure-CPU one responded 2.31x — a 3% match
-- versus 11%. Recorded so nobody re-runs the experiment.

-- stable order regardless of table iteration
table.sort(scenarios, function(a, b)
	return a.name < b.name
end)

return scenarios
