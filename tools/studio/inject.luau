--!strict
-- Studio injector (verification surface, contract §5): run via the Studio MCP
-- execute_luau in the EDIT datamodel while `lune run tools/lune/studio_sync`
-- is serving. Fetches build/studio_manifest.json from the local sync server
-- and creates/patches the gallery instance tree in the open place:
--   ReplicatedStorage.LuauUI            (library, src/)
--   ReplicatedStorage.LuauUIExamples    (tutorial examples)
--   ReplicatedStorage.LuauUIScenarios   (verification scenarios + runner)
--   StarterPlayer.StarterPlayerScripts.Gallery (client bootstrap)
-- Idempotent: existing nodes are patched in place (module require cache means
-- a PLAY session always sees fresh sources because play-mode copies re-require;
-- see docs/lessons re: cached module results in a single play session).
-- Stamps workspace attribute LuauUI_SourceStamp with the manifest stamp so a
-- session can prove which source state it runs (contract §4 step 2).
-- Returns a JSON summary string.

local HttpService = game:GetService("HttpService")
pcall(function()
	HttpService.HttpEnabled = true
end)

local BASE = "http://127.0.0.1:8642"
local manifest = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/manifest"))

local function resolveParent(path: string): (Instance, string)
	local parts = string.split(path, ".")
	local node: Instance = game
	for i = 1, #parts - 1 do
		local seg = parts[i]
		local nxt = if node == game then game:GetService(seg) else node:FindFirstChild(seg)
		assert(nxt ~= nil, "missing ancestor " .. seg .. " for " .. path)
		node = nxt
	end
	return node, parts[#parts]
end

local created, patched, skipped = 0, 0, 0
for idx, entry in ipairs(manifest.files) do
	local parent, leaf = resolveParent(entry.path)
	local inst = parent:FindFirstChild(leaf)
	local wantClass = entry.className
	if inst ~= nil and inst.ClassName ~= wantClass then
		inst:Destroy()
		inst = nil
	end
	if inst == nil then
		inst = Instance.new(wantClass)
		inst.Name = leaf
		inst.Parent = parent
		created += 1
	end
	if entry.file ~= "" and (wantClass == "ModuleScript" or wantClass == "LocalScript") then
		local src = HttpService:GetAsync(BASE .. "/file/" .. tostring(idx))
		if (inst :: any).Source ~= src then
			(inst :: any).Source = src
			patched += 1
		else
			skipped += 1
		end
	end
end

workspace:SetAttribute("LuauUI_SourceStamp", manifest.stamp)
return HttpService:JSONEncode({
	stamp = manifest.stamp,
	nodes = #manifest.files,
	created = created,
	patched = patched,
	unchanged = skipped,
})
