--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Verify = require("../vendor/verify/src/core")
local runner = require("../../tests/runner")
local plan = Verify.validatePlan(serde.decode("json", fs.readFile("tests/plan.json")))
local execution = runner.execute(plan, "full", nil)
local rows = {}
local bySource = {}
for _, result in execution.report.results do
	local source = result.source or "unknown"
	local row = bySource[source]
	if not row then
		row = { spec = source, cases = 0, casesMs = 0 }
		bySource[source] = row
		table.insert(rows, row)
	end
	row.cases += 1
	row.casesMs += result.durationMicros / 1000
end
local output = process.args[1] or "artifacts/spec-timings.json"
fs.writeFile(output, serde.encode("json", { execution = execution, sources = rows }, true))
local lines = { "spec\tcases\tcases_ms" }
for _, row in rows do
	table.insert(lines, `{row.spec}\t{row.cases}\t{row.casesMs}`)
end
fs.writeFile(output .. ".tsv", table.concat(lines, "\n") .. "\n")
print(`spec timings: {output} and {output}.tsv`)
if not runner.accept(execution, "full") then
	process.exit(1)
end
