--!strict
local process = require("@std/process")
local Verify = require("../vendor/verify/src/core")
local Lute = require("../vendor/verify/src/lute")
local Double = require("../../tests/lib/live_double")
local Files = require("../facet/lib/files")

local output = process.args[2]
local list = process.args[3]
Files.makeDirectory(output)
for line in string.gmatch(Lute.fixture.host.readFile(list), "[^\n]+") do
	local name, matched = string.match(line, "^(%S+)%s*(%S*)$")
	local mode: string = matched or ""
	local suite, id = string.match(assert(name), "^([^/]+)/(.+)$")
	local controller = mode == "controller"
	local harness = Verify.createHarness({ source = assert(suite), now = os.clock })
	local started = os.clock()
	harness:case(assert(id), function(check)
		Double.run(check, suite, id, nil, controller, if mode == "touch" then "iphone_14" else nil)
	end)
	local report = harness:run({ executor = "lute" })
	local elapsed = os.clock() - started
	local messages: { string } = {}
	for _, result in report.results do
		for _, failure in result.failures or {} do
			table.insert(messages, string.sub(tostring(failure.message), 1, 6000))
		end
		for _, step in result.steps or {} do
			if step.status ~= "passed" then
				table.insert(messages, "STEP " .. step.name .. ": " .. string.sub(tostring(step.message), 1, 300))
			end
		end
	end
	local safe = string.gsub(`{name}{if mode ~= "" then "@" .. mode else ""}`, "/", "__")
	Files.write(
		`{output}/{safe}.json`,
		Lute.encode({
			name = name,
			controller = controller,
			passed = report.passed,
			failed = report.failed,
			seconds = elapsed,
			messages = messages,
		})
	)
	print(`{if report.failed == 0 and report.passed == 1 then "PASS" else "FAIL"} {name} {mode} {math.floor(elapsed)}s`)
end
