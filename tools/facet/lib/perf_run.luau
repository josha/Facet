--!strict

local Files = require("./files")
local Json = require("./json")
local Run = require("./run")
local Loader = require("../../../tests/lib/loader")

local loader = Loader.new()
local perf_runner = loader.require("bench/perf_runner.luau") :: typeof(require("../../../bench/perf_runner"))
local perf_scenes = loader.require("bench/perf_scenes.luau") :: typeof(require("../../../bench/perf_scenes"))
local perf_profiles = loader.require("bench/perf_profiles.luau") :: typeof(require("../../../bench/perf_profiles"))

local PerfRun = {}

local ARTIFACT_PATH = "artifacts/phase-4/perf.json"
local BUDGETS_PATH = "bench/perf_budgets.json"
local DEVICE_CAPTURE_DIR = "artifacts/cross-platform-proof/device"
local ROW_PATH = "artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json"
local PROOF_PATH = "artifacts/performance-stress-places/prove-perf-gate.json"
local RUN_COMMAND = "lute run tools/facet perf run"

local BUDGET_MULTIPLIER = 4.0
local BUDGET_FLOOR_MS = 0.10
local UI_FRAME_SHARE = 0.25
local REPEATS = 5

local TARGET_SCENE = "lab-dense-scroll"
local FACTOR = 8

type Phases = { total: { p50_ms: number, p95_ms: number, p99_ms: number, samples: number? } }
type Row = { scene: string, device: string, requirement: string, evidenceClass: string, phases: Phases }
type SceneBudget = { total_p95_ms: number, ceilingMs: number?, [string]: unknown }
type Budgets =
	{ referenceProfile: string, multiplier: number, frameCeiling: unknown, scenes: { [string]: SceneBudget } }
type Violation = {
	kind: string,
	requirement: string,
	scene: string,
	device: string,
	observedMs: number,
	budgetMs: number,
	hint: string,
}
type Check = { ok: boolean, violations: { Violation }, skipped: { { class: string, reason: string } } }

PerfRun.ARTIFACT_PATH = ARTIFACT_PATH
PerfRun.BUDGETS_PATH = BUDGETS_PATH
PerfRun.RUN_COMMAND = RUN_COMMAND

function PerfRun.writeJson(path: string, value: unknown)
	Files.write(path, Json.encode(value, { indent = 2, sortKeys = true, ascii = false }) .. "\n")
end

local function record(fields: { [string]: unknown }): { [string]: unknown }
	return fields
end

local function readJson(path: string): unknown
	return Json.decode(Files.read(path))
end

local function profiles(): { unknown }
	local list: { unknown } = {}
	for _, name in perf_profiles.list() do
		table.insert(list, perf_profiles.get(name))
	end
	return list
end

local function injected(): ({ unknown }, string?, number)
	local injectScene = Run.env("FACET_PERF_INJECT_REGRESSION")
	local injectFactor = tonumber(Run.env("FACET_PERF_INJECT_FACTOR") or "") or 8
	if injectScene == nil then
		return perf_scenes, nil, injectFactor
	end
	local found = false
	local scenes: { unknown } = {}
	for _, scene in perf_scenes do
		if scene.name == injectScene then
			found = true
			local original = scene.run
			local clone = table.clone(scene)
			clone.run = function(state: unknown): unknown
				local phases = original(state)
				for _ = 2, injectFactor do
					original(state)
				end
				return phases
			end
			table.insert(scenes, clone)
		else
			table.insert(scenes, scene)
		end
	end
	assert(found, `perf: FACET_PERF_INJECT_REGRESSION names no scene '{injectScene}'`)
	print(`perf: INJECTED REGRESSION — scene '{injectScene}' doing {injectFactor}x the work (falsification run)`)
	return scenes, injectScene, injectFactor
end

local function sceneBudget(
	row: Row,
	referenceProfile: { frameTargetHz: number },
	worst: number,
	best: number
): { [string]: unknown }
	local ceilingMs = perf_runner.ceilingMsFor(referenceProfile.frameTargetHz, UI_FRAME_SHARE)
	return {
		total_p95_ms = math.max(worst * BUDGET_MULTIPLIER, BUDGET_FLOOR_MS),
		requirement = row.requirement,
		observed_p95_ms = worst,
		baselineRepeats = REPEATS,
		observed_p95_min_ms = best,
		observed_p95_max_ms = worst,
		frameTargetHz = referenceProfile.frameTargetHz,
		frameBudgetMs = 1000 / referenceProfile.frameTargetHz,
		ceilingMs = ceilingMs,
	}
end

local function writeBaseline(report: { runs: { Row }, [string]: unknown }, scenes: { unknown }): number
	local referenceProfile = perf_profiles.get(perf_profiles.REFERENCE)
	local ceilingMs = perf_runner.ceilingMsFor(referenceProfile.frameTargetHz, UI_FRAME_SHARE)
	local worst: { [string]: number } = {}
	local best: { [string]: number } = {}
	for _, r in report.runs do
		if r.device == perf_profiles.REFERENCE then
			worst[r.scene] = r.phases.total.p95_ms
			best[r.scene] = r.phases.total.p95_ms
		end
	end
	for pass = 2, REPEATS do
		local extra = perf_runner.run(scenes, { referenceProfile })
		for _, r in extra.runs :: { Row } do
			worst[r.scene] = math.max(worst[r.scene] or 0, r.phases.total.p95_ms)
			best[r.scene] = math.min(best[r.scene] or math.huge, r.phases.total.p95_ms)
		end
		print(`perf: baseline repeat {pass}/{REPEATS}`)
	end
	local scenesBudget: { [string]: unknown } = {}
	for _, r in report.runs do
		if r.device == perf_profiles.REFERENCE then
			local budget: { [string]: unknown } = sceneBudget(r, referenceProfile, worst[r.scene], best[r.scene])
			budget.hint = `scene '{r.scene}' ({r.requirement}) exceeded its headless trend budget — `
				.. `profile the reactive/layout path it exercises; re-baseline with `
				.. `'{RUN_COMMAND} baseline' ONLY if the cost is intended`
			scenesBudget[r.scene] = budget
		end
	end
	local function device(hz: number, note: string): { [string]: unknown }
		return {
			frameTargetHz = hz,
			uiShare = UI_FRAME_SHARE,
			budgetMs = perf_runner.ceilingMsFor(hz, UI_FRAME_SHARE),
			measured = false,
			requirement = "UI-PERF-002",
			note = note,
		}
	end
	PerfRun.writeJson(BUDGETS_PATH, {
		schema = "facet-perf-budgets/2",
		evidenceClass = perf_runner.CLASS,
		evidenceLevel = perf_runner.LEVEL,
		referenceProfile = perf_profiles.REFERENCE,
		multiplier = BUDGET_MULTIPLIER,
		floorMs = BUDGET_FLOOR_MS,
		frameCeiling = {
			uiShare = UI_FRAME_SHARE,
			frameTargetHz = referenceProfile.frameTargetHz,
			ceilingMs = ceilingMs,
			directionality = "one-way",
			note = "Exceeding this proves the scene cannot hold the frame target on ANY supported device, "
				.. "because this host is faster than all of them. Passing it proves NOTHING about a device.",
		},
		note = "Headless trend budgets, floor-device (low-end Android) reference. observed_p95_ms is the WORST p95 over "
			.. "baselineRepeats runs, so the multiplier applies to a number that already contains the run-to-run jitter. "
			.. "total_p95_ms = max(worst_p95 × multiplier, floorMs). Trend-only; NOT a device SLA (§14.3).",
		scenes = scenesBudget,
		deviceBudgets = {
			["phone-physical"] = device(
				30,
				"the weakest supported physical Android device; PENDING_PHYSICAL (ledger XP-P1)"
			),
			["console-physical"] = device(60, "the supported console / ten-foot path; PENDING_PHYSICAL (ledger XP-P2)"),
			["desktop-retail"] = device(60, "the retail (non-Studio) desktop client; PENDING_PHYSICAL (ledger XP-P3)"),
		},
	})
	print(`perf: wrote {BUDGETS_PATH} from this baseline run ({#report.runs} runs)`)
	report.status = "BASELINE"
	report.budget = { checked = false }
	PerfRun.writeJson(ARTIFACT_PATH, report)
	print(`perf: wrote {ARTIFACT_PATH}`)
	return 0
end

local function ingest(report: { runs: { unknown }, [string]: unknown })
	local ingestedRows: { string } = {}
	local rejected: { { [string]: unknown } } = {}
	if Files.isDirectory(DEVICE_CAPTURE_DIR) then
		for _, entry in Files.list(DEVICE_CAPTURE_DIR) do
			if string.match(entry.name, "%.json$") == nil then
				continue
			end
			local ok, decoded = pcall(readJson, `{DEVICE_CAPTURE_DIR}/{entry.name}`)
			if not ok or type(decoded) ~= "table" then
				continue
			end
			local capture = decoded :: { evidenceClass: string, rows: { { [string]: unknown } }? }
			if perf_runner.DEVICE_CLASSES[capture.evidenceClass] ~= true then
				continue
			end
			local rows: { { [string]: unknown } } = capture.rows or {}
			for _, row in rows do
				local scene = row.scene or row.row
				if row.evidenceClass ~= capture.evidenceClass then
					table.insert(
						rejected,
						record({
							scene = scene,
							fileClass = capture.evidenceClass,
							rowClass = row.evidenceClass,
							reason = "the row's own evidence class disagrees with the file's; a relabelled file cannot "
								.. "relabel the rows inside it",
						})
					)
					continue
				end
				local problems = perf_runner.provenanceProblems(row)
				if #problems > 0 then
					table.insert(
						rejected,
						record({
							scene = scene,
							fileClass = capture.evidenceClass,
							rowClass = row.evidenceClass,
							reason = `the row claims '{tostring(row.evidenceClass)}' but does not carry what that class implies: `
								.. table.concat(problems, "; "),
							provenanceProblems = problems,
						})
					)
					continue
				end
				local merged = table.clone(row)
				merged.scene = scene
				local metrics = row.metrics :: { [string]: unknown }?
				if metrics ~= nil and metrics.frameWorkMs == nil then
					local copied = table.clone(metrics)
					copied.frameWorkMs = metrics.M1_frameWorkMs
					merged.metrics = copied
				end
				table.insert(report.runs, merged)
				table.insert(ingestedRows, `{capture.evidenceClass}:{tostring(scene)}`)
			end
		end
	end
	if #ingestedRows > 0 then
		print(`perf: ingested {#ingestedRows} device row(s) from {DEVICE_CAPTURE_DIR}`)
		report.ingestedDeviceRows = ingestedRows
	end
	if #rejected > 0 then
		print(`perf: REJECTED {#rejected} device row(s)`)
		for _, r in rejected do
			print(`  rejected {tostring(r.scene)}: {tostring(r.reason)}`)
		end
		report.rejectedDeviceRows = rejected
	end
end

function PerfRun.run(baseline: boolean): number
	local list = profiles()
	local scenes, injectScene, injectFactor = injected()
	print(`perf: {#scenes} scenes × {#list} profiles (reference = {perf_profiles.REFERENCE})`)
	local report = perf_runner.run(scenes, list)
	report.referenceProfile = perf_profiles.REFERENCE
	if injectScene ~= nil then
		report.injectedRegression = {
			scene = injectScene,
			factor = injectFactor,
			note = "DELIBERATE falsification run (ledger XP-A6). This artifact is not a valid baseline.",
		}
	end
	if baseline then
		assert(
			injectScene == nil,
			"perf: refusing to write a baseline from an injected-regression run — that would bake the fault in"
		)
		return writeBaseline(report, scenes)
	end
	if not Files.isFile(BUDGETS_PATH) then
		print(`perf: missing {BUDGETS_PATH} (hint: run '{RUN_COMMAND} baseline' first)`)
		return 1
	end
	local budgets = readJson(BUDGETS_PATH) :: Budgets
	ingest(report)
	local present: { [string]: number } = {}
	for _, r in report.runs :: { Row } do
		present[r.evidenceClass] = (present[r.evidenceClass] or 0) + 1
	end
	for _, entry in report.evidenceClasses :: { { id: string, rows: number } } do
		entry.rows = present[entry.id] or 0
	end
	local result = perf_runner.checkBudgets(report, budgets) :: Check
	report.status = if result.ok then "PASS" else "FAIL"
	report.budget = {
		checked = true,
		referenceProfile = budgets.referenceProfile,
		multiplier = budgets.multiplier,
		frameCeiling = budgets.frameCeiling,
		violations = result.violations,
		skippedDeviceBudgets = result.skipped,
	}
	PerfRun.writeJson(ARTIFACT_PATH, report)
	local referenceProfile = perf_profiles.get(perf_profiles.REFERENCE)
	print("")
	print(
		string.format(
			"  %-28s %8s %10s %10s   %s",
			"scene",
			"p95(ms)",
			"trend(ms)",
			"ceil(ms)",
			`result   (reference: {perf_profiles.REFERENCE} @ {referenceProfile.frameTargetHz}Hz)`
		)
	)
	for _, r in report.runs :: { Row } do
		if r.device == perf_profiles.REFERENCE then
			local b = budgets.scenes[r.scene]
			local budgetMs = if b then b.total_p95_ms else math.huge
			local ceil = if b and b.ceilingMs then b.ceilingMs else math.huge
			local p95 = r.phases.total.p95_ms
			local verdict = if p95 > budgetMs then "OVER-TREND" elseif p95 > ceil then "OVER-CEILING" else "ok"
			print(string.format("  %-28s %8.4f %10.3f %10.3f   %s", r.scene, p95, budgetMs, ceil, verdict))
		end
	end
	print("")
	for _, s in result.skipped do
		print(`  (device budget '{s.class}' not checked: {s.reason})`)
	end
	print("")
	if not result.ok then
		print(
			`perf: FAIL_ENVIRONMENT — {#result.violations} host timing budget violation(s) [artifact: {ARTIFACT_PATH}]`
		)
		for _, v in result.violations do
			print(
				string.format(
					"  FAIL [%s/%s] scene=%s device=%s: p95 %.4fms > budget %.3fms\n       hint: %s",
					v.kind,
					v.requirement,
					v.scene,
					v.device,
					v.observedMs,
					v.budgetMs,
					v.hint
				)
			)
		end
		return 2
	end
	print(`perf: PASS ({#report.runs} runs, {#scenes} scenes) [artifact: {ARTIFACT_PATH}]`)
	print("perf: headless trend numbers only — device measurement is authoritative (§14.3)")
	return 0
end

function PerfRun.baselineScenes(names: { string }): number
	if #names == 0 then
		print("usage: lute run tools/facet perf baseline <scene> [<scene> ...]")
		return 2
	end
	local wanted: { [string]: boolean } = {}
	for _, name in names do
		wanted[name] = true
	end
	local selected: { unknown } = {}
	for _, scene in perf_scenes do
		if wanted[scene.name] then
			table.insert(selected, scene)
		end
	end
	if #selected ~= #names then
		print(`perf baseline: {#selected} of {#names} named scene(s) exist in bench/perf_scenes.luau`)
		return 1
	end
	if not Files.isFile(BUDGETS_PATH) then
		print(`perf baseline: missing {BUDGETS_PATH}`)
		return 1
	end
	local budgets = readJson(BUDGETS_PATH) :: Budgets
	local referenceProfile = perf_profiles.get(perf_profiles.REFERENCE)
	if budgets.referenceProfile ~= perf_profiles.REFERENCE then
		print(
			`perf baseline: the budgets file was recorded against '{budgets.referenceProfile}' but the current `
				.. `reference is '{perf_profiles.REFERENCE}'; a scoped baseline must not mix reference profiles`
		)
		return 1
	end
	local worst: { [string]: number } = {}
	local best: { [string]: number } = {}
	local rows: { [string]: Row } = {}
	for pass = 1, REPEATS do
		local report = perf_runner.run(selected, { referenceProfile })
		for _, r in report.runs :: { Row } do
			local p95 = r.phases.total.p95_ms
			worst[r.scene] = math.max(worst[r.scene] or 0, p95)
			best[r.scene] = math.min(best[r.scene] or math.huge, p95)
			rows[r.scene] = r
		end
		print(`perf baseline: repeat {pass}/{REPEATS}`)
	end
	for _, name in names do
		local budget: { [string]: unknown } = sceneBudget(rows[name], referenceProfile, worst[name], best[name])
		budget.scopedBaseline = true
		budget.hint = `scene '{name}' ({rows[name].requirement}) exceeded its headless trend budget — profile the reactive/layout `
			.. `path it exercises; re-baseline with 'lute run tools/facet perf baseline {name}' ONLY if the cost `
			.. `is intended`
		budgets.scenes[name] = (budget :: unknown) :: SceneBudget
		print(
			string.format(
				"perf baseline: %s worst p95 %.4fms (min %.4f) -> budget %.3fms, ceiling %.3fms",
				name,
				worst[name],
				best[name],
				budgets.scenes[name].total_p95_ms,
				budgets.scenes[name].ceilingMs or math.huge
			)
		)
	end
	PerfRun.writeJson(BUDGETS_PATH, budgets)
	print(`perf baseline: wrote {#names} scene budget(s) into {BUDGETS_PATH}; every other entry is untouched`)
	return 0
end

local function gate(extra: { [string]: string }?): (number, string)
	local environment = Run.environment()
	local additions: { [string]: string } = extra or {}
	for key, value in additions do
		environment[key] = value
	end
	local result = Run.capture(
		{ Run.lute(), "run", "tools/facet", "perf", "run" },
		{ env = environment, timeout = 3600 }
	)
	return (if result.ok then 0 else 1), result.stdout .. result.stderr
end

local function syntheticReport(scene: string, p95: number): { [string]: unknown }
	return {
		schema = "facet-perf/2",
		environment = { evidenceClass = perf_runner.CLASS },
		runs = {
			{
				scene = scene,
				device = "floorAndroid",
				evidenceClass = perf_runner.CLASS,
				requirement = "UI-PERF-001",
				phases = { total = { p50_ms = p95 / 2, p95_ms = p95, p99_ms = p95 * 7 / 6 } },
			},
		},
	}
end

function PerfRun.proveGate(): number
	print(`perf prove-gate: injecting a {FACTOR}x regression into '{TARGET_SCENE}' and running the real gate…`)
	local injectedCode, injectedOut = gate({
		FACET_PERF_INJECT_REGRESSION = TARGET_SCENE,
		FACET_PERF_INJECT_FACTOR = tostring(FACTOR),
	})
	local trendFailed = injectedCode ~= 0
	local namedScene = string.find(injectedOut, TARGET_SCENE, 1, true) ~= nil
	local namedTrend = string.find(injectedOut, "trend/", 1, true) ~= nil
	local namedHint = string.find(injectedOut, "hint:", 1, true) ~= nil
	local violationLine: string? = nil
	for line in string.gmatch(injectedOut, "[^\n]+") do
		if string.find(line, "FAIL [", 1, true) ~= nil and string.find(line, TARGET_SCENE, 1, true) ~= nil then
			violationLine = (string.gsub(line, "^%s+", ""))
		end
	end
	print(`perf prove-gate: injected run exit={injectedCode} (expected nonzero)`)
	local injectedViolations: { { scene: string, kind: string } } = {}
	local stampedAsInjected = false
	if Files.isFile(ARTIFACT_PATH) then
		local artifact = readJson(ARTIFACT_PATH) :: {
			injectedRegression: { scene: string }?,
			budget: { violations: { { scene: string, kind: string } }? }?,
		}
		stampedAsInjected = artifact.injectedRegression ~= nil and artifact.injectedRegression.scene == TARGET_SCENE
		injectedViolations = if artifact.budget then artifact.budget.violations or {} else {}
	end
	local sceneKinds: { [string]: boolean } = {}
	for _, v in injectedViolations do
		if v.scene == TARGET_SCENE then
			sceneKinds[v.kind] = true
		end
	end
	local ceilingResult = perf_runner.checkBudgets(syntheticReport("synthetic-heavy", 12.0), {
		referenceProfile = "floorAndroid",
		scenes = {
			["synthetic-heavy"] = {
				total_p95_ms = 1000,
				requirement = "UI-PERF-001",
				frameTargetHz = 30,
				ceilingMs = perf_runner.ceilingMsFor(30, 0.25),
				hint = "x",
			},
		},
	}) :: Check
	local ceilingFired = false
	for _, v in ceilingResult.violations do
		if v.kind == "frame-ceiling" then
			ceilingFired = true
		end
	end
	local refusalResult = perf_runner.checkBudgets(syntheticReport("synthetic", 0.1), {
		referenceProfile = "floorAndroid",
		scenes = {},
		deviceBudgets = {
			["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
		},
	}) :: Check
	local refusalFired = false
	for _, v in refusalResult.violations do
		if v.kind == "class-mismatch" then
			refusalFired = true
		end
	end
	print("perf prove-gate: rerunning the gate clean to restore the artifact…")
	local cleanCode, cleanOut = gate()
	local cleanPassed = cleanCode == 0
	local restoredArtifactClean = false
	if Files.isFile(ARTIFACT_PATH) then
		local committed = readJson(ARTIFACT_PATH) :: { injectedRegression: unknown?, status: string? }
		restoredArtifactClean = committed.injectedRegression == nil and committed.status == "PASS"
	end
	PerfRun.writeJson(PROOF_PATH, {
		schema = "facet-perf-gate-proof/1",
		scene = TARGET_SCENE,
		factor = FACTOR,
		injectedExitCode = injectedCode,
		namedTheScene = namedScene,
		artifactStampedAsInjected = stampedAsInjected,
		violations = injectedViolations,
		cleanRunPassed = cleanPassed,
		committedArtifactIsClean = restoredArtifactClean,
	})
	local ok = trendFailed
		and sceneKinds.trend == true
		and sceneKinds["frame-ceiling"] == true
		and stampedAsInjected
		and namedScene
		and namedTrend
		and namedHint
		and ceilingFired
		and refusalFired
	local restored = cleanPassed and restoredArtifactClean
	PerfRun.writeJson(ROW_PATH, {
		schema = "facet-perf-falsification/1",
		row = "XP-A6",
		requirement = "UI-PERF-002",
		evidenceClass = perf_runner.CLASS,
		evidenceLevel = "E1",
		gateFailedAsExpected = ok and restored,
		trend = {
			method = `wrapped scene '{TARGET_SCENE}' run() to do {FACTOR}x its own work; ran the shipped {RUN_COMMAND} unchanged`,
			exitCode = injectedCode,
			failed = trendFailed,
			namedTheScene = namedScene,
			classifiedAsTrend = namedTrend,
			gaveAnActionableHint = namedHint,
			violationLine = violationLine,
		},
		frameCeiling = {
			method = "a 12.0ms p95 against a 30Hz frame with a 0.25 UI share (8.33ms ceiling) and a deliberately generous trend budget",
			firedIndependentlyOfTrend = ceilingFired,
			violations = ceilingResult.violations,
		},
		classRefusal = {
			method = `a measured phone-physical budget checked against a report containing only {perf_runner.CLASS} rows`,
			refused = refusalFired,
			violations = refusalResult.violations,
		},
		restore = {
			cleanRunPassed = cleanPassed,
			committedArtifactIsClean = restoredArtifactClean,
			note = "the falsification run must not leave a poisoned artifact; the clean rerun is part of the proof",
		},
		note = `Reproduce: FACET_PERF_INJECT_REGRESSION={TARGET_SCENE} FACET_PERF_INJECT_FACTOR={FACTOR} {RUN_COMMAND} `
			.. `(expect exit 2), then {RUN_COMMAND} (expect exit 0).`,
	})
	if not ok then
		print("perf prove-gate: FAIL — the gate did not behave as a gate")
		print(`  trendFailed={trendFailed} namedScene={namedScene} namedTrend={namedTrend} namedHint={namedHint}`)
		print(`  ceilingFired={ceilingFired} refusalFired={refusalFired} stampedAsInjected={stampedAsInjected}`)
		print(`  sceneTrend={sceneKinds.trend == true} sceneCeiling={sceneKinds["frame-ceiling"] == true}`)
		print(`  cleanPassed={cleanPassed} restoredArtifactClean={restoredArtifactClean}`)
		print(cleanOut)
		return 1
	end
	if not restored then
		print(
			"perf prove-gate: FAIL_ENVIRONMENT — the injected regression fired, but the clean rerun failed its host timing budgets"
		)
		print(`  cleanPassed={cleanPassed} restoredArtifactClean={restoredArtifactClean}`)
		print(cleanOut)
		return 2
	end
	print(`perf prove-gate: PASS — trend, ceiling and class-refusal all fire; clean rerun restored [{ROW_PATH}]`)
	return 0
end

return table.freeze(PerfRun)
