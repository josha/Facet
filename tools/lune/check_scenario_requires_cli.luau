--!strict
-- CLI wrapper for the scenario/reference require-path guard (SHOWCASE2 task A).
-- Exit 0 only with zero violations.
local process = require("@lune/process")
local checker = require("./check_scenario_requires")

local result = checker.check()
if result.ok then
	print(
		`scenario requires: clean — {result.counts.files} files, `
			.. `{result.counts.requiresChecked} module-scope relative require(s) checked`
	)
	process.exit(0)
end
for _, v in result.violations do
	print(`{v.file} ({v.scriptPath}): require("{v.require}") — {v.reason}`)
end
print(`scenario requires: {#result.violations} violation(s)`)
process.exit(1)
