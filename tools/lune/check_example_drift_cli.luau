--!strict
-- CLI wrapper for the example property-authority drift lint. Exit 0 only with
-- zero violations; writes artifacts/example-quality-pass/drift.json.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local checker = require("./check_example_drift")

local result = checker.check()
if not fs.isDir("artifacts/example-quality-pass") then
	fs.writeDir("artifacts/example-quality-pass")
end
fs.writeFile(
	"artifacts/example-quality-pass/drift.json",
	serde.encode("json", {
		schema = "facet-example-drift/1",
		ok = result.ok,
		counts = result.counts,
		violations = result.violations,
		allowlist = checker.ALLOWLIST,
		scanned = checker.SCANNED_DIR,
	}, true)
)
if result.ok then
	print(
		`example drift: clean — {result.counts.files} files, {result.counts.lines} lines, `
			.. `{result.counts.roleUses} semantic role uses, {result.counts.allowlisted} allowlisted`
	)
	process.exit(0)
end
for _, problem in result.problems do
	print(problem)
end
print(`example drift: {#result.violations} violation(s)`)
process.exit(1)
