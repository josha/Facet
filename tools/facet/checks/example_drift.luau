--!strict

local stringext = require("@std/stringext")
local Case = require("../lib/case")
local Files = require("../lib/files")
local Luau = require("../lib/luau")
local Rule = require("../lib/rule")

local SCANNED = { "examples/gallery/examples", "examples/reference" }
local SKIPPED = { "examples/gallery/examples/words" }
local THEMES = "src/ui/themes.luau"

export type Entry = { file: string, match: string, why: string }

local ALLOWLIST: { Entry } = {
	{
		file = "examples/gallery/examples/05_word_game.luau",
		match = "TextSize = 24,",
		why = "the letter glyph of a fixed 48 px board tile; a theme type step would overflow the tile",
	},
	{
		file = "examples/gallery/examples/05_word_game.luau",
		match = "TextSize = 12,",
		why = "the corner mark of a fixed 48 px board tile, sized with the tile",
	},
	{
		file = "examples/gallery/examples/06_tile_game.luau",
		match = "TextSize = 16,",
		why = "the letter of a fixed 44 to 48 px board cell or rack tile, sized with the cell",
	},
	{
		file = "examples/gallery/examples/07_match3.luau",
		match = "TextSize = 16,",
		why = "the fallback glyph of a fixed board tile, shown only when the tile art is missing",
	},
	{
		file = "examples/gallery/examples/07_match3.luau",
		match = "Color = Color3.new(1, 1, 1),",
		why = "the selection ring over coloured gem art must contrast with every gem, so it does not follow the palette",
	},
	{
		file = "examples/gallery/examples/07_match3.luau",
		match = 'game:GetService("RunService")',
		why = "the engine fallback when the host context supplies no run service",
	},
	{
		file = "examples/reference/p1_glade/init.luau",
		match = 'game:GetService("RunService")',
		why = "the engine fallback when the host context supplies no heartbeat",
	},
	{
		file = "examples/reference/p2_cartwheel/init.luau",
		match = 'game:GetService("RunService")',
		why = "the engine fallback when the host context supplies no heartbeat",
	},
	{
		file = "examples/reference/p3_sipworks/init.luau",
		match = 'game:GetService("RunService")',
		why = "the engine fallback when the host context supplies no heartbeat",
	},
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'game:GetService("RunService")',
		why = "the engine fallback when the host context supplies no heartbeat",
	},
	{
		file = "examples/reference/p2_cartwheel/init.luau",
		match = "Color3.fromRGB(",
		why = "illustration content: the cart, wheel and awning art of the cartwheel scene, not interface paint",
	},
	{
		file = "examples/gallery/examples/08_garage.luau",
		match = "C3.fromRGB(",
		why = "vehicle body paint, wheels, headlights and the turntable are authored 3D artwork",
	},
	{
		file = "examples/gallery/examples/09_adventurers_pack.luau",
		match = "C3.fromRGB(",
		why = "equipment materials and the explorer are authored 3D artwork",
	},
	{
		file = "examples/gallery/examples/10_potion_shop.luau",
		match = "C3.fromRGB(",
		why = "potion liquids, corks and the counter are authored 3D artwork",
	},
	{
		file = "examples/gallery/examples/12_outpost.luau",
		match = "C3.fromRGB(",
		why = "outpost structures and power indicator lamps are authored 3D world content",
	},
	{
		file = "examples/gallery/examples/showcase_view.luau",
		match = "C3.fromRGB(",
		why = "the miniature scene backdrop and scene lighting are authored artwork; surrounding controls retain theme paint",
	},
}

type Kind = string

local KINDS: { Kind } = { "textSize", "paint", "font", "colour", "instance", "service" }

type Message = { code: string, what: string }

local RULES: { [Kind]: Message } = {
	textSize = { code = "R1", what = "a literal TextSize; use a textRole or the control size" },
	paint = { code = "R1", what = "a literal paint colour; use a theme tag or role" },
	font = { code = "R1", what = "a literal font; use a textRole" },
	colour = { code = "R3", what = "a raw colour; use a theme tag or role" },
	instance = { code = "R4", what = "an engine reach-around; use the Host constructors" },
	service = { code = "R4", what = "an engine reach-around; receive the service through the context" },
}

local PAINT_KEYS: { [string]: boolean } = { TextColor3 = true, BackgroundColor3 = true, ImageColor3 = true }
local COLOUR_TYPES: { [string]: boolean } = { Color3 = true, C3 = true }
local NUMERIC_CONSTRUCTORS: { [string]: boolean } = { new = true, fromRGB = true, fromHSV = true }

type Role = { column: number, role: string }

type Line = { kinds: { [Kind]: boolean }, roles: { Role } }

local function segments(dotted: string): { string }
	local parts: { string } = {}
	for part in string.gmatch(dotted, "[^%.]+") do
		table.insert(parts, part)
	end
	return parts
end

local function endsWithPath(dotted: string, suffix: string): boolean
	return dotted == suffix or string.sub(dotted, -(#suffix + 1)) == "." .. suffix
end

local function isNumeric(expression: Luau.Node?): boolean
	if expression == nil then
		return false
	end
	local tag = Luau.tag(expression)
	if tag == "number" or tag == "integer" then
		return true
	elseif tag == "unary" and Luau.tokenText(expression, "operator") == "-" then
		local operand = Luau.child(expression, "operand")
		return operand ~= nil and (Luau.tag(operand) == "number" or Luau.tag(operand) == "integer")
	elseif tag == "group" then
		return isNumeric(Luau.child(expression, "expression"))
	end
	return false
end

local function colourCall(expression: Luau.Node, prefixes: { [string]: boolean }?): (string?, boolean)
	if Luau.tag(expression) ~= "call" then
		return nil, false
	end
	local callee = Luau.dotted(Luau.child(expression, "func"))
	if callee == nil or string.find(callee, ":", 1, true) ~= nil then
		return nil, false
	end
	local parts = segments(callee)
	if #parts < 2 or not COLOUR_TYPES[parts[#parts - 1]] then
		return nil, false
	end
	if prefixes ~= nil then
		local prefix = table.concat(parts, ".", 1, #parts - 2)
		if not prefixes[prefix] then
			return nil, false
		end
	end
	return parts[#parts], isNumeric(Luau.items(expression, "arguments")[1])
end

local function leadingName(expression: Luau.Node): string?
	if Luau.tag(expression) == "call" then
		return Luau.dotted(Luau.child(expression, "func"))
	end
	return Luau.dotted(expression)
end

local PAINT_PREFIXES: { [string]: boolean } = { [""] = true, ["ctx.types"] = true }

local function assignmentKinds(key: string, value: Luau.Node): { Kind }
	local kinds: { Kind } = {}
	if key == "TextSize" and isNumeric(value) then
		table.insert(kinds, "textSize")
	end
	if PAINT_KEYS[key] then
		local _, numeric = colourCall(value, PAINT_PREFIXES)
		if numeric then
			table.insert(kinds, "paint")
		end
	end
	if key == "Font" or key == "FontFace" then
		local name = leadingName(value)
		if name ~= nil and (string.sub(name, 1, 9) == "Enum.Font" or string.sub(name, 1, 5) == "Font.") then
			table.insert(kinds, "font")
		end
	end
	return kinds
end

local function callKind(call: Luau.Call): Kind?
	local callee = call.callee
	if callee == nil then
		return nil
	end
	if endsWithPath(callee, "Instance.new") then
		return "instance"
	end
	if endsWithPath(callee, "game:GetService") then
		return "service"
	end
	local constructor, numeric = colourCall(call.node, nil)
	if constructor == "fromHex" or (constructor ~= nil and NUMERIC_CONSTRUCTORS[constructor] and numeric) then
		return "colour"
	end
	return nil
end

type Assignment = { key: string, value: Luau.Node, line: number, column: number }

local function assignments(parsed: Luau.Parsed): { Assignment }
	local found: { Assignment } = {}
	local function add(keyToken: Luau.Node?, value: Luau.Node?)
		local key = Luau.text(keyToken)
		if keyToken == nil or key == nil or value == nil then
			return
		end
		local location = Luau.location(keyToken)
		table.insert(found, { key = key, value = value, line = location.beginLine, column = location.beginColumn })
	end
	Luau.walk(parsed.root, function(node)
		local kind = Luau.kind(node)
		if kind == "record" then
			add(Luau.child(node, "key"), Luau.child(node, "value"))
		elseif kind == "stat" and Luau.tag(node) == "assign" then
			local values = Luau.items(node, "values")
			for index, variable in Luau.items(node, "variables") do
				local tag = Luau.tag(variable)
				if tag == "indexname" then
					add(Luau.child(variable, "index"), values[index])
				elseif tag == "global" then
					add(Luau.child(variable, "name"), values[index])
				elseif tag == "local" then
					add(Luau.child(variable, "token"), values[index])
				end
			end
		elseif kind == "stat" and Luau.tag(node) == "local" then
			local values = Luau.items(node, "values")
			for index, variable in Luau.items(node, "variables") do
				add(Luau.child(variable, "name"), values[index])
			end
		end
		return true
	end)
	return found
end

local function typeRoles(context: Rule.Context): ({ [string]: boolean }?, string?)
	local path = context.path(THEMES)
	if not Files.isFile(path) then
		return nil, ("cannot read TYPE_ROLES: %s does not exist"):format(THEMES)
	end
	local parsed, problem = Luau.parse(Files.text(path))
	if parsed == nil then
		return nil, ("cannot read TYPE_ROLES: %s does not parse: %s"):format(THEMES, problem or "")
	end
	local roles: { [string]: boolean }? = nil
	Luau.walk(parsed.root, function(node)
		if roles ~= nil or Luau.kind(node) ~= "stat" or Luau.tag(node) ~= "assign" then
			return roles == nil
		end
		local values = Luau.items(node, "values")
		for index, variable in Luau.items(node, "variables") do
			local value = values[index]
			if Luau.dotted(variable) == "themes.TYPE_ROLES" and value ~= nil and Luau.tag(value) == "call" then
				local callee = Luau.dotted(Luau.child(value, "func"))
				local argument = Luau.items(value, "arguments")[1]
				if
					(callee == "table.freeze" or callee == "freeze")
					and argument ~= nil
					and Luau.tag(argument) == "table"
				then
					local found: { [string]: boolean } = {}
					for _, entry in Luau.items(argument, "entries") do
						local item = Luau.child(entry, "value")
						local role = if Luau.kind(entry) == "list" and item ~= nil then Luau.stringValue(item) else nil
						if role ~= nil then
							found[role] = true
						end
					end
					roles = found
				end
			end
		end
		return true
	end)
	if roles == nil then
		return nil, ("cannot read TYPE_ROLES from %s"):format(THEMES)
	end
	return roles, nil
end

local function files(context: Rule.Context): { string }
	local found: { string } = {}
	for _, base in SCANNED do
		for _, relative in Files.walk(context.path(base)) do
			local file = base .. "/" .. relative
			local skipped = false
			for _, skip in SKIPPED do
				if string.sub(file, 1, #skip + 1) == skip .. "/" then
					skipped = true
				end
			end
			if not skipped and string.sub(file, -5) == ".luau" and string.sub(file, -10) ~= ".spec.luau" then
				table.insert(found, file)
			end
		end
	end
	table.sort(found)
	return found
end

local function lineOf(lines: { [number]: Line }, line: number): Line
	local existing = lines[line]
	if existing ~= nil then
		return existing
	end
	local created: Line = { kinds = {}, roles = {} }
	lines[line] = created
	return created
end

local function scan(parsed: Luau.Parsed): { [number]: Line }
	local lines: { [number]: Line } = {}
	for _, assignment in assignments(parsed) do
		for _, kind in assignmentKinds(assignment.key, assignment.value) do
			lineOf(lines, assignment.line).kinds[kind] = true
		end
		if assignment.key == "textRole" then
			local role = Luau.stringValue(assignment.value)
			if role ~= nil then
				local found: Role = { column = assignment.column, role = role }
				table.insert(lineOf(lines, assignment.line).roles, found)
			end
		end
	end
	for _, call in Luau.calls(parsed) do
		local kind = callKind(call)
		if kind ~= nil then
			lineOf(lines, call.line).kinds[kind] = true
		end
	end
	return lines
end

local function allowedEntry(file: string, text: string, allowlist: { Entry }): Entry?
	for _, entry in allowlist do
		if entry.file == file and string.find(text, entry.match, 1, true) ~= nil then
			return entry
		end
	end
	return nil
end

local function inspect(context: Rule.Context, allowlist: { Entry }): ({ string }, number)
	local roles, problem = typeRoles(context)
	if roles == nil then
		return { problem or "cannot read TYPE_ROLES" }, 0
	end
	local roleNames: { string } = {}
	for role in roles do
		table.insert(roleNames, role)
	end
	table.sort(roleNames)
	local roleList = table.concat(roleNames, ", ")
	local violations: { string } = {}
	local used: { [Entry]: boolean } = {}
	local scanned = 0
	for _, file in files(context) do
		scanned += 1
		local source = Files.text(context.path(file))
		local parsed, parseProblem = Luau.parse(source)
		if parsed == nil then
			table.insert(violations, ("%s: cannot parse the example: %s"):format(file, parseProblem or ""))
			continue
		end
		local sourceLines = string.split(source, "\n")
		local hits = scan(parsed)
		local numbers: { number } = {}
		for number in hits do
			table.insert(numbers, number)
		end
		table.sort(numbers)
		for _, number in numbers do
			local hit = hits[number]
			local messages: { Message } = {}
			for _, kind in KINDS do
				local message = RULES[kind]
				if hit.kinds[kind] and message ~= nil then
					table.insert(messages, message)
				end
			end
			table.sort(hit.roles, function(left: Role, right: Role): boolean
				return left.column < right.column
			end)
			local unknownRole = false
			for _, found in hit.roles do
				if not roles[found.role] then
					unknownRole = true
					local message: Message = {
						code = "R2",
						what = ("an unknown textRole '%s'; the roles are %s"):format(found.role, roleList),
					}
					table.insert(messages, message)
				end
			end
			if #messages == 0 then
				continue
			end
			local text = sourceLines[number] or ""
			local entry = allowedEntry(file, text, allowlist)
			if entry ~= nil and not unknownRole then
				used[entry] = true
				continue
			end
			for _, message in messages do
				table.insert(
					violations,
					("%s:%d: [%s] %s: %s"):format(file, number, message.code, message.what, stringext.trim(text))
				)
			end
		end
	end
	for _, entry in allowlist do
		if not used[entry] then
			table.insert(violations, ("%s: allowlist entry '%s' matches nothing"):format(entry.file, entry.match))
		end
	end
	return violations, scanned
end

local function check(context: Rule.Context): { string }
	local violations = inspect(context, ALLOWLIST)
	return violations
end

local THEMES_FIXTURE =
	'local themes = {}\nthemes.TYPE_ROLES = table.freeze({ "caption", "label", "title" })\nreturn themes\n'

local function planted(source: string, allowlist: { Entry }?): { string }
	local findings: { string } = {}
	local failure = Rule.within({
		[THEMES] = THEMES_FIXTURE,
		["examples/gallery/examples/plant.luau"] = source,
		["examples/gallery/examples/words/skipped.luau"] = 'local s = Instance.new("Frame")\n',
		["examples/reference/plant.spec.luau"] = 'local s = Instance.new("Frame")\n',
	}, function(context)
		findings = inspect(context, allowlist or {})
		return nil
	end)
	if failure ~= nil then
		error(failure)
	end
	return findings
end

local function fires(source: string, fragment: string): string?
	local findings = planted(source)
	if Rule.contains(findings, fragment) then
		return nil
	end
	return ("expected a finding with '%s', got %s"):format(fragment, Rule.describe(findings))
end

local function silent(source: string, allowlist: { Entry }?): string?
	return Case.same(planted(source, allowlist), {})
end

local PLANT = "examples/gallery/examples/plant.luau"

local function cases(): { Rule.Case }
	return {
		{
			name = "a literal TextSize is reported",
			run = function()
				return fires("local a = { TextSize = 18 }\n", PLANT .. ":1: [R1] a literal TextSize")
			end,
		},
		{
			name = "a literal paint colour and a literal font are reported",
			run = function()
				return Case.first(
					fires(
						"local a = { TextColor3 = ctx.types.Color3.fromRGB(1, 2, 3) }\n",
						"[R1] a literal paint colour"
					),
					fires("frame.FontFace = Font.new('x')\n", "[R1] a literal font"),
					fires("local a = { Font = Enum.Font.Gotham }\n", "[R1] a literal font")
				)
			end,
		},
		{
			name = "an unknown textRole is reported",
			run = function()
				return fires(
					'local b = UI.Label { textRole = "banner" }\n',
					"[R2] an unknown textRole 'banner'; the roles are caption, label, title"
				)
			end,
		},
		{
			name = "a raw colour is reported, even across lines",
			run = function()
				return Case.first(
					fires("local c = Color3.fromRGB(1, 2, 3)\n", PLANT .. ":1: [R3] a raw colour"),
					fires("local c = C3.fromHex('#fff')\n", "[R3] a raw colour"),
					fires("local c = Color3.new(\n\t-1,\n\t0,\n\t0\n)\n", PLANT .. ":1: [R3] a raw colour")
				)
			end,
		},
		{
			name = "an engine reach-around is reported",
			run = function()
				return Case.first(
					fires('local d = Instance.new("Frame")\n', "[R4] an engine reach-around; use the Host"),
					fires('local s = game:GetService("RunService")\n', "[R4] an engine reach-around; receive")
				)
			end,
		},
		{
			name = "computed values, comments and strings are not reported",
			run = function()
				return silent(
					'--!strict\n-- Instance.new("Frame")\nlocal a = { TextSize = size or 16, TextColor3 = Color3.new(r, g, b) }\nlocal t = "Instance.new(1)"\nlocal c = Color3.fromHSV(index / 7, 0.5, 0.8)\nreturn { a, t, c }\n'
				)
			end,
		},
		{
			name = "an allowlisted line passes and its entry is used",
			run = function()
				return silent("local e = Color3.new(1, 1, 1)\n", {
					{ file = PLANT, match = "Color3.new(1, 1, 1)", why = "test" },
				})
			end,
		},
		{
			name = "an allowlist entry never reaches an unknown textRole on its line",
			run = function()
				local findings = planted('local e = { TextSize = 12, textRole = "banner" }\n', {
					{ file = PLANT, match = "TextSize = 12", why = "test" },
				})
				return Case.expect(
					Rule.contains(findings, "[R1] a literal TextSize") and Rule.contains(findings, "[R2]"),
					"expected both findings, got " .. Rule.describe(findings)
				)
			end,
		},
		{
			name = "a stale allowlist entry is reported",
			run = function()
				local findings =
					planted("return nil\n", { { file = PLANT, match = "Color3.new(1, 1, 1)", why = "test" } })
				return Case.same(findings, { PLANT .. ": allowlist entry 'Color3.new(1, 1, 1)' matches nothing" })
			end,
		},
		{
			name = "a known textRole and CRLF line endings pass",
			run = function()
				return silent('local f = UI.Label {\r\n\ttextRole = "title",\r\n}\r\nreturn f\r\n')
			end,
		},
		{
			name = "an example that does not parse and a missing TYPE_ROLES are reported",
			run = function()
				return Case.first(
					fires("local = 1\n", PLANT .. ": cannot parse the example"),
					Rule.within({
						[THEMES] = "return {}\n",
					}, function(context)
						return Case.same(check(context), { "cannot read TYPE_ROLES from " .. THEMES })
					end)
				)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "example-drift",
	summary = "Examples use theme roles, Host constructors and context services, not literal paint or engine reach-arounds.",
	check = check,
	cases = cases,
}

return rule
