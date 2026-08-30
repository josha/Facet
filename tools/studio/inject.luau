--!strict
-- Studio injector (verification surface, contract §5): run via the Studio MCP
-- execute_luau in the EDIT datamodel while `lune run tools/lune/studio_sync`
-- is serving. Fetches build/studio_manifest.json from the local sync server
-- and creates/patches the gallery instance tree in the open place:
--   ReplicatedStorage.Facet            (library, src/)
--   ReplicatedStorage.FacetExamples    (tutorial examples)
--   ReplicatedStorage.FacetScenarios   (verification scenarios + runner)
--   StarterPlayer.StarterPlayerScripts.Gallery (client bootstrap)
-- Idempotent: existing nodes are patched in place (module require cache means
-- a PLAY session always sees fresh sources because play-mode copies re-require;
-- see docs/lessons re: cached module results in a single play session).
-- Stamps workspace attribute Facet_SourceStamp with the manifest stamp so a
-- session can prove which source state it runs (contract §4 step 2).
-- Returns a JSON summary string.
--
-- THE 200,000-CHAR SOURCE CAP IS PART OF THIS TOOL'S CONTRACT (2026-08-14).
-- `Script.Source` refuses any assignment of `>= 200000` characters — measured in
-- this very session on a throwaway ModuleScript, the engine's own words:
--
--   Unable to assign property Source. Provided string length (200000) is
--   greater than or equal to max length (200000)
--
-- so a module at or over the cap CANNOT be injected, and previously this script
-- threw on the first one and left the rest of the tree unpatched — a partial
-- inject that still stamped nothing and told nobody. Worse, a caller who ran it
-- before the cap was crossed and again after would see the same "it synced"
-- shape while three of the largest modules silently stayed at whatever the
-- built `.rbxl` carried. That is the false-evidence machine described in
-- `docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md` and guarded on
-- disk by `tools/check_source_size.py`.
--
-- So: every write is attempted under `pcall`, an over-cap module is REFUSED
-- before the attempt, and the return carries `refused` (with each module's disk
-- size, the size actually live in the place, and the byte gap) plus a
-- `staleModules` count. A session that reads a non-empty `refused` list knows
-- exactly which modules its live results do NOT describe.

local HttpService = game:GetService("HttpService")
pcall(function()
	HttpService.HttpEnabled = true
end)

-- `>=`, not `>`: a file at EXACTLY 200,000 is unsyncable (measured, above).
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
	--[[ `Script` JOINED THE LIST with the showcase's first server side
		(`examples/gallery/server`, ADR-0063). Without it the manifest would create
		the instance and never write its Source, so the injected place would carry
		an EMPTY authority script — which looks exactly like a server that decided
		to refuse everything. ]]
	if entry.file ~= "" and (wantClass == "ModuleScript" or wantClass == "LocalScript" or wantClass == "Script") then
		local src = HttpService:GetAsync(BASE .. "/file/" .. tostring(idx))
		local live = (inst :: any).Source
		if live == src then
			skipped += 1
		elseif #src >= SOURCE_CAP then
			-- do not even attempt it: the write throws, and a throw here used to
			-- abandon every remaining file in the manifest
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

workspace:SetAttribute("Facet_SourceStamp", manifest.stamp)
-- The stamp describes the manifest, NOT the place, whenever anything was
-- refused — say so on the attribute too, so a preflight that only reads the
-- stamp cannot certify a source state the place does not have.
workspace:SetAttribute("Facet_SourceStale", #refused + #failed)
return HttpService:JSONEncode({
	stamp = manifest.stamp,
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
