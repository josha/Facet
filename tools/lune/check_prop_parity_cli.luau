--!strict
-- CLI for the property-parity checker (Milestone 0 acceptance row M0-A3):
--   lune run tools/lune/check_prop_parity_cli
-- Exits 0 when the public schema, dirty classification, render authority,
-- adapter binding, layout/handler consumption, exported types, and API
-- reference all describe the same property surface.

local process = require("@lune/process")
local checker = require("./check_prop_parity")

local result = checker.check()
if result.ok then
	print(
		`check_prop_parity: PASS ({result.counts.classes} classes, {result.counts.props} properties, `
			.. `{result.counts.deprecated} diagnosed, {result.counts.typedFields} typed fields)`
	)
	process.exit(0)
end

print(`check_prop_parity: FAIL [UI-AGENT-001] — {#result.problems} problem(s):`)
for _, p in result.problems do
	print(`  - {p}`)
end
print("hint: src/blueprint_schema.luau is the single source of truth; make the other views follow it")
process.exit(1)
