--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Double = require("./lib/live_double")
local Lute = require("../tools/vendor/verify/src/lute")

return function(harness: Verify.Harness)
	for _, id in { "screen-padding-and-gap", "zstack-alignment", "stack-distribution" } do
		harness:case(`original live primitives/{id} on the Verify engine double`, function(check)
			Double.run(check, "primitives", id)
		end)
	end
	harness:case("the unchanged live assertions reject a planted gap regression", function(check)
		local path = "tools/studio/live/suites/primitives.luau"
		local source, count = string.gsub(Lute.fixture.host.readFile(path), 'gap = "s"', 'gap = "m"', 1)
		check:expect(count):toBe(1)
		local proof = Verify.createHarness({ now = os.clock })
		proof:case("planted gap", function(context)
			Double.run(context, "primitives", "screen-padding-and-gap", { [path] = source })
		end)
		local report = proof:run({ executor = "live-double-defect" })
		check:expect(report.failed):toBe(1)
		local detected = false
		for _, step in report.results[1].steps do
			detected = detected or step.name == "B follows A by 10 + 8" and step.status == "failed"
		end
		check:expect(detected):toBe(true)
	end)
end
