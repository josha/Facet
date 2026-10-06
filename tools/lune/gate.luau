--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Gate = require("../vendor/verify/src/gate")
local Lune = require("../vendor/verify/src/lune")
local Verify = require("../vendor/verify/src/core")

local TIERS = { "affected", "fast", "full", "release" }
local SELECTED = {
	affected = { "fast" },
	fast = { "fast" },
	full = { "fast", "full" },
}
local DEFERRAL = {
	studio = "the live Studio evidence is not recorded on this host",
	device = "the physical device evidence is not recorded on this host",
	perf = "a host timing budget failed away from the reference host",
}
local ARTIFACTS = "artifacts/verify/native"
local CATALOG = "tools/lune/producers.json"
local CENSUS = "tests/case_inventory.json"
local WORKER = "tests/worker.luau"

export type Entry = {
	id: string,
	tier: string,
	environment: string,
	kind: ("command" | "build" | "tests")?,
	argv: { string }?,
	after: { string }?,
	report: Gate.ReportExpectation?,
	deadlineSeconds: number?,
	replaces: { string }?,
	worker: string?,
	locators: { string }?,
	cases: { string }?,
	workers: number?,
	sourceDeadlineSeconds: number?,
}

local function census(path: string, sources: { [string]: boolean }): { string }
	local cases = {}
	for _, case in serde.decode("json", fs.readFile(path)).cases do
		if sources[case.source] then
			table.insert(cases, case.id)
		end
	end
	return cases
end

local function sources(names: { string }): ({ string }, { [string]: boolean })
	local locators, named = {}, {}
	for _, name in names do
		assert(fs.isFile(`tests/{name}.spec.luau`), "unknown spec: " .. name)
		table.insert(locators, `tests/{name}.spec.luau`)
		named[name] = true
	end
	return locators, named
end

local function catalog(): { Entry }
	local entries: { Entry } = {}
	for _, producer in serde.decode("json", fs.readFile(CATALOG)).producers do
		local entry: Entry = {
			id = producer.id,
			tier = producer.tier,
			environment = producer.environment or "deterministic",
			kind = producer.kind,
			argv = if producer.run then string.split(producer.run, " ") else nil,
			after = producer.after,
			deadlineSeconds = producer.deadlineSeconds,
			replaces = producer.replaces,
			worker = producer.worker,
			workers = producer.workers,
			sourceDeadlineSeconds = producer.sourceDeadlineSeconds,
		}
		if producer.plan then
			local names = {}
			for _, unit in serde.decode("json", fs.readFile(producer.plan)).units do
				assert(unit.locator == `tests/{unit.id}.spec.luau`, "plan locator differs from its source: " .. unit.id)
				table.insert(names, unit.id)
			end
			local locators, named = sources(names)
			entry.locators, entry.cases = locators, census(producer.census, named)
		end
		table.insert(entries, entry)
	end
	return entries
end

local function define(entries: { Entry }, referenceHost: boolean, id: string?): Gate.Definition
	local producers: { Gate.ProducerDraft } = {}
	local deferrals: { [string]: string } = {}
	for _, entry in entries do
		local reason = DEFERRAL[entry.environment]
		local deferrable = reason ~= nil and not (entry.environment == "perf" and referenceHost)
		if deferrable then
			deferrals[entry.id] = reason
		end
		local tests = entry.kind == "tests"
		table.insert(producers, {
			id = entry.id,
			kind = entry.kind or "command",
			why = if entry.replaces then "replaces " .. table.concat(entry.replaces, ", ") else nil,
			argv = entry.argv,
			tier = entry.tier,
			tags = { entry.environment },
			after = entry.after,
			report = entry.report,
			deadlineSeconds = entry.deadlineSeconds,
			exit = if deferrable then { [2] = "deferred" :: Gate.ExitClass } else nil,
			worker = entry.worker,
			locators = entry.locators,
			cases = entry.cases,
			isolate = if tests then true else nil,
			workers = entry.workers,
			sourceDeadlineSeconds = entry.sourceDeadlineSeconds,
		})
	end
	return Gate.define({
		id = id or "facet",
		producers = producers,
		policy = { concurrency = 1, commandDeadlineSeconds = 1800, deferrals = deferrals },
	})
end

local function selection(tier: string): Gate.Selection?
	assert(table.find(TIERS, tier), "unknown tier: " .. tier)
	return if SELECTED[tier] then { tiers = SELECTED[tier] } else nil
end

local function completeTier(outcome: Gate.Outcome): boolean
	local scope = outcome.scope
	return #scope.ids == 0 and #scope.cases == 0 and #scope.notSelected == #scope.skippedByTier
end

local function conclusion(outcome: Gate.Outcome, tier: string): (string, number)
	local acceptance = outcome.acceptance
	if acceptance.verdict == "failed" then
		return "FAIL", 1
	end
	if acceptance.releasable then
		return "PASS (releasable)", 0
	end
	if not completeTier(outcome) then
		return "PASS_SELECTED (focused run; not the tier)", 0
	end
	if tier == "release" then
		return "FAIL (environment deferrals block release)", 1
	end
	local deferred = #acceptance.deferred
	local suffix = if deferred > 0 then `; {deferred} environment deferral(s)` else ""
	if tier == "full" then
		return `PASS (complete full tier; not releasable{suffix})`, 0
	end
	return `PASS_PARTIAL (working tier; not full verification{suffix})`, 0
end

local function output(command: string, arguments: { string }): string
	local result = process.exec(command, arguments)
	return if result.ok then (string.gsub(result.stdout, "%s+$", "")) else ""
end

local function build(): Verify.EvidenceBuild
	return {
		commit = output("git", { "rev-parse", "HEAD" }),
		tree = output("git", { "rev-parse", "HEAD^{tree}" }),
		clean = output("git", { "status", "--porcelain" }) == "",
		digest = output("python3", {
			"-c",
			"import sys; sys.path.insert(0, 'tools'); import package; print(package.source_hash())",
		}),
	}
end

local function run(gate: Gate.Definition, tier: string, chosen: Gate.Selection?, referenceHost: boolean): Gate.Outcome
	local outcome = Lune.gate.run(gate, {
		directory = ARTIFACTS .. "/gate",
		build = build(),
		selection = chosen,
		environment = {
			tier = tier,
			referenceHost = tostring(referenceHost),
			historicalParity = "not-established",
		},
		observe = function(record: Gate.Record)
			if record.status == "not_selected" then
				return
			end
			print(`{record.id}: {record.status} ({string.format("%.1f", record.durationMicros / 1e6)}s)`)
			if record.status ~= "passed" then
				print("  " .. tostring(record.deferral or record.detail))
				local log = record.log
				if log ~= nil and record.status ~= "deferred" then
					print(log.stdout)
					print(log.stderr)
				end
			end
		end,
	})
	for _, result in outcome.execution.report.results do
		if result.status == "failed" or result.status == "timed_out" then
			print(`{result.status}: {result.id}`)
			for _, failure in result.failures do
				print(`  {failure.phase}: {failure.message}`)
			end
		end
	end
	print(Gate.format(outcome))
	return outcome
end

local function specs(names: { string }, tier: string): Gate.Outcome
	local locators, named = sources(names)
	local gate = define({
		{
			id = "specs",
			tier = "fast",
			environment = "deterministic",
			kind = "tests",
			worker = WORKER,
			locators = locators,
			cases = census(CENSUS, named),
			workers = 4,
			deadlineSeconds = 3600,
			sourceDeadlineSeconds = 600,
		},
	}, false, "facet-specs")
	return run(gate, tier, if tier == "release" then nil else { tiers = { "fast" } }, false)
end

local function main()
	local tier: string? = nil
	local rerun: string | boolean = false
	local referenceHost, explained, focused = false, false, false
	local names: { string } = {}
	local index = 1
	while index <= #process.args do
		local flag = process.args[index]
		local following = process.args[index + 1]
		if flag == "spec" and index == 1 then
			focused = true
		elseif flag == "--tier" and focused and following then
			index += 1
			tier = following
		elseif focused and string.sub(flag, 1, 2) ~= "--" then
			table.insert(names, flag)
		elseif table.find(TIERS, flag) and not focused then
			tier = flag
		elseif flag == "--rerun" then
			rerun = true
			if following and string.sub(following, 1, 2) ~= "--" and not table.find(TIERS, following) then
				index += 1
				rerun = following
			end
		elseif flag == "--reference-host" then
			referenceHost = true
		elseif flag == "--explain" then
			explained = true
		else
			print(
				"usage: tools/verify.sh [affected|fast|full|release] [--rerun [PRODUCER]] [--reference-host] [--explain]"
			)
			print("       tools/verify.sh spec SPEC... [--tier full|release]")
			process.exit(2)
		end
		index += 1
	end
	fs.writeDir(ARTIFACTS)
	if focused then
		assert(#names > 0, "name at least one spec")
		local outcome = specs(names, tier or "full")
		process.exit(if outcome.acceptance.verdict == "failed" then 1 else 0)
	end
	local chosenTier = tier or "full"
	local gate = define(catalog(), referenceHost)
	print(`Facet verification gate: {chosenTier}; {#gate.producers} producers declared.`)
	print(
		"Historical parity: NOT ESTABLISHED. See docs/guide/20-verification-parity.md for the producer and assertion comparison with main."
	)
	if explained then
		print(
			"Exit 2 from a studio, device or perf producer is an explicit deferral: the evidence is not recorded on this host. --reference-host makes a perf deferral a failure. A deferral is never releasable."
		)
		print(Gate.list(gate))
	end
	local chosen = selection(chosenTier)
	if rerun == true then
		local previous, problem = Lune.gate.last(gate, { directory = ARTIFACTS .. "/gate" })
		chosen = Gate.rerun((assert(previous, problem)))
		assert(chosen, "the last run left nothing to rerun")
	elseif rerun then
		chosen = { ids = { rerun :: string }, tiers = SELECTED[chosenTier] }
	end
	local outcome = run(gate, chosenTier, chosen, referenceHost)
	local status, code = conclusion(outcome, chosenTier)
	fs.writeFile(`{ARTIFACTS}/report.json`, serde.encode("json", outcome, true))
	if completeTier(outcome) then
		fs.writeFile(`artifacts/verify/latest-{chosenTier}.json`, serde.encode("json", outcome, true))
	end
	print(`facet {chosenTier}: {status}; {ARTIFACTS}/report.json`)
	process.exit(code)
end

return {
	catalog = catalog,
	define = define,
	selection = selection,
	conclusion = conclusion,
	completeTier = completeTier,
	specs = specs,
	main = main,
}
