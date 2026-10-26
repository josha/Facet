--!strict
local Files = require("./files")
local Luau = require("./luau")

export type Field = { type: string, options: { string }?, datatype: string? }

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

local DATATYPES: { [string]: boolean } = {
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

local aliases: { [string]: string } = {}
local resolving: { [string]: boolean } = {}

local classify: (key: string, text: string) -> Field?

local function classifyOne(key: string, text: string): Field?
	local current = unwrap(text)
	local wrapped = string.match(current, "^[%w_]+%.Input<(.*)>$") or string.match(current, "^Input<(.*)>$")
	if wrapped then
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
	local aliasName = string.match(current, "^[%w_]+%.([%w_]+)$") or string.match(current, "^([%w_]+)$")
	local aliased = if aliasName then aliases[aliasName] else nil
	if aliasName and aliased and not resolving[aliasName] then
		resolving[aliasName] = true
		local field = classify(key, aliased)
		resolving[aliasName] = nil
		return field
	end
	return nil
end

classify = function(key: string, text: string): Field?
	local current = unwrap(text)
	if string.find(current, "->", 1, true) then
		if string.match(key, "^on%u") then
			return { type = "event" }
		end
		return nil
	end
	local parts = splitUnion(current)
	if #parts == 1 then
		return classifyOne(key, parts[1])
	end
	local options: { string } = {}
	for _, part in parts do
		local option = string.match(part, '^"([^"]*)"$')
		if option == nil then
			options = {}
			break
		end
		table.insert(options, option)
	end
	if #options == #parts then
		return { type = "choice", options = options }
	end
	local found: Field? = nil
	for _, part in parts do
		local field = classifyOne(key, part)
		local textual = field ~= nil and (field.type == "string" or field.type == "choice")
		if field ~= nil and (found == nil or (found.type ~= "string" and textual)) then
			found = if textual then { type = "string" } else field
		end
	end
	return found
end

type Declared = { source: string, node: Luau.Node, parsed: Luau.Parsed }

local function exportedTables(root: string): { [string]: Declared }
	local found: { [string]: Declared } = {}
	table.clear(aliases)
	for _, entry in Files.list(Files.join(root, "src/ui")) do
		local name = entry.name
		local module = string.match(name, "^(.+)%.luau$")
		if module then
			local source = Files.text(Files.join(root, "src/ui", name))
			if string.find(source, "export type", 1, true) then
				local parsed = Luau.parse(source)
				if parsed then
					for _, statement in Luau.items(parsed.root, "statements") do
						if Luau.tag(statement) == "typealias" and statement.export ~= nil then
							local key, value = Luau.tokenText(statement, "name"), Luau.child(statement, "type")
							if key and value and Luau.tag(value) == "table" then
								found[module .. "." .. key] = { source = source, node = value, parsed = parsed }
							elseif key and value then
								local location = Luau.location(value)
								local first = Luau.offset(parsed, location.beginLine, location.beginColumn)
								local last = Luau.offset(parsed, location.endLine, location.endColumn) - 1
								aliases[key] = aliases[key] or string.sub(source, first, last)
							end
						end
					end
				end
			end
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
				if key and field then
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
