--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local AgentEval = require("../../tools/vendor/verify/src/agent-eval")
local UsageLint = require("../../tools/facet/lib/usage_lint")

local binding = AgentEval.lute

local USAGE = [[usage: lute run eval/tools/coverage.luau <evidence directory>... [--arm ARM]

Reads the interface sources of each finished run of ARM (default facet), counts
the Facet controls and helpers that they use, writes usage.json next to the
run's result.json, and prints the controls of each run, the number of runs that
use each control, and the controls that no run uses.]]

type Run = { label: string, counts: { [string]: number } }

local function list(path: string): { string }
	local names: { string } = {}
	if fs.exists(path) then
		for _, entry in fs.listDirectory(path) do
			if entry.type == "dir" then
				table.insert(names, entry.name)
			end
		end
	end
	table.sort(names)
	return names
end

local function sources(directory: string, into: { { file: string, source: string } })
	for _, entry in fs.listDirectory(directory) do
		local path = directory .. "/" .. entry.name
		if entry.type == "dir" then
			sources(path, into)
		elseif string.sub(entry.name, -5) == ".luau" or string.sub(entry.name, -4) == ".lua" then
			table.insert(into, { file = path, source = fs.readFileToString(path) })
		end
	end
end

local function load(evidence: string, arm: string): { Run }
	local runs: { Run } = {}
	local root = evidence .. "/runs"
	for _, task in list(root) do
		for _, agent in list(("%s/%s/%s"):format(root, task, arm)) do
			for _, seed in list(("%s/%s/%s/%s"):format(root, task, arm, agent)) do
				local run = ("%s/%s/%s/%s/%s"):format(root, task, arm, agent, seed)
				local client = run .. "/workspace/src/client"
				if fs.exists(run .. "/result.json") and fs.exists(client) then
					local found: { { file: string, source: string } } = {}
					sources(client, found)
					local counts = UsageLint.usage(found)
					fs.writeStringToFile(run .. "/usage.json", binding.encode(counts) .. "\n")
					table.insert(runs, { label = ("%s %s %s"):format(task, agent, seed), counts = counts })
				end
			end
		end
	end
	return runs
end

local function main(): number
	local evidence: { string } = {}
	local arm = "facet"
	local index = 2
	while index <= #process.args do
		local word = process.args[index]
		if word == "--arm" then
			arm = process.args[index + 1] or arm
			index += 1
		else
			table.insert(evidence, word)
		end
		index += 1
	end
	if #evidence == 0 then
		print(USAGE)
		return 2
	end
	local runs: { Run } = {}
	for _, path in evidence do
		for _, run in load(binding.absolute(path), arm) do
			run.label = ("%s: %s"):format(path, run.label)
			table.insert(runs, run)
		end
	end
	local known = UsageLint.controls(fs.readFileToString("src/ui/control_types.luau"))
	local reach: { [string]: number } = {}
	local lines: { string } = {
		("# Control coverage of the %s arm"):format(arm),
		"",
		"| Run | Controls and helpers (count) |",
		"| --- | --- |",
	}
	for _, run in runs do
		local names: { string } = {}
		for name in run.counts do
			table.insert(names, name)
			reach[name] = (reach[name] or 0) + 1
		end
		table.sort(names)
		local parts: { string } = {}
		for _, name in names do
			table.insert(parts, ("`%s` %d"):format(name, run.counts[name]))
		end
		table.insert(lines, ("| %s | %s |"):format(run.label, table.concat(parts, ", ")))
	end
	local used: { string } = {}
	for name in reach do
		table.insert(used, name)
	end
	table.sort(used, function(left: string, right: string): boolean
		if reach[left] ~= reach[right] then
			return reach[left] > reach[right]
		end
		return left < right
	end)
	table.insert(lines, "")
	table.insert(lines, ("| Control or helper | Runs that use it (of %d) |"):format(#runs))
	table.insert(lines, "| --- | ---: |")
	for _, name in used do
		table.insert(lines, ("| `%s` | %d |"):format(name, reach[name]))
	end
	local unused: { string } = {}
	for _, name in known do
		if reach[name] == nil then
			table.insert(unused, ("`%s`"):format(name))
		end
	end
	table.insert(lines, "")
	table.insert(
		lines,
		("UI members that no run uses (%d of %d): %s"):format(#unused, #known, table.concat(unused, ", "))
	)
	print(table.concat(lines, "\n"))
	return 0
end

process.exit(main())
