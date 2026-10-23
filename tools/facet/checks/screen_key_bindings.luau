--!strict

local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Luau = require("../lib/luau")
local Rule = require("../lib/rule")

type Pin = { path: string, count: number, reason: string }

type Hit = { rule: string, line: number, column: number, text: string }

type Detection = { hits: { Hit }, sites: number, parsed: boolean }

type Pattern = { rule: string, name: string, reason: string }

type Totals = { snippets: number, fallbacks: number, fallbackLabels: { string } }

local FACET_SOURCES = { "src/ui", "src/init.luau" }
local SCREEN_SOURCES = { "examples" }
local TEACHING_DOCS = { "README.md", "docs/guide", "docs/reference", "docs/extending", "examples", "skills" }

local SERVICE = "ContextActionService"

local SERVICE_PATTERN: Pattern = {
	rule = "service",
	name = "ContextActionService",
	reason = "Facet controls bind keys only through native InputContext and InputAction",
}
local BIND_PATTERN: Pattern = {
	rule = "bind",
	name = "BindAction",
	reason = "ContextActionService binding is a second input system",
}
local INSTANCE_PATTERN: Pattern = {
	rule = "instance",
	name = "raw input Instance",
	reason = "Compose owns input Instances through the host constructors",
}
local POLLING_PATTERN: Pattern = {
	rule = "polling",
	name = "key polling",
	reason = "a screen polls the keyboard or gamepad itself",
}
local DEVICE_PATTERN: Pattern = {
	rule = "device",
	name = "key device test",
	reason = "a screen classifies raw key input itself",
}

local FACET_PATTERNS = { SERVICE_PATTERN, BIND_PATTERN, INSTANCE_PATTERN }
local PROBE_PATTERNS = { BIND_PATTERN, INSTANCE_PATTERN }
local SCREEN_PATTERNS = { SERVICE_PATTERN, BIND_PATTERN, INSTANCE_PATTERN, POLLING_PATTERN, DEVICE_PATTERN }

local KEY_READ_REASON = "a screen inspects raw key codes itself"

local READ_ONLY_PROBES: { [string]: string } = {
	["src/ui/gamepad_contention.luau"] = "Facet.gamepadContention reads the legacy player scripts' ContextActionService bindings and can unbind their jumpAction; it binds no key",
}

local PINS: { Pin } = {
	{
		path = "examples/facet-lab/src/hint_pages.luau",
		count = 1,
		reason = "the ShortcutHint variant describes one native F2 InputBinding on a detached InputAction; it does not capture screen input",
	},
	{
		path = "examples/gallery/examples/05_word_game.luau",
		count = 3,
		reason = "the word game declares letter, Submit and Backspace keys in its own sinking InputContext under ctx.inputTarget, the documented seam for game hotkeys",
	},
	{
		path = "examples/gallery/examples/06_tile_game.luau",
		count = 1,
		reason = "the crossword declares its letter keys in its own sinking InputContext under ctx.inputTarget",
	},
	{
		path = "examples/virtual_monitors/screens.luau",
		count = 1,
		reason = "Discover owns the Slash InputAction that its ShortcutHint describes and that focuses the search field, as docs/reference/api.md documents for the hint's action option",
	},
	{
		path = "examples/gallery/scenarios/shortcut_hint.luau",
		count = 3,
		reason = "the ShortcutHint recipe owns the InputAction that the hint describes, as docs/reference/api.md documents for its action option",
	},
	{
		path = "examples/gallery/client/screen.luau",
		count = 1,
		reason = "the Showcase chrome declares LB and backquote through one InputBinding factory in owned InputContexts; CollapsibleView owns cancellation",
	},
	{
		path = "examples/virtual_monitors/main.client.luau",
		count = 2,
		reason = "the View button switches presentation and Space flaps only in the active game; both use owned InputContexts at Facet.inputPriority.belowControls",
	},
	{
		path = "examples/gallery/scenarios/outpost_terminal.luau",
		count = 2,
		reason = "the world terminal declares LeaveConsole on Escape and ButtonB while engaged, in its own InputContext under ctx.inputTarget",
	},
}

local BIND_METHODS: { [string]: boolean } = {
	BindAction = true,
	BindCoreAction = true,
	BindActionAtPriority = true,
	BindCoreActionAtPriority = true,
}

local POLLING_METHODS: { [string]: boolean } = {
	IsKeyDown = true,
	GetKeysPressed = true,
	IsGamepadButtonDown = true,
	GetGamepadState = true,
}

local INPUT_CLASSES: { [string]: boolean } = { InputBinding = true, InputAction = true, InputContext = true }

local ENUM_ALIASES: { [string]: boolean } = { Enum = true, E = true }

local function wordByte(byte: number?): boolean
	if byte == nil then
		return false
	end
	return byte >= 0x80
		or byte == 0x5F
		or (byte >= 0x30 and byte <= 0x39)
		or (byte >= 0x41 and byte <= 0x5A)
		or (byte >= 0x61 and byte <= 0x7A)
end

local function closeLong(source: string, from: number, level: number): number
	local closer = "]" .. string.rep("=", level) .. "]"
	local found = string.find(source, closer, from, true)
	if found == nil then
		return #source + 1
	end
	return found + #closer
end

local function blankComments(source: string): string
	local parts: { string } = {}
	local length = #source
	local index = 1
	while index <= length do
		local char = string.sub(source, index, index)
		if char == "-" and string.sub(source, index, index + 1) == "--" then
			local level = string.match(source, "^%[(=*)%[", index + 2)
			local stop: number
			if level ~= nil then
				stop = closeLong(source, index + 2 + #level + 2, #level)
			else
				stop = string.find(source, "\n", index, true) or length + 1
			end
			local blanked = string.gsub(string.sub(source, index, stop - 1), "[^\n]", " ")
			table.insert(parts, blanked)
			index = stop
		elseif char == "[" then
			local level = string.match(source, "^%[(=*)%[", index)
			if level ~= nil then
				local stop = closeLong(source, index + #level + 2, #level)
				table.insert(parts, string.sub(source, index, stop - 1))
				index = stop
			else
				table.insert(parts, char)
				index += 1
			end
		elseif char == '"' or char == "'" or char == "`" then
			local cursor = index + 1
			while cursor <= length and string.sub(source, cursor, cursor) ~= char do
				local current = string.sub(source, cursor, cursor)
				if current == "\\" then
					cursor += 2
				elseif current == "\n" and char ~= "`" then
					break
				else
					cursor += 1
				end
			end
			local stop = math.min(cursor + 1, length + 1)
			table.insert(parts, string.sub(source, index, stop - 1))
			index = stop
		else
			table.insert(parts, char)
			index += 1
		end
	end
	return table.concat(parts)
end

local function lineStarts(code: string): { number }
	local starts = { 1 }
	local index = 1
	while true do
		local newline = string.find(code, "\n", index, true)
		if newline == nil then
			break
		end
		table.insert(starts, newline + 1)
		index = newline + 1
	end
	return starts
end

local function lineAt(starts: { number }, offset: number): number
	local low, high = 1, #starts
	while low < high do
		local middle = (low + high + 1) // 2
		if starts[middle] <= offset then
			low = middle
		else
			high = middle - 1
		end
	end
	return low
end

local function skipSpace(code: string, index: number): number
	return string.find(code, "[^%s]", index) or #code + 1
end

local function methodAt(code: string, colon: number, names: { [string]: boolean }): string?
	local start = skipSpace(code, colon + 1)
	local name = string.match(code, "^[%a_][%w_]*", start)
	if name == nil or not names[name] then
		return nil
	end
	local after = skipSpace(code, start + #name)
	if string.sub(code, after, after) ~= "(" then
		return nil
	end
	return string.sub(code, colon, after)
end

local function textDetection(code: string, screen: boolean): Detection
	local hits: { Hit } = {}
	local starts = lineStarts(code)
	local function add(rule: string, offset: number, text: string)
		table.insert(hits, { rule = rule, line = lineAt(starts, offset), column = offset, text = text })
	end
	local index = 1
	while true do
		local found = string.find(code, SERVICE, index, true)
		if found == nil then
			break
		end
		add("service", found, SERVICE)
		index = found + #SERVICE
	end
	index = 1
	while true do
		local colon = string.find(code, ":", index, true)
		if colon == nil then
			break
		end
		local bind = methodAt(code, colon, BIND_METHODS)
		if bind ~= nil then
			add("bind", colon, bind)
		end
		local polling = methodAt(code, colon, POLLING_METHODS)
		if polling ~= nil then
			add("polling", colon, polling)
		end
		index = colon + 1
	end
	index = 1
	while true do
		local found = string.find(code, "Instance.new(", index, true)
		if found == nil then
			break
		end
		local quote = skipSpace(code, found + 13)
		local opener = string.sub(code, quote, quote)
		if opener == '"' or opener == "'" or opener == "`" then
			local class = string.match(code, "^Input%a+", quote + 1)
			local closer = if class then string.sub(code, quote + 1 + #class, quote + 1 + #class) else ""
			if class ~= nil and INPUT_CLASSES[class] and (closer == '"' or closer == "'" or closer == "`") then
				add("instance", found, string.sub(code, found, quote + 1 + #class))
			end
		end
		index = found + 1
	end
	index = 1
	while true do
		local found = string.find(code, "UserInputType.", index, true)
		if found == nil then
			break
		end
		local member = found + 14
		local keyboard = string.sub(code, member, member + 7) == "Keyboard"
			and not wordByte(string.byte(code, member + 8))
		local gamepad = string.match(code, "^Gamepad[%w_\128-\255]*", member)
		if keyboard then
			add("device", found, "UserInputType.Keyboard")
		elseif gamepad ~= nil then
			add("device", found, "UserInputType." .. gamepad)
		end
		index = found + 1
	end
	local sites = 0
	index = 1
	while true do
		local found = string.find(code, "InputBinding", index, true)
		if found == nil then
			break
		end
		if not wordByte(string.byte(code, found - 1)) then
			local after = skipSpace(code, found + 12)
			local next = string.sub(code, after, after)
			if next == "(" or next == "{" then
				sites += 1
			end
		end
		index = found + 1
	end
	if screen then
		index = 1
		while true do
			local found = string.find(code, ".KeyCode", index, true)
			if found == nil then
				break
			end
			index = found + 1
			if wordByte(string.byte(code, found + 8)) then
				continue
			end
			local start = found
			while start > 1 and wordByte(string.byte(code, start - 1)) do
				start -= 1
			end
			local name = string.sub(code, start, found - 1)
			local before = string.sub(code, start - 1, start - 1)
			if
				name ~= ""
				and string.match(name, "^[%a_]") ~= nil
				and (start == 1 or before ~= ".")
				and not ENUM_ALIASES[name]
			then
				add("key", start, name .. ".KeyCode")
			end
		end
	end
	return { hits = hits, sites = sites, parsed = false }
end

local function plainName(expression: Luau.Node?): string?
	if expression == nil then
		return nil
	end
	local tag = Luau.tag(expression)
	if tag == "global" then
		return Luau.tokenText(expression, "name")
	elseif tag == "local" then
		return Luau.tokenText(expression, "token")
	end
	return nil
end

local function lastName(expression: Luau.Node?): string?
	if expression ~= nil and Luau.tag(expression) == "indexname" then
		return Luau.tokenText(expression, "index")
	end
	return plainName(expression)
end

local function astDetection(parsed: Luau.Parsed, screen: boolean): Detection
	local hits: { Hit } = {}
	local sites = 0
	local handled: { [Luau.Node]: boolean } = {}
	local function add(rule: string, node: Luau.Node, text: string)
		local location = Luau.location(node)
		table.insert(hits, { rule = rule, line = location.beginLine, column = location.beginColumn, text = text })
	end
	local function service(node: Luau.Node, text: string?)
		if text ~= nil and string.find(text, SERVICE, 1, true) ~= nil then
			add("service", node, SERVICE)
		end
	end
	Luau.walk(parsed.root, function(node)
		local kind, tag = Luau.kind(node), Luau.tag(node)
		if kind == "token" then
			if not handled[node] then
				service(node, Luau.text(node))
			end
			return true
		end
		if kind ~= "expr" then
			return true
		end
		if tag == "string" then
			local value = Luau.child(node, "value")
			if value ~= nil then
				handled[value] = true
			end
			service(node, Luau.stringValue(node))
		elseif tag == "interpolatedstring" then
			for _, piece in Luau.items(node, "strings") do
				handled[piece] = true
				service(piece, Luau.text(piece))
			end
		elseif tag == "call" then
			local func = Luau.child(node, "func")
			local arguments = Luau.items(node, "arguments")
			if node.self == true and func ~= nil and Luau.tag(func) == "indexname" then
				local method = Luau.tokenText(func, "index") or ""
				if BIND_METHODS[method] then
					add("bind", node, ":" .. method .. "(")
				elseif POLLING_METHODS[method] then
					add("polling", node, ":" .. method .. "(")
				end
			end
			local callee = Luau.dotted(func) or ""
			if callee == "Instance.new" or string.sub(callee, -13) == ".Instance.new" then
				local first = arguments[1]
				local class = if first ~= nil then Luau.stringValue(first) else nil
				if class ~= nil and INPUT_CLASSES[class] then
					add("instance", node, ('Instance.new("%s")'):format(class))
				end
			end
			if lastName(func) == "InputBinding" then
				local first = arguments[1]
				if Luau.child(node, "openParens") ~= nil or (first ~= nil and Luau.tag(first) == "table") then
					sites += 1
				end
			end
		elseif tag == "indexname" then
			local index = Luau.tokenText(node, "index") or ""
			local accessor = Luau.tokenText(node, "accessor")
			local base = Luau.child(node, "expression")
			if
				accessor == "."
				and (index == "Keyboard" or string.sub(index, 1, 7) == "Gamepad")
				and lastName(base) == "UserInputType"
			then
				add("device", node, "UserInputType." .. index)
			end
			if screen and accessor == "." and index == "KeyCode" then
				local name = plainName(base)
				if name ~= nil and not ENUM_ALIASES[name] then
					add("key", node, name .. ".KeyCode")
				end
			end
		end
		return true
	end)
	return { hits = hits, sites = sites, parsed = true }
end

local function detect(source: string, screen: boolean, text: boolean?): Detection
	if not text then
		local parsed = Luau.parse(source)
		if parsed ~= nil then
			return astDetection(parsed, screen)
		end
	end
	return textDetection(blankComments(source), screen)
end

local function offences(label: string, detection: Detection, patterns: { Pattern }, screen: boolean): { string }
	local ordered = table.clone(detection.hits)
	table.sort(ordered, function(left: Hit, right: Hit): boolean
		if left.line ~= right.line then
			return left.line < right.line
		end
		return left.column < right.column
	end)
	local found: { string } = {}
	for _, pattern in patterns do
		for _, hit in ordered do
			if hit.rule == pattern.rule then
				table.insert(
					found,
					("%s:%d: %s `%s` (%s)"):format(label, hit.line, pattern.name, hit.text, pattern.reason)
				)
			end
		end
	end
	if screen then
		for _, hit in ordered do
			if hit.rule == "key" then
				table.insert(found, ("%s:%d: key read `%s` (%s)"):format(label, hit.line, hit.text, KEY_READ_REASON))
			end
		end
	end
	return found
end

local function filesUnder(context: Rule.Context, root: string, suffixes: { [string]: boolean }): { string }
	local base = context.path(root)
	if Files.isFile(base) then
		return if suffixes[Files.extension(root)] then { root } else {}
	end
	local found: { string } = {}
	for _, relative in Files.walk(base) do
		if suffixes[Files.extension(relative)] then
			table.insert(found, root .. "/" .. relative)
		end
	end
	return found
end

type Snippet = { start: number, code: string }

local function snippets(text: string): { Snippet }
	local lines = string.split(text, "\n")
	local found: { Snippet } = {}
	local index = 1
	while index <= #lines do
		local line = lines[index]
		if string.match(line, "^```luau?%s*$") == nil then
			index += 1
			continue
		end
		local first = index + 1
		while first <= #lines and string.match(lines[first], "^%s*$") ~= nil do
			first += 1
		end
		local closing = first
		while closing <= #lines and string.match(lines[closing], "^```%s*$") == nil do
			closing += 1
		end
		if closing > #lines then
			break
		end
		local body = table.concat(lines, "\n", first, closing - 1)
		table.insert(found, {
			start = first - 2,
			code = "\n" .. body .. (if closing > first then "\n" else ""),
		})
		index = closing + 1
	end
	return found
end

local function scan(context: Rule.Context, pins: { Pin }, totals: Totals?): { string }
	local found: { string } = {}
	local sites: { [string]: number } = {}
	for _, root in FACET_SOURCES do
		for _, relative in filesUnder(context, root, { [".luau"] = true }) do
			local patterns = if READ_ONLY_PROBES[relative] then PROBE_PATTERNS else FACET_PATTERNS
			local detection = detect(Files.text(context.path(relative)), false)
			for _, offence in offences(relative, detection, patterns, false) do
				table.insert(found, offence)
			end
		end
	end
	for _, root in SCREEN_SOURCES do
		for _, relative in filesUnder(context, root, { [".luau"] = true, [".lua"] = true }) do
			local detection = detect(Files.text(context.path(relative)), true)
			for _, offence in offences(relative, detection, SCREEN_PATTERNS, true) do
				table.insert(found, offence)
			end
			if detection.sites > 0 then
				sites[relative] = detection.sites
			end
		end
	end
	local seen: { [string]: boolean } = {}
	for _, root in TEACHING_DOCS do
		for _, relative in filesUnder(context, root, { [".md"] = true }) do
			if seen[relative] then
				continue
			end
			seen[relative] = true
			for _, snippet in snippets(Files.text(context.path(relative))) do
				local detection = detect(snippet.code, true)
				local label = ("%s+%d"):format(relative, snippet.start)
				if totals ~= nil then
					totals.snippets += 1
					if not detection.parsed then
						totals.fallbacks += 1
						table.insert(totals.fallbackLabels, label)
					end
				end
				for _, offence in offences(label, detection, SCREEN_PATTERNS, true) do
					table.insert(found, offence)
				end
				if detection.sites > 0 then
					sites[relative] = (sites[relative] or 0) + detection.sites
				end
			end
		end
	end
	local pinned: { [string]: Pin } = {}
	for _, pin in pins do
		pinned[pin.path] = pin
	end
	local sitePaths: { string } = {}
	for path in sites do
		table.insert(sitePaths, path)
	end
	table.sort(sitePaths)
	for _, path in sitePaths do
		local count = sites[path]
		local pin = pinned[path]
		if pin == nil then
			table.insert(
				found,
				("%s: %d unpinned InputBinding declaration site(s); a screen claims keys without an approved pin"):format(
					path,
					count
				)
			)
		elseif pin.count ~= count then
			table.insert(
				found,
				("%s: %d InputBinding declaration site(s); the pin records %d"):format(path, count, pin.count)
			)
		end
	end
	local stale: { string } = {}
	for path in pinned do
		if sites[path] == nil then
			table.insert(stale, path)
		end
	end
	table.sort(stale)
	for _, path in stale do
		table.insert(found, ("%s: pinned InputBinding sites are gone; remove the stale pin"):format(path))
	end
	for _, pin in pins do
		if string.match(pin.reason, "^%s*$") ~= nil or pin.count <= 0 then
			table.insert(found, ("%s: every pin needs a positive count and a reason"):format(pin.path))
		end
	end
	return found
end

local function check(context: Rule.Context): { string }
	return scan(context, PINS)
end

local function serviceSeen(source: string, text: boolean?): boolean
	for _, hit in detect(source, true, text).hits do
		if hit.rule == "service" then
			return true
		end
	end
	return false
end

local function red(source: string, text: boolean?): boolean
	return #offences("case", detect(source, true, text), SCREEN_PATTERNS, true) > 0
end

type Expectation = { name: string, source: string, expected: boolean }

type SiteExpectation = { name: string, source: string, expected: number }

local LEXER_CASES: { Expectation } = {
	{ name = "a line comment is stripped", source = "x = 1 -- ContextActionService\n", expected = false },
	{
		name = "a block comment is stripped",
		source = "--[[\n\tContextActionService priority\n]]\n",
		expected = false,
	},
	{ name = "a level-2 long comment is stripped", source = "--[==[\nContextActionService\n]==]\n", expected = false },
	{
		name = "a level-1 close does not close a level-2 comment",
		source = "--[==[\n]]\nContextActionService\n]==]\n",
		expected = false,
	},
	{
		name = "an unterminated block comment blanks to the end",
		source = "--[[\nContextActionService\n",
		expected = false,
	},
	{
		name = "an inline block comment is stripped",
		source = "a --[[ ContextActionService ]] b = 1\n",
		expected = false,
	},
	{
		name = "a service name in a string is seen",
		source = 'local s = game:GetService("ContextActionService")\n',
		expected = true,
	},
	{
		name = "code after a block comment is seen",
		source = "--[[ prose ]]\nlocal u = ContextActionService\n",
		expected = true,
	},
	{
		name = "code before a trailing comment is seen",
		source = "local u = ContextActionService -- why\n",
		expected = true,
	},
	{
		name = "a dash pair inside a string does not open a comment",
		source = 'local d = "--" .. ContextActionService\n',
		expected = true,
	},
	{ name = "long comments do not nest", source = "--[[ [[ ]] ContextActionService ]]\n", expected = true },
	{ name = "long string contents stay visible", source = "local s = [[ContextActionService]]\n", expected = true },
	{
		name = "an escaped quote does not end the string",
		source = 'local s = "a\\"-- " .. ContextActionService\n',
		expected = true,
	},
	{
		name = "an interpolated string does not swallow the line",
		source = "local s = `a{b}` .. ContextActionService\n",
		expected = true,
	},
}

local RULE_CASES: { Expectation } = {
	{ name = "a key comparison is red", source = "if input.KeyCode == Enum.KeyCode.Q then end\n", expected = true },
	{
		name = "a reversed key comparison is red",
		source = "if Enum.KeyCode.Q == event.KeyCode then end\n",
		expected = true,
	},
	{ name = "a key table lookup is red", source = "local f = handlers[input.KeyCode]\n", expected = true },
	{ name = "IsKeyDown polling is red", source = "local down = service:IsKeyDown(Enum.KeyCode.W)\n", expected = true },
	{
		name = "a keyboard device test is red",
		source = "if input.UserInputType == Enum.UserInputType.Keyboard then end\n",
		expected = true,
	},
	{
		name = "a ContextActionService bind is red",
		source = "cas:BindAction('Jump', jump, false, Enum.KeyCode.Space)\n",
		expected = true,
	},
	{
		name = "a raw InputBinding Instance is red",
		source = 'local b = Instance.new("InputBinding")\n',
		expected = true,
	},
	{
		name = "an enum value in a declaration is clean",
		source = "Host.InputBinding({ KeyCode = Enum.KeyCode.Return })\n",
		expected = false,
	},
	{ name = "an aliased enum value is clean", source = "local k = E.KeyCode.Return\n", expected = false },
	{ name = "a field-path enum is clean", source = "local k = types.Enum.KeyCode.Return\n", expected = false },
	{
		name = "a pointer device test is clean",
		source = "if input.UserInputType == E.UserInputType.Touch then end\n",
		expected = false,
	},
	{
		name = "a commented key comparison is clean",
		source = "-- if input.KeyCode == Enum.KeyCode.Q then end\n",
		expected = false,
	},
	{
		name = "a gamepad device test is red",
		source = "local pad = input.UserInputType == Enum.UserInputType.Gamepad1\n",
		expected = true,
	},
	{
		name = "a prioritized core bind is red",
		source = "cas:BindCoreActionAtPriority('Jump', jump, false, 1)\n",
		expected = true,
	},
}

local SITE_CASES: { SiteExpectation } = {
	{
		name = "a commented declaration does not count",
		source = "-- Host.InputBinding({ KeyCode = Enum.KeyCode.Tab })\n",
		expected = 0,
	},
	{
		name = "a class name string does not count",
		source = 'action:FindFirstChildWhichIsA("InputBinding")\n',
		expected = 0,
	},
	{
		name = "a call declaration counts",
		source = "Host.InputBinding({ KeyCode = Enum.KeyCode.Tab })\n",
		expected = 1,
	},
	{
		name = "a table-call declaration counts",
		source = "Host.InputBinding { KeyCode = Enum.KeyCode.Tab }\n",
		expected = 1,
	},
	{
		name = "two declarations on one line count twice",
		source = "local t = { Host.InputBinding({}), Host.InputBinding({}) }\n",
		expected = 2,
	},
}

type Plant = { name: string, path: string, content: string }

local PLANTS: { Plant } = {
	{
		name = "a raw key handler",
		path = "examples/gallery/scenarios/planted.luau",
		content = '--!strict\nlocal uis = game:GetService("UserInputService")\nuis.InputBegan:Connect(function(input)\n\tif input.KeyCode == Enum.KeyCode.Q then\n\t\tprint("q")\n\tend\nend)\n',
	},
	{
		name = "an unpinned native binding",
		path = "examples/consumer/src/planted.luau",
		content = "--!strict\nreturn function(Host)\n\treturn Host.InputBinding({ KeyCode = Enum.KeyCode.Q })\nend\n",
	},
	{
		name = "a ContextActionService bind in Facet",
		path = "src/ui/planted.luau",
		content = '--!strict\nlocal cas = game:GetService("ContextActionService")\nreturn cas\n',
	},
	{
		name = "a key comparison in a teaching snippet",
		path = "docs/guide/planted.md",
		content = "# Planted\n\n```luau\nif input.KeyCode == Enum.KeyCode.Q then\nend\n```\n",
	},
	{
		name = "a key comparison in an unparsable teaching snippet",
		path = "docs/reference/planted.md",
		content = "# Planted\n\n```lua\nif input.KeyCode == Enum.KeyCode.Q then\n```\n",
	},
}

local BASELINE: { [string]: string } = {
	["src/init.luau"] = "--!strict\nreturn {}\n",
	["src/ui/gamepad_contention.luau"] = '--!strict\nlocal cas = game:GetService("ContextActionService")\nreturn cas\n',
	["examples/gallery/scenarios/keys.luau"] = "--!strict\nreturn function(Host)\n\treturn Host.InputBinding({ KeyCode = Enum.KeyCode.Return })\nend\n",
	["docs/guide/input.md"] = "# Input\n\n```luau\nlocal action = Host.InputAction({})\n```\n",
	["README.md"] = "# Readme\n",
}

local BASELINE_PINS: { Pin } = {
	{ path = "examples/gallery/scenarios/keys.luau", count = 1, reason = "the fixture owns one Return binding" },
}

local function cases(): { Rule.Case }
	local built: { Rule.Case } = {}
	for _, expectation in LEXER_CASES do
		table.insert(built, {
			name = "lexer: " .. expectation.name,
			run = function()
				local blanked = blankComments(expectation.source)
				local _, sourceLines = string.gsub(expectation.source, "\n", "")
				local _, blankedLines = string.gsub(blanked, "\n", "")
				return Case.first(
					Case.equal(serviceSeen(expectation.source, true), expectation.expected, "the text scan"),
					Case.equal(serviceSeen(expectation.source), expectation.expected, "the parse-or-scan path"),
					Case.equal(#blanked, #expectation.source, "the blanked length"),
					Case.equal(blankedLines, sourceLines, "the blanked line count")
				)
			end,
		})
	end
	for _, expectation in RULE_CASES do
		table.insert(built, {
			name = "rule: " .. expectation.name,
			run = function()
				local parsed = Luau.parse(expectation.source)
				return Case.first(
					Rule.expect(parsed ~= nil, "the case source must parse"),
					Case.equal(red(expectation.source), expectation.expected, "the syntax tree"),
					Case.equal(red(expectation.source, true), expectation.expected, "the text scan")
				)
			end,
		})
	end
	for _, expectation in SITE_CASES do
		table.insert(built, {
			name = "site: " .. expectation.name,
			run = function()
				return Case.first(
					Case.equal(detect(expectation.source, true).sites, expectation.expected, "the syntax tree"),
					Case.equal(detect(expectation.source, true, true).sites, expectation.expected, "the text scan")
				)
			end,
		})
	end
	table.insert(built, {
		name = "the read-only probe may name the service but not bind",
		run = function()
			return Rule.within({
				["src/ui/gamepad_contention.luau"] = '--!strict\nlocal cas = game:GetService("ContextActionService")\ncas:BindAction("x", f, false)\nreturn cas\n',
			}, function(context)
				return Case.same(scan(context, {}), {
					"src/ui/gamepad_contention.luau:3: BindAction `:BindAction(` (ContextActionService binding is a second input system)",
				})
			end)
		end,
	})
	table.insert(built, {
		name = "Facet sources may read key codes but not create input Instances",
		run = function()
			return Rule.within({
				["src/ui/field.luau"] = '--!strict\nlocal k = input.KeyCode\nlocal b = types.Instance.new("InputContext")\n',
			}, function(context)
				return Case.same(scan(context, {}), {
					'src/ui/field.luau:3: raw input Instance `Instance.new("InputContext")` (Compose owns input Instances through the host constructors)',
				})
			end)
		end,
	})
	table.insert(built, {
		name = "snippet labels and lines point at the Markdown line",
		run = function()
			return Rule.within({
				["docs/guide/keys.md"] = "# Keys\n\n```luau\n\nlocal a = 1\nlocal k = input.KeyCode\n```\n\n```lua\nif input.KeyCode then\n```\n",
			}, function(context)
				return Case.same(scan(context, {}), {
					"docs/guide/keys.md+3:3: key read `input.KeyCode` (a screen inspects raw key codes itself)",
					"docs/guide/keys.md+8:2: key read `input.KeyCode` (a screen inspects raw key codes itself)",
				})
			end)
		end,
	})
	table.insert(built, {
		name = "the fixture baseline is clean",
		run = function()
			return Rule.within(BASELINE, function(context)
				return Case.same(scan(context, BASELINE_PINS), {})
			end)
		end,
	})
	for _, plant in PLANTS do
		table.insert(built, {
			name = "plant: " .. plant.name,
			run = function()
				local files = table.clone(BASELINE)
				files[plant.path] = plant.content
				return Rule.within(files, function(context)
					local findings = scan(context, BASELINE_PINS)
					return Rule.expect(
						Rule.contains(findings, plant.path),
						("the plant stayed green: %s"):format(Rule.describe(findings))
					)
				end)
			end,
		})
	end
	table.insert(built, {
		name = "pins must match their sites",
		run = function()
			return Rule.within(BASELINE, function(context)
				return Case.same(
					scan(context, {
						{ path = "examples/gallery/scenarios/keys.luau", count = 2, reason = "two bindings" },
						{ path = "examples/gone.luau", count = 1, reason = "a removed screen" },
						{ path = "examples/empty.luau", count = 0, reason = " " },
					}),
					{
						"examples/gallery/scenarios/keys.luau: 1 InputBinding declaration site(s); the pin records 2",
						"examples/empty.luau: pinned InputBinding sites are gone; remove the stale pin",
						"examples/gone.luau: pinned InputBinding sites are gone; remove the stale pin",
						"examples/empty.luau: every pin needs a positive count and a reason",
					}
				)
			end)
		end,
	})
	table.insert(built, {
		name = "an unpinned site is reported with its count",
		run = function()
			return Rule.within(BASELINE, function(context)
				return Case.same(scan(context, {}), {
					"examples/gallery/scenarios/keys.luau: 1 unpinned InputBinding declaration site(s); a screen claims keys without an approved pin",
				})
			end)
		end,
	})
	return built
end

local function report(context: Rule.Context, _invocation: Cli.Invocation): number
	local totals: Totals = { snippets = 0, fallbacks = 0, fallbackLabels = {} }
	local findings = scan(context, PINS, totals)
	print(
		("screen-key-bindings: %d teaching snippets; %d parse, %d use the comment-blanking text scan"):format(
			totals.snippets,
			totals.snippets - totals.fallbacks,
			totals.fallbacks
		)
	)
	for _, label in totals.fallbackLabels do
		print("  text scan: " .. label)
	end
	return if #findings == 0 then 0 else 1
end

local rule: Rule.Rule = {
	name = "screen-key-bindings",
	summary = "Screens reach keys only through Facet controls or a pinned native InputContext declaration.",
	check = check,
	cases = cases,
	actions = {
		snippets = {
			summary = "Count the teaching snippets that parse and the ones that use the text scan.",
			run = report,
		},
	},
}

return rule
