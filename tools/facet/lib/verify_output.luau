--!strict

local Files = require("./files")
local Look = require("./look")
local Path = require("@std/path")

local Output = {}

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
			table.insert(output, `{#order - 12} more unique findings; read report.txt in --out.`)
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
