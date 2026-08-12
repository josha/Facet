--!strict
-- HISTORICAL EVIDENCE — KEEP. This is the scoping experiment whose numbers
-- docs/plans/row-actions-hosted-mode-design.md §"Measured floors" cites (it is
-- what proved the hosted design's floor, and what surfaced the one-pass
-- measurement-order bias the A/A control row records). It measures a SIMULATED
-- floor, not the shipped feature: the budgeted measurement of the real hosted
-- integration lives in perf_workload.luau, which is de-biased (interleaved) and
-- is the file to run for any budget call. Kept unmodified so the design doc's
-- table stays reproducible.
--
-- FLOOR EXPERIMENT (row-actions perf mission scoping, 2026-08-12; TEMP, not a
-- gate artifact): measures the closed-row cost floor of the proposed "hosted
-- row-actions" design — baseline rows plus ONLY what a closed hosted row would
-- carry: one per-row offsetX memo on the cell root (reading a shared
-- engagedKey signal), four trampoline closures (the lazy-engine stubs), and
-- one constant per-list overlay When at the screen. NO wrapper instances.
-- Same drive shapes as perf_workload.luau. Reproduce:
-- `lune run artifacts/row-actions/perf_floor_experiment.luau`

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

local function rowContent(UI: any, core: any, item: any, offsetX: any): any
	return UI.HStack({
		id = "Row",
		gap = "s",
		alignV = "center",
		offsetX = offsetX,
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

local function buildWorld(hosted: boolean)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local UI = LuauUI.UI

	local items = buildItems()
	local rows = core:signal(items)
	-- the one-open coordinator means at most ONE row is ever engaged: a single
	-- shared signal, read by every row's offsetX memo (dynamic deps keep the
	-- offset read out of disengaged rows)
	local engagedKey = core:signal(nil :: string?)
	local engagedOffset = core:signal(0)
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
			-- LEAN FLOOR: the slide rides the presentation channel (like the
			-- DropLine / drag ghosts), so a closed row declares NO per-row memo
			-- and NO reactive offsetX; the 4 pointer trampolines are SHARED per
			-- list (handlers receive the row path), so a closed row adds zero
			-- Luau allocations at mount. The cell is a pure passthrough.
			return rowContent(UI, core, item, nil)
		end,
	})
	local screenChildren: { any } = { list.blueprint }
	if hosted then
		-- 3) the constant per-list tray overlay (one When, closed): mirrors the
		-- shared-overlay design — ONE structural region for the whole list
		local overlayOn = core:memo(function(use)
			return use(engagedKey) ~= nil
		end)
		table.insert(
			screenChildren,
			UI.When({
				id = "TrayOverlay",
				condition = overlayOn,
				thenView = function()
					return UI.Box({ id = "Trays", width = { type = "fixed", px = 100 }, height = { type = "fixed", px = 56 } })
				end,
			})
		)
	end
	local screen = UI.Screen({ id = "PerfWorkload", padding = 8, children = screenChildren })
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

local function summarize(timings: { number }): any
	local sum = 0
	for _, v in timings do
		sum += v
	end
	return {
		n = #timings,
		mean_ms = (sum / #timings) * 1000,
		p50_ms = percentile(timings, 0.5) * 1000,
		p95_ms = percentile(timings, 0.95) * 1000,
	}
end

local function pctDelta(base: number, over: number): number
	if base <= 0 then
		return 0
	end
	return (over - base) / base * 100
end

print("Building unwrapped baseline (200 rows)...")
local baseline = buildWorld(false)
local baseTotal, baseWindowed = instancesPerRow(baseline)
print(("  windowed rows: %d, total nodes: %d"):format(baseWindowed, baseTotal))

print("Building hosted-floor (200 rows)...")
local hosted = buildWorld(true)
local hostTotal, hostWindowed = instancesPerRow(hosted)
print(("  windowed rows: %d, total nodes: %d"):format(hostWindowed, hostTotal))
print(("  FLOOR COST: +%.2f nodes/row (closed)"):format((hostTotal - baseTotal) / hostWindowed))

print("Steady scroll: baseline...")
local baseScroll = summarize(runSteadyScroll(baseline, SAMPLES, WARMUP))
print("Steady scroll: hosted-floor...")
local hostScroll = summarize(runSteadyScroll(hosted, SAMPLES, WARMUP))
print("Fling: baseline...")
local baseFling = summarize(runFling(baseline, SAMPLES, WARMUP))
print("Fling: hosted-floor...")
local hostFling = summarize(runFling(hosted, SAMPLES, WARMUP))

print("\n=== FLOOR RESULTS ===")
print(("steady: base mean=%.4fms hosted mean=%.4fms delta=%.2f%%"):format(
	baseScroll.mean_ms,
	hostScroll.mean_ms,
	pctDelta(baseScroll.mean_ms, hostScroll.mean_ms)
))
print(("fling:  base mean=%.4fms hosted mean=%.4fms delta=%.2f%%"):format(
	baseFling.mean_ms,
	hostFling.mean_ms,
	pctDelta(baseFling.mean_ms, hostFling.mean_ms)
))

baseline.list.dispose()
hosted.list.dispose()
