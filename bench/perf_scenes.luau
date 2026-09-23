--!strict
-- Named perf scenes (design §14.3 named-scene list; §17 Phase 4). Each scene is
-- PRODUCTION-shaped — it drives a real Facet application (component → mount →
-- render → present) through the headless FakeTarget adapter — so a device profile (viewport,
-- insets, input class) actually changes the work the solver does. setup(profile)
-- applies the profile to the environment; the perf runner
-- (bench/perf_runner.luau) supplies warm-up/sampling/percentiles and records the
-- §14.3 field set. run() returns per-phase sub-timings (seconds) so the runner
-- can report p50/p95/p99 per scheduler phase where the scene can split them.
--
-- §14.3 named scenes covered here:
--   live HUD binding storm ......... hud-binding-storm       (UI-PERF-001)
--   Settings open/close churn ...... settings-churn          (UI-LIFE-002)
--   scroll and focus traversal ..... scroll-focus-traversal  (UI-FOCUS-001)
--   structural collection mutation . collection-mutation     (UI-RUNTIME-002)
--   animation interruption ......... animation-interruption  (UI-PERF-001)
--   locale/preferred-text-size ..... locale-textsize-change  (UI-ENV-001)
--   async image burst .............. async-image-burst       (UI-PERF-001)
--   shadow storm ................... shadow-storm            (UI-STYLE-001)
--
-- Roadmap Step 4 PRODUCTION-SHAPED scenes (the shapes real screens actually
-- have, not the smallest tree that exercises a code path):
--   large virtual list ............. virtual-list-scroll     (UI-RUNTIME-002)
--   native scroll + drag ........... native-scroll-drag      (UI-NATIVE-001/002)
--   dense Sponsor-like HUD ......... dense-hud               (UI-PERF-001)
--   StyleSheet state churn ......... stylesheet-state-churn  (UI-STYLE-001)
--   async image grid (real provider) async-image-grid        (UI-PERF-001)
--   screen mount/unmount churn ..... screen-lifecycle-churn  (UI-LIFE-002)
--   theme swap: palette only ....... theme-swap-flat         (UI-PERF-002)
--   theme swap: metric-changing .... theme-swap-metrics      (UI-PERF-002)
--   theme swap: asset-backed ....... theme-swap-assets       (UI-PERF-002)
--
-- Roadmap Step 5 (sponsor-framework-gaps, row SF-M8):
--   dense motion frame ............. dense-motion            (UI-PERF-001)
--
-- The three theme-swap scenes are deliberately SEPARATE. They have three
-- different invalidation shapes and averaging them into one "theme swap" number
-- would hide the only interesting fact: a palette swap must not move geometry,
-- a metric swap must re-solve, and an asset swap additionally declares fetch
-- work. Each scene asserts its own invalidation shape and records it in extras,
-- so a regression that turns a repaint into a reflow fails visibly.
--
-- Scenes may declare `samples`/`warmup` to override the runner defaults (the
-- heavier production shapes do), `extras(state)` for scene-specific counters,
-- and a phase named `inputToVisible` which the runner lifts into the metric
-- ledger's M6 slot.
--
-- Depends on: src (Facet public API), bench/native_app (one headless
-- application over tests/lib/fake_target), bench/perf_profiles.

local Facet = require("../src") :: any
local nativeApp = require("./native_app")
local perf_profiles = require("../bench/perf_profiles")
-- THE SHARED LAB DEFINITIONS (roadmap Step 9, acceptance PL-12). The headless
-- scenes below and the Roblox performance place build the SAME dataset from the
-- SAME generator and the SAME row shape. Two independently written "dense lists"
-- would drift, and the day they did, this budget would be guarding a workload the
-- place does not run.
local perf_dataset = require("../examples/performance/lab/dataset")
local perf_rows = require("../examples/performance/lab/rows")
local navigationInventory = require("../examples/performance/lab/navigation_inventory")
local transientSurfaces = require("../examples/performance/lab/transient_surfaces")
local themeSnapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local scopes = require("../src/core/profile")

local Compose = Facet.Compose

export type PerfScene = {
	name: string,
	requirement: string,
	dataset: string,
	setup: (profile: any) -> any,
	run: (state: any) -> { [string]: number }?,
	afterRun: ((state: any) -> ())?,
	teardown: ((state: any) -> ())?,
	samples: number?,
	warmup: number?,
	extras: ((state: any) -> any)?,
	asyncStats: ((state: any) -> { dropped: number, stale: number, completed: number })?,
}

-- One headless application sized to `profile`. The record carries `app`, `UI`,
-- `core`, `env`, `adapter`, `pres`, `frame` and `tick`; scenes add their own
-- fields to it and return it as their state.
local function newStack(profile: any, hostOpts: any?): any
	return nativeApp({
		hostOpts = hostOpts,
		configure = function(env)
			perf_profiles.apply(env, profile)
		end,
	})
end

local function noop() end
local function fixed(px: number)
	return { type = "fixed", px = px }
end
local function disposeApp(state: any)
	state.app.dispose()
end

-- how many adapter nodes sit under `prefix` with the leaf name `leaf`
local function countLeaves(adapter: any, prefix: string, leaf: string): number
	local n = 0
	local suffix = "/" .. leaf
	for _, path in adapter.paths() do
		if path:sub(1, #prefix) == prefix and path:sub(-#suffix) == suffix then
			n += 1
		end
	end
	return n
end

local scenes: { PerfScene } = {}

-- 1. live HUD binding storm: a mounted speed readout takes a storm of writes,
-- then one commit. The unbatched-write worst case for the reactive graph.
table.insert(scenes, {
	name = "hud-binding-storm",
	requirement = "UI-PERF-001",
	dataset = "HUD Screen(Text←formula(speed), Button); 50 speed writes + 1 refresh per iter",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local speed = Compose.cell(0)
		state.app.mount(function()
			return UI.Screen("Hud")({
				padding = 8,
				gap = 4,
				UI.Text("Speed")({
					text = function(use)
						return `{use(speed)} sps`
					end,
					textSize = 18,
				}),
				UI.Button("Boost")({ label = "Boost", onActivate = noop }),
			})
		end)
		state.speed, state.n = speed, 0
		return state
	end,
	run = function(state)
		state.n += 1
		local base = state.n * 50
		local t0 = os.clock()
		for i = 1, 50 do
			state.speed:set(base + i)
		end
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
})

-- 2. Settings open/close churn: a modal settings panel is presented over a base
-- HUD and dismissed every iteration — full mount+render / dispose churn.
table.insert(scenes, {
	name = "settings-churn",
	requirement = "UI-LIFE-002",
	dataset = "base HUD + modal Settings(6 rows) presented then dismissed per iter",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		state.app.mount(function()
			return UI.Screen("Base")({ UI.Text("T")({ text = "HUD" }) })
		end)
		function state.settings()
			local props: { [any]: any } = { padding = 12, gap = 6 }
			for i = 1, 6 do
				table.insert(
					props,
					UI.HStack(`Row{i}`)({
						gap = 8,
						UI.Text("L")({ text = `Setting {i}` }),
						UI.Toggle("TG")({ label = `Toggle {i}`, value = Compose.cell(i % 2 == 0) }),
					})
				)
			end
			return UI.Screen("Settings")(props)
		end
		return state
	end,
	run = function(state)
		local t0 = os.clock()
		local close = state.app.presentModal(state.settings)
		local open = os.clock() - t0
		local t1 = os.clock()
		close()
		return { open = open, close = os.clock() - t1 }
	end,
	teardown = disposeApp,
})

-- 3. scroll and focus traversal: a scrollable list of focusable buttons; each
-- iteration walks focus fully around the ring and commits — the navigation +
-- focus-ring re-derivation hot path.
table.insert(scenes, {
	name = "scroll-focus-traversal",
	requirement = "UI-FOCUS-001",
	dataset = "ScrollView of 16 focusable Buttons; 16 focus navigates + 1 refresh per iter",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		state.app.mount(function()
			local props: { [any]: any } = { gap = 2 }
			for i = 1, 16 do
				table.insert(props, UI.Button(`Item{i}`)({ label = `Row {i}`, onActivate = noop }))
			end
			return UI.Screen("List")({ UI.ScrollView("Scroll")(props) })
		end)
		return state
	end,
	run = function(state)
		local t0 = os.clock()
		for _ = 1, 16 do
			state.pres.focus.navigate(1)
		end
		local move = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { focusMove = move, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
})

-- 4. structural collection mutation: the Table control with keyed rows; one row
-- replaced + one selection toggle + refresh per iteration (keyed row churn).
table.insert(scenes, {
	name = "collection-mutation",
	requirement = "UI-RUNTIME-002",
	dataset = "Table(8 keyed rows, 2 cols, multi-select); replace 1 row + toggle sel + refresh",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local items = {}
		for i = 1, 8 do
			table.insert(items, { id = `r{i}`, name = `Racer {i}` })
		end
		local rows, selected = Compose.cell(items), Compose.cell({})
		state.app.mount(function()
			return UI.Screen("S")({
				UI.Table("Bench")({
					columns = {
						{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
						{ id = "n", width = { type = "fixed", px = 48 } },
					},
					rows = rows,
					key = function(item)
						return item.id
					end,
					cellFor = function(_columnId, item)
						return UI.Text("V")({
							text = function(use)
								return use(item).name
							end,
							textSize = 14,
						})
					end,
					rowHeight = 40,
					header = false,
					selection = "multi",
					selectedKeys = selected,
				}),
			})
		end)
		state.pres.refresh()
		state.rows, state.selected, state.items, state.n = rows, selected, items, 8
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
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
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
})

-- 5. animation interruption: a value eased toward a target is RETARGETED before
-- it settles every iteration (the interruption), stepping several frames each
-- time and committing. Models the re-render churn a spring/tween under constant
-- interruption imposes, with the ease computed by the scene so the sample is
-- deterministic.
table.insert(scenes, {
	name = "animation-interruption",
	requirement = "UI-PERF-001",
	dataset = "Text←eased value; retarget + 6 lerp steps + 6 refreshes per iter",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local value = Compose.cell(0.0)
		state.app.mount(function()
			return UI.Screen("Anim")({
				UI.Text("Meter")({
					text = function(use)
						return string.format("%.1f%%", use(value) * 100)
					end,
					textSize = 20,
				}),
			})
		end)
		state.value, state.current, state.n = value, 0.0, 0
		return state
	end,
	run = function(state)
		state.n += 1
		-- retarget (the interruption): alternate 0..1 so the ease never settles
		local target = if state.n % 2 == 0 then 1.0 else 0.0
		local step = 0.0
		local commit = 0.0
		for _ = 1, 6 do
			local t0 = os.clock()
			state.current += (target - state.current) * 0.35 -- critically-damped-ish ease
			state.value:set(state.current)
			step += os.clock() - t0
			local t1 = os.clock()
			state.pres.refresh()
			commit += os.clock() - t1
		end
		return { step = step, commit = commit }
	end,
	teardown = disposeApp,
})

-- 6. locale / preferred-text-size change: flipping locale + text-size scale
-- invalidates the whole typography/measure path; each iteration toggles both
-- and commits — the environment-driven full re-measure hot path.
table.insert(scenes, {
	name = "locale-textsize-change",
	requirement = "UI-ENV-001",
	dataset = "Screen(8 Text rows); toggle locale + preferredTextSize + refresh per iter",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		state.app.mount(function()
			local props: { [any]: any } = { padding = 8, gap = 4 }
			for i = 1, 8 do
				table.insert(props, UI.Text(`L{i}`)({ text = `Menu item {i}`, textSize = 16 }))
			end
			return UI.Screen("Menu")(props)
		end)
		state.n = 0
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		state.env:set("locale", if state.n % 2 == 0 then "en-us" else "de-de")
		state.env:set("preferredTextSize", if state.n % 2 == 0 then 1.0 else 1.3)
		local envChange = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { envChange = envChange, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
})

-- 7. async image burst: a grid of Image nodes takes a burst of new asset ids
-- each iteration, fed through a modeled bounded-concurrency loader. When a
-- node's target changes before its in-flight load completes, that load is
-- counted STALE/dropped (§14.3 "dropped or stale async work"). The loader is
-- modeled deterministically in the scene — measuring both the image-prop
-- reactive churn and the async accounting; `async-image-grid` below runs the
-- real provider.
local ASYNC_CONCURRENCY = 4
table.insert(scenes, {
	name = "async-image-burst",
	requirement = "UI-PERF-001",
	dataset = "12 Image nodes; burst 12 new asset ids/iter; loader concurrency=4",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local N = 12
		local imageCells = {}
		for i = 1, N do
			imageCells[i] = Compose.cell(`rbxassetid://0`)
		end
		state.app.mount(function()
			local props: { [any]: any } = { gap = 2 }
			for i = 1, N do
				table.insert(props, UI.Image(`Img{i}`)({ image = imageCells[i] }))
			end
			return UI.Screen("Gallery")(props)
		end)
		-- loader model: `inflight[node]` = the asset id currently "loading";
		-- completion respects ASYNC_CONCURRENCY. Counters accumulate across the run.
		state.imageCells, state.N, state.n = imageCells, N, 0
		state.inflight = {} :: { [number]: string? }
		state.stats = { dropped = 0, stale = 0, completed = 0 }
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		-- burst: assign every node a fresh asset id (the reactive prop churn)
		for i = 1, state.N do
			local newId = `rbxassetid://{state.n * 100 + i}`
			local prev = state.inflight[i]
			if prev ~= nil then
				-- target changed before the prior load completed -> stale/dropped
				state.stats.stale += 1
				state.stats.dropped += 1
			end
			state.imageCells[i]:set(newId)
			state.inflight[i] = newId
		end
		local enqueue = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		-- advance the loader: up to ASYNC_CONCURRENCY loads complete this frame
		local completedThisFrame = 0
		for i = 1, state.N do
			if state.inflight[i] ~= nil and completedThisFrame < ASYNC_CONCURRENCY then
				state.inflight[i] = nil
				state.stats.completed += 1
				completedThisFrame += 1
			end
		end
		return { enqueue = enqueue, commit = os.clock() - t1 }
	end,
	asyncStats = function(state)
		return state.stats
	end,
	teardown = disposeApp,
})

-- 8. shadow storm (§17 Phase 4 engine styling): a screen at the ~100-shadow
-- engine budget. Measures the style-authority write + lint cost so the
-- budget is a NUMBER the runner tracks, not just a lint rule.
table.insert(scenes, {
	name = "shadow-storm",
	requirement = "UI-STYLE-001",
	dataset = "Screen with 100 shadowed+rounded Boxes (the engine budget); refresh + style_lint per iter",
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local _, root = state.app.mount(function()
			local props: { [any]: any } = { padding = 4, gap = 1 }
			for i = 1, 100 do
				table.insert(
					props,
					UI.corners(
						UI.shadow(UI.Box(`Sh{i}`)({ width = fixed(20), height = fixed(8) }), "raised"),
						"control"
					)
				)
			end
			return UI.Screen("Shadows")(props)
		end)
		state.root, state.lint, state.warnings = root, require("../src/render/style_lint"), 0
		return state
	end,
	run = function(state)
		local t0 = os.clock()
		state.pres.refresh()
		local commit = os.clock() - t0
		local t1 = os.clock()
		local warnings = state.lint.lint(state.root)
		state.warnings = #warnings
		return { commit = commit, lint = os.clock() - t1 }
	end,
	teardown = disposeApp,
})

-- 9. large virtual list, scrolled. 2000 rows of a production row shape
-- (avatar + two-line text + a control), windowed by the real VirtualList over
-- the native scroll substrate. Each iteration scrolls by a little over one row
-- so the window genuinely slides — the case where windowing, keyed survivor
-- identity and canvas geometry all have to agree.
table.insert(scenes, {
	name = "virtual-list-scroll",
	requirement = "UI-RUNTIME-002",
	dataset = "VirtualList 2000 rows x (Image + 2 Text + Toggle), itemExtent 56; scroll 61px + refresh per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local items = table.create(2000)
		for i = 1, 2000 do
			items[i] = { id = `racer{i}`, name = `Racer {i}`, detail = `Lap {i % 5 + 1} · P{i % 24 + 1}` }
		end
		local rows = Compose.cell(items)
		state.app.mount(function()
			return UI.Screen("Roster")({
				UI.VirtualList("Roster")({
					rows = rows,
					key = "id",
					itemExtent = 56,
					viewportExtent = math.max(120, profile.viewport.h - 80),
					cell = function(_, cellCtx)
						-- The cell receives the item; `current` follows its edits.
						local item = Compose.formula(cellCtx.current)
						return UI.HStack("Row")({
							gap = 8,
							padding = 6,
							UI.Image("Avatar")({ image = "rbxassetid://0" }),
							UI.VStack("Lines")({
								gap = 2,
								UI.Text("Name")({
									text = function(use)
										return use(item).name
									end,
									textSize = 16,
								}),
								UI.Text("Detail")({
									text = function(use)
										return use(item).detail
									end,
									textSize = 13,
								}),
							}),
							UI.Toggle("Fav")({ label = "Favourite", value = Compose.cell(false) }),
						})
					end,
				}),
			})
		end)
		state.pres.refresh()
		state.y = 0
		return state
	end,
	run = function(state)
		-- 61px: deliberately NOT a row multiple, so every iteration lands the
		-- window on a fresh partial-row boundary instead of a lucky aligned one
		state.y += 61
		if state.y > 2000 * 56 - 400 then
			state.y = 0
		end
		local t0 = os.clock()
		state.adapter.driveScroll("/Roster/Roster", { x = 0, y = state.y })
		local scroll = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { scroll = scroll, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
	extras = function(state)
		return { windowedRows = countLeaves(state.adapter, "/Roster/Roster/", "Row"), virtualRows = 2000 }
	end,
})

-- 10. native scroll + drag. The two mechanisms Roblox owns at the adapter edge
-- (ScrollingFrame offset, pointer capture) driven together through the REAL
-- handler seams — adapter.driveScroll moves the engine mirror and
-- pointerDown/Move/Up run the capture path, never a direct callback.
table.insert(scenes, {
	name = "native-scroll-drag",
	requirement = "UI-NATIVE-001",
	dataset = "ScrollView(30 draggable Grip rows); 1 scroll + a 6-step pointer drag through the capture path per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local moved, drops = 0, 0
		local session: any = nil
		state.app.mount(function()
			local props: { [any]: any } = { gap = 4 }
			for i = 1, 30 do
				table.insert(
					props,
					UI.Grip(`Card{i}`)({
						width = UI.fill(),
						height = fixed(48),
						onPointerDown = function(_path, pos)
							session = Facet.newDragSession({
								payload = { card = i },
								source = `Card{i}`,
								targets = {
									{ id = "SlotA", rect = { x = 0, y = 0, w = 200, h = 200 } },
									{ id = "SlotB", rect = { x = 200, y = 0, w = 200, h = 200 } },
								},
							})
							session:update(pos.x, pos.y)
							return true
						end,
						onPointerMove = function(_path, pos)
							if session ~= nil then
								session:update(pos.x, pos.y)
								moved += 1
							end
						end,
						onPointerUp = function(_path, pos)
							if session ~= nil then
								local result = session:drop(pos.x, pos.y)
								if result.kind == "dropped" then
									drops += 1
								end
								session = nil
							end
						end,
					})
				)
			end
			return UI.Screen("Cards")({ UI.ScrollView("Scroll")(props) })
		end)
		state.pres.refresh()
		state.y, state.dragPath = 0, "/Cards/Scroll/Card1"
		function state.counts()
			return moved, drops
		end
		return state
	end,
	run = function(state)
		state.y = (state.y + 37) % 600
		local t0 = os.clock()
		state.adapter.driveScroll("/Cards/Scroll", { x = 0, y = state.y })
		local scroll = os.clock() - t0
		local t1 = os.clock()
		state.adapter.pointerDown(state.dragPath, 10, 10, "mouse")
		for step = 1, 6 do
			state.adapter.pointerMove(10 + step * 30, 10 + step * 12)
		end
		state.adapter.pointerUp(210, 90)
		local drag = os.clock() - t1
		local t2 = os.clock()
		state.pres.refresh()
		return { scroll = scroll, drag = drag, commit = os.clock() - t2 }
	end,
	-- a scene whose pointer path silently stopped resolving would still record
	-- a (very fast) time, so the counters that prove the work happened are part
	-- of the record and the gate checks them
	extras = function(state)
		local moved, drops = state.counts()
		return { dragMoves = moved, dropsCommitted = drops }
	end,
	teardown = disposeApp,
})

-- 11. dense Sponsor-like HUD. The node count and binding fan-out a race HUD
-- actually has: live readouts, a progress bar, a keyed marker overlay and an
-- action row. This is also the scene that measures M6 — the semantic action
-- dispatch through to the committed visible write, driven through the adapter's
-- activate seam rather than by calling the handler.
table.insert(scenes, {
	name = "dense-hud",
	requirement = "UI-PERF-001",
	dataset = "HUD: 8 live readouts + ProgressView + 12 keyed markers + 4 Buttons; 24 writes, 1 activate, 1 refresh per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local cells = {}
		for i = 1, 8 do
			cells[i] = Compose.cell(0)
		end
		local marks = {}
		for i = 1, 12 do
			marks[i] = { id = `m{i}`, x = i * 7 }
		end
		local markerData = Compose.cell(marks)
		local progress = Compose.cell(0)
		local boosts = Compose.cell(0)
		-- the M6 chain's OBSERVABLE end: the committed text on the mounted node.
		-- extras reads it back from the adapter, so an activate seam that quietly
		-- stopped reaching paint fails the gate instead of getting faster.
		state.app.mount(function()
			local readouts: { [any]: any } = { gap = 6 }
			for i = 1, 8 do
				table.insert(
					readouts,
					UI.Text(`R{i}`)({
						text = function(use)
							return `{use(cells[i])}`
						end,
						textSize = 15,
					})
				)
			end
			local actions: { [any]: any } = { gap = 6 }
			for i = 1, 4 do
				table.insert(
					actions,
					UI.Button(`Act{i}`)({
						label = `Action {i}`,
						onActivate = function()
							boosts:set(boosts:peek() + 1)
						end,
					})
				)
			end
			return UI.Screen("Hud")({
				padding = 6,
				gap = 4,
				UI.HStack("Readouts")(readouts),
				UI.ProgressView("Lap")({ value = progress }),
				UI.ForEach("Markers")({
					Compose.keyed({
						from = markerData,
						key = function(m)
							return m.id
						end,
						render = function(m)
							return UI.Box(`Dot-{m:peek().id}`)({ width = fixed(6), height = fixed(6) })
						end,
					}),
				}),
				UI.Text("BoostCount")({
					text = function(use)
						return `Boost x{use(boosts)}`
					end,
					textSize = 14,
				}),
				UI.HStack("Actions")(actions),
			})
		end)
		state.pres.refresh()
		state.cells, state.progress, state.n = cells, progress, 0
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		for i = 1, 8 do
			state.cells[i]:set(state.n * 10 + i)
			state.cells[i]:set(state.n * 10 + i + 1)
			state.cells[i]:set(state.n * 10 + i + 2)
		end
		state.progress:set((state.n % 100) / 100)
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		local commit = os.clock() - t1
		-- M6: the full semantic chain, adapter activate -> handler -> cell ->
		-- refresh -> committed property write. Not a callback call: the tap goes
		-- through the same activate seam a pointer/touch/gamepad press does.
		local t2 = os.clock()
		state.adapter.tap("/Hud/Actions/Act1")
		state.pres.refresh()
		local inputToVisible = os.clock() - t2
		return { mutate = mutate, commit = commit, inputToVisible = inputToVisible }
	end,
	extras = function(state)
		local node = state.adapter.node("/Hud/BoostCount")
		return {
			activates = state.n,
			boostText = if node ~= nil then node.props.text else nil,
		}
	end,
	teardown = disposeApp,
})

-- 12. StyleSheet state churn. In production the visual states are native
-- StyleSheet rules and the ADAPTER writes the tags; what Facet owns — and what
-- can regress — is the state fan-out plus the pure hint->tag classification the
-- adapter runs per node. Both are measured here. The engine's own
-- CollectionService writes are an E3 quantity and are NOT modelled.
table.insert(scenes, {
	name = "stylesheet-state-churn",
	requirement = "UI-STYLE-001",
	dataset = "40 controls; selected/toggle/disabled/error flip per iter + 40 classifyTags passes + refresh",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local values = {}
		for i = 1, 40 do
			values[i] = Compose.cell(i == 1)
		end
		state.app.mount(function()
			local props: { [any]: any } = { gap = 2 }
			for i = 1, 40 do
				table.insert(props, UI.Toggle(`Opt{i}`)({ label = `Option {i}`, value = values[i] }))
			end
			return UI.Screen("Opts")(props)
		end)
		state.pres.refresh()
		state.values, state.n, state.tagCount = values, 0, 0
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		-- the selection fans out to all forty; two of them change
		local selected = (state.n % 40) + 1
		for i, value in state.values do
			value:set(i == selected)
		end
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		local commit = os.clock() - t1
		local t2 = os.clock()
		local tags = 0
		for i = 1, 40 do
			local desired = sheet_model.classifyTags({
				surface = "control",
				interactive = true,
				pointerLive = i % 2 == 0,
				selected = ((state.n + i) % 40) == 0,
				toggleOn = (i % 3) == 0,
				errorState = (i % 17) == 0,
				strong = (i % 8) == 0,
			})
			for _ in desired do
				tags += 1
			end
		end
		state.tagCount = tags
		return { mutate = mutate, commit = commit, classify = os.clock() - t2 }
	end,
	extras = function(state)
		return { tagsPerPass = state.tagCount }
	end,
	teardown = disposeApp,
})

-- 13. async image grid over the REAL provider. Twelve avatars are acquired by
-- one mounted screen, partially fulfilled, and the whole screen is released and
-- rebuilt with new keys — the shape a scrolling player list has, including the
-- stale completions a released handle must reject.
table.insert(scenes, {
	name = "async-image-grid",
	requirement = "UI-PERF-001",
	dataset = "12 AsyncImage over the real bounded provider; screen release + rebuild with new keys + partial drain per iter",
	samples = 120,
	warmup = 30,
	setup = function(profile)
		local state = newStack(profile)
		state.provider = Facet.newResourceProvider(state.core, { maxConcurrent = 4, cacheBudget = 16 })
		state.close = nil :: any
		state.n = 0
		state.stats = { dropped = 0, stale = 0, completed = 0 }
		return state
	end,
	run = function(state)
		state.n += 1
		local UI = state.UI
		local t0 = os.clock()
		-- release the previous generation: the screen's owner going away is what
		-- makes any still-in-flight request's completion stale
		if state.close ~= nil then
			state.close()
			state.close = nil
		end
		local mount = os.clock() - t0
		local t1 = os.clock()
		state.close = state.app.mount(function()
			local props: { [any]: any } = { gap = 2 }
			for i = 1, 12 do
				table.insert(
					props,
					UI.AsyncImage(`Av{i}`)({
						provider = state.provider,
						key = `rbxthumb://gen={state.n}&id={i}`,
					})
				)
			end
			return UI.Screen("Avatars")(props)
		end)
		state.pres.refresh()
		local commit = os.clock() - t1
		-- drain what the concurrency window exposes; the rest are dropped when
		-- the next iteration releases the screen
		local t2 = os.clock()
		local pending = state.provider.pendingRequests()
		for idx, req in pending do
			if idx > 4 then
				break
			end
			local verdict = state.provider.complete(req.key, req.generation, req.key)
			if verdict == "applied" then
				state.stats.completed += 1
			else
				state.stats.stale += 1
				state.stats.dropped += 1
			end
		end
		return { mount = mount, commit = commit, drain = os.clock() - t2 }
	end,
	teardown = disposeApp,
	asyncStats = function(state)
		return state.stats
	end,
})

-- 14. screen mount/unmount churn at production weight. `settings-churn` above
-- churns six plain rows; this one churns a screen made of real composite
-- controls, which is what a pause menu or a garage actually costs to open.
table.insert(scenes, {
	name = "screen-lifecycle-churn",
	requirement = "UI-LIFE-002",
	dataset = "Screen(Slider + Stepper + Picker + ProgressView + Label + 12 Toggles) presented and dismissed per iter",
	samples = 120,
	warmup = 30,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		state.app.mount(function()
			return UI.Screen("Base")({ UI.Text("T")({ text = "HUD" }) })
		end)
		state.pres.refresh()
		state.n = 0
		return state
	end,
	run = function(state)
		state.n += 1
		local UI = state.UI
		local build = 0
		local t0 = os.clock()
		local close = state.app.presentModal(function()
			local b0 = os.clock()
			local toggles: { [any]: any } = { gap = 4 }
			for i = 1, 12 do
				table.insert(toggles, UI.Toggle(`Flag{i}`)({ label = `Flag {i}`, value = Compose.cell(i % 2 == 0) }))
			end
			local screen = UI.Screen("Settings")({
				padding = 12,
				gap = 6,
				UI.Label("Head")({ title = "Settings" }),
				UI.Slider("Vol")({ label = "Volume", value = Compose.cell(50), min = 0, max = 100 }),
				UI.Stepper("Qual")({ label = "Quality", value = Compose.cell(2), min = 0, max = 4 }),
				UI.Picker("Detail")({
					label = "Detail",
					options = {
						{ value = "low", label = "Low" },
						{ value = "medium", label = "Medium" },
						{ value = "high", label = "High" },
					},
					selected = Compose.cell("medium"),
				}),
				UI.ProgressView("Load")({ value = 0.4 }),
				UI.VStack("Flags")(toggles),
			})
			build = os.clock() - b0
			return screen
		end)
		local open = os.clock() - t0 - build
		local t2 = os.clock()
		close()
		return { build = build, open = open, close = os.clock() - t2 }
	end,
	teardown = disposeApp,
})

-- ---- the three theme-swap invalidation shapes -----------------------------
-- One fixture, three different swaps. Each scene records the SHAPE of the
-- invalidation it caused (how many probe rects moved) beside its cost, so
-- "a palette swap became a reflow" is a visible regression rather than a
-- slightly larger number.

local THEME_PROBES = { "/Fixture/Head", "/Fixture/Row/Go", "/Fixture/Row/Flag", "/Fixture/Bar" }

local function themeFixture(profile: any)
	local state = newStack(profile)
	local UI = state.UI
	state.app.mount(function()
		return UI.Screen("Fixture")({
			padding = 8,
			gap = 6,
			UI.Text("Head")({ text = "Garage", textSize = 20 }),
			UI.HStack("Row")({
				gap = 8,
				UI.Button("Go")({ label = "Go", onActivate = noop }),
				UI.Toggle("Flag")({ label = "Flag", value = Compose.cell(true) }),
			}),
			UI.ProgressView("Bar")({ value = 0.6 }),
		})
	end)
	state.pres.refresh()
	return state
end

local function probeRects(adapter: any): { [string]: any }
	local out: { [string]: any } = {}
	for _, path in THEME_PROBES do
		local node = adapter.node(path)
		out[path] = if node ~= nil and node.rect ~= nil then table.clone(node.rect) else nil
	end
	return out
end

local function movedCount(a: { [string]: any }, b: { [string]: any }): number
	local moved = 0
	for _, path in THEME_PROBES do
		local ra, rb = a[path], b[path]
		if ra == nil or rb == nil then
			if ra ~= rb then
				moved += 1
			end
		elseif ra.x ~= rb.x or ra.y ~= rb.y or ra.w ~= rb.w or ra.h ~= rb.h then
			moved += 1
		end
	end
	return moved
end

-- a theme-swap scene factory: `kind` names the invalidation shape the scene is
-- supposed to have, and the extras record what it actually had
local function themeSwapScene(spec: {
	name: string,
	kind: string,
	dataset: string,
	snapshots: (any) -> { any },
	assetsDeclared: number,
}): PerfScene
	return {
		name = spec.name,
		requirement = "UI-PERF-002",
		dataset = spec.dataset,
		samples = 160,
		warmup = 40,
		setup = function(profile)
			local state = themeFixture(profile)
			local snapshots = spec.snapshots(profile)
			state.env:set("themeMetrics", snapshots[1])
			state.pres.refresh()
			state.snapshots, state.baseline, state.moved, state.n = snapshots, probeRects(state.adapter), 0, 0
			return state
		end,
		run = function(state)
			state.n += 1
			local target = state.snapshots[(state.n % 2) + 1]
			local t0 = os.clock()
			state.env:set("themeMetrics", target)
			local swap = os.clock() - t0
			local t1 = os.clock()
			state.pres.refresh()
			local commit = os.clock() - t1
			-- the invalidation SHAPE, measured every iteration against the
			-- fixture's first-theme baseline. The MAXIMUM over the run is what
			-- the record keeps: the loop alternates themes, so the last
			-- iteration is back on the baseline theme half the time and a
			-- last-value-wins reading would report 0 for a swap that plainly
			-- reflows (found while wiring the gate check, 2026-07-26).
			local moved = movedCount(state.baseline, probeRects(state.adapter))
			if moved > state.moved then
				state.moved = moved
			end
			return { swap = swap, commit = commit }
		end,
		teardown = disposeApp,
		extras = function(state)
			return {
				themeSwap = {
					measured = true,
					kind = spec.kind,
					probes = #THEME_PROBES,
					movedRects = state.moved, -- max over the sampled run, see run()
					assetsDeclared = spec.assetsDeclared,
					note = "movedRects counts probe rects whose solved geometry differs from the first "
						.. "theme's; a palette-only swap must be 0 and a metric swap must not be",
				},
			}
		end,
	}
end

-- 15. flat swap: two themes of ONE package that differ only in palette. The
-- metric snapshot values are identical, so nothing may reflow. This is the
-- scene that catches a repaint quietly becoming a relayout.
local parchment = require("../examples/themes/fantasy_parchment")
table.insert(
	scenes,
	themeSwapScene({
		name = "theme-swap-flat",
		kind = "palette-only",
		dataset = "Fantasy Parchment Daylight <-> Candlelight (identical metrics); swap + refresh per iter",
		assetsDeclared = 0,
		snapshots = function()
			local pkg = parchment.build(Facet.themes)
			return {
				themeSnapshot.resolve(pkg, "Daylight", {}),
				themeSnapshot.resolve(pkg, "Candlelight", {}),
			}
		end,
	})
)

-- 16. metric-changing swap: the RS-A14 platform pair — a compact pointer
-- package and a roomy touch package. Control heights, spacing and type sizes
-- all move, so the solver must re-solve the whole fixture.
local compactPointer = require("../examples/themes/compact_pointer")
local glossyTouch = require("../examples/themes/glossy_touch")
table.insert(
	scenes,
	themeSwapScene({
		name = "theme-swap-metrics",
		kind = "metric-changing",
		dataset = "compact_pointer (24px controls) <-> glossy_touch (44px controls); swap + full re-solve per iter",
		assetsDeclared = 0,
		snapshots = function()
			return {
				themeSnapshot.resolve(compactPointer.build(Facet.themes), nil, {}),
				themeSnapshot.resolve(glossyTouch.build(Facet.themes), nil, {}),
			}
		end,
	})
)

-- 17. asset-backed swap: Facet Neutral (no art) against Fantasy Ornate (33
-- declared assets and chrome recipes). Headlessly this measures the metric
-- invalidation plus the asset DECLARATION the package carries; the nine-slice
-- layer instances and their decode cost are an E3 quantity captured in Studio,
-- which the artifact says rather than implying this number covers them.
local fantasyOrnate = require("../examples/themes/fantasy_ornate")
local ORNATE_ASSETS = (function(): number
	local pkg = fantasyOrnate.build(Facet.themes)
	local n = 0
	for _ in (pkg.assets or {}) do
		n += 1
	end
	return n
end)()
-- 18. DENSE MOTION (row SF-M8, review PG-6). The frame shape a celebration
-- actually lands on, and the one the motion authority's cost claims are about:
-- ≥20 concurrent springs writing the presentation channel, a timeline running
-- its beats through the same clock, and a windowed list churning underneath —
-- all in one iteration. Mirrors `dense-hud`'s shape (a production stack, phase
-- splits, extras that prove the work happened) with the motion axis added.
--
-- THE CLOCK IS SCRIPTED. `now` is the scene's own counter, so the sample measures
-- WORK and never wall-clock luck: the same iteration always steps the same dt,
-- fires the same beats, and settles the same springs, which is what makes a
-- regression here a regression in the framework rather than in the host's load.
-- Every motion write goes through `controller.setPresentationTransform` — the
-- real write surface — so a re-solve dropping (or re-asserting) a motion shows up
-- as cost instead of hiding.
table.insert(scenes, {
	name = "dense-motion",
	requirement = "UI-PERF-001",
	dataset = "24 springs on the presentation channel + a 4-beat timeline + a 600-row windowed list re-sorted; "
		.. "1 scripted clock step + 24 transform writes + 1 refresh per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local now = 0
		local clock = Facet.motion.newClock(state.core, {
			now = function()
				return now
			end,
		})
		local items = table.create(600)
		for i = 1, 600 do
			items[i] = { id = `chip{i}`, name = `Racer {i}` }
		end
		local rows = Compose.cell(items)
		local springs = {}
		for i = 1, 24 do
			springs[i] = clock:spring(0, if i % 2 == 0 then "object" else "reward")
		end
		local banner = Compose.cell("ready")
		local _, _, handle = state.app.mount(function()
			local chips: { [any]: any } = { gap = 4 }
			for i = 1, 24 do
				table.insert(chips, UI.Box(`Chip{i}`)({ surface = "control", width = fixed(24), height = fixed(24) }))
			end
			return UI.Screen("Celebrate")({
				padding = 6,
				gap = 4,
				UI.Text("Banner")({ text = banner, textSize = 18 }),
				UI.HStack("Chips")(chips),
				UI.VirtualList("Roster")({
					rows = rows,
					key = "id",
					itemExtent = 44,
					viewportExtent = math.max(120, math.floor(profile.viewport.h * 0.5)),
					cell = function(_, cellCtx)
						local item = Compose.formula(cellCtx.current)
						return UI.Text("Name")({
							text = function(use)
								return use(item).name
							end,
							textSize = 15,
						})
					end,
				}),
			})
		end)
		state.pres.refresh()
		state.controller, state.clock, state.springs = handle.controller, clock, springs
		state.rows, state.banner, state.beats, state.timeline, state.now, state.n = rows, banner, 0, nil, now, 0
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		-- the churn underneath: a re-sort that KEEPS every key, so the window slides
		-- over the same identities a live leaderboard does
		local current = state.rows:peek() :: { any }
		local next = table.create(#current)
		for i = 2, #current do
			next[i - 1] = current[i]
		end
		next[#current] = current[1]
		state.rows:set(next)
		-- retarget every spring: nothing is allowed to settle and go free
		for i, spring in state.springs do
			spring:setTarget(if (state.n + i) % 2 == 0 then 12 else -12)
		end
		-- ...and a timeline is always running (a new one the moment the last ends)
		if state.timeline == nil or state.timeline:isDone() then
			state.beats += 1
			local mark = state.beats
			state.timeline = state.clock:timeline({
				beats = {
					{ at = 0, run = function() end },
					{
						at = 0.1,
						run = function()
							state.banner:set(`beat {mark}`)
						end,
					},
					{ at = 0.2, run = function() end },
					{
						at = 0.3,
						run = function()
							state.banner:set(`done {mark}`)
						end,
					},
				},
			})
		end
		local mutate = os.clock() - t0
		-- ONE clock step: every active motion advances inside one core transaction
		local t1 = os.clock()
		state.now += 1 / 60
		state.clock:step(1 / 60)
		for i, spring in state.springs do
			state.controller.setPresentationTransform(`/Celebrate/Chips/Chip{i}`, { x = 0, y = spring:peek() })
		end
		local motion = os.clock() - t1
		local t2 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, motion = motion, commit = os.clock() - t2 }
	end,
	extras = function(state)
		local stats = state.clock:stats()
		return {
			springs = #state.springs,
			activeMotions = state.clock:activeCount(),
			timelineBeats = state.beats,
			windowedRows = countLeaves(state.adapter, "/Celebrate/Roster/", "Name"),
			virtualRows = 600,
			-- the contract this scene exists to keep honest: one transaction per
			-- stepped frame, however many springs moved
			motionSteps = stats.steps,
			motionTransactions = stats.transactions,
			banner = state.banner:peek(),
		}
	end,
	teardown = function(state)
		state.app.dispose()
		state.clock:dispose()
	end,
})

-- 2026-09-12 transitions round: the four new Luau-side motions on ONE screen —
-- a 30-row staggered ForEach re-keyed every 30 iterations, a DisclosureGroup
-- flipped every 20, a TextInput invalid shake every 15, and a popped Button
-- tapped every 10, with one scripted clock step and one refresh per iteration.
--
-- WHY IT IS ITS OWN SCENE. `dense-motion` prices the motion AUTHORITY (springs
-- and timelines driven straight off a clock the scene owns); this one prices
-- what the CONTROLS ask that authority to do on a frame where all four kinds of
-- motion overlap. The control motions are booked by the controls themselves on
-- the application runtime, and the row enter is one runtime timeline per row, so
-- a control that starts booking a timeline per frame, or a frame that stops
-- sharing one drain, shows up as cost instead of hiding inside a control spec.
--
-- THE CLOCK IS SCRIPTED: `tick(1/60)` steps a fixed dt on the application's
-- virtual clock, so the same iteration always advances the same beats and the
-- sample measures WORK rather than wall-clock luck. The proof is the one
-- `dense-motion` keeps — one drain per stepped frame that moved anything,
-- however many values moved — plus a counter per motion kind, because a shake or a pop that quietly stopped firing would only
-- make this scene faster.
local STAGGER_S, ENTER_S = 0.02, 0.2
local DISCLOSURE_BODY = "/Motion/Adv/Reveal/Body"
table.insert(scenes, {
	name = "control-motion",
	requirement = "UI-PERF-001",
	dataset = "30-row staggered ForEach (enter fade, 0.02s) + DisclosureGroup + TextInput.invalid shake + Button.pop; "
		.. "1 scripted clock step + 1 refresh per iter, re-key/20 flip/15 pulse/10 pop",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local state = newStack(profile)
		local UI, runtime = state.UI, state.app.runtime
		local gen = 0
		local function batch()
			gen += 1
			local out = table.create(30)
			for i = 1, 30 do
				out[i] = { id = `g{gen}-{i}`, index = i }
			end
			return out
		end
		local items = Compose.cell(batch())
		local invalid = Compose.cell(false)
		local expanded = Compose.cell(false)
		local pops = 0
		state.app.mount(function()
			-- one timeline carries the whole list's entrance; a re-key restarts it
			local entry = runtime.timeline({ duration = 29 * STAGGER_S + ENTER_S })
			local entered = items:peek()
			Compose.watch(function(use)
				local current = use(items)
				if current ~= entered then
					entered = current
					entry:restart()
				end
			end)
			return UI.Screen("Motion")({
				padding = 6,
				gap = 4,
				UI.TextInput("Name")({ value = Compose.cell(""), invalid = invalid }),
				UI.Button("Go")({
					label = "Go",
					pop = true,
					onActivate = function()
						pops += 1
					end,
				}),
				UI.DisclosureGroup("Adv")({
					label = "Advanced",
					expanded = expanded,
					content = function()
						return UI.Text("Body")({ text = "body", textSize = 14 })
					end,
				}),
				UI.ForEach("List")({
					Compose.keyed({
						from = items,
						key = function(item)
							return item.id
						end,
						render = function(item)
							-- the staggered enter: each row holds for its place in the
							-- rhythm, then fades in over ENTER_S
							local record = item:peek()
							local hold = (record.index - 1) * STAGGER_S
							return UI.ZStack(`Row-{record.id}`)({
								canvasGroup = true,
								height = fixed(20),
								opacity = function(use)
									return math.clamp((use(entry.elapsed) - hold) / ENTER_S, 0, 1)
								end,
								UI.Text("T")({ text = record.id, textSize = 14 }),
							})
						end,
					}),
				}),
			})
		end)
		state.pres.refresh()
		state.items, state.batch, state.invalid, state.expanded = items, batch, invalid, expanded
		function state.popsRef()
			return pops
		end
		function state.genRef()
			return gen
		end
		state.n, state.rekeys, state.flips, state.pulses, state.staggerHeld = 0, 0, 0, 0, 0
		-- the FRAMEWORK-ANSWERED halves of the flip and the pulse (below):
		-- what the tree and the paint say, not what the driving code asked for
		state.contentUp = state.adapter.node(DISCLOSURE_BODY) ~= nil
		state.flipsSeen, state.shakesSeen = 0, 0
		state.motionSteps, state.motionDrains = 0, 0
		-- the flushes are counted off the settle pass's `react` phase: one per
		-- transaction, however many reactors and settle callbacks it opened
		scopes.setEnabled(true)
		scopes.setHooks(noop, noop)
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		if state.n % 30 == 0 then
			state.items:set(state.batch())
			state.rekeys += 1
		end
		if state.n % 20 == 0 then
			state.expanded:set(not state.expanded:peek())
			state.flips += 1
		end
		if state.n % 15 == 0 then
			-- the EDGE is what shakes, so this alternates true/false rather than
			-- re-asserting true (which the control de-duplicates away)
			state.invalid:set(state.n % 30 ~= 0)
			state.pulses += 1
		end
		if state.n % 10 == 0 then
			-- the same activate seam a pointer/touch/gamepad press reaches, not
			-- the handler: the pop kick is booked inside the control's `activate`
			state.adapter.tap("/Motion/Go")
		end
		local mutate = os.clock() - t0
		-- ONE clock step: every active control motion advances inside one core
		-- transaction, which is what `motionSteps == motionTransactions` asserts
		local t1 = os.clock()
		local stepsBefore = state.pres.motionClock:stats().steps
		scopes.resetCounters()
		state.tick(1 / 60)
		local flushes = scopes.counters().byScope.react or 0
		local motion = os.clock() - t1
		if state.pres.motionClock:stats().steps > stepsBefore then
			state.motionSteps += 1
		end
		state.motionDrains += flushes
		local t2 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, motion = motion, commit = os.clock() - t2 }
	end,
	-- THE STAGGER WITNESS, and the reason it is in `afterRun` rather than `run`:
	-- the runner times `run` externally and books `afterRun` as its own `settle`
	-- phase, so reading the painted alphas costs the budget nothing. Every other
	-- counter this scene reports is incremented by the code that DROVE the
	-- mutation, which proves the scene ran but not that the framework answered;
	-- this one is read back off the adapter. On the re-key frame the first row
	-- has already begun its enter while the last one is still painted absent —
	-- exactly the rhythm `tests/transitions.spec.luau` proves per row — so a
	-- stagger that stopped holding rows (every row entering at once) leaves this
	-- at zero and reddens `tools/check_perf_scenes.py`.
	afterRun = function(state)
		--[[ THE FLIP AND THE PULSE, ANSWERED BY THE FRAMEWORK (final review item 2).
			`flips` and `pulses` are incremented by the code that SET the signal, so
			they prove the scene drove its own mutation and nothing more: a
			DisclosureGroup that stopped building its content, or a shake the control
			stopped booking, leaves both counters climbing while the frame prices
			nothing. These two read the answer back instead.

			THE FLIP is the content node's EXISTENCE changing — the disclosure's whole
			cost is mounting that subtree, so a flip that changes nothing about the
			tree is not a flip. Measured, this reads 1 over the 200 iterations rather
			than 10, and the reason is worth stating rather than tuning away: the
			content RETIRES, and this scene flips every 20 frames while the exit is
			still in flight, so after the first expand the subtree is continuously
			mounted (re-entering mid-exit, which is itself the expensive path this
			frame is meant to price). So the counter's contract is "the framework
			built the disclosure's content AT ALL" — which is exactly the silent
			absence that would make this scene faster while `flips` kept climbing.

			THE SHAKE is the painted displacement of the input's ROOT, composed the
			way the live adapter writes the engine Position (`presentedPosition`
			less the solved rect — the shake moves paint and never the solver's
			rect, which is the contract `tests/motion_paint_only.spec.luau` holds).
			It counts every iteration the field is off its rest line, not only the
			pulse frames: a shake lasts many frames, and 90 of 200 is the beat this
			scene is actually paying for. ]]
		local body = state.adapter.node(DISCLOSURE_BODY)
		local up = body ~= nil
		if up ~= state.contentUp then
			state.contentUp = up
			state.flipsSeen += 1
		end
		local field = state.adapter.node("/Motion/Name")
		if
			field ~= nil
			and field.rect ~= nil
			and field.presentedPosition ~= nil
			and field.presentedPosition.x ~= field.rect.x
		then
			state.shakesSeen += 1
		end
		if state.n % 30 ~= 0 then
			return
		end
		local g = state.genRef()
		local first = state.adapter.node(`/Motion/List/Row-g{g}-1`)
		local last = state.adapter.node(`/Motion/List/Row-g{g}-30`)
		if first == nil or last == nil or first.canvasGroupInstance == nil or last.canvasGroupInstance == nil then
			return
		end
		if first.canvasGroupInstance.groupTransparency < last.canvasGroupInstance.groupTransparency then
			state.staggerHeld += 1
		end
	end,
	extras = function(state)
		return {
			rekeys = state.rekeys,
			flips = state.flips,
			pulses = state.pulses,
			pops = state.popsRef(),
			staggerHeld = state.staggerHeld,
			flipsSeen = state.flipsSeen,
			shakesSeen = state.shakesSeen,
			rows = 30,
			-- the contract this scene shares with dense-motion: one reactive drain
			-- per stepped frame that moved anything, however many control motions moved
			motionSteps = state.motionSteps,
			motionTransactions = state.motionDrains,
		}
	end,
	teardown = function(state)
		scopes.setHooks(nil, nil)
		scopes.setEnabled(false)
		state.app.dispose()
	end,
})

table.insert(
	scenes,
	themeSwapScene({
		name = "theme-swap-assets",
		kind = "asset-backed",
		dataset = "Facet Neutral <-> Fantasy Ornate (declared art + chrome recipes); swap + refresh per iter",
		assetsDeclared = ORNATE_ASSETS,
		snapshots = function()
			return {
				themeSnapshot.resolve(Facet.themes.neutralPackage(), nil, {}),
				themeSnapshot.resolve(fantasyOrnate.build(Facet.themes), nil, {}),
			}
		end,
	})
)

-- ---------------------------------------------------------------------------
-- Roadmap Step 9 (performance-stress-places): the LAB-LINKED scenes.
--
-- These are the headless half of the performance lab. They exist for two reasons
-- and neither of them is "measure a device":
--
--   1. REGRESSION SCREENING. The lab's workload runs on every `tools/perf.sh`, so
--      a framework change that makes the dense list more expensive reddens the
--      gate on the development host long before anyone opens Studio.
--   2. A FALSIFIABLE GATE. `prove_perf_gate` injects a regression into a named
--      scene; a lab-linked scene is what makes that proof about the workload this
--      stage actually cares about.
--
-- They are TREND EVIDENCE ONLY, like every other scene here: no engine, no frame,
-- no device. The place is where engine cost is measured and only a phone can
-- close the device budget.
--
-- THE SEAM WITH THE LAB MODULES. Each lab builder takes the application context
-- first — `ctx = { Facet, app, UI, Compose, env, core }` — and builds natively
-- under whatever owner is active when it is called:
--   perf_rows.cell(ctx, item, { provider, values, toggles, compact }) -> node
--   navigationInventory.build(ctx, imageKeys) -> { screen = component, tabs, builds, ... }
--   transientSurfaces.build(ctx, kind) -> { present, open, close, proof, dispose }
local function labContext(state: any)
	return {
		Facet = Facet,
		app = state.app,
		UI = state.UI,
		Compose = Compose,
		env = state.env,
		core = state.core,
	}
end

local LAB_LIST = "/PerfWorkload/Rows"

local function labStack(profile: any, items: { any }, viewportHeight: number)
	local state = newStack(profile)
	local UI = state.UI
	local ctx = labContext(state)
	local provider = Facet.newResourceProvider(state.core)
	local rows = Compose.cell(items)
	local values: { [string]: any } = {}
	local toggles: { [string]: any } = {}
	-- THE SAME ARRANGEMENT DECISION THE PLACE MAKES. The reference profile is
	-- `floorAndroid` at 360x640 — a compact phone — and the one-line row overflows
	-- it, so a budget taken from that layout would guard a screen nobody ships.
	-- Sharing `compactFor` is the whole point of sharing the row module.
	local compact = perf_rows.compactFor(profile.viewport.w)
	state.app.mount(function()
		return UI.Screen("PerfWorkload")({
			padding = 8,
			gap = 6,
			UI.VirtualList("Rows")({
				rows = rows,
				key = "id",
				itemExtent = perf_rows.heightFor(compact),
				rowGap = perf_rows.ROW_GAP,
				viewportExtent = viewportHeight,
				overscan = perf_rows.OVERSCAN,
				cell = function(item: any)
					return perf_rows.cell(ctx, item, {
						provider = provider,
						values = values,
						toggles = toggles,
						compact = compact,
					})
				end,
			}),
		})
	end)
	state.pres.refresh()
	state.provider, state.rows, state.compact, state.viewportHeight = provider, rows, compact, viewportHeight
	return state
end

-- mounted row slots: the list's canvas holds exactly one child per windowed
-- row, two path segments below the list
local function labWindow(state: any): number
	local n = 0
	local prefix = LAB_LIST .. "/"
	for _, path in state.adapter.paths() do
		if path:sub(1, #prefix) == prefix then
			local _, separators = path:sub(#prefix + 1):gsub("/", "")
			if separators == 1 then
				n += 1
			end
		end
	end
	return n
end

-- LAB-1: the principal dense-scroll workload, headless.
table.insert(scenes, {
	name = "lab-dense-scroll",
	requirement = "UI-PERF-001",
	dataset = `perf-lab shared dataset (seed 1, 2000 rows, {perf_dataset.VERSION}) x {perf_rows.VERSION} `
		.. "(image + 2 text + toggle + stepper + button); 61px scroll + refresh per iter",
	samples = 120,
	warmup = 30,
	setup = function(profile)
		local items = perf_dataset.build({ count = 2000, seed = 1, content = "normal" })
		local state = labStack(profile, items, math.max(120, profile.viewport.h - 80))
		state.y, state.digest = 0, perf_dataset.digest(items)
		return state
	end,
	run = function(state)
		-- 61px, deliberately not a row multiple (same reasoning as
		-- virtual-list-scroll): every iteration lands on a fresh partial boundary
		state.y += 61
		local extent = 2000 * (perf_rows.heightFor(state.compact) + perf_rows.ROW_GAP) - state.viewportHeight
		if state.y > extent then
			state.y = 0
		end
		local t0 = os.clock()
		state.adapter.driveScroll(LAB_LIST, { x = 0, y = state.y })
		local scroll = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { scroll = scroll, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
	extras = function(state)
		return {
			windowedRows = labWindow(state),
			-- the SAME bound the place asserts, computed from the same arithmetic,
			-- so a windowing regression fails here as well as there
			windowBound = perf_rows.expectedWindow(state.viewportHeight, state.compact),
			logicalRows = 2000,
			datasetVersion = perf_dataset.VERSION,
			rowVersion = perf_rows.VERSION,
			datasetDigest = state.digest,
		}
	end,
})

-- LAB-2: collection churn over the same dataset — insert, remove and reorder
-- while the window holds. Separated from the scroll scene because the two have
-- different invalidation shapes and blending them hides which one moved.
table.insert(scenes, {
	name = "lab-collection-churn",
	requirement = "UI-RUNTIME-002",
	dataset = `perf-lab shared dataset (seed 1, 800 rows, {perf_dataset.VERSION}) x {perf_rows.VERSION}; `
		.. "one insert + one remove + one reorder + refresh per iter",
	samples = 100,
	warmup = 25,
	setup = function(profile)
		local items = perf_dataset.build({ count = 800, seed = 1, content = "normal" })
		local state = labStack(profile, items, math.max(120, profile.viewport.h - 80))
		state.n = 0
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		local items = table.clone(state.rows:peek())
		local at = math.max(1, math.floor(#items * 0.25))
		table.insert(items, at, {
			id = `ins{state.n}`,
			name = `Inserted {state.n}`,
			detail = "inserted during churn",
			team = "Ember",
			imageKey = perf_dataset.IMAGE_KEYS[(state.n % #perf_dataset.IMAGE_KEYS) + 1],
			value = 0.5,
			enabled = true,
			rank = at,
		})
		table.remove(items, math.max(1, math.floor(#items * 0.6)))
		local moved = table.remove(items, math.max(1, (state.n * 7) % #items))
		table.insert(items, math.max(1, ((state.n * 7) % #items) + 3), moved)
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.rows:set(items)
		state.pres.refresh()
		return { mutate = mutate, commit = os.clock() - t1 }
	end,
	teardown = disposeApp,
	extras = function(state)
		return {
			windowedRows = labWindow(state),
			windowBound = perf_rows.expectedWindow(state.viewportHeight, state.compact),
			logicalRows = #state.rows:peek(),
			datasetVersion = perf_dataset.VERSION,
			rowVersion = perf_rows.VERSION,
		}
	end,
})

-- Shared controls in an inventory-shaped page. Geometry/identity assertions
-- guard the work avoided, independently of noisy wall-clock trend budgets.
table.insert(scenes, {
	name = "adaptive-navigation-images",
	requirement = "UI-PERF-001",
	dataset = "24 framed image Buttons in a responsive inventory Grid; 3 TabView destinations; idle, focus and sidebar round-trip",
	samples = 120,
	warmup = 20,
	setup = function(profile)
		local stack = newStack(profile)
		-- `navigationInventory.build` constructs composite controls (TabView,
		-- Button) that register their teardown with the ambient Compose owner
		-- (docs/extending/new-control.md step 3) — so it has to run INSIDE
		-- `app.mount`'s callback, which is what establishes that owner, rather
		-- than being built eagerly and handed to `mount` as a static node.
		local state: any = nil
		local _, _, handle = stack.app.mount(function()
			state = navigationInventory.build(labContext(stack), perf_dataset.IMAGE_KEYS)
			return state.screen
		end)
		stack.pres.refresh()
		stack.tick(1 / 60)
		stack.pres.refresh()
		state.app, state.core, state.env, state.adapter = stack.app, stack.core, stack.env, stack.adapter
		state.pres, state.tick, state.handle = stack.pres, stack.tick, handle
		-- the two cards focus alternates between, resolved once from the mounted tree
		state.cards = {}
		for index = 1, 2 do
			local suffix = `/Cars/Car{index}`
			for _, path in stack.adapter.paths() do
				if path:sub(-#suffix) == suffix then
					state.cards[index] = path
				end
			end
			assert(state.cards[index], `adaptive-navigation-images: inventory card {index} is not mounted`)
		end
		state.n = 0
		return state
	end,
	run = function(state)
		local pres, c = state.pres, state.handle.controller
		local phases = {}
		local before = c.stats()
		local t0 = os.clock()
		state.tick(1 / 60)
		pres.refresh()
		phases.idle = os.clock() - t0
		assert(c.stats().solves == before.solves, "idle adaptive controls must not solve")
		state.n += 1
		t0 = os.clock()
		pres.focus.focusOn(state.cards[state.n % 2 + 1])
		state.tick(1 / 60)
		pres.refresh()
		phases.focus = os.clock() - t0
		assert(c.stats().solves == before.solves, "image focus must remain paint-only")
		assert(c.stats().creates == before.creates, "image focus must not remount content")
		t0 = os.clock()
		state.tabs.expandSidebar()
		pres.refresh()
		state.tick(1 / 60)
		state.tabs.collapseSidebar()
		pres.refresh()
		state.tick(1 / 60)
		pres.refresh()
		state.tick(1 / 60)
		pres.refresh()
		phases.navigation = os.clock() - t0
		assert(state.builds() == 1, "navigation chrome must preserve its selected page")
		return phases
	end,
	afterRun = function(state)
		-- Settling is measured separately from one player event. It still runs
		-- on every iteration and must leave the next idle sample truly idle.
		for _ = 1, 60 do
			state.tick(1 / 60)
			state.pres.refresh()
		end
	end,
	extras = function(state)
		return { contentBuilds = state.builds(), render = state.handle.controller.stats() }
	end,
	teardown = disposeApp,
})

local customizationScene = table.clone(scenes[#scenes])
customizationScene.name = "navigation-customization"
customizationScene.dataset =
	"Reorder three live destinations around a retained 24-card inventory; event cost and multi-frame settling reported separately"
customizationScene.run = function(state)
	state.n += 1
	local before = state.builds()
	local started = os.clock()
	state.tabs.moveTab("garage", if state.n % 2 == 0 then 1 else 2)
	state.pres.refresh()
	assert(state.builds() == before, "customization must preserve the selected page")
	return { customization = os.clock() - started }
end
table.insert(scenes, customizationScene)

-- ---- 2026-09-11: the four player-visible landings without a scene ---------
-- Each landing below shipped after the last baseline with no headless row aimed
-- at it: Alert (role-ordered action row/stack), the Picker menu (anchored
-- popover), the segmented strip's reactive fit rule, and the radial menu. A
-- scene per landing keeps the trend gate honest about exactly the cost that
-- moved, instead of letting it hide inside `screen-lifecycle-churn`. The three
-- open/close fixtures are `examples/performance/lab/transient_surfaces.luau`,
-- SHARED with the lab's `transient-surfaces` workload so the trend gate and the
-- Studio capture price the same tree (the `adaptive-navigation` precedent).

local function transientScene(spec: { name: string, requirement: string, dataset: string, kind: string })
	return {
		name = spec.name,
		requirement = spec.requirement,
		dataset = spec.dataset,
		samples = 120,
		warmup = 30,
		setup = function(profile)
			local state = newStack(profile)
			-- the fixture mounts its base screen through `ctx.app` (labContext)
			state.fixture = transientSurfaces.build(labContext(state), spec.kind)
			state.fixture.present(state.pres)
			return state
		end,
		run = function(state)
			local t0 = os.clock()
			state.fixture.open(state.pres)
			local open = os.clock() - t0
			local t1 = os.clock()
			state.fixture.close(state.pres)
			return { open = open, close = os.clock() - t1 }
		end,
		extras = function(state)
			return state.fixture.proof(state.pres)
		end,
		teardown = function(state)
			state.fixture.dispose()
			state.app.dispose()
		end,
	}
end

-- 23. Alert present/dismiss: a three-action alert (destructive + default +
-- cancel) is presented over a base screen and dismissed every iteration. Prices
-- the role-ordered AdaptiveStack + keyed ForEach the Alert now builds, and the
-- presenter's modal mount/dispose churn around it.
table.insert(
	scenes,
	transientScene({
		name = "alert-present-dismiss",
		requirement = "UI-LIFE-002",
		dataset = "Base Screen(Button); Alert(title, message, 3 role-placed actions) presented + refreshed + ticked, dismissed + refreshed + ticked per iter",
		kind = "alert",
	})
)

-- 24. Picker menu open/close: the menu-style picker (the phone/desktop default)
-- opens its anchored popover and closes it every iteration. Prices the popover
-- host mount, the anchor solve, the materialize transition's first tick, and the
-- teardown — the path every settings row on a phone now takes. A gamepad profile
-- presents a sheet instead; the presentation is recorded beside the number.
table.insert(
	scenes,
	transientScene({
		name = "picker-menu-open-close",
		requirement = "UI-PERF-001",
		dataset = `Screen(Picker style=menu, {transientSurfaces.PICKER_OPTIONS} options) presented; api.open + refresh + tick, api.close + refresh + tick per iter`,
		kind = "picker",
	})
)

-- 25. Segmented strip text-size flip: a segmented picker under a preferred
-- text-size change. The strip's fit rule is reactive on the preference, so
-- every flip re-measures and re-arranges the segments and moves the selection
-- bar. Prices the reactive fit rule and the strip relayout, nothing else.
table.insert(scenes, {
	name = "picker-segmented-textsize",
	requirement = "UI-ENV-001",
	dataset = "Screen(Picker style=segmented, 3 options + 2 Text rows); preferredTextSize 1.0<->1.3 + refresh per iter",
	samples = 120,
	warmup = 30,
	setup = function(profile)
		local state = newStack(profile)
		local UI = state.UI
		local selected = Compose.cell("normal")
		state.app.mount(function()
			return UI.Screen("S")({
				padding = 12,
				gap = 8,
				UI.Text("Head")({ text = "Race setup", textSize = 18 }),
				UI.Picker("Difficulty")({
					label = "Difficulty",
					style = "segmented",
					options = {
						{ value = "easy", label = "Easy" },
						{ value = "normal", label = "Normal" },
						{ value = "hard", label = "Hard" },
					},
					selected = selected,
				}),
				UI.Text("Note")({ text = "Affects rival speed and damage.", textSize = 14 }),
			})
		end)
		state.pres.refresh()
		state.n, state.flips = 0, 0
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		state.env:set("preferredTextSize", if state.n % 2 == 0 then 1.0 else 1.3)
		local envChange = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		local commit = os.clock() - t1
		state.flips += 1
		return { envChange = envChange, commit = commit }
	end,
	extras = function(state)
		-- the selection bar exists only in the segmented strip, so the tree answers
		-- which style the control resolved
		local bar = state.adapter.node("/S/Difficulty/Indicator/Layer/Bar")
		return { flips = state.flips, style = if bar ~= nil then "segmented" else nil }
	end,
	teardown = disposeApp,
})

-- 26. Radial menu open/close: a six-item compass radial opens from its solved
-- launcher and closes every iteration. Prices the sector geometry refresh, the
-- opening scale/aim motion's first ticks and the close path.
table.insert(
	scenes,
	transientScene({
		name = "radial-menu-open-close",
		requirement = "UI-PERF-001",
		dataset = `Screen(RadialMenu donut/compass, {transientSurfaces.RADIAL_ITEMS} items) settled; api.open + refresh + 2 ticks, api.close + refresh + 2 ticks per iter`,
		kind = "radial",
	})
)

return scenes
