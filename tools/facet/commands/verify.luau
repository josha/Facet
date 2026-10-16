--!strict

local Cli = require("../lib/cli")
local Case = require("../lib/case")
local Encoding = require("../lib/encoding")
local Files = require("../lib/files")
local Look = require("../lib/look")
local Run = require("../lib/run")

local USAGE = [[usage: lute run tools/facet verify [paths...] [--project FILE] [--static]
    [--device ID]... [--tap TEXT]... [--wait SECONDS] [--out DIR]
    [--dump FILE --device ID] [--verbose]

Runs strict types, usage lint and a Rojo build. One Studio session supplies
both the audit and preview screenshots on all five devices. Prints only
problems and screenshot paths. --static skips Studio and reports that limit.
--dump audits saved evidence instead of starting Studio; it needs one device.
UTF-8 BOMs in application Luau files are removed before engine tools read them.
The exit code is 1 for a failed check, missed tap, missing capture or high or
medium audit finding. Repeated findings are grouped; at most 12 unique findings
are printed. report.txt in --out keeps every finding. --verbose prints them all.
Saved evidence does not prove current live behavior.]]

local function compact(lines: { string }): { string }
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

local function summarize(screens: { Look.Screen }): ({ string }, boolean)
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

local function run(invocation: Cli.Invocation): number
	if
		Cli.unknownFlags(invocation, { "project", "static", "device", "tap", "wait", "out", "dump", "verbose" }) ~= nil
	then
		print(USAGE)
		return 2
	end
	local devices = invocation.repeated.device or Look.DEVICES
	for _, device in devices do
		if table.find(Look.DEVICES, device) == nil then
			print("problem: unknown device " .. device .. "; use " .. table.concat(Look.DEVICES, ", "))
			return 2
		end
	end
	local saved = Cli.flag(invocation, "dump")
	if saved ~= nil and (#devices ~= 1 or Cli.switch(invocation, "static")) then
		print("problem: --dump needs exactly one --device and cannot use --static")
		return 2
	end
	local project = Cli.flag(invocation, "project") or "default.project.json"
	local paths: { string } = if #invocation.positional > 0 then invocation.positional else { "src/client" }
	Encoding.normalize({ "src" })
	local argv = { Run.lute(), "run", "tools/facet", "lint", "--types", "--project", project }
	for _, path in paths do
		table.insert(argv, path)
	end
	local lint = Run.capture(argv, { timeout = 300 })
	local failed = not lint.ok
	for _, line in Files.lines(lint.stdout .. "\n" .. lint.stderr) do
		if line ~= "" and string.sub(line, 1, 11) ~= "facet lint:" then
			print(line)
		end
	end
	if not lint.ok and lint.stdout == "" and lint.stderr == "" then
		print("problem: lint failed with exit code " .. tostring(lint.code))
	end
	local out = Cli.flag(invocation, "out") or "artifacts/facet-verify"
	Files.makeDirectory(out)
	local built = Run.capture({ "rojo", "build", project, "-o", Files.join(out, "game.rbxlx") }, { timeout = 120 })
	if not built.ok then
		print("problem: Rojo build failed: " .. built.stdout .. built.stderr)
		failed = true
	end
	if failed then
		return 1
	end
	if Cli.switch(invocation, "static") then
		print("problem: live audit and screenshots not checked (--static)")
		return 0
	end
	local screens: { Look.Screen }
	if saved ~= nil then
		print("problem: saved evidence only; current live behavior not checked")
		screens = { { device = devices[1], label = saved, dump = saved } }
	else
		local result = Look.run({
			project = project,
			devices = devices,
			steps = Look.parseSteps(invocation.repeated.tap or {}, tonumber(Cli.flag(invocation, "wait") or "")),
			out = Files.join(out, "live"),
		})
		if result.problem ~= nil then
			print("problem: " .. result.problem)
			return 1
		end
		screens = result.screens
		for _, screen in screens do
			if screen.png == nil then
				screen.problem = (screen.problem or "") .. " no screenshot"
			end
		end
	end
	local lines, problems = summarize(screens)
	Files.write(Files.join(out, "report.txt"), table.concat(lines, "\n") .. "\n")
	if not Cli.switch(invocation, "verbose") then
		lines = compact(lines)
	end
	if #lines > 0 then
		print(table.concat(lines, "\n"))
	end
	return if problems then 1 else 0
end

return {
	name = "verify",
	summary = "Run types, lint, build, audit and screenshots together.",
	usage = USAGE,
	values = { "project", "device", "tap", "wait", "out", "dump" },
	cases = function(): { Case.Case }
		return {
			{
				name = "duplicate findings keep their count and distinct findings stay available in the report",
				run = function(): string?
					local lines = {
						"screenshot a.png",
						"console shop: medium [rule] App.Control: detail",
						"console offer: medium [rule] App.Control: detail",
					}
					for index = 1, 13 do
						table.insert(lines, `desktop start: high [rule] App.Control{index}: detail`)
					end
					local result = compact(lines)
					return Case.first(
						Case.equal(#result, 14, "bounded output"),
						Case.equal(
							result[2],
							"console shop (+1 screens): medium [rule] App.Control: detail",
							"grouped finding"
						),
						Case.equal(#lines, 16, "full report preserved")
					)
				end,
			},
		}
	end,
	run = run,
} :: Cli.Command
