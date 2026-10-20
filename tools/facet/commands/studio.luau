--!strict
local Cli = require("../lib/cli")
local fs = require("@std/fs")
local json = require("@std/json")
local process = require("@std/process")
local Lute = require("../../vendor/verify/src/lute")
local Verify = require("../../vendor/verify/src/core")

local function run(invocation: Cli.Invocation): number
	if invocation.arguments[1] ~= "live" then
		print("usage: lute run tools/facet studio live SUITE... [options]")
		return 2
	end
	local PLACE = `build/Facet-Live-{process.pid()}.rbxl`
	local PROJECT = `examples/.live-{process.pid()}.project.json`

	local suites: { string } = {}
	local caseIds: { string } = {}
	local only: string? = nil
	local tag = "launched"
	local deadline = 600
	local placeOnly = false
	local noProgress = false
	local interactive = false
	local casesFromTree = false
	local studio: string? = nil
	local resumeRun: string? = nil
	local device = "none"
	local sharedValues: { string } = {}
	local index = 2
	while index <= #invocation.arguments do
		local argument = invocation.arguments[index]
		if argument == "--only" then
			index += 1
			only = invocation.arguments[index]
		elseif argument == "--case" then
			index += 1
			local id = assert(invocation.arguments[index], "--case needs an id")
			table.insert(caseIds, id)
		elseif argument == "--tag" then
			index += 1
			tag = invocation.arguments[index]
		elseif argument == "--shared" then
			index += 1
			local name, value = string.match(invocation.arguments[index], "^([%w_]+)=(.+)$")
			assert(name and value, "--shared needs NAME=JSON")
			table.insert(
				sharedValues,
				`shared[{string.format("%q", name)}] = game:GetService('HttpService'):JSONDecode({string.format(
					"%q",
					value
				)})`
			)
		elseif argument == "--resume-run" then
			index += 1
			resumeRun = invocation.arguments[index]
		elseif argument == "--device" then
			index += 1
			device = invocation.arguments[index]
		elseif argument == "--studio" then
			index += 1
			studio = invocation.arguments[index]
		elseif argument == "--place" then
			placeOnly = true
		elseif argument == "--no-progress" then
			noProgress = true
		elseif argument == "--cases-from-tree" then
			casesFromTree = true
		elseif argument == "--interactive" then
			interactive = true
		elseif argument == "--deadline" then
			index += 1
			deadline = assert(tonumber(invocation.arguments[index]), "--deadline needs seconds")
		else
			table.insert(suites, argument)
		end
		index += 1
	end
	if #suites == 0 and not placeOnly then
		print(
			"usage: lute run tools/facet studio live SUITE... [--only TEXT] [--case ID]... [--tag NAME] [--deadline SECONDS] [--studio ID] [--device NAME] [--interactive] [--cases-from-tree] [--resume-run ID] [--shared NAME=JSON] [--no-progress]"
		)
		print("       lute run tools/facet studio live --place")
		return 2
	end
	if placeOnly then
		PLACE = "build/Facet-Live.rbxl"
	end

	local project = json.deserialize(fs.readFileToString("examples/gallery.project.json")) :: any
	project.name = "Facet-Live"
	local revision = process.run({ "git", "rev-parse", "HEAD" })
	local status = process.run({ "git", "status", "--porcelain", "--untracked-files=no" })
	assert(revision.ok and status.ok, "cannot record the live build revision")
	project.tree.Workspace["$attributes"] = {
		Facet_Demos = fs.readFileToString("tools/studio/live/fixture_demos.json"),
		Facet_SourceStamp = string.gsub(revision.stdout, "%s+$", "") .. (if status.stdout == "" then "" else "+dirty"),
	}
	project.tree.ReplicatedStorage.FacetLive = { ["$path"] = "../tools/studio/live" }
	project.tree.ReplicatedStorage.FacetVerify = { ["$path"] = "../tools/vendor/verify/src" }
	project.tree.ReplicatedStorage.FacetConsumerScreen = { ["$path"] = "consumer/src/screen.luau" }
	project.tree.ReplicatedStorage.Lab = {
		["$className"] = "Folder",
		drag_drop_demo = { ["$path"] = "facet-lab/src/drag_drop_demo.luau" },
		journal_demo = { ["$path"] = "facet-lab/src/journal_demo.luau" },
	}
	project.tree.ReplicatedStorage.LabThemes = { ["$path"] = "facet-lab/themes" }
	if table.find(suites, "lab") then
		project.tree.ReplicatedStorage.Lab = { ["$path"] = "facet-lab/src" }
		project.tree.ReplicatedStorage.FacetShowcase = {
			["$className"] = "Folder",
			screen = { ["$path"] = "gallery/client/screen.luau" },
			demo_picker = { ["$path"] = "gallery/client/demo_picker.luau" },
		}
	end
	local monitors: { [string]: any } = { ["$className"] = "Folder" }
	for _, entry in fs.listDirectory("examples/virtual_monitors") do
		local name = string.match(entry.name, "^(.+)%.luau$")
		if name and not string.find(name, "%.client$") and not string.find(name, "%.verify$") then
			monitors[name] = { ["$path"] = "virtual_monitors/" .. entry.name }
		end
	end
	project.tree.ReplicatedStorage.VirtualMonitors = monitors
	fs.writeStringToFile(PROJECT, json.serialize(project))
	if not fs.exists("build") then
		fs.createDirectory("build")
	end
	if not fs.exists("artifacts/studio-live") then
		fs.createDirectory("artifacts/studio-live", { makeParents = true })
	end
	local built = process.run({ "rojo", "build", PROJECT, "-o", PLACE })
	fs.remove(PROJECT)
	if not built.ok then
		print(built.stderr)
		return 1
	end

	local LIMITS: Verify.AttachmentLimits = require("../../studio/live/attachment_limits")

	local function write(path: string, text: string)
		local directory = string.match(path, "^(.*)/[^/]+$")
		if directory and not fs.exists(directory) then
			fs.createDirectory(directory, { makeParents = true })
		end
		fs.writeStringToFile(path, text)
	end

	local function destination(suite: string, caseId: string, name: string): string
		local atlas = string.match(name, "^atlas/(.+)$")
		if atlas then
			return "tests/fixtures/focus_atlas/" .. atlas
		end
		local saved = string.match(name, "^live/(.+)$")
		if saved then
			return "artifacts/studio-live/" .. saved
		end
		return `artifacts/studio-live/{suite}-{tag}/{string.gsub(caseId, "[^%w%-_]", "_")}/{name}`
	end

	if placeOnly then
		print(PLACE)
		return 0
	end

	local failed = false
	assert(not casesFromTree or studio ~= nil, "--cases-from-tree requires --studio ID")
	assert(resumeRun == nil or (studio ~= nil and #suites == 1), "--resume-run requires --studio ID and one suite")
	assert(
		#caseIds == 0 or (only == nil and not interactive and resumeRun == nil),
		"--case cannot be combined with --only, --interactive or --resume-run"
	)
	local selectedIds: { string } = {}
	for _, id in caseIds do
		table.insert(selectedIds, string.format("%q", id))
	end
	for _, suite in suites do
		local options =
			`\{ runId = runId, progressToken = progressToken, device = {string.format("%q", device)}, ids = {if #selectedIds
					> 0
				then "{" .. table.concat(selectedIds, ",") .. "}"
				else "nil"}, only = {if only then string.format("%q", only) else "nil"} }`
		local code = table.concat({
			table.concat(sharedValues, "\n"),
			"local storage = game:GetService('ReplicatedStorage')",
			"local live = require(storage:WaitForChild('FacetLive'))",
			if #caseIds > 0
				then "assert(live.caseSelection == true, 'the live place needs a rebuild before --case can select cases')"
				else "",
			"local channel = require(storage:WaitForChild('FacetVerify'):WaitForChild('roblox'):WaitForChild('report-channel'))",
			if casesFromTree
				then table.concat({
					`local caseModule = storage:WaitForChild('FacetLive'):WaitForChild('suites'):WaitForChild({string.format(
						"%q",
						suite
					)})`,
					`local currentCases = (function(script)\n{fs.readFileToString(
						"tools/studio/live/suites/" .. suite .. ".luau"
					)}\nend)(caseModule)`,
					`local placedCases = live.cases({string.format("%q", suite)})`,
					"table.clear(placedCases)",
					"table.move(currentCases, 1, #currentCases, 1, placedCases)",
				}, "\n")
				else "",
			if interactive
				then `local drive = (function()\n{fs.readFileToString("tools/studio/live/interactive.luau")}\nend)()`
				else "",
			`local report = {if interactive then "drive(live, " else "live.report("}{string.format("%q", suite)}, {options})`,
			`report.environment.caseSource = {string.format("%q", if casesFromTree then "working-tree" else "place")}`,
			"for _, source in report.sources or {} do if source.environment then source.environment.caseSource = report.environment.caseSource end end",
			"for _, case in report.results do if case.origin and case.origin.environment then case.origin.environment.caseSource = report.environment.caseSource end end",
			"return game:GetService('HttpService'):JSONEncode(channel.envelope(runId, report))",
		}, "\n")
		local progressFile = if noProgress then nil else `artifacts/studio-live/{suite}-{tag}.progress.jsonl`
		local outcome = if resumeRun
			then (function(): Verify.BatchOutcome
				local session, refusal = Lute.studio.attach({
					studioId = studio,
					mode = "play",
					runSeconds = deadline,
					authorize = function(request)
						return { ok = request.studioId == nil or request.studioId == studio }
					end,
				})
				if not session then
					return { status = "faulted", detail = if refusal then refusal.detail else "Studio attach failed" }
				end
				local resumed = session.report("Client", "error('the saved Verify run is absent')", resumeRun :: string)
				session.close()
				return if resumed.report
					then { status = "returned", report = resumed.report }
					else { status = "faulted", detail = resumed.problem }
			end)()
			elseif studio then Lute.studio.run({
				code = code,
				context = "Client",
				deadlineSeconds = deadline,
				progressFile = progressFile,
				attach = {
					studioId = studio,
					runSeconds = deadline,
					authorize = function(request)
						return { ok = request.studioId == nil or request.studioId == studio }
					end,
				},
			})
			else Lute.studio.run({
				place = PLACE,
				code = code,
				worker = "tools/vendor/verify/tools/studio-worker.luau",
				context = "Client",
				deadlineSeconds = deadline,
				progressFile = progressFile,
			})
		local returned = outcome.report
		if outcome.status ~= "returned" or returned == nil then
			print(`{suite}: {outcome.status} {outcome.detail or ""}`)
			failed = true
			continue
		end
		local report, issues = Lute.attachments.materialize(Verify.decode(returned), {
			directory = `artifacts/studio-live/{suite}-{tag}`,
			limits = LIMITS,
			host = "roblox-studio",
			sink = function(caseId: string, name: string, text: string): (string?, string?)
				local path = destination(suite, caseId, name)
				write(path, text)
				if string.sub(name, 1, 6) == "atlas/" then
					local captured = `artifacts/studio-live/{suite}-{tag}/{string.gsub(caseId, "[^%w%-_]", "_")}/{name}`
					write(captured, text)
					return captured, nil
				end
				return path, nil
			end,
		})
		write(`artifacts/studio-live/{suite}-{tag}.json`, Lute.encode(report))
		print(Verify.format(report))
		for _, issue in issues do
			print("attachment: " .. issue)
		end
		print(
			`{suite}: {report.passed} passed, {report.failed} failed, {report.unsupported} unsupported of {report.total}; artifacts/studio-live/{suite}-{tag}.json`
		)
		failed = failed or report.passed + report.unsupported ~= report.total or report.passed == 0 or #issues > 0
	end
	return if failed then 1 else 0
end

local command: Cli.Command = {
	name = "studio",
	summary = "Run live Studio suites through Verify.",
	usage = "usage: lute run tools/facet studio live SUITE... [--only TEXT | --case ID] [--studio ID] [--tag NAME]",
	run = run,
}
return command
