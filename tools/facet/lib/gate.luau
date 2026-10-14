--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Gate = require("../../vendor/verify/src/gate")
local Lute = require("../../vendor/verify/src/lute")
local Verify = require("../../vendor/verify/src/core")
local Model = require("./model")

export type Kind = "tests" | "command" | "build" | "native"

export type Entry = {
	id: string,
	tier: string,
	environment: string?,
	kind: Kind?,
	run: string?,
	plan: string?,
	requires: string?,
	after: { string }?,
	replaces: { string }?,
	producer: Gate.ProducerDraft?,
	deadlineSeconds: number?,
}

type Unit = { id: string, locator: string, requires: { string }? }
type Plan = { units: { Unit } }
type Catalog = { producers: { Entry } }

local TIERS: { [string]: { string } } = {
	affected = { "fast" },
	fast = { "fast" },
	full = { "fast", "full" },
	release = {},
}
local DEFERRAL: { [string]: string } = {
	studio = "the live Studio evidence is not recorded on this host",
	device = "the physical device evidence is not recorded on this host",
	perf = "a host timing budget failed away from the reference host",
}
local DIRECTORY = "artifacts/verify/native/gate"
local CATALOG = "tools/facet/producers.json"
local PLAN = "tests/plan.json"
local ENGINE_WORKER = "tests/worker.luau"
local TOOL_WORKER = "tests/lute/worker.luau"
local TOOL_REQUIREMENT = "lute"

local USAGE = table.concat({
	"usage: lute run tools/facet gate [affected|fast|full|release] [--reference-host] [--only PRODUCER]... [--case ID]... [--file SPEC]... [--name TEXT] [--rerun] [--explain ID] [--list]",
	"       lute run tools/facet gate spec SPEC... [--tier release] [--case ID]... [--name TEXT]",
}, "\n")

local function decode<T>(path: string): T
	return (Lute.parse(fs.readFileToString(path)) :: unknown) :: T
end

local function toolUnits(): { [string]: boolean }
	local tools: { [string]: boolean } = {}
	for _, unit in decode(PLAN).units :: { Unit } do
		tools[unit.id] = table.find(unit.requires or {}, TOOL_REQUIREMENT) ~= nil
	end
	return tools
end

local function tests(id: string, names: { string }): Gate.ProducerDraft
	local locators: { string } = {}
	local tools = toolUnits()
	local worker: string? = nil
	for _, name in names do
		local locator = `tests/{name}.spec.luau`
		assert(fs.exists(locator), "unknown spec: " .. name)
		table.insert(locators, locator)
		local chosen = if tools[name] then TOOL_WORKER else ENGINE_WORKER
		assert(worker == nil or worker == chosen, "a run cannot mix engine specs and tool specs: " .. name)
		worker = chosen
	end
	return {
		id = id,
		kind = "tests",
		tier = "fast",
		worker = worker or ENGINE_WORKER,
		locators = locators,
		isolate = true,
		workers = 4,
		deadlineSeconds = 3600,
		sourceDeadlineSeconds = 600,
	}
end

local function requiresAny(unit: Unit, labels: { [string]: boolean }): boolean
	local requires: { string } = unit.requires or {}
	for _, label in requires do
		if labels[label] then
			return true
		end
	end
	return false
end

local function planned(entry: Entry, claimed: { [string]: boolean }): { string }
	local names: { string } = {}
	local wanted = entry.requires
	for _, unit in decode(entry.plan :: string).units :: { Unit } do
		assert(unit.locator == `tests/{unit.id}.spec.luau`, "plan locator differs from its source: " .. unit.id)
		local selected = if wanted ~= nil
			then table.find(unit.requires or {}, wanted) ~= nil
			else not requiresAny(unit, claimed)
		if selected then
			table.insert(names, unit.id)
		end
	end
	return names
end

local function define(entries: { Entry }, referenceHost: boolean, id: string?): Gate.Draft
	local producers: { Gate.ProducerDraft } = {}
	local deferrals: { [string]: string } = {}
	local claimed: { [string]: boolean } = {}
	for _, entry in entries do
		if entry.plan and entry.requires then
			claimed[entry.requires] = true
		end
	end
	for _, entry in entries do
		local environment = entry.environment or "deterministic"
		local reason = DEFERRAL[environment]
		local deferrable = reason ~= nil and not (environment == "perf" and referenceHost)
		if deferrable then
			deferrals[entry.id] = reason
		end
		local producer: Gate.ProducerDraft
		if entry.producer then
			producer = entry.producer
		elseif entry.plan then
			producer = tests(entry.id, planned(entry, claimed))
		else
			producer = {
				id = entry.id,
				kind = entry.kind or "command",
				argv = string.split(assert(entry.run, "a producer needs a command: " .. entry.id), " "),
				deadlineSeconds = entry.deadlineSeconds,
			}
		end
		if deferrable and producer.kind ~= "tests" then
			local exit: { [number]: Gate.ExitClass } = { [2] = "deferred" }
			producer.exit = exit
		end
		producer.tier = entry.tier
		producer.tags = { environment }
		producer.after = entry.after
		producer.why = if entry.replaces then "replaces " .. table.concat(entry.replaces, ", ") else nil
		table.insert(producers, producer)
	end
	return {
		id = id or "facet",
		producers = producers,
		policy = { concurrency = 1, commandDeadlineSeconds = 1800, deferrals = deferrals },
	}
end

local function draft(referenceHost: boolean): Gate.Draft
	local catalog: Catalog = decode(CATALOG)
	return define(catalog.producers, referenceHost)
end

local function releasable(code: number, tier: string, outcome: Gate.Outcome?): number
	if code == 0 and tier == "release" and outcome ~= nil and not outcome.acceptance.releasable then
		print("gate: the release tier is not releasable with a deferral or a narrowed run")
		return 1
	end
	return code
end

local function output(argv: { string }): string
	local result = process.run(argv)
	return if result.ok then (string.gsub(result.stdout, "%s+$", "")) else ""
end

local function build(): Verify.EvidenceBuild
	return {
		commit = output({ "git", "rev-parse", "HEAD" }),
		tree = output({ "git", "rev-parse", "HEAD^{tree}" }),
		clean = output({ "git", "status", "--porcelain" }) == "",
		digest = Model.sourceHash("."),
	}
end

local function main(arguments: { string }): number
	local focused = arguments[1] == "spec"
	local tier = "full"
	local referenceHost = false
	local names: { string } = {}
	local flags: { string } = {}
	local index = if focused then 2 else 1
	while index <= #arguments do
		local argument = arguments[index]
		if TIERS[argument] and #flags == 0 and #names == 0 then
			tier = argument
		elseif argument == "--tier" and focused then
			index += 1
			tier = arguments[index]
		elseif argument == "--reference-host" then
			referenceHost = true
		elseif focused and string.sub(argument, 1, 2) ~= "--" and #flags == 0 then
			table.insert(names, argument)
		else
			table.insert(flags, argument)
		end
		index += 1
	end
	if TIERS[tier] == nil then
		print("gate: unknown tier " .. tostring(tier))
		print(USAGE)
		return 2
	end
	if focused and #names == 0 then
		print(USAGE)
		return 2
	end
	local selectedTiers: { string } = if focused and tier ~= "release" then { "fast" } else TIERS[tier]
	for _, name in selectedTiers do
		table.insert(flags, "--tier")
		table.insert(flags, name)
	end
	local gate: Gate.Draft = if focused
		then { id = "facet-specs", producers = { tests("specs", names) } }
		else draft(referenceHost)
	local options: Lute.GateOptions = {
		directory = if focused then DIRECTORY .. "-specs" else DIRECTORY,
		build = build(),
		environment = {
			tier = tier,
			referenceHost = tostring(referenceHost),
		},
	}
	print(`Facet verification gate: {tier}.`)
	local code = Lute.gate.cli(gate, flags, { options = options, usage = USAGE })
	return releasable(code, tier, (Lute.gate.last(Gate.define(gate), options)))
end

return table.freeze({
	CATALOG = CATALOG,
	USAGE = USAGE,
	tiers = TIERS,
	define = define,
	draft = draft,
	tests = tests,
	releasable = releasable,
	build = build,

	main = main,
})
