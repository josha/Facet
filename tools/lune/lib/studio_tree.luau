--!strict

local fs = require("@lune/fs")

export type FileEntry = {
	path: string,
	className: string,
	runContext: string?,
	file: string,
}

local studio_tree = {}

local function addTree(entries: { FileEntry }, fsDir: string, robloxPath: string, rootClassName: string)
	local initFile: string? = nil
	local className = rootClassName
	local runContext: string? = nil
	if fs.isFile(fsDir .. "/init.luau") then
		initFile = fsDir .. "/init.luau"
	elseif fs.isFile(fsDir .. "/init.client.luau") then
		initFile = fsDir .. "/init.client.luau"
		className = "Script"
		runContext = "Client"
	elseif fs.isFile(fsDir .. "/init.server.luau") then
		initFile = fsDir .. "/init.server.luau"
		className = "Script"
		runContext = "Server"
	end
	table.insert(entries, {
		path = robloxPath,
		className = if initFile then className else "Folder",
		runContext = if initFile then runContext else nil,
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

function studio_tree.entries(mode: string?): { FileEntry }
	local entries: { FileEntry } = {}
	addTree(entries, "src", "ReplicatedStorage.Facet", "ModuleScript")
	addTree(entries, "examples/themes", "ReplicatedStorage.FacetThemes", "Folder")
	if mode == "perf" then
		addTree(entries, "examples/performance/lab", "ReplicatedStorage.FacetScenarios", "ModuleScript")
		addTree(entries, "examples/performance/client", "ReplicatedStorage.PerfLab", "ModuleScript")
		addTree(entries, "tools/studio/live", "ReplicatedStorage.FacetLive", "ModuleScript")
	else
		addTree(entries, "examples/gallery/examples", "ReplicatedStorage.FacetExamples", "Folder")
		addTree(entries, "examples/gallery/scenarios", "ReplicatedStorage.FacetScenarios", "ModuleScript")
		addTree(entries, "examples/gallery/client", "ReplicatedStorage.Gallery", "ModuleScript")

		addTree(entries, "examples/gallery/server", "ServerScriptService.Outpost", "Script")

		addTree(entries, "examples/reference", "ReplicatedStorage.FacetReference", "Folder")
		addTree(entries, "tools/studio/live", "ReplicatedStorage.FacetLive", "ModuleScript")
		table.insert(entries, {
			path = "ReplicatedStorage.FacetConsumerScreen",
			className = "ModuleScript",
			file = "examples/consumer/src/screen.luau",
		})
		table.insert(entries, { path = "ReplicatedStorage.VirtualMonitors", className = "Folder", file = "" })
		for _, name in fs.readDir("examples/virtual_monitors") do
			if name:match("%.luau$") and not name:match("%.client%.luau$") and not name:match("%.spec%.luau$") then
				table.insert(entries, {
					path = "ReplicatedStorage.VirtualMonitors." .. name:gsub("%.luau$", ""),
					className = "ModuleScript",
					file = "examples/virtual_monitors/" .. name,
				})
			end
		end
	end
	return entries
end

return studio_tree
