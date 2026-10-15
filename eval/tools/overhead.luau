--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local AgentEval = require("../../tools/vendor/verify/src/agent-eval")

local binding = AgentEval.lute

local USAGE = "usage: lute run eval/tools/overhead.luau <evidence directory> [--treatment ARM] [--baseline ARM]"

type Metric = { id: string, label: string }

local METRICS: { Metric } = {
	{ id = "mountSeconds", label = "Mount s" },
	{ id = "idleFrameP50Ms", label = "Idle frame p50 ms" },
	{ id = "activeFrameP50Ms", label = "Active frame p50 ms" },
	{ id = "activeFrameP95Ms", label = "Active frame p95 ms" },
	{ id = "baseGuiObjects", label = "GuiObjects" },
	{ id = "baseComponents", label = "UI components" },
	{ id = "peakGuiObjects", label = "Peak GuiObjects" },
	{ id = "instanceDelta", label = "Instances left" },
	{ id = "guiObjectDelta", label = "GuiObjects left" },
	{ id = "heapDeltaKb", label = "Heap delta KB" },
}

type Run = { task: string, arm: string, scores: { [string]: number }, passed: boolean }

local function field(value: unknown, key: string): unknown
	return if type(value) == "table" then (value :: { [string]: unknown })[key] else nil
end

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local middle = (#sorted + 1) / 2
	return (sorted[math.floor(middle)] + sorted[math.ceil(middle)]) / 2
end

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

local function load(evidence: string): { Run }
	local runs: { Run } = {}
	local root = evidence .. "/runs"
	for _, task in list(root) do
		for _, arm in list(root .. "/" .. task) do
			for _, agent in list(("%s/%s/%s"):format(root, task, arm)) do
				for _, seed in list(("%s/%s/%s/%s"):format(root, task, arm, agent)) do
					local path = ("%s/%s/%s/%s/%s/result.json"):format(root, task, arm, agent, seed)
					if fs.exists(path) then
						local result = binding.decode(fs.readFileToString(path))
						local scores: { [string]: number } = {}
						local raw = field(result, "scores")
						if type(raw) == "table" then
							for key, value in raw :: { [string]: unknown } do
								if type(value) == "number" then
									scores[key] = value
								end
							end
						end
						table.insert(
							runs,
							{ task = task, arm = arm, scores = scores, passed = field(result, "passed") == true }
						)
					end
				end
			end
		end
	end
	return runs
end

local function format(value: number?): string
	if value == nil then
		return "-"
	end
	local number = value :: number
	return if math.abs(number) >= 100 then ("%.0f"):format(number) else ("%.2f"):format(number)
end

local function main(): number
	local evidence: string? = nil
	local treatment, baseline = "facet", "plain"
	local index = 2
	while index <= #process.args do
		local word = process.args[index]
		if word == "--treatment" then
			treatment = process.args[index + 1]
			index += 1
		elseif word == "--baseline" then
			baseline = process.args[index + 1]
			index += 1
		else
			evidence = word
		end
		index += 1
	end
	if evidence == nil then
		print(USAGE)
		return 2
	end
	local runs = load(binding.absolute(evidence :: string))
	local tasks: { string } = {}
	local devices: { [string]: boolean } = {}
	local byKey: { [string]: { number } } = {}
	for _, run in runs do
		if table.find(tasks, run.task) == nil then
			table.insert(tasks, run.task)
		end
		for key, value in run.scores do
			local device, metric = string.match(key, "^play%.perf%.([%w%-]+)%.([%w]+)$")
			if device ~= nil and metric ~= nil then
				devices[device :: string] = true
				local slot = ("%s|%s|%s|%s"):format(run.task, run.arm, device :: string, metric :: string)
				byKey[slot] = byKey[slot] or {}
				table.insert(byKey[slot], value)
			end
		end
	end
	table.sort(tasks)
	local deviceList: { string } = {}
	for device in devices do
		table.insert(deviceList, device)
	end
	table.sort(deviceList)
	local lines: { string } = {
		"# Interface cost: " .. treatment .. " compared with " .. baseline,
		"",
		("Exploratory measurements of %s compared with %s. Run eval/tools/report.luau for confirmed limits, intervals and completeness checks. Instances are reported, not gated."):format(
			treatment,
			baseline
		),
		"",
		("| Task | Device | Metric | %s | %s | Ratio |"):format(baseline, treatment),
		"| --- | --- | --- | ---: | ---: | ---: |",
	}
	local ratios: { [string]: { number } } = {}
	for _, task in tasks do
		for _, device in deviceList do
			for _, metric in METRICS do
				local base = median(byKey[("%s|%s|%s|%s"):format(task, baseline, device, metric.id)] or {})
				local treated = median(byKey[("%s|%s|%s|%s"):format(task, treatment, device, metric.id)] or {})
				if base == nil and treated == nil then
					continue
				end
				local ratio: number? = nil
				if base ~= nil and treated ~= nil and (base :: number) > 0 then
					ratio = (treated :: number) / (base :: number)
					ratios[metric.id] = ratios[metric.id] or {}
					table.insert(ratios[metric.id], ratio :: number)
				end
				table.insert(
					lines,
					("| `%s` | %s | %s | %s | %s | %s |"):format(
						task,
						device,
						metric.label,
						format(base),
						format(treated),
						if ratio ~= nil then ("%.2f"):format(ratio :: number) else "-"
					)
				)
			end
		end
	end
	table.insert(lines, "")
	table.insert(lines, "| Metric | Median ratio | Pairs |")
	table.insert(lines, "| --- | ---: | ---: |")
	for _, metric in METRICS do
		local values = ratios[metric.id] or {}
		local middle = median(values)
		table.insert(
			lines,
			("| %s | %s | %d |"):format(
				metric.label,
				if middle ~= nil then ("%.2f"):format(middle :: number) else "-",
				#values
			)
		)
	end
	print(table.concat(lines, "\n"))
	return 0
end

process.exit(main())
