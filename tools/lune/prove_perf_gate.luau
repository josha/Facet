--!strict
-- Falsify the performance gate (roadmap Step 4, ledger row XP-A6).
--
-- An unfalsified gate is decoration: until someone has watched it fail for a
-- real regression, "perf: PASS" is a habit rather than evidence. This tool
-- makes it fail on purpose, three ways, and records what it saw:
--
--   1. TREND     — a real regression in a real scene (the scene does 8× its own
--                  work) must break its measured-baseline budget, END TO END
--                  through the shipped `tools/perf.sh`, with a nonzero exit and
--                  a message naming the scene.
--   2. CEILING   — a scene above the frame-target share must be flagged as a
--                  frame-ceiling violation, distinctly from a trend regression.
--   3. REFUSAL   — a device budget must not be satisfiable by headless rows.
--
-- Then it reruns the gate CLEAN and requires a pass, so the falsification run
-- cannot leave a poisoned artifact behind. Writes
-- artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json.
--
--   lune run tools/lune/prove_perf_gate

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local artifact = require("./artifact")
local perf_runner = require("../../bench/perf_runner")

local ROW_PATH = "artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json"
local PERF_ARTIFACT = "artifacts/phase-4/perf.json"
-- a mid-weight scene: cheap enough that 8× is fast, expensive enough that its
-- trend budget is well above the noise floor (so the failure is the regression,
-- not jitter)
local TARGET_SCENE = "dense-hud"
local FACTOR = 8

local function run(env: { [string]: string }?): (number, string)
	local result = process.exec("lune", { "run", "tools/lune/perf" }, { env = env })
	return (if result.ok then 0 else 1), (result.stdout or "") .. (result.stderr or "")
end

print(`prove_perf_gate: injecting a {FACTOR}x regression into '{TARGET_SCENE}' and running the real gate…`)
local injectedCode, injectedOut = run({
	FACET_PERF_INJECT_REGRESSION = TARGET_SCENE,
	FACET_PERF_INJECT_FACTOR = tostring(FACTOR),
})

local trendFailed = injectedCode ~= 0
local namedScene = string.find(injectedOut, TARGET_SCENE, 1, true) ~= nil
local namedTrend = string.find(injectedOut, "trend/", 1, true) ~= nil
local namedHint = string.find(injectedOut, "hint:", 1, true) ~= nil
-- capture the exact violation line for the record
local violationLine: string? = nil
for line in string.gmatch(injectedOut, "[^\n]+") do
	if string.find(line, "FAIL [", 1, true) ~= nil and string.find(line, TARGET_SCENE, 1, true) ~= nil then
		violationLine = (string.gsub(line, "^%s+", ""))
	end
end

print(`prove_perf_gate: injected run exit={injectedCode} (expected nonzero)`)

-- 2. the frame ceiling, in-process: a scene above the share of the frame target
local ceilingReport = {
	schema = "facet-perf/2",
	environment = { evidenceClass = "lune" },
	runs = {
		{
			scene = "synthetic-heavy",
			device = "floorAndroid",
			evidenceClass = "lune",
			requirement = "UI-PERF-001",
			phases = { total = { p50_ms = 6, p95_ms = 12.0, p99_ms = 14 } },
		},
	},
}
local ceilingResult = perf_runner.checkBudgets(ceilingReport, {
	referenceProfile = "floorAndroid",
	scenes = {
		["synthetic-heavy"] = {
			total_p95_ms = 1000, -- deliberately generous: only the ceiling may fire
			requirement = "UI-PERF-001",
			frameTargetHz = 30,
			ceilingMs = perf_runner.ceilingMsFor(30, 0.25),
			hint = "x",
		},
	},
})
local ceilingFired = false
for _, v in ceilingResult.violations do
	if v.kind == "frame-ceiling" then
		ceilingFired = true
	end
end

-- 3. the refusal: a measured device budget against a report of headless rows
local refusalResult = perf_runner.checkBudgets({
	schema = "facet-perf/2",
	environment = { evidenceClass = "lune" },
	runs = {
		{
			scene = "synthetic",
			device = "floorAndroid",
			evidenceClass = "lune",
			requirement = "UI-PERF-001",
			phases = { total = { p50_ms = 0.1, p95_ms = 0.1, p99_ms = 0.1 } },
		},
	},
}, {
	referenceProfile = "floorAndroid",
	scenes = {},
	deviceBudgets = {
		["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
	},
})
local refusalFired = false
for _, v in refusalResult.violations do
	if v.kind == "class-mismatch" then
		refusalFired = true
	end
end

-- restore: rerun the gate clean so the committed artifact is a real one
print("prove_perf_gate: rerunning the gate clean to restore the artifact…")
local cleanCode, cleanOut = run()
local cleanPassed = cleanCode == 0
local restoredArtifactClean = false
if fs.isFile(PERF_ARTIFACT) then
	local committed = serde.decode("json", fs.readFile(PERF_ARTIFACT))
	restoredArtifactClean = committed.injectedRegression == nil and committed.status == "PASS"
end

local ok = trendFailed
	and namedScene
	and namedTrend
	and namedHint
	and ceilingFired
	and refusalFired
	and cleanPassed
	and restoredArtifactClean

artifact.writeJson(ROW_PATH, {
	schema = "facet-perf-falsification/1",
	row = "XP-A6",
	requirement = "UI-PERF-002",
	evidenceClass = "lune",
	evidenceLevel = "E1",
	gateFailedAsExpected = ok,
	trend = {
		method = `wrapped scene '{TARGET_SCENE}' run() to do {FACTOR}x its own work; ran the shipped tools/perf.sh unchanged`,
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
		method = "a measured phone-physical budget checked against a report containing only lune rows",
		refused = refusalFired,
		violations = refusalResult.violations,
	},
	restore = {
		cleanRunPassed = cleanPassed,
		committedArtifactIsClean = restoredArtifactClean,
		note = "the falsification run must not leave a poisoned artifact; the clean rerun is part of the proof",
	},
	note = "Reproduce: FACET_PERF_INJECT_REGRESSION=" .. TARGET_SCENE .. " FACET_PERF_INJECT_FACTOR=" .. tostring(
		FACTOR
	) .. " tools/perf.sh   (expect exit 1), then tools/perf.sh (expect exit 0).",
})

if not ok then
	print("prove_perf_gate: FAIL — the gate did not behave as a gate")
	print(`  trendFailed={trendFailed} namedScene={namedScene} namedTrend={namedTrend} namedHint={namedHint}`)
	print(`  ceilingFired={ceilingFired} refusalFired={refusalFired}`)
	print(`  cleanPassed={cleanPassed} restoredArtifactClean={restoredArtifactClean}`)
	print(cleanOut)
	process.exit(1)
end

print(`prove_perf_gate: PASS — trend, ceiling and class-refusal all fire; clean rerun restored [{ROW_PATH}]`)
process.exit(0)
