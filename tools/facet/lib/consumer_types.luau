--!strict

local Analyzer = require("./analyzer")
local Definitions = require("./definitions")
local Files = require("./files")
local Hash = require("./hash")
local Json = require("./json")
local Run = require("./run")

local ConsumerTypes = {}
local DEFINITIONS = { "tools/typecheck/roblox.d.luau", "artifacts/verify/types/roblox.d.luau" }
local CACHE = "artifacts/facet-lint/types-cache.json"
local LOCK = "tools/typecheck/roblox.lock.json"
local FLAGS = { "--flag:LuauTarjanChildLimit=100000" }

local function fingerprint(
	paths: { string },
	project: string,
	solver: string,
	definitions: string,
	version: string
): string
	local parts: { string } = {
		"consumer-types-v2",
		"luau-lsp",
		version,
		solver,
		definitions,
		Files.read(definitions),
		Files.read(LOCK),
		Files.read(project),
		table.concat(FLAGS, "\n"),
	}
	if Files.isFile(".luaurc") then
		table.insert(parts, Files.read(".luaurc"))
	end
	local roots = table.clone(paths)
	for _, root in { "src", "Packages" } do
		if Files.isDirectory(root) and table.find(roots, root) == nil then
			table.insert(roots, root)
		end
	end
	for _, root in roots do
		if Files.isFile(root) then
			table.insert(parts, root .. "|" .. Files.read(root))
		elseif Files.isDirectory(root) then
			for _, file in Files.walk(root) do
				if string.match(file, "%.luau?$") or string.match(file, "%.luaurc$") then
					table.insert(parts, root .. "/" .. file .. "|" .. Files.read(Files.join(root, file)))
				end
			end
		end
	end
	table.sort(parts)
	return Hash.sha256(table.concat(parts, "\n"))
end

local function cached(key: string): { Analyzer.Diagnostic }?
	if not Files.isFile(CACHE) then
		return nil
	end
	local ok, stored = pcall(Json.decode, Files.read(CACHE))
	if not ok or Json.stringField(stored, "key") ~= key then
		return nil
	end
	local found: { Analyzer.Diagnostic } = {}
	local entries: Json.Array = Json.arrayField(stored, "diagnostics") or {}
	for _, entry in entries do
		table.insert(found, {
			file = Json.stringField(entry, "file") or "",
			line = Json.numberField(entry, "line") or 0,
			column = Json.numberField(entry, "column") or 0,
			kind = Json.stringField(entry, "kind") or "",
			message = Json.stringField(entry, "message") or "",
		})
	end
	return found
end

function ConsumerTypes.check(paths: { string }, project: string, solver: string): ({ Analyzer.Diagnostic }?, string?)
	local reported = Run.capture({ "luau-lsp", "--version" })
	if not reported.ok then
		return nil, "Pinned luau-lsp is missing; run rokit install"
	end
	local version = string.gsub(reported.stdout, "%s+$", "")
	local expected = Json.stringField(Json.decode(Files.read(LOCK)), "analyzerVersion")
	if version ~= expected then
		return nil, `Analyzer {version} differs from the pinned toolchain; run rokit install`
	end
	local definitions = DEFINITIONS[2]
	for _, candidate in DEFINITIONS do
		if Files.isFile(candidate) then
			definitions = candidate
			break
		end
	end
	local resolved, result = pcall(Definitions.resolve, LOCK, definitions)
	if not resolved then
		return nil, tostring(result)
	end
	if not Files.isFile(project) then
		return nil, "no Rojo project at " .. project
	end
	local key = fingerprint(paths, project, solver, definitions :: string, version)
	local reused = cached(key)
	if reused then
		return reused, nil
	end
	local directory = Files.temporaryDirectory("facet-lint")
	local sourcemap = Files.join(directory, "sourcemap.json")
	local built = Run.capture({ "rojo", "sourcemap", project, "--absolute", "-o", sourcemap }, { timeout = 120 })
	if not built.ok then
		return nil, "rojo sourcemap failed: " .. built.stderr
	end
	local function plain(node: unknown)
		local filePaths: Json.Array = Json.arrayField(node, "filePaths") or {}
		for index, file in filePaths do
			if type(file) == "string" then
				filePaths[index] = Analyzer.withoutVerbatimPrefix(file)
			end
		end
		local children: Json.Array = Json.arrayField(node, "children") or {}
		for _, child in children do
			plain(child)
		end
	end
	local tree = Json.decode(Files.read(sourcemap))
	plain(tree)
	Files.write(sourcemap, Json.encode(tree))
	local argv = {
		"luau-lsp",
		"analyze",
		"--platform",
		"roblox",
		"--definitions=" .. (definitions :: string),
		"--sourcemap=" .. sourcemap,
		"--flag:LuauSolverV2=" .. (if solver == "old" then "false" else "true"),
	}
	for _, flag in FLAGS do
		table.insert(argv, flag)
	end
	for _, path in paths do
		table.insert(argv, path)
	end
	local analyzed = Run.capture(argv, { timeout = 300 })
	pcall(Files.remove, directory)
	local parsed = Analyzer.parse(analyzed.stdout .. "\n" .. analyzed.stderr, Files.cwd())
	if not analyzed.ok and (#parsed == 0 or analyzed.timedOut or analyzed.code ~= 1) then
		return nil, `analyzer failed (exit {analyzed.code}): {analyzed.stdout}{analyzed.stderr}`
	end
	local owned: { Analyzer.Diagnostic } = {}
	for _, diagnostic in parsed do
		local file = string.lower(Files.absolute(diagnostic.file))
		for _, path in paths do
			local root = string.lower(Files.absolute(path))
			if file == root or string.sub(file, 1, #root + 1) == root .. "/" then
				table.insert(owned, diagnostic)
				break
			end
		end
	end
	local entries = Json.array()
	for _, diagnostic in owned do
		local entry = Json.object()
		Json.set(entry, "file", diagnostic.file)
		Json.set(entry, "line", diagnostic.line)
		Json.set(entry, "column", diagnostic.column)
		Json.set(entry, "kind", diagnostic.kind)
		Json.set(entry, "message", diagnostic.message)
		table.insert(entries, entry)
	end
	local stored = Json.object()
	Json.set(stored, "key", key)
	Json.set(stored, "diagnostics", entries)
	Files.write(CACHE, Json.encode(stored))
	return owned, nil
end

return ConsumerTypes
