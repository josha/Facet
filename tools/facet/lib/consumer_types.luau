--!strict

local Analyzer = require("./analyzer")
local Definitions = require("./definitions")
local Files = require("./files")
local Json = require("./json")
local Run = require("./run")

local ConsumerTypes = {}
local DEFINITIONS = { "tools/typecheck/roblox.d.luau", "artifacts/verify/types/roblox.d.luau" }

function ConsumerTypes.check(paths: { string }, project: string, solver: string): ({ Analyzer.Diagnostic }?, string?)
	local definitions = DEFINITIONS[2]
	for _, candidate in DEFINITIONS do
		if Files.isFile(candidate) then
			definitions = candidate
			break
		end
	end
	local resolved, result = pcall(Definitions.resolve, "tools/typecheck/roblox.lock.json", definitions)
	if not resolved then
		return nil, tostring(result)
	end
	if not Files.isFile(project) then
		return nil, "no Rojo project at " .. project
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
		"--flag:LuauTarjanChildLimit=100000",
		"--flag:LuauSolverV2=" .. (if solver == "old" then "false" else "true"),
	}
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
	return owned, nil
end

return ConsumerTypes
