--!strict
-- Task 11 perf row (Global Constraints director directive 2026-08-10):
-- 200 actionable-but-CLOSED rows vs 200 plain baseline rows, same content,
-- same viewport, same scroll/fling drive shape `bench/perf_scenes.luau`'s
-- own "lab-dense-scroll" scene uses (scrollTop:set + pres.refresh(), timed
-- with os.clock() — headless Lune / evidence class E1, trend-only, NOT a
-- device result). Standalone script (not wired into the gated bench/budget
-- files) so this one-off comparison does not touch shared perf gates.
-- Reproduce: `lune run artifacts/row-actions/perf_workload.luau` from the
-- repo root.
--
-- WHERE THE RESULTS LIVE: device-matrix.md's perf section still records the
-- SUPERSEDED one-pass wrapper numbers (measured 2026-08-10, before this
-- file was de-biased and before the hosted integration existed) — do not
-- read them as this script's output. The hosted results land there in the
-- gate task, as >=5-run MEANS; a single run of this script is not a result.
--
-- ===================================================================
-- WHY THE MEASUREMENT IS INTERLEAVED (row-actions hosted mode, Task 7)
-- ===================================================================
-- The original version of this file built and measured the baseline world
-- first and the wrapped world second, in one pass each. An A/A CONTROL —
-- the identical script with BOTH worlds built plain, so the true delta is
-- zero by construction — showed that fixed order carries a systematic
-- second-world penalty:
--
--   A/A control, 3 runs, this machine (2026-08-12):
--     steady mean delta  +0.77% / +0.96% / +2.20%   (mean +1.3pp)
--     fling  mean delta  +5.96% / +5.69% / +5.23%   (mean +5.6pp)
--     idle   mean delta  +4.02% / +0.57% / +1.34%
--
-- i.e. two IDENTICAL worlds "failed" a <=5% fling budget purely on
-- measurement order (allocator/GC state accumulated by the first world's
-- 180 refreshes is paid by the second). A ceiling applied to a one-pass
-- A/B is therefore not a gate, it is a coin flip.
--
-- The fix here changes only the SCHEDULE, never the drive: per shape each
-- world is measured in TWO blocks of SAMPLES/2, run in ABBA order
-- (base -> other -> other -> base), and each world's two blocks are
-- concatenated. Every world still walks its own 30-warmup + 150-sample
-- drive sequence in exactly the committed order (the drive state is
-- threaded across a world's two blocks, so block 2 continues where block 1
-- stopped) — the sample SET per world is byte-identical to the one-pass
-- version; only who holds the CPU when is different.
--
-- ABBA, NOT ABAB (review round 1): the first interleaved cut used ABAB,
-- which still left the second world second in BOTH pairs. Its own A/A
-- control measured a one-sided residual of +1.15pp fling / +2.57pp steady —
-- ~30% of a 5% budget spent on schedule. ABBA gives each world one leader
-- slot and one follower slot, so a monotone drift cancels to first order.
--
-- THE A/A CONTROL IS LOAD-BEARING, NOT A ONE-TIME SANITY CHECK: ABBA's own
-- block asymmetry (B's two blocks are CONTIGUOUS; A re-enters COLD after B
-- runs both of its blocks back to back) nets to ~0 empirically on this
-- workload (measured residual -0.01pp steady / -0.24pp fling, 6 runs) —
-- that is a measured result, not a structural guarantee. Re-run the A/A
-- control whenever the schedule (block count/order) or the drive constants
-- (SAMPLES, WARMUP, ROW_COUNT, viewport, step sizes) change, before trusting
-- a budget call against the new numbers.
--
-- Run-to-run noise on top of this is large (per-run sd ~2.3pp on fling,
-- and single runs have printed both +6% and -1.5% for the same code): a
-- budget call needs the MEAN OF >=5 RUNS. A single run is not a result.
--
-- THREE WORLDS ARE MEASURED:
--   baseline  — plain rows (the budget's denominator)
--   hosted    — `rowActions = actionsFor` on the list spec: the BLESSED
--               integration (VirtualList hosts the feature; a closed row
--               mounts nothing extra and builds no engine). BUDGETED.
--   legacy-standalone-wrap — the old shape: every cell manually wrapped in
--               `newRowActions`, a 5-instance composite per row whether or
--               not it is ever touched. INFORMATIONAL ONLY, printed so the
--               cost the hosted design removed stays visible. Measured
--               against its OWN freshly built baseline world (`baseline2`),
--               interleaved the same way, so its numbers are un-biased too
--               rather than inheriting the hosted pair's ordering. Both are
--               built AFTER the budgeted pair has been measured, so their
--               281 extra resident nodes cannot compress the budgeted delta.

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")

local ROW_COUNT = 200
local VIEWPORT = { w = 400, h = 700 }
local ROW_HEIGHT = 56
local ROW_GAP = 4
local SAMPLES = 150
local WARMUP = 30
-- the interleave: SAMPLES split into two blocks per world, run ABBA (base,
-- other, other, base). Halves of an even 150 => 75 + 75 = the full 150.
local BLOCK = SAMPLES // 2

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

-- mode: "base" (plain rows) | "hosted" (spec.rowActions) | "legacy" (manual
-- per-cell newRowActions wrap). Everything else is held identical by
-- construction — same items, same viewport, same content, same spec.
local function buildWorld(mode: string)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local UI = LuauUI.UI

	local items = buildItems()
	local rows = core:signal(items)
	local spec: any = {
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
		-- read ONLY by hosted row actions (tray metrics), and only when an
		-- engine is actually built; passed on all three worlds so the specs
		-- differ in exactly one key.
		env = env,
		cell = function(item: any, cellCtx: any): any
			local content = rowContent(UI, core, item)
			if mode ~= "legacy" then
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
	}
	if mode == "hosted" then
		-- THE BLESSED INTEGRATION: the same actions table the legacy world
		-- hands to `newRowActions`, declared on the list instead.
		spec.rowActions = actionsFor
	end
	local list = LuauUI.newVirtualList(LuauUI, core, spec)
	local screen = UI.Screen({ id = "PerfWorkload", padding = 8, children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	return { core = core, adapter = adapter, pres = pres, list = list, handle = handle, mode = mode }
end

local function windowedCount(list: any): number
	local n = 0
	for _ in list.debugWindow() do
		n += 1
	end
	return n
end

-- INSTANCE CENSUS: total adapter-tracked nodes for the mounted (windowed)
-- rows, divided by the windowed row count — same content every variant, so
-- the delta IS the variant's per-row instance cost.
local function instancesPerRow(world: any): (number, number)
	local total = 0
	for _ in world.adapter.paths() do
		total += 1
	end
	local windowed = windowedCount(world.list)
	return total, windowed
end

-- SANITY GUARD (hosted only): a budgeted hosted measurement is only honest
-- if every row stayed CLOSED and UNTOUCHED for the whole run — no gesture,
-- no lazily built engine. Asserted at the end of every hosted block.
local function assertHostedIdle(world: any, where: string): number
	local dbg = world.list._hostedDebug()
	assert(dbg.engineCount == 0, `hosted world built {dbg.engineCount} engine(s) during {where} — not a closed run`)
	assert(dbg.engagedKey == nil, `hosted world engaged row '{tostring(dbg.engagedKey)}' during {where}`)
	return dbg.engineCount
end

local function percentile(samples: { number }, p: number): number
	local sorted = table.clone(samples)
	table.sort(sorted)
	local idx = math.max(1, math.ceil(p * #sorted))
	return sorted[idx]
end

-- DRIVE STATE, threaded across a world's two measurement blocks so the
-- interleave never restarts a drive: block 2 continues exactly where block 1
-- stopped, and a world's full 30+150 sequence is the committed one.
local function newDrive(): any
	return { y = 0, dir = 1 }
end

-- STEADY SCROLL: 61px increments (deliberately not a row multiple — same
-- reasoning bench/perf_scenes.luau's own lab-dense-scroll uses: every
-- iteration lands on a fresh partial boundary, never re-measuring the same
-- solved state twice).
local function runSteadyScroll(world: any, drive: any, samples: number, warmup: number): { number }
	local extent = ROW_COUNT * (ROW_HEIGHT + ROW_GAP) - (VIEWPORT.h - 40)
	local timings = {}
	for i = 1, warmup + samples do
		drive.y += 61
		if drive.y > extent then
			drive.y = 0
		end
		local t0 = os.clock()
		world.list.scrollTop:set(drive.y)
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
local function runIdleScroll(world: any, drive: any, samples: number, warmup: number): { number }
	local timings = {}
	for i = 1, warmup + samples do
		drive.y += 4
		if drive.y > 40 then -- well under one row (60px); resets before ever crossing one
			drive.y = 0
		end
		local t0 = os.clock()
		world.list.scrollTop:set(drive.y)
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
local function runFling(world: any, drive: any, samples: number, warmup: number): { number }
	local extent = math.max(1, ROW_COUNT * (ROW_HEIGHT + ROW_GAP) - (VIEWPORT.h - 40))
	local timings = {}
	for i = 1, warmup + samples do
		drive.y += drive.dir * (extent / 3)
		if drive.y > extent then
			drive.y = extent
			drive.dir = -1
		elseif drive.y < 0 then
			drive.y = 0
			drive.dir = 1
		end
		local t0 = os.clock()
		world.list.scrollTop:set(drive.y)
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

local function concat(a: { number }, b: { number }): { number }
	local out = table.clone(a)
	for _, v in b do
		table.insert(out, v)
	end
	return out
end

--[[ THE INTERLEAVED PAIR, in ABBA ORDER — A, B, B, A — of SAMPLES/2 each, with
	the 30-sample warmup paid on each world's FIRST block only (the world is
	warm for its second). Each world's two blocks are concatenated, so both
	summaries are over the same 150 samples of the same drive positions.

	WHY ABBA AND NOT ABAB (review round 1, P1). Splitting into blocks halves how
	much first-world drift world B eats, but ABAB leaves B second in BOTH pairs,
	so the residual is one-sided: an A/A control through the ABAB schedule still
	measured +1.15pp on fling and +2.57pp on steady — ~30% of a 5% budget spent
	on schedule alone. ABBA puts each world once in the "leader" slot and once
	in the "follower" slot, so a monotone drift over the four blocks cancels to
	first order instead of accumulating on one side. ]]
local function interleavedPair(shape: string, driver: any, worldA: any, worldB: any, labelA: string, labelB: string)
	local driveA, driveB = newDrive(), newDrive()
	local a1 = driver(worldA, driveA, BLOCK, WARMUP)
	local b1 = driver(worldB, driveB, BLOCK, WARMUP)
	if worldB.mode == "hosted" then
		assertHostedIdle(worldB, `{shape} block 1`)
	end
	local b2 = driver(worldB, driveB, SAMPLES - BLOCK, 0)
	if worldB.mode == "hosted" then
		assertHostedIdle(worldB, `{shape} block 2`)
	end
	local a2 = driver(worldA, driveA, SAMPLES - BLOCK, 0)
	return summarize(`{labelA}-{shape}`, concat(a1, a2)), summarize(`{labelB}-{shape}`, concat(b1, b2))
end

local function pctDelta(base: number, over: number): number
	if base <= 0 then
		return 0
	end
	return (over - base) / base * 100
end

local function report(base: any, over: any, overName: string)
	print(("%-28s p50=%.4fms mean=%.4fms p95=%.4fms"):format(base.label, base.p50_ms, base.mean_ms, base.p95_ms))
	print(("%-28s p50=%.4fms mean=%.4fms p95=%.4fms"):format(over.label, over.p50_ms, over.mean_ms, over.p95_ms))
	print(("  %s delta (p50): %.2f%%"):format(overName, pctDelta(base.p50_ms, over.p50_ms)))
	print(("  %s delta (mean): %.2f%%"):format(overName, pctDelta(base.mean_ms, over.mean_ms)))
end

print("Building baseline (plain rows, 200)...")
local baseline = buildWorld("base")
local baseTotal, baseWindowed = instancesPerRow(baseline)
print(
	("  windowed rows: %d, total adapter nodes: %d, nodes/windowed-row: %.2f"):format(
		baseWindowed,
		baseTotal,
		baseTotal / baseWindowed
	)
)

print("Building hosted (spec.rowActions, all rows closed, 200)...")
local hosted = buildWorld("hosted")
local hostedTotal, hostedWindowed = instancesPerRow(hosted)
print(
	("  windowed rows: %d, total adapter nodes: %d, nodes/windowed-row: %.2f"):format(
		hostedWindowed,
		hostedTotal,
		hostedTotal / hostedWindowed
	)
)
print(("  hosted engines at build: %d"):format(assertHostedIdle(hosted, "build")))

-- census: same method as the committed workload — (variant total - baseline
-- total) / windowed rows.
local hostedNodesPerRow = (hostedTotal - baseTotal) / hostedWindowed
print(("  HOSTED COST: +%.2f nodes/row (closed)"):format(hostedNodesPerRow))

--[[ THE BUDGETED PAIR RUNS FIRST, AND ALONE (review round 1, P3): the legacy
	world and its baseline2 are built AFTER it. Building all four up front left
	281 extra adapter nodes (legacy's 5-instance-per-row composites plus a whole
	second baseline) resident on the heap for the whole budgeted measurement —
	symmetric across baseline and hosted, but it inflates both sides' absolute
	cost and so COMPRESSES the delta the budget is read from. The informational
	pair pays that cost instead, where it cannot flatter the number that gates. ]]
print("\nInterleaved steady scroll (base/hosted, ABBA)...")
local baseScroll, hostedScroll =
	interleavedPair("steady-scroll", runSteadyScroll, baseline, hosted, "baseline", "hosted")
print("Interleaved fling (base/hosted, ABBA)...")
local baseFling, hostedFling = interleavedPair("fling", runFling, baseline, hosted, "baseline", "hosted")
print("Interleaved idle scroll (base/hosted, ABBA)...")
local baseIdle, hostedIdle = interleavedPair("idle-scroll", runIdleScroll, baseline, hosted, "baseline", "hosted")

print("\nBuilding baseline2 (the legacy world's own un-biased denominator)...")
local baseline2 = buildWorld("base")
local base2Total, base2Windowed = instancesPerRow(baseline2)
print(
	("  windowed rows: %d, total adapter nodes: %d, nodes/windowed-row: %.2f"):format(
		base2Windowed,
		base2Total,
		base2Total / base2Windowed
	)
)
print("Building legacy-standalone-wrap (manual newRowActions per cell, 200)...")
local legacy = buildWorld("legacy")
local legacyTotal, legacyWindowed = instancesPerRow(legacy)
print(
	("  windowed rows: %d, total adapter nodes: %d, nodes/windowed-row: %.2f"):format(
		legacyWindowed,
		legacyTotal,
		legacyTotal / legacyWindowed
	)
)
-- legacy's census is taken against BASELINE2 (review round 1, P4) — the same
-- world that is its time denominator, so the instance number and the ms number
-- are statements about the same pair.
local legacyNodesPerRow = (legacyTotal - base2Total) / legacyWindowed
print(("  LEGACY COST: +%.2f nodes/row (closed, vs baseline2) [informational]"):format(legacyNodesPerRow))

print("\n[informational] Interleaved steady scroll (base2/legacy, ABBA)...")
local base2Scroll, legacyScroll =
	interleavedPair("steady-scroll", runSteadyScroll, baseline2, legacy, "baseline2", "legacy")
print("[informational] Interleaved fling (base2/legacy, ABBA)...")
local base2Fling, legacyFling = interleavedPair("fling", runFling, baseline2, legacy, "baseline2", "legacy")
print("[informational] Interleaved idle scroll (base2/legacy, ABBA)...")
local base2Idle, legacyIdle = interleavedPair("idle-scroll", runIdleScroll, baseline2, legacy, "baseline2", "legacy")

print("\n=== RESULTS: HOSTED (budgeted) ===")
report(baseScroll, hostedScroll, "hosted")
report(baseFling, hostedFling, "hosted")
report(baseIdle, hostedIdle, "hosted")
print(("hosted engines built over the whole run: %d (rows stayed closed)"):format(assertHostedIdle(hosted, "final")))

print("\n=== RESULTS: LEGACY STANDALONE WRAP (informational, NOT budgeted) ===")
report(base2Scroll, legacyScroll, "legacy")
report(base2Fling, legacyFling, "legacy")
report(base2Idle, legacyIdle, "legacy")

print(("\nhosted nodes/closed-row: %.2f (budget: <=4)"):format(hostedNodesPerRow))
print(("legacy nodes/closed-row: %.2f (vs baseline2) [informational]"):format(legacyNodesPerRow))

local budgetScrollOk = pctDelta(baseScroll.mean_ms, hostedScroll.mean_ms) <= 5
local budgetFlingOk = pctDelta(baseFling.mean_ms, hostedFling.mean_ms) <= 5
local budgetWrapperOk = hostedNodesPerRow <= 4
print(("\nBUDGET hosted steady-scroll <=5%%: %s"):format(if budgetScrollOk then "PASS" else "FAIL"))
print(("BUDGET hosted fling <=5%%: %s"):format(if budgetFlingOk then "PASS" else "FAIL"))
print(("BUDGET hosted <=4 instances/row: %s"):format(if budgetWrapperOk then "PASS" else "FAIL"))
print("(single-run deltas carry ~2.3pp sd — call the budget on >=5-run MEANS)")

baseline.list.dispose()
hosted.list.dispose()
baseline2.list.dispose()
legacy.list.dispose()
