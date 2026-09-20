--!strict
local observeChange = require("../src/core/on_change")
-- Named benchmark scenario registry (design §14.3). Each scenario:
--   { name: string, requirement: string, setup: () -> any,
--     run: (state: any) -> (), teardown: ((state: any) -> ())?,
--     samples: number?, warmup: number? }
-- run() is one iteration; the runner handles warmup/sampling/percentiles.
-- Phase 0 contents: the foundation bake-off — the same three workloads
-- (HUD binding storm, settings open/close churn, keyed collection mutation)
-- on each core candidate. Numbers feed the rubric's update-cost/allocation
-- axes (headless trend data; device authoritative per §14.3).
--
-- THERE IS ONE ARM. Facet sits directly on Compose, so there is no second core
-- to bake off against: these four measure the runtime the library ships.

local services = require("../src/core/services")
local Compose = require("../src/vendor/compose/core")

export type Scenario = {
	name: string,
	requirement: string,
	-- override the runner's warm-up and sample counts (a slow iteration does)
	samples: number?,
	warmup: number?,
	setup: () -> any,
	run: (state: any) -> (),
	teardown: ((state: any) -> ())?,
}

local scenarios: { Scenario } = {}

-- 1. live HUD binding storm: 100 independent writes through a 3-deep
-- memo chain with a render observer (worst-case unbatched updates)
table.insert(scenarios, {
	name = "hud-binding-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local core = services.new()
		local speed = Compose.cell(0)
		local rounded = Compose.formula(function(use)
			return math.floor(use(speed))
		end)
		local label = Compose.formula(function(use)
			return `{use(rounded)} sps`
		end)
		local renders = 0
		observeChange(core.owner, label, function()
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
	name = "settings-churn",
	requirement = "UI-LIFE-002",
	setup = function()
		return { core = services.new() }
	end,
	run = function(state)
		local core = state.core
		local scope = core.owner.createChild()
		local draft = Compose.cell(false)
		local status = Compose.cell("idle")
		local label = Compose.withOwner(scope, function()
			return Compose.formula(function(use)
				return `music: {use(draft) and "on" or "off"} ({use(status)})`
			end)
		end)
		observeChange(scope, label, function() end)
		draft:set(true)
		status:set("confirmed")
		scope:dispose()
	end,
})

-- 3. keyed collection mutation: 50 keyed item scopes; one move + one
-- add/remove per iteration (ForEach-at-core-scale)
table.insert(scenarios, {
	name = "collection-mutation",
	requirement = "UI-RUNTIME-002",
	setup = function()
		local core = services.new()
		local root = core.owner.createChild()
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
					local itemScope = root.createChild()
					Compose.cell(k)
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
	name = "sparse-update-under-load",
	requirement = "UI-PERF-001",
	setup = function()
		local core = services.new()
		local signals = {}
		for i = 1, 200 do
			local s = Compose.cell(i)
			local m = Compose.formula(function(use)
				return use(s) * 2
			end)
			observeChange(core.owner, m, function() end)
			table.insert(signals, s)
		end
		return { core = core, signals = signals, n = 0 }
	end,
	run = function(state)
		state.n += 1
		state.signals[1]:set(1000 + state.n)
	end,
})

-- Phase 1: full mounted-slice update storm (component -> application -> render ->
-- fake adapter), the production-shaped hot path
local Facet = require("../src") :: any
local nativeApp = require("./native_app")
local Compose = Facet.Compose
local function noop() end
table.insert(scenarios, {
	name = "mounted-slice-update-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local world = nativeApp()
		local UI = world.UI
		local speed = Compose.cell(0)
		world.app.mount(function()
			return UI.Screen("Hud")({
				UI.Text("Speed")({
					text = function(use)
						return `{use(speed)} sps`
					end,
					textSize = 18,
				}),
				UI.Button("Boost")({ label = "Boost", onActivate = noop }),
			})
		end)
		world.pres.refresh()
		return { app = world.app, pres = world.pres, speed = speed, n = 0 }
	end,
	run = function(state)
		state.n += 1
		local base = state.n * 50
		for i = 1, 50 do
			state.speed:set(base + i)
		end
		state.pres.refresh()
	end,
	teardown = function(state)
		state.app.dispose()
	end,
})

--[[ MOUNT RAMP. Every other scene measures an update or a churn; these two
	measure building a tree. The tree is a 3,281-node balanced fan-out that
	declares NEITHER inherited channel, because the off path is the one every
	ordinary screen takes.

	`mount-ramp-inherited` is the same tree under a disabled, tinted root, so the
	cost of the feature when it is used is on the record beside the cost when it
	is not.

	One iteration is the application's whole mount: build, present, first solve,
	then dismissal and the frame that releases the owner. ]]
local function rampTree(UI: any, depth: number, i: number): any
	if depth == 0 then
		return UI.Text(`T{i}`)({ text = "leaf" })
	end
	local props: { any } = {}
	for k = 1, 3 do
		table.insert(props, rampTree(UI, depth - 1, k))
	end
	return UI.VStack(`V{i}`)(props)
end
for _, inherited in { false, true } do
	table.insert(scenarios, {
		name = if inherited then "mount-ramp-inherited" else "mount-ramp",
		requirement = "UI-PERF-001",
		-- one iteration is ~100ms, so the default 1500 samples would take minutes
		samples = 120,
		warmup = 5,
		setup = function()
			return nativeApp()
		end,
		run = function(state)
			local UI = state.UI
			local close = state.app.mount(function()
				local props: { [any]: any } = { rampTree(UI, 7, 1) }
				if inherited then
					props.enabled = false
					props.tint = { role = "accent", blend = 1 }
				end
				return UI.Screen("S")(props)
			end)
			close()
			state.frame()
			assert(state.adapter.rootCount() == 0, "mount-ramp: the dismissed screen is still mounted")
		end,
		teardown = function(state)
			state.app.dispose()
		end,
	})
end

local function racers(): { any }
	local items = {}
	for i = 1, 8 do
		items[i] = { id = `r{i}`, name = `Racer {i}` }
	end
	return items
end
local function racerCell(UI: any)
	return function(_columnId: string, item: any)
		return UI.Text("V")({
			text = function(use)
				return use(item).name
			end,
			textSize = 14,
		})
	end
end
local function racerKey(item: any)
	return item.id
end

-- Table: row churn + selection toggle on the composite control
table.insert(scenarios, {
	name = "table-mutation",
	requirement = "UI-PERF-001",
	setup = function()
		local world = nativeApp({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local UI = world.UI
		local items = racers()
		local rows, selected = Compose.cell(items), Compose.cell({})
		world.app.mount(function()
			return UI.Screen("S")({
				UI.Table("Bench")({
					rows = rows,
					key = racerKey,
					columns = {
						{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
						{ id = "n", width = { type = "fixed", px = 48 } },
					},
					cellFor = racerCell(UI),
					rowHeight = 40,
					header = false,
					selection = "multi",
					selectedKeys = selected,
				}),
			})
		end)
		world.frame()
		return { app = world.app, frame = world.frame, rows = rows, selected = selected, items = items, n = 8 }
	end,
	run = function(state)
		-- one row replaced + one selection toggle + frame (the hot loop)
		state.n += 1
		local items = table.clone(state.items)
		local key = `r{state.n}`
		items[((state.n - 1) % 8) + 1] = { id = key, name = `Racer {state.n}` }
		state.items = items
		state.rows:set(items)
		state.selected:update(function(previous)
			local next = table.clone(previous)
			next[key] = if next[key] then nil else true
			return next
		end)
		state.frame()
	end,
	teardown = function(state)
		state.app.dispose()
	end,
})

-- Table: a full grip drag gesture — pointer down, eight preview moves
-- (arrange-only re-solves of the guide line), release commit
table.insert(scenarios, {
	name = "table-resize-drag",
	requirement = "UI-PERF-001",
	setup = function()
		local world = nativeApp({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local UI = world.UI
		local rows = Compose.cell(racers())
		world.app.mount(function()
			return UI.Screen("S")({
				UI.Table("Bench")({
					rows = rows,
					key = racerKey,
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
					cellFor = racerCell(UI),
					rowHeight = 40,
					header = true,
					selection = "none",
				}),
			})
		end)
		world.frame()
		local gripPath = "/S/Bench/Main/Header/Head-name/Grip"
		assert(world.adapter.node(gripPath), "table-resize-drag: the resize grip is not mounted")
		return { app = world.app, frame = world.frame, adapter = world.adapter, grip = gripPath, n = 0 }
	end,
	run = function(state)
		state.n += 1
		-- alternate direction so committed widths oscillate instead of pinning
		local dir = if state.n % 2 == 0 then 1 else -1
		state.adapter.pointerDown(state.grip, 600, 10)
		for i = 1, 8 do
			state.adapter.pointerMove(600 + dir * i * 5, 10)
			state.frame()
		end
		state.adapter.pointerUp(600 + dir * 40, 10)
		state.frame()
	end,
	teardown = function(state)
		state.app.dispose()
	end,
})

-- Billboard canvas: a nameplate on a 300x96 pixel canvas — the world-UI hot
-- path is many small canvases taking frequent text updates
table.insert(scenarios, {
	name = "billboard-nameplate-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local world = nativeApp({ viewport = { x = 0, y = 0, w = 300, h = 96 } })
		local UI = world.UI
		local health = Compose.cell("100")
		world.app.mount(function()
			return UI.Screen("Nameplate")({
				padding = 8,
				gap = 4,
				UI.Text("Name")({ text = "Racer", textSize = 18 }),
				UI.Text("Health")({ text = health, textSize = 14 }),
			})
		end)
		world.pres.refresh()
		return { app = world.app, pres = world.pres, health = health, n = 0 }
	end,
	run = function(state)
		state.n += 1
		for i = 1, 50 do
			state.health:set(tostring((state.n * 50 + i) % 100))
		end
		state.pres.refresh()
	end,
	teardown = function(state)
		state.app.dispose()
	end,
})

-- TextInput: a typing storm — N graphemes per iteration driven through the
-- adapter text seam (focusText + typeText, exactly what the engine TextBox
-- adapter feeds back). A keystroke is paint/semantic writes, never a rebuild:
-- the scenario asserts the field node and the component build count never move.
-- It reverts (cancel) each iteration so the value stays bounded and the
-- workload is deterministic.
table.insert(scenarios, {
	name = "textinput-typing-storm",
	requirement = "UI-PERF-001",
	setup = function()
		local world = nativeApp({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local UI, value = world.UI, Compose.cell("")
		local builds = 0
		world.app.mount(function()
			builds += 1
			return UI.Screen("S")({
				UI.TextInput("Storm")({
					value = value,
					placeholder = "type",
					maxLength = 64,
					onChange = noop,
				}),
			})
		end)
		world.frame()
		local path = "/S/Storm/Field"
		return {
			app = world.app,
			adapter = world.adapter,
			frame = world.frame,
			path = path,
			field = assert(world.adapter.node(path)),
			builds = function()
				return builds
			end,
		}
	end,
	run = function(state)
		state.adapter.tap(state.path) -- enter editing
		state.adapter.focusText(state.path) -- engine focus: seed the buffer
		state.adapter.typeText(state.path, "The quick brown fox 0123") -- 24 graphemes
		state.frame()
		assert(
			state.adapter.node(state.path) == state.field and state.builds() == 1,
			"textinput-typing-storm: the field or its component rebuilt during typing"
		)
		state.adapter.cancelText(state.path) -- revert to "" and end editing
		state.frame()
	end,
	teardown = function(state)
		state.app.dispose()
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

local authoringMotion = require("./authoring_motion")
for _, automatic in { false, true } do
	table.insert(scenarios, {
		name = if automatic then "motion-declarative" else "motion-explicit",
		requirement = "UI-PERF-001",
		setup = function()
			return authoringMotion(automatic)
		end,
		run = function(state)
			state.run()
		end,
		teardown = function(state)
			state.dispose()
		end,
	})
end

-- stable order regardless of table iteration
table.sort(scenarios, function(a, b)
	return a.name < b.name
end)

return scenarios
