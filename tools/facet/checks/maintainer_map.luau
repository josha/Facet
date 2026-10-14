--!strict

local stringext = require("@std/stringext")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Luau = require("../lib/luau")
local Markdown = require("../lib/markdown")
local Rule = require("../lib/rule")

local MAP = "docs/MAINTAINERS.md"
local MAP_DIRECTORY = "docs"
local SRC = "src"
local TESTS = "tests"
local SCENARIO_DIRECTORY = "examples/gallery/scenarios"
local SCENARIO_INDEX = SCENARIO_DIRECTORY .. "/init.luau"
local PLAYBOOKS = "docs/extending"
local IGNORE_FILE = ".gitignore"
local SURFACE = "tools/public_surface.txt"
local COMMAND_REGISTRY = "tools/facet/commands/init.luau"
local RULE_REGISTRY = "tools/facet/checks/init.luau"
local FACET = "tools/facet"
local EM_DASH = "\u{2014}"

local AREA_MARKER = "<!-- maintainer-map:areas -->"
local PROOF_MARKER = "<!-- maintainer-map:proof -->"
local TREE_MARKER = "<!-- maintainer-map:tree -->"
local QUICK_MARKER = "<!-- maintainer-map:quick -->"

local CHECK_FLAGS: { [string]: boolean } = { selftest = true, all = true, list = true, help = true, json = true }
local CHECK_VALUES: { [string]: boolean } = { root = true }

local OBLIGATIONS = {
	"every module under src/ (read from disk) is owned by exactly one area row",
	"every src path an area row owns exists, and no path has two owners",
	"the area table and the proof table name the same areas in the same order",
	"every spec a proof row names exists and requires, in one hop, a module of that row's area",
	'every Studio scenario named exists and is registered, or the cell says "None ' .. EM_DASH .. ' <reason>"',
	"every top-level directory (read from disk, less .gitignore directories) has a row in the tree table",
	"every repository path in a code span of the map exists",
	"every `lute run tools/facet <command>` in a code span names a registered command, and every `check` names registered rules and flags",
	"every quick answer links the page that carries the rest of the answer",
	"every local link resolves, and a link with an anchor lands on a real heading",
	"every page under docs/extending is linked by the map",
	"every Facet.<name> in the public-seam column is a root member listed in tools/public_surface.txt",
}

type Row = { cells: { string }, line: number }

type Ownership = { files: { [string]: string }, directories: { [string]: string } }

type Registered = { actions: { [string]: boolean }, values: { [string]: boolean } }

type Registry = { commands: { [string]: Registered }, rules: { [string]: Registered } }

export type Counts = {
	areas: number,
	srcModules: number,
	treeEntries: number,
	tests: number,
	scenarios: number,
	seams: number,
	paths: number,
	commands: number,
	links: number,
	playbooks: number,
}

export type Coverage = { area: string, specs: number }

local function backticked(cell: string): { string }
	local found: { string } = {}
	for token in string.gmatch(cell, "`([^`]+)`") do
		table.insert(found, token)
	end
	return found
end

local function areaName(cell: string): string
	local stripped = string.gsub(cell, "%*", "")
	return stringext.trim(stripped)
end

local function tableAfter(lines: { string }, marker: string): { Row }?
	local start: number? = nil
	for index, line in lines do
		if string.find(line, marker, 1, true) ~= nil then
			start = index
			break
		end
	end
	if start == nil then
		return nil
	end
	local rows: { Row } = {}
	local started = false
	for index = start, #lines do
		local line = stringext.trim(lines[index])
		if string.sub(line, 1, 1) == "|" then
			started = true
			if string.match(line, "^[|%s:-]+$") == nil then
				local cells: { string } = {}
				for cell in string.gmatch(line, "|([^|]*)") do
					table.insert(cells, stringext.trim(cell))
				end
				if #cells > 0 and cells[#cells] == "" then
					table.remove(cells)
				end
				table.insert(rows, { cells = cells, line = index })
			end
		elseif started then
			break
		end
	end
	if #rows > 0 then
		table.remove(rows, 1)
	end
	return rows
end

local function sourceModules(context: Rule.Context): { string }
	local found: { string } = {}
	for _, relative in Files.walk(context.path(SRC)) do
		if string.sub(relative, -5) == ".luau" then
			table.insert(found, SRC .. "/" .. relative)
		end
	end
	return found
end

local function ignoredTopLevel(context: Rule.Context): { [string]: boolean }
	local ignored: { [string]: boolean } = {}
	local path = context.path(IGNORE_FILE)
	if not Files.isFile(path) then
		return ignored
	end
	for _, line in Files.lines(Files.text(path)) do
		local name = string.match(stringext.trim(line), "^/?([%w_.-]+)/$")
		if name ~= nil then
			ignored[name] = true
		end
	end
	return ignored
end

local function rootDirectories(context: Rule.Context): { string }
	local found: { string } = {}
	for _, entry in Files.list(context.root) do
		if string.sub(entry.name, 1, 1) ~= "." and Files.isDirectory(context.path(entry.name)) then
			table.insert(found, entry.name)
		end
	end
	return found
end

local function moduleFile(context: Rule.Context, resolved: string): string?
	if Files.isFile(context.path(resolved .. ".luau")) then
		return resolved .. ".luau"
	end
	if Files.isFile(context.path(resolved .. "/init.luau")) then
		return resolved .. "/init.luau"
	end
	return nil
end

local function requiredPaths(source: string): { string }
	local found: { string } = {}
	local parsed = Luau.parse(source)
	if parsed == nil then
		for target in string.gmatch(source, 'require%(%s*"([^"]+)"%s*%)') do
			table.insert(found, target)
		end
		return found
	end
	for _, required in Luau.requires(parsed) do
		if not required.dynamic then
			table.insert(found, required.path)
		end
	end
	return found
end

local function requiredModules(context: Rule.Context, file: string): { string }
	local found: { string } = {}
	local path = context.path(file)
	if not Files.isFile(path) then
		return found
	end
	local directory = Markdown.directoryOf(file)
	for _, target in requiredPaths(Files.text(path)) do
		if string.sub(target, 1, 1) == "@" then
			continue
		end
		local resolved = Markdown.normalize(directory .. "/" .. target)
		if resolved ~= SRC and not stringext.hasPrefix(resolved, SRC .. "/") then
			continue
		end
		local module = moduleFile(context, resolved)
		if module ~= nil then
			table.insert(found, module)
		end
	end
	return found
end

local function ownerOf(ownership: Ownership, file: string): string?
	local direct = ownership.files[file]
	if direct ~= nil then
		return direct
	end
	local best: string? = nil
	local bestLength = 0
	for directory, area in ownership.directories do
		if stringext.hasPrefix(file, directory) and #directory > bestLength then
			best = area
			bestLength = #directory
		end
	end
	return best
end

local function pathExists(context: Rule.Context, word: string): boolean
	local bare = if string.sub(word, -1) == "/" then string.sub(word, 1, -2) else word
	local path = context.path(bare)
	return Files.isFile(path) or Files.isDirectory(path) or Files.isFile(path .. ".luau")
end

local function publicMembers(context: Rule.Context): { [string]: boolean }?
	local path = context.path(SURFACE)
	if not Files.isFile(path) then
		return nil
	end
	local members: { [string]: boolean } = {}
	for _, line in Files.lines(Files.text(path)) do
		local member = string.match(line, "^([%a_][%w_]*) : ")
		if member ~= nil then
			members[member] = true
		end
	end
	return members
end

local function returnedTable(parsed: Luau.Parsed): Luau.Node?
	local statements = Luau.items(parsed.root, "statements")
	local last = statements[#statements]
	if last == nil or Luau.tag(last) ~= "return" then
		return nil
	end
	local returned = Luau.items(last, "expressions")[1]
	if returned == nil then
		return nil
	end
	if Luau.tag(returned) == "table" then
		return returned
	end
	local name = if Luau.tag(returned) == "local"
		then Luau.tokenText(returned, "token")
		elseif Luau.tag(returned) == "global" then Luau.tokenText(returned, "name")
		else nil
	if name == nil then
		return nil
	end
	local found: Luau.Node? = nil
	for _, statement in statements do
		local tag = Luau.tag(statement)
		if tag == "local" then
			local values = Luau.items(statement, "values")
			for index, variable in Luau.items(statement, "variables") do
				local value = values[index]
				if Luau.tokenText(variable, "name") == name and value ~= nil and Luau.tag(value) == "table" then
					found = value
				end
			end
		elseif tag == "assign" then
			local values = Luau.items(statement, "values")
			for index, variable in Luau.items(statement, "variables") do
				local value = values[index]
				local assigned = if Luau.tag(variable) == "local"
					then Luau.tokenText(variable, "token")
					elseif Luau.tag(variable) == "global" then Luau.tokenText(variable, "name")
					else nil
				if assigned == name and value ~= nil and Luau.tag(value) == "table" then
					found = value
				end
			end
		end
	end
	return found
end

local function recordField(tableNode: Luau.Node, key: string): Luau.Node?
	for _, entry in Luau.items(tableNode, "entries") do
		if Luau.kind(entry) == "record" and Luau.tokenText(entry, "key") == key then
			return Luau.child(entry, "value")
		end
	end
	return nil
end

local function recordKeys(tableNode: Luau.Node?): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	if tableNode == nil or Luau.tag(tableNode) ~= "table" then
		return keys
	end
	for _, entry in Luau.items(tableNode, "entries") do
		if Luau.kind(entry) == "record" then
			local key = Luau.tokenText(entry, "key")
			if key ~= nil then
				keys[key] = true
			end
		elseif Luau.kind(entry) == "general" then
			local key = Luau.child(entry, "key")
			local value = if key ~= nil then Luau.stringValue(key) else nil
			if value ~= nil then
				keys[value] = true
			end
		end
	end
	return keys
end

local function listStrings(tableNode: Luau.Node?): { [string]: boolean }
	local strings: { [string]: boolean } = {}
	if tableNode == nil or Luau.tag(tableNode) ~= "table" then
		return strings
	end
	for _, entry in Luau.items(tableNode, "entries") do
		local value = if Luau.kind(entry) == "list" then Luau.child(entry, "value") else nil
		local text = if value ~= nil then Luau.stringValue(value) else nil
		if text ~= nil then
			strings[text] = true
		end
	end
	return strings
end

local function registeredModules(context: Rule.Context, registry: string): { [string]: Registered }
	local found: { [string]: Registered } = {}
	local path = context.path(registry)
	if not Files.isFile(path) then
		return found
	end
	local parsed = Luau.parse(Files.text(path))
	if parsed == nil then
		return found
	end
	local directory = Markdown.directoryOf(registry)
	for _, required in Luau.requires(parsed) do
		local module = string.match(required.path, "^@self/(.+)$") or string.match(required.path, "^%./(.+)$")
		if module == nil or required.dynamic then
			continue
		end
		local file = moduleFile(context, directory .. "/" .. module)
		if file == nil then
			continue
		end
		local moduleParsed = Luau.parse(Files.text(context.path(file)))
		local returned = if moduleParsed ~= nil then returnedTable(moduleParsed) else nil
		if returned == nil then
			continue
		end
		local nameNode = recordField(returned, "name")
		local name = if nameNode ~= nil then Luau.stringValue(nameNode) else nil
		if name ~= nil then
			found[name] = {
				actions = recordKeys(recordField(returned, "actions")),
				values = listStrings(recordField(returned, "values")),
			}
		end
	end
	return found
end

local function registry(context: Rule.Context): Registry
	return {
		commands = registeredModules(context, COMMAND_REGISTRY),
		rules = registeredModules(context, RULE_REGISTRY),
	}
end

local function placeholder(word: string): boolean
	return string.find(word, "[%*<>{}]") ~= nil
end

local function commandProblems(words: { string }, start: number, known: Registry): { string }
	local problems: { string } = {}
	local command = words[start]
	if command == nil or placeholder(command) or command == "help" then
		return problems
	end
	if known.commands[command] == nil then
		table.insert(problems, ("names the facet command '%s', which %s does not register"):format(command, FACET))
		return problems
	end
	if command ~= "check" then
		return problems
	end
	local named: { Registered } = {}
	local flags: { string } = {}
	local valueFlags: { [string]: boolean } = table.clone(CHECK_VALUES)
	for _, registered in known.rules do
		for value in registered.values do
			valueFlags[value] = true
		end
	end
	local index = start + 1
	while index <= #words do
		local word = words[index]
		local flag, assigned = string.match(word, "^%-%-([%w%-]+)(=?)")
		if placeholder(word) then
			index += 1
		elseif flag ~= nil then
			table.insert(flags, flag)
			index += if valueFlags[flag] and assigned == "" then 2 else 1
		else
			local rule = known.rules[word]
			if rule == nil then
				table.insert(problems, ("names the rule '%s', which %s does not register"):format(word, RULE_REGISTRY))
			else
				table.insert(named, rule)
			end
			index += 1
		end
	end
	for _, flag in flags do
		local accepted = CHECK_FLAGS[flag] == true or valueFlags[flag] == true
		for _, rule in named do
			if rule.actions[flag] then
				accepted = true
			end
		end
		if not accepted then
			table.insert(problems, ("passes '--%s' to `check`, which no named rule takes"):format(flag))
		end
	end
	return problems
end

local function inspect(context: Rule.Context): ({ string }, Counts)
	local problems: { string } = {}
	local counts: Counts = {
		areas = 0,
		srcModules = 0,
		treeEntries = 0,
		tests = 0,
		scenarios = 0,
		seams = 0,
		paths = 0,
		commands = 0,
		links = 0,
		playbooks = 0,
	}
	local function problem(line: number?, what: string, fix: string)
		local location = if line ~= nil then ("%s:%d"):format(MAP, line) else MAP
		table.insert(problems, ("%s: %s. Fix: %s."):format(location, what, fix))
	end

	local mapPath = context.path(MAP)
	if not Files.isFile(mapPath) then
		problem(nil, "the maintainer map is missing", "write " .. MAP)
		return problems, counts
	end
	local source = Files.text(mapPath)
	local lines = string.split(source, "\n")

	local areaRows = tableAfter(lines, AREA_MARKER)
	local proofRows = tableAfter(lines, PROOF_MARKER)
	local treeRows = tableAfter(lines, TREE_MARKER)
	local quickRows = tableAfter(lines, QUICK_MARKER)
	if areaRows == nil or proofRows == nil or treeRows == nil or quickRows == nil then
		problem(
			nil,
			"a table marker is missing, so a table could not be found",
			("keep %s, %s, %s and %s above their tables"):format(AREA_MARKER, PROOF_MARKER, TREE_MARKER, QUICK_MARKER)
		)
		return problems, counts
	end

	local members = publicMembers(context)
	if members == nil then
		problem(
			nil,
			("%s is missing, so the public seams cannot be checked"):format(SURFACE),
			"restore it with the public-surface producer"
		)
	end

	local ownership: Ownership = { files = {}, directories = {} }
	local areaOrder: { string } = {}
	for _, row in areaRows do
		local cells = row.cells
		if #cells < 4 then
			problem(
				row.line,
				("the area row '%s' does not have four columns"):format(cells[1] or ""),
				"give it: area, owns, responsibility, public seam"
			)
			continue
		end
		local area = areaName(cells[1])
		table.insert(areaOrder, area)
		for _, token in backticked(cells[2]) do
			if not stringext.hasPrefix(token, SRC .. "/") then
				problem(
					row.line,
					("the '%s' row owns '%s', which is not under src/"):format(area, token),
					"claim only src modules and directories"
				)
				continue
			end
			if string.sub(token, -1) == "/" then
				if not Files.isDirectory(context.path(string.sub(token, 1, -2))) then
					problem(
						row.line,
						("the '%s' row owns '%s', which does not exist"):format(area, token),
						"delete the claim, or restore the directory"
					)
				end
				local previous = ownership.directories[token]
				if previous ~= nil then
					problem(
						row.line,
						("'%s' is owned by both '%s' and '%s'"):format(token, previous, area),
						"give it one owner"
					)
				end
				ownership.directories[token] = area
			else
				if not Files.isFile(context.path(token)) then
					problem(
						row.line,
						("the '%s' row owns '%s', which does not exist"):format(area, token),
						"delete the claim, or restore the module"
					)
				end
				local previous = ownership.files[token]
				if previous ~= nil then
					problem(
						row.line,
						("'%s' is owned by both '%s' and '%s'"):format(token, previous, area),
						"give it one owner"
					)
				end
				ownership.files[token] = area
			end
		end
		for member in string.gmatch(cells[4], "`Facet%.([%w_]+)") do
			counts.seams += 1
			if members ~= nil and not members[member] then
				problem(
					row.line,
					("the '%s' row advertises the seam 'Facet.%s', which the library does not export"):format(
						area,
						member
					),
					"name an export the library has, or delete the claim"
				)
			end
		end
	end
	counts.areas = #areaOrder

	local ownedFiles: { string } = {}
	for file in ownership.files do
		table.insert(ownedFiles, file)
	end
	table.sort(ownedFiles)
	local ownedDirectories: { string } = {}
	for directory in ownership.directories do
		table.insert(ownedDirectories, directory)
	end
	table.sort(ownedDirectories)
	for _, file in ownedFiles do
		for _, directory in ownedDirectories do
			if stringext.hasPrefix(file, directory) then
				problem(nil, ("'%s' is owned directly and through '%s'"):format(file, directory), "give it one owner")
			end
		end
	end

	for _, file in sourceModules(context) do
		counts.srcModules += 1
		if ownerOf(ownership, file) == nil then
			problem(nil, ("%s is not owned by any area row"):format(file), "add it to the area that owns it")
		end
	end

	local proofByArea: { [string]: Row } = {}
	local proofOrder: { string } = {}
	for _, row in proofRows do
		if #row.cells < 1 then
			continue
		end
		local area = areaName(row.cells[1])
		table.insert(proofOrder, area)
		proofByArea[area] = row
	end
	if #proofOrder ~= #areaOrder then
		problem(
			nil,
			("the area table has %d rows and the proof table has %d"):format(#areaOrder, #proofOrder),
			"give every area one row in each table"
		)
	end
	for index, area in areaOrder do
		if proofOrder[index] ~= area then
			problem(
				nil,
				("row %d is '%s' in the area table and '%s' in the proof table"):format(
					index,
					area,
					tostring(proofOrder[index])
				),
				"keep both tables in the same order"
			)
		end
	end

	local registeredScenarios: { [string]: boolean } = {}
	local indexPath = context.path(SCENARIO_INDEX)
	if Files.isFile(indexPath) then
		local indexSource = Files.text(indexPath)
		local parsed = Luau.parse(indexSource)
		if parsed ~= nil then
			for _, literal in Luau.strings(parsed) do
				registeredScenarios[literal.value] = true
			end
		else
			for name in string.gmatch(indexSource, '"([^"\n]*)"') do
				registeredScenarios[name] = true
			end
		end
	end

	for _, area in areaOrder do
		local row = proofByArea[area]
		if row == nil or #row.cells < 4 then
			problem(
				if row then row.line else nil,
				("the proof row for '%s' does not have four columns"):format(area),
				"give it: area, tests, scenario, extend via"
			)
			continue
		end
		local tests, scenario = row.cells[2], row.cells[3]
		local named = 0
		for _, token in backticked(tests) do
			if string.sub(token, -10) ~= ".spec.luau" then
				continue
			end
			named += 1
			counts.tests += 1
			if not Files.isFile(context.path(token)) then
				problem(
					row.line,
					("the '%s' row names '%s', which does not exist"):format(area, token),
					"name a spec file that exists"
				)
				continue
			end
			local covers = false
			for _, file in requiredModules(context, token) do
				if ownerOf(ownership, file) == area then
					covers = true
					break
				end
			end
			if not covers then
				problem(
					row.line,
					("the '%s' row names '%s', which requires no module of that area"):format(area, token),
					"name a spec whose own requires reach this area"
				)
			end
		end
		if named == 0 then
			problem(
				row.line,
				("the '%s' row names no covering spec"):format(area),
				"name at least one spec that requires this area"
			)
		end
		local scenarioTokens = backticked(scenario)
		if #scenarioTokens == 0 then
			local reasoned = string.match(scenario, "^[Nn]one%s*%-") ~= nil
				or string.match(scenario, "^[Nn]one%s*" .. EM_DASH) ~= nil
			if not reasoned then
				problem(
					row.line,
					("the '%s' row names no Studio scenario and gives no reason"):format(area),
					('name a scenario, or write "None %s <reason>"'):format(EM_DASH)
				)
			end
		else
			for _, token in scenarioTokens do
				counts.scenarios += 1
				if not Files.isFile(context.path(("%s/%s.luau"):format(SCENARIO_DIRECTORY, token))) then
					problem(
						row.line,
						("the '%s' row names the scenario '%s', which is not a module in %s"):format(
							area,
							token,
							SCENARIO_DIRECTORY
						),
						"name a scenario that exists"
					)
				elseif not registeredScenarios[token] then
					problem(
						row.line,
						("the scenario '%s' is not registered in %s"):format(token, SCENARIO_INDEX),
						"register it, or name another"
					)
				end
			end
		end
	end

	local claimedTop: { [string]: boolean } = {}
	for _, row in treeRows do
		for _, token in backticked(row.cells[1] or "") do
			local name = string.match(token, "^([%w_.-]+)/$")
			if name == nil then
				problem(
					row.line,
					("the tree row claims '%s', which is not a top-level directory"):format(token),
					"write it as `<name>/`"
				)
				continue
			end
			claimedTop[name] = true
		end
	end
	local ignored = ignoredTopLevel(context)
	local roots: { [string]: boolean } = {}
	for _, name in rootDirectories(context) do
		roots[name] = true
		if ignored[name] then
			continue
		end
		counts.treeEntries += 1
		if not claimedTop[name] then
			problem(
				nil,
				("%s/ is a top-level directory that the tree table does not claim"):format(name),
				"add a row for it"
			)
		end
	end

	local known: Registry? = nil
	local spanCursor = 1
	while true do
		local start, finish, token = string.find(source, "`([^`]+)`", spanCursor)
		if start == nil or finish == nil or token == nil then
			break
		end
		spanCursor = finish + 1
		local line = Luau.lineOf(source, start)
		local words: { string } = {}
		for word in string.gmatch(token, "%S+") do
			table.insert(words, word)
		end
		for _, word in words do
			local head = string.match(word, "^([%w_.-]+)/")
			if head == nil or not roots[head] or placeholder(word) then
				continue
			end
			counts.paths += 1
			if not pathExists(context, word) then
				problem(
					line,
					("names the path '%s', which does not exist"):format(word),
					"fix the path, or restore the file"
				)
			end
		end
		for index = 1, #words - 2 do
			if words[index] == "lute" and words[index + 1] == "run" and words[index + 2] == FACET then
				counts.commands += 1
				if known == nil then
					known = registry(context)
				end
				for _, found in commandProblems(words, index + 3, known :: Registry) do
					problem(line, ("`%s` %s"):format(token, found), "name a registered command, rule or action")
				end
			end
		end
	end

	for index, row in quickRows do
		local cells = row.cells
		if #cells < 3 or string.find(cells[3], "](", 1, true) == nil then
			problem(
				row.line,
				("quick answer %d does not link the page that carries the rest of the answer"):format(index),
				"end it with a link"
			)
		end
	end

	local linkedPlaybooks: { [string]: boolean } = {}
	local anchorCache: { [string]: { [string]: boolean } } = {}
	local linkCursor = 1
	while true do
		local start, finish, target = string.find(source, "%]%(([^)]+)%)", linkCursor)
		if start == nil or finish == nil or target == nil then
			break
		end
		linkCursor = finish + 1
		if stringext.hasPrefix(target, "http") or stringext.hasPrefix(target, "#") then
			continue
		end
		counts.links += 1
		local line = Luau.lineOf(source, start)
		local path, anchor = string.match(target, "^([^#]*)#(.+)$")
		local resolved = Markdown.normalize(MAP_DIRECTORY .. "/" .. (path or target))
		local absolute = context.path(resolved)
		if not Files.isFile(absolute) and not Files.isDirectory(absolute) then
			problem(
				line,
				("links '%s', which resolves to '%s' and does not exist"):format(target, resolved),
				"fix the link"
			)
			continue
		end
		if string.match(resolved, "^docs/extending/.+%.md$") ~= nil then
			linkedPlaybooks[resolved] = true
		end
		if anchor ~= nil and string.sub(resolved, -3) == ".md" and Files.isFile(absolute) then
			local anchors = anchorCache[resolved]
			if anchors == nil then
				anchors = Markdown.anchors(Files.text(absolute))
				anchorCache[resolved] = anchors
			end
			if not anchors[anchor] then
				problem(
					line,
					("links '%s', but '%s' has no heading with that anchor"):format(target, resolved),
					"link a real heading"
				)
			end
		end
	end

	for _, entry in Files.list(context.path(PLAYBOOKS)) do
		if string.sub(entry.name, -3) ~= ".md" then
			continue
		end
		counts.playbooks += 1
		local playbook = PLAYBOOKS .. "/" .. entry.name
		if not linkedPlaybooks[playbook] then
			problem(nil, ("%s is an extension playbook that the map does not link"):format(playbook), "link it")
		end
	end

	return problems, counts
end

local function check(context: Rule.Context): { string }
	local problems = inspect(context)
	return problems
end

local function coverage(context: Rule.Context): { Coverage }
	local ordered: { Coverage } = {}
	local mapPath = context.path(MAP)
	if not Files.isFile(mapPath) then
		return ordered
	end
	local ownership: Ownership = { files = {}, directories = {} }
	local index: { [string]: Coverage } = {}
	local areaRows: { Row } = tableAfter(string.split(Files.text(mapPath), "\n"), AREA_MARKER) or {}
	for _, row in areaRows do
		if #row.cells < 2 then
			continue
		end
		local area = areaName(row.cells[1])
		local entry: Coverage = { area = area, specs = 0 }
		table.insert(ordered, entry)
		index[area] = entry
		for _, token in backticked(row.cells[2]) do
			if string.sub(token, -1) == "/" then
				ownership.directories[token] = area
			else
				ownership.files[token] = area
			end
		end
	end
	for _, relative in Files.walk(context.path(TESTS)) do
		if string.sub(relative, -10) ~= ".spec.luau" then
			continue
		end
		local hit: { [string]: boolean } = {}
		for _, file in requiredModules(context, TESTS .. "/" .. relative) do
			local area = ownerOf(ownership, file)
			if area ~= nil and not hit[area] and index[area] ~= nil then
				hit[area] = true
				index[area].specs += 1
			end
		end
	end
	return ordered
end

local function printCoverage(context: Rule.Context, _invocation: Cli.Invocation): number
	if not Files.isFile(context.path(MAP)) then
		print(("maintainer-map: %s is missing"):format(MAP))
		return 1
	end
	print("covering specs per area (one require hop out of each spec file):")
	for _, row in coverage(context) do
		print(("  %s: %d spec files"):format(row.area, row.specs))
	end
	return 0
end

local function printObligations(_context: Rule.Context, _invocation: Cli.Invocation): number
	print("maintainer-map enforces:")
	for index, obligation in OBLIGATIONS do
		print(("  %d. %s"):format(index, obligation))
	end
	return 0
end

local MAP_FIXTURE = table.concat({
	"# Map",
	"",
	AREA_MARKER,
	"",
	"| Area | Owns | Responsibility | Public seam |",
	"|---|---|---|---|",
	"| **root** | `src/init.luau`, `src/ui/` | Exports the table. | `Facet.controls` |",
	"| **themes** | `src/themes.luau` | Theme packages. | `Facet.themes` |",
	"",
	PROOF_MARKER,
	"",
	"| Area | Tests | Studio scenario | Extend via |",
	"|---|---|---|---|",
	"| **root** | `tests/root.spec.luau` | `all_controls` | [Adding a control](extending/new-control.md) |",
	"| **themes** | `tests/themes.spec.luau` | None "
		.. EM_DASH
		.. " a live suite covers it. | [Adding a control](extending/new-control.md) |",
	"",
	TREE_MARKER,
	"",
	"| Directory | Holds | Check |",
	"|---|---|---|",
	"| `src/` | The library. | `lute run tools/facet check doc-style maintainer-map` |",
	"| `tests/` | The specs. | `lute run tools/facet check maintainer-map --counts` |",
	"| `docs/` | The guide. | `lute run tools/facet check doc-style --warnings --root .` |",
	"| `examples/` | The gallery. | `lute run tools/facet version` |",
	"| `tools/` | The tools. | `lute run tools/facet check <rule> --selftest` and `tools/facet/init.luau` |",
	"",
	QUICK_MARKER,
	"",
	"| Question | Answer | Read |",
	"|---|---|---|",
	"| Where does a control go? | In its family. | [Adding a control](extending/new-control.md#steps) |",
	"",
}, "\n")

local function command(name: string, values: string?): string
	return ('local command = { name = "%s", values = { %s } }\nreturn command\n'):format(name, values or "")
end

local function fixture(): { [string]: string }
	return {
		[MAP] = MAP_FIXTURE,
		["src/init.luau"] = "return {}\n",
		["src/ui/button.luau"] = "return {}\n",
		["src/themes.luau"] = "return {}\n",
		["tests/root.spec.luau"] = 'local Facet = require("../src")\nreturn Facet\n',
		["tests/themes.spec.luau"] = "local themes = require('../src/themes')\nreturn themes\n",
		[SCENARIO_INDEX] = 'return { "all_controls" }\n',
		[SCENARIO_DIRECTORY .. "/all_controls.luau"] = "return {}\n",
		[SCENARIO_DIRECTORY .. "/unlisted.luau"] = "return {}\n",
		["docs/extending/new-control.md"] = "# Adding a control\n\n## Steps\n",
		[SURFACE] = "VERSION 1.0.0\nVERSION : string\ncontrols : function\nthemes : table\n  themes.define : function\ncontrols(runtime).Button : function\ntype Theme\n",
		[IGNORE_FILE] = "build/\n",
		["build/output.txt"] = "",
		["tools/facet/init.luau"] = "return nil\n",
		[COMMAND_REGISTRY] = 'local commands = { require("@self/version"), require("@self/check") }\nreturn commands\n',
		["tools/facet/commands/version.luau"] = command("version"),
		["tools/facet/commands/check.luau"] = command("check", '"root"'),
		[RULE_REGISTRY] = 'local rules = { require("@self/doc_style"), require("@self/maintainer_map") }\nreturn rules\n',
		["tools/facet/checks/doc_style.luau"] = 'local rule\nrule = { name = "doc-style", actions = { warnings = {} } }\nreturn rule\n',
		["tools/facet/checks/maintainer_map.luau"] = 'return { name = "maintainer-map", actions = { counts = {}, ["rules"] = {} } }\n',
	}
end

local function replaceOnce(text: string, find: string, replacement: string): string
	local start, finish = string.find(text, find, 1, true)
	if start == nil or finish == nil then
		error(("the fixture map does not contain '%s'"):format(find))
	end
	return string.sub(text, 1, start - 1) .. replacement .. string.sub(text, finish + 1)
end

local function dropLine(text: string, needle: string): string
	local kept: { string } = {}
	local dropped = false
	for _, line in string.split(text, "\n") do
		if not dropped and string.find(line, needle, 1, true) ~= nil then
			dropped = true
			continue
		end
		table.insert(kept, line)
	end
	if not dropped then
		error(("no fixture line contains '%s'"):format(needle))
	end
	return table.concat(kept, "\n")
end

local function planted(edit: (string) -> string, extra: { [string]: string }?, expected: string): string?
	local files = fixture()
	files[MAP] = edit(files[MAP])
	local additions: { [string]: string } = extra or {}
	for path, contents in additions do
		files[path] = contents
	end
	return Rule.within(files, function(context)
		local findings = check(context)
		if Rule.contains(findings, expected) then
			return nil
		end
		return ("expected a finding with '%s', got %s"):format(expected, Rule.describe(findings))
	end)
end

local function unchanged(text: string): string
	return text
end

local function cases(): { Rule.Case }
	return {
		{
			name = "the clean fixture passes and counts each table",
			run = function()
				return Rule.within(fixture(), function(context)
					local findings, counts = inspect(context)
					return Case.first(
						Case.same(findings, {}),
						Case.equal(counts.areas, 2, "areas"),
						Case.equal(counts.srcModules, 3, "src modules"),
						Case.equal(counts.treeEntries, 5, "top-level directories"),
						Case.equal(counts.seams, 2, "seams"),
						Case.equal(counts.commands, 5, "facet commands"),
						Case.equal(counts.playbooks, 1, "playbooks")
					)
				end)
			end,
		},
		{
			name = "an unowned module is reported",
			run = function()
				return planted(
					unchanged,
					{ ["src/extra.luau"] = "return {}\n" },
					"src/extra.luau is not owned by any area row"
				)
			end,
		},
		{
			name = "an owned module that does not exist is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`src/themes.luau`", "`src/no_such_module.luau`")
				end, nil, "the 'themes' row owns 'src/no_such_module.luau', which does not exist")
			end,
		},
		{
			name = "a module with two owners is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`src/init.luau`, ", "`src/init.luau`, `src/themes.luau`, ")
				end, nil, "'src/themes.luau' is owned by both 'root' and 'themes'")
			end,
		},
		{
			name = "a module owned directly and through its directory is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`src/themes.luau`", "`src/themes.luau`, `src/ui/button.luau`")
				end, nil, "'src/ui/button.luau' is owned directly and through 'src/ui/'")
			end,
		},
		{
			name = "an unmapped top-level directory is reported and an ignored one is not",
			run = function()
				return planted(
					unchanged,
					{ ["bench/scene.luau"] = "return {}\n" },
					"bench/ is a top-level directory that the tree table does not claim"
				) or planted(function(text)
					return dropLine(text, "| `examples/` |")
				end, nil, "examples/ is a top-level directory")
			end,
		},
		{
			name = "a missing repository path is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`tools/facet/init.luau`", "`tools/no_such_check.luau --check`")
				end, nil, "names the path 'tools/no_such_check.luau'")
			end,
		},
		{
			name = "an unregistered facet command, rule or action is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "facet version", "facet versions")
				end, nil, "names the facet command 'versions'") or planted(function(text)
					return replaceOnce(text, "check doc-style maintainer-map", "check doc-style no-such-rule")
				end, nil, "names the rule 'no-such-rule'") or planted(function(text)
					return replaceOnce(text, "maintainer-map --counts", "doc-style --counts")
				end, nil, "passes '--counts' to `check`, which no named rule takes")
			end,
		},
		{
			name = "a spec named under an area it does not cover is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`tests/root.spec.luau`", "`tests/themes.spec.luau`")
				end, nil, "the 'root' row names 'tests/themes.spec.luau', which requires no module of that area")
			end,
		},
		{
			name = "a missing, unregistered or unexplained scenario is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`all_controls`", "`no_such_scenario`")
				end, nil, "is not a module in examples/gallery/scenarios") or planted(function(text)
					return replaceOnce(text, "`all_controls`", "`unlisted`")
				end, nil, "the scenario 'unlisted' is not registered") or planted(function(text)
					return replaceOnce(text, "None " .. EM_DASH .. " a live suite covers it.", "Nothing yet.")
				end, nil, "the 'themes' row names no Studio scenario and gives no reason")
			end,
		},
		{
			name = "a public seam the library does not export is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "`Facet.themes`", "`Facet.themez`")
				end, nil, "advertises the seam 'Facet.themez', which the library does not export") or planted(
					function(text)
						return replaceOnce(text, "`Facet.themes`", "`Facet.define`")
					end,
					nil,
					"seam 'Facet.define'"
				)
			end,
		},
		{
			name = "a broken link or anchor is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "(extending/new-control.md)", "(extending/no-such-page.md)")
				end, nil, "resolves to 'docs/extending/no-such-page.md' and does not exist") or planted(
					function(text)
						return replaceOnce(text, "new-control.md#steps", "new-control.md#nowhere")
					end,
					nil,
					"has no heading with that anchor"
				)
			end,
		},
		{
			name = "an unlinked playbook is reported",
			run = function()
				return planted(
					unchanged,
					{ ["docs/extending/new-theme.md"] = "# Adding a theme\n" },
					"docs/extending/new-theme.md is an extension playbook that the map does not link"
				)
			end,
		},
		{
			name = "tables out of order are reported",
			run = function()
				return planted(function(text)
					return dropLine(text, "| **root** | `tests/")
				end, nil, "the area table has 2 rows and the proof table has 1")
			end,
		},
		{
			name = "a quick answer without a link is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, "[Adding a control](extending/new-control.md#steps)", "The playbook.")
				end, nil, "quick answer 1 does not link the page")
			end,
		},
		{
			name = "a missing marker, map or surface file is reported",
			run = function()
				return planted(function(text)
					return replaceOnce(text, QUICK_MARKER, "")
				end, nil, "a table marker is missing") or planted(
					unchanged,
					{ [SURFACE] = "" },
					"advertises the seam 'Facet.controls'"
				) or Rule.within({ ["src/init.luau"] = "return {}\n" }, function(context)
					return Case.expect(
						Rule.contains(check(context), "the maintainer map is missing"),
						"a missing map was not reported"
					)
				end)
			end,
		},
		{
			name = "CRLF line endings in the map pass like LF",
			run = function()
				local files = fixture()
				files[MAP] = string.gsub(files[MAP], "\n", "\r\n")
				return Rule.within(files, function(context)
					return Case.same(check(context), {})
				end)
			end,
		},
		{
			name = "the counts action reports the covering specs of each area",
			run = function()
				return Rule.within(fixture(), function(context)
					local rows = coverage(context)
					local shown: { string } = {}
					for _, row in rows do
						table.insert(shown, ("%s=%d"):format(row.area, row.specs))
					end
					return Case.same(shown, { "root=1", "themes=1" })
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "maintainer-map",
	summary = "docs/MAINTAINERS.md agrees with the tree: owners, proof, directories, paths, commands and links.",
	check = check,
	cases = cases,
	actions = {
		counts = {
			summary = "Print the number of covering specs for each area.",
			run = printCoverage,
		},
		rules = {
			summary = "Print each obligation that the rule enforces.",
			run = printObligations,
		},
	},
}

return rule
