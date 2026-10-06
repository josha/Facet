--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
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
local SUITE_RECEIPT = ARTIFACTS .. "/suite.json"

export type Entry = {
	id: string,
	argv: { string },
	tier: string,
	environment: string,
	kind: ("command" | "build")?,
	after: { string }?,
	report: Verify.GateReportExpectation?,
	deadlineSeconds: number?,
	replaces: { string }?,
}

local function expectedCases(tier: string): { string }
	local plan = serde.decode("json", fs.readFile("tests/plan.json"))
	local planned = {}
	for _, unit in plan.units do
		planned[unit.id] = true
	end
	local cases = {}
	for _, case in serde.decode("json", fs.readFile("tests/case_inventory.json")).cases do
		local gated = case.tier ~= nil and (table.find(TIERS, case.tier) or 0) > (table.find(TIERS, tier) or 0)
		if planned[case.source] and not gated then
			table.insert(cases, case.id)
		end
	end
	return cases
end

local function catalog(tier: string): { Entry }
	local entries: { Entry } = {}
	for _, producer in serde.decode("json", fs.readFile(CATALOG)).producers do
		local command = string.gsub(producer.run, "{tier}", tier)
		command = string.gsub(command, "{suite}", SUITE_RECEIPT)
		local cases = if producer.report == "census" then expectedCases(tier) else nil
		table.insert(entries, {
			id = producer.id,
			argv = string.split(command, " "),
			tier = producer.tier,
			environment = producer.environment or "deterministic",
			kind = producer.kind,
			after = producer.after,
			report = if cases then { minimum = #cases, cases = cases } else nil,
			deadlineSeconds = producer.deadlineSeconds,
			replaces = producer.replaces,
		})
	end
	return entries
end

local function define(entries: { Entry }, referenceHost: boolean, id: string?): Verify.Gate
	local producers: { Verify.GateProducerDraft } = {}
	local deferrals: { [string]: string } = {}
	for _, entry in entries do
		local reason = DEFERRAL[entry.environment]
		local deferrable = reason ~= nil and not (entry.environment == "perf" and referenceHost)
		if deferrable then
			deferrals[entry.id] = reason
		end
		table.insert(producers, {
			id = entry.id,
			kind = entry.kind or "command",
			argv = entry.argv,
			tier = entry.tier,
			tags = { entry.environment },
			after = entry.after,
			report = entry.report,
			deadlineSeconds = entry.deadlineSeconds,
			exit = if deferrable then { [2] = "deferred" :: Verify.GateExitClass } else nil,
		})
	end
	return Verify.defineGate({
		id = id or "facet",
		producers = producers,
		policy = { concurrency = 1, commandDeadlineSeconds = 1800, deferrals = deferrals },
	})
end

local function selection(tier: string, rerun: string?): Verify.GateSelection?
	assert(table.find(TIERS, tier), "unknown tier: " .. tier)
	if rerun ~= nil then
		return { ids = { rerun }, tiers = SELECTED[tier] }
	end
	return if SELECTED[tier] then { tiers = SELECTED[tier] } else nil
end

local function tierComplete(outcome: Verify.GateOutcome, tier: string, rerun: string?): boolean
	if rerun ~= nil then
		return false
	end
	local tiers = SELECTED[tier]
	for _, record in outcome.producers do
		local wanted = tiers == nil or table.find(tiers, record.tier :: string) ~= nil
		if wanted and (not record.selected or record.status == "not_run" or record.status == "not_selected") then
			return false
		end
	end
	return true
end

local function conclusion(outcome: Verify.GateOutcome, tier: string, rerun: string?): (string, number)
	local acceptance = outcome.acceptance
	if acceptance.verdict == "failed" then
		return "FAIL", 1
	end
	if acceptance.releasable then
		return "PASS (releasable)", 0
	end
	if tier == "release" and rerun == nil then
		return "FAIL (environment deferrals block release)", 1
	end
	if not tierComplete(outcome, tier, rerun) then
		return "PASS_SELECTED (focused run; not the tier)", 0
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

local function explain(entries: { Entry }, tier: string)
	print(
		`Selection: every producer whose tier is in the '{tier}' run. Each command runs afresh; no stored result is reused.`
	)
	print(
		"Status: exit 0 passes. Exit 2 from a studio, device or perf producer is an explicit deferral: the evidence is not recorded on this host. --reference-host makes a perf deferral a failure. A deferral is reported and is never releasable."
	)
	local tiers = SELECTED[tier]
	for _, entry in entries do
		if tiers == nil or table.find(tiers, entry.tier) then
			local replaces = if entry.replaces then ` replaces {table.concat(entry.replaces, ", ")}` else ""
			print(`  {entry.id} [{entry.environment}; tier {entry.tier}]{replaces}: {table.concat(entry.argv, " ")}`)
		end
	end
end

local function main()
	local tier = "full"
	local rerun: string? = nil
	local referenceHost = false
	local explained = false
	local index = 1
	while index <= #process.args do
		local flag = process.args[index]
		if table.find(TIERS, flag) then
			tier = flag
		elseif flag == "--rerun" then
			index += 1
			rerun = assert(process.args[index], "--rerun needs a producer id")
		elseif flag == "--reference-host" then
			referenceHost = true
		elseif flag == "--explain" then
			explained = true
		else
			print(
				"usage: tools/verify.sh [affected|fast|full|release] [--rerun PRODUCER] [--reference-host] [--explain]"
			)
			process.exit(2)
		end
		index += 1
	end
	local entries = catalog(tier)
	local gate = define(entries, referenceHost)
	fs.writeDir(ARTIFACTS)
	print(`Facet verification gate: {tier}; {#entries} producers declared.`)
	print(
		"Historical parity: NOT ESTABLISHED. See docs/guide/20-verification-parity.md for the producer and assertion comparison with main."
	)
	if explained then
		explain(entries, tier)
	end
	local outcome = Lune.gate.run(gate, {
		directory = ARTIFACTS .. "/gate",
		build = build(),
		selection = selection(tier, rerun),
		environment = {
			tier = tier,
			referenceHost = tostring(referenceHost),
			historicalParity = "not-established",
		},
		observe = function(record: Verify.GateRecord)
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
	print(Verify.formatGate(outcome))
	local status, code = conclusion(outcome, tier, rerun)
	fs.writeFile(`{ARTIFACTS}/report.json`, serde.encode("json", outcome, true))
	if tierComplete(outcome, tier, rerun) then
		fs.writeFile(`artifacts/verify/latest-{tier}.json`, serde.encode("json", outcome, true))
	end
	print(`facet {tier}: {status}; {ARTIFACTS}/report.json`)
	process.exit(code)
end

return {
	catalog = catalog,
	define = define,
	selection = selection,
	conclusion = conclusion,
	tierComplete = tierComplete,
	main = main,
}
