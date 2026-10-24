--!strict
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Luau = require("../lib/luau")
local Rule = require("../lib/rule")

type Literal = { text: string, line: number, column: number }

type Finding = {
	path: string,
	line: number,
	rule: string,
	text: string,
	hint: string,
	order: { number },
}

type Pair = { name: string, line: number, column: number, value: Luau.Node }

type Metrics = { [string]: { [number]: string } }

local ALLOWLIST = "tools/theme_drift_allowlist.json"
local THEME = "src/ui/themes.luau"
local EXCLUDED = "src/vendor/"

local STATUSES: { [string]: string } = {
	structural = "derived from the part's own geometry or an invisible structural surface",
	["no-metric"] = "the theme package defines no metric or role for this sub-part",
	authored = "the value is the caller's authored override, not default paint",
}

local STATUS_LIST = "['authored', 'no-metric', 'structural']"

local FAMILIES = { "radius", "stroke", "type-size" }

local SECTIONS: { [string]: string } = { radius = "radii", stroke = "strokes", ["type-size"] = "typography" }

local REACTIVE: { [string]: string } = {
	TextSize = "type-size",
	LineHeight = "type-size",
	CornerRadius = "radius",
	Thickness = "stroke",
}

local COLOR_CONSTRUCTORS: { [string]: boolean } = { new = true, fromRGB = true, fromHex = true, fromHSV = true }

local FONT_CONSTRUCTORS = { "new", "fromEnum", "fromName", "fromId" }

local ORDER: { [string]: number } = {
	["paint-color"] = 1,
	["paint-opacity"] = 2,
	["type-size"] = 3,
	["type-face"] = 4,
	udim = 5,
	corner = 6,
	stroke = 7,
	reactive = 8,
}

local function decimal(text: string): boolean
	return string.find(text, "^%d+$") ~= nil or string.find(text, "^%d+%.%d+$") ~= nil
end

local function numberText(node: Luau.Node?): string?
	if node == nil then
		return nil
	end
	local tag = Luau.tag(node)
	if Luau.kind(node) ~= "expr" or (tag ~= "number" and tag ~= "integer") then
		return nil
	end
	return Luau.tokenText(node, "token")
end

local function leading(expression: Luau.Node): Luau.Node
	local current = expression
	while true do
		local tag = Luau.tag(current)
		local inner = if tag == "binary"
			then Luau.child(current, "lhsOperand")
			elseif tag == "cast" then Luau.child(current, "operand")
			else nil
		if inner == nil then
			return current
		end
		current = inner
	end
end

local function segments(expression: Luau.Node?): { string }
	local dotted = Luau.dotted(expression)
	if dotted == nil then
		return {}
	end
	local normalized = string.gsub(dotted, ":", ".")
	return string.split(normalized, ".")
end

local function nameOf(expression: Luau.Node): Luau.Node?
	local tag = Luau.tag(expression)
	if tag == "indexname" then
		return Luau.child(expression, "index")
	elseif tag == "global" then
		return Luau.child(expression, "name")
	elseif tag == "local" then
		return Luau.child(expression, "token")
	end
	return nil
end

local function pairsOf(parsed: Luau.Parsed): { Pair }
	local found: { Pair } = {}
	local function add(token: Luau.Node?, value: Luau.Node?)
		local name = Luau.text(token)
		if token == nil or name == nil or value == nil then
			return
		end
		local location = Luau.location(token)
		table.insert(found, { name = name, line = location.beginLine, column = location.beginColumn, value = value })
	end
	Luau.walk(parsed.root, function(node)
		local kind, tag = Luau.kind(node), Luau.tag(node)
		if kind == "record" then
			add(Luau.child(node, "key"), Luau.child(node, "value"))
		elseif kind == "stat" and tag == "assign" then
			local values = Luau.items(node, "values")
			for index, variable in Luau.items(node, "variables") do
				add(nameOf(variable), values[index])
			end
		elseif kind == "stat" and (tag == "local" or tag == "const") then
			local values = Luau.items(node, "values")
			for index, variable in Luau.items(node, "variables") do
				add(Luau.child(variable, "name"), values[index])
			end
		end
		return true
	end)
	table.sort(found, function(left: Pair, right: Pair): boolean
		if left.line ~= right.line then
			return left.line < right.line
		end
		return left.column < right.column
	end)
	return found
end

local function literals(root: Luau.Node, after: number?, before: number?): { Literal }
	local found: { Literal } = {}
	Luau.walk(root, function(node)
		local text = numberText(node)
		if text ~= nil and decimal(text) then
			local value = tonumber(text)
			local location = Luau.location(node)
			local inside = (after == nil or location.beginLine > after)
				and (before == nil or location.beginLine < before)
			if value ~= 0 and value ~= 1 and inside then
				table.insert(found, { text = text, line = location.beginLine, column = location.beginColumn })
			end
		end
		return true
	end)
	table.sort(found, function(left: Literal, right: Literal): boolean
		if left.line ~= right.line then
			return left.line < right.line
		end
		return left.column < right.column
	end)
	return found
end

local function metricValues(parsed: Luau.Parsed): { [string]: { [number]: string }? }
	local tables: { [string]: Luau.Node } = {}
	for _, pair in pairsOf(parsed) do
		local value = pair.value
		if Luau.tag(value) == "table" then
			for family, section in SECTIONS do
				if section == pair.name and family ~= "type-size" and tables[family] == nil then
					tables[family] = value
				end
			end
		end
	end
	local typography: Luau.Node? = nil
	local first = math.huge
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) == "expr" and Luau.tag(node) == "table" then
			local entry = Luau.items(node, "entries")[1]
			if entry ~= nil and Luau.kind(entry) == "record" and Luau.tokenText(entry, "key") == "caption" then
				local location = Luau.location(node)
				local position = location.beginLine * 1e6 + location.beginColumn
				if position < first then
					first = position
					typography = node
				end
			end
		end
		return true
	end)
	if typography ~= nil then
		tables["type-size"] = typography
	end
	local values: { [string]: { [number]: string }? } = {}
	for _, family in FAMILIES do
		local found = tables[family]
		if found == nil then
			continue
		end
		local labels: { [number]: { string } } = {}
		local order: { number } = {}
		for _, entry in Luau.items(found, "entries") do
			local key = Luau.tokenText(entry, "key")
			local text = numberText(Luau.child(entry, "value"))
			if Luau.kind(entry) == "record" and key ~= nil and text ~= nil and decimal(text) then
				local number = tonumber(text) :: number
				if labels[number] == nil then
					labels[number] = {}
					table.insert(order, number)
				end
				table.insert(labels[number], SECTIONS[family] .. "." .. key)
			end
		end
		local joined: { [number]: string } = {}
		for _, number in order do
			joined[number] = table.concat(labels[number], " or ")
		end
		values[family] = joined
	end
	return values
end

local function scanSource(relative: string, source: string, parsed: Luau.Parsed, metrics: Metrics): { Finding }
	local lines = string.split(source, "\n")
	local found: { Finding } = {}
	local function add(line: number, rule: string, order: { number }, values: { string })
		local hints: { string } = {}
		local table_ = metrics[rule] or {}
		for _, value in values do
			local name = table_[tonumber(value) :: number]
			if name ~= nil then
				table.insert(hints, ("%s is the neutral %s"):format(value, name))
			end
		end
		table.insert(found, {
			path = relative,
			line = line,
			rule = rule,
			text = stringext.trim(lines[line] or ""),
			hint = table.concat(hints, "; "),
			order = order,
		})
	end
	local colorLines: { [number]: boolean } = {}
	local fontLines: { [number]: boolean } = {}
	local reactiveLines: { [number]: boolean } = {}
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) ~= "expr" or Luau.tag(node) ~= "call" or Luau.child(node, "openParens") == nil then
			return true
		end
		local func = Luau.child(node, "func")
		local parts = segments(func)
		local count = #parts
		local location = Luau.location(node)
		local line = location.beginLine
		if count >= 2 then
			local owner, member = parts[count - 1], parts[count]
			if (owner == "Color3" and COLOR_CONSTRUCTORS[member]) or owner == "BrickColor" then
				if not colorLines[line] then
					colorLines[line] = true
					add(line, "paint-color", { line, ORDER["paint-color"], line, location.beginColumn }, {})
				end
			end
			if owner == "ctx" and member == "corner" then
				local values: { string } = {}
				for _, argument in Luau.items(node, "arguments") do
					for _, literal in literals(argument) do
						table.insert(values, literal.text)
					end
				end
				if #values > 0 then
					add(line, "radius", { line, ORDER.corner, line, location.beginColumn }, values)
				end
			end
		end
		return true
	end)
	for _, pair in pairsOf(parsed) do
		local value = leading(pair.value)
		local tag = Luau.tag(value)
		local text = numberText(value)
		local line = pair.line
		local function order(rule: string): { number }
			return { line, ORDER[rule], line, pair.column }
		end
		if string.sub(pair.name, -12) == "Transparency" and text ~= nil and string.find(text, "^0?%.%d+$") ~= nil then
			local number = tonumber(text) :: number
			if number > 0 and number < 1 then
				add(line, "paint-opacity", order("paint-opacity"), {})
			end
		end
		if pair.name == "TextSize" and text ~= nil and decimal(text) then
			add(line, "type-size", order("type-size"), { text })
		end
		if pair.name == "FontFace" or pair.name == "Font" then
			local reference = if tag == "call" then Luau.child(value, "func") else value
			local parts = segments(reference)
			local matched = false
			for index = 1, #parts - 1 do
				local current, following = parts[index], parts[index + 1]
				if pair.name == "FontFace" and string.sub(current, -4) == "Font" then
					for _, constructor in FONT_CONSTRUCTORS do
						if string.sub(following, 1, #constructor) == constructor then
							matched = true
						end
					end
				elseif
					pair.name == "Font"
					and string.sub(current, -4) == "Enum"
					and following == "Font"
					and parts[index + 2] ~= nil
				then
					matched = true
				end
			end
			if matched and not fontLines[line] then
				fontLines[line] = true
				add(line, "type-face", order("type-face"), {})
			end
		end
		if pair.name == "CornerRadius" and tag == "call" and Luau.child(value, "openParens") ~= nil then
			local parts = segments(Luau.child(value, "func"))
			local arguments = Luau.items(value, "arguments")
			local firstTag = if arguments[1] ~= nil then Luau.tag(arguments[1]) else ""
			local radius = numberText(arguments[2])
			if
				#parts >= 2
				and parts[#parts] == "new"
				and #arguments == 2
				and firstTag ~= "call"
				and firstTag ~= "group"
				and firstTag ~= "function"
				and firstTag ~= "table"
				and radius ~= nil
				and decimal(radius)
				and tonumber(radius) ~= 0
			then
				add(line, "radius", order("udim"), { radius })
			end
		end
		if pair.name == "Thickness" and text ~= nil and decimal(text) then
			add(line, "stroke", order("stroke"), { text })
		end
		local family = REACTIVE[pair.name]
		if family ~= nil and tag == "function" and not reactiveLines[line] then
			reactiveLines[line] = true
			local body = Luau.child(value, "body")
			local ending = Luau.child(value, "endKeyword")
			if body ~= nil and ending ~= nil then
				local grouped: { [number]: { string } } = {}
				local bodyLines: { number } = {}
				for _, literal in literals(body, line, Luau.line(ending)) do
					if grouped[literal.line] == nil then
						grouped[literal.line] = {}
						table.insert(bodyLines, literal.line)
					end
					table.insert(grouped[literal.line], literal.text)
				end
				for _, bodyLine in bodyLines do
					add(bodyLine, family, { line, ORDER.reactive, bodyLine, 0 }, grouped[bodyLine])
				end
			end
		end
	end
	table.sort(found, function(left: Finding, right: Finding): boolean
		for index = 1, 4 do
			if left.order[index] ~= right.order[index] then
				return left.order[index] < right.order[index]
			end
		end
		return false
	end)
	return found
end

local function sources(context: Rule.Context): { string }
	local found: { string } = {}
	for _, relative in Files.walk(context.path("src")) do
		local path = "src/" .. relative
		if Files.extension(path) == ".luau" and path ~= THEME and string.sub(path, 1, #EXCLUDED) ~= EXCLUDED then
			table.insert(found, path)
		end
	end
	return found
end

local function nonEmpty(value: unknown): boolean
	return type(value) == "string" and string.find(value, "%S") ~= nil
end

local function words(text: string): number
	local count = 0
	for _ in string.gmatch(text, "%S+") do
		count += 1
	end
	return count
end

local function readAllowlist(context: Rule.Context): ({ Json.Object }?, { string })
	local path = context.path(ALLOWLIST)
	if not Files.isFile(path) then
		return nil, { ("[allowlist] cannot read %s: the file does not exist"):format(ALLOWLIST) }
	end
	local decoded, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		return nil, { ("[allowlist] cannot read %s: %s"):format(ALLOWLIST, problem) }
	end
	local entries = Json.arrayField(decoded, "entries")
	if Json.asObject(decoded) == nil or entries == nil then
		return nil, { ("[allowlist] %s must hold an 'entries' list"):format(ALLOWLIST) }
	end
	local problems: { string } = {}
	local objects: { Json.Object } = {}
	for index, entry in entries do
		local where = ("%s entries[%d]"):format(ALLOWLIST, index - 1)
		local object = Json.asObject(entry)
		if object == nil then
			table.insert(problems, ("[allowlist] %s is not an object"):format(where))
			continue
		end
		for _, field in { "path", "rule", "match", "reason", "status" } do
			if not nonEmpty(object[field]) then
				table.insert(problems, ("[allowlist] %s needs a non-empty '%s'"):format(where, field))
			end
		end
		local status = Json.asString(object.status)
		if status == nil or STATUSES[status] == nil then
			table.insert(problems, ("[allowlist] %s status must be one of %s"):format(where, STATUS_LIST))
		end
		local reason = Json.asString(object.reason)
		if reason ~= nil and words(reason) < 6 then
			table.insert(problems, ("[allowlist] %s reason is too short to justify an exception"):format(where))
		end
		table.insert(objects, object)
	end
	return objects, problems
end

local function show(value: unknown): string
	if type(value) == "string" then
		return value
	end
	return "None"
end

local function check(context: Rule.Context): { string }
	local problems: { string } = {}
	local themePath = context.path(THEME)
	if not Files.isFile(themePath) then
		return { ("[rule] cannot read %s: the file does not exist"):format(THEME) }
	end
	local theme, themeProblem = Luau.parse(Files.text(themePath))
	if theme == nil then
		return { ("[rule] cannot parse %s: %s"):format(THEME, string.match(themeProblem or "", "^[^\n]*") or "") }
	end
	local declared = metricValues(theme)
	local metrics: Metrics = {}
	for _, family in FAMILIES do
		local values = declared[family]
		if values == nil or next(values) == nil then
			table.insert(
				problems,
				("[rule] %s no longer declares the %s metrics the '%s' rule protects"):format(
					THEME,
					SECTIONS[family],
					family
				)
			)
		end
		metrics[family] = values or {}
	end
	local entries, allowlistProblems = readAllowlist(context)
	if entries == nil then
		return allowlistProblems
	end
	for _, problem in allowlistProblems do
		table.insert(problems, problem)
	end
	local used: { number } = table.create(#entries, 0)
	for _, relative in sources(context) do
		local source = Files.text(context.path(relative))
		local parsed, parseProblem = Luau.parse(source)
		if parsed == nil then
			table.insert(
				problems,
				("[parse] %s: cannot parse Luau: %s"):format(
					relative,
					string.match(parseProblem or "", "^[^\n]*") or ""
				)
			)
			continue
		end
		for _, finding in scanSource(relative, source, parsed, metrics) do
			local covered = false
			for position, entry in entries do
				local match = entry.match
				if
					entry.path == relative
					and entry.rule == finding.rule
					and type(match) == "string"
					and string.find(finding.text, match, 1, true) ~= nil
				then
					used[position] += 1
					covered = true
				end
			end
			if not covered then
				local hint = if finding.hint ~= "" then (" (%s; read it from the theme)"):format(finding.hint) else ""
				table.insert(
					problems,
					("[%s] %s:%d: %s%s"):format(finding.rule, finding.path, finding.line, finding.text, hint)
				)
			end
		end
	end
	for position, entry in entries do
		if used[position] == 0 then
			table.insert(
				problems,
				("[allowlist] stale entry %s %s '%s' matches nothing"):format(
					show(entry.path),
					show(entry.rule),
					show(entry.match)
				)
			)
		end
	end
	return problems
end

local THEME_SOURCE = table.concat({
	"--!strict",
	"local neutral = {",
	"\tradii = { control = 8, panel = 12, pill = 999, tab = 999 },",
	"\tstrokes = { hairline = 1 },",
	"}",
	"local typography = { caption = 12, label = 14, body = 16 }",
	"return { neutral = neutral, typography = typography }",
	"",
}, "\n")

local CONTROL_SOURCE = table.concat({
	"--!strict",
	"return function(ctx, Host, D)",
	"\treturn Host.Frame({",
	"\t\tBackgroundTransparency = 1,",
	"\t\tctx.corner(2),",
	'\t\tHost.TextLabel({ Text = "Color3.new(1, 0, 0) TextSize = 18" }),',
	"\t})",
	"end",
	"",
}, "\n")

local function allowlist(entries: { { [string]: string } }): string
	local encoded: { unknown } = {}
	for _, entry in entries do
		table.insert(encoded, entry)
	end
	return Json.encode({ entries = encoded })
end

local BASE_ENTRY: { [string]: string } = {
	path = "src/ui/inputs.luau",
	rule = "radius",
	match = "ctx.corner(2),",
	status = "structural",
	reason = "The activity dots are fixed 4x4 px circles; radius 2 is half the dot.",
}

local function fixture(control: string, entries: { { [string]: string } }): { [string]: string }
	return {
		[THEME] = THEME_SOURCE,
		["src/ui/inputs.luau"] = control,
		["src/vendor/compose/paint.luau"] = "return Color3.fromRGB(1, 2, 3)\n",
		[ALLOWLIST] = allowlist(entries),
	}
end

local function planted(text: string): string
	return "--!strict\nlocal planted = {\n\t\t\t" .. text .. "\n}\n" .. string.sub(CONTROL_SOURCE, #"--!strict\n" + 1)
end

type Plant = { name: string, text: string, rule: string, expected: string? }

local PLANTS: { Plant } = {
	{
		name = "a hardcoded paint color in a control",
		text = "BackgroundColor3 = Color3.fromRGB(40, 40, 40),",
		rule = "paint-color",
	},
	{ name = "a fractional opacity literal", text = "BackgroundTransparency = 0.35,", rule = "paint-opacity" },
	{
		name = "a literal text size",
		text = "TextSize = 18,",
		rule = "type-size",
		expected = "[type-size] src/ui/inputs.luau:3: TextSize = 18,",
	},
	{
		name = "a hardcoded font face",
		text = 'FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json"),',
		rule = "type-face",
	},
	{
		name = "a literal control corner radius",
		text = "Host.UICorner({ CornerRadius = D.new(0, 8) }),",
		rule = "radius",
		expected = "[radius] src/ui/inputs.luau:3: Host.UICorner({ CornerRadius = D.new(0, 8) }), (8 is the neutral radii.control; read it from the theme)",
	},
	{ name = "a literal radius through the corner helper", text = "ctx.corner(8),", rule = "radius" },
	{
		name = "a named corner table inside a reactive radius",
		text = "CornerRadius = function(use)\n\t\t\t\treturn D.new(0, ({ square = 0, rounded = 8 }).rounded)\n\t\t\tend,",
		rule = "radius",
		expected = "[radius] src/ui/inputs.luau:4: return D.new(0, ({ square = 0, rounded = 8 }).rounded) (8 is the neutral radii.control; read it from the theme)",
	},
	{
		name = "a literal stroke thickness",
		text = "Thickness = 2,",
		rule = "stroke",
	},
	{
		name = "a literal inside a reactive text size",
		text = "TextSize = function(use)\n\t\t\t\treturn 18\n\t\t\tend,",
		rule = "type-size",
		expected = "[type-size] src/ui/inputs.luau:4: return 18",
	},
	{
		name = "an enum font",
		text = "Font = Enum.Font.GothamBold,",
		rule = "type-face",
	},
	{
		name = "a pill radius names every matching metric",
		text = "ctx.corner(999),",
		rule = "radius",
		expected = "[radius] src/ui/inputs.luau:3: ctx.corner(999), (999 is the neutral radii.pill or radii.tab; read it from the theme)",
	},
}

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the unplanted fixture passes and vendor sources are skipped", {
		id = prefix .. "the unplanted fixture passes and vendor sources are skipped",
		run = function(test: Verify.Context)
			Rule.within(test, fixture(CONTROL_SOURCE, { BASE_ENTRY }), function(context)
				Verify.expect(check(context)):toEqual({})
			end)
		end,
	})
	for _, plant in PLANTS do
		harness:case(prefix .. ("plant: " .. plant.name), {
			id = prefix .. ("plant: " .. plant.name),
			run = function(test: Verify.Context)
				Rule.within(test, fixture(planted(plant.text), { BASE_ENTRY }), function(context)
					local findings = check(context)
					local prefix = ("[%s] src/ui/inputs.luau"):format(plant.rule)
					local bitten = false
					for _, finding in findings do
						if string.sub(finding, 1, #prefix) == prefix then
							bitten = true
						end
					end
					if not bitten then
						error("the plant stayed green: " .. Rule.describe(findings), 0)
					end
					local expected = plant.expected
					if expected ~= nil and table.find(findings, expected) == nil then
						error(("expected %q in %s"):format(expected, Rule.describe(findings)), 0)
					end
					return
				end)
			end,
		})
	end
	harness:case(prefix .. "a stale, short-reasoned or unknown-status allowlist entry bites", {
		id = prefix .. "a stale, short-reasoned or unknown-status allowlist entry bites",
		run = function(test: Verify.Context)
			local bad = {
				path = "src/ui/inputs.luau",
				rule = "radius",
				match = "ctx.corner(77)",
				reason = "short",
				status = "maybe",
			}
			Rule.within(test, fixture(CONTROL_SOURCE, { BASE_ENTRY, bad }), function(context)
				Verify.expect(check(context)):toEqual({
					"[allowlist] tools/theme_drift_allowlist.json entries[1] status must be one of ['authored', 'no-metric', 'structural']",
					"[allowlist] tools/theme_drift_allowlist.json entries[1] reason is too short to justify an exception",
					"[allowlist] stale entry src/ui/inputs.luau radius 'ctx.corner(77)' matches nothing",
				})
			end)
		end,
	})
	harness:case(prefix .. "an allowlist entry needs every field", {
		id = prefix .. "an allowlist entry needs every field",
		run = function(test: Verify.Context)
			Rule.within(
				test,
				fixture(CONTROL_SOURCE, { BASE_ENTRY, { path = "src/ui/inputs.luau" } }),
				function(context)
					Verify.expect(check(context)):toEqual({
						"[allowlist] tools/theme_drift_allowlist.json entries[1] needs a non-empty 'rule'",
						"[allowlist] tools/theme_drift_allowlist.json entries[1] needs a non-empty 'match'",
						"[allowlist] tools/theme_drift_allowlist.json entries[1] needs a non-empty 'reason'",
						"[allowlist] tools/theme_drift_allowlist.json entries[1] needs a non-empty 'status'",
						"[allowlist] tools/theme_drift_allowlist.json entries[1] status must be one of ['authored', 'no-metric', 'structural']",
						"[allowlist] stale entry src/ui/inputs.luau None 'None' matches nothing",
					})
				end
			)
		end,
	})
	harness:case(prefix .. "a malformed allowlist and a theme without metrics are reported", {
		id = prefix .. "a malformed allowlist and a theme without metrics are reported",
		run = function(test: Verify.Context)
			local files = fixture(CONTROL_SOURCE, {})
			files[ALLOWLIST] = '{"entries": {}}'
			Rule.within(test, files, function(context)
				Verify.expect(check(context)):toEqual({
					"[allowlist] tools/theme_drift_allowlist.json must hold an 'entries' list",
				})
				Files.write(context.path(ALLOWLIST), allowlist({ BASE_ENTRY }))
				Files.write(context.path(THEME), "--!strict\nreturn { radii = {} }\n")
				Verify.expect(check(context)):toEqual({
					"[rule] src/ui/themes.luau no longer declares the radii metrics the 'radius' rule protects",
					"[rule] src/ui/themes.luau no longer declares the strokes metrics the 'stroke' rule protects",
					"[rule] src/ui/themes.luau no longer declares the typography metrics the 'type-size' rule protects",
				})
			end)
		end,
	})
	harness:case(prefix .. "literals in strings, zero opacity and whole numbers in helpers stay clean", {
		id = prefix .. "literals in strings, zero opacity and whole numbers in helpers stay clean",
		run = function(test: Verify.Context)
			local source = planted(
				'BackgroundTransparency = 0,\n\t\t\tTextTransparency = 1,\n\t\t\tctx.corner(1),\n\t\t\tName = "TextSize = 18",'
			)
			Rule.within(test, fixture(source, { BASE_ENTRY }), function(context)
				Verify.expect(check(context)):toEqual({})
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "theme-drift",
	summary = "Framework controls read paint, type and metric values from the theme, not literals.",
	check = check,
	register = register,
}

return rule
