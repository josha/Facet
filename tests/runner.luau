--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Verify = require("../tools/vendor/verify/src/core")
local requireDynamic = require :: (any) -> any

local runner = {}

function runner.execute(plan: Verify.PlanDraft, tier: string, jsonOut: string?): Verify.ExecutionReport
	local environment = { runtime = "lune", tier = tier }
	local host: Verify.Host = {
		name = "facet-lune",
		now = os.clock,
		capabilities = { "local-luau" },
		environment = environment,
		runBatch = function(batch)
			local reports = {}
			for _, unit in batch.units do
				print(`LOAD {unit.id}`)
				local loaded, register = pcall(requireDynamic, "../" .. string.gsub(unit.locator, "%.luau$", ""))
				local harness = Verify.createHarness({ now = os.clock, source = unit.id, prefixIds = false })
				local phase = "load"
				local ok, problem = loaded, register
				if loaded then
					phase = "registration"
					ok, problem = pcall(function()
						assert(type(register) == "function", "a spec must return a Verify registration function")
						register(harness, tier)
					end)
				end
				local report
				if ok then
					report = harness:run({
						executor = "facet-lune",
						capabilities = { "local-luau" },
						environment = environment,
					})
					if report.total == 0 then
						ok, problem = false, "the source registered no cases"
					end
				end
				if not ok then
					report = Verify.syntheticReport({
						executor = "facet-lune",
						environment = environment,
						id = unit.id .. "::" .. phase,
						source = unit.id,
						name = unit.id,
						status = "failed",
						phase = phase :: any,
						message = tostring(problem),
					})
				end
				print(Verify.format(report :: Verify.Report))
				table.insert(reports, report)
			end
			return { status = "returned", report = Verify.merge(reports, "facet-lune", environment) }
		end,
	}
	local execution = Verify.execute(plan, host)
	Verify.decode(execution.report)
	if jsonOut and jsonOut ~= "" then
		local dir = string.match(jsonOut, "^(.*)/[^/]*$")
		if dir then
			fs.writeDir(dir)
		end
		fs.writeFile(jsonOut, serde.encode("json", execution, true))
	end
	return execution
end

function runner.accept(execution: Verify.ExecutionReport, tier: string): boolean
	local report = Verify.decode(execution.report)
	if
		not execution.provenance.complete
		or report.total == 0
		or report.failed + report.unsupported + report.timedOut + report.cancelled > 0
	then
		return false
	end
	for _, result in report.results do
		if result.status == "skipped" then
			local lowerTier = tier == "one" or tier == "fast" or tier == "affected"
			local deferred = (result.skipReason == "tier:release" and tier ~= "release")
				or (result.skipReason == "tier:full" and lowerTier)
			if not deferred then
				return false
			end
		end
	end
	return true
end

return runner
