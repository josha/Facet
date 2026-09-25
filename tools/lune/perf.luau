--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local artifact = require("./artifact")
local perf_runner = require("../../bench/perf_runner")
local perf_scenes = require("../../bench/perf_scenes")
local perf_profiles = require("../../bench/perf_profiles")

local fidelity = serde.decode("json", fs.readFile("bench/workload_fidelity.json"))
assert(fidelity.status == "verified", "controlled workload fidelity audit is incomplete")
local mode = process.args[1]
local ARTIFACT_PATH = "artifacts/phase-4/perf.json"
local BUDGETS_PATH = "bench/perf_budgets.json"

local DEVICE_CAPTURE_DIR = "artifacts/cross-platform-proof/device"

local BUDGET_MULTIPLIER = 4.0

local BUDGET_FLOOR_MS = 0.10

local UI_FRAME_SHARE = 0.25

local profiles = {}
for _, name in perf_profiles.list() do
	table.insert(profiles, perf_profiles.get(name))
end

local injectScene = process.env.FACET_PERF_INJECT_REGRESSION
local injectFactor = tonumber(process.env.FACET_PERF_INJECT_FACTOR or "") or 8
local scenes = perf_scenes
if injectScene ~= nil and injectScene ~= "" then
	local found = false
	scenes = {}
	for _, scene in perf_scenes do
		if scene.name == injectScene then
			found = true
			local original = scene.run
			local clone = table.clone(scene)
			clone.run = function(state: any)
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
end

print(`perf: {#scenes} scenes × {#profiles} profiles (reference = {perf_profiles.REFERENCE})`)
local report = perf_runner.run(scenes, profiles)
report.referenceProfile = perf_profiles.REFERENCE
report.workloadFidelity = fidelity
if injectScene ~= nil and injectScene ~= "" then
	report.injectedRegression = {
		scene = injectScene,
		factor = injectFactor,
		note = "DELIBERATE falsification run (ledger XP-A6). This artifact is not a valid baseline.",
	}
end

local referenceProfile = perf_profiles.get(perf_profiles.REFERENCE)
local ceilingMs = perf_runner.ceilingMsFor(referenceProfile.frameTargetHz, UI_FRAME_SHARE)

if mode == "baseline" then
	assert(
		injectScene == nil or injectScene == "",
		"perf: refusing to write a baseline from an injected-regression run — that would bake the fault in"
	)

	local REPEATS = 5
	local worst: { [string]: number } = {}
	local best: { [string]: number } = {}
	for _, r in report.runs do
		if r.device == perf_profiles.REFERENCE then
			worst[r.scene] = r.phases.total.p95_ms
			best[r.scene] = r.phases.total.p95_ms
		end
	end
	local referenceOnly = { referenceProfile }
	for pass = 2, REPEATS do
		local extra = perf_runner.run(scenes, referenceOnly)
		for _, r in extra.runs do
			worst[r.scene] = math.max(worst[r.scene] or 0, r.phases.total.p95_ms)
			best[r.scene] = math.min(best[r.scene] or math.huge, r.phases.total.p95_ms)
		end
		print(`perf: baseline repeat {pass}/{REPEATS}`)
	end

	local scenesBudget: { [string]: any } = {}
	for _, r in report.runs do
		if r.device == perf_profiles.REFERENCE then
			local p95 = worst[r.scene]
			scenesBudget[r.scene] = {
				total_p95_ms = math.max(p95 * BUDGET_MULTIPLIER, BUDGET_FLOOR_MS),
				requirement = r.requirement,
				observed_p95_ms = p95,

				baselineRepeats = REPEATS,
				observed_p95_min_ms = best[r.scene],
				observed_p95_max_ms = worst[r.scene],

				frameTargetHz = referenceProfile.frameTargetHz,
				frameBudgetMs = 1000 / referenceProfile.frameTargetHz,
				ceilingMs = ceilingMs,
				hint = `scene '{r.scene}' ({r.requirement}) exceeded its headless trend budget — `
					.. `profile the reactive/layout path it exercises; re-baseline with `
					.. `'tools/perf.sh baseline' ONLY if the cost is intended`,
			}
		end
	end
	local budgets = {
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
			["phone-physical"] = {
				frameTargetHz = 30,
				uiShare = UI_FRAME_SHARE,
				budgetMs = perf_runner.ceilingMsFor(30, UI_FRAME_SHARE),
				measured = false,
				requirement = "UI-PERF-002",
				note = "the weakest supported physical Android device; PENDING_PHYSICAL (ledger XP-P1)",
			},
			["console-physical"] = {
				frameTargetHz = 60,
				uiShare = UI_FRAME_SHARE,
				budgetMs = perf_runner.ceilingMsFor(60, UI_FRAME_SHARE),
				measured = false,
				requirement = "UI-PERF-002",
				note = "the supported console / ten-foot path; PENDING_PHYSICAL (ledger XP-P2)",
			},
			["desktop-retail"] = {
				frameTargetHz = 60,
				uiShare = UI_FRAME_SHARE,
				budgetMs = perf_runner.ceilingMsFor(60, UI_FRAME_SHARE),
				measured = false,
				requirement = "UI-PERF-002",
				note = "the retail (non-Studio) desktop client; PENDING_PHYSICAL (ledger XP-P3)",
			},
		},
	}
	artifact.writeJson(BUDGETS_PATH, budgets)
	print(`perf: wrote {BUDGETS_PATH} from this baseline run ({#report.runs} runs)`)

	report.status = "BASELINE"
	report.budget = { checked = false }
	artifact.writeJson(ARTIFACT_PATH, report)
	print(`perf: wrote {ARTIFACT_PATH}`)
	process.exit(0)
end

assert(fs.isFile(BUDGETS_PATH), `perf: missing {BUDGETS_PATH} (hint: run 'tools/perf.sh baseline' first)`)
local budgets = serde.decode("json", fs.readFile(BUDGETS_PATH))

local ingested = {}
local rejected: { any } = {}
if fs.isDir(DEVICE_CAPTURE_DIR) then
	for _, name in fs.readDir(DEVICE_CAPTURE_DIR) do
		if string.match(name, "%.json$") == nil then
			continue
		end
		local ok, capture = pcall(function()
			return serde.decode("json", fs.readFile(`{DEVICE_CAPTURE_DIR}/{name}`))
		end)
		if not ok or type(capture) ~= "table" then
			continue
		end
		if perf_runner.DEVICE_CLASSES[capture.evidenceClass] ~= true then
			continue
		end
		for _, row in capture.rows or {} do
			if row.evidenceClass ~= capture.evidenceClass then
				table.insert(rejected, {
					scene = row.scene or row.row,
					fileClass = capture.evidenceClass,
					rowClass = row.evidenceClass,
					reason = "the row's own evidence class disagrees with the file's; a relabelled file cannot "
						.. "relabel the rows inside it",
				})
				continue
			end

			local problems = perf_runner.provenanceProblems(row)
			if #problems > 0 then
				table.insert(rejected, {
					scene = row.scene or row.row,
					fileClass = capture.evidenceClass,
					rowClass = row.evidenceClass,
					reason = `the row claims '{tostring(row.evidenceClass)}' but does not carry what that class implies: `
						.. table.concat(problems, "; "),
					provenanceProblems = problems,
				})
				continue
			end
			local merged = table.clone(row)
			merged.scene = row.scene or row.row
			merged.metrics = row.metrics

			if merged.metrics ~= nil and merged.metrics.frameWorkMs == nil then
				merged.metrics = table.clone(merged.metrics)
				merged.metrics.frameWorkMs = merged.metrics.M1_frameWorkMs
			end
			table.insert(report.runs, merged)
			table.insert(ingested, `{capture.evidenceClass}:{merged.scene}`)
		end
	end
end
if #ingested > 0 then
	print(`perf: ingested {#ingested} device row(s) from {DEVICE_CAPTURE_DIR}`)
	report.ingestedDeviceRows = ingested
end
if #rejected > 0 then
	print(`perf: REJECTED {#rejected} device row(s)`)
	for _, r in rejected do
		print(`  rejected {r.scene}: {r.reason}`)
	end
	report.rejectedDeviceRows = rejected
end

local present: { [string]: number } = {}
for _, r in report.runs do
	present[r.evidenceClass] = (present[r.evidenceClass] or 0) + 1
end
for _, entry in report.evidenceClasses do
	entry.rows = present[entry.id] or 0
end

local result = perf_runner.checkBudgets(report, budgets)

report.status = if result.ok then "PASS" else "FAIL"
report.budget = {
	checked = true,
	referenceProfile = budgets.referenceProfile,
	multiplier = budgets.multiplier,
	frameCeiling = budgets.frameCeiling,
	violations = result.violations,

	skippedDeviceBudgets = result.skipped,
}
artifact.writeJson(ARTIFACT_PATH, report)

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
for _, r in report.runs do
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
	print(`perf: FAIL_ENVIRONMENT — {#result.violations} host timing budget violation(s) [artifact: {ARTIFACT_PATH}]`)
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
	process.exit(2)
end

print(`perf: PASS ({#report.runs} runs, {#scenes} scenes) [artifact: {ARTIFACT_PATH}]`)
print("perf: headless trend numbers only — device measurement is authoritative (§14.3)")
process.exit(0)
