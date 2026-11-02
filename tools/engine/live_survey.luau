--!strict
local process = require("@std/process")
local Verify = require("../vendor/verify/src/core")
local Lute = require("../vendor/verify/src/lute")
local Double = require("../../tests/lib/live_double")
local Files = require("../facet/lib/files")

local output = process.args[2] or ".verify-survey/baseline"
local selected = process.args[3]
local controller = process.args[4] == "controller"
local interactive = process.args[4] == "interactive"
local only = process.args[5]
Files.makeDirectory(output)
local catalog: Double.Catalog? = nil
local discovery = Verify.createHarness({ source = "live-survey-catalog", now = os.clock })
discovery:case("catalog", function(check)
	catalog = Double.catalog(check)
end)
local discovered = discovery:run({ executor = "lute" })
assert(discovered.passed == 1, Verify.format(discovered))
local inventory = assert(catalog)
Files.write(output .. "/catalog.json", Lute.encode(inventory))
for _, suite in inventory.sources do
	if selected and selected ~= suite.id then
		continue
	end
	local reports: { Verify.Report } = {}
	for _, case in suite.cases do
		if (if interactive then case.interactive else case.automatic) and (only == nil or case.id == only) then
			local harness = Verify.createHarness({ source = suite.id, now = os.clock })
			harness:case(case.id, function(check)
				Double.run(check, suite.id, case.id, nil, controller)
			end)
			local report = harness:run({ executor = "lute" })
			Files.write(`{output}/{suite.id}/{case.id}.json`, Lute.encode(report))
			table.insert(reports, report)
		end
	end
	local report = Verify.merge(reports, "lute", {})
	Files.write(output .. "/" .. suite.id .. ".json", Lute.encode(report))
	print(`{suite.id}: {report.passed}/{report.total}`)
end
