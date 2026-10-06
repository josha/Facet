--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Verify = require("../tools/vendor/verify/src/core")
local runner = require("./runner")

local name = process.args[1]
assert(name ~= nil and name ~= "", "usage: lune run tests/run_one <spec-name> [one|fast|affected|full|release]")
local tier = process.args[2] or "one"
assert(table.find({ "one", "fast", "affected", "full", "release" }, tier), "unknown single-spec tier")
local plan = Verify.validatePlan(serde.decode("json", fs.readFile("tests/plan.json")))
local focused = Verify.selectPlan(plan, { ids = { name } })
if #focused.units == 0 then
	local census = serde.decode("json", fs.readFile("tests/case_inventory.json"))
	local known = false
	for _, case in census.cases do
		if case.source == name then
			known = true
		end
	end
	assert(known, "unknown spec: " .. name)
	focused = Verify.validatePlan({
		id = "facet-single-source",
		policy = { caseIdStyle = "bare" },
		units = { { id = name, locator = "tests/" .. name .. ".spec.luau", requires = { "local-luau" } } },
	})
end
assert(#focused.units == 1, "exactly one declared source is required")
local execution = runner.execute(focused, tier, process.env.FACET_SUITE_JSON)
if not runner.accept(execution, tier) then
	process.exit(1)
end
