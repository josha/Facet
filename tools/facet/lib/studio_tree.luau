--!strict

export type FileSystem = {
	isFile: (path: string) -> boolean,
	isDir: (path: string) -> boolean,
	readDir: (path: string) -> { string },
	readFile: (path: string) -> string,
}

export type FileEntry = {
	path: string,
	className: string,
	runContext: string?,
	file: string,
}

local StudioTree = {}

local function located(root: string?, relative: string): string
	if root == nil or root == "" or root == "." then
		return relative
	end
	return root .. "/" .. relative
end

local function sortedNames(fs: FileSystem, directory: string): { string }
	local names = table.clone(fs.readDir(directory))
	table.sort(names)
	return names
end

local function addTree(
	fs: FileSystem,
	root: string?,
	entries: { FileEntry },
	directory: string,
	robloxPath: string,
	rootClassName: string
)
	if not fs.isDir(located(root, directory)) then
		return
	end
	local initFile: string? = nil
	local className = rootClassName
	local runContext: string? = nil
	if fs.isFile(located(root, directory .. "/init.luau")) then
		initFile = directory .. "/init.luau"
	elseif fs.isFile(located(root, directory .. "/init.client.luau")) then
		initFile = directory .. "/init.client.luau"
		className = "Script"
		runContext = "Client"
	elseif fs.isFile(located(root, directory .. "/init.server.luau")) then
		initFile = directory .. "/init.server.luau"
		className = "Script"
		runContext = "Server"
	end
	table.insert(entries, {
		path = robloxPath,
		className = if initFile then className else "Folder",
		runContext = if initFile then runContext else nil,
		file = initFile or "",
	})
	for _, name in sortedNames(fs, located(root, directory)) do
		local child = directory .. "/" .. name
		if fs.isDir(located(root, child)) then
			addTree(fs, root, entries, child, robloxPath .. "." .. name, "ModuleScript")
		elseif
			string.match(name, "%.luau$") ~= nil
			and string.match(name, "%.verify%.luau$") == nil
			and string.match(name, "^init%.") == nil
		then
			table.insert(entries, {
				path = robloxPath .. "." .. string.gsub(name, "%.luau$", ""),
				className = "ModuleScript",
				file = child,
			})
		end
	end
end

function StudioTree.entries(fs: FileSystem, root: string?, mode: string?): { FileEntry }
	local entries: { FileEntry } = {}
	addTree(fs, root, entries, "src", "ReplicatedStorage.Facet", "ModuleScript")
	addTree(fs, root, entries, "tools/vendor/verify/src", "ReplicatedStorage.FacetVerify", "Folder")
	addTree(fs, root, entries, "examples/themes", "ReplicatedStorage.FacetThemes", "Folder")
	if mode == "perf" then
		addTree(fs, root, entries, "examples/performance/lab", "ReplicatedStorage.FacetScenarios", "ModuleScript")
		addTree(fs, root, entries, "examples/performance/client", "ReplicatedStorage.PerfLab", "ModuleScript")
		addTree(fs, root, entries, "tools/studio/live", "ReplicatedStorage.FacetLive", "ModuleScript")
		return entries
	end
	addTree(fs, root, entries, "examples/gallery/examples", "ReplicatedStorage.FacetExamples", "Folder")
	addTree(fs, root, entries, "examples/gallery/scenarios", "ReplicatedStorage.FacetScenarios", "ModuleScript")
	addTree(fs, root, entries, "examples/gallery/client", "ReplicatedStorage.Gallery", "ModuleScript")
	addTree(fs, root, entries, "examples/gallery/server", "ServerScriptService.Outpost", "Script")
	addTree(fs, root, entries, "examples/reference", "ReplicatedStorage.FacetReference", "Folder")
	addTree(fs, root, entries, "tools/studio/live", "ReplicatedStorage.FacetLive", "ModuleScript")
	table.insert(entries, {
		path = "ReplicatedStorage.FacetConsumerScreen",
		className = "ModuleScript",
		file = "examples/consumer/src/screen.luau",
	})
	table.insert(entries, { path = "ReplicatedStorage.VirtualMonitors", className = "Folder", file = "" })
	local monitors = "examples/virtual_monitors"
	if fs.isDir(located(root, monitors)) then
		for _, name in sortedNames(fs, located(root, monitors)) do
			if
				string.match(name, "%.luau$") ~= nil
				and string.match(name, "%.client%.luau$") == nil
				and string.match(name, "%.verify%.luau$") == nil
			then
				table.insert(entries, {
					path = "ReplicatedStorage.VirtualMonitors." .. string.gsub(name, "%.luau$", ""),
					className = "ModuleScript",
					file = monitors .. "/" .. name,
				})
			end
		end
	end
	return entries
end

function StudioTree.located(root: string?, relative: string): string
	return located(root, relative)
end

return table.freeze(StudioTree)
