--!strict
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local Files = require("../lib/files")
local Luau = require("../lib/luau")
local Rule = require("../lib/rule")
local Run = require("../lib/run")

local CONTROL_TYPES = "src/ui/control_types.luau"
local FACET_INIT = "src/init.luau"

local SCANNED_ROOTS = { "examples/", "bench/", "tests/", "docs/" }

local EXCLUDED_TREES = { "artifacts/", "docs/superpowers/", "docs/plans/", ".superpowers/" }

type AllowEntry = { path: string, pattern: string, plain: boolean, reason: string }

local ALLOWLIST: { AllowEntry } = {
	{
		path = "tests/native_public_surface.verify.luau",
		pattern = "toBeNil()",
		plain = true,
		reason = "the public-surface spec asserts that each removed name is nil",
	},
	{
		path = "tests/native_registration.verify.luau",
		pattern = "%f[%w_]UI%.ProofControl%f[^%w_]",
		plain = false,
		reason = "the registration spec generates ProofControl into an edited copy of src/ui/init.luau and proves the new constructor is exported",
	},
	{
		path = "tests/scenario_require_paths.verify.luau",
		pattern = 'GetService("ReplicatedStorage").Facet.tokens.chrome_slots',
		plain = true,
		reason = "a planted require line for the require-path checker names an Instance path under ReplicatedStorage, not the Facet table",
	},
}

local APP_MEMBERS: { [string]: boolean } = {
	controls = true,
	presentModal = true,
	installTheme = true,
	environment = true,
	core = true,
	present = true,
}

local SCAFFOLDING: { [string]: boolean } = {
	newPresenter = true,
	newActionSystem = true,
	newFocusGraph = true,
	newCore = true,
	createHost = true,
}

export type Surface = { controls: { [string]: boolean }, members: { [string]: boolean } }

type Hit = { position: number, message: string }

local function isWord(byte: number?): boolean
	if byte == nil then
		return false
	end
	return (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95
end

local function isIdentifierStart(byte: number?): boolean
	return byte ~= nil and isWord(byte) and not (byte >= 48 and byte <= 57)
end

local function isUpper(byte: number?): boolean
	return byte ~= nil and byte >= 65 and byte <= 90
end

local function isSpace(byte: number?): boolean
	return byte ~= nil and (byte == 32 or (byte >= 9 and byte <= 13))
end

local function wordEnd(text: string, start: number): number
	local finish = start
	while isWord(string.byte(text, finish)) do
		finish += 1
	end
	return finish
end

local function skipSpaces(text: string, position: number): number
	local cursor = position
	while isSpace(string.byte(text, cursor)) do
		cursor += 1
	end
	return cursor
end

local function identifierAt(text: string, position: number): (string?, number)
	if not isIdentifierStart(string.byte(text, position)) then
		return nil, position
	end
	local finish = wordEnd(text, position)
	return string.sub(text, position, finish - 1), finish
end

local DOUBLE_QUOTE = string.byte('"')
local DOT = string.byte(".")

local function uiHits(code: string, controls: { [string]: boolean }, hits: { Hit })
	local cursor = 1
	while cursor <= #code do
		local before = string.byte(code, cursor - 1)
		if
			not isIdentifierStart(string.byte(code, cursor))
			or isWord(before)
			or before == DOT
			or before == DOUBLE_QUOTE
		then
			cursor += 1
			continue
		end
		local finish = wordEnd(code, cursor)
		local member: string? = nil
		local matchEnd = cursor
		if string.sub(code, finish, finish + 3) == ".UI." then
			member, matchEnd = identifierAt(code, finish + 4)
		end
		if member == nil and string.sub(code, cursor, cursor + 2) == "UI." then
			member, matchEnd = identifierAt(code, cursor + 3)
		end
		if member ~= nil then
			local name = member :: string
			if not controls[name] then
				table.insert(hits, {
					position = cursor,
					message = ("`UI.%s` is not a constructor on Facet.controls(runtime)"):format(name),
				})
			end
			cursor = matchEnd
		else
			cursor = finish
		end
	end
end

local function facetHits(code: string, members: { [string]: boolean }, hits: { Hit })
	local cursor = 1
	while true do
		local start = string.find(code, "Facet.", cursor, true)
		if start == nil then
			return
		end
		local before = string.byte(code, start - 1)
		local member, finish = identifierAt(code, start + 6)
		if member ~= nil and not isWord(before) and before ~= DOUBLE_QUOTE then
			if not members[member] then
				table.insert(hits, {
					position = start,
					message = ("`Facet.%s` is not exported by %s"):format(member, FACET_INIT),
				})
			end
			cursor = finish
		else
			cursor = start + 1
		end
	end
end

local function appHits(code: string, hits: { Hit })
	local cursor = 1
	while true do
		local start = string.find(code, "app.", cursor, true)
		if start == nil then
			return
		end
		local before = string.byte(code, start - 1)
		local finish = wordEnd(code, start + 4)
		local member = string.sub(code, start + 4, finish - 1)
		if not isWord(before) and before ~= DOT and APP_MEMBERS[member] then
			table.insert(hits, {
				position = start,
				message = ("`app.%s` belongs to the removed Facet application object"):format(member),
			})
			cursor = finish
		else
			cursor = start + 1
		end
	end
end

local function eachMatch(code: string, pattern: string, visit: (start: number, finish: number) -> ())
	local cursor = 1
	while true do
		local start, finish = string.find(code, pattern, cursor)
		if start == nil or finish == nil then
			return
		end
		visit(start, finish)
		cursor = math.max(finish, start) + 1
	end
end

local function scaffoldHits(code: string, hits: { Hit })
	eachMatch(code, "[%a_][%w_]*", function(start, finish)
		local name = string.sub(code, start, finish)
		if not SCAFFOLDING[name] or isWord(string.byte(code, start - 1)) then
			return
		end
		local after = skipSpaces(code, finish + 1)
		if string.sub(code, after, after) ~= "(" then
			return
		end
		if name == "createHost" and string.sub(code, math.max(1, start - 7), start - 1) == "Roblox." then
			return
		end
		table.insert(hits, { position = start, message = ("`%s(` is removed Facet scaffolding"):format(name) })
	end)
end

local function flatBuilderAt(code: string, start: number, runEnd: number): (Hit?, number)
	for dot = runEnd - 1, start + 1, -1 do
		if string.sub(code, dot, dot + 3) ~= ".new" or not isUpper(string.byte(code, dot + 4)) then
			continue
		end
		local base = string.sub(code, start, dot - 1)
		local nameEnd = wordEnd(code, dot + 4)
		local position = skipSpaces(code, nameEnd)
		if string.sub(code, position, position) ~= "(" then
			continue
		end
		position = skipSpaces(code, position + 1)
		if string.sub(code, position, position + #base - 1) ~= base then
			continue
		end
		position = skipSpaces(code, position + #base)
		if string.sub(code, position, position) ~= "," then
			continue
		end
		local name = string.sub(code, dot + 4, nameEnd - 1)
		return {
			position = start,
			message = ("flat builder `%s.new%s(%s, ...)` was removed"):format(base, name, base),
		},
			position + 1
	end
	return nil, start + 1
end

local function flatBuilderHits(code: string, hits: { Hit })
	local cursor = 1
	eachMatch(code, "[%w_.]+", function(runStart, runFinish)
		if string.find(string.sub(code, runStart, runFinish), "%.new%u") == nil then
			return
		end
		local runEnd = runFinish + 1
		local start = math.max(runStart, cursor)
		while start < runEnd do
			if not isIdentifierStart(string.byte(code, start)) then
				start += 1
				continue
			end
			local hit, nextCursor = flatBuilderAt(code, start, runEnd)
			if hit ~= nil then
				table.insert(hits, hit)
				cursor = nextCursor
				break
			end
			start += 1
		end
	end)
end

local function colonHits(code: string, hits: { Hit })
	eachMatch(code, ":new%u[%w_]*", function(start, finish)
		local after = skipSpaces(code, finish + 1)
		if string.sub(code, after, after) == "(" then
			table.insert(hits, { position = start, message = "colon builder `:new<Name>(` was removed" })
		end
	end)
end

local function codeOf(scope: string, source: string): string
	if string.sub(scope, -3) ~= ".md" then
		return source
	end
	local kept: { string } = {}
	local inside = false
	for _, line in string.split(source, "\n") do
		if inside then
			if string.match(line, "^%s*```%s*$") ~= nil then
				inside = false
				table.insert(kept, "")
			else
				table.insert(kept, line)
			end
		else
			local language = string.match(line, "^%s*```%s*(%a+)%s*$")
			inside = language == "lua" or language == "luau"
			table.insert(kept, "")
		end
	end
	return table.concat(kept, "\n")
end

local function allowed(scope: string, text: string): boolean
	for _, entry in ALLOWLIST do
		local base = string.gsub(entry.path, "/+$", "")
		if scope == entry.path or stringext.hasPrefix(scope, base .. "/") then
			if string.find(text, entry.pattern, 1, entry.plain) ~= nil then
				return true
			end
		end
	end
	return false
end

local function scanSource(scope: string, source: string, surface: Surface): { string }
	local normalized = string.gsub(source, "\r\n", "\n")
	local code = codeOf(scope, normalized)
	local lines = string.split(code, "\n")
	local groups: { { Hit } } = { {}, {}, {}, {}, {}, {} }
	uiHits(code, surface.controls, groups[1])
	facetHits(code, surface.members, groups[2])
	appHits(code, groups[3])
	scaffoldHits(code, groups[4])
	flatBuilderHits(code, groups[5])
	colonHits(code, groups[6])
	local findings: { string } = {}
	for _, group in groups do
		for _, hit in group do
			local line = Luau.lineOf(code, hit.position)
			if not allowed(scope, lines[line] or "") then
				table.insert(findings, ("%s:%d: %s"):format(scope, line, hit.message))
			end
		end
	end
	return findings
end

local function inScope(path: string): boolean
	for _, prefix in EXCLUDED_TREES do
		if stringext.hasPrefix(path, prefix) then
			return false
		end
	end
	local scanned = false
	for _, prefix in SCANNED_ROOTS do
		if stringext.hasPrefix(path, prefix) then
			scanned = true
		end
	end
	if not scanned then
		return false
	end
	if stringext.hasPrefix(path, "docs/") then
		return string.sub(path, -3) == ".md" or string.sub(path, -5) == ".luau"
	end
	return string.sub(path, -5) == ".luau"
end

local function returnedName(block: Luau.Node): string?
	local statements = Luau.items(block, "statements")
	local last = statements[#statements]
	if last == nil or Luau.tag(last) ~= "return" then
		return nil
	end
	local returned = Luau.items(last, "expressions")[1]
	if returned == nil then
		return nil
	end
	if Luau.tag(returned) == "local" then
		return Luau.tokenText(returned, "token")
	elseif Luau.tag(returned) == "global" then
		return Luau.tokenText(returned, "name")
	end
	return nil
end

local function frozenTable(value: Luau.Node?): Luau.Node?
	if value == nil or Luau.tag(value) ~= "call" then
		return nil
	end
	local callee = Luau.dotted(Luau.child(value, "func"))
	local argument = Luau.items(value, "arguments")[1]
	if (callee == "freeze" or callee == "table.freeze") and argument ~= nil and Luau.tag(argument) == "table" then
		return argument
	end
	return nil
end

local function exportTable(parsed: Luau.Parsed): Luau.Node?
	local found: Luau.Node? = nil
	Luau.walk(parsed.root, function(node)
		if found ~= nil then
			return false
		end
		if Luau.kind(node) ~= "stat" or Luau.tag(node) ~= "block" then
			return true
		end
		local name = returnedName(node)
		if name == nil then
			return true
		end
		for _, statement in Luau.items(node, "statements") do
			local tag = Luau.tag(statement)
			if tag ~= "assign" and tag ~= "local" then
				continue
			end
			local values = Luau.items(statement, "values")
			for index, variable in Luau.items(statement, "variables") do
				local assigned = if tag == "local"
					then Luau.tokenText(variable, "name")
					elseif Luau.tag(variable) == "local" then Luau.tokenText(variable, "token")
					else nil
				local frozen = frozenTable(values[index])
				if assigned == name and frozen ~= nil then
					found = frozen
				end
			end
		end
		return found == nil
	end)
	return found
end

local function surfaceOf(context: Rule.Context): (Surface?, string?)
	local controlsPath = context.path(CONTROL_TYPES)
	if not Files.isFile(controlsPath) then
		return nil, ("%s does not exist"):format(CONTROL_TYPES)
	end
	local controlsParsed, controlsProblem = Luau.parse(Files.text(controlsPath))
	if controlsParsed == nil then
		return nil, ("%s does not parse: %s"):format(CONTROL_TYPES, controlsProblem or "")
	end
	local controls: { [string]: boolean } = {}
	local declared = false
	for _, statement in Luau.items(controlsParsed.root, "statements") do
		if Luau.tag(statement) == "typealias" and Luau.tokenText(statement, "name") == "Controls" then
			local aliased = Luau.child(statement, "type")
			if aliased ~= nil and Luau.tag(aliased) == "table" then
				declared = true
				for _, entry in Luau.items(aliased, "entries") do
					local key = if Luau.kind(entry) == "property" then Luau.tokenText(entry, "key") else nil
					if key ~= nil then
						controls[key] = true
					end
				end
			end
		end
	end
	if not declared then
		return nil, ("no Controls table type in %s"):format(CONTROL_TYPES)
	end
	if next(controls) == nil then
		return nil, ("empty Controls type in %s"):format(CONTROL_TYPES)
	end
	local initPath = context.path(FACET_INIT)
	if not Files.isFile(initPath) then
		return nil, ("%s does not exist"):format(FACET_INIT)
	end
	local initParsed, initProblem = Luau.parse(Files.text(initPath))
	if initParsed == nil then
		return nil, ("%s does not parse: %s"):format(FACET_INIT, initProblem or "")
	end
	local exported = exportTable(initParsed)
	if exported == nil then
		return nil, ("no frozen export table returned in %s"):format(FACET_INIT)
	end
	local members: { [string]: boolean } = {}
	for _, entry in Luau.items(exported, "entries") do
		local key = if Luau.kind(entry) == "record" then Luau.tokenText(entry, "key") else nil
		if key ~= nil then
			members[key] = true
		end
	end
	for _, statement in Luau.items(initParsed.root, "statements") do
		if Luau.tag(statement) == "typealias" and statement.isExported == true then
			local name = Luau.tokenText(statement, "name")
			if name ~= nil then
				members[name] = true
			end
		end
	end
	return { controls = controls, members = members }, nil
end

local function inspect(context: Rule.Context, paths: { string }): { string }
	local surface, problem = surfaceOf(context)
	if surface == nil then
		return { "cannot read the public constructors: " .. (problem or "") }
	end
	local findings: { string } = {}
	for _, path in paths do
		local normalized = Files.normalize(path)
		local absolute = context.path(normalized)
		if inScope(normalized) and Files.isFile(absolute) then
			for _, finding in scanSource(normalized, Files.read(absolute), surface) do
				table.insert(findings, finding)
			end
		end
	end
	return findings
end

local function listed(context: Rule.Context): ({ string }?, string?)
	local result = Run.git({ "ls-files", "-z", "--cached", "--others", "--exclude-standard" }, context.root)
	if not result.ok then
		return nil, ("git ls-files failed in %s: %s"):format(context.root, result.stderr)
	end
	local seen: { [string]: boolean } = {}
	local paths: { string } = {}
	for _, path in string.split(result.stdout, "\0") do
		if path ~= "" and not seen[path] then
			seen[path] = true
			table.insert(paths, path)
		end
	end
	table.sort(paths)
	return paths, nil
end

local function check(context: Rule.Context): { string }
	local paths, problem = listed(context)
	if paths == nil then
		return { problem or "git ls-files failed" }
	end
	return inspect(context, paths)
end

local SURFACE_FIXTURE: { [string]: string } = {
	[CONTROL_TYPES] = "export type Controls = {\n\tButton: (unknown) -> unknown,\n\tLabel: (unknown) -> unknown,\n}\nreturn nil\n",
	[FACET_INIT] = 'local freeze = table.freeze\nexport type Facet = { controls: unknown }\nlocal function bind()\n\tlocal surface\n\tsurface = freeze({\n\t\tVERSION = "1",\n\t\tcontrols = function() end,\n\t\tthemes = {},\n\t})\n\treturn surface\nend\nreturn bind()\n',
}

local function scanned(test: Verify.Context, files: { [string]: string }): { string }
	local fixture = table.clone(SURFACE_FIXTURE)
	for path, contents in files do
		fixture[path] = contents
	end
	local findings: { string } = {}
	Rule.within(test, fixture, function(context)
		findings = inspect(context, Files.walk(context.root))
		return
	end)
	return findings
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the public constructors and members are read from source", {
		id = prefix .. "the public constructors and members are read from source",
		run = function(test: Verify.Context)
			Rule.within(test, SURFACE_FIXTURE, function(context)
				local surface = surfaceOf(context)
				if surface == nil then
					error("the surface was not read", 0)
				end
				Verify.expect(
					surface.controls.Button == true
						and surface.controls.Scene == nil
						and surface.members.controls == true
						and surface.members.Facet == true
						and surface.members.new == nil
				):toBeTrueWith("the public constructor sets were not read from source")
			end)
		end,
	})
	harness:case(prefix .. "a removed constructor is reported and a public one is not", {
		id = prefix .. "a removed constructor is reported and a public one is not",
		run = function(test: Verify.Context)
			Verify.expect(scanned(test, {
				["examples/probe.luau"] = 'local UI = Facet.controls(runtime)\nreturn UI.Scene("Column")({\n\tUI.Button({ label = "Go" }),\n\tctx.UI.Label({}),\n})\n',
			})):toEqual({ "examples/probe.luau:2: `UI.Scene` is not a constructor on Facet.controls(runtime)" })
		end,
	})
	harness:case(prefix .. "a removed Facet member and an application member are reported", {
		id = prefix .. "a removed Facet member and an application member are reported",
		run = function(test: Verify.Context)
			Verify.expect(scanned(test, {
				["bench/probe.luau"] = "local app = Facet.new()\nreturn app\n",
				["tests/probe.luau"] = "app.presentModal(function() end)\nlocal ok = app.presentation\nreturn nil\n",
			})):toEqual({
				"bench/probe.luau:1: `Facet.new` is not exported by src/init.luau",
				"tests/probe.luau:1: `app.presentModal` belongs to the removed Facet application object",
			})
		end,
	})
	harness:case(prefix .. "a wrapped flat builder, a colon builder and scaffolding are reported", {
		id = prefix .. "a wrapped flat builder, a colon builder and scaffolding are reported",
		run = function(test: Verify.Context)
			Verify.expect(scanned(test, {
				["examples/probe.luau"] = "local x = Facet.newTable(\n\tFacet,\n\tcore,\n\t{}\n)\nlocal y = view:newButton({})\nlocal z = newCore ()\nlocal h = Roblox.createHost(engine)\nreturn x, y, z, h\n",
			})):toEqual({
				"examples/probe.luau:1: `Facet.newTable` is not exported by src/init.luau",
				"examples/probe.luau:7: `newCore(` is removed Facet scaffolding",
				"examples/probe.luau:1: flat builder `Facet.newTable(Facet, ...)` was removed",
				"examples/probe.luau:6: colon builder `:new<Name>(` was removed",
			})
		end,
	})
	harness:case(prefix .. "only lua and luau fences in documents are scanned", {
		id = prefix .. "only lua and luau fences in documents are scanned",
		run = function(test: Verify.Context)
			Verify.expect(scanned(test, {
				["docs/probe.md"] = "# Probe\n\n`UI.Scene` in prose is not code.\n\n```luau\nlocal row = UI.Scene({})\n```\n\n```text\nUI.Scene\n```\n",
				["docs/plans/old.md"] = "```luau\nlocal row = UI.Scene({})\n```\n",
				["docs/probe.txt"] = "UI.Scene\n",
			})):toEqual({ "docs/probe.md:6: `UI.Scene` is not a constructor on Facet.controls(runtime)" })
		end,
	})
	harness:case(prefix .. "an allowlist pattern covers only its own line", {
		id = prefix .. "an allowlist pattern covers only its own line",
		run = function(test: Verify.Context)
			Verify.expect(scanned(test, {
				["tests/native_public_surface.verify.luau"] = "expect(Facet.new).toBeNil()\nlocal row = UI.Scene({})\n",
			})):toEqual({
				"tests/native_public_surface.verify.luau:2: `UI.Scene` is not a constructor on Facet.controls(runtime)",
			})
		end,
	})
	harness:case(prefix .. "CRLF line endings report the same lines as LF", {
		id = prefix .. "CRLF line endings report the same lines as LF",
		run = function(test: Verify.Context)
			Verify.expect(scanned(test, { ["examples/probe.luau"] = "local a = 1\r\nlocal b = UI.Scene({})\r\n" }))
				:toEqual({ "examples/probe.luau:2: `UI.Scene` is not a constructor on Facet.controls(runtime)" })
		end,
	})
	harness:case(prefix .. "a missing Controls type is reported", {
		id = prefix .. "a missing Controls type is reported",
		run = function(test: Verify.Context)
			Rule.within(test, { [CONTROL_TYPES] = "return nil\n" }, function(context)
				Verify.expect(inspect(context, {})):toEqual({
					"cannot read the public constructors: no Controls table type in " .. CONTROL_TYPES,
				})
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "call-shape-drift",
	summary = "Examples, bench, tests and docs code call only current constructors and exported Facet members.",
	check = check,
	register = register,
}

return rule
