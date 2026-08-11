--!strict
-- Task 11 perf row (Global Constraints director directive 2026-08-10):
-- 200 wrapped-but-CLOSED rows vs 200 unwrapped baseline rows, same content,
-- same viewport, same scroll/fling drive shape `bench/perf_scenes.luau`'s
-- own "lab-dense-scroll" scene uses (scrollTop:set + pres.refresh(), timed
-- with os.clock() — headless Lune / evidence class E1, trend-only, NOT a
-- device result). Standalone script (not wired into the gated bench/budget
-- files) so this one-off comparison does not touch shared perf gates.
-- Reproduce: `lune run artifacts/row-actions/perf_workload.luau` from the
-- repo root. Results are in artifacts/row-actions/device-matrix.md's perf
-- section (measured 2026-08-10).

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")

local ROW_COUNT = 200
local VIEWPORT = { w = 400, h = 700 }
local ROW_HEIGHT = 56
local ROW_GAP = 4
local SAMPLES = 150
local WARMUP = 30

local function buildItems(): { any }
	local out = {}
	for i = 1, ROW_COUNT do
		out[i] = { id = "row" .. i, subject = "Subject line " .. i, preview = "Preview text for row " .. i }
	end
	return out
end

-- the representative row content EVERY variant shares byte-for-byte:
-- image-ish box + 2-line text stack + a control (mirrors bench/perf_scenes'
-- own "image + 2 text + toggle" shape; a Toggle stands in for "a
-- representative control", matching the plan's row description)
local function rowContent(UI: any, core: any, item: any): any
	return UI.HStack({
		id = "Row",
		gap = "s",
		alignV = "center",
		width = { type = "fill", weight = 1 },
		padding = { top = 8, bottom = 8, left = 10, right = 10 },
		children = {
			UI.Box({
				id = "Thumb",
				surface = "raised",
				width = { type = "fixed", px = 32 },
				height = { type = "fixed", px = 32 },
			}),
			UI.VStack({
				id = "Text",
				gap = 2,
				width = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Subject", text = item.subject, textSize = 14 }),
					UI.Text({ id = "Preview", text = item.preview, textSize = 12, role = "secondary" }),
				},
			}),
			UI.Toggle({ id = "Flag", label = "Flag", value = core:signal(false) }),
		},
	})
end

local function actionsFor(item: any): any
	return {
		leading = {
			{ id = "read", role = "normal", label = "Mark Read", onAction = function() end },
		},
		trailing = {
			{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
			{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
		},
		fullSwipe = true,
	}
end

local function buildWorld(wrapped: boolean)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local UI = LuauUI.UI

	local items = buildItems()
	local rows = core:signal(items)
	local list = LuauUI.newVirtualList(LuauUI, core, {
		id = "Rows",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		rowGap = ROW_GAP,
		viewportHeight = VIEWPORT.h - 40,
		overscan = 2,
		selection = "none",
		cell = function(item: any, cellCtx: any): any
			local content = rowContent(UI, core, item)
			if not wrapped then
				return content
			end
			local actions = actionsFor(item)
			local built = LuauUI.newRowActions(LuauUI, core, {
				id = item.id,
				width = { type = "fill", weight = 1 },
				content = content,
				leading = actions.leading,
				trailing = actions.trailing,
				fullSwipe = actions.fullSwipe,
			})
			cellCtx.scope:own(built.dispose)
			return built.blueprint
		end,
	})
	local screen = UI.Screen({ id = "PerfWorkload", padding = 8, children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	return { core = core, adapter = adapter, pres = pres, list = list, handle = handle }
end

local function windowedCount(list: any): number
	local n = 0
	for _ in list.debugWindow() do
		n += 1
	end
	return n
end

-- INSTANCE CENSUS: total adapter-tracked nodes for the mounted (windowed)
-- rows, divided by the windowed row count — same content both variants, so
-- the delta IS the wrapper's per-row instance cost.
local function instancesPerRow(world: any): (number, number)
	local total = 0
	for _ in world.adapter.paths() do
		total += 1
	end
	local windowed = windowedCount(world.list)
	return total, windowed
end

local function percentile(samples: { number }, p: number): number
	local sorted = table.clone(samples)
	table.sort(sorted)
	local idx = math.max(1, math.ceil(p * #sorted))
	return sorted[idx]
end

-- STEADY SCROLL: 61px increments (deliberately not a row multiple — same
-- reasoning bench/perf_scenes.luau's own lab-dense-scroll uses: every
-- iteration lands on a fresh partial boundary, never re-measuring the same
-- solved state twice).
local function runSteadyScroll(world: any, samples: number, warmup: number): { number }
	local extent = ROW_COUNT * (ROW_HEIGHT + ROW_GAP) - (VIEWPORT.h - 40)
	local y = 0
	local timings = {}
	for i = 1, warmup + samples do
		y += 61
		if y > extent then
			y = 0
		end
		local t0 = os.clock()
		world.list.scrollTop:set(y)
		world.pres.refresh()
		local dt = os.clock() - t0
		if i > warmup then
			table.insert(timings, dt)
		end
	end
	return timings
end

-- IDLE STEADY SCROLL: small (4px) increments that stay WELL inside the
-- current window for many steps before crossing a row boundary — isolates
-- "no active mount/unmount" per-refresh cost from the 61px scene's boundary
-- churn (director directive (a)/(b): a closed row should be near-free when
-- the window is NOT changing membership). Reported alongside the 61px number
-- rather than instead of it, because the shipped codebase's own
-- `lab-dense-scroll` scene IS the 61px boundary-churn shape.
local function runIdleScroll(world: any, samples: number, warmup: number): { number }
	local y = 0
	local timings = {}
	for i = 1, warmup + samples do
		y += 4
		if y > 40 then -- well under one row (60px); resets before ever crossing one
			y = 0
		end
		local t0 = os.clock()
		world.list.scrollTop:set(y)
		world.pres.refresh()
		local dt = os.clock() - t0
		if i > warmup then
			table.insert(timings, dt)
		end
	end
	return timings
end

-- FLING: a large single jump (a third of the scrollable extent) per
-- iteration — the ballistic-release shape a real fling produces, distinct
-- from steady scroll's small per-frame delta.
local function runFling(world: any, samples: number, warmup: number): { number }
	local extent = math.max(1, ROW_COUNT * (ROW_HEIGHT + ROW_GAP) - (VIEWPORT.h - 40))
	local timings = {}
	local dir = 1
	local y = 0
	for i = 1, warmup + samples do
		y += dir * (extent / 3)
		if y > extent then
			y = extent
			dir = -1
		elseif y < 0 then
			y = 0
			dir = 1
		end
		local t0 = os.clock()
		world.list.scrollTop:set(y)
		world.pres.refresh()
		local dt = os.clock() - t0
		if i > warmup then
			table.insert(timings, dt)
		end
	end
	return timings
end

local function summarize(label: string, timings: { number }): any
	local sum = 0
	for _, v in timings do
		sum += v
	end
	return {
		label = label,
		n = #timings,
		mean_ms = (sum / #timings) * 1000,
		p50_ms = percentile(timings, 0.5) * 1000,
		p95_ms = percentile(timings, 0.95) * 1000,
	}
end

print("Building unwrapped baseline (200 rows)...")
local baseline = buildWorld(false)
local baseTotal, baseWindowed = instancesPerRow(baseline)
print(
	("  windowed rows: %d, total adapter nodes: %d, nodes/windowed-row: %.2f"):format(
		baseWindowed,
		baseTotal,
		baseTotal / baseWindowed
	)
)

print("Building wrapped-but-closed (200 rows)...")
local wrapped = buildWorld(true)
local wrapTotal, wrapWindowed = instancesPerRow(wrapped)
print(
	("  windowed rows: %d, total adapter nodes: %d, nodes/windowed-row: %.2f"):format(
		wrapWindowed,
		wrapTotal,
		wrapTotal / wrapWindowed
	)
)

local wrapperNodesPerRow = (wrapTotal - baseTotal) / wrapWindowed
print(("  WRAPPER COST: +%.2f nodes/row (closed)"):format(wrapperNodesPerRow))

print("\nSteady scroll: baseline...")
local baseScroll = summarize("baseline-steady-scroll", runSteadyScroll(baseline, SAMPLES, WARMUP))
print("Steady scroll: wrapped...")
local wrapScroll = summarize("wrapped-steady-scroll", runSteadyScroll(wrapped, SAMPLES, WARMUP))

print("Fling: baseline...")
local baseFling = summarize("baseline-fling", runFling(baseline, SAMPLES, WARMUP))
print("Fling: wrapped...")
local wrapFling = summarize("wrapped-fling", runFling(wrapped, SAMPLES, WARMUP))

print("Idle scroll (no boundary churn): baseline...")
local baseIdle = summarize("baseline-idle-scroll", runIdleScroll(baseline, SAMPLES, WARMUP))
print("Idle scroll (no boundary churn): wrapped...")
local wrapIdle = summarize("wrapped-idle-scroll", runIdleScroll(wrapped, SAMPLES, WARMUP))

local function pctDelta(base: number, over: number): number
	if base <= 0 then
		return 0
	end
	return (over - base) / base * 100
end

print("\n=== RESULTS ===")
print(
	("baseline steady-scroll p50=%.4fms mean=%.4fms p95=%.4fms"):format(
		baseScroll.p50_ms,
		baseScroll.mean_ms,
		baseScroll.p95_ms
	)
)
print(
	("wrapped  steady-scroll p50=%.4fms mean=%.4fms p95=%.4fms"):format(
		wrapScroll.p50_ms,
		wrapScroll.mean_ms,
		wrapScroll.p95_ms
	)
)
print(("  delta (p50): %.2f%%"):format(pctDelta(baseScroll.p50_ms, wrapScroll.p50_ms)))
print(("  delta (mean): %.2f%%"):format(pctDelta(baseScroll.mean_ms, wrapScroll.mean_ms)))

print(
	("baseline fling p50=%.4fms mean=%.4fms p95=%.4fms"):format(baseFling.p50_ms, baseFling.mean_ms, baseFling.p95_ms)
)
print(
	("wrapped  fling p50=%.4fms mean=%.4fms p95=%.4fms"):format(wrapFling.p50_ms, wrapFling.mean_ms, wrapFling.p95_ms)
)
print(("  delta (p50): %.2f%%"):format(pctDelta(baseFling.p50_ms, wrapFling.p50_ms)))
print(("  delta (mean): %.2f%%"):format(pctDelta(baseFling.mean_ms, wrapFling.mean_ms)))

print(
	("baseline idle-scroll p50=%.4fms mean=%.4fms p95=%.4fms"):format(
		baseIdle.p50_ms,
		baseIdle.mean_ms,
		baseIdle.p95_ms
	)
)
print(
	("wrapped  idle-scroll p50=%.4fms mean=%.4fms p95=%.4fms"):format(
		wrapIdle.p50_ms,
		wrapIdle.mean_ms,
		wrapIdle.p95_ms
	)
)
print(("  delta (p50): %.2f%%"):format(pctDelta(baseIdle.p50_ms, wrapIdle.p50_ms)))
print(("  delta (mean): %.2f%%"):format(pctDelta(baseIdle.mean_ms, wrapIdle.mean_ms)))

print(("\nwrapper nodes/closed-row: %.2f (budget: <=4)"):format(wrapperNodesPerRow))

local budgetScrollOk = pctDelta(baseScroll.mean_ms, wrapScroll.mean_ms) <= 5
local budgetFlingOk = pctDelta(baseFling.mean_ms, wrapFling.mean_ms) <= 5
local budgetWrapperOk = wrapperNodesPerRow <= 4
print(("\nBUDGET steady-scroll <=5%%: %s"):format(if budgetScrollOk then "PASS" else "FAIL"))
print(("BUDGET fling <=5%%: %s"):format(if budgetFlingOk then "PASS" else "FAIL"))
print(("BUDGET wrapper<=4 instances/row: %s"):format(if budgetWrapperOk then "PASS" else "FAIL"))

baseline.list.dispose()
wrapped.list.dispose()
