--!strict
-- LuauUI seeded property-fuzz command (design §15.2, §16.1, §17 Phase 4).
-- Runs the scheduler/layout/replication fuzzers at scaled case counts and
-- writes one artifact per target under artifacts/phase-4/. Deterministic:
-- fixed default base seeds; every failure records a replayable case seed.
-- Usage:  lune run tools/lune/fuzz [target]           (default: all)
--   env LUAUUI_FUZZ_CASES=N     scale case count (default 400)
--   env LUAUUI_FUZZ_SEED=S      replay ONE case seed for the target (raw
--                               error + stack surfaces; no artifact)
-- Exits nonzero on any failure, naming the requirement and the replay
-- command (UI-AGENT-001 command contract).

local process = require("@lune/process")

local artifact = require("./artifact")
local fuzz = require("../../tests/lib/fuzz")

local scheduler_fuzzer = require("../../tests/lib/fuzzers/scheduler")
local layout_fuzzer = require("../../tests/lib/fuzzers/layout")
local replication_fuzzer = require("../../tests/lib/fuzzers/replication")

type Target = {
	name: string,
	requirements: { string },
	baseSeed: number,
	case: (rng: any) -> (),
	extra: { { name: string, baseSeed: number, case: (rng: any) -> (), cases: number? } }?,
}

local TARGETS: { [string]: Target } = {
	scheduler = {
		name = "scheduler",
		requirements = { "UI-RUNTIME-001", "UI-RUNTIME-003", "UI-LIFE-002" },
		baseSeed = 94651,
		case = scheduler_fuzzer.case,
	},
	layout = {
		name = "layout",
		requirements = { "UI-LAYOUT-001", "UI-LAYOUT-002" },
		baseSeed = 260720,
		case = layout_fuzzer.case,
		extra = {
			{ name = "layout-adversarial", baseSeed = 999331, case = layout_fuzzer.adversarialCase, cases = 60 },
		},
	},
	replication = {
		name = "replication",
		requirements = { "UI-REPL-001", "UI-REPL-002" },
		baseSeed = 471120,
		case = replication_fuzzer.case,
	},
}

local targetArg = process.args[1] or "all"
local cases = tonumber(process.env.LUAUUI_FUZZ_CASES) or 400
local replaySeed = tonumber(process.env.LUAUUI_FUZZ_SEED)

if replaySeed ~= nil then
	local target = TARGETS[targetArg]
	assert(target ~= nil, `fuzz replay needs an explicit target (scheduler|layout|replication), got '{targetArg}'`)
	print(`fuzz: replaying {target.name} case seed {replaySeed} (raw error will surface)`)
	fuzz.replayCase(replaySeed, target.case)
	print("fuzz: replay completed with no failure")
	process.exit(0)
end

local names: { string } = {}
if targetArg == "all" then
	names = { "scheduler", "layout", "replication" }
else
	assert(TARGETS[targetArg] ~= nil, `unknown fuzz target '{targetArg}' (scheduler|layout|replication|all)`)
	names = { targetArg }
end

local anyFailed = false
for _, name in names do
	local target = TARGETS[name]
	local runs = {}
	local failures = 0
	local function runOne(runName: string, baseSeed: number, caseFn: (rng: any) -> (), runCases: number)
		local report = fuzz.run({ name = runName, baseSeed = baseSeed, cases = runCases, case = caseFn })
		failures += #report.failures
		table.insert(runs, {
			name = runName,
			baseSeed = baseSeed,
			cases = report.cases,
			fingerprint = report.fingerprint,
			failures = report.failures,
			replay = `LUAUUI_FUZZ_SEED=<seed> lune run tools/lune/fuzz {name}`,
		})
	end
	runOne(target.name, target.baseSeed, target.case, cases)
	for _, extra in target.extra or {} do
		runOne(extra.name, extra.baseSeed, extra.case, extra.cases or cases)
	end

	local status = if failures == 0 then "PASS" else "FAIL"
	artifact.writeJson(`artifacts/phase-4/fuzz-{name}.json`, {
		schema = "luauui-fuzz/1",
		target = name,
		status = status,
		requirements = target.requirements,
		totalCases = cases,
		runs = runs,
		hint = if failures == 0
			then ""
			else `re-run one failing case with LUAUUI_FUZZ_SEED=<seed> lune run tools/lune/fuzz {name}; the raw error and stack will surface`,
	})
	print(`fuzz {name}: {status} ({cases} cases/run, {failures} failure(s)) -> artifacts/phase-4/fuzz-{name}.json`)
	if failures > 0 then
		anyFailed = true
		print(`  FAILING requirement(s): {table.concat(target.requirements, ", ")}`)
	end
end

process.exit(if anyFailed then 1 else 0)
