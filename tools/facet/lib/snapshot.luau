--!strict

local Files = require("./files")
local Packages = require("./packages")
local Run = require("./run")

export type Name = "compose"

export type Config = {
	name: string,
	alias: string,
	root: string,
	destination: string,
	docsSource: string,
	docsDestination: string,
	paths: { string },
	stripPrefix: string,
	relocateDocs: boolean,
}

export type Source = {
	directory: string,
	docs: string?,
	repository: string,
	commit: string,
}

export type Entries = { [string]: string }

export type Request = {
	check: boolean,
	contentOnly: boolean?,
	source: Source?,
}

local Snapshot = {}

local PROTECTED = "README.md"

function Snapshot.config(root: string, _name: Name): Config
	return {
		name = "Compose",
		alias = "compose",
		root = root,
		destination = "src/vendor/compose",
		docsSource = ".agents/skills/compose",
		docsDestination = "skills/compose",
		paths = { "src/core", "src/roblox", "src/design", "src/design-editor", "LICENSE" },
		stripPrefix = "src/",
		relocateDocs = true,
	}
end

local function destination(config: Config): string
	return Files.join(config.root, config.destination)
end

local function docsDestination(config: Config): string
	return Files.join(config.root, config.docsDestination)
end

function Snapshot.source(config: Config): (Source?, string?)
	local locked, problem = Packages.locked(config.root, config.alias)
	if locked == nil then
		return nil, ("%s: %s"):format(config.name, problem or "not locked")
	end
	local directory = Files.join(config.root, locked.directory)
	if not Files.isDirectory(directory) then
		return nil, ("%s: %s is not installed; run lute pkg install --vendor"):format(config.name, locked.directory)
	end
	local docs: string? = nil
	local candidates = { Files.join(directory, config.docsSource) }
	if locked.store ~= nil then
		table.insert(candidates, Files.join(locked.store, config.docsSource))
	end
	for _, candidate in candidates do
		if Files.isDirectory(candidate) then
			docs = candidate
			break
		end
	end
	return {
		directory = directory,
		docs = docs,
		repository = locked.source,
		commit = locked.rev,
	}, nil
end

local function posixJoin(directory: string, target: string): string
	if directory == "" then
		return Files.collapse(target)
	end
	return Files.collapse(directory .. "/" .. target)
end

function Snapshot.relocateGuide(config: Config, data: string, name: string, source: Source): string
	local directory = string.match(name, "^(.*)/[^/]*$") or ""
	local base = string.gsub(source.repository, "%.git$", "")
	local relocated = string.gsub(data, "%]%(([^)]+)%)", function(target: string): string
		if string.find(target, ":", 1, true) ~= nil or string.sub(target, 1, 1) == "#" then
			return "](" .. target .. ")"
		end
		local path = posixJoin(directory, target)
		if string.sub(path, 1, #config.docsSource + 1) == config.docsSource .. "/" then
			return "](" .. target .. ")"
		end
		return "](" .. base .. "/blob/" .. source.commit .. "/" .. path .. ")"
	end)
	return relocated
end

local function stripped(config: Config, name: string): string
	if config.stripPrefix ~= "" and string.sub(name, 1, #config.stripPrefix) == config.stripPrefix then
		return string.sub(name, #config.stripPrefix + 1)
	end
	return name
end

function Snapshot.collect(config: Config, source: Source): (Entries?, Entries?, string?)
	local files: Entries = {}
	for _, member in config.paths do
		local absolute = Files.join(source.directory, member)
		if Files.isFile(absolute) then
			files[stripped(config, member)] = Files.read(absolute)
		elseif Files.isDirectory(absolute) then
			for _, relative in Files.walk(absolute) do
				files[stripped(config, member .. "/" .. relative)] = Files.read(Files.join(absolute, relative))
			end
		else
			return nil, nil, ("%s: the installed package has no %s"):format(config.name, member)
		end
	end
	local license = files.LICENSE
	if license == nil then
		return nil, nil, config.name .. ": the installed package has no LICENSE"
	end
	files["license.luau"] = "--!strict\nreturn [=[\n" .. license .. "\n]=]\n"
	local docs: Entries = {}
	local docsRoot = source.docs
	if docsRoot == nil then
		return nil,
			nil,
			("%s: neither the installed package nor its store checkout has %s"):format(config.name, config.docsSource)
	end
	for _, relative in Files.walk(docsRoot) do
		local data = Files.read(Files.join(docsRoot, relative))
		docs[relative] = if config.relocateDocs and string.sub(relative, -3) == ".md"
			then Snapshot.relocateGuide(config, data, config.docsSource .. "/" .. relative, source)
			else data
	end
	return files, docs, nil
end

local function committedFiles(config: Config): Entries
	local root = destination(config)
	local docs = docsDestination(config)
	local found: Entries = {}
	for _, relative in Files.walk(root) do
		local absolute = Files.join(root, relative)
		if relative ~= PROTECTED and not Files.within(absolute, docs) then
			found[relative] = absolute
		end
	end
	return found
end

local function committedDocs(config: Config): Entries
	local root = docsDestination(config)
	local found: Entries = {}
	for _, relative in Files.walk(root) do
		found[relative] = Files.join(root, relative)
	end
	return found
end

local function sameBytes(path: string, expected: string): boolean
	local bytes = Files.read(path)
	if bytes == expected then
		return true
	end
	return string.find(bytes, "\r\n", 1, true) ~= nil and (string.gsub(bytes, "\r\n", "\n")) == expected
end

local function difference(label: string, committed: Entries, expected: Entries): string?
	local names: { string } = {}
	for name in expected do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local path = committed[name]
		if path == nil then
			return ("%s/%s is missing"):format(label, name)
		end
		if not sameBytes(path, expected[name]) then
			return ("%s/%s differs from the installed package"):format(label, name)
		end
	end
	local extra: { string } = {}
	for name in committed do
		if expected[name] == nil then
			table.insert(extra, name)
		end
	end
	table.sort(extra)
	if #extra > 0 then
		return ("%s/%s is not in the installed package"):format(label, extra[1])
	end
	return nil
end

function Snapshot.compare(config: Config, files: Entries, docs: Entries): string?
	return difference(config.destination, committedFiles(config), files)
		or difference(config.docsDestination, committedDocs(config), docs)
end

function Snapshot.writeSnapshot(config: Config, files: Entries, docs: Entries)
	local root = destination(config)
	local docsRoot = docsDestination(config)
	local targets: { { base: string, entries: Entries } } = {
		{ base = root, entries = files },
		{ base = docsRoot, entries = docs },
	}
	for _, target in targets do
		local base = target.base
		local entries = target.entries
		for _, relative in Files.walk(base) do
			local absolute = Files.join(base, relative)
			local protected = base == root and relative == PROTECTED
			local foreign = base == root and Files.within(absolute, docsRoot)
			if not protected and not foreign and entries[relative] == nil then
				Files.remove(absolute)
			end
		end
		for name, data in entries do
			Files.write(Files.join(base, name), data)
		end
	end
	local directories = Files.walk(root, { directories = true })
	table.sort(directories, function(left: string, right: string): boolean
		local _, leftDepth = string.gsub(left, "/", "")
		local _, rightDepth = string.gsub(right, "/", "")
		if leftDepth ~= rightDepth then
			return leftDepth > rightDepth
		end
		return left > right
	end)
	for _, relative in directories do
		local absolute = Files.join(root, relative)
		if #Files.list(absolute) == 0 then
			Files.remove(absolute)
		end
	end
end

local function git(arguments: { string }, cwd: string?): (string?, string?)
	local result = Run.git(arguments, cwd)
	if not result.ok then
		return nil, ("git %s failed: %s"):format(table.concat(arguments, " "), (string.gsub(result.stderr, "%s+$", "")))
	end
	return result.stdout, nil
end

function Snapshot.executables(config: Config): { string }
	local found: { string } = {}
	local roots = { config.destination, config.docsDestination }
	for _, root in roots do
		local listed = git({ "ls-files", "-s", "--", root }, config.root)
		for line in string.gmatch(listed or "", "[^\n]+") do
			local mode, path = string.match(line, "^(%d+) %x+ %d+\t(.+)$")
			if mode ~= nil and path ~= nil and mode ~= "100644" then
				table.insert(found, path)
			end
		end
	end
	table.sort(found)
	return found
end

local function clearExecutables(config: Config): string?
	local executables = Snapshot.executables(config)
	if #executables == 0 then
		return nil
	end
	local arguments = { "update-index", "--chmod=-x", "--" }
	for _, path in executables do
		table.insert(arguments, path)
		Run.capture({ "chmod", "644", Files.join(config.root, path) })
	end
	local _, failure = git(arguments, config.root)
	return failure
end

function Snapshot.sync(config: Config, request: Request): (number, string)
	local source = request.source
	if source == nil then
		local found, problem = Snapshot.source(config)
		if found == nil then
			return 1, problem or (config.name .. ": no installed package")
		end
		source = found
	end
	assert(source ~= nil)
	local files, docs, failure = Snapshot.collect(config, source)
	if files == nil or docs == nil then
		return 1, failure or (config.name .. ": the installed package could not be read")
	end
	local differs = Snapshot.compare(config, files, docs)
	if request.check then
		if differs ~= nil then
			return 1,
				("%s: %s; run lute run tools/facet sync %s"):format(config.name, differs, string.lower(config.name))
		end
		local executables: { string } = if request.contentOnly then {} else Snapshot.executables(config)
		if #executables > 0 then
			return 1,
				("%s: generated files must have mode 100644: %s; run lute run tools/facet sync %s"):format(
					config.name,
					table.concat(executables, ", "),
					string.lower(config.name)
				)
		end
		return 0, ("%s: the copy matches the installed package %s"):format(config.name, source.commit)
	end
	if differs ~= nil then
		Snapshot.writeSnapshot(config, files, docs)
		local remaining = Snapshot.compare(config, files, docs)
		if remaining ~= nil then
			return 1, ("%s: the copy still differs after writing: %s"):format(config.name, remaining)
		end
	end
	local cleared = clearExecutables(config)
	if cleared ~= nil then
		return 1, ("%s: %s"):format(config.name, cleared)
	end
	return 0,
		if differs == nil
			then ("%s: the copy already matches the installed package %s"):format(config.name, source.commit)
			else ("%s: copied the installed package %s"):format(config.name, source.commit)
end

function Snapshot.check(root: string, name: Name): (boolean, string)
	local code, message = Snapshot.sync(Snapshot.config(root, name), { check = true })
	return code == 0, message
end

return table.freeze(Snapshot)
