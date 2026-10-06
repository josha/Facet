--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Verify = require("../vendor/verify/src/core")

local input = serde.decode("json", fs.readFile((assert(process.args[1], "producer input path required"))))
local output = assert(process.args[2], "producer output path required")
local units = {}
local commands = {}
for _, producer in input.producers do
	table.insert(units, { id = producer.id, locator = producer.id, requires = { "command" } })
	commands[producer.id] = producer
end
local plan =
	Verify.validatePlan({ id = "facet-producers", units = units, policy = { caseIdStyle = "bare", batchCount = 1 } })
local records = {}
local environment = { tier = input.tier, commit = input.commit or "unknown" }
local execution = Verify.execute(plan, {
	name = "facet-commands",
	now = os.clock,
	capabilities = { "command" },
	environment = environment,
	runBatch = function(batch)
		local reports = {}
		for _, unit in batch.units do
			local producer = commands[unit.id]
			local command = producer.command
			local args = table.clone(command)
			table.remove(args, 1)
			print(`{unit.id}: RUN {table.concat(command, " ")}`)
			local started = os.clock()
			local launched, result = pcall(process.exec, command[1], args)
			local code = if launched then result.code else 1
			local diagnostics = if launched then result.stdout .. result.stderr else tostring(result)
			local log = `artifacts/verify/native/{unit.id}.log`
			fs.writeFile(log, diagnostics)
			local status = if code == 0 then "PASS" else "FAIL"
			if
				code == 2
				and (
					producer.environment == "studio"
					or producer.environment == "device"
					or (producer.environment == "perf" and not input.referenceHost)
				)
			then
				status = "FAIL_ENVIRONMENT"
			end
			local harness = Verify.createHarness({ source = unit.id, now = os.clock, prefixIds = false })
			harness:case(unit.id, {
				id = unit.id,
				run = function(context)
					context:artifact("command log", log, "text/plain")
					if status == "FAIL_ENVIRONMENT" then
						context:skip("environment:" .. producer.environment)
					end
					context:expect(code):toBe(0)
					if unit.id == "suite" then
						local suite = serde.decode("json", fs.readFile("artifacts/verify/native/suite.json"))
						Verify.decode(suite.report)
						context:expect(suite.provenance.complete):toBe(true)
					end
				end,
			})
			local report =
				harness:run({ executor = "facet-commands", environment = environment, capabilities = { "command" } })
			if report.failed > 0 then
				status = "FAIL"
			end
			table.insert(reports, report)
			table.insert(records, {
				id = unit.id,
				status = status,
				exitCode = code,
				environment = producer.environment,
				replaces = producer.replaces,
				seconds = os.clock() - started,
				log = log,
			})
			print(`{unit.id}: {status} ({string.format("%.1f", os.clock() - started)}s)`)
			if status == "FAIL" then
				print(string.sub(diagnostics, -5000))
				print(Verify.format(report))
			end
		end
		return { status = "returned", report = Verify.merge(reports, "facet-commands", environment) }
	end,
})
assert(Verify.accountPlan(plan, execution).complete, "producer plan was not fully accounted for")
Verify.decode(execution.report)
fs.writeFile(output, serde.encode("json", { execution = execution, producers = records }, true))
if not execution.provenance.complete or execution.report.total ~= #input.producers then
	process.exit(1)
end
