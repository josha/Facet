--!strict

local Cli = require("../lib/cli")
local Case = require("../lib/case")
local Encoding = require("../lib/encoding")
local Files = require("../lib/files")
local Look = require("../lib/look")
local Run = require("../lib/run")
local Output = require("../lib/verify_output")
local Task = require("@std/task")
local Json = require("../lib/json")

local USAGE = [=[usage: lute run tools/facet verify [paths...] [--project FILE] [--static]
    [--device ID]... [--tap TEXT]... [--wait SECONDS] [--out DIR]
    [--dump FILE --device ID] [--verbose]
    [--report [--device ID] [--rule ID] [--step ID] [--page N]]

Runs strict types, usage lint and a Rojo build. One Studio session supplies
both the audit and preview screenshots on all five devices. Prints an expected
duration, capture directories, findings and verdict. --static skips Studio.
--dump audits saved evidence instead of starting Studio; it needs one device.
UTF-8 BOMs in application Luau files are removed before engine tools read them.
The exit code is 1 for a failed check, missed tap, missing capture or high or
medium audit finding. Repeated findings are grouped; at most 12 unique findings
are printed. --report queries saved findings, bounded to 4096 bytes per page.
Use --device, --rule and --step to select findings. --verbose prints them all.
Saved evidence does not prove current live behavior.]=]

local function run(invocation: Cli.Invocation): number
	local started = os.clock()
	local timings: { [string]: number } = {}
	if
		Cli.unknownFlags(
			invocation,
			{ "project", "static", "device", "tap", "wait", "out", "dump", "verbose", "report", "rule", "step", "page" }
		) ~= nil
	then
		print(USAGE)
		return 2
	end
	local out = Cli.flag(invocation, "out") or "artifacts/facet-verify"
	if Cli.switch(invocation, "report") then
		local file = Files.join(out, "report.txt")
		local page = tonumber(Cli.flag(invocation, "page") or "1")
		if page == nil or page < 1 or page % 1 ~= 0 or page == math.huge then
			print("problem: --page must be a positive integer")
			return 2
		end
		if not Files.isFile(file) then
			print("problem: no saved report at " .. file)
			return 1
		end
		print(table.concat(
			Output.query(Files.lines(Files.text(file)), {
				device = Cli.flag(invocation, "device"),
				rule = Cli.flag(invocation, "rule"),
				step = Cli.flag(invocation, "step"),
				page = page,
			}),
			"\n"
		))
		return 0
	end
	if Cli.switch(invocation, "rule") or Cli.switch(invocation, "step") or Cli.switch(invocation, "page") then
		print("problem: --rule, --step and --page need --report")
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
	local wait = tonumber(Cli.flag(invocation, "wait") or "")
	if wait ~= nil and (wait < 0 or wait >= math.huge) then
		print("problem: --wait must be finite and nonnegative")
		return 2
	end
	if saved == nil and not Cli.switch(invocation, "static") then
		print(
			`verify: expected duration about {Output.estimate(#devices, #(invocation.repeated.tap or {}), wait)} seconds; wait for the verdict.`
		)
	end
	local paths: { string } = if #invocation.positional > 0 then invocation.positional else { "src/client" }
	Encoding.normalize({ "src" })
	local argv = { Run.lute(), "run", "tools/facet", "lint", "--types", "--project", project }
	if not Cli.switch(invocation, "static") and not Cli.switch(invocation, "verbose") then
		table.insert(argv, "--warning-counts")
	end
	if Cli.switch(invocation, "verbose") then
		table.insert(argv, "--verbose")
	end
	for _, path in paths do
		table.insert(argv, path)
	end
	local checked: Run.Result? = nil
	Task.spawn(function()
		local lintStarted = os.clock()
		checked = Run.capture(argv, { timeout = 300 })
		timings.lint = os.clock() - lintStarted
	end)
	local function lintFailed(): boolean
		while checked == nil do
			Task.wait(0.01)
		end
		local lint = checked :: Run.Result
		for _, line in Files.lines(lint.stdout .. "\n" .. lint.stderr) do
			if line ~= "" and string.sub(line, 1, 11) ~= "facet lint:" then
				print(line)
			end
		end
		if not lint.ok and lint.stdout == "" and lint.stderr == "" then
			print("problem: lint failed with exit code " .. tostring(lint.code))
		end
		return not lint.ok
	end
	Files.makeDirectory(out)
	local buildStarted = os.clock()
	local built = Run.capture({ "rojo", "build", project, "-o", Files.join(out, "game.rbxlx") }, { timeout = 120 })
	timings.build = os.clock() - buildStarted
	if not built.ok then
		print("problem: Rojo build failed: " .. built.stdout .. built.stderr)
		lintFailed()
		print("verify: FAIL")
		return 1
	end
	if Cli.switch(invocation, "static") then
		local failed = lintFailed()
		print("problem: live audit and screenshots not checked (--static)")
		print("verify: " .. (if failed then "FAIL" else "PASS"))
		return if failed then 1 else 0
	end
	local screens: { Look.Screen }
	if saved ~= nil then
		print("problem: saved evidence only; current live behavior not checked")
		screens = { { device = devices[1], label = saved, dump = saved } }
	else
		local result = Look.run({
			project = project,
			devices = devices,
			steps = Look.parseSteps(invocation.repeated.tap or {}, wait),
			out = Files.join(out, "live"),
			basePlace = Files.absolute(Files.join(out, "game.rbxlx")),
		})
		if result.problem ~= nil then
			lintFailed()
			print("problem: " .. result.problem)
			print("verify: FAIL")
			return 1
		end
		screens = result.screens
		for _, screen in screens do
			if screen.png == nil then
				screen.problem = (screen.problem or "") .. " no screenshot"
			end
		end
	end
	local failed = lintFailed()
	local auditStarted = os.clock()
	local lines, problems = Output.summarize(screens)
	problems = problems or failed
	timings.audit = os.clock() - auditStarted
	timings.total = os.clock() - started
	Files.write(Files.join(out, "timings.json"), Json.encode(timings))
	Files.write(Files.join(out, "report.txt"), table.concat(lines, "\n") .. "\n")
	local queries = Output.queries(lines, out)
	if not Cli.switch(invocation, "verbose") then
		local findings: { string } = {}
		for _, line in lines do
			if string.sub(line, 1, 11) ~= "screenshot " then
				table.insert(findings, line)
			end
		end
		lines = Output.captures(screens)
		for _, line in Output.compact(findings) do
			table.insert(lines, line)
		end
	end
	if #lines > 0 then
		print(table.concat(lines, "\n"))
	end
	if #queries > 0 then
		print(table.concat(queries, "\n"))
	end
	print("verify: " .. (if problems then "FAIL" else "PASS"))
	return if problems then 1 else 0
end

return {
	name = "verify",
	summary = "Run types, lint, build, audit and screenshots together.",
	usage = USAGE,
	values = { "project", "device", "tap", "wait", "out", "dump", "rule", "step", "page" },
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
					local result = Output.compact(lines)
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
