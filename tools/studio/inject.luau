--!strict

local HttpService = game:GetService("HttpService")
pcall(function()
	HttpService.HttpEnabled = true
end)

local SOURCE_CAP = 200000

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
local refused: { any } = {}
local failed: { any } = {}
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

	if entry.runContext ~= nil and wantClass == "Script" then
		pcall(function()
			(inst :: any).RunContext = (Enum.RunContext :: any)[entry.runContext]
		end)
	end

	if entry.file ~= "" and (wantClass == "ModuleScript" or wantClass == "LocalScript" or wantClass == "Script") then
		local src = HttpService:GetAsync(BASE .. "/file/" .. tostring(idx))
		local live = (inst :: any).Source
		if live == src then
			skipped += 1
		elseif #src >= SOURCE_CAP then
			table.insert(refused, {
				path = entry.path,
				file = entry.file,
				diskBytes = #src,
				liveBytes = #live,
				behindBy = #src - #live,
			})
		else
			local ok, err = pcall(function()
				(inst :: any).Source = src
			end)
			if ok then
				patched += 1
			else
				table.insert(failed, { path = entry.path, diskBytes = #src, error = tostring(err) })
			end
		end
	end
end

local migratedBootstrap = false
if #refused + #failed == 0 then
	local modern = game:GetService("ReplicatedStorage"):FindFirstChild("Gallery")
	local starter = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local legacy = starter and starter:FindFirstChild("Gallery")
	if
		modern
		and modern:IsA("Script")
		and modern.RunContext == Enum.RunContext.Client
		and legacy
		and (legacy:IsA("LocalScript") or legacy:IsA("Script"))
		and (string.find(legacy.Source, "FacetScenarios", 1, true) or legacy.Source == modern.Source)
	then
		legacy:Destroy()
		migratedBootstrap = true
	end
end

workspace:SetAttribute("Facet_SourceStamp", manifest.stamp)

workspace:SetAttribute("Facet_SourceStale", #refused + #failed)
return HttpService:JSONEncode({
	stamp = manifest.stamp,
	migratedBootstrap = migratedBootstrap,
	nodes = #manifest.files,
	created = created,
	patched = patched,
	unchanged = skipped,
	staleModules = #refused + #failed,
	refused = refused,
	failed = failed,
	warning = if #refused + #failed > 0
		then `{#refused + #failed} module(s) are NOT live in this place — every result that depends on them is evidence about older code`
		else nil,
})
