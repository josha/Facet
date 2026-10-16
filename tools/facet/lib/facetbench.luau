--!strict

local process = require("@std/process")
local Files = require("./files")
local Json = require("./json")

local Bench = {}
Bench.turns = {
	"hub-livery-editor",
	"hub-track-vote",
	"hub-quick-chat",
	"hub-upgrades",
	"hub-party-invite",
	"hub-first-time-tutorial",
}
local MODULES = { "Livery", "TrackVote", "QuickChat", "Upgrades", "Party", "Tutorial" }
local sequence = 0
Bench.starter = "artifacts/facetbench/extended-starter"
Bench.project = "eval/validation/extended.project.json"

local function patch(root: string, destination: string, source: string)
	local result = process.run({ "git", "apply", "--directory=" .. destination, source }, { cwd = root })
	assert(result.ok, result.stdout .. result.stderr)
end

local function read(path: string): Json.Object
	return Json.decode(Files.read(path)) :: Json.Object
end

local function node(path: string): Json.Object
	return { ["$path"] = Files.absolute(path) }
end

local function write(path: string, contents: string)
	if not Files.isFile(path) or Files.read(path) ~= contents then
		Files.writeAtomic(path, contents)
	end
end

local function sync(source: string, destination: string)
	for _, relative in Files.walk(destination) do
		if not Files.isFile(source .. "/" .. relative) then
			Files.remove(destination .. "/" .. relative)
		end
	end
	for _, relative in Files.walk(source) do
		write(destination .. "/" .. relative, Files.read(source .. "/" .. relative))
	end
end

function Bench.prepare(root: string)
	local function path(relative: string): string
		return Files.join(root, relative)
	end
	local starter = path(Bench.starter)
	sequence += 1
	local scratch = "artifacts/facetbench/prepare-" .. tostring(process.pid()) .. "-" .. tostring(sequence)
	local stagedStarter = scratch .. "/starter"
	for _, directory in { "server", "shared" } do
		Files.copyTree(
			path("eval/tasks/racing-hub/starter/src/" .. directory),
			path(stagedStarter .. "/src/" .. directory)
		)
	end
	Files.copy(
		path("eval/tasks/racing-hub/starter/src/client/Driving.client.luau"),
		path(stagedStarter .. "/src/client/Driving.client.luau")
	)
	Files.copyTree(path("eval/extended-starter/src"), path(stagedStarter .. "/src"))
	patch(root, stagedStarter, "eval/extended-starter/admin.patch")
	sync(path(stagedStarter), starter)
	local followups = "eval/validation/followups/strong"
	local stagedFollowups = scratch .. "/followups"
	for _, name in { "HubPanels.luau", "settings/init.luau", "shop/init.luau" } do
		Files.copy(
			path("eval/validation/racing-hub/strong/src/client/Interface/" .. name),
			path(stagedFollowups .. "/src/client/Interface/" .. name)
		)
	end
	for _, name in { "hub-panels", "settings", "shop" } do
		patch(root, stagedFollowups, "eval/validation/followups/" .. name .. ".patch")
	end
	sync(path(stagedFollowups), path(followups))
	Files.remove(path(scratch))
	local scripts: Json.Object = {}
	for index, id in Bench.turns do
		local source = path("eval/tasks/" .. id)
		local task = read(source .. "/task.json")
		task.brief = source .. "/brief.md"
		for _, value in task.checks :: { Json.Object } do
			if value.argv ~= nil then
				for argument, word in value.argv :: { string } do
					(value.argv :: { string })[argument] = string.gsub(word, "{task}", function(): string
						return source
					end)
				end
			end
		end
		if task.arms ~= nil then
			task.arms = { strong = { overlay = { starter } }, weak = { overlay = { starter } } }
		end
		write(path("eval/validation/" .. id .. "/task.json"), Json.encode(task) .. "\n")
		for _, arm in { "strong", "weak" } do
			local interface = node(path("eval/validation/" .. id .. "/strong/src/client/Interface"))
			for _, name in
				{
					"Kit",
					"HubPanels",
					"ExtendedKit",
					"codes",
					"daily-rewards",
					"inventory",
					"npc-dialogue",
					"pack-opening",
					"round-hud",
					"settings",
					"shop",
				}
			do
				local base = "eval/validation/racing-hub/strong/src/client/Interface/"
				if name == "HubPanels" or name == "settings" or name == "shop" then
					base = followups .. "/src/client/Interface/"
				elseif name == "ExtendedKit" then
					base = "eval/validation/hub-livery-editor/strong/src/client/Interface/"
				end
				interface[name] = node(path(base .. name .. (if string.match(name, "^%u") then ".luau" else "")))
			end
			for earlier = 1, index do
				local variant = if earlier == index then arm else "strong"
				interface[MODULES[earlier]] = node(
					path(
						"eval/validation/"
							.. Bench.turns[earlier]
							.. "/"
							.. variant
							.. "/src/client/Interface/"
							.. MODULES[earlier]
							.. ".luau"
					)
				)
			end
			scripts[MODULES[index] .. "-" .. arm] = { ["$className"] = "Folder", Interface = interface }
		end
	end
	local shared = node(starter .. "/src/shared")
	shared.Extended = node(path("eval/extended-starter/src/shared/Extended.luau"))
	local server = node(starter .. "/src/server")
	server.Extended = node(path("eval/extended-starter/src/server/Extended.server.luau"))
	write(path(Bench.project), Json.encode({
		name = "extended-reference-type-context",
		tree = {
			["$className"] = "DataModel",
			Lighting = { ["$properties"] = { Technology = "Future" } },
			ReplicatedStorage = { Shared = shared },
			ServerScriptService = { Server = server },
			StarterPlayer = { StarterPlayerScripts = scripts },
		},
	}) .. "\n")
end

return Bench
