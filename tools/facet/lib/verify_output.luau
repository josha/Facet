--!strict

local Files = require("./files")
local Look = require("./look")
local Path = require("@std/path")

local Output = {}

export type Filter = { device: string?, rule: string?, step: string?, page: number? }

local function finding(line: string): (string?, string?, string?, string?)
	local device, step, body = string.match(line, "^(%S+) ([^:]+): (.+)$")
	if device == nil or step == nil or body == nil then
		return nil
	end
	local rule = string.match(body, "^%a+ %[(.-)%]")
		or (if string.sub(body, 1, 8) == "problem:" then "problem" else nil)
	return device, step, rule, body
end

function Output.query(lines: { string }, filter: Filter): { string }
	local matches: { string } = {}
	for _, line in lines do
		local device, step, rule, body = finding(line)
		if
			device
			and step
			and rule
			and body
			and (filter.device == nil or filter.device == device)
			and (filter.rule == nil or filter.rule == rule)
			and (filter.step == nil or filter.step == step)
		then
			table.insert(matches, device .. "/" .. step .. ": " .. body)
		end
	end
	local pages: { { string } } = { {} }
	local bytes = 0
	for _, line in matches do
		local short = if #line > 700 then string.sub(line, 1, 680) .. " [shortened]" else line
		if bytes + #short + 1 > 3500 or #pages[#pages] >= 20 then
			table.insert(pages, {})
			bytes = 0
		end
		table.insert(pages[#pages], short)
		bytes += #short + 1
	end
	local page = filter.page or 1
	local output =
		{ `report: {#matches} matching findings; page {page}/{#pages}. Capture: live/captures/<device>/<step>.png` }
	local selected: { string } = pages[page] or {}
	for _, line in selected do
		table.insert(output, line)
	end
	if page < #pages then
		table.insert(output, `More matching findings: repeat this query with --page {page + 1}.`)
	end
	return output
end

function Output.queries(lines: { string }, out: string): { string }
	local seen: { [string]: boolean } = {}
	local result: { string } = {}
	for _, line in lines do
		local device, _, rule = finding(line)
		if device and rule then
			local key = device .. "\0" .. rule
			if not seen[key] then
				seen[key] = true
				table.insert(
					result,
					`lute run tools/facet verify --report --out "{out}" --device {device} --rule {rule}`
				)
			end
		end
	end
	return result
end

function Output.estimate(devices: number, taps: number, wait: number?): number
	return math.ceil(15 + devices * (5 + (taps + 1) + taps * (wait or 0.3)))
end

function Output.captures(screens: { Look.Screen }): { string }
	local order: { string } = {}
	local counts: { [string]: number } = {}
	local directories: { [string]: string } = {}
	for _, screen in screens do
		if counts[screen.device] == nil then
			table.insert(order, screen.device)
			counts[screen.device] = 0
		end
		if screen.png ~= nil then
			counts[screen.device] += 1
			directories[screen.device] =
				Files.normalize(Path.format(Path.relative(Files.cwd(), Files.absolute(Files.parent(screen.png)))))
		end
	end
	local lines: { string } = {}
	for _, device in order do
		table.insert(
			lines,
			`{device}: {counts[device]} captures` .. (if directories[device] then ` in {directories[device]}` else "")
		)
	end
	return lines
end

function Output.compact(lines: { string }): { string }
	local output: { string } = {}
	local order: { string } = {}
	local groups: { [string]: { string } } = {}
	for _, line in lines do
		local label, finding = string.match(line, "^(.-): (%a+ %[[^%]]+%].*)$")
		if label and finding then
			if groups[finding] == nil then
				groups[finding] = {}
				table.insert(order, finding)
			end
			table.insert(groups[finding], label)
		else
			table.insert(output, line)
		end
	end
	for index, finding in order do
		if index > 12 then
			table.insert(output, `{#order - 12} more unique findings; use the report queries below.`)
			break
		end
		local labels = groups[finding]
		table.insert(output, labels[1] .. (if #labels > 1 then ` (+{#labels - 1} screens)` else "") .. ": " .. finding)
	end
	return output
end

function Output.summarize(screens: { Look.Screen }): ({ string }, boolean)
	local lines: { string } = {}
	local failed = #screens == 0
	if failed then
		table.insert(lines, "problem: no screens captured")
	end
	for _, screen in screens do
		local label = screen.device .. " " .. screen.label
		if screen.png ~= nil then
			table.insert(lines, "screenshot " .. screen.png)
		end
		if screen.problem ~= nil or (screen.tap ~= nil and screen.found ~= true) then
			failed = true
			table.insert(lines, label .. ": problem: " .. (screen.problem or "tap did not find its control"))
			continue
		end
		if screen.dump == nil then
			failed = true
			table.insert(lines, label .. ": problem: no interface dump")
		else
			local loaded, dump = pcall(Look.load, screen.dump)
			if not loaded then
				failed = true
				table.insert(lines, label .. ": problem: " .. tostring(dump))
			else
				for _, finding in Look.audit(dump, screen.device).violations do
					if finding.severity == "high" or finding.severity == "medium" then
						failed = true
						table.insert(
							lines,
							`{label}: {finding.severity} [{finding.rule}] {finding.path}: {finding.detail}`
						)
					end
				end
			end
		end
	end
	return lines, failed
end

return Output
