--!strict

local Files = require("./files")
local Hash = require("./hash")
local Json = require("./json")
local Run = require("./run")
local Tar = require("./tar")

export type Name = "compose" | "verify"

export type Config = {
	name: string,
	root: string,
	destination: string,
	docsSource: string,
	docsDestination: string,
	paths: { string },
	stripPrefix: string,
	relocateDocs: boolean,
}

export type Pin = {
	repository: string,
	commit: string,
	sha256: { [string]: string },
	docs: { [string]: string },
	document: Json.Object,
}

export type Entries = { [string]: string }

export type Fetch = (config: Config, scratch: string, pin: Pin) -> (Entries, Entries)

local Snapshot = {}

local COMMIT = "^[0-9a-f]+$"

function Snapshot.config(root: string, name: Name): Config
	if name == "compose" then
		return {
			name = "Compose",
			root = root,
			destination = "src/vendor/compose",
			docsSource = ".agents/skills/compose",
			docsDestination = "skills/compose",
			paths = { "src/core", "src/roblox", "src/design", "src/design-editor", "LICENSE" },
			stripPrefix = "src/",
			relocateDocs = true,
		}
	end
	return {
		name = "Verify",
		root = root,
		destination = "tools/vendor/verify",
		docsSource = ".agents/skills/verify",
		docsDestination = "tools/vendor/verify/.agents/skills/verify",
		paths = {
			"src/core",
			"src/roblox",
			"src/lute",
			"tools/studio-worker.luau",
			"tools/export-studio-reflection.luau",
			"tools/export-studio-probes.luau",
			"tools/lib/studio-edit.luau",
			"src/gate",
			"src/evidence",
			"src/agent-eval",
			"src/codec",
			"tools/agent-eval.luau",
			"tools/scoped-studio-mcp.luau",
			"src/benchmark.luau",
			"src/benchmark-case.luau",
			"src/benchmark-check.luau",
			"src/benchmark-store.luau",
			"src/benchmark-types.luau",
			"LICENSE",
			"PROVENANCE.md",
			"docs",
		},
		stripPrefix = "",
		relocateDocs = false,
	}
end

local function destination(config: Config): string
	return Files.join(config.root, config.destination)
end

local function docsDestination(config: Config): string
	return Files.join(config.root, config.docsDestination)
end

local function pinPath(config: Config): string
	return Files.join(destination(config), "UPSTREAM.lock")
end

local function pinLabel(config: Config): string
	return config.destination .. "/UPSTREAM.lock"
end

function Snapshot.validCommit(value: unknown): boolean
	return type(value) == "string" and #value == 40 and string.match(value, COMMIT) ~= nil
end

function Snapshot.validRepository(value: unknown): boolean
	if type(value) ~= "string" then
		return false
	end
	local owner, project = string.match(value, "^https://github%.com/([%w%._%-]+)/([%w%._%-]+)$")
	return owner ~= nil and project ~= nil
end

function Snapshot.checkedPin(config: Config, document: unknown): (Pin?, string?)
	local commit = Json.field(document, "commit")
	local repository = Json.field(document, "repository")
	if not Snapshot.validCommit(commit) then
		return nil,
			("%s: %s records commit %s, which is not a full 40-character lowercase-hex object name. Refusing to pass it to git."):format(
				config.name,
				pinLabel(config),
				Json.encode(commit)
			)
	end
	if not Snapshot.validRepository(repository) then
		return nil,
			("%s: %s records repository %s, which is not an https://github.com/<owner>/<name> URL. Refusing to fetch from it."):format(
				config.name,
				pinLabel(config),
				Json.encode(repository)
			)
	end
	local function hashes(key: string): { [string]: string }
		local found: { [string]: string } = {}
		local object = Json.objectField(document, key)
		if object ~= nil then
			for name, digest in object do
				if type(digest) == "string" then
					found[name] = digest
				end
			end
		end
		return found
	end
	local object = Json.asObject(document) or Json.object()
	return {
		repository = repository :: string,
		commit = commit :: string,
		sha256 = hashes("sha256"),
		docs = hashes("docs"),
		document = object,
	},
		nil
end

function Snapshot.safeMemberName(config: Config, name: string): (string?, string?)
	local probe = string.gsub(name, "\\", "/")
	local first = string.split(probe, "/")[1] or ""
	if string.sub(probe, 1, 1) == "/" or string.find(first, ":", 1, true) ~= nil then
		return nil, ("%s: archive member %s is an absolute path; refusing"):format(config.name, Json.encode(name))
	end
	for _, part in string.split(Files.collapse(probe), "/") do
		if part == ".." then
			return nil,
				("%s: archive member %s escapes the snapshot root; refusing"):format(config.name, Json.encode(name))
		end
	end
	return name, nil
end

local function posixJoin(directory: string, target: string): string
	if directory == "" then
		return Files.collapse(target)
	end
	return Files.collapse(directory .. "/" .. target)
end

function Snapshot.relocateGuide(config: Config, data: string, name: string, pin: Pin): string
	local directory = string.match(name, "^(.*)/[^/]*$") or ""
	local base = string.gsub(pin.repository, "%.git$", "")
	local relocated = string.gsub(data, "%]%(([^)]+)%)", function(target: string): string
		if string.find(target, ":", 1, true) ~= nil or string.sub(target, 1, 1) == "#" then
			return "](" .. target .. ")"
		end
		local path = posixJoin(directory, target)
		if string.sub(path, 1, #config.docsSource + 1) == config.docsSource .. "/" then
			return "](" .. target .. ")"
		end
		return "](" .. base .. "/blob/" .. pin.commit .. "/" .. path .. ")"
	end)
	return relocated
end

local function digest(path: string, expected: string): boolean
	local bytes = Files.read(path)
	if Hash.sha256(bytes) == expected then
		return true
	end
	return string.find(bytes, "\r\n", 1, true) ~= nil and Hash.sha256Text(bytes) == expected
end

local function generatedFiles(config: Config): { [string]: string }
	local root = destination(config)
	local docs = docsDestination(config)
	local found: { [string]: string } = {}
	for _, relative in Files.walk(root) do
		local absolute = Files.join(root, relative)
		if relative ~= "UPSTREAM.lock" and relative ~= "README.md" and not Files.within(absolute, docs) then
			found[relative] = absolute
		end
	end
	return found
end

local function docFiles(config: Config): { [string]: string }
	local root = docsDestination(config)
	local found: { [string]: string } = {}
	for _, relative in Files.walk(root) do
		found[relative] = Files.join(root, relative)
	end
	return found
end

local function sameKeys(left: { [string]: string }, right: { [string]: string }): boolean
	for key in left do
		if right[key] == nil then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function parents(name: string): { string }
	local found: { string } = {}
	local current = name
	while true do
		local parent = string.match(current, "^(.*)/[^/]*$")
		if parent == nil or parent == "" then
			break
		end
		table.insert(found, parent)
		current = parent
	end
	return found
end

function Snapshot.verify(config: Config, pin: Pin): boolean
	local generated = generatedFiles(config)
	local docs = docFiles(config)
	if not sameKeys(generated, pin.sha256) or not sameKeys(docs, pin.docs) then
		return false
	end
	for name, path in generated do
		if not digest(path, pin.sha256[name]) then
			return false
		end
	end
	for name, path in docs do
		if not digest(path, pin.docs[name]) then
			return false
		end
	end
	local expected: { [string]: boolean } = {}
	for name in generated do
		for _, parent in parents(name) do
			expected[parent] = true
		end
	end
	local root = destination(config)
	local docsRoot = docsDestination(config)
	for name in pin.docs do
		local absolute = Files.join(docsRoot, name)
		for _, parent in parents(absolute) do
			if parent ~= root and Files.within(parent, root) then
				expected[Files.relative(parent, root)] = true
			end
		end
	end
	local actual: { [string]: boolean } = {}
	for _, relative in Files.walk(root, { directories = true }) do
		actual[relative] = true
	end
	for name in expected do
		if not actual[name] then
			return false
		end
	end
	for name in actual do
		if not expected[name] then
			return false
		end
	end
	return true
end

function Snapshot.inventory(entries: Entries): { [string]: string }
	local hashes: { [string]: string } = {}
	for name, data in entries do
		hashes[name] = Hash.sha256(data)
	end
	return hashes
end

local function sameInventory(left: { [string]: string }, right: { [string]: string }): boolean
	if not sameKeys(left, right) then
		return false
	end
	for key, value in left do
		if right[key] ~= value then
			return false
		end
	end
	return true
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
			local protected = base == root and (relative == "UPSTREAM.lock" or relative == "README.md")
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

function Snapshot.materialize(
	config: Config,
	repository: string,
	pin: Pin,
	scratch: string
): (Entries?, Entries?, string?)
	local resolved, problem =
		git({ "rev-parse", "--verify", "--end-of-options", pin.commit .. "^{commit}" }, repository)
	if resolved == nil then
		return nil, nil, problem
	end
	local commit = string.gsub(resolved, "%s+$", "")
	if commit ~= pin.commit then
		return nil, nil, config.name .. " pin must be a full commit identity"
	end
	local archive = Files.join(scratch, "snapshot.tar")
	local arguments = { "archive", "--format=tar", "-o", Files.absolute(archive), commit, "--" }
	for _, path in config.paths do
		table.insert(arguments, path)
	end
	table.insert(arguments, config.docsSource)
	local archived, failure = git(arguments, repository)
	if archived == nil then
		return nil, nil, failure
	end
	local files: Entries = {}
	local docs: Entries = {}
	local prefix = config.docsSource .. "/"
	for _, entry in Tar.read(Files.read(archive)) do
		if entry.kind ~= "file" then
			continue
		end
		local name, unsafe = Snapshot.safeMemberName(config, entry.name)
		if name == nil then
			return nil, nil, unsafe
		end
		if string.sub(name, 1, #prefix) == prefix then
			local relative = string.sub(name, #prefix + 1)
			docs[relative] = if config.relocateDocs and string.sub(name, -3) == ".md"
				then Snapshot.relocateGuide(config, entry.data, name, pin)
				else entry.data
		else
			local relative = if config.stripPrefix ~= ""
					and string.sub(name, 1, #config.stripPrefix) == config.stripPrefix
				then string.sub(name, #config.stripPrefix + 1)
				else name
			files[relative] = entry.data
		end
	end
	local license = files.LICENSE
	if license == nil then
		return nil, nil, config.name .. ": the archive has no LICENSE"
	end
	files["license.luau"] = "--!strict\nreturn [=[\n" .. license .. "\n]=]\n"
	return files, docs, nil
end

function Snapshot.fetch(config: Config, scratch: string, pin: Pin, source: string?): (string?, string?)
	if source ~= nil then
		return source, nil
	end
	local repository = Files.join(scratch, "repository")
	local initialized, problem = git({ "init", "--quiet", "--", repository })
	if initialized == nil then
		return nil, problem
	end
	local fetched, failure = git({ "fetch", "--depth=1", "--", pin.repository, pin.commit }, repository)
	if fetched == nil then
		return nil, failure
	end
	return repository, nil
end

export type Request = {
	check: boolean,
	contentOnly: boolean?,
	bump: string?,
	source: string?,
	materialize: Fetch?,
}

function Snapshot.sync(config: Config, request: Request): (number, string)
	local path = pinPath(config)
	if not Files.isFile(path) then
		return 1, ("%s: %s is missing"):format(config.name, pinLabel(config))
	end
	local document, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		return 1, ("%s: %s is not JSON: %s"):format(config.name, pinLabel(config), problem)
	end
	local object = Json.asObject(document)
	if object == nil then
		return 1, ("%s: %s is not a JSON object"):format(config.name, pinLabel(config))
	end
	if request.bump ~= nil then
		if request.check then
			return 1, config.name .. ": --bump and --check are different requests"
		end
		Json.set(object, "commit", request.bump)
	end
	local pin, refusal = Snapshot.checkedPin(config, object)
	if pin == nil then
		return 1, refusal or "invalid pin"
	end
	if request.bump == nil and Snapshot.verify(config, pin) then
		local executables = if request.contentOnly then {} else Snapshot.executables(config)
		if #executables == 0 then
			return 0, ("%s: pinned dependency verified %s"):format(config.name, pin.commit)
		elseif request.check then
			return 1,
				("%s: generated files must have mode 100644: %s; run lute run tools/facet sync %s"):format(
					config.name,
					table.concat(executables, ", "),
					string.lower(config.name)
				)
		end
		local failure = clearExecutables(config)
		if failure ~= nil then
			return 1, ("%s: %s"):format(config.name, failure)
		end
		return 0, ("%s: cleared the executable mode on %d generated files"):format(config.name, #executables)
	end
	if request.check then
		return 1,
			("%s: missing or modified dependency; run lute run tools/facet sync %s"):format(
				config.name,
				string.lower(config.name)
			)
	end
	local scratch = Files.temporaryDirectory("facet-" .. string.lower(config.name) .. "-")
	local files: Entries?, docs: Entries?, failure: string?
	local completed, raised = pcall(function()
		local injected = request.materialize
		if injected ~= nil then
			files, docs = injected(config, scratch, pin)
		else
			local repository, fetchFailure = Snapshot.fetch(config, scratch, pin, request.source)
			if repository == nil then
				failure = fetchFailure
			else
				files, docs, failure = Snapshot.materialize(config, repository, pin, scratch)
			end
		end
	end)
	Files.remove(scratch)
	if not completed then
		return 1, ("%s: %s"):format(config.name, tostring(raised))
	end
	if files == nil or docs == nil then
		return 1, failure or (config.name .. ": materialization failed")
	end
	local hashes = Snapshot.inventory(files)
	local guides = Snapshot.inventory(docs)
	if request.bump ~= nil then
		local recordedHashes = Json.object()
		local names: { string } = {}
		for name in hashes do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			Json.set(recordedHashes, name, hashes[name])
		end
		local recordedGuides = Json.object()
		local guideNames: { string } = {}
		for name in guides do
			table.insert(guideNames, name)
		end
		table.sort(guideNames)
		for _, name in guideNames do
			Json.set(recordedGuides, name, guides[name])
		end
		Json.set(object, "sha256", recordedHashes)
		Json.set(object, "docs", recordedGuides)
		pin.sha256 = hashes
		pin.docs = guides
	elseif not sameInventory(hashes, pin.sha256) or not sameInventory(guides, pin.docs) then
		return 1, config.name .. ": archive does not match pinned integrity inventory"
	end
	Snapshot.writeSnapshot(config, files, docs)
	if request.bump ~= nil then
		Files.write(path, Json.pretty(object))
	end
	if not Snapshot.verify(config, pin) then
		return 1, config.name .. " materialization did not match its pin"
	end
	local cleared = clearExecutables(config)
	if cleared ~= nil then
		return 1, ("%s: %s"):format(config.name, cleared)
	end
	return 0, ("%s: materialized %s"):format(config.name, pin.commit)
end

function Snapshot.check(root: string, name: Name): (boolean, string)
	local code, message = Snapshot.sync(Snapshot.config(root, name), { check = true })
	return code == 0, message
end

return table.freeze(Snapshot)
