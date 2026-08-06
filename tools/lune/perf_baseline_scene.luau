--!strict
-- Baseline ONE named scene (or several) into bench/perf_budgets.json, leaving
-- every other scene's budget byte-identical.
--
-- WHY THIS EXISTS. `tools/perf.sh baseline` re-records the WHOLE budgets file. That
-- is right when the machine or the reference profile changes, and wrong when a
-- stage adds a scene: it would quietly re-base eighteen budgets that other stages
-- are relying on, in the same commit that adds a nineteenth. "Never silently
-- rebaseline" is the plan's rule; this is the tool that makes obeying it cheap.
--
-- It uses the SAME arithmetic tools/lune/perf.luau uses — the worst p95 over
-- REPEATS runs of the reference profile, times the same multiplier, floored the
-- same way — so a budget written here is indistinguishable from one written by a
-- full baseline, and the entry records that it was scoped.
--
-- Usage: lune run tools/lune/perf_baseline_scene <scene> [<scene> ...]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local perf_runner = require("../../bench/perf_runner")
local perf_scenes = require("../../bench/perf_scenes")
local perf_profiles = require("../../bench/perf_profiles")

local BUDGETS_PATH = "bench/perf_budgets.json"
local BUDGET_MULTIPLIER = 4.0
local BUDGET_FLOOR_MS = 0.10
local UI_FRAME_SHARE = 0.25
local REPEATS = 5

local wanted: { [string]: boolean } = {}
local names: { string } = {}
for i = 1, #process.args do
	wanted[process.args[i]] = true
	table.insert(names, process.args[i])
end
assert(#names > 0, "usage: lune run tools/lune/perf_baseline_scene <scene> [<scene> ...]")

local selected = {}
for _, scene in perf_scenes do
	if wanted[scene.name] then
		table.insert(selected, scene)
	end
end
assert(
	#selected == #names,
	`perf_baseline_scene: {#selected} of {#names} named scene(s) exist in bench/perf_scenes.luau`
)

assert(fs.isFile(BUDGETS_PATH), `perf_baseline_scene: missing {BUDGETS_PATH}`)
local budgets = serde.decode("json", fs.readFile(BUDGETS_PATH))

local referenceProfile = perf_profiles.get(perf_profiles.REFERENCE)
assert(
	budgets.referenceProfile == perf_profiles.REFERENCE,
	`perf_baseline_scene: the budgets file was recorded against '{budgets.referenceProfile}' but the current `
		.. `reference is '{perf_profiles.REFERENCE}'; a scoped baseline must not mix reference profiles`
)
local ceilingMs = perf_runner.ceilingMsFor(referenceProfile.frameTargetHz, UI_FRAME_SHARE)

local worst: { [string]: number } = {}
local best: { [string]: number } = {}
local requirement: { [string]: string } = {}
for pass = 1, REPEATS do
	local report = perf_runner.run(selected, { referenceProfile })
	for _, r in report.runs do
		local p95 = r.phases.total.p95_ms
		worst[r.scene] = math.max(worst[r.scene] or 0, p95)
		best[r.scene] = math.min(best[r.scene] or math.huge, p95)
		requirement[r.scene] = r.requirement
	end
	print(`perf_baseline_scene: repeat {pass}/{REPEATS}`)
end

for _, name in names do
	local p95 = worst[name]
	budgets.scenes[name] = {
		total_p95_ms = math.max(p95 * BUDGET_MULTIPLIER, BUDGET_FLOOR_MS),
		requirement = requirement[name],
		observed_p95_ms = p95,
		baselineRepeats = REPEATS,
		observed_p95_min_ms = best[name],
		observed_p95_max_ms = worst[name],
		frameTargetHz = referenceProfile.frameTargetHz,
		frameBudgetMs = 1000 / referenceProfile.frameTargetHz,
		ceilingMs = ceilingMs,
		-- recorded so a reader can tell a scoped baseline from a whole-file one
		scopedBaseline = true,
		hint = `scene '{name}' ({requirement[name]}) exceeded its headless trend budget — profile the reactive/layout `
			.. `path it exercises; re-baseline with 'lune run tools/lune/perf_baseline_scene {name}' ONLY if the cost `
			.. `is intended`,
	}
	print(
		string.format(
			"perf_baseline_scene: %s worst p95 %.4fms (min %.4f) -> budget %.3fms, ceiling %.3fms",
			name,
			p95,
			best[name],
			budgets.scenes[name].total_p95_ms,
			ceilingMs
		)
	)
end

fs.writeFile(BUDGETS_PATH, serde.encode("json", budgets, true) .. "\n")
print(`perf_baseline_scene: wrote {#names} scene budget(s) into {BUDGETS_PATH}; every other entry is untouched`)
