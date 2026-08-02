--!strict
-- LuauUI fault-injection command (design §17 Phase 4, §16.1). Runs every
-- scenario in tests/lib/fault_scenarios.luau at scaled iteration counts and
-- writes artifacts/phase-4/faults.json. Deterministic: seeded storms record
-- replayable seeds in their error messages.
-- Usage:  lune run tools/lune/faults        (env LUAUUI_FAULT_ITERATIONS=N)
-- Exits nonzero on any scenario failure, naming the requirement + scenario.

local process = require("@lune/process")

local artifact = require("./artifact")
local scenarios = require("../../tests/lib/fault_scenarios")

local iterations = tonumber(process.env.LUAUUI_FAULT_ITERATIONS) or 200

local results = {}
local anyFailed = false
for _, scenario in scenarios.list do
	local ok, err = pcall(scenario.run, iterations)
	table.insert(results, {
		name = scenario.name,
		summary = scenario.summary,
		requirements = scenario.requirements,
		iterations = iterations,
		state = if ok then "PASS" else "FAIL",
		error = if ok then nil else tostring(err),
	})
	print(`faults {scenario.name}: {if ok then "PASS" else "FAIL"}`)
	if not ok then
		anyFailed = true
		print(`  FAILING requirement(s): {table.concat(scenario.requirements, ", ")}`)
		print(`  {tostring(err)}`)
	end
end

artifact.writeJson("artifacts/phase-4/faults.json", {
	schema = "luauui-faults/1",
	status = if anyFailed then "FAIL" else "PASS",
	iterations = iterations,
	scenarios = results,
	hint = if anyFailed
		then "seeded scenarios name a replayable seed in their error; re-run the paired spec (tests/faults.spec.luau) or bisect with the seed"
		else "",
})
print(`faults: {if anyFailed then "FAIL" else "PASS"} -> artifacts/phase-4/faults.json`)
process.exit(if anyFailed then 1 else 0)
