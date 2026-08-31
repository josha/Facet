--!strict
-- Drift check for the maintainer map (docs/MAINTAINERS.md; release-candidate
-- review row RC-11). The map answers "who owns this, what proves it, and how do
-- I extend it" for every production area. A map is only worth reading while it
-- is true, and every fact in it is already written down somewhere the build
-- reads, so every fact in it is checked against that place:
--
--   1. AREA COVERAGE. Every top-level entry under src/ — a directory, or a
--      module sitting directly in src/ — is claimed by exactly one row of the
--      area table. The list of entries is READ FROM DISK, never typed here, so
--      a new area is unmapped the moment it lands.
--   2. NO INVENTED AREA. Every `src/...` path the map claims exists.
--   3. THE TWO TABLES AGREE. The area table and the proof table name the same
--      areas in the same order, so a row cannot gain a responsibility without
--      gaining the evidence that holds it.
--   4. OWNER MODULES EXIST. Every backticked src module path anywhere in the
--      map is a real file.
--   5. TESTS REALLY COVER. Every spec named in a row's tests cell exists AND
--      names a module of that row's area in one of its own `require` calls.
--      That is the whole derivation rule the map publishes: coverage is the
--      require graph one hop out of the spec file, and a spec that reaches the
--      library only through `require("../src")` counts under the library root.
--   6. SCENARIOS EXIST. Every Studio scenario named is a module under
--      examples/gallery/scenarios AND is registered in that folder's init. An
--      area with no live surface must say so in the words `none —` plus a
--      reason, rather than leaving an empty cell.
--   7. GATES EXIST. Every `stage/row` the map cites is a real row of a real
--      stage in tools/lune/verify/graph.json, and every bare `stage` is a real
--      stage.
--   8. BOUNDARY RULES EXIST. Every dependency rule the map cites by name is a
--      rule tools/lune/check_boundary.luau really enforces, so the map cannot
--      claim an enforcement that was deleted.
--   9. LINKS RESOLVE. Every local markdown link resolves to a real path, and a
--      link carrying an anchor lands on a heading that document really has.
--  10. EVERY PLAYBOOK IS REACHABLE. Every page under docs/extending is linked
--      by the map, so a new extension path cannot ship unmapped.
--  11. THE PUBLIC SEAM IS LIVE. Every `Facet.<name>` the seam column advertises
--      is a field of the exported table, read from the table itself rather than
--      from a parsed literal — the same source check_docs reads. This is the
--      column a maintainer trusts most, so it is the one that must not be able
--      to name a rename victim.
--
-- check(opts?) -> { ok, problems, counts }. `opts.mapPath` points the check at
-- a COPY of the map, which is how the command-line selftest proves each rule
-- bites without touching the working tree. Same shape as check_docs.
--
-- CLI: tools/lune/check_maintainer_map_cli.luau (read-only; --selftest,
-- --counts, --list).

local fs = require("@lune/fs")
local serde = require("@lune/serde")

--[[ THE LIVE LIBRARY TABLE, not a parsed literal. The seam column claims that a
	name is public; the only honest source for "what is public" is the exported
	table, so this module requires it the same way tools/lune/check_docs does. A
	hand list here would be one more place a rename could fail to appear. ]]
local liveFacet = require("../../src") :: any

local check_maintainer_map = {}

local MAP = "docs/MAINTAINERS.md"
local SRC = "src"
local SCENARIO_DIR = "examples/gallery/scenarios"
local SCENARIO_INDEX = SCENARIO_DIR .. "/init.luau"
local GATES = "tools/lune/verify/graph.json"
local BOUNDARY = "tools/lune/check_boundary.luau"
local PLAYBOOKS = "docs/extending"

-- the three tables this checker reads, each introduced by a marker comment. A
-- marker is invisible in rendered markdown and unambiguous to a parser, which
-- is why the tables are found by marker rather than by counting pipes.
local AREA_MARKER = "<!-- maintainer-map:areas -->"
local PROOF_MARKER = "<!-- maintainer-map:proof -->"
local QUICK_MARKER = "<!-- maintainer-map:quick -->"

-- `mapPath` points the check at a COPY of the map on disk (the command-line
-- selftest's form: a real file, the same scan, nothing planted in the working
-- tree). `mapSource` hands it the text directly, which is the form the suite
-- uses so a test run writes nothing at all. Everything else — src/, tests/, the
-- scenarios, the gate manifest, the boundary checker — is always the live tree,
-- because those are the sources the map is being judged against.
export type Opts = {
	mapPath: string?,
	mapSource: string?,
}

export type Result = {
	ok: boolean,
	problems: { string },
	counts: {
		areas: number,
		srcEntries: number,
		tests: number,
		scenarios: number,
		gateRows: number,
		boundaryRules: number,
		seams: number,
		links: number,
		playbooks: number,
	},
}

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

-- resolve "a/b/../c" without touching the filesystem
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

-- the cells of the markdown table that follows `marker`, header row dropped and
-- alignment row dropped. Returns nil when the marker is absent.
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
				-- a trailing pipe leaves one empty cell; drop it
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
		table.remove(rows, 1) -- the header
	end
	return rows
end

-- `src/core/` -> "core"; `src/mount.luau` -> "mount". Anything else -> nil.
local function topEntryOf(path: string): string?
	local rest = string.match(path, "^src/(.+)$")
	if rest == nil then
		return nil
	end
	local dir = string.match(rest, "^([^/]+)/$")
	if dir ~= nil then
		return dir
	end
	local file = string.match(rest, "^([^/]+)%.luau$")
	if file ~= nil and string.find(rest, "/") == nil then
		return file
	end
	return nil
end

-- the src-relative modules a file requires, ONE HOP, resolved to a top-level
-- entry name. `require("../src")` resolves to the library root, whose top-level
-- entry is `init` — the same name the disk scan gives src/init.luau.
local function requiredEntries(filePath: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if not fs.isFile(filePath) then
		return out
	end
	local dir = string.match(filePath, "^(.*)/[^/]+$") or ""
	for target in string.gmatch(fs.readFile(filePath), [[require%(%s*"([^"]+)"%s*%)]]) do
		if string.sub(target, 1, 1) == "@" then
			continue
		end
		local resolved = normalize(dir .. "/" .. target)
		if resolved == SRC then
			out["init"] = true
			continue
		end
		local rest = string.match(resolved, "^src/(.+)$")
		if rest == nil then
			continue
		end
		local head = string.match(rest, "^([^/]+)") :: string
		if string.find(rest, "/") ~= nil then
			out[head] = true
		else
			out[head] = true
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

function check_maintainer_map.check(opts: Opts?): Result
	local options: Opts = opts or {}
	local mapPath = options.mapPath or MAP
	local problems: { string } = {}
	local counts = {
		areas = 0,
		srcEntries = 0,
		tests = 0,
		scenarios = 0,
		gateRows = 0,
		boundaryRules = 0,
		seams = 0,
		links = 0,
		playbooks = 0,
	}

	local function problem(what: string, fix: string)
		table.insert(problems, `{mapPath}: {what}\n      fix: {fix}`)
	end

	if options.mapSource == nil and not fs.isFile(mapPath) then
		problem("the maintainer map is missing", `write {MAP}, the map every area row is checked against`)
		return { ok = false, problems = problems, counts = counts }
	end
	local source = options.mapSource or fs.readFile(mapPath)
	local lines = splitLines(source)

	local areaRows = tableAfter(lines, AREA_MARKER)
	local proofRows = tableAfter(lines, PROOF_MARKER)
	local quickRows = tableAfter(lines, QUICK_MARKER)
	if areaRows == nil or proofRows == nil or quickRows == nil then
		problem(
			"one of the three marker comments is missing, so a table could not be found",
			`keep {AREA_MARKER}, {PROOF_MARKER} and {QUICK_MARKER} above their tables`
		)
		return { ok = false, problems = problems, counts = counts }
	end

	-- ---- 1/2. the areas, and the src tree they claim ------------------------
	local claimed: { [string]: string } = {} -- top entry -> area name
	local areaOrder: { string } = {}
	local ownedBy: { [string]: { [string]: boolean } } = {} -- area -> top entries
	for _, cells in areaRows :: { { string } } do
		if #cells < 2 then
			continue
		end
		local area = trim((string.gsub(cells[1], "%*", "")))
		table.insert(areaOrder, area)
		ownedBy[area] = {}
		for _, token in backticked(cells[2]) do
			local entry = topEntryOf(token)
			if entry == nil then
				problem(
					`the '{area}' row claims '{token}', which is not a top-level src path`,
					"write a directory as `src/<name>/` and a root module as `src/<name>.luau`"
				)
				continue
			end
			local onDisk = string.sub(token, -1) == "/"
			local exists = if onDisk then fs.isDir(string.sub(token, 1, -2)) else fs.isFile(token)
			if not exists then
				problem(
					`the '{area}' row claims '{token}', which does not exist`,
					"delete the claim, or restore the module"
				)
			end
			if claimed[entry] ~= nil then
				problem(
					`'{token}' is claimed by both '{claimed[entry]}' and '{area}'`,
					"give every src entry exactly one owning area"
				)
			end
			claimed[entry] = area
			ownedBy[area][entry] = true
		end

		-- (11) the seam column advertises only names the library really exports
		if #cells >= 4 then
			for member in string.gmatch(cells[4], "`Facet%.([%w_]+)") do
				counts.seams += 1
				if liveFacet[member] == nil then
					problem(
						`the '{area}' row advertises the seam 'Facet.{member}', which the library does not export`,
						"name the export the library really has, or delete the claim"
					)
				end
			end
		end
	end
	counts.areas = #areaOrder

	for _, name in fs.readDir(SRC) do
		local entry: string? = nil
		if fs.isDir(SRC .. "/" .. name) then
			entry = name
		elseif string.match(name, "%.luau$") ~= nil then
			entry = string.match(name, "^(.+)%.luau$")
		end
		if entry == nil then
			continue
		end
		counts.srcEntries += 1
		if claimed[entry] == nil then
			problem(
				`src/{name} is not claimed by any area row`,
				"add a row for it to the area table, or fold it into the row that owns it"
			)
		end
	end

	-- ---- 3. the proof table names the same areas, in the same order ---------
	local proofByArea: { [string]: { string } } = {}
	local proofOrder: { string } = {}
	for _, cells in proofRows :: { { string } } do
		if #cells < 1 then
			continue
		end
		local area = trim((string.gsub(cells[1], "%*", "")))
		table.insert(proofOrder, area)
		proofByArea[area] = cells
	end
	if #proofOrder ~= #areaOrder then
		problem(
			`the area table has {#areaOrder} rows and the proof table has {#proofOrder}`,
			"give every area exactly one row in each table"
		)
	end
	for index, area in areaOrder do
		if proofOrder[index] ~= area then
			problem(
				`row {index} is '{area}' in the area table and '{tostring(proofOrder[index])}' in the proof table`,
				"keep both tables in the same order, so a reader can hold one area across the two"
			)
		end
	end

	-- ---- 4. every src module path in the whole map is real ------------------
	for token in string.gmatch(source, "`(src/[^`]+)`") do
		if string.sub(token, -1) == "/" then
			if not fs.isDir(string.sub(token, 1, -2)) then
				problem(`names the directory '{token}', which does not exist`, "fix the path, or restore the directory")
			end
		elseif string.match(token, "%.luau$") ~= nil then
			if not fs.isFile(token) then
				problem(`names the module '{token}', which does not exist`, "fix the path, or restore the module")
			end
		end
	end

	-- ---- 5/6/7/8. the proof cells --------------------------------------------
	local scenarioIndex = if fs.isFile(SCENARIO_INDEX) then fs.readFile(SCENARIO_INDEX) else ""
	local boundarySource = if fs.isFile(BOUNDARY) then fs.readFile(BOUNDARY) else ""

	-- stage -> row names, read from the verification graph (the phase views and
	-- their rows replaced the retired gate manifest, 2026-08-31)
	local stages: { [string]: { [string]: boolean } } = {}
	if fs.isFile(GATES) then
		local graph = serde.decode("json", fs.readFile(GATES))
		for _, phase in (graph.phases or {}) :: { any } do
			local id = if type(phase) == "table" then phase.id else phase
			if type(id) == "string" then
				stages[id] = {}
			end
		end
		for _, row in (graph.rows or {}) :: { any } do
			if type(row) == "table" and type(row.phase) == "string" and type(row.name) == "string" then
				if stages[row.phase] == nil then
					stages[row.phase] = {}
				end
				stages[row.phase][row.name] = true
			end
		end
	end

	for _, area in areaOrder do
		local cells = proofByArea[area]
		if cells == nil or #cells < 6 then
			problem(
				`the proof row for '{area}' does not have all six columns`,
				"give every proof row: area, dependency direction, tests, scenario, gate, extension path"
			)
			continue
		end
		local dependency, tests, scenario, gate = cells[2], cells[3], cells[4], cells[5]

		-- (8) dependency rules cited by name
		for _, token in backticked(dependency) do
			if string.match(token, "^[a-z][a-z-]+$") ~= nil and string.find(token, "-") ~= nil then
				counts.boundaryRules += 1
				if string.find(boundarySource, `"{token}"`, 1, true) == nil then
					problem(
						`the '{area}' row cites the boundary rule '{token}', which check_boundary does not enforce`,
						`name a rule tools/lune/check_boundary.luau really reports, or stop claiming enforcement`
					)
				end
			end
		end

		-- (5) tests
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
			local entries = requiredEntries(token)
			local covers = false
			for entry in ownedBy[area] do
				if entries[entry] then
					covers = true
					break
				end
			end
			if not covers then
				problem(
					`the '{area}' row names '{token}', which requires no module of that area`,
					"name a spec whose own requires reach this area, or move the spec to the row it really covers"
				)
			end
		end
		if named == 0 then
			problem(`the '{area}' row names no covering spec`, "name at least one spec that requires this area")
		end

		-- (6) Studio scenario
		local scenarioTokens = backticked(scenario)
		if #scenarioTokens == 0 then
			if string.match(scenario, "^none%s*—") == nil then
				problem(
					`the '{area}' row names no Studio scenario and gives no reason`,
					'name a scenario, or write "none — <why this area has no live surface>"'
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
						"add it to the scenario ORDER, or name one that is registered"
					)
				end
			end
		end

		-- (7) gates
		local gateNamed = 0
		for _, token in backticked(gate) do
			local stage, row = string.match(token, "^([^/]+)/([^/]+)$")
			if stage == nil then
				stage = token
			end
			if stages[stage :: string] == nil then
				gateNamed += 1
				problem(
					`the '{area}' row cites the gate stage '{stage}', which {GATES} does not define`,
					"cite a stage the verification graph really has"
				)
				continue
			end
			gateNamed += 1
			if row ~= nil then
				counts.gateRows += 1
				if not stages[stage :: string][row :: string] then
					problem(
						`the '{area}' row cites '{token}', but that stage has no row of that name`,
						"cite a row the stage really has"
					)
				end
			end
		end
		if gateNamed == 0 then
			problem(`the '{area}' row cites no gate`, "cite the stage, and where you can the row, that pins this area")
		end
	end

	-- ---- the quick answers each send the reader somewhere -------------------
	for index, cells in quickRows :: { { string } } do
		if #cells < 3 or string.find(cells[3], "](", 1, true) == nil then
			problem(
				`quick answer {index} does not link the page that carries the rest of the answer`,
				"end every quick answer with a link"
			)
		end
	end

	-- ---- 9. every local link resolves --------------------------------------
	local mapDir = "docs"
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
		local resolved = normalize(mapDir .. "/" .. (path :: string))
		if not (fs.isFile(resolved) or fs.isDir(resolved)) then
			problem(`links '{target}', which resolves to '{resolved}' and does not exist`, "fix the link")
			continue
		end
		if string.match(resolved, "^docs/extending/.+%.md$") ~= nil then
			linkedPlaybooks[resolved] = true
		end
		if anchor ~= nil and string.match(resolved, "%.md$") ~= nil then
			local anchors = headingAnchors(fs.readFile(resolved))
			if not anchors[anchor :: string] then
				problem(
					`links '{target}', but '{resolved}' has no heading with that anchor`,
					"point at a heading that document really has"
				)
			end
		end
	end

	-- ---- 10. every playbook is reachable from the map -----------------------
	if fs.isDir(PLAYBOOKS) then
		for _, name in fs.readDir(PLAYBOOKS) do
			if string.match(name, "%.md$") == nil then
				continue
			end
			counts.playbooks += 1
			if not linkedPlaybooks[`{PLAYBOOKS}/{name}`] then
				problem(
					`{PLAYBOOKS}/{name} is a shipped extension playbook the map never links`,
					"link it from the area that owns it, or from a quick answer"
				)
			end
		end
	end

	return { ok = #problems == 0, problems = problems, counts = counts }
end

-- The per-area covering-spec counts, derived the same way rule 5 derives them.
-- The map states the RULE and never the numbers, so this is where a maintainer
-- reads the numbers: a count written into prose would be a second catalog.
function check_maintainer_map.coverage(): { { area: string, entries: { string }, specs: number } }
	local lines = splitLines(fs.readFile(MAP))
	local areaRows = tableAfter(lines, AREA_MARKER) or {}
	local ordered: { { area: string, entries: { string }, specs: number } } = {}
	local owners: { [string]: number } = {}
	for _, cells in areaRows do
		if #cells < 2 then
			continue
		end
		local area = trim((string.gsub(cells[1], "%*", "")))
		local entries: { string } = {}
		for _, token in backticked(cells[2]) do
			local entry = topEntryOf(token)
			if entry ~= nil then
				table.insert(entries, entry)
			end
		end
		table.insert(ordered, { area = area, entries = entries, specs = 0 })
		owners[area] = #ordered
	end

	local function walk(dir: string, visit: (string) -> ())
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, visit)
			elseif string.match(name, "%.spec%.luau$") ~= nil then
				visit(path)
			end
		end
	end

	walk("tests", function(path)
		local entries = requiredEntries(path)
		for _, row in ordered do
			for _, entry in row.entries do
				if entries[entry] then
					row.specs += 1
					break
				end
			end
		end
	end)
	return ordered
end

check_maintainer_map.OBLIGATIONS = table.freeze({
	"every top-level entry under src/ (read from disk) is claimed by exactly one row of the area table",
	"every src path the map claims exists, and no two areas claim the same one",
	"the area table and the proof table name the same areas in the same order",
	"every backticked src module path anywhere in the map is a real file",
	"every spec a proof row names exists and requires a module of that row's area (coverage is the require "
		.. "graph one hop out of the spec file; a spec that reaches the library only through the root counts "
		.. "under the library-root row)",
	'every Studio scenario named exists and is registered in the scenario index, or the cell says "none — <reason>"',
	"every gate stage and stage/row the map cites exists in tools/lune/verify/graph.json",
	"every dependency rule the map cites by name is a rule tools/lune/check_boundary.luau really reports",
	"every quick answer links the page that carries the rest of the answer",
	"every local markdown link resolves, and a link with an anchor lands on a heading that document has",
	"every page under docs/extending is linked by the map",
	"every Facet.<name> the public-seam column advertises is a field of the exported library table, read from "
		.. "the table itself rather than from a parsed literal",
})

return check_maintainer_map
