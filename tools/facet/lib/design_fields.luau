--!strict
local Files = require("./files")
local Luau = require("./luau")

export type Field = { type: string, options: { string }?, datatype: string?, also: { string }? }

local OUTPUT = "src/design/fields.luau"
local HOST_CLASSES = {
	"BillboardGui",
	"CanvasGroup",
	"Frame",
	"ImageButton",
	"ImageLabel",
	"ScrollingFrame",
	"SurfaceGui",
	"TextBox",
	"TextButton",
	"TextLabel",
	"UIAspectRatioConstraint",
	"UICorner",
	"UIFlexItem",
	"UIGradient",
	"UIGridLayout",
	"UIListLayout",
	"UIPadding",
	"UIScale",
	"UISizeConstraint",
	"UIStroke",
	"ViewportFrame",
}
local CONTROLS = "src/ui/control_types.luau"

local SCALARS: { [string]: string } = {
	Boolean = "boolean",
	String = "string",
	Number = "number",
	Color3 = "color",
}

local NODES: { [string]: boolean } = {
	Attachment = true,
	BasePart = true,
	GuiInstance = true,
	Instance = true,
	Model = true,
	PVInstance = true,
}

local DATATYPES: { [string]: boolean } = {
	Font = true,
	UDim2 = true,
	UDim = true,
	Vector2 = true,
	Vector3 = true,
	Rect = true,
	NumberRange = true,
}

local function trim(text: string): string
	return (string.gsub(text, "^%s+", ""):gsub("%s+$", ""))
end

local function unwrap(text: string): string
	local current = trim(text)
	while true do
		local optional = string.match(current, "^(.-)%?$")
		if optional then
			current = trim(optional)
		end
		local inner = string.match(current, "^%((.*)%)$")
		if inner and not string.find(inner, "->", 1, true) then
			current = trim(inner)
		elseif optional == nil then
			return current
		end
	end
end

local function splitUnion(text: string): { string }
	local parts: { string } = {}
	local depth, start = 0, 1
	for index = 1, #text do
		local character = string.sub(text, index, index)
		if character == "(" or character == "<" or character == "{" then
			depth += 1
		elseif character == ")" or character == ">" or character == "}" then
			depth -= 1
		elseif character == "|" and depth == 0 then
			table.insert(parts, trim(string.sub(text, start, index - 1)))
			start = index + 1
		end
	end
	table.insert(parts, trim(string.sub(text, start)))
	return parts
end

type Module = { aliases: { [string]: string }, requires: { [string]: string } }

local modules: { [string]: Module } = {}
local resolving: { [string]: boolean } = {}
local currentFile = ""

local classify: (key: string, text: string) -> Field?

local function classifyOne(key: string, text: string): Field?
	local current = unwrap(text)
	local wrapped = string.match(current, "^[%w_]+%.Input<(.*)>$")
		or string.match(current, "^Input<(.*)>$")
		or string.match(current, "^[%w_]+%.ReadOnlyValue<(.*)>$")
	if wrapped then
		local inner = unwrap(wrapped)
		if (string.match(inner, "^[%w_]+%.([%w_]+)$") or inner) == "GuiObject" then
			return { type = "node" }
		end
		return classify(key, wrapped)
	end
	local valueName = string.match(current, "^[%w_]+%.Value([%w_]+)$") or string.match(current, "^Value([%w_]+)$")
	if valueName then
		local enum = string.match(valueName, "^Enum(%w+)$")
		if enum then
			return { type = "datatype", datatype = "Enum." .. enum }
		elseif SCALARS[valueName] then
			return { type = SCALARS[valueName] }
		elseif DATATYPES[valueName] then
			return { type = "datatype", datatype = valueName }
		end
		return nil
	end
	local bare = string.match(current, "^[%w_]+%.([%w_]+)$") or current
	if NODES[bare] then
		return { type = "node" }
	elseif bare == "Color3" then
		return { type = "color" }
	end
	if current == "boolean" or current == "string" or current == "number" then
		local scalar: string = current
		return { type = scalar }
	end
	local enumName = string.match(current, "^Enum%.(%w+)$")
	if enumName then
		return { type = "datatype", datatype = "Enum." .. enumName }
	end
	if DATATYPES[current] then
		return { type = "datatype", datatype = current }
	end
	local qualifier, qualified = string.match(current, "^([%w_]+)%.([%w_]+)$")
	local here = modules[currentFile]
	local target = if qualifier and here then here.requires[qualifier] elseif qualifier then nil else currentFile
	local aliasName = qualified or string.match(current, "^([%w_]+)$")
	local info = if target then modules[target] else nil
	local aliased = if info and aliasName then info.aliases[aliasName] else nil
	if target and aliasName and aliased then
		local marker = target .. ":" .. aliasName
		if not resolving[marker] then
			resolving[marker] = true
			local saved = currentFile
			currentFile = target
			local field = classify(key, aliased)
			currentFile = saved
			resolving[marker] = nil
			return field
		end
	end
	return nil
end

local classifyKnown: (key: string, text: string) -> Field?

classify = function(key: string, text: string): Field?
	local current = unwrap(text)
	if string.find(current, "->", 1, true) then
		if string.match(key, "^on%u") then
			return { type = "event" }
		elseif string.match(current, "^%(?%(%)%s*%->%s*[%w_%.]*GuiObject%)?$") then
			return { type = "content" }
		end
		return nil
	end
	local known = classifyKnown(key, current)
	if known ~= nil then
		return known
	end
	return if string.match(key, "^%l") then { type = "value" } else nil
end

classifyKnown = function(key: string, current: string): Field?
	local parts = splitUnion(current)
	if #parts == 1 then
		return classifyOne(key, parts[1])
	end
	local options: { string } = {}
	local found: Field? = nil
	for _, part in parts do
		local option = string.match(part, '^"([^"]*)"$')
		if option ~= nil then
			table.insert(options, option)
		else
			local field = classifyOne(key, part)
			if field ~= nil and field.type == "choice" then
				for _, choice in field.options or {} do
					table.insert(options, choice)
				end
			elseif field ~= nil and (found == nil or (found.type ~= "string" and field.type == "string")) then
				found = field
			end
		end
	end
	if #options == 0 or (found ~= nil and found.type == "string") then
		return found
	elseif found ~= nil and found.type == "number" then
		return { type = "choice", options = options, also = { "number" } }
	end
	return { type = "choice", options = options }
end

type Declared = { source: string, node: Luau.Node, parsed: Luau.Parsed, file: string }

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function resolveRequire(root: string, from: string, spec: string): string?
	local directory = dirname(from)
	local isInit = string.match(from, "/init%.luau$") ~= nil
	local base
	if string.sub(spec, 1, 6) == "@self/" then
		base = directory .. "/" .. string.sub(spec, 7)
	elseif isInit then
		base = dirname(directory) .. "/" .. spec
	else
		base = directory .. "/" .. spec
	end
	local path = normalize(base)
	if Files.isFile(Files.join(root, path .. ".luau")) then
		return path .. ".luau"
	elseif Files.isFile(Files.join(root, path, "init.luau")) then
		return path .. "/init.luau"
	end
	return nil
end

local function scan(root: string, path: string, found: { [string]: Declared }, module: string?)
	local source = Files.text(Files.join(root, path))
	local info: Module = { aliases = {}, requires = {} }
	modules[path] = info
	for line in string.gmatch(source, "[^\n]+") do
		local alias, spec = string.match(line, '^local ([%w_]+)[^=]*= require%(?%s*"([^"]+)"')
		if alias and spec then
			local resolved = resolveRequire(root, path, spec)
			if resolved then
				info.requires[alias] = resolved
			end
		end
	end
	if not string.find(source, "type", 1, true) then
		return
	end
	local parsed = Luau.parse(source)
	if parsed == nil then
		return
	end
	for _, statement in Luau.items(parsed.root, "statements") do
		local key, value = Luau.tokenText(statement, "name"), Luau.child(statement, "type")
		if Luau.tag(statement) == "typealias" and key and value then
			if Luau.tag(value) == "table" then
				if module and statement.export ~= nil then
					found[module .. "." .. key] = { source = source, node = value, parsed = parsed, file = path }
				end
			else
				local location = Luau.location(value)
				local first = Luau.offset(parsed, location.beginLine, location.beginColumn)
				local last = Luau.offset(parsed, location.endLine, location.endColumn) - 1
				info.aliases[key] = string.sub(source, first, last)
			end
		end
	end
end

local function exportedTables(root: string): { [string]: Declared }
	local found: { [string]: Declared } = {}
	table.clear(modules)
	for _, entry in Files.list(Files.join(root, "src/ui")) do
		local module = string.match(entry.name, "^(.+)%.luau$")
		if module then
			scan(root, "src/ui/" .. entry.name, found, module)
		end
	end
	for _, relative in Files.walk(Files.join(root, "src/vendor/compose/core")) do
		if string.match(relative, "%.luau$") then
			scan(root, "src/vendor/compose/core/" .. relative, found, nil)
		end
	end
	return found
end

local function constructors(root: string): { [string]: string }
	local text = Files.text(Files.join(root, CONTROLS))
	local modules: { [string]: string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local alias, module = string.match(line, '^local ([%w_]+) = require%("%./([%w_]+)"%)')
		if alias and module then
			modules[alias] = module
		end
	end
	local kinds: { [string]: string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local kind, alias, typeName = string.match(line, "^\t(%u[%w]*): Constructor<([%w_]+)%.([%w_]+)")
		if kind == nil then
			local named, constructor = string.match(line, "^\t(%u[%w]*): ([%w_]+)Constructor,$")
			if named and constructor then
				local first = string.find(text, "\ntype " .. constructor .. "Shapes? =")
					or string.find(text, "\nexport type " .. constructor .. "Shapes? =")
				if first then
					local stop = string.find(text, "\n%a", first + 1) or #text
					local declaration = string.sub(text, first, stop)
					local specAlias, specName = string.match(declaration, "=.-([%w_]+)%.([%w_]+)")
					kind, alias, typeName = named, specAlias, specName
				end
			end
		end
		local module = if alias then modules[alias] else nil
		if kind and module and typeName and kinds[kind] == nil then
			kinds[kind] = module .. "." .. typeName
		end
	end
	return kinds
end

type Derived = { fields: { [string]: Field }, children: boolean }

local function renderSection(lines: { string }, title: string, kinds: { [string]: Derived })
	local names: { string } = {}
	for kind in kinds do
		table.insert(names, kind)
	end
	table.sort(names)
	table.insert(lines, "\t" .. title .. " = {")
	for _, kind in names do
		local entry = kinds[kind]
		table.insert(lines, "\t\t" .. kind .. " = {")
		table.insert(lines, `\t\t\tchildren = {tostring(entry.children)},`)
		table.insert(lines, "\t\t\tfields = {")
		local keys: { string } = {}
		for key in entry.fields do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			local field = entry.fields[key]
			local parts = { `type = "{field.type}"` }
			if field.datatype then
				table.insert(parts, `datatype = "{field.datatype}"`)
			end
			local also = field.also
			if also then
				local quoted: { string } = {}
				for _, kind in also do
					table.insert(quoted, string.format("%q", kind))
				end
				table.insert(parts, "also = { " .. table.concat(quoted, ", ") .. " }")
			end
			local options = field.options
			if options then
				local quoted: { string } = {}
				for _, option in options do
					table.insert(quoted, string.format("%q", option))
				end
				table.insert(parts, "options = { " .. table.concat(quoted, ", ") .. " }")
			end
			table.insert(lines, "\t\t\t\t" .. key .. " = { " .. table.concat(parts, ", ") .. " },")
		end
		table.insert(lines, "\t\t\t},")
		table.insert(lines, "\t\t},")
	end
	table.insert(lines, "\t},")
end

local function render(controls: { [string]: Derived }, host: { [string]: Derived }): string
	local lines = {
		"--!strict",
		"",
		'local Types = require("./types")',
		"",
		"local derived: Types.Derived = {",
	}
	renderSection(lines, "controls", controls)
	renderSection(lines, "host", host)
	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, "return derived")
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

local DesignFields = {}

DesignFields.OUTPUT = OUTPUT
DesignFields.classify = classify

local function derive(declared: Declared): Derived
	currentFile = declared.file
	local fields: { [string]: Field } = {}
	local children = false
	for _, entry in Luau.items(declared.node, "entries") do
		local value = Luau.child(entry, "value")
		if value then
			local location = Luau.location(value)
			local first = Luau.offset(declared.parsed, location.beginLine, location.beginColumn)
			local last = Luau.offset(declared.parsed, location.endLine, location.endColumn) - 1
			local text = string.sub(declared.source, first, last)
			if entry.indexerOpen ~= nil then
				children = children or string.find(text, "Child", 1, true) ~= nil
			else
				local key = Luau.tokenText(entry, "key")
				local field = if key then classify(key, text) else nil
				if key and key ~= "Name" and field then
					fields[key] = field
				end
			end
		end
	end
	return { fields = fields, children = children }
end

function DesignFields.generate(root: string): string
	local tables = exportedTables(root)
	local controls: { [string]: Derived } = {}
	for kind, typeName in constructors(root) do
		local declared = tables[typeName]
		if declared then
			controls[kind] = derive(declared)
		end
	end
	local host: { [string]: Derived } = {}
	for _, className in HOST_CLASSES do
		local declared = tables["engine_types." .. className .. "Props"]
		if declared then
			host[className] = derive(declared)
		end
	end
	return render(controls, host)
end

return DesignFields
