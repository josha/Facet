--!strict
-- The Studio-sync tree SHAPE — one walk, shared by `tools/lune/studio_sync.luau`
-- (which serves it over HTTP so the Studio MCP can inject sources) and
-- `tools/lune/check_scenario_requires.luau` (which proves a literal relative
-- `require("...")` string in the gallery/scenario/reference tree actually
-- resolves against it). Extracted so the two readers cannot describe the
-- mapping differently (SHOWCASE2 task A: the guard has to know EXACTLY what
-- `studio_sync` would serve, not a hand-maintained echo of it).
--
-- Mirrors `examples/gallery.project.json` (gallery mode) / `examples/
-- performance.project.json` (perf mode): src -> ReplicatedStorage.Facet,
-- examples/gallery/examples -> ReplicatedStorage.FacetExamples,
-- examples/gallery/scenarios -> ReplicatedStorage.FacetScenarios,
-- examples/gallery/client -> StarterPlayer.StarterPlayerScripts.Gallery,
-- examples/gallery/server -> ServerScriptService.Outpost,
-- examples/reference -> ReplicatedStorage.FacetReference,
-- examples/themes -> ReplicatedStorage.FacetThemes. Rojo folding: <dir>/
-- init.luau => ModuleScript named <dir> whose Source is the init file;
-- sibling .luau files => child ModuleScripts. *.spec.luau excluded.

local fs = require("@lune/fs")

export type FileEntry = {
	path: string, -- dot path under game, e.g. ReplicatedStorage.Facet.layout.solver
	className: string, -- ModuleScript | LocalScript | Folder
	file: string, -- repo-relative source file ("" for a folder with no init)
}

local studio_tree = {}

local function addTree(entries: { FileEntry }, fsDir: string, robloxPath: string, rootClassName: string)
	-- the directory itself: init.luau (or init.client.luau) becomes the node
	local initFile: string? = nil
	local className = rootClassName
	if fs.isFile(fsDir .. "/init.luau") then
		initFile = fsDir .. "/init.luau"
	elseif fs.isFile(fsDir .. "/init.client.luau") then
		initFile = fsDir .. "/init.client.luau"
		className = "LocalScript"
	elseif fs.isFile(fsDir .. "/init.server.luau") then
		--[[ THE SERVER FOLD, added with the showcase's first server side
			(`examples/gallery/server`, the outpost's server authority). Rojo maps
			`init.server.luau` to a `Script` exactly as it maps `init.client.luau`
			to a `LocalScript`; this walk knew only the client half, so a server
			folder would have been served as a `Folder` with no source and the
			injected place would have had no authority at all. ]]
		initFile = fsDir .. "/init.server.luau"
		className = "Script"
	end
	table.insert(entries, {
		path = robloxPath,
		className = if initFile then className else "Folder",
		file = initFile or "",
	})
	for _, name in fs.readDir(fsDir) do
		local full = fsDir .. "/" .. name
		if fs.isDir(full) then
			addTree(entries, full, robloxPath .. "." .. name, "ModuleScript")
		elseif name:match("%.luau$") and not name:match("%.spec%.luau$") and not name:match("^init%.") then
			table.insert(entries, {
				path = robloxPath .. "." .. name:gsub("%.luau$", ""),
				className = "ModuleScript",
				file = full,
			})
		end
	end
end

-- entries(mode): mode is "gallery" (default) or "perf" — see studio_sync.luau's
-- "TWO TREES, ONE AT A TIME" note for why the two never mount together.
function studio_tree.entries(mode: string?): { FileEntry }
	local entries: { FileEntry } = {}
	addTree(entries, "src", "ReplicatedStorage.Facet", "ModuleScript")
	addTree(entries, "examples/themes", "ReplicatedStorage.FacetThemes", "Folder")
	if mode == "perf" then
		addTree(entries, "examples/performance/lab", "ReplicatedStorage.FacetScenarios", "ModuleScript")
		table.insert(entries, {
			path = "ReplicatedStorage.FacetScenarios.runner",
			className = "ModuleScript",
			file = "examples/gallery/scenarios/runner.luau",
		})
		addTree(entries, "examples/performance/client", "StarterPlayer.StarterPlayerScripts.PerfLab", "ModuleScript")
	else
		addTree(entries, "examples/gallery/examples", "ReplicatedStorage.FacetExamples", "Folder")
		addTree(entries, "examples/gallery/scenarios", "ReplicatedStorage.FacetScenarios", "ModuleScript")
		addTree(entries, "examples/gallery/client", "StarterPlayer.StarterPlayerScripts.Gallery", "ModuleScript")
		-- the showcase's server side: the outpost's authority, and the
		-- only server-owned code in the repository
		addTree(entries, "examples/gallery/server", "ServerScriptService.Outpost", "Script")
		-- reference-app-validation: the five clean-room reference proofs,
		-- mirrored from gallery.project.json's FacetReference mapping
		addTree(entries, "examples/reference", "ReplicatedStorage.FacetReference", "Folder")
	end
	return entries
end

return studio_tree
