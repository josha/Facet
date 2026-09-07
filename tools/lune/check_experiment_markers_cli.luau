--!strict
-- CLI wrapper for the scratch-experiment-marker guard (RED-TEAM C1).
-- Exit 0 only when no `ZZ`-prefixed name exists anywhere under `src/`.
local process = require("@lune/process")
local checker = require("./check_experiment_markers")

local result = checker.check()
if result.ok then
	print(`check_experiment_markers: PASS — {result.counts.files} modules, {result.counts.lines} lines, no ZZ marker`)
	process.exit(0)
end
for _, v in result.violations do
	print("  " .. checker.describe(v))
end
print(`check_experiment_markers: FAIL — {#result.violations} scratch marker(s) in src/`)
process.exit(1)
