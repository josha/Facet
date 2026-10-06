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
local index = 2
while index <= #process.args do
	local argument = process.args[index]
	if argument == "--only" then
		index += 1
		only = process.args[index]
	elseif argument == "--tag" then
		index += 1
		tag = process.args[index]
	elseif argument == "--deadline" then
		index += 1
		deadline = assert(tonumber(process.args[index]), "--deadline needs seconds")
	else
		table.insert(suites, argument)
	end
	index += 1
end
if #suites == 0 then
	print("usage: lute run tools/lute/studio_live.luau SUITE... [--only TEXT] [--tag NAME] [--deadline SECONDS]")
	process.exit(2)
end

local project = json.deserialize(fs.readFileToString("examples/gallery.project.json")) :: any
project.name = "Facet-Live"
project.tree.ReplicatedStorage.FacetLive = { ["$path"] = "../tools/studio/live" }
project.tree.ReplicatedStorage.FacetVerify = { ["$path"] = "../tools/vendor/verify/src" }
project.tree.ReplicatedStorage.FacetConsumerScreen = { ["$path"] = "consumer/src/screen.luau" }
fs.writeStringToFile(PROJECT, json.serialize(project))
local built = process.run({ "rojo", "build", PROJECT, "-o", PLACE })
fs.remove(PROJECT)
if not built.ok then
	print(built.stderr)
	process.exit(1)
end

local failed = false
if not fs.exists("artifacts/studio-live") then
	fs.createDirectory("artifacts/studio-live", { makeParents = true })
end
for _, suite in suites do
	local options = if only then `\{ only = {string.format("%q", only)} }` else "nil"
	local code = table.concat({
		"local storage = game:GetService('ReplicatedStorage')",
		"local live = require(storage:WaitForChild('FacetLive'))",
		"local channel = require(storage:WaitForChild('FacetVerify'):WaitForChild('roblox'):WaitForChild('report-channel'))",
		`local report = live.report({string.format("%q", suite)}, {options})`,
		"return game:GetService('HttpService'):JSONEncode(channel.envelope(runId, report))",
	}, "\n")
	local outcome = Lute.studio.run({
		place = PLACE,
		code = code,
		worker = "tools/vendor/verify/tools/studio-worker.luau",
		context = "Client",
		deadlineSeconds = deadline,
	})
	local report = outcome.report
	if outcome.status ~= "returned" or report == nil then
		print(`{suite}: {outcome.status} {outcome.detail or ""}`)
		failed = true
		continue
	end
	local decoded = Verify.decode(report)
	fs.writeStringToFile(`artifacts/studio-live/{suite}-{tag}.json`, Lute.encode(decoded))
	print(Verify.format(decoded))
	print(
		`{suite}: {decoded.passed} passed, {decoded.failed} failed of {decoded.total}; artifacts/studio-live/{suite}-{tag}.json`
	)
	failed = failed or decoded.passed ~= decoded.total
end
process.exit(if failed then 1 else 0)
