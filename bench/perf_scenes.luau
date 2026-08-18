--!strict
-- Named perf scenes (design §14.3 named-scene list; §17 Phase 4). Each scene is
-- PRODUCTION-shaped — it drives the real mount → render → present pipeline
-- through the headless FakeTarget adapter — so a device profile (viewport,
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
-- Depends on: src (Facet public API), src/controls/table, tests/lib/fake_target
-- (the headless RenderTargetAdapter), bench/perf_profiles.

local Facet = require("../src")
local table_control = require("../src/controls/table")
local fake_target = require("../tests/lib/fake_target")
local perf_profiles = require("../bench/perf_profiles")
-- THE SHARED LAB DEFINITIONS (roadmap Step 9, acceptance PL-12). The headless
-- scenes below and the Roblox performance place build the SAME dataset from the
-- SAME generator and the SAME row shape. Two independently written "dense lists"
-- would drift, and the day they did, this budget would be guarding a workload the
-- place does not run.
local perf_dataset = require("../examples/performance/lab/dataset")
local perf_rows = require("../examples/performance/lab/rows")
local themeSnapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")

local UI = Facet.UI

export type PerfScene = {
	name: string,
	requirement: string,
	dataset: string,
	setup: (profile: any) -> any,
	run: (state: any) -> { [string]: number }?,
	teardown: ((state: any) -> ())?,
	samples: number?,
	warmup: number?,
	extras: ((state: any) -> any)?,
	asyncStats: ((state: any) -> { dropped: number, stale: number, completed: number })?,
}

-- build a fully-wired headless stack sized to `profile`
local function newStack(profile: any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	perf_profiles.apply(env, profile)
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return core, env, system, adapter, pres
end

local scenes: { PerfScene } = {}

-- 1. live HUD binding storm: a mounted speed readout takes a storm of writes,
-- then one commit. The unbatched-write worst case for the reactive graph.
table.insert(scenes, {
	name = "hud-binding-storm",
	requirement = "UI-PERF-001",
	dataset = "HUD Screen(Text←memo(speed), Button); 50 speed writes + 1 refresh per iter",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local speed = core:signal(0)
		local label = core:memo(function(use)
			return `{use(speed)} sps`
		end)
		pres.present(UI.Screen({
			id = "Hud",
			padding = 8,
			gap = 4,
			children = {
				UI.Text({ id = "Speed", text = label, textSize = 18 }),
				UI.Button({ id = "Boost", label = "Boost" }),
			},
		}))
		return { core = core, adapter = adapter, pres = pres, speed = speed, n = 0 }
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
})

-- 2. Settings open/close churn: a modal settings panel is presented over a base
-- HUD and dismissed every iteration — full mount+render / dispose churn.
table.insert(scenes, {
	name = "settings-churn",
	requirement = "UI-LIFE-002",
	dataset = "base HUD + modal Settings(6 rows) presented then dismissed per iter",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		pres.present(UI.Screen({ id = "Base", children = { UI.Text({ id = "T", text = "HUD" }) } }))
		local rows = {}
		for i = 1, 6 do
			table.insert(
				rows,
				UI.HStack({
					id = `Row{i}`,
					gap = 8,
					children = {
						UI.Text({ id = "L", text = `Setting {i}` }),
						UI.Toggle({ id = "TG", label = `Toggle {i}`, value = i % 2 == 0 }),
					},
				})
			)
		end
		local settings = UI.Screen({ id = "Settings", padding = 12, gap = 6, children = rows })
		return { core = core, adapter = adapter, pres = pres, settings = settings }
	end,
	run = function(state)
		local t0 = os.clock()
		local handle = state.pres.presentModal(state.settings)
		local open = os.clock() - t0
		local t1 = os.clock()
		state.pres.dismiss(handle)
		return { open = open, close = os.clock() - t1 }
	end,
})

-- 3. scroll and focus traversal: a scrollable list of focusable buttons; each
-- iteration walks focus fully around the ring and commits — the navigation +
-- focus-ring re-derivation hot path.
table.insert(scenes, {
	name = "scroll-focus-traversal",
	requirement = "UI-FOCUS-001",
	dataset = "ScrollView of 16 focusable Buttons; 16 focus navigates + 1 refresh per iter",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local buttons = {}
		for i = 1, 16 do
			table.insert(buttons, UI.Button({ id = `Item{i}`, label = `Row {i}` }))
		end
		pres.present(UI.Screen({
			id = "List",
			children = {
				UI.ScrollView({ id = "Scroll", gap = 2, children = buttons }),
			},
		}))
		return { core = core, adapter = adapter, pres = pres }
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
})

-- 4. structural collection mutation: the Table control with keyed rows; one row
-- replaced + one selection toggle + refresh per iteration (keyed ForEach churn).
table.insert(scenes, {
	name = "collection-mutation",
	requirement = "UI-RUNTIME-002",
	dataset = "Table(8 keyed rows, 2 cols, multi-select); replace 1 row + toggle sel + refresh",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local items = {}
		for i = 1, 8 do
			table.insert(items, { id = `r{i}`, name = `Racer {i}` })
		end
		local rows = core:signal(items)
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
			cellFor = function(_columnId, item)
				return UI.Text({ id = "V", text = item.name, textSize = 14 })
			end,
			rowHeight = 40,
			header = false,
			selection = "multi",
		})
		pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, rows = rows, tbl = tbl, items = items, n = 8 }
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		local items = table.clone(state.items)
		items[((state.n - 1) % 8) + 1] = { id = `r{state.n}`, name = `Racer {state.n}` }
		state.items = items
		state.rows:set(items)
		state.tbl.api.select(`r{state.n}`)
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, commit = os.clock() - t1 }
	end,
})

-- 5. animation interruption: a value eased toward a target is RETARGETED before
-- it settles every iteration (the interruption), stepping several frames each
-- time and committing. Models the re-render churn a spring/tween under constant
-- interruption imposes — Facet has no tween module yet, so the scene builds the
-- observability (ENGINEERING.md "build the observability") deterministically.
table.insert(scenes, {
	name = "animation-interruption",
	requirement = "UI-PERF-001",
	dataset = "Text←eased value; retarget + 6 lerp steps + 6 refreshes per iter",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local value = core:signal(0.0)
		local shown = core:memo(function(use)
			return string.format("%.1f%%", use(value) * 100)
		end)
		pres.present(UI.Screen({
			id = "Anim",
			children = { UI.Text({ id = "Meter", text = shown, textSize = 20 }) },
		}))
		return { core = core, adapter = adapter, pres = pres, value = value, current = 0.0, n = 0 }
	end,
	run = function(state)
		state.n += 1
		-- retarget (the interruption): alternate 0..1 so the ease never settles
		local target = if state.n % 2 == 0 then 1.0 else 0.0
		local step = os.clock() - os.clock()
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
})

-- 6. locale / preferred-text-size change: flipping locale + text-size scale
-- invalidates the whole typography/measure path; each iteration toggles both
-- and commits — the environment-driven full re-measure hot path.
table.insert(scenes, {
	name = "locale-textsize-change",
	requirement = "UI-ENV-001",
	dataset = "Screen(8 Text rows); toggle locale + preferredTextSize + refresh per iter",
	setup = function(profile)
		local core, env, _sys, adapter, pres = newStack(profile)
		local labels = {}
		for i = 1, 8 do
			table.insert(labels, UI.Text({ id = `L{i}`, text = `Menu item {i}`, textSize = 16 }))
		end
		pres.present(UI.Screen({ id = "Menu", padding = 8, gap = 4, children = labels }))
		return { core = core, adapter = adapter, env = env, pres = pres, n = 0 }
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
})

-- 7. async image burst: a grid of Image nodes takes a burst of new asset ids
-- each iteration, fed through a modeled bounded-concurrency loader. When a
-- node's target changes before its in-flight load completes, that load is
-- counted STALE/dropped (§14.3 "dropped or stale async work"). Facet has no
-- async-resource module yet, so the loader is modeled deterministically in the
-- scene — measuring both the image-prop reactive churn and the async accounting.
local ASYNC_CONCURRENCY = 4
table.insert(scenes, {
	name = "async-image-burst",
	requirement = "UI-PERF-001",
	dataset = "12 Image nodes; burst 12 new asset ids/iter; loader concurrency=4",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local N = 12
		local imageSignals = {}
		local children = {}
		for i = 1, N do
			local sig = core:signal(`rbxassetid://0`)
			imageSignals[i] = sig
			table.insert(children, UI.Image({ id = `Img{i}`, image = sig }))
		end
		pres.present(UI.Screen({ id = "Gallery", gap = 2, children = children }))
		-- loader model: `inflight[node]` = the asset id currently "loading";
		-- `queue` respects ASYNC_CONCURRENCY. Counters accumulate across the run.
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			imageSignals = imageSignals,
			N = N,
			n = 0,
			inflight = {} :: { [number]: string? },
			stats = { dropped = 0, stale = 0, completed = 0 },
		}
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
			state.imageSignals[i]:set(newId)
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
})

-- 8. shadow storm (§17 Phase 4 engine styling): a screen at the ~100-shadow
-- engine budget. Measures the style-authority write + lint cost so the
-- budget is a NUMBER the runner tracks, not just a lint rule.
table.insert(scenes, {
	name = "shadow-storm",
	requirement = "UI-STYLE-001",
	dataset = "Screen with 100 shadowed+rounded Boxes (the engine budget); refresh + style_lint per iter",
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local style_lint = require("../src/render/style_lint")
		local children = {}
		for i = 1, 100 do
			table.insert(
				children,
				UI.corners(
					UI.shadow(
						UI.Box({
							id = `Sh{i}`,
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 8 },
						}),
						"raised"
					),
					"control"
				)
			)
		end
		local handle = pres.present(UI.Screen({ id = "Shadows", padding = 4, gap = 1, children = children }))
		return { core = core, adapter = adapter, pres = pres, handle = handle, lint = style_lint, warnings = 0 }
	end,
	run = function(state)
		local t0 = os.clock()
		state.pres.refresh()
		local commit = os.clock() - t0
		local t1 = os.clock()
		local warnings = state.lint.lint(state.handle.root.node)
		state.warnings = #warnings
		return { commit = commit, lint = os.clock() - t1 }
	end,
})

-- ===========================================================================
-- ROADMAP STEP 4: production-shaped scenes
--
-- Everything above this line is a mechanism benchmark: the smallest tree that
-- exercises one hot path. Everything below is a SHAPE — a list a game actually
-- ships, a HUD with the node count a race HUD has, a theme swap with the
-- invalidation a real package causes. Mechanism benchmarks catch algorithmic
-- regressions; shapes catch the ones that only appear at production size.
-- ===========================================================================

-- 9. large virtual list, scrolled. 2000 rows of a production row shape
-- (avatar + two-line text + a control), windowed by the real VirtualList over
-- the native scroll substrate. Each iteration scrolls by a little over one row
-- so the window genuinely slides — the case where windowing, keyed survivor
-- identity and canvas geometry all have to agree.
table.insert(scenes, {
	name = "virtual-list-scroll",
	requirement = "UI-RUNTIME-002",
	dataset = "VirtualList 2000 rows x (Image + 2 Text + Toggle), rowHeight 56; scroll 61px + refresh per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local items = table.create(2000)
		for i = 1, 2000 do
			items[i] = { id = `racer{i}`, name = `Racer {i}`, detail = `Lap {i % 5 + 1} · P{i % 24 + 1}` }
		end
		local rows = core:signal(items)
		local list = Facet.newVirtualList(Facet, core, {
			id = "Roster",
			rows = rows,
			key = function(item)
				return item.id
			end,
			rowHeight = 56,
			viewportHeight = math.max(120, profile.viewport.h - 80),
			cell = function(item)
				return UI.HStack({
					id = "Row",
					gap = 8,
					padding = 6,
					children = {
						UI.Image({ id = "Avatar", image = "rbxassetid://0" }),
						UI.VStack({
							id = "Lines",
							gap = 2,
							children = {
								UI.Text({ id = "Name", text = item.name, textSize = 16 }),
								UI.Text({ id = "Detail", text = item.detail, textSize = 13 }),
							},
						}),
						UI.Toggle({ id = "Fav", label = "Favourite", value = false }),
					},
				})
			end,
		})
		pres.present(UI.Screen({ id = "Roster", children = { list.blueprint } }))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, list = list, y = 0 }
	end,
	run = function(state)
		-- 61px: deliberately NOT a row multiple, so every iteration lands the
		-- window on a fresh partial-row boundary instead of a lucky aligned one
		state.y += 61
		if state.y > 2000 * 56 - 400 then
			state.y = 0
		end
		local t0 = os.clock()
		state.list.scrollTop:set(state.y)
		local scroll = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { scroll = scroll, commit = os.clock() - t1 }
	end,
	teardown = function(state)
		state.list.dispose()
	end,
	extras = function(state)
		local window = state.list.debugWindow()
		local n = 0
		for _ in window do
			n += 1
		end
		return { windowedRows = n, virtualRows = 2000 }
	end,
})

-- 10. native scroll + drag. The two mechanisms Roblox owns at the adapter edge
-- (ScrollingFrame offset, pointer capture) driven together through the REAL
-- handler seams — adapter.driveScroll moves the engine mirror and
-- pointerDown/Move/Up run the capture path, never a direct callback.
table.insert(scenes, {
	name = "native-scroll-drag",
	requirement = "UI-NATIVE-001",
	dataset = "ScrollView(30 draggable rows); 1 scroll + a 6-step pointer drag through the capture path per iter",
	samples = 160,
	warmup = 40,
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local moved = core:signal(0)
		local drops = core:signal(0)
		local session: any = nil
		local rows = {}
		for i = 1, 30 do
			table.insert(
				rows,
				UI.Button({
					id = `Card{i}`,
					label = `Card {i}`,
					height = { type = "fixed", px = 48 },
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
							moved:set(moved:get() + 1)
						end
					end,
					onPointerUp = function(_path, pos)
						if session ~= nil then
							local result = session:drop(pos.x, pos.y)
							if result.kind == "dropped" then
								drops:set(drops:get() + 1)
							end
							session = nil
						end
					end,
				})
			)
		end
		pres.present(UI.Screen({
			id = "Cards",
			children = { UI.ScrollView({ id = "Scroll", gap = 4, children = rows }) },
		}))
		pres.refresh()
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			y = 0,
			dragPath = "/Cards/Scroll/Card1",
			moved = moved,
			drops = drops,
		}
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
		return { dragMoves = state.moved:get(), dropsCommitted = state.drops:get() }
	end,
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
		local core, _env, _sys, adapter, pres = newStack(profile)
		local readouts = {}
		local signals = {}
		for i = 1, 8 do
			local sig = core:signal(0)
			signals[i] = sig
			local text = core:memo(function(use)
				return `{use(sig)}`
			end)
			table.insert(readouts, UI.Text({ id = `R{i}`, text = text, textSize = 15 }))
		end
		local markerData = core:signal({})
		local marks = {}
		for i = 1, 12 do
			marks[i] = { id = `m{i}`, x = i * 7 }
		end
		markerData:set(marks)
		local progress = core:signal(0)
		local bar = Facet.newProgressView(Facet, core, { id = "Lap", value = progress })
		local boosts = core:signal(0)
		local actions = {}
		for i = 1, 4 do
			table.insert(
				actions,
				UI.Button({
					id = `Act{i}`,
					label = `Action {i}`,
					onActivate = function()
						boosts:set(boosts:get() + 1)
					end,
				})
			)
		end
		local boostText = core:memo(function(use)
			return `Boost x{use(boosts)}`
		end)
		-- the M6 chain's OBSERVABLE end: the committed text on the mounted node.
		-- extras reads it back from the adapter, so an activate seam that quietly
		-- stopped reaching paint fails the gate instead of getting faster.
		pres.present(UI.Screen({
			id = "Hud",
			padding = 6,
			gap = 4,
			children = {
				UI.HStack({ id = "Readouts", gap = 6, children = readouts }),
				bar.blueprint,
				UI.ForEach({
					id = "Markers",
					items = markerData,
					key = function(m)
						return m.id
					end,
					row = function(_m)
						return UI.Box({
							id = "Dot",
							width = { type = "fixed", px = 6 },
							height = { type = "fixed", px = 6 },
						})
					end,
				}),
				UI.Text({ id = "BoostCount", text = boostText, textSize = 14 }),
				UI.HStack({ id = "Actions", gap = 6, children = actions }),
			},
		}))
		pres.refresh()
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			bar = bar,
			signals = signals,
			progress = progress,
			n = 0,
		}
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		for i = 1, 8 do
			state.signals[i]:set(state.n * 10 + i)
			state.signals[i]:set(state.n * 10 + i + 1)
			state.signals[i]:set(state.n * 10 + i + 2)
		end
		state.progress:set((state.n % 100) / 100)
		local mutate = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		local commit = os.clock() - t1
		-- M6: the full semantic chain, adapter activate -> handler -> signal ->
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
	teardown = function(state)
		state.bar.dispose()
	end,
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
		local core, _env, _sys, adapter, pres = newStack(profile)
		local selected = core:signal(1)
		local children = {}
		for i = 1, 40 do
			local isSel = core:memo(function(use)
				return use(selected) == i
			end)
			table.insert(children, UI.Toggle({ id = `Opt{i}`, label = `Option {i}`, value = isSel }))
		end
		pres.present(UI.Screen({ id = "Opts", gap = 2, children = children }))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, selected = selected, n = 0, tagCount = 0 }
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		state.selected:set((state.n % 40) + 1)
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
})

-- 13. async image grid over the REAL provider. Twelve avatars are acquired in a
-- scope, partially fulfilled, and the whole scope is released and rebuilt with
-- new keys — the shape a scrolling player list has, including the stale
-- completions a released handle must reject.
table.insert(scenes, {
	name = "async-image-grid",
	requirement = "UI-PERF-001",
	dataset = "12 AsyncImage over the real bounded provider; scope release + rebuild with new keys + partial drain per iter",
	samples = 120,
	warmup = 30,
	setup = function(profile)
		local core, _env, _sys, adapter, pres = newStack(profile)
		local provider = Facet.newResourceProvider(core, { maxConcurrent = 4, cacheBudget = 16 })
		local state = {
			core = core,
			adapter = adapter,
			pres = pres,
			provider = provider,
			scope = nil :: any,
			handle = nil :: any,
			images = {} :: { any },
			n = 0,
			stats = { dropped = 0, stale = 0, completed = 0 },
		}
		return state
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		-- release the previous generation: scope disposal is what makes any
		-- still-in-flight request's completion stale
		if state.handle ~= nil then
			state.pres.dismiss(state.handle)
			state.handle = nil
		end
		for _, img in state.images do
			if img.dispose ~= nil then
				img.dispose()
			end
		end
		if state.scope ~= nil then
			state.scope:dispose()
		end
		state.scope = state.core:scope()
		local images = {}
		local children = {}
		for i = 1, 12 do
			local img = Facet.newAsyncImage(Facet, state.core, {
				id = `Av{i}`,
				scope = state.scope,
				provider = state.provider,
				key = `rbxthumb://gen={state.n}&id={i}`,
			})
			images[i] = img
			table.insert(children, img.blueprint)
		end
		state.images = images
		local mount = os.clock() - t0
		local t1 = os.clock()
		state.handle = state.pres.present(UI.Screen({ id = "Avatars", gap = 2, children = children }))
		state.pres.refresh()
		local commit = os.clock() - t1
		-- drain what the concurrency window exposes; the rest are dropped when
		-- the next iteration releases the scope
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
	teardown = function(state)
		if state.scope ~= nil then
			state.scope:dispose()
		end
	end,
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
		local core, _env, _sys, adapter, pres = newStack(profile)
		pres.present(UI.Screen({ id = "Base", children = { UI.Text({ id = "T", text = "HUD" }) } }))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, n = 0 }
	end,
	run = function(state)
		state.n += 1
		local core = state.core
		local t0 = os.clock()
		local volume = core:signal(50)
		local quality = core:signal(2)
		local choice = core:signal("medium")
		local slider =
			Facet.newSlider(Facet, core, { id = "Vol", label = "Volume", value = volume, min = 0, max = 100 })
		local stepper =
			Facet.newStepper(Facet, core, { id = "Qual", label = "Quality", value = quality, min = 0, max = 4 })
		local picker = Facet.newPicker(Facet, core, {
			id = "Detail",
			label = "Detail",
			options = {
				{ value = "low", label = "Low" },
				{ value = "medium", label = "Medium" },
				{ value = "high", label = "High" },
			},
			selected = choice,
		})
		local bar = Facet.newProgressView(Facet, core, { id = "Load", value = 0.4 })
		local label = Facet.newLabel(Facet, core, { id = "Head", title = "Settings" })
		local toggles = {}
		for i = 1, 12 do
			table.insert(toggles, UI.Toggle({ id = `Flag{i}`, label = `Flag {i}`, value = i % 2 == 0 }))
		end
		local screen = UI.Screen({
			id = "Settings",
			padding = 12,
			gap = 6,
			children = {
				label.blueprint,
				slider.blueprint,
				stepper.blueprint,
				picker.blueprint,
				bar.blueprint,
				UI.VStack({ id = "Flags", gap = 4, children = toggles }),
			},
		})
		local build = os.clock() - t0
		local t1 = os.clock()
		local handle = state.pres.presentModal(screen)
		local open = os.clock() - t1
		local t2 = os.clock()
		state.pres.dismiss(handle)
		slider.dispose()
		stepper.dispose()
		picker.dispose()
		bar.dispose()
		label.dispose()
		return { build = build, open = open, close = os.clock() - t2 }
	end,
})

-- ---- the three theme-swap invalidation shapes -----------------------------
-- One fixture, three different swaps. Each scene records the SHAPE of the
-- invalidation it caused (how many probe rects moved) beside its cost, so
-- "a palette swap became a reflow" is a visible regression rather than a
-- slightly larger number.

local THEME_PROBES = { "/Fixture/Head", "/Fixture/Row/Go", "/Fixture/Row/Flag", "/Fixture/Bar" }

local function themeFixture(profile: any)
	local core, env, _sys, adapter, pres = newStack(profile)
	local bar = Facet.newProgressView(Facet, core, { id = "Bar", value = 0.6 })
	pres.present(UI.Screen({
		id = "Fixture",
		padding = 8,
		gap = 6,
		children = {
			UI.Text({ id = "Head", text = "Garage", textSize = 20 }),
			UI.HStack({
				id = "Row",
				gap = 8,
				children = {
					UI.Button({ id = "Go", label = "Go" }),
					UI.Toggle({ id = "Flag", label = "Flag", value = true }),
				},
			}),
			bar.blueprint,
		},
	}))
	pres.refresh()
	return core, env, adapter, pres, bar
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
			local core, env, adapter, pres, bar = themeFixture(profile)
			local snapshots = spec.snapshots(profile)
			env:set("themeMetrics", snapshots[1])
			pres.refresh()
			return {
				core = core,
				adapter = adapter,
				env = env,
				pres = pres,
				bar = bar,
				snapshots = snapshots,
				baseline = probeRects(adapter),
				moved = 0,
				n = 0,
			}
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
		teardown = function(state)
			state.bar.dispose()
		end,
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

-- 17. asset-backed swap: Studio Neutral (no art) against Fantasy Ornate (33
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
		local core, _env, _sys, adapter, pres = newStack(profile)
		local now = 0
		local clock = Facet.motion.newClock(core, {
			now = function()
				return now
			end,
		})
		local items = table.create(600)
		for i = 1, 600 do
			items[i] = { id = `chip{i}`, name = `Racer {i}` }
		end
		local rows = core:signal(items)
		local list = Facet.newVirtualList(Facet, core, {
			id = "Roster",
			rows = rows,
			key = function(item)
				return item.id
			end,
			rowHeight = 44,
			viewportHeight = math.max(120, math.floor(profile.viewport.h * 0.5)),
			cell = function(item)
				return UI.Text({ id = "Name", text = item.name, textSize = 15 })
			end,
		})
		local chips = {}
		local springs = {}
		for i = 1, 24 do
			table.insert(
				chips,
				UI.Box({
					id = `Chip{i}`,
					surface = "control",
					width = { type = "fixed", px = 24 },
					height = { type = "fixed", px = 24 },
				})
			)
			springs[i] = clock:spring(0, if i % 2 == 0 then "object" else "reward")
		end
		local banner = core:signal("ready")
		local handle = pres.present(UI.Screen({
			id = "Celebrate",
			padding = 6,
			gap = 4,
			children = {
				UI.Text({ id = "Banner", text = banner, textSize = 18 }),
				UI.HStack({ id = "Chips", gap = 4, children = chips }),
				list.blueprint,
			},
		}))
		pres.refresh()
		local beats = 0
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			controller = handle.controller,
			clock = clock,
			springs = springs,
			list = list,
			rows = rows,
			banner = banner,
			beats = beats,
			timeline = nil :: any,
			now = now,
			n = 0,
		}
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		-- the churn underneath: a re-sort that KEEPS every key, so the window slides
		-- over the same identities a live leaderboard does
		local current = state.rows:get() :: { any }
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
			state.controller.setPresentationTransform(`/Celebrate/Chips/Chip{i}`, { x = 0, y = spring:get() })
		end
		local motion = os.clock() - t1
		local t2 = os.clock()
		state.pres.refresh()
		return { mutate = mutate, motion = motion, commit = os.clock() - t2 }
	end,
	extras = function(state)
		local window = 0
		for _ in state.list.debugWindow() do
			window += 1
		end
		local stats = state.clock:stats()
		return {
			springs = #state.springs,
			activeMotions = state.clock:activeCount(),
			timelineBeats = state.beats,
			windowedRows = window,
			virtualRows = 600,
			-- the contract this scene exists to keep honest: one transaction per
			-- stepped frame, however many springs moved
			motionSteps = stats.steps,
			motionTransactions = stats.transactions,
			banner = state.banner:get(),
		}
	end,
	teardown = function(state)
		state.list.dispose()
		state.clock:dispose()
	end,
})

table.insert(
	scenes,
	themeSwapScene({
		name = "theme-swap-assets",
		kind = "asset-backed",
		dataset = "Studio Neutral <-> Fantasy Ornate (declared art + chrome recipes); swap + refresh per iter",
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
local function labStack(profile)
	local core, env, system, adapter, pres = newStack(profile)
	local provider = Facet.newResourceProvider(core)
	return core, env, system, adapter, pres, provider
end

local function labList(core: any, pres: any, provider: any, items: { any }, viewportHeight: number, profile: any)
	local rowsSignal = core:signal(items)
	local ownerScope = core:scope("perf-scene-rows")
	local values: { [string]: any } = {}
	local toggles: { [string]: any } = {}
	-- THE SAME ARRANGEMENT DECISION THE PLACE MAKES (2026-08-05). The reference profile
	-- is `floorAndroid` at 360x640 — a compact phone — so before this, every headless
	-- number for these two scenes was measured on a row overflowing its box by 132px.
	-- The work was real work, but the layout was not one anybody would ship, and a
	-- budget taken from it was guarding the wrong thing. Sharing `compactFor` is the
	-- whole point of sharing the row module.
	local compact = perf_rows.compactFor(profile.viewport.w)
	local list = Facet.newVirtualList(Facet, core, {
		id = "Rows",
		rows = rowsSignal,
		key = function(item: any)
			return item.id
		end,
		rowHeight = perf_rows.heightFor(compact),
		rowGap = perf_rows.ROW_GAP,
		viewportHeight = viewportHeight,
		overscan = perf_rows.OVERSCAN,
		selection = "single",
		cell = function(item: any, cellCtx: any)
			return perf_rows.cell(Facet, core, item, {
				scope = cellCtx.scope,
				ownerScope = ownerScope,
				provider = provider,
				values = values,
				toggles = toggles,
				compact = compact,
			})
		end,
	})
	pres.present(UI.Screen({ id = "PerfWorkload", padding = 8, gap = 6, children = { list.blueprint } }))
	pres.refresh()
	return list, rowsSignal
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
		local core, _env, _sys, adapter, pres, provider = labStack(profile)
		local items = perf_dataset.build({ count = 2000, seed = 1, content = "normal" })
		local viewportHeight = math.max(120, profile.viewport.h - 80)
		local list = labList(core, pres, provider, items, viewportHeight, profile)
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			list = list,
			provider = provider,
			y = 0,
			viewportHeight = viewportHeight,
			compact = perf_rows.compactFor(profile.viewport.w),
			digest = perf_dataset.digest(items),
		}
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
		state.list.scrollTop:set(state.y)
		local scroll = os.clock() - t0
		local t1 = os.clock()
		state.pres.refresh()
		return { scroll = scroll, commit = os.clock() - t1 }
	end,
	teardown = function(state)
		state.list.dispose()
	end,
	extras = function(state)
		local n = 0
		for _ in state.list.debugWindow() do
			n += 1
		end
		return {
			windowedRows = n,
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
		local core, _env, _sys, adapter, pres, provider = labStack(profile)
		local items = perf_dataset.build({ count = 800, seed = 1, content = "normal" })
		local viewportHeight = math.max(120, profile.viewport.h - 80)
		local list, rowsSignal = labList(core, pres, provider, items, viewportHeight, profile)
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			list = list,
			rowsSignal = rowsSignal,
			viewportHeight = viewportHeight,
			compact = perf_rows.compactFor(profile.viewport.w),
			n = 0,
		}
	end,
	run = function(state)
		state.n += 1
		local t0 = os.clock()
		local items = table.clone(state.rowsSignal:get())
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
		state.rowsSignal:set(items)
		state.pres.refresh()
		return { mutate = mutate, commit = os.clock() - t1 }
	end,
	teardown = function(state)
		state.list.dispose()
	end,
	extras = function(state)
		local n = 0
		for _ in state.list.debugWindow() do
			n += 1
		end
		return {
			windowedRows = n,
			windowBound = perf_rows.expectedWindow(state.viewportHeight, state.compact),
			logicalRows = #state.rowsSignal:get(),
			datasetVersion = perf_dataset.VERSION,
			rowVersion = perf_rows.VERSION,
		}
	end,
})

return scenes
