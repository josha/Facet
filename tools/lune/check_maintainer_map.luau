--!strict
local fs = require("@lune/fs")

local liveFacet = require("../../src") :: any

local check_maintainer_map = {}

local MAP = "docs/MAINTAINERS.md"
local MAP_DIR = "docs"
local SRC = "src"
local SCENARIO_DIR = "examples/gallery/scenarios"
local SCENARIO_INDEX = SCENARIO_DIR .. "/init.luau"
local PLAYBOOKS = "docs/extending"
local IGNORE_FILE = ".gitignore"

local AREA_MARKER = "<!-- maintainer-map:areas -->"
local PROOF_MARKER = "<!-- maintainer-map:proof -->"
local TREE_MARKER = "<!-- maintainer-map:tree -->"
local QUICK_MARKER = "<!-- maintainer-map:quick -->"

export type Opts = {
	mapPath: string?,
	mapSource: string?,
}

export type Counts = {
	areas: number,
	srcModules: number,
	treeEntries: number,
	tests: number,
	scenarios: number,
	seams: number,
	paths: number,
	links: number,
	playbooks: number,
}

export type Result = {
	ok: boolean,
	problems: { string },
	counts: Counts,
}

export type Coverage = { area: string, specs: number }

local function splitLines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

local function trim(text: string): string
	return (string.match(text, "^%s*(.-)%s*$")) :: string
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function backticked(cell: string): { string }
	local out: { string } = {}
	for token in string.gmatch(cell, "`([^`]+)`") do
		table.insert(out, token)
	end
	return out
end

local function areaName(cell: string): string
	return trim((string.gsub(cell, "%*", "")))
end

local function tableAfter(lines: { string }, marker: string): { { string } }?
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
	local rows: { { string } } = {}
	local started = false
	for index = start :: number, #lines do
		local line = trim(lines[index])
		if string.sub(line, 1, 1) == "|" then
			started = true
			if string.match(line, "^[|%s:-]+$") == nil then
				local cells: { string } = {}
				for cell in string.gmatch(line, "|([^|]*)") do
					table.insert(cells, trim(cell))
				end
				if #cells > 0 and cells[#cells] == "" then
					table.remove(cells)
				end
				table.insert(rows, cells)
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

local function sourceModules(): { string }
	local out: { string } = {}
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isDir(path) then
				walk(path)
			elseif string.match(name, "%.luau$") ~= nil then
				table.insert(out, path)
			end
		end
	end
	walk(SRC)
	table.sort(out)
	return out
end

local function ignoredTopLevel(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if not fs.isFile(IGNORE_FILE) then
		return out
	end
	for _, line in splitLines(fs.readFile(IGNORE_FILE)) do
		local name = string.match(trim(line), "^/?([%w_.-]+)/$")
		if name ~= nil then
			out[name] = true
		end
	end
	return out
end

local function topLevelDirectories(): { string }
	local ignored = ignoredTopLevel()
	local out: { string } = {}
	for _, name in fs.readDir(".") do
		if string.sub(name, 1, 1) ~= "." and fs.isDir(name) and not ignored[name] then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

local function moduleFile(resolved: string): string?
	if fs.isFile(resolved .. ".luau") then
		return resolved .. ".luau"
	end
	if fs.isFile(resolved .. "/init.luau") then
		return resolved .. "/init.luau"
	end
	return nil
end

local function requiredModules(filePath: string): { string }
	local out: { string } = {}
	if not fs.isFile(filePath) then
		return out
	end
	local dir = string.match(filePath, "^(.*)/[^/]+$") or ""
	for target in string.gmatch(fs.readFile(filePath), [[require%(%s*"([^"]+)"%s*%)]]) do
		if string.sub(target, 1, 1) == "@" then
			continue
		end
		local resolved = normalize(dir .. "/" .. target)
		if resolved ~= SRC and string.sub(resolved, 1, #SRC + 1) ~= SRC .. "/" then
			continue
		end
		local file = moduleFile(resolved)
		if file ~= nil then
			table.insert(out, file)
		end
	end
	return out
end

local function headingAnchors(text: string): { [string]: boolean }
	local seen: { [string]: number } = {}
	local anchors: { [string]: boolean } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local heading = string.match(line, "^#+%s+(.-)%s*$")
		if heading ~= nil then
			local slug = string.lower(heading)
			slug = string.gsub(slug, "[`*]", "")
			slug = string.gsub(slug, "[^%w%s_-]", "")
			slug = string.gsub(slug, "%s", "-")
			local count = seen[slug] or 0
			anchors[if count == 0 then slug else `{slug}-{count}`] = true
			seen[slug] = count + 1
		end
	end
	return anchors
end

type Ownership = {
	files: { [string]: string },
	dirs: { [string]: string },
}

local function ownerOf(ownership: Ownership, file: string): string?
	local direct = ownership.files[file]
	if direct ~= nil then
		return direct
	end
	for dir, area in ownership.dirs do
		if string.sub(file, 1, #dir) == dir then
			return area
		end
	end
	return nil
end

local function pathExists(word: string): boolean
	local bare = if string.sub(word, -1) == "/" then string.sub(word, 1, -2) else word
	return fs.isFile(bare) or fs.isDir(bare) or fs.isFile(bare .. ".luau")
end

function check_maintainer_map.check(opts: Opts?): Result
	local options: Opts = opts or {}
	local mapPath = options.mapPath or MAP
	local problems: { string } = {}
	local counts: Counts = {
		areas = 0,
		srcModules = 0,
		treeEntries = 0,
		tests = 0,
		scenarios = 0,
		seams = 0,
		paths = 0,
		links = 0,
		playbooks = 0,
	}

	local function problem(what: string, fix: string)
		table.insert(problems, `{mapPath}: {what}\n      fix: {fix}`)
	end

	if options.mapSource == nil and not fs.isFile(mapPath) then
		problem("the maintainer map is missing", `write {MAP}`)
		return { ok = false, problems = problems, counts = counts }
	end
	local source = options.mapSource or fs.readFile(mapPath)
	local lines = splitLines(source)

	local areaRows = tableAfter(lines, AREA_MARKER)
	local proofRows = tableAfter(lines, PROOF_MARKER)
	local treeRows = tableAfter(lines, TREE_MARKER)
	local quickRows = tableAfter(lines, QUICK_MARKER)
	if areaRows == nil or proofRows == nil or treeRows == nil or quickRows == nil then
		problem(
			"a table marker is missing, so a table could not be found",
			`keep {AREA_MARKER}, {PROOF_MARKER}, {TREE_MARKER} and {QUICK_MARKER} above their tables`
		)
		return { ok = false, problems = problems, counts = counts }
	end

	local ownership: Ownership = { files = {}, dirs = {} }
	local areaOrder: { string } = {}
	for _, cells in areaRows :: { { string } } do
		if #cells < 4 then
			problem(
				`the area row '{cells[1] or ""}' does not have four columns`,
				"give it: area, owns, responsibility, public seam"
			)
			continue
		end
		local area = areaName(cells[1])
		table.insert(areaOrder, area)
		for _, token in backticked(cells[2]) do
			if string.sub(token, 1, #SRC + 1) ~= SRC .. "/" then
				problem(
					`the '{area}' row owns '{token}', which is not under src/`,
					"claim only src modules and directories"
				)
				continue
			end
			local isDir = string.sub(token, -1) == "/"
			if isDir then
				if not fs.isDir(string.sub(token, 1, -2)) then
					problem(
						`the '{area}' row owns '{token}', which does not exist`,
						"delete the claim, or restore the directory"
					)
				end
				if ownership.dirs[token] ~= nil then
					problem(`'{token}' is owned by both '{ownership.dirs[token]}' and '{area}'`, "give it one owner")
				end
				ownership.dirs[token] = area
			else
				if not fs.isFile(token) then
					problem(
						`the '{area}' row owns '{token}', which does not exist`,
						"delete the claim, or restore the module"
					)
				end
				if ownership.files[token] ~= nil then
					problem(`'{token}' is owned by both '{ownership.files[token]}' and '{area}'`, "give it one owner")
				end
				ownership.files[token] = area
			end
		end
		for member in string.gmatch(cells[4], "`Facet%.([%w_]+)") do
			counts.seams += 1
			if liveFacet[member] == nil then
				problem(
					`the '{area}' row advertises the seam 'Facet.{member}', which the library does not export`,
					"name an export the library has, or delete the claim"
				)
			end
		end
	end
	counts.areas = #areaOrder

	for file in ownership.files do
		for dir in ownership.dirs do
			if string.sub(file, 1, #dir) == dir then
				problem(`'{file}' is owned directly and through '{dir}'`, "give it one owner")
			end
		end
	end

	for _, file in sourceModules() do
		counts.srcModules += 1
		if ownerOf(ownership, file) == nil then
			problem(`{file} is not owned by any area row`, "add it to the area that owns it")
		end
	end

	local proofByArea: { [string]: { string } } = {}
	local proofOrder: { string } = {}
	for _, cells in proofRows :: { { string } } do
		if #cells < 1 then
			continue
		end
		local area = areaName(cells[1])
		table.insert(proofOrder, area)
		proofByArea[area] = cells
	end
	if #proofOrder ~= #areaOrder then
		problem(
			`the area table has {#areaOrder} rows and the proof table has {#proofOrder}`,
			"give every area one row in each table"
		)
	end
	for index, area in areaOrder do
		if proofOrder[index] ~= area then
			problem(
				`row {index} is '{area}' in the area table and '{tostring(proofOrder[index])}' in the proof table`,
				"keep both tables in the same order"
			)
		end
	end

	local scenarioIndex = if fs.isFile(SCENARIO_INDEX) then fs.readFile(SCENARIO_INDEX) else ""
	for _, area in areaOrder do
		local cells = proofByArea[area]
		if cells == nil or #cells < 4 then
			problem(
				`the proof row for '{area}' does not have four columns`,
				"give it: area, tests, scenario, extend via"
			)
			continue
		end
		local tests, scenario = cells[2], cells[3]

		local named = 0
		for _, token in backticked(tests) do
			if string.match(token, "%.spec%.luau$") == nil then
				continue
			end
			named += 1
			counts.tests += 1
			if not fs.isFile(token) then
				problem(`the '{area}' row names '{token}', which does not exist`, "name a spec file that exists")
				continue
			end
			local covers = false
			for _, file in requiredModules(token) do
				if ownerOf(ownership, file) == area then
					covers = true
					break
				end
			end
			if not covers then
				problem(
					`the '{area}' row names '{token}', which requires no module of that area`,
					"name a spec whose own requires reach this area"
				)
			end
		end
		if named == 0 then
			problem(`the '{area}' row names no covering spec`, "name at least one spec that requires this area")
		end

		local scenarioTokens = backticked(scenario)
		if #scenarioTokens == 0 then
			if string.match(scenario, "^[Nn]one%s*[—-]") == nil then
				problem(
					`the '{area}' row names no Studio scenario and gives no reason`,
					'name a scenario, or write "None — <reason>"'
				)
			end
		else
			for _, token in scenarioTokens do
				counts.scenarios += 1
				if not fs.isFile(`{SCENARIO_DIR}/{token}.luau`) then
					problem(
						`the '{area}' row names the scenario '{token}', which is not a module in {SCENARIO_DIR}`,
						"name a scenario that exists"
					)
				elseif string.find(scenarioIndex, `"{token}"`, 1, true) == nil then
					problem(
						`the scenario '{token}' is not registered in {SCENARIO_INDEX}`,
						"register it, or name another"
					)
				end
			end
		end
	end

	local claimedTop: { [string]: boolean } = {}
	for _, cells in treeRows :: { { string } } do
		for _, token in backticked(cells[1] or "") do
			local name = string.match(token, "^([%w_.-]+)/$")
			if name == nil then
				problem(`the tree row claims '{token}', which is not a top-level directory`, "write it as `<name>/`")
				continue
			end
			claimedTop[name] = true
		end
	end
	for _, name in topLevelDirectories() do
		counts.treeEntries += 1
		if not claimedTop[name] then
			problem(`{name}/ is a top-level directory that the tree table does not claim`, "add a row for it")
		end
	end

	local roots: { [string]: boolean } = {}
	for _, name in fs.readDir(".") do
		if string.sub(name, 1, 1) ~= "." and fs.isDir(name) then
			roots[name] = true
		end
	end
	for token in string.gmatch(source, "`([^`]+)`") do
		for word in string.gmatch(token, "%S+") do
			local head = string.match(word, "^([%w_.-]+)/")
			if head == nil or not roots[head] or string.find(word, "[%*<>{}]") ~= nil then
				continue
			end
			counts.paths += 1
			if not pathExists(word) then
				problem(`names the path '{word}', which does not exist`, "fix the path, or restore the file")
			end
		end
	end

	for index, cells in quickRows :: { { string } } do
		if #cells < 3 or string.find(cells[3], "](", 1, true) == nil then
			problem(
				`quick answer {index} does not link the page that carries the rest of the answer`,
				"end it with a link"
			)
		end
	end

	local linkedPlaybooks: { [string]: boolean } = {}
	for target in string.gmatch(source, "%]%(([^)]+)%)") do
		if string.sub(target, 1, 4) == "http" or string.sub(target, 1, 1) == "#" then
			continue
		end
		counts.links += 1
		local path, anchor = string.match(target, "^([^#]*)#(.+)$")
		if path == nil then
			path = target
		end
		local resolved = normalize(MAP_DIR .. "/" .. (path :: string))
		if not (fs.isFile(resolved) or fs.isDir(resolved)) then
			problem(`links '{target}', which resolves to '{resolved}' and does not exist`, "fix the link")
			continue
		end
		if string.match(resolved, "^docs/extending/.+%.md$") ~= nil then
			linkedPlaybooks[resolved] = true
		end
		if anchor ~= nil and string.match(resolved, "%.md$") ~= nil then
			if not headingAnchors(fs.readFile(resolved))[anchor :: string] then
				problem(`links '{target}', but '{resolved}' has no heading with that anchor`, "link a real heading")
			end
		end
	end

	if fs.isDir(PLAYBOOKS) then
		for _, name in fs.readDir(PLAYBOOKS) do
			if string.match(name, "%.md$") == nil then
				continue
			end
			counts.playbooks += 1
			if not linkedPlaybooks[`{PLAYBOOKS}/{name}`] then
				problem(`{PLAYBOOKS}/{name} is an extension playbook that the map does not link`, "link it")
			end
		end
	end

	return { ok = #problems == 0, problems = problems, counts = counts }
end

function check_maintainer_map.coverage(): { Coverage }
	local lines = splitLines(fs.readFile(MAP))
	local ownership: Ownership = { files = {}, dirs = {} }
	local ordered: { Coverage } = {}
	local index: { [string]: Coverage } = {}
	for _, cells in tableAfter(lines, AREA_MARKER) or {} do
		if #cells < 2 then
			continue
		end
		local area = areaName(cells[1])
		local row = { area = area, specs = 0 }
		table.insert(ordered, row)
		index[area] = row
		for _, token in backticked(cells[2]) do
			if string.sub(token, -1) == "/" then
				ownership.dirs[token] = area
			else
				ownership.files[token] = area
			end
		end
	end
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isDir(path) then
				walk(path)
			elseif string.match(name, "%.spec%.luau$") ~= nil then
				local hit: { [string]: boolean } = {}
				for _, file in requiredModules(path) do
					local area = ownerOf(ownership, file)
					if area ~= nil and not hit[area] then
						hit[area] = true
						index[area].specs += 1
					end
				end
			end
		end
	end
	walk("tests")
	return ordered
end

check_maintainer_map.OBLIGATIONS = table.freeze({
	"every module under src/ (read from disk) is owned by exactly one area row",
	"every src path an area row owns exists, and no path has two owners",
	"the area table and the proof table name the same areas in the same order",
	"every spec a proof row names exists and requires, in one hop, a module of that row's area",
	'every Studio scenario named exists and is registered, or the cell says "None — <reason>"',
	"every top-level directory (read from disk, less .gitignore directories) has a row in the tree table",
	"every repository path in a code span of the map exists",
	"every quick answer links the page that carries the rest of the answer",
	"every local link resolves, and a link with an anchor lands on a real heading",
	"every page under docs/extending is linked by the map",
	"every Facet.<name> in the public-seam column is a field of the exported library table",
})

return check_maintainer_map
