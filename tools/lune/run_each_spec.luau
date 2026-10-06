--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")
local Verify = require("../vendor/verify/src/core")
local runner = require("../../tests/runner")

local function execute(input: any): Verify.ExecutionReport
	local plan = Verify.validatePlan(serde.decode("json", fs.readFile("tests/plan.json")))
	if input.only then
		assert(#input.only > 0, "an explicit source selection must not be empty")
		plan = Verify.selectPlan(plan, { ids = input.only })
		assert(#plan.units == #input.only, "every selected source must be in the committed plan")
	end
	plan.policy.batchCount = #plan.units
	plan.policy.maxParallelBatches = input.jobs
	local directory = input.directory
	fs.writeDir(directory)
	local tier = input.tier or "one"
	local environment = { runtime = "lune", tier = tier }
	local host: Verify.Host = {
		name = "facet-lune-workers",
		now = os.clock,
		capabilities = { "local-luau" },
		environment = environment,
		runBatch = function(batch: Verify.PlanBatch): Verify.BatchOutcome
			assert(#batch.units == 1, "one source per worker batch required")
			local unit = batch.units[1]
			local output = `{directory}/{unit.id}.json`
			if fs.isFile(output) then
				fs.removeFile(output)
			end
			local result =
				process.exec("python3", { "tools/verify_worker.py", unit.id, output, tostring(input.timeout), tier })
			fs.writeFile(`{directory}/{unit.id}.log`, result.stdout .. result.stderr)
			if result.code == 124 then
				return { status = "timed_out", detail = "the worker process group was killed after its deadline" }
			end
			if not fs.isFile(output) then
				return { status = "faulted", detail = `worker exited {result.code} without its receipt` }
			end
			local execution = serde.decode("json", fs.readFile(output))
			local report = Verify.decode(execution.report)
			if
				not execution.provenance.complete
				or report.total == 0
				or (result.code ~= 0 and report.failed + report.cancelled + report.timedOut == 0)
			then
				return { status = "faulted", detail = "worker exit and Verify receipt disagree" }
			end
			return { status = "returned", report = report }
		end,
	}
	function host.runBatches(batches: { Verify.PlanBatch }, deliver: (number, Verify.BatchOutcome) -> ())
		local remaining = #batches
		for _, batch in batches do
			task.spawn(function()
				local ok, outcome = pcall(host.runBatch, batch)
				deliver(batch.index, if ok then outcome else { status = "faulted", detail = tostring(outcome) })
				remaining -= 1
			end)
		end
		while remaining > 0 do
			task.wait()
		end
	end
	local execution = Verify.execute(plan, host)

	if input.output then
		fs.writeFile(input.output, serde.encode("json", execution, true))
	end
	return execution
end

return { execute = execute, accept = runner.accept }
