--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Lune = require("../vendor/verify/src/lune")
local Verify = require("../vendor/verify/src/core")

local TIERS = { "one", "affected", "fast", "full", "release" }
local RECEIPTS = "artifacts/verify/suite"

export type Options = {
	tier: string,
	only: { string }?,
	jobs: number?,
	deadlineSeconds: number?,
	plan: Verify.Plan?,
	directory: string?,
	worker: string?,
}

local function rank(tier: string): number
	return assert(table.find(TIERS, tier), "unknown tier: " .. tier)
end

export type Inventory = { cases: { { id: string, source: string, tier: string? } } }

local function census(
	sources: { [string]: boolean },
	tier: string,
	committed: Inventory?
): ({ [string]: boolean }, { [string]: string })
	local inventory: Inventory = committed or serde.decode("json", fs.readFile("tests/case_inventory.json"))
	local expected: { [string]: boolean } = {}
	local higher: { [string]: string } = {}
	for _, case in inventory.cases do
		if sources[case.source] then
			if case.tier ~= nil and rank(case.tier) > rank(tier) then
				higher[case.id] = "tier:" .. case.tier
			else
				expected[case.id] = true
			end
		end
	end
	return expected, higher
end

local function committedPlan(only: { string }?): Verify.Plan
	local plan = Verify.validatePlan(serde.decode("json", fs.readFile("tests/plan.json")))
	if only == nil then
		return plan
	end
	assert(#only > 0, "an explicit source selection must not be empty")
	local units = {}
	for _, id in only do
		assert(fs.isFile(`tests/{id}.spec.luau`), "unknown spec: " .. id)
		table.insert(units, { id = id, locator = `tests/{id}.spec.luau`, requires = { "local-luau" } })
	end
	return Verify.validatePlan({ id = plan.id .. "-selected", policy = { caseIdStyle = "bare" }, units = units })
end

local function execute(options: Options): (Verify.ExecutionReport, Verify.Plan)
	rank(options.tier)
	local plan = options.plan or committedPlan(options.only)
	local jobs = options.jobs or 4
	local environment = { runtime = "lune", tier = options.tier }
	local host = Lune.host({
		worker = options.worker or "tests/worker.luau",
		command = { "/usr/bin/env", "FACET_TIER=" .. options.tier, process.env.LUNE or "lune", "run" },
		directory = options.directory or RECEIPTS,
		deadlineSeconds = options.deadlineSeconds or 600,
		name = "facet-lune-workers",
		capabilities = { "local-luau" },
		environment = environment,
		maxParallelBatches = jobs,
	})
	return Verify.execute(plan, host, { batchCount = #plan.units, parallel = jobs }), plan
end

local function findings(
	execution: Verify.ExecutionReport,
	plan: Verify.Plan,
	tier: string,
	inventory: Inventory?
): { string }
	local problems: { string } = {}
	local report = Verify.decode(execution.report)
	if not Verify.accountPlan(plan, execution).complete or not execution.provenance.complete then
		table.insert(problems, "the plan was not fully accounted for")
	end
	if report.environment.tier ~= tier then
		table.insert(problems, "the report does not carry the requested tier")
	end
	local sources: { [string]: boolean } = {}
	local locators: { [string]: boolean } = {}
	for _, unit in plan.units do
		sources[unit.id] = true
		locators[unit.locator] = true
	end
	local expected, higher = census(sources, tier, inventory)
	local seen: { [string]: boolean } = {}
	for _, result in report.results do
		seen[result.id] = true
		if not locators[result.source or ""] then
			table.insert(problems, "case from an unplanned source: " .. result.id)
		elseif higher[result.id] ~= nil then
			if result.status ~= "skipped" or result.skipReason ~= higher[result.id] then
				table.insert(problems, "case ran below its committed tier: " .. result.id)
			end
		elseif not expected[result.id] then
			table.insert(problems, "case absent from the committed census: " .. result.id)
		elseif result.status ~= "passed" then
			table.insert(problems, `{result.status}: {result.id}`)
		end
	end
	for id in expected do
		if not seen[id] then
			table.insert(problems, "census case did not report: " .. id)
		end
	end
	for id in higher do
		if not seen[id] then
			table.insert(problems, "tier-gated case did not report: " .. id)
		end
	end
	for _, fact in execution.facts do
		if fact.severity == "failure" then
			table.insert(problems, `{fact.code}: {fact.detail}`)
		end
	end
	table.sort(problems)
	return problems
end

local function tierReport(execution: Verify.ExecutionReport, tier: string): Verify.Report
	local report = table.clone(Verify.decode(execution.report))
	local results = {}
	local deferred = 0
	for _, result in report.results do
		local gate = result.skipReason and string.match(result.skipReason, "^tier:(.+)$")
		if result.status == "skipped" and gate ~= nil and table.find(TIERS, gate) and rank(gate) > rank(tier) then
			deferred += 1
		else
			table.insert(results, result)
		end
	end
	report.results = results
	report.total -= deferred
	report.skipped -= deferred
	return Verify.decode(report)
end

local function main()
	local tier = "one"
	local only: { string }? = nil
	local jobs: number? = nil
	local reportPath: string? = nil
	local runId: string? = nil
	local receipt = `{RECEIPTS}/latest.json`
	local index = 1
	while index <= #process.args do
		local flag = process.args[index]
		local value = process.args[index + 1]
		if flag == "--tier" then
			tier = value
		elseif flag == "--jobs" then
			jobs = tonumber(value)
		elseif flag == "--report" then
			reportPath = value
		elseif flag == "--run" then
			runId = value
		elseif flag == "--receipt" then
			receipt = value
		elseif string.sub(flag, 1, 2) ~= "--" then
			only = only or {}
			table.insert(only :: { string }, flag)
			index -= 1
		else
			error("usage: lune run tools/lune/suite_cli [SPEC]... [--tier T] [--jobs N] [--receipt PATH]")
		end
		index += 2
	end
	local execution, plan = execute({ tier = tier, only = only, jobs = jobs })
	fs.writeDir(RECEIPTS)
	fs.writeFile(receipt, serde.encode("json", execution, true))
	local problems = findings(execution, plan, tier)
	local report = execution.report
	if #problems > 0 then
		print(Verify.format(report))
	end
	print(
		`suite {tier}: {report.passed} passed, {report.failed} failed, {report.skipped} skipped of {report.total} cases from {#plan.units} sources`
	)
	for index = 1, math.min(#problems, 40) do
		print("  " .. problems[index])
	end
	if reportPath ~= nil and #problems == 0 then
		Lune.gate.writeReport(reportPath, assert(runId, "--report needs --run"), tierReport(execution, tier))
	end
	process.exit(if #problems == 0 then 0 else 1)
end

return { execute = execute, findings = findings, tierReport = tierReport, main = main }
