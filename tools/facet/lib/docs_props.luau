--!strict
local Files = require("./files")
local Luau = require("./luau")

type Module = {
	source: string,
	parsed: Luau.Parsed,
	types: { [string]: Luau.Node },
	imports: { [string]: string },
	locals: { [string]: string },
}
export type Option = { name: string, type: string, shapes: { string }? }
local Props = {}
local DEFAULTS: { [string]: { [string]: string } } = {
	Stack = {
		width = '"hug"',
		height = '"hug"',
		gap = "0",
		padding = "0",
		wrap = "false",
		maxWidth = "nil",
		align = "native",
		distribute = "native",
	},
	Picker = {
		style = '"automatic"',
		sizing = '"fill"',
		maxHeight = "400",
		enabled = "true",
		multiple = "false",
		isPresented = "cell(false)",
		axis = "by style",
	},
	Screen = { chrome = '"device"', width = '"fill"', height = '"fill"', padding = '"m"' },
	ScrollView = { axis = '"y"', width = '"fill"', height = "by axis and children" },
}
local GUIDANCE: { [string]: { [string]: string } } = {
	Toast = { closeButton = "Requires action; a toast without an action is display-only." },
	Picker = { options = "Type the list as { Facet.PickerOption<V> }. For a typed example, open Picker.card." },
}

function Props.load(root: string): { [string]: { Option } }
	local directory = if Files.isDirectory(Files.join(root, "Packages/Facet/ui")) then "Packages/Facet/ui" else "src/ui"
	local modules: { [string]: Module } = {}
	local function module(name: string): Module
		if modules[name] then
			return modules[name]
		end
		local source = Files.text(Files.join(root, directory, name .. ".luau"))
		local parsed = assert(Luau.parse(source))
		local found: Module = { source = source, parsed = parsed, types = {}, imports = {}, locals = {} }
		modules[name] = found
		for alias, target in string.gmatch(source, 'local ([%w_]+) = require%("%./([%w_]+)"%)') do
			found.imports[alias] = assert(target)
		end
		for alias, target in string.gmatch(source, "local ([%w_]+) = %(nil :: unknown%) :: ([%w_.]+)") do
			found.locals[alias] = assert(target)
		end
		for _, statement in Luau.items(parsed.root, "statements") do
			if Luau.tag(statement) == "typealias" then
				local key, value = Luau.tokenText(statement, "name"), Luau.child(statement, "type")
				if key and value then
					found.types[key] = value
				end
			end
		end
		return found
	end
	local function text(owner: Module, node: Luau.Node): string
		local at = Luau.location(node)
		return (
			string.gsub(
				string.sub(
					owner.source,
					Luau.offset(owner.parsed, at.beginLine, at.beginColumn),
					Luau.offset(owner.parsed, at.endLine, at.endColumn) - 1
				),
				"%s+",
				" "
			)
		)
	end
	local function reference(owner: Module, name: string): (Module, string)
		local alias, key = string.match(name, "^([%w_]+)%.([%w_]+)$")
		if alias and key and owner.imports[alias] then
			return module(owner.imports[alias]), key
		end
		return owner, name
	end
	local shapes: { [string]: string } = {}
	local function expand(owner: Module, raw: string, depth: number): string
		if depth > 3 then
			return raw
		end
		local replacements: { [string]: string } = {}
		for word in string.gmatch(raw, "[%a_][%w_.]*") do
			local target, name = reference(owner, word)
			local node = target.types[name]
			if node and Luau.tag(node) == "table" and string.match(name, "^%u") then
				local value = text(target, node)
				if #value < 200 and not string.find(value, "typeof", 1, true) then
					shapes[name] = name .. " = " .. (string.gsub(expand(target, value, depth + 1), "[%w_]+%.", ""))
				end
			end
			if node and Luau.tag(node) ~= "table" and Luau.tag(node) ~= "function" then
				local value = text(target, node)
				if
					#value < 180
					and value ~= word
					and not string.find(value, "typeof", 1, true)
					and not string.find(value, "<", 1, true)
				then
					local expanded = expand(target, value, depth + 1)
					replacements[word] = if string.find(value, "|", 1, true) then "(" .. expanded .. ")" else expanded
				end
			end
		end
		return (string.gsub(raw, "[%a_][%w_.]*", function(word)
			return replacements[word] or word
		end))
	end
	local function fields(owner: Module, node: Luau.Node, output: { [string]: string }, depth: number)
		if depth > 12 then
			return
		end
		if Luau.tag(node) == "table" then
			for _, entry in Luau.items(node, "entries") do
				local key, value = Luau.tokenText(entry, "key"), Luau.child(entry, "value")
				if key and value and string.match(key, "^[a-z]") then
					local raw = text(owner, value)
					local alias, field = string.match(raw, "^typeof%(([%w_]+)%.([%w_]+)%)$")
					local cast, castField =
						string.match(raw, "^typeof%(%(%(nil :: unknown%) :: ([%w_.]+)[^)]*%)%.([%w_]+)%)$")
					local origin = if alias then owner.locals[alias] else cast
					field = field or castField
					if origin and field then
						local target, name = reference(owner, origin)
						local nested: { [string]: string } = {}
						if target.types[name] then
							fields(target, target.types[name], nested, depth + 1)
						end
						raw = nested[field] or raw
					end
					raw = expand(owner, raw, 0)
					raw = string.gsub(raw, "[%w_]+%.", "")
					output[key] = if output[key] and output[key] ~= raw then output[key] .. " | " .. raw else raw
				end
			end
		elseif Luau.tag(node) == "union" or Luau.tag(node) == "intersection" then
			for _, part in Luau.items(node, "types") do
				fields(owner, part, output, depth + 1)
			end
		else
			local raw = string.match(text(owner, node), "^([%w_.]+)")
			if raw then
				local target, name = reference(owner, raw)
				if target.types[name] then
					fields(target, target.types[name], output, depth + 1)
				end
			end
		end
	end
	local controls = module("control_types")
	local result: { [string]: { Option } } = {}
	local special = { VStack = "Stack", HStack = "Stack", VirtualList = "Collection", VirtualGrid = "Collection" }
	for _, entry in Luau.items(assert(controls.types.Controls), "entries") do
		local name, value = Luau.tokenText(entry, "key"), Luau.child(entry, "value")
		if name == nil or value == nil or not string.match(name, "^[A-Z]") then
			continue
		end
		local target = string.match(text(controls, value), "Constructor<([%w_.]+)")
		local owner: Module? = nil
		local key = special[name] or name
		if target then
			owner, key = reference(controls, target)
		else
			for _, family in { "input", "navigation", "radial", "collection" } do
				local candidate = module(family .. "_props")
				if candidate.types[key .. "Props"] then
					owner, key = candidate, key .. "Props"
					break
				end
				if candidate.types[key .. "Spec"] then
					owner, key = candidate, key .. "Spec"
					break
				end
			end
		end
		if owner and owner.types[key] then
			local collected: { [string]: string } = {}
			table.clear(shapes)
			fields(owner, owner.types[key], collected, 0)
			local options: { Option } = {}
			for field, kind in collected do
				table.insert(options, { name = field, type = kind })
			end
			table.sort(options, function(a: Option, b: Option)
				return a.name < b.name
			end)
			if name == "Picker" then
				local ref = collected.ref
				collected = {}
				if ref then
					collected.ref = ref
				end
				local nav = module("navigation_types")
				for _, kind in { "PickerCommon", "SingleSelection", "MultipleSelection" } do
					fields(nav, assert(nav.types[kind]), collected, 0)
				end
				options = {}
				for field, kind in collected do
					table.insert(options, { name = field, type = kind })
				end
				table.sort(options, function(a: Option, b: Option)
					return a.name < b.name
				end)
			end
			for _, option in options do
				local used: { string } = {}
				for shape, line in shapes do
					if string.find(option.type, "%f[%w_]" .. shape .. "%f[^%w_]") then
						table.insert(used, line)
					end
				end
				if #used > 0 then
					table.sort(used)
					option.shapes = used
				end
			end
			result[name] = options
		end
	end
	result.Stack = result.VStack
	return result
end

Props.ICONS_NODE = "docs/reference/nodes/Icons.names.md"

Props.ICON_USES = table.freeze({
	bag = "Shop or store",
	bolt = "Energy, boost or power",
	calendar = "Date or schedule",
	car = "Vehicle, kart or garage",
	chat = "Chat or messages",
	check = "Same art as `checkmark`",
	checkmark = "Done, confirm or selected",
	["chevron.down"] = "Expand or move down",
	["chevron.first"] = "Go to the first item",
	["chevron.last"] = "Go to the last item",
	["chevron.leading"] = "Back or previous",
	["chevron.trailing"] = "Forward, next or a child page",
	["chevron.up"] = "Collapse or move up",
	["chevron.up.chevron.down"] = "Choice in a pop-up menu",
	clock = "Time of day or duration",
	close = "Close or dismiss",
	coin = "Coins or soft currency",
	crown = "VIP, leader or top rank",
	decrement = "Decrease",
	edit = "Edit or rename",
	flag = "Report, goal or checkpoint",
	gem = "Gems or premium currency",
	gift = "Gift or daily reward",
	heart = "Like, favorite or health",
	increment = "Increase or add",
	lock = "Locked item or requirement",
	menu = "Main menu",
	more = "More actions",
	mute = "Sound off",
	person = "Player, user or profile",
	settings = "Settings",
	speaker = "Sound on",
	star = "Favorite, rating or reward",
	["status.error"] = "Error",
	["status.info"] = "Information",
	["status.success"] = "Success",
	["status.warning"] = "Warning",
	timer = "Countdown or stopwatch",
	trash = "Delete",
	trophy = "Achievement, win or leaderboard",
	["view.grid"] = "Grid layout",
	["view.list"] = "List layout",
	["view.table"] = "Table layout",
	["vote.down"] = "Dislike",
	["vote.up"] = "Like",
	volume = "Same art as `speaker`",
	wrench = "Repair, upgrade or tools",
}) :: { [string]: string }

function Props.iconNames(root: string): { string }
	local directory = if Files.isDirectory(Files.join(root, "Packages/Facet/ui")) then "Packages/Facet/ui" else "src/ui"
	local names: { string } = {}
	local source = Files.text(Files.join(root, directory, "icons.luau"))
	for name in string.gmatch(source, '\n\t%["([%w_.]+)"%] = ') do
		table.insert(names, name)
	end
	for name in string.gmatch(source, "\n\t([%a_][%w_]*) = table%.freeze") do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Props.icons(root: string): string
	local lines = {
		"# Icons.names",
		"",
		"<!-- aliases: Icons | icon names | icon | glyphs -->",
		"",
		"Names for `icon` on Button, Label, Badge, Notice, Chip and the other controls with an icon option.",
		"`NAME.fill` uses NAME when no filled art exists.",
		"A theme package or the `icons` factory option can add a name or replace its art.",
		"An unknown name causes an error, so take each name from this list or register it in your icons map.",
		"Each glyph is a near-white silhouette, and the theme supplies its color.",
		"Use a name from this list before you draw a glyph with Path or Frames.",
		"",
		"| Name | Use for |",
		"| --- | --- |",
	}
	for _, name in Props.iconNames(root) do
		table.insert(lines, ("| `%s` | %s |"):format(name, Props.ICON_USES[name] or ""))
	end
	return table.concat(lines, "\n") .. "\n"
end

function Props.iconProblems(root: string): { string }
	local problems: { string } = {}
	local registered: { [string]: boolean } = {}
	for _, name in Props.iconNames(root) do
		registered[name] = true
		if Props.ICON_USES[name] == nil then
			table.insert(problems, `Icons.names: {name} has no use in tools/facet/lib/docs_props.luau ICON_USES`)
		end
	end
	for name in Props.ICON_USES do
		if not registered[name] then
			table.insert(problems, `Icons.names: {name} in ICON_USES is not a registered icon name`)
		end
	end
	local committed = Files.join(root, Props.ICONS_NODE)
	if not Files.isFile(committed) then
		table.insert(problems, `{Props.ICONS_NODE} is missing; run lute run tools/facet check docs-nodes --write`)
	elseif Files.text(committed) ~= Props.icons(root) then
		table.insert(
			problems,
			`{Props.ICONS_NODE} differs from the icon registry; run lute run tools/facet check docs-nodes --write`
		)
	end
	table.sort(problems)
	return problems
end

function Props.render(name: string, options: { Option }): string
	local lines = {
		"# " .. name .. ".props",
		"Options: name: type = default. omitted uses the control or theme default; required has no default.",
	}
	for _, option in options do
		local defaults: { [string]: string } = DEFAULTS[if name == "VStack" or name == "HStack" then "Stack" else name]
			or {}
		local default = defaults[option.name]
		table.insert(
			lines,
			option.name
				.. ": "
				.. option.type
				.. " = "
				.. (
					if default
						then default
						elseif
							string.sub(option.type, -1) == "?" or string.find(option.type, "nil", 1, true)
						then "omitted"
						else "required"
				)
		)
	end
	local guidance = GUIDANCE[name]
	for _, option in options do
		if guidance and guidance[option.name] then
			table.insert(lines, option.name .. ": " .. guidance[option.name])
		end
	end
	local listed: { [string]: boolean } = {}
	for _, option in options do
		local shapes: { string } = option.shapes or {}
		for _, line in shapes do
			if not listed[line] then
				listed[line] = true
				table.insert(lines, line)
			end
		end
	end
	return table.concat(lines, "\n")
end

return Props
