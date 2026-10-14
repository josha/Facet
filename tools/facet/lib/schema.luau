--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Cst = require("../design/cst")

export type ShapeKind =
	"string"
	| "number"
	| "boolean"
	| "nil"
	| "unknown"
	| "literal"
	| "union"
	| "table"
	| "array"
	| "function"
	| "roblox"
	| "enum"
	| "value"
	| "cell"
	| "readable"
	| "child"
	| "opaque"

export type Shape = {
	kind: ShapeKind,
	literal: (string | boolean)?,
	options: { Shape }?,
	alias: string?,
	token: string?,
	fields: { Field }?,
	indexer: { key: Shape, value: Shape }?,
	element: Shape?,
	inner: Shape?,
	name: string?,
}

export type Field = { name: string, shape: Shape, optional: boolean, origin: string }

export type Control = {
	name: string,
	family: string,
	instance: string,
	props: { Field },
	byName: { [string]: Field },
	children: boolean,
	required: { string },
}

export type Helper = { name: string, family: string }

export type Schema = {
	root: string,
	controls: { [string]: Control },
	order: { string },
	helpers: { Helper },
	tokens: { [string]: { string } },
}

type Alias = { generics: { string }, body: Cst.Type }

type Module = {
	path: string,
	name: string,
	compose: boolean,
	aliases: { [string]: Alias },
	imports: { [string]: string },
}

type Env = { module: Module, subst: { [string]: Shape } }

local Schema = {}

local TOKEN_ALIASES: { [string]: string } = {
	SpaceStep = "space",
	TextRole = "typography",
	ControlSize = "controlSize",
	Status = "status",
}

local BUILTIN: { [string]: ShapeKind } = {
	string = "string",
	number = "number",
	boolean = "boolean",
	["nil"] = "nil",
	unknown = "unknown",
	never = "unknown",
	thread = "opaque",
	buffer = "opaque",
	vector = "opaque",
	["any"] = "unknown",
}

local COMPOSE: { [string]: ShapeKind } = {
	Readable = "readable",
	Formula = "readable",
	Body = "readable",
	Source = "readable",
	Cell = "cell",
	Child = "child",
	Use = "function",
	Dispose = "function",
}

local function shape(kind: ShapeKind): Shape
	return { kind = kind }
end

local NO_SHAPES: { Shape } = {}
local NO_FIELDS: { Field } = {}

local function optionsOf(value: Shape): { Shape }
	return value.options or NO_SHAPES
end

local function fieldsIn(value: Shape): { Field }
	return value.fields or NO_FIELDS
end

local function opaque(name: string): Shape
	return { kind = "opaque", name = name }
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	local joined = table.concat(parts, "/")
	if string.sub(path, 1, 1) == "/" then
		return "/" .. joined
	end
	return joined
end

function Schema.findRoot(start: string?): string?
	local current = string.gsub(start or tostring(process.cwd()), "\\", "/")
	for _ = 1, 32 do
		if fs.exists(current .. "/src/ui/control_types.luau") then
			return current
		end
		local parent = dirname(current)
		if parent == current or parent == "." or parent == "" then
			return nil
		end
		current = parent
	end
	return nil
end

local function requirePath(expr: Cst.Expr): string?
	if expr.tag ~= "call" then
		return nil
	end
	local callee = expr.func
	if callee.tag ~= "global" or callee.name.text ~= "require" then
		return nil
	end
	local argument = expr.arguments[1]
	if argument == nil or argument.tag ~= "string" then
		return nil
	end
	return argument.value.text
end

type LoaderState = {
	root: string,
	modules: { [string]: Module },
	cache: { [string]: Shape },
	active: { [string]: boolean },
	depth: number,
}

local function loadModule(state: LoaderState, path: string): Module
	local existing = state.modules[path]
	if existing then
		return existing
	end
	local name = string.match(path, "([^/]+)%.luau$") or path
	local compose = string.find(path, "vendor/compose", 1, true) ~= nil
	local module: Module = { path = path, name = name, compose = compose, aliases = {}, imports = {} }
	state.modules[path] = module
	if compose then
		return module
	end
	local source = fs.readFileToString(state.root .. "/" .. path)
	local result = Cst.parse(source)
	for _, statement in result.root.statements do
		if statement.tag == "typealias" then
			local generics: { string } = {}
			local list = statement.generics
			if list then
				for index = 1, #list do
					table.insert(generics, list[index].name.text)
				end
			end
			module.aliases[statement.name.text] = { generics = generics, body = statement.type }
		elseif statement.tag == "local" then
			for index = 1, #statement.variables do
				local value = statement.values[index]
				local target = if value then requirePath(value) else nil
				if target then
					local resolved = normalize(dirname(path) .. "/" .. target)
					if string.find(resolved, "vendor/compose", 1, true) then
						module.imports[statement.variables[index].name.text] = resolved
					else
						module.imports[statement.variables[index].name.text] = resolved .. ".luau"
					end
				end
			end
		end
	end
	return module
end

local Resolver = {}

local function flattenUnion(options: { Shape }): { Shape }
	local flat: { Shape } = {}
	for _, option in options do
		if option.kind == "union" and option.alias == nil and option.options then
			for _, nested in option.options do
				table.insert(flat, nested)
			end
		else
			table.insert(flat, option)
		end
	end
	return flat
end

local function fieldsOf(value: Shape): ({ Field }?, boolean)
	if value.kind == "table" then
		local children = false
		if value.indexer and (value.indexer.key.kind == "number" or value.indexer.key.kind == "union") then
			children = true
		end
		return value.fields or {}, children
	end
	if value.kind == "union" and value.options then
		local merged: { [string]: Field } = {}
		local order: { string } = {}
		local present: { [string]: number } = {}
		local children = false
		local alternatives = 0
		for _, option in value.options do
			if option.kind == "nil" then
				continue
			end
			local fields, hasChildren = fieldsOf(option)
			if fields == nil then
				return nil, false
			end
			alternatives += 1
			children = children or hasChildren
			for _, field in fields do
				local existing = merged[field.name]
				if existing == nil then
					merged[field.name] = {
						name = field.name,
						shape = field.shape,
						optional = field.optional,
						origin = field.origin,
					}
					table.insert(order, field.name)
					present[field.name] = 1
				else
					present[field.name] += 1
					existing.optional = existing.optional or field.optional
					if
						existing.shape ~= field.shape
						and Schema.describe(existing.shape) ~= Schema.describe(field.shape)
					then
						existing.shape = { kind = "union", options = flattenUnion({ existing.shape, field.shape }) }
					end
				end
			end
		end
		local result: { Field } = {}
		for _, name in order do
			local field = merged[name]
			if present[name] < alternatives then
				field.optional = true
			end
			table.insert(result, field)
		end
		return result, children
	end
	return nil, false
end

local function intersect(members: { Shape }): Shape
	local merged: { [string]: Field } = {}
	local order: { string } = {}
	local children = false
	for _, member in members do
		local fields, hasChildren = fieldsOf(member)
		if fields == nil then
			return shape("function")
		end
		children = children or hasChildren
		for _, field in fields do
			if merged[field.name] == nil then
				table.insert(order, field.name)
			end
			merged[field.name] = field
		end
	end
	local result: { Field } = {}
	for _, name in order do
		table.insert(result, merged[name])
	end
	local indexer = if children then { key = shape("number"), value = shape("child") } else nil
	return { kind = "table", fields = result, indexer = indexer }
end

local function isValueAlias(module: Module, alias: Alias): boolean
	local body = alias.body
	if body.tag ~= "union" or #alias.generics ~= 1 then
		return false
	end
	local own = false
	local readable = 0
	for index = 1, #body.types do
		local member = body.types[index]
		if member.tag ~= "reference" then
			return false
		end
		local prefix = member.prefix
		if prefix == nil and member.name.text == alias.generics[1] then
			own = true
		elseif
			prefix
			and module.imports[prefix.text]
			and string.find(module.imports[prefix.text], "vendor/compose", 1, true)
		then
			readable += 1
		else
			return false
		end
	end
	return own and readable > 0
end

local function arguments(state: LoaderState, node: Cst.TypeReference, env: Env): { Shape }
	local result: { Shape } = {}
	local parameters = node.parameters
	if parameters then
		for index = 1, #parameters do
			local parameter = parameters[index]
			if parameter.kind == "type" then
				table.insert(result, Resolver.resolve(state, parameter :: Cst.Type, env))
			else
				local pack = parameter :: Cst.TypePack
				if pack.tag == "explicit" and #pack.types == 1 then
					table.insert(result, Resolver.resolve(state, pack.types[1], env))
				else
					table.insert(result, shape("unknown"))
				end
			end
		end
	end
	return result
end

local function expand(state: LoaderState, module: Module, name: string, args: { Shape }): Shape
	if module.compose then
		local kind: ShapeKind? = COMPOSE[name]
		if kind == nil then
			return opaque(name)
		end
		local composed: Shape = shape(kind)
		if kind == "readable" or kind == "cell" then
			composed.inner = args[1] or shape("unknown")
		end
		return composed
	end
	local alias = module.aliases[name]
	if alias == nil then
		return { kind = "roblox", name = name }
	end
	if isValueAlias(module, alias) then
		return { kind = "value", inner = args[1] or shape("unknown") }
	end
	local key = module.path .. "#" .. name
	local cacheable = #alias.generics == 0
	if cacheable and state.cache[key] then
		return state.cache[key]
	end
	if state.active[key] or state.depth > 48 then
		return opaque(name)
	end
	state.active[key] = true
	state.depth += 1
	local subst: { [string]: Shape } = {}
	for index, generic in alias.generics do
		subst[generic] = args[index] or shape("unknown")
	end
	local result: Shape = Resolver.resolve(state, alias.body, { module = module, subst = subst })
	state.depth -= 1
	state.active[key] = nil
	if result.kind == "union" and result.alias == nil then
		local literals = true
		for _, option in optionsOf(result) do
			if option.kind ~= "literal" then
				literals = false
			end
		end
		if literals then
			local named: Shape = {
				kind = "union",
				options = result.options,
				alias = name,
				token = TOKEN_ALIASES[name],
			}
			result = named
		end
	end
	if cacheable then
		state.cache[key] = result
	end
	return result
end

function Resolver.resolve(state: LoaderState, node: Cst.Type, env: Env): Shape
	if node.tag == "reference" then
		local name = node.name.text
		local prefix = node.prefix
		if prefix == nil then
			local substituted = env.subst[name]
			if substituted then
				return substituted
			end
			local builtin: ShapeKind? = BUILTIN[name]
			if builtin then
				return shape(builtin)
			end
			return expand(state, env.module, name, arguments(state, node, env))
		end
		if prefix.text == "Enum" then
			return { kind = "enum", name = name }
		end
		local target = env.module.imports[prefix.text]
		if target == nil then
			return opaque(prefix.text .. "." .. name)
		end
		return expand(state, loadModule(state, target), name, arguments(state, node, env))
	elseif node.tag == "boolean" then
		return { kind = "literal", literal = node.value }
	elseif node.tag == "string" then
		return { kind = "literal", literal = node.value.text }
	elseif node.tag == "typeof" then
		return opaque("typeof")
	elseif node.tag == "group" then
		return Resolver.resolve(state, node.type, env)
	elseif node.tag == "optional" then
		return shape("nil")
	elseif node.tag == "union" then
		local options: { Shape } = {}
		for index = 1, #node.types do
			table.insert(options, Resolver.resolve(state, node.types[index], env))
		end
		return { kind = "union", options = flattenUnion(options) }
	elseif node.tag == "intersection" then
		local members: { Shape } = {}
		for index = 1, #node.types do
			table.insert(members, Resolver.resolve(state, node.types[index], env))
		end
		return intersect(members)
	elseif node.tag == "array" then
		return { kind = "array", element = Resolver.resolve(state, node.type, env) }
	elseif node.tag == "table" then
		local fields: { Field } = {}
		local indexer: { key: Shape, value: Shape }? = nil
		for _, entry in node.entries do
			if entry.kind == "property" then
				local value = Resolver.resolve(state, entry.value, env)
				local optional = value.kind == "nil"
				if value.kind == "union" and value.options then
					for _, option in value.options do
						if option.kind == "nil" then
							optional = true
						end
					end
				end
				table.insert(
					fields,
					{ name = entry.key.text, shape = value, optional = optional, origin = env.module.name }
				)
			else
				indexer =
					{ key = Resolver.resolve(state, entry.key, env), value = Resolver.resolve(state, entry.value, env) }
			end
		end
		return { kind = "table", fields = fields, indexer = indexer }
	end
	return shape("function")
end

local function unwrapTypeof(node: Cst.Type): (string?, string?, string?)
	if node.tag ~= "typeof" then
		return nil, nil, nil
	end
	local expr = node.expression
	if expr.tag ~= "indexname" then
		return nil, nil, nil
	end
	local field = expr.index.text
	local inner = expr.expression
	while inner.tag == "group" do
		inner = inner.expression
	end
	if inner.tag ~= "cast" then
		return nil, nil, nil
	end
	local annotation = inner.annotation
	if annotation.tag ~= "reference" or annotation.prefix == nil then
		return nil, nil, nil
	end
	local prefix = annotation.prefix :: Cst.Token
	return prefix.text, annotation.name.text, field
end

local function returnName(pack: Cst.TypePack): string
	if pack.tag == "explicit" and #pack.types >= 1 then
		local first = pack.types[1]
		if first.tag == "reference" then
			return first.name.text
		end
	end
	return "Instance"
end

local function constructorOf(state: LoaderState, node: Cst.Type, module: Module, depth: number): (Shape?, string?)
	if depth > 8 then
		return nil, nil
	end
	if node.tag == "group" then
		return constructorOf(state, node.type, module, depth + 1)
	elseif node.tag == "reference" then
		local parameters = node.parameters
		if node.name.text == "Constructor" and parameters and #parameters == 2 then
			local props = parameters[1]
			local instance = parameters[2]
			if props.kind ~= "type" then
				return nil, nil
			end
			local name = if instance.kind == "type" and (instance :: Cst.Type).tag == "reference"
				then ((instance :: Cst.Type) :: Cst.TypeReference).name.text
				else "Instance"
			return Resolver.resolve(state, props :: Cst.Type, { module = module, subst = {} }), name
		end
		local target = module
		local prefix = node.prefix
		if prefix then
			local path = module.imports[prefix.text]
			if path == nil then
				return nil, nil
			end
			target = loadModule(state, path)
		end
		local alias = target.aliases[node.name.text]
		if alias == nil or #alias.generics > 0 then
			return nil, nil
		end
		return constructorOf(state, alias.body, target, depth + 1)
	elseif node.tag == "function" then
		local first = node.parameters[1]
		if first == nil then
			return nil, nil
		end
		local parameterType = first.type
		if parameterType.tag == "reference" and parameterType.name.text == "string" then
			return nil, nil
		end
		local subst: { [string]: Shape } = {}
		local generics = node.generics
		if generics then
			for index = 1, #generics do
				subst[generics[index].name.text] = shape("unknown")
			end
		end
		return Resolver.resolve(state, parameterType, { module = module, subst = subst }), returnName(node.returnTypes)
	elseif node.tag == "intersection" then
		local specs: { Shape } = {}
		local instance: string? = nil
		for index = 1, #node.types do
			local spec, name = constructorOf(state, node.types[index], module, depth + 1)
			if spec then
				table.insert(specs, spec)
				instance = instance or name
			end
		end
		if #specs == 0 then
			return nil, nil
		elseif #specs == 1 then
			return specs[1], instance
		end
		return { kind = "union", options = specs }, instance
	end
	return nil, nil
end

local function sortFields(fields: { Field }): { Field }
	local sorted = table.clone(fields)
	table.sort(sorted, function(left: Field, right: Field): boolean
		local leftNative = left.origin == "engine_types"
		local rightNative = right.origin == "engine_types"
		if leftNative ~= rightNative then
			return rightNative
		end
		return left.name < right.name
	end)
	return sorted
end

local cached: { [string]: Schema } = {}

function Schema.load(root: string?): Schema
	local base = root or Schema.findRoot()
	if base == nil then
		error("facet: cannot find src/ui/control_types.luau from the current directory", 2)
	end
	local repository = string.gsub(base :: string, "\\", "/")
	if cached[repository] then
		return cached[repository]
	end
	local state: LoaderState = { root = repository, modules = {}, cache = {}, active = {}, depth = 0 }
	local registry = loadModule(state, "src/ui/control_types.luau")
	local controlsAlias = assert(registry.aliases.Controls, "control_types.luau declares no Controls type")
	assert(controlsAlias.body.tag == "table", "the Controls type is not a table type")
	local controls: { [string]: Control } = {}
	local order: { string } = {}
	local helpers: { Helper } = {}
	for _, entry in controlsAlias.body.entries do
		if entry.kind ~= "property" then
			continue
		end
		local name = entry.key.text
		local moduleName, typeName, fieldName = unwrapTypeof(entry.value)
		local family = "unknown"
		local declared: Cst.Type? = nil
		local owner = registry
		if moduleName and typeName and fieldName then
			local path = registry.imports[moduleName]
			if path then
				owner = loadModule(state, path)
				family = owner.name
				local container = owner.aliases[typeName]
				if container and container.body.tag == "table" then
					for _, member in container.body.entries do
						if member.kind == "property" and member.key.text == fieldName then
							declared = member.value
						end
					end
				end
			end
		end
		local props: Shape? = nil
		local instance: string? = nil
		if declared then
			props, instance = constructorOf(state, declared, owner, 0)
		end
		if props == nil or string.match(name, "^%u") == nil then
			table.insert(helpers, { name = name, family = family })
			continue
		end
		local fields, children = fieldsOf(props)
		local sorted = sortFields(fields or {})
		local byName: { [string]: Field } = {}
		local required: { string } = {}
		for _, field in sorted do
			byName[field.name] = field
			if not field.optional then
				table.insert(required, field.name)
			end
		end
		controls[name] = {
			name = name,
			family = family,
			instance = instance or "Instance",
			props = sorted,
			byName = byName,
			children = children,
			required = required,
		}
		table.insert(order, name)
	end
	table.sort(order)
	table.sort(helpers, function(left: Helper, right: Helper): boolean
		return left.name < right.name
	end)
	local tokens: { [string]: { string } } = {}
	for aliasName, set in TOKEN_ALIASES do
		for _, module in state.modules do
			local alias = module.aliases[aliasName]
			if alias and tokens[set] == nil then
				local resolved = Resolver.resolve(state, alias.body, { module = module, subst = {} })
				local values: { string } = {}
				for _, option in optionsOf(resolved) do
					if option.kind == "literal" and type(option.literal) == "string" then
						table.insert(values, option.literal :: string)
					end
				end
				tokens[set] = values
			end
		end
	end
	local schema: Schema = {
		root = repository,
		controls = controls,
		order = order,
		helpers = helpers,
		tokens = tokens,
	}
	cached[repository] = schema
	return schema
end

function Schema.control(schema: Schema, name: string): Control?
	return schema.controls[name]
end

function Schema.field(control: Control, name: string): Field?
	return control.byName[name]
end

function Schema.options(value: Shape): { Shape }
	local result: { Shape } = {}
	local function visit(current: Shape)
		if current.kind == "union" and current.options then
			for _, option in current.options do
				visit(option)
			end
		elseif current.kind == "value" and current.inner then
			visit(current.inner)
			local readable: Shape = { kind = "readable", inner = current.inner }
			table.insert(result, readable)
		else
			table.insert(result, current)
		end
	end
	visit(value)
	return result
end

function Schema.accepts(value: Shape, kind: ShapeKind): boolean
	for _, option in Schema.options(value) do
		if option.kind == kind or option.kind == "unknown" or option.kind == "opaque" then
			return true
		end
	end
	return false
end

function Schema.literals(value: Shape): { string | boolean }
	local result: { string | boolean } = {}
	for _, option in Schema.options(value) do
		if option.kind == "literal" and option.literal ~= nil then
			table.insert(result, option.literal :: string | boolean)
		end
	end
	return result
end

function Schema.tokenSets(value: Shape): { [string]: { string } }
	local result: { [string]: { string } } = {}
	local function visit(current: Shape)
		if current.kind == "union" and current.options then
			if current.token then
				local values: { string } = {}
				for _, option in current.options do
					if option.kind == "literal" and type(option.literal) == "string" then
						table.insert(values, option.literal :: string)
					end
				end
				result[current.token] = values
			end
			for _, option in current.options do
				visit(option)
			end
		elseif current.kind == "value" and current.inner then
			visit(current.inner)
		end
	end
	visit(value)
	return result
end

function Schema.describe(value: Shape): string
	local kind = value.kind
	if kind == "literal" then
		if type(value.literal) == "string" then
			return string.format("%q", value.literal :: string)
		end
		return tostring(value.literal)
	elseif kind == "union" then
		if value.alias then
			return value.alias
		end
		local parts: { string } = {}
		for _, option in optionsOf(value) do
			table.insert(parts, Schema.describe(option))
		end
		return table.concat(parts, " | ")
	elseif kind == "value" then
		return "Value<" .. Schema.describe(value.inner or shape("unknown")) .. ">"
	elseif kind == "cell" or kind == "readable" then
		local label = if kind == "cell" then "Cell" else "Readable"
		return label .. "<" .. Schema.describe(value.inner or shape("unknown")) .. ">"
	elseif kind == "array" then
		return "{ " .. Schema.describe(value.element or shape("unknown")) .. " }"
	elseif kind == "table" then
		local parts: { string } = {}
		for _, field in fieldsIn(value) do
			table.insert(parts, field.name .. (if field.optional then "?" else ""))
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	elseif kind == "roblox" or kind == "opaque" then
		return value.name or kind
	elseif kind == "enum" then
		return "Enum." .. (value.name or "?")
	end
	return kind
end

function Schema.shapeJson(value: Shape, depth: number?): { [string]: unknown }
	local level = depth or 0
	local result: { [string]: unknown } = { kind = value.kind }
	if value.literal ~= nil then
		result.literal = value.literal
	end
	if value.alias then
		result.alias = value.alias
	end
	if value.token then
		result.token = value.token
	end
	if value.name then
		result.name = value.name
	end
	if level > 12 then
		result.truncated = true
		return result
	end
	if value.options then
		local options: { unknown } = {}
		for _, option in value.options do
			table.insert(options, Schema.shapeJson(option, level + 1))
		end
		result.options = options
	end
	if value.inner then
		result.inner = Schema.shapeJson(value.inner, level + 1)
	end
	if value.element then
		result.element = Schema.shapeJson(value.element, level + 1)
	end
	if value.fields then
		local fields: { unknown } = {}
		for _, field in value.fields do
			table.insert(fields, {
				name = field.name,
				optional = field.optional,
				shape = Schema.shapeJson(field.shape, level + 1),
			})
		end
		result.fields = fields
	end
	return result
end

function Schema.controlJson(control: Control, native: boolean?): { [string]: unknown }
	local props: { unknown } = {}
	for _, field in control.props do
		local isNative = field.origin == "engine_types"
		if native ~= false or not isNative then
			table.insert(props, {
				name = field.name,
				optional = field.optional,
				native = isNative,
				type = Schema.describe(field.shape),
				shape = Schema.shapeJson(field.shape),
			})
		end
	end
	return {
		name = control.name,
		family = control.family,
		instance = control.instance,
		children = control.children,
		required = control.required,
		props = props,
	}
end

function Schema.toJson(schema: Schema, native: boolean?): { [string]: unknown }
	local controls: { unknown } = {}
	for _, name in schema.order do
		table.insert(controls, Schema.controlJson(schema.controls[name], native))
	end
	local helpers: { unknown } = {}
	for _, helper in schema.helpers do
		table.insert(helpers, { name = helper.name, family = helper.family })
	end
	return { controls = controls, helpers = helpers, tokens = schema.tokens }
end

return table.freeze(Schema)
