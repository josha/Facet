--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Bench = require("../../tools/facet/lib/facetbench")
local Files = require("../../tools/facet/lib/files")

local AgentEval = require("../../tools/vendor/verify/src/agent-eval")
local Play = require("../../tools/play/host/play")
local Universal = require("../tasks/racing-hub/hidden/universal")
local HubScenario = require("../tasks/racing-hub/hidden/scenario")

local SCENARIOS: { [string]: Play.Scenario } = {
	["racing-hub"] = require("../tasks/racing-hub/hidden/scenario"),
	["racing-hub-slice"] = require("../tasks/racing-hub/hidden/scenario"),
	["hub-shop-categories"] = require("../tasks/hub-shop-categories/hidden/scenario"),
	["hub-garage-sort"] = require("../tasks/hub-garage-sort/hidden/scenario"),
	["hub-settings-reset"] = require("../tasks/hub-settings-reset/hidden/scenario"),
	["hub-race-scoreboard"] = require("../tasks/hub-race-scoreboard/hidden/scenario"),
	["hub-livery-editor"] = require("../tasks/hub-livery-editor/hidden/scenario"),
	["hub-track-vote"] = require("../tasks/hub-track-vote/hidden/scenario"),
	["hub-quick-chat"] = require("../tasks/hub-quick-chat/hidden/scenario"),
	["hub-upgrades"] = require("../tasks/hub-upgrades/hidden/scenario"),
	["hub-party-invite"] = require("../tasks/hub-party-invite/hidden/scenario"),
	["hub-first-time-tutorial"] = require("../tasks/hub-first-time-tutorial/hidden/scenario"),
}

local binding = AgentEval.lute
local EXTENDED_SCENARIOS: { [string]: Play.Scenario } = {
	["hub-shop-categories"] = require("../tasks/extended/hub-shop-categories/hidden/scenario"),
	["hub-garage-sort"] = require("../tasks/extended/hub-garage-sort/hidden/scenario"),
	["hub-settings-reset"] = require("../tasks/extended/hub-settings-reset/hidden/scenario"),
	["hub-race-scoreboard"] = require("../tasks/extended/hub-race-scoreboard/hidden/scenario"),
}
local absolute = binding.absolute

local function directoryOf(source: string): string
	local path = absolute((string.gsub(source, "^@", "")))
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local EVAL = absolute(directoryOf(debug.info(1, "s")) .. "/..")
Bench.prepare(Files.parent(EVAL))
local structuralLoader = binding.loader()
structuralLoader.files = table.clone(structuralLoader.files)
local generatedKits = {
	[absolute(EVAL .. "/../artifacts/facetbench/arm-shared")] = true,
	[absolute(EVAL .. "/../artifacts/facetbench/arm-facet")] = true,
}
structuralLoader.files.exists = function(path: string): boolean
	return generatedKits[absolute(path)] == true or binding.files.exists(path)
end
structuralLoader.files.isDirectory = function(path: string): boolean
	return generatedKits[absolute(path)] == true or binding.files.isDirectory(path)
end
structuralLoader.files.list = function(path: string)
	if generatedKits[absolute(path)] and not binding.files.exists(path) then
		return {}
	end
	return binding.files.list(path)
end

local problems: { string } = {}
local notes: { string } = {}
local tierCounts: { [string]: { universal: number, spec: number } } = {}

local function fail(message: string)
	table.insert(problems, message)
end

local function read(path: string): unknown
	return binding.decode(fs.readFileToString(path))
end

local function field(value: unknown, key: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	return (value :: { [string]: unknown })[key]
end

local function list(value: unknown): { unknown }
	if type(value) ~= "table" then
		return {}
	end
	return value :: { unknown }
end

local function checkProjects(directory: string)
	for _, relative in Files.walk(directory, { skip = { vendor = true } }) do
		if not string.match(relative, "%.project%.json$") then
			continue
		end
		local path = directory .. "/" .. relative
		local tree = field(read(path), "tree")
		if field(tree, "$className") == "DataModel" then
			local technology = field(field(field(tree, "Lighting"), "$properties"), "Technology")
			if type(technology) ~= "string" or technology == "" or technology == "Compatibility" then
				fail(path .. " must set Lighting.Technology to a non-Compatibility value")
			end
		end
	end
end

for _, directory in { "eval", "examples", "tools" } do
	checkProjects(Files.parent(EVAL) .. "/" .. directory)
end
checkProjects(Files.parent(EVAL) .. "/" .. Bench.starter)

local function suite(path: string): AgentEval.Suite?
	local ok, value: unknown = pcall(function(): AgentEval.Suite
		return AgentEval.decodeSuite(read(path), path, structuralLoader)
	end)
	if not ok then
		fail(("%s does not load: %s"):format(path, tostring(value)))
		return nil
	end
	local loaded = value :: AgentEval.Suite
	local runs = AgentEval.plan(loaded, structuralLoader)
	print(("check: %s has %d task(s), %d arm(s) and %d run(s)"):format(path, #loaded.tasks, #loaded.arms, #runs))
	return loaded
end

local games = suite(EVAL .. "/games.json")
local slice = suite(EVAL .. "/slice.json")
local gameValidation = suite(EVAL .. "/validation/games.json")
suite(EVAL .. "/validation/slice.json")
local extended = suite(EVAL .. "/extended.json")
suite(EVAL .. "/extended-spec.json")
for _, id in
	{
		"hub-livery-editor",
		"hub-track-vote",
		"hub-quick-chat",
		"hub-upgrades",
		"hub-party-invite",
		"hub-first-time-tutorial",
	}
do
	suite(EVAL .. "/validation/" .. id .. ".json")
end

local thresholdsOk, thresholds: unknown = pcall(function(): unknown
	return AgentEval.report.decodeThresholds(read(EVAL .. "/thresholds.json"))
end)
if not thresholdsOk then
	fail("eval/thresholds.json does not load: " .. tostring(thresholds))
end

for _, loaded in { games, slice, extended } do
	if loaded ~= nil then
		local corpus = loaded :: AgentEval.Suite
		for _, item in corpus.tasks do
			local hidden = if fs.exists(item.directory .. "/hidden")
				then item.directory .. "/hidden/"
				else item.directory .. "/../hidden/"
			for _, name in { "play.luau", "scenario.luau" } do
				if not fs.exists(hidden .. name) then
					fail(("task %s has no hidden/%s"):format(item.id, name))
				end
			end
			local hasPlay = false
			local hasSpec = false
			for _, check in item.checks do
				if check.id == "play" and check.kind == "verify" then
					hasPlay = check.required ~= false and table.find(check.argv or {}, "universal") ~= nil
				end
				if check.id == "spec" and check.kind == "verify" then
					hasSpec = check.required == false and table.find(check.argv or {}, "spec") ~= nil
				end
			end
			if not hasSpec then
				fail(("task %s has no non-required spec producer"):format(item.id))
			end
			if not hasPlay then
				fail(("task %s has no play check"):format(item.id))
			end
			if corpus.id == "facetbench-games" and #item.devices ~= 5 then
				fail(("task %s does not run on the five devices"):format(item.id))
			end
			local scenario = if string.find(item.directory, "/extended/", 1, true) ~= nil
				then EXTENDED_SCENARIOS[item.id]
				else SCENARIOS[item.id]
			if item.id == "racing-hub-slice" then
				scenario = HubScenario.forSystems({ shop = true, ["hud-dock"] = true })
			end
			if scenario == nil then
				fail(("task %s has no scenario in eval/tools/check.luau"):format(item.id))
				continue
			end
			local sessions: { [string]: { [string]: boolean } } = {}
			for _, session in scenario.sessions do
				for _, case in session.cases do
					if case.tier ~= "spec" then
						fail(item.id .. "/" .. case.id .. " has no spec tier")
					end
				end
				if corpus.id == "facetbench-games" then
					print(("check: %s/%s has %d case(s)"):format(item.id, session.device, #session.cases))
				end
				local screens: { [string]: boolean } = {}
				for _, case in session.cases do
					if case.screen ~= nil then
						screens[case.screen :: string] = true
					end
				end
				sessions[session.device] = screens
			end
			for _, session in Universal.scenario(item.id).sessions do
				for _, case in session.cases do
					if case.screen ~= nil then
						sessions[session.device][case.screen] = true
					end
				end
			end
			local universalCount = #Universal.scenario(item.id).sessions[1].cases
			tierCounts[item.id] = { universal = universalCount, spec = #scenario.sessions[1].cases }
			for _, device in item.devices do
				if sessions[device.id] == nil then
					fail(("task %s has no play session for the device %s"):format(item.id, device.id))
				end
			end
			for _, check in item.checks do
				if check.kind ~= "audit" then
					continue
				end
				local folder, screen = string.match(check.dump or "", "/dumps/([^/]+)/([%w%-]+)%.json$")
				if folder == nil or screen == nil then
					fail(
						("task %s has the audit %s with no dumps/<device>/<screen>.json path"):format(item.id, check.id)
					)
					continue
				end
				local devices: { string } = {}
				if check.perDevice and folder == "{device}" then
					for _, device in item.devices do
						table.insert(devices, device.id)
					end
				elseif not check.perDevice and folder ~= "{device}" then
					table.insert(devices, folder :: string)
				else
					fail(
						("task %s has the audit %s with a dump path that does not match perDevice"):format(
							item.id,
							check.id
						)
					)
					continue
				end
				for _, device in devices do
					local screens = sessions[device]
					if screens == nil or not screens[screen :: string] then
						fail(
							("task %s audits the screen %s on %s, but no case of that session names it"):format(
								item.id,
								screen :: string,
								device
							)
						)
					end
				end
			end
		end
		for _, arm in corpus.arms do
			for _, overlay in arm.setup.overlay do
				if
					string.find(overlay, "arm-facet", 1, true) ~= nil
					and not fs.exists(overlay .. "/Packages/Facet/init.luau")
				then
					table.insert(
						notes,
						"the facet arm kit is not written; run lute run tools/facet kit --out artifacts/facetbench/arm-facet --force"
					)
				end
				if
					string.find(overlay, "arm-shared", 1, true) ~= nil
					and not fs.exists(overlay .. "/tools/typecheck/roblox.d.luau")
				then
					table.insert(notes, "the shared arm files are not written; run lute run eval/tools/shared-kit.luau")
				end
			end
		end
	end
end
local _ = gameValidation
for id, counts in tierCounts do
	print(("tiers: %s universal=%d spec=%d per device"):format(id, counts.universal, counts.spec))
end

for _, note in notes do
	print("note: " .. note)
end
if #problems > 0 then
	for _, problem in problems do
		print("problem: " .. problem)
	end
	process.exit(1)
end
print("check: the FacetBench corpus is consistent")
