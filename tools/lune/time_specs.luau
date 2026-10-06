--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local outcome = serde.decode("json", fs.readFile(process.args[1] or "artifacts/verify/native/report.json"))
local rows = {}
local bySource = {}
for _, result in outcome.execution.report.results do
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
local lines = { "spec\tcases\tcases_ms" }
for _, row in rows do
	table.insert(lines, `{row.spec}\t{row.cases}\t{row.casesMs}`)
end
local output = process.args[2] or "artifacts/spec-timings.tsv"
fs.writeFile(output, table.concat(lines, "\n") .. "\n")
print(`spec timings from the last gate outcome: {output}`)
