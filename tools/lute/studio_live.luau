--!strict
local fs = require("@std/fs")
local json = require("@std/json")
local process = require("@std/process")
local Lute = require("../vendor/verify/src/lute")
local Verify = require("../vendor/verify/src/core")

local PLACE = "build/Facet-Live.rbxlx"
local PROJECT = "examples/.live.project.json"

local suites: { string } = {}
local only: string? = nil
local tag = "launched"
local deadline = 600
local placeOnly = false
local interactive = false
local studio: string? = nil
local device = "none"
local sharedValues: { string } = {}
local index = 2
while index <= #process.args do
	local argument = process.args[index]
	if argument == "--only" then
		index += 1
		only = process.args[index]
	elseif argument == "--tag" then
		index += 1
		tag = process.args[index]
	elseif argument == "--shared" then
		index += 1
		local name, value = string.match(process.args[index], "^([%w_]+)=(.+)$")
		assert(name and value, "--shared needs NAME=JSON")
		table.insert(
			sharedValues,
			`shared[{string.format("%q", name)}] = game:GetService('HttpService'):JSONDecode({string.format("%q", value)})`
		)
	elseif argument == "--device" then
		index += 1
		device = process.args[index]
	elseif argument == "--studio" then
		index += 1
		studio = process.args[index]
	elseif argument == "--place" then
		placeOnly = true
	elseif argument == "--interactive" then
		interactive = true
	elseif argument == "--deadline" then
		index += 1
		deadline = assert(tonumber(process.args[index]), "--deadline needs seconds")
	else
		table.insert(suites, argument)
	end
	index += 1
end
if #suites == 0 and not placeOnly then
	print(
		"usage: lute run tools/lute/studio_live.luau SUITE... [--only TEXT] [--tag NAME] [--deadline SECONDS] [--studio ID] [--device NAME] [--interactive] [--shared NAME=JSON]"
	)
	print("       lute run tools/lute/studio_live.luau --place")
	process.exit(2)
end

local project = json.deserialize(fs.readFileToString("examples/gallery.project.json")) :: any
project.name = "Facet-Live"
project.tree.Workspace["$attributes"] = { Facet_Demos = fs.readFileToString("tools/studio/live/fixture_demos.json") }
project.tree.ReplicatedStorage.FacetLive = { ["$path"] = "../tools/studio/live" }
project.tree.ReplicatedStorage.FacetVerify = { ["$path"] = "../tools/vendor/verify/src" }
project.tree.ReplicatedStorage.FacetConsumerScreen = { ["$path"] = "consumer/src/screen.luau" }
local monitors: { [string]: any } = { ["$className"] = "Folder" }
for _, entry in fs.listDirectory("examples/virtual_monitors") do
	local name = string.match(entry.name, "^(.+)%.luau$")
	if name and not string.find(name, "%.client$") and not string.find(name, "%.spec$") then
		monitors[name] = { ["$path"] = "virtual_monitors/" .. entry.name }
	end
end
project.tree.ReplicatedStorage.VirtualMonitors = monitors
fs.writeStringToFile(PROJECT, json.serialize(project))
if not fs.exists("build") then
	fs.createDirectory("build")
end
local built = process.run({ "rojo", "build", PROJECT, "-o", PLACE })
fs.remove(PROJECT)
if not built.ok then
	print(built.stderr)
	process.exit(1)
end

local LIMITS = { maxBytes = 4194304, maxCount = 512, maxTotalBytes = 33554432 }

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
	process.exit(0)
end

local failed = false
assert(not interactive or studio ~= nil, "--interactive requires --studio ID")
for _, suite in suites do
	local options =
		`\{ runId = runId, progressToken = progressToken, device = {string.format("%q", device)}, only = {if only
			then string.format("%q", only)
			else "nil"} }`
	local code = table.concat({
		table.concat(sharedValues, "\n"),
		"local storage = game:GetService('ReplicatedStorage')",
		"local live = require(storage:WaitForChild('FacetLive'))",
		"local channel = require(storage:WaitForChild('FacetVerify'):WaitForChild('roblox'):WaitForChild('report-channel'))",
		if interactive
			then `local drive = (function()\n{fs.readFileToString("tools/studio/live/interactive.luau")}\nend)()`
			else "",
		`local report = {if interactive then "drive(live, " else "live.report("}{string.format("%q", suite)}, {options})`,
		"return game:GetService('HttpService'):JSONEncode(channel.envelope(runId, report))",
	}, "\n")
	local outcome = if studio
		then Lute.studio.run({
			code = code,
			context = "Client",
			deadlineSeconds = deadline,
			progressFile = `artifacts/studio-live/{suite}-{tag}.progress.jsonl`,
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
			progressFile = `artifacts/studio-live/{suite}-{tag}.progress.jsonl`,
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
process.exit(if failed then 1 else 0)
