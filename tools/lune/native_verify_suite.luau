--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local workers = require("./run_each_spec")
local Verify = require("../vendor/verify/src/core")
local plan = Verify.validatePlan(serde.decode("json", fs.readFile("tests/plan.json")))
local selected = serde.decode("json", fs.readFile("artifacts/verify/native/specs.json"))
assert(#selected > 0, "native verification selected no specs")
local selectedPlan = Verify.selectPlan(plan, { ids = selected })
assert(#selectedPlan.units == #selected, "selected specs must be in the committed Verify plan")
local tier = process.args[1] or "full"
local execution = workers.execute({
	tier = tier,
	jobs = 4,
	timeout = 600,
	only = selected,
	directory = "artifacts/verify/native/workers",
	output = "artifacts/verify/native/suite.json",
})
print(Verify.format(execution.report))
assert(Verify.accountPlan(selectedPlan, execution).complete, "every selected source must be accounted for")
if not workers.accept(execution, tier) then
	process.exit(1)
end
