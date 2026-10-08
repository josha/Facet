--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Gate = require("../vendor/verify/src/gate")
local Lune = require("../vendor/verify/src/lune")
local Verify = require("../vendor/verify/src/core")

local TIERS = {
	affected = { "fast" },
	fast = { "fast" },
	full = { "fast", "full" },
	release = {},
}
local DEFERRAL = {
	studio = "the live Studio evidence is not recorded on this host",
	device = "the physical device evidence is not recorded on this host",
	perf = "a host timing budget failed away from the reference host",
}
local DIRECTORY = "artifacts/verify/native/gate"
local CATALOG = "tools/lune/producers.json"

local function tests(id: string, names: { string }): Gate.ProducerDraft
	local locators = {}
	for _, name in names do
		assert(fs.isFile(`tests/{name}.spec.luau`), "unknown spec: " .. name)
		table.insert(locators, `tests/{name}.spec.luau`)
	end
	return {
		id = id,
		kind = "tests",
		tier = "fast",
		worker = "tests/worker.luau",
		locators = locators,
		isolate = true,
		workers = 4,
		deadlineSeconds = 3600,
		sourceDeadlineSeconds = 600,
	}
end

export type Entry = {
	id: string,
	tier: string,
	environment: string?,
	kind: string?,
	run: string?,
	plan: string?,
	after: { string }?,
	replaces: { string }?,
	producer: Gate.ProducerDraft?,
	deadlineSeconds: number?,
}

local function define(entries: { Entry }, referenceHost: boolean, id: string?): Gate.Draft
	local producers: { Gate.ProducerDraft } = {}
	local deferrals: { [string]: string } = {}
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
			local names = {}
			for _, unit in serde.decode("json", fs.readFile(entry.plan)).units do
				assert(unit.locator == `tests/{unit.id}.spec.luau`, "plan locator differs from its source: " .. unit.id)
				table.insert(names, unit.id)
			end
			producer = tests(entry.id, names)
		else
			producer = {
				id = entry.id,
				kind = (entry.kind or "command") :: any,
				argv = string.split(assert(entry.run), " "),
				deadlineSeconds = entry.deadlineSeconds,
			}
		end
		if deferrable and producer.kind ~= "tests" then
			producer.exit = { [2] = "deferred" :: Gate.ExitClass }
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
	return define(serde.decode("json", fs.readFile(CATALOG)).producers, referenceHost)
end

local function releasable(code: number, tier: string, outcome: Gate.Outcome?): number
	if code == 0 and tier == "release" and outcome ~= nil and not outcome.acceptance.releasable then
		print("gate: the release tier is not releasable with a deferral or a narrowed run")
		return 1
	end
	return code
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

local function main()
	local arguments = table.clone(process.args)
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
		elseif focused and string.sub(argument, 1, 2) ~= "--" then
			table.insert(names, argument)
		else
			table.insert(flags, argument)
		end
		index += 1
	end
	assert(TIERS[tier], "unknown tier: " .. tostring(tier))
	for _, name in if focused and tier ~= "release" then { "fast" } else TIERS[tier] do
		table.insert(flags, "--tier")
		table.insert(flags, name)
	end
	local gate: Gate.Draft = if focused
		then { id = "facet-specs", producers = { tests("specs", names) } }
		else draft(referenceHost)
	local options = {
		directory = if focused then DIRECTORY .. "-specs" else DIRECTORY,
		build = build(),
		environment = {
			tier = tier,
			referenceHost = tostring(referenceHost),
		},
	}
	print(`Facet verification gate: {tier}.`)
	local code = Lune.gate.cli(gate, flags, {
		options = options,
		usage = "usage: lune run tools/lune/verify [affected|fast|full|release] [--reference-host] [--only PRODUCER]... [--case ID]... [--name TEXT] [--rerun] [--explain ID] [--list]\n       lune run tools/lune/verify spec SPEC... [--tier release]",
	})
	code = releasable(code, tier, (Lune.gate.last(Gate.define(gate), options)))
	process.exit(code)
end

return {
	define = define,
	draft = draft,
	tests = tests,
	tiers = TIERS,
	releasable = releasable,
	build = build,
	main = main,
}
