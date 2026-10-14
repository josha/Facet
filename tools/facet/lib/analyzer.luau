--!strict

local Files = require("./files")

export type Diagnostic = {
	file: string,
	line: number,
	column: number,
	kind: string,
	message: string,
}

export type Platform = "roblox" | "standard"

export type Run = {
	targets: { string },
	name: string,
	extra: { string },
	platform: Platform,
	plugin: boolean,
	project: string?,
}

export type Project = {
	project: string,
	name: string,
	sourcemap: string,
	mapped: { string },
}

export type Classified = {
	owned: { Diagnostic },
	external: { Diagnostic },
}

local Analyzer = {}

Analyzer.LUTE_RUNTIME = {
	"tools/facet/",
	"tests/tools/",
	"tests/lute/",
	"tools/lute/",
	"tools/vendor/verify/src/lute/",
	"tools/vendor/verify/tools/",
}

Analyzer.VENDOR = { "src/vendor/", "tools/vendor/" }

Analyzer.KINDS = { TypeError = true, SyntaxError = true }

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

function Analyzer.isLute(path: string): boolean
	for _, prefix in Analyzer.LUTE_RUNTIME do
		if startsWith(path, prefix) then
			return true
		end
	end
	return false
end

function Analyzer.isOwnedSource(path: string): boolean
	return startsWith(path, "src/") and not startsWith(path, "src/vendor/")
end

function Analyzer.isPlugin(path: string): boolean
	return startsWith(path, "tools/designer/")
end

function Analyzer.isRepository(path: string): boolean
	return not (startsWith(path, "/") or startsWith(path, "../") or string.match(path, "^%a:/") ~= nil)
end

function Analyzer.isFirstParty(path: string): boolean
	if not Analyzer.isRepository(path) then
		return false
	end
	for _, prefix in Analyzer.VENDOR do
		if startsWith(path, prefix) then
			return false
		end
	end
	return true
end

function Analyzer.withoutVerbatimPrefix(path: string): string
	if string.sub(path, 1, 4) == "\\\\?\\" or string.sub(path, 1, 4) == "//?/" then
		return string.sub(path, 5)
	end
	return path
end

function Analyzer.relative(path: string, root: string): string
	local normalized = Files.normalize(Analyzer.withoutVerbatimPrefix(path))
	local absolute = startsWith(normalized, "/") or string.match(normalized, "^%a:/") ~= nil
	local resolved = Files.collapse(if absolute then normalized else Files.normalize(root) .. "/" .. normalized)
	local base = Files.collapse(root)
	local caseless = string.match(base, "^%a:/") ~= nil
	local comparedResolved = if caseless then string.lower(resolved) else resolved
	local comparedBase = if caseless then string.lower(base) else base
	if comparedResolved == comparedBase then
		return "."
	end
	local prefix = if string.sub(comparedBase, -1) == "/" then comparedBase else comparedBase .. "/"
	if string.sub(comparedResolved, 1, #prefix) == prefix then
		return string.sub(resolved, #prefix + 1)
	end
	return resolved
end

local function header(line: string): (string?, number?, number?, string?, string?)
	local search = 1
	while true do
		local start, finish, lineNumber, column, kind = string.find(line, "%((%d+),(%d+)%): ([%w_]+): ", search)
		if start == nil or finish == nil then
			return nil, nil, nil, nil, nil
		end
		local prefix = string.sub(line, 1, start - 1)
		local file = string.match(prefix, "^(.+%.luau?)$") or string.match(prefix, "^(.+%.luau?) %[[^%]]*%]$")
		if file ~= nil and lineNumber ~= nil and column ~= nil and kind ~= nil then
			return file, tonumber(lineNumber), tonumber(column), kind, string.sub(line, finish + 1)
		end
		search = start + 1
	end
end

local function isLogLine(line: string): boolean
	return string.match(line, "^%[[A-Z]+%] ") ~= nil
end

function Analyzer.key(diagnostic: Diagnostic): string
	return table.concat({
		diagnostic.file,
		tostring(diagnostic.line),
		tostring(diagnostic.column),
		diagnostic.kind,
		diagnostic.message,
	}, "\0")
end

function Analyzer.dedupe(diagnostics: { Diagnostic }): { Diagnostic }
	local seen: { [string]: boolean } = {}
	local unique: { Diagnostic } = {}
	for _, diagnostic in diagnostics do
		local key = Analyzer.key(diagnostic)
		if not seen[key] then
			seen[key] = true
			table.insert(unique, diagnostic)
		end
	end
	return unique
end

local function strip(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or text
end

function Analyzer.parse(output: string, root: string): { Diagnostic }
	local normalized = string.gsub(output, "\r\n", "\n")
	local diagnostics: { Diagnostic } = {}
	local current: Diagnostic? = nil
	local pieces: { string } = {}
	local function close()
		local open = current
		if open ~= nil then
			open.message = strip(table.concat(pieces, "\n"))
			if Analyzer.KINDS[open.kind] then
				table.insert(diagnostics, open)
			end
		end
		current = nil
		pieces = {}
	end
	for _, line in string.split(normalized, "\n") do
		local file, lineNumber, column, kind, message = header(line)
		if file ~= nil and lineNumber ~= nil and column ~= nil and kind ~= nil and message ~= nil then
			close()
			current = {
				file = Analyzer.relative(file, root),
				line = lineNumber,
				column = column,
				kind = kind,
				message = "",
			}
			table.insert(pieces, message)
		elseif current ~= nil and not isLogLine(line) then
			table.insert(pieces, line)
		end
	end
	close()
	return Analyzer.dedupe(diagnostics)
end

function Analyzer.missingStrict(text: string): boolean
	local normalized = string.gsub(text, "\r\n", "\n")
	if string.sub(normalized, 1, 10) ~= "--!strict\n" then
		return true
	end
	for _, line in string.split(normalized, "\n") do
		for _, directive in { "--!nocheck", "--!nonstrict" } do
			if
				string.sub(line, 1, #directive) == directive
				and string.match(string.sub(line, #directive + 1, #directive + 1), "^[%w_]$") == nil
			then
				return true
			end
		end
	end
	return false
end

function Analyzer.inventory(listing: string, isFile: (string) -> boolean): { string }
	local seen: { [string]: boolean } = {}
	local files: { string } = {}
	for _, path in string.split(listing, "\0") do
		if path ~= "" and not seen[path] and isFile(path) then
			seen[path] = true
			table.insert(files, path)
		end
	end
	table.sort(files)
	return files
end

function Analyzer.partition(files: { string }): ({ string }, { string })
	local roblox: { string } = {}
	local lute: { string } = {}
	for _, path in files do
		table.insert(if Analyzer.isLute(path) then lute else roblox, path)
	end
	return roblox, lute
end

function Analyzer.plan(files: { string }, projects: { Project }): { Run }
	local targets: { [string]: boolean } = {}
	for _, path in files do
		targets[path] = true
	end
	local covered: { [string]: boolean } = {}
	local runs: { Run } = {}
	for _, project in projects do
		local mapped: { [string]: boolean } = {}
		for _, path in project.mapped do
			mapped[path] = true
		end
		local selected: { string } = {}
		for path in targets do
			if mapped[path] then
				table.insert(selected, path)
			end
		end
		table.sort(selected)
		if #selected == 0 then
			continue
		end
		for _, path in selected do
			covered[path] = true
		end
		for _, plugin in { false, true } do
			local group: { string } = {}
			for _, path in selected do
				if Analyzer.isPlugin(path) == plugin then
					table.insert(group, path)
				end
			end
			if #group > 0 then
				local planned: Run = {
					targets = group,
					name = project.name .. (if plugin then "-plugin" else ""),
					extra = { "--sourcemap=" .. project.sourcemap },
					platform = "roblox",
					plugin = plugin,
					project = project.project,
				}
				table.insert(runs, planned)
			end
		end
	end
	local remaining: { string } = {}
	for path in targets do
		if not covered[path] then
			table.insert(remaining, path)
		end
	end
	table.sort(remaining)
	for _, plugin in { false, true } do
		local group: { string } = {}
		for _, path in remaining do
			if Analyzer.isPlugin(path) == plugin then
				table.insert(group, path)
			end
		end
		if #group > 0 then
			local planned: Run = {
				targets = group,
				name = if plugin then "unmapped-plugin" else "unmapped",
				extra = {},
				platform = "roblox",
				plugin = plugin,
				project = nil,
			}
			table.insert(runs, planned)
		end
	end
	return runs
end

function Analyzer.classify(
	run: Run,
	diagnostics: { Diagnostic },
	public: boolean,
	targets: { [string]: boolean }
): Classified
	local owned: { Diagnostic } = {}
	local external: { Diagnostic } = {}
	for _, diagnostic in diagnostics do
		local blocking = if run.platform == "standard"
			then (if public then Analyzer.isFirstParty(diagnostic.file) else targets[diagnostic.file] == true)
			else (if public then Analyzer.isRepository(diagnostic.file) else targets[diagnostic.file] == true)
		table.insert(if blocking then owned else external, diagnostic)
	end
	return { owned = owned, external = external }
end

function Analyzer.merge(results: { Classified }): Classified
	local owned: { Diagnostic } = {}
	local external: { Diagnostic } = {}
	for _, result in results do
		table.move(result.owned, 1, #result.owned, #owned + 1, owned)
		table.move(result.external, 1, #result.external, #external + 1, external)
	end
	owned = Analyzer.dedupe(owned)
	local ownedKeys: { [string]: boolean } = {}
	for _, diagnostic in owned do
		ownedKeys[Analyzer.key(diagnostic)] = true
	end
	local dependencies: { Diagnostic } = {}
	for _, diagnostic in Analyzer.dedupe(external) do
		if not ownedKeys[Analyzer.key(diagnostic)] then
			table.insert(dependencies, diagnostic)
		end
	end
	return { owned = owned, external = dependencies }
end

function Analyzer.chunks(files: { string }, budget: number): { { string } }
	local chunks: { { string } } = {}
	local current: { string } = {}
	local used = 0
	for _, path in files do
		local cost = #path + 3
		if #current > 0 and used + cost > budget then
			table.insert(chunks, current)
			current = {}
			used = 0
		end
		table.insert(current, path)
		used += cost
	end
	if #current > 0 then
		table.insert(chunks, current)
	end
	return chunks
end

function Analyzer.publicNames(source: string): { string }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	local position = 1
	while true do
		local start, finish, name = string.find(source, "UI%.([%w_]+)%s*=", position)
		if start == nil or finish == nil or name == nil then
			break
		end
		local before = if start > 1 then string.sub(source, start - 1, start - 1) else ""
		if string.match(before, "[%w_]") == nil and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
		position = start + 1
	end
	table.sort(names)
	return names
end

function Analyzer.named(code: string): string
	local replaced = string.gsub(code, "UI%.([%w_]+)%({", 'UI.%1("Typed")({', 1)
	return replaced
end

function Analyzer.truncate(text: string, limit: number): string
	local cut = utf8.offset(text, limit + 1)
	if cut == nil or cut > #text then
		return text
	end
	return string.sub(text, 1, cut - 1)
end

return table.freeze(Analyzer)
