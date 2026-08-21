--!strict
-- T15 probe (RR-5): does coalescing fresh-`{}` memos behind VALUE eq change any
-- perf scene's churn counters? Arm A = shipped default (identity) eq. Arm B =
-- value eq supplied to every memo that declared none. Arm B is the UPPER BOUND
-- on what the RR-5 fix could ever buy. Throwaway measurement instrument.
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local Facet = require("../../src")
local fake_target = require("../../tests/lib/fake_target")

-- ---- the value-eq used for arm B (and for the "would have been equal" count)
local function valueEq(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local seen = 0
	for k, v in a :: any do
		seen += 1
		local w = (b :: any)[k]
		if v ~= w then
			if type(v) == "table" and type(w) == "table" then
				if not valueEq(v, w) then
					return false
				end
			else
				return false
			end
		end
	end
	local other = 0
	for _ in b :: any do
		other += 1
	end
	return seen == other
end

local sites: { [string]: any } = {}
local realNewCore = Facet.newCore
local ARM = "A"
-- when ONLY is non-nil, arm B's value-eq is applied to the single site whose key
-- ends with this suffix — that is what turns "coalescing helps" into "THIS site
-- is the one that helps"
local ONLY: string? = nil
-- ...or a SET of suffixes, for the cumulative arms that answer "is the combined
-- win bigger than the sum of its parts"
local ONLY_SET: { string }? = nil

local function inOnlySet(key: string): boolean
	local set = ONLY_SET
	if set == nil then
		return false
	end
	for _, suffix in set do
		if string.sub(key, -#suffix) == suffix then
			return true
		end
	end
	return false
end

local function install()
	Facet.newCore = function(...)
		local core: any = realNewCore(...)
		local realMemo = core.memo
		core.memo = function(selfCore: any, compute: any, eq: any)
			if eq ~= nil then
				return realMemo(selfCore, compute, eq)
			end
			local src, line = debug.info(compute, "sl")
			local key = `{src}:{line}`
			local rec = sites[key]
			if rec == nil then
				rec = { key = key, computes = 0, wouldCoalesce = 0, identical = 0, freshTable = false }
				sites[key] = rec
			end
			local last: any = nil
			local first = true
			local wrapped = function(use: any)
				local v = compute(use)
				rec.computes += 1
				if type(v) == "table" then
					rec.freshTable = true
				end
				if not first then
					if last == v then
						rec.identical += 1
					elseif valueEq(last, v) then
						rec.wouldCoalesce += 1
					end
				end
				first = false
				last = v
				return v
			end
			local picked = if ONLY_SET ~= nil then inOnlySet(key) else (ONLY == nil or string.sub(key, -#ONLY) == ONLY)
			if ARM == "B" and picked then
				return realMemo(selfCore, wrapped, valueEq)
			end
			return realMemo(selfCore, wrapped)
		end
		return core
	end
end
install()

-- collect every renderer controller so the SOLVE-level churn is readable, not
-- just the adapter write log (the renderer diffs writes, so a wasted solve is
-- invisible in the op count).
local rendererLib = require("../../src/render/renderer")
local liveControllers: { any } = {}
local realAttach = rendererLib.attach
rendererLib.attach = function(...)
	local controller = realAttach(...)
	table.insert(liveControllers, controller)
	return controller
end

local perf_scenes = require("../../bench/perf_scenes")
local perf_profiles = require("../../bench/perf_profiles")

local PROFILE = perf_profiles.get("floorAndroid")
local ITERS = 40

local function opKinds(ops: { string }): { [string]: number }
	local out: { [string]: number } = {}
	for _, op in ops do
		local kind = string.match(op, "^(%a+)") or "?"
		out[kind] = (out[kind] or 0) + 1
	end
	return out
end

local results: { any } = {}

local function runScene(scene: any): any
	liveControllers = {}
	local state: any = scene.setup(PROFILE)
	local adapter: any = state.adapter
	if adapter ~= nil and adapter.takeOps ~= nil then
		adapter.takeOps() -- discard mount cost; the question is STEADY churn
	end
	for _ = 1, ITERS do
		if scene.run ~= nil then
			scene.run(state)
		end
	end
	local ops = if adapter ~= nil and adapter.takeOps ~= nil then adapter.takeOps() else {}
	-- extras are read BEFORE teardown
	local kinds = opKinds(ops)
	local solves, arranged, measured, rects, props = 0, 0, 0, 0, 0
	local partial, creates, removes, elided = 0, 0, 0, 0
	for _, c in liveControllers do
		local ok, st = pcall(function()
			return c.stats()
		end)
		if ok and st ~= nil then
			solves += st.solves or 0
			arranged += st.lastArranged or 0
			measured += st.lastMeasured or 0
			rects += st.rectWrites or 0
			props += st.propWrites or 0
			partial += st.partialSolves or 0
			creates += st.creates or 0
			removes += st.removes or 0
			elided += st.elided or 0
		end
	end
	local extras: any = nil
	if scene.extras ~= nil then
		local okX, x = pcall(scene.extras, state)
		extras = if okX then x else `EXTRAS ERROR {tostring(x)}`
	end
	if scene.teardown ~= nil then
		scene.teardown(state)
	end
	return {
		name = scene.name,
		totalOps = #ops,
		kinds = kinds,
		solves = solves,
		arranged = arranged,
		measured = measured,
		rectWrites = rects,
		propWrites = props,
		partialSolves = partial,
		creates = creates,
		removes = removes,
		elided = elided,
		extras = extras,
	}
end

-- ---- the perf LAB workloads, same instrument ------------------------------
-- The bench scenes do not touch every control; the lab's seventeen workloads
-- reach the ones they miss (tables, grids, row actions, motion, extents).
local dataset = require("../../examples/performance/lab/dataset")
local rowsLib = require("../../examples/performance/lab/rows")
local captureLib = require("../../examples/performance/lab/capture")
local overlayLib = require("../../examples/performance/lab/overlay")
local leversLib = require("../../examples/performance/lab/levers")
local hapticsLib = require("../../src/client/haptics")
local perf_lab = require("../../examples/performance/lab/perf_lab")

local function newLabHarness(): (any, any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)
	local clock = 0
	local host: any = {
		facts = function()
			return {
				evidenceClass = "lune",
				capturedAtIso = "2026-08-21T00:00:00Z",
				sourceStamp = "t15",
				placeName = "headless",
				viewport = "900x700",
				orientation = "landscape",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lune",
				thermalNote = "n/a",
				capturePath = "n/a",
				summaryPath = "n/a",
			}
		end,
	}
	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		host = host,
		lab = {
			dataset = dataset,
			rows = rowsLib,
			capture = captureLib,
			overlay = overlayLib,
			levers = leversLib,
			haptics = hapticsLib,
		},
		telemetry = {
			clock = function()
				clock += 0.001
				return clock
			end,
			step = function()
				return 0
			end,
			instances = function()
				return { measured = true, guiObjects = 0, screenGuis = 0 }
			end,
			connections = function()
				return { measured = false }
			end,
			memory = function()
				return { measured = true, luaHeapKb = 0 }
			end,
			frameWork = function(frames: number)
				return { measured = true, frames = frames, p50_ms = 0, p95_ms = 0, p99_ms = 0 }
			end,
		},
		geometry = function()
			return {}
		end,
		themePackages = {},
		themeChrome = {
			setPackage = function()
				return false
			end,
			census = function()
				return { unsupported = true }
			end,
		},
	}
	return perf_lab.build(ctx), ctx
end

local function runLab(): { any }
	local out: { any } = {}
	local probe = newLabHarness()
	local declared = probe.steps.workloads()
	probe.dispose()
	for _, w in declared.workloads do
		liveControllers = {}
		local built = newLabHarness()
		pcall(function()
			built.steps.select(nil, `scenario={w.id},rows=400,seed=3`)
			built.steps.mount()
		end)
		for _, passName in w.passes do
			pcall(function()
				built.steps.pass(nil, passName .. "=6")
			end)
		end
		local solves, partial, creates, arranged, measured = 0, 0, 0, 0, 0
		for _, c in liveControllers do
			local ok, st = pcall(function()
				return c.stats()
			end)
			if ok and st ~= nil then
				solves += st.solves or 0
				partial += st.partialSolves or 0
				creates += st.creates or 0
				arranged += st.lastArranged or 0
				measured += st.lastMeasured or 0
			end
		end
		table.insert(out, {
			id = w.id,
			solves = solves,
			partialSolves = partial,
			creates = creates,
			arranged = arranged,
			measured = measured,
		})
		built.dispose()
	end
	return out
end

local function sweep(arm: string, only: string?, onlySet: { string }?): any
	ARM = arm
	ONLY = only
	ONLY_SET = onlySet
	sites = {}
	local rows = {}
	for _, scene in perf_scenes do
		local ok, r = pcall(runScene, scene)
		if ok then
			table.insert(rows, r)
		else
			table.insert(rows, { name = scene.name, error = tostring(r) })
		end
	end
	local memoRows = {}
	for _, rec in sites do
		if rec.freshTable and rec.computes > 0 then
			table.insert(memoRows, rec)
		end
	end
	table.sort(memoRows, function(x, y)
		return x.wouldCoalesce > y.wouldCoalesce
	end)
	local lab = runLab()
	local memoRows2 = {}
	for _, rec in sites do
		if rec.freshTable and rec.computes > 0 then
			table.insert(memoRows2, rec)
		end
	end
	table.sort(memoRows2, function(x, y)
		return x.wouldCoalesce > y.wouldCoalesce
	end)
	return { arm = arm, scenes = rows, memos = memoRows2, lab = lab }
end

local A = sweep("A")
local B = sweep("B")

-- per-site attribution, on the one counter that moved
local ATTRIB = {
	"controls/virtual_list:3238",
	"controls/virtual_list:3241",
	"controls/virtual_list:3257",
	"controls/virtual_list:3525",
	"controls/virtual_window:266",
	"controls/virtual_window:284",
	"controls/table:1386",
	"controls/table:1968",
	"env/environment:214",
}
local attribution: { any } = {}
for _, only in ATTRIB do
	local arm = sweep("B", only)
	local row: { any } = { site = only, scenes = {} }
	for i, a in A.scenes do
		local b = arm.scenes[i]
		local ds = (b.solves or 0) - (a.solves or 0)
		if ds ~= 0 then
			table.insert(row.scenes, `bench/{a.name}: solves {a.solves} -> {b.solves} ({ds})`)
		end
	end
	for i, a in A.lab do
		local b = arm.lab[i]
		local ds = (b.solves or 0) - (a.solves or 0)
		local dp = (b.partialSolves or 0) - (a.partialSolves or 0)
		if ds ~= 0 or dp ~= 0 then
			table.insert(
				row.scenes,
				`lab/{a.id}: solves {a.solves} -> {b.solves} ({ds}), partial {a.partialSolves} -> {b.partialSolves} ({dp})`
			)
		end
	end
	table.insert(attribution, row)
end

print("scene | ops A/B | solves A/B | rectWrites A/B | propWrites A/B")
local anyDelta = 0
for i, a in A.scenes do
	local b = B.scenes[i]
	local da = (b.totalOps or -1) - (a.totalOps or -1)
	local ds = (b.solves or -1) - (a.solves or -1)
	local dr = (b.rectWrites or -1) - (a.rectWrites or -1)
	local dp = (b.propWrites or -1) - (a.propWrites or -1)
	anyDelta += math.abs(da) + math.abs(ds) + math.abs(dr) + math.abs(dp)
	print(
		`{a.name} | {a.totalOps}/{b.totalOps} ({da}) | {a.solves}/{b.solves} ({ds}) `
			.. `| {a.rectWrites}/{b.rectWrites} ({dr}) | {a.propWrites}/{b.propWrites} ({dp})`
	)
end
print(`TOTAL |delta| across scenes (ops+solves+rects+props): {anyDelta}`)
print("")
print("BEHAVIOURAL EQUALITY CHECK (creates/removes/arranged/measured/elided + scene extras):")
for i, a in A.scenes do
	local b = B.scenes[i]
	local same = a.creates == b.creates
		and a.removes == b.removes
		and a.arranged == b.arranged
		and a.measured == b.measured
		and a.elided == b.elided
		and valueEq(a.extras, b.extras)
	if not same then
		print(
			`  {a.name}: DIFFERS creates {a.creates}/{b.creates} removes {a.removes}/{b.removes} `
				.. `arranged {a.arranged}/{b.arranged} measured {a.measured}/{b.measured} elided {a.elided}/{b.elided}`
		)
		print(`      extrasA={serde.encode("json", a.extras)}`)
		print(`      extrasB={serde.encode("json", b.extras)}`)
	end
end
print("  (no line above = every arm produced identical structure and identical scene proof counters)")
print("")
print("LAB workloads | solves A/B | partialSolves A/B | creates A/B")
for i, a in A.lab do
	local b = B.lab[i]
	local mark = if a.solves ~= b.solves
			or a.partialSolves ~= b.partialSolves
			or a.creates ~= b.creates
		then "  <-- MOVED"
		else ""
	print(`  {a.id} | {a.solves}/{b.solves} | {a.partialSolves}/{b.partialSolves} | {a.creates}/{b.creates}{mark}`)
end

print("")
print("memo sites whose recompute produced a VALUE-EQUAL table (arm A):")
local coalescable = 0
for _, rec in A.memos do
	if rec.wouldCoalesce > 0 then
		coalescable += 1
		print(`  {rec.key}  computes={rec.computes} wouldCoalesce={rec.wouldCoalesce}`)
	end
end
print(`sites with >=1 coalescable recompute: {coalescable} (of {#A.memos} fresh-table default-eq memos that ran)`)

-- the cumulative arm: every virtual-list-family site at once, to see whether the
-- combined win exceeds the sum of the singles (it does — some waste is only
-- removable once its upstream has stopped firing)
local cumul = sweep("B", nil, {
	"controls/virtual_list:3238",
	"controls/virtual_list:3241",
	"controls/virtual_list:3257",
	"controls/virtual_list:3525",
	"controls/virtual_window:266",
	"controls/virtual_window:284",
})
print("")
print("CUMULATIVE arm (all virtual-list-family sites at once):")
for i, a in A.lab do
	local b = cumul.lab[i]
	if a.solves ~= b.solves or a.partialSolves ~= b.partialSolves then
		print(`  {a.id}: solves {a.solves} -> {b.solves}, partial {a.partialSolves} -> {b.partialSolves}`)
	end
end

print("")
print("per-site attribution (solve-count deltas):")
for _, row in attribution do
	if #row.scenes == 0 then
		print(`  {row.site}: NO scene moved`)
	else
		for _, line in row.scenes do
			print(`  {row.site}: {line}`)
		end
	end
end

fs.writeFile(
	"artifacts/release-candidate-review/perf/_rr5.json",
	serde.encode("json", { A = A, B = B, attribution = attribution }, true)
)
